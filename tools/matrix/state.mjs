import fs from 'node:fs';
import path from 'node:path';

export const TASK_STATES = ['pending', 'claimed', 'interrupted', 'awaiting-review', 'withdrawn', 'dead-letter', 'complete'];
const SECRET_KEY = /token|secret|password|authorization|credential|stderr|stdout|raw/i;

// Write a temporary file, flush it, then rename over the target, so a crash never leaves half a file.
export function atomic(file, value) {
  const tmp = `${file}.${process.pid}.tmp`;
  const fd = fs.openSync(tmp, 'w', 0o600);
  try { fs.writeFileSync(fd, JSON.stringify(value, null, 2) + '\n'); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  fs.renameSync(tmp, file);
}

// Exclusive lock file. A stale lock after a crash needs a person: never steal it by age or process ID.
export function locked(directory, fn) {
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  const file = path.join(directory, 'worker.lock');
  let fd;
  try { fd = fs.openSync(file, 'wx', 0o600); }
  catch (error) {
    if (error.code === 'EEXIST') throw new Error('Matrix state is locked. If no worker is running, a person must remove worker.lock');
    throw error;
  }
  const release = () => { fs.closeSync(fd); fs.unlinkSync(file); };
  let result;
  try {
    fs.writeFileSync(fd, JSON.stringify({ pid: process.pid, started: new Date().toISOString() }));
    result = fn();
  } catch (error) { release(); throw error; }
  if (result && typeof result.then === 'function') return result.finally(release);
  release();
  return result;
}

export const emptyState = () => ({ schema: 1, tasks: {}, events: [], history: [] });

// Never replaces a corrupt or unreadable file with an empty one: an empty state could erase who owns what.
// restart: true (the default) is for a worker starting up. A running board tick passes restart: false so that it never
// marks a live claim as interrupted.
export function readState(directory, { restart = true } = {}) {
  const file = path.join(directory, 'state.json');
  if (!fs.existsSync(file)) return emptyState();
  let state;
  try { state = JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch { throw new Error('Matrix state is unreadable; restore a verified backup (it was not replaced)'); }
  if (!state || state.schema !== 1 || !state.tasks || typeof state.tasks !== 'object' || !Array.isArray(state.events) || !Array.isArray(state.history)) {
    throw new Error('Matrix state is invalid; restore a verified backup (it was not replaced)');
  }
  // A claimed task on load means a restart happened mid-run.
  if (restart) for (const task of Object.values(state.tasks)) {
    if (task.state === 'claimed') { task.state = 'interrupted'; task.reason = 'Worker restarted; inspect retained work before retry'; }
  }
  return state;
}

export function writeState(directory, state) {
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  atomic(path.join(directory, 'state.json'), state);
}

// Append-only structured log. Secrets, tokens, raw provider output and stderr are never written.
export function logEvent(directory, event) {
  const logs = path.join(directory, 'logs');
  fs.mkdirSync(logs, { recursive: true, mode: 0o700 });
  const clean = Object.fromEntries(Object.entries(event).filter(([key]) => !SECRET_KEY.test(key)));
  fs.appendFileSync(path.join(logs, 'worker.jsonl'), JSON.stringify({ time: new Date().toISOString(), ...clean }) + '\n', { mode: 0o600 });
}

export function reconcile(state, prompts, revision, now = new Date().toISOString()) {
  const ids = new Set(prompts.map(p => p.id));
  for (const task of Object.values(state.tasks)) {
    if (!ids.has(task.id) && task.state === 'pending') { task.state = 'withdrawn'; task.reason = 'Missing from current main'; }
  }
  for (const p of prompts) {
    let task = state.tasks[p.id];
    if (!task) task = state.tasks[p.id] = { id: p.id, state: 'pending', attempts: 0, created: now };
    if (p.complete) task.state = 'complete';
    else if (task.state === 'withdrawn') task.state = 'pending';
    task.file = p.file; task.hash = p.hash; task.revision = revision; task.updated = now;
  }
}

export function claim(state, prompt, revision, maximum = 2, now = new Date().toISOString()) {
  const task = state.tasks[prompt.id];
  if (!task || task.state !== 'pending' || task.hash !== prompt.hash || task.revision !== revision) throw new Error('Claim rejected');
  if (task.attempts >= maximum) { task.state = 'dead-letter'; return false; }
  task.state = 'claimed'; task.attempts++;
  if (!task.runStartedAt) task.runStartedAt = now;
  return true;
}

export function finish(state, id, result, details = {}) {
  const task = state.tasks[id];
  if (!task || task.state !== 'claimed' || !['awaiting-review', 'interrupted', 'dead-letter'].includes(result)) throw new Error('Invalid finish transition');
  Object.assign(task, details, { state: result });
  // Only reconciliation against the merged prompts/done folder may mark a task complete.
}

export function record(state, event) {
  state.history.push({ time: new Date().toISOString(), ...event });
  state.history = state.history.slice(-1000);
}
