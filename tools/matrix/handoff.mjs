// Hand-off between the board tick and the worker. The tick decides what to build and writes this file; the worker,
// holding its own state lock, reads it, re-checks it against its own fresh snapshot of main, claims through its
// normal path and comments on the issue. A stale or invalid hand-off means the worker idles: there is no fallback.
import fs from 'node:fs';
import path from 'node:path';
import { atomic } from './state.mjs';
import { pickupProvenance } from './pickup.mjs';

export const HANDOFF_FILE = 'board-handoff.json';
export const HANDOFF_MAX_AGE_MS = 15 * 60000;

export function writeHandoff(directory, { selected, job, revision, now = Date.now(), resumedFrom = null }) {
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  atomic(path.join(directory, HANDOFF_FILE), {
    schema: 1, createdAt: new Date(now).toISOString(), job, revision, taskId: selected.taskId, promptHash: selected.promptHash, status: selected.status,
    provenance: pickupProvenance({ status: selected.status, selectedAt: new Date(now).toISOString(), resumedFrom }),
    ...(selected.generated ? { generated: selected.generated } : {}),
    issue: selected.issue, itemId: selected.itemId, repository: selected.repository,
  });
}

export function clearHandoff(directory) { fs.rmSync(path.join(directory, HANDOFF_FILE), { force: true }); }

export function readHandoff(directory, { now = Date.now(), maxAgeMs = HANDOFF_MAX_AGE_MS } = {}) {
  let data;
  try { data = JSON.parse(fs.readFileSync(path.join(directory, HANDOFF_FILE), 'utf8')); } catch { return null; }
  const age = now - Date.parse(data?.createdAt);
  const text = value => typeof value === 'string' && value.length > 0;
  if (data?.schema !== 1 || !Number.isFinite(age) || age < 0 || age > maxAgeMs) return null;
  if (data.generated !== undefined && !(typeof data.generated?.file === 'string' && typeof data.generated?.text === 'string' && data.generated.text.length <= 200000)) return null;
  if (![data.job, data.revision, data.taskId, data.promptHash, data.itemId, data.repository].every(text) || !Number.isInteger(data.issue)) return null;
  return data;
}

// The prompt must still exist, be unchanged since the tick chose it, and still be unclaimed.
export function adoptHandoff(state, prompts, handoff) {
  const prompt = prompts.find(p => p.id === handoff.taskId);
  if (!prompt) return { reason: 'Prompt no longer exists on main' };
  if (prompt.hash !== handoff.promptHash) return { reason: 'Prompt changed since the board selection' };
  const task = state.tasks[handoff.taskId];
  if (!task || task.state !== 'pending') return { reason: `Task is not pending (${task?.state ?? 'unknown'})` };
  return { prompt };
}

// Board fields the delivery lifecycle and the pickup comment need.
export function boardFields(handoff, now = new Date().toISOString()) {
  return { job: handoff.job, issue: handoff.issue, itemId: handoff.itemId, repository: handoff.repository, claimedAt: now, pickupCommentAt: null, pickup: handoff.provenance ?? pickupProvenance({}) };
}
