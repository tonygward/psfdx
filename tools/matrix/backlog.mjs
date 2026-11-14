import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';

// The prompt scan. Prompts come from the base branch as fetched from the remote, never from a working tree.
const FIELDS = new Set(['id', 'priority', 'effort', 'dependencies', 'conflicts']);
// Ignored on purpose: the board owns status, and Matrix always runs Sonnet.
const IGNORED = new Set(['status', 'execution', 'model']);
export const digest = text => createHash('sha256').update(text).digest('hex');

export function idPattern(prefixes) {
  return new RegExp(`^(?:${prefixes.join('|')})-\\d{2,}$`);
}

function parseList(key, raw, pattern) {
  let value;
  try { value = JSON.parse(raw); } catch { throw new Error(`${key} must be an inline JSON array`); }
  if (!Array.isArray(value) || value.some(x => typeof x !== 'string' || !pattern.test(x))) throw new Error(`Invalid ${key}`);
  return value;
}

// A deliberately small YAML subset: scalars and inline JSON arrays. No nesting, aliases, anchors or tags.
export function parsePrompt(file, text, prefixes = ['PSF', 'AUTO']) {
  const pattern = idPattern(prefixes);
  const normal = text.replace(/^﻿/, '').replace(/\r\n/g, '\n');
  let body = normal;
  const meta = {};
  if (normal.startsWith('---\n')) {
    const end = normal.indexOf('\n---\n', 4);
    if (end < 0) throw new Error('Unterminated metadata');
    for (const line of normal.slice(4, end).split('\n')) {
      if (!line.trim() || line.trim().startsWith('#')) continue;
      if (/^\s/.test(line) || /^-\s/.test(line)) throw new Error(`Nested metadata is not allowed: ${line.trim()}`);
      const match = /^([a-z]+):\s*(.*?)\s*$/.exec(line);
      if (!match) throw new Error(`Invalid metadata line: ${line}`);
      const [, key, raw] = match;
      if (IGNORED.has(key)) continue;
      if (!FIELDS.has(key)) throw new Error(`Unknown metadata field: ${key}`);
      if (Object.hasOwn(meta, key)) throw new Error(`Duplicate metadata field: ${key}`);
      if (raw === '') throw new Error(`Empty metadata field: ${key}`);
      if (/^[&*!|>]/.test(raw)) throw new Error(`Aliases, anchors, tags and block scalars are not allowed: ${key}`);
      if (key === 'dependencies' || key === 'conflicts') { meta[key] = parseList(key, raw, pattern); continue; }
      let value = raw;
      if (/^".*"$/.test(raw)) { try { value = JSON.parse(raw); } catch { throw new Error(`Invalid ${key}`); } }
      else if (/^'.*'$/.test(raw)) value = raw.slice(1, -1);
      if (typeof value !== 'string' || !value || /[[\]{}&*!#\n]/.test(value)) throw new Error(`Invalid ${key}`);
      meta[key] = value;
    }
    body = normal.slice(end + 5);
  }
  const parts = file.split('/');
  const base = path.posix.basename(file);
  const inferred = new RegExp(`^((?:${prefixes.join('|')})-\\d{2,})-`).exec(base)?.[1];
  if (!inferred) throw new Error('File name must start with <PREFIX>-<NN>-');
  const id = meta.id ?? inferred;
  if (!pattern.test(id) || id !== inferred) throw new Error(`id ${id} does not match the file name`);
  const effort = (meta.effort ?? 'unknown').toLowerCase();
  if (meta.effort && !['low', 'medium', 'high'].includes(effort)) throw new Error('Unknown effort');
  const priorityText = meta.priority ?? '99';
  const priority = { high: 1, medium: 50, low: 90 }[priorityText] ?? (/^\d+(?:\.\d+)?$/.test(priorityText) ? Number(priorityText) : NaN);
  if (!Number.isFinite(priority) || priority < 0) throw new Error('Invalid priority');
  return {
    id, file, hash: digest(normal), complete: parts.includes('done'), priority, effort,
    dependencies: meta.dependencies ?? [], conflicts: meta.conflicts ?? [], body,
  };
}

// files: Map of repository path -> text. Only <promptDirectory>/**.md is read.
export function scan(files, { prefixes = ['PSF', 'AUTO'], promptDirectory = 'prompts' } = {}) {
  const prompts = [], errors = [], warnings = [], seen = new Set();
  for (const [file, text] of files) {
    if (!file.startsWith(`${promptDirectory}/`) || !file.endsWith('.md')) continue;
    if (path.posix.basename(file) === 'README.md') continue;
    try {
      const prompt = parsePrompt(file, text, prefixes);
      if (seen.has(prompt.id)) throw new Error(`Duplicate ID ${prompt.id}`);
      seen.add(prompt.id); prompts.push(prompt);
    } catch (error) {
      // A broken archived prompt is only a warning. A broken active prompt blocks all selection.
      (file.includes('/done/') ? warnings : errors).push({ file, reason: error.message });
    }
  }
  return { prompts, errors, warnings };
}

function cyclic(id, byId, trail = []) {
  if (trail.includes(id)) return true;
  const prompt = byId.get(id);
  return !!prompt && prompt.dependencies.some(dep => cyclic(dep, byId, [...trail, id]));
}

const compareIds = (a, b) => a.localeCompare(b, 'en', { numeric: true });
const ACTIVE_STATES = ['claimed', 'interrupted', 'awaiting-review'];

// Returns { selected, decisions, blocked }. Scan errors and duplicate active IDs block everything.
export function select(scanResult, tasks = {}, limit = 1) {
  const { prompts, errors } = scanResult;
  if (errors.length > 0) {
    return { selected: [], decisions: [], blocked: `Prompt scan has ${errors.length} error(s): ${errors.map(e => `${e.file}: ${e.reason}`).join('; ')}` };
  }
  const byId = new Map(prompts.map(p => [p.id, p]));
  const complete = new Set(prompts.filter(p => p.complete).map(p => p.id));
  const activeIds = Object.values(tasks).filter(t => ACTIVE_STATES.includes(t.state)).map(t => t.id);
  const selected = [], decisions = [];
  for (const p of prompts.filter(p => !p.complete).sort((a, b) => a.priority - b.priority || compareIds(a.id, b.id))) {
    const task = tasks[p.id];
    let reason = null;
    if (task && ['claimed', 'interrupted', 'awaiting-review', 'complete', 'dead-letter'].includes(task.state)) reason = `durable state: ${task.state}`;
    if (!reason && p.dependencies.includes(p.id)) reason = 'self dependency';
    if (!reason && cyclic(p.id, byId)) reason = 'circular dependency';
    if (!reason) {
      const missing = p.dependencies.filter(dep => !byId.has(dep));
      if (missing.length) reason = `dependency has no prompt: ${missing.join(', ')}`;
    }
    if (!reason && p.dependencies.some(dep => !complete.has(dep))) reason = 'dependency not merged (its prompt is not in done/)';
    // Conflicts are symmetric, against running work and against what is already selected.
    const others = [...activeIds, ...selected.map(s => s.id)];
    if (!reason && others.some(id => p.conflicts.includes(id) || byId.get(id)?.conflicts.includes(p.id))) reason = 'conflicts with other work';
    if (!reason && selected.length >= limit) reason = 'batch capacity';
    decisions.push({ id: p.id, file: p.file, priority: p.priority, effort: p.effort, dependencies: p.dependencies, reason: reason ?? 'candidate' });
    if (!reason) selected.push(p);
  }
  return { selected, decisions, blocked: null };
}

// Reads prompts from the fetched base branch with git ls-tree and git show. `run` is injectable for tests.
export function readPromptFiles({ cwd, ref = 'refs/remotes/origin/main', promptDirectory = 'prompts', git = 'git', run = spawnSync }) {
  const exec = args => {
    const result = run(git, args, { cwd, encoding: 'utf8', shell: false, windowsHide: true, maxBuffer: 16 * 1024 * 1024 });
    if (result.error || result.status !== 0) throw new Error('Git could not read the base branch');
    return result.stdout;
  };
  const revision = exec(['rev-parse', '--verify', `${ref}^{commit}`]).trim();
  if (!/^[a-f0-9]{40,64}$/.test(revision)) throw new Error('Base branch revision is not a commit');
  const names = exec(['ls-tree', '-r', '--name-only', revision, '--', promptDirectory]).split('\n').filter(n => n.endsWith('.md'));
  const files = new Map();
  for (const name of names) files.set(name, exec(['show', `${revision}:${name}`]));
  return { revision, files };
}
