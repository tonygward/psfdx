// Genuine pickup: persist the claim first, then tell the tracking issue. A Doing card alone is not pickup evidence.
// The claim is durable before any comment is posted, so a crash or a failed comment can never lead to a second job
// for the same task.
import path from 'node:path';
import { atomic, locked, readState, claim, record } from './state.mjs';
import { londonDay, TIME_ZONE } from './policy.mjs';

import { commentMarker } from './github-io.mjs';

export const marker = (taskId, job) => commentMarker('pickup', taskId, job);
export const UNKNOWN_REASON = 'Unknown (provenance unavailable)';

/**
 * Why a card was picked up, captured at selection, before Matrix moves the card to Doing. Never inferred afterwards:
 * a Doing card does not prove a person moved it, and the status after the claim is always Doing.
 * Returns the record that is persisted with the claim and rendered in the starting comment.
 */
export function pickupProvenance({ status, selectedAt, resumedFrom = null } = {}) {
  const at = Date.parse(selectedAt);
  if (!['Todo', 'Doing'].includes(status) || !Number.isFinite(at)) return { reason: UNKNOWN_REASON, preClaimStatus: null, selectedAt: null };
  const base = { preClaimStatus: status, selectedAt: new Date(at).toISOString() };
  if (resumedFrom) return { ...base, reason: `Resumed (${status})`, initiator: `Unknown (the card was moved back to ${status})`, resumedFrom };
  if (status === 'Todo') return { ...base, reason: 'Scheduled (Todo)', scheduleDate: londonDay(new Date(at)), initiator: 'Scheduled overnight queue' };
  return { ...base, reason: 'Run now (Doing)', initiator: 'Unknown (board status requested immediate processing)' };
}

const londonTime = iso => new Intl.DateTimeFormat('en-GB', { timeZone: TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
  .formatToParts(new Date(iso)).reduce((all, part) => ({ ...all, [part.type]: part.value }), {});

export function provenanceLines(provenance) {
  if (!provenance || !provenance.reason || provenance.reason === UNKNOWN_REASON) return [`- Pickup reason: ${UNKNOWN_REASON}`];
  const t = londonTime(provenance.selectedAt), from = provenance.resumedFrom;
  return [`- Pickup reason: ${provenance.reason}`, `- Before claim: ${provenance.preClaimStatus}`,
    `- Selected at: ${t.year}-${t.month}-${t.day} ${t.hour}:${t.minute} Europe/London`,
    ...(provenance.scheduleDate ? [`- London schedule date: ${provenance.scheduleDate}`] : []),
    `- Initiator: ${provenance.initiator}`,
    ...(from ? [`- Resumed from: job \`${from.job ?? 'unknown'}\`${from.reason ? ` (${from.reason})` : ''}${from.pr ? `, ${from.pr}` : ''}${from.branch ? `, branch \`${from.branch}\`` : ''}`] : [])];
}

export function pickupComment({ taskId, job, promptHash, revision, repository, limits = null, provenance = null }) {
  return [marker(taskId, job),
    `Matrix has picked up **${taskId}**.`, '',
    ...provenanceLines(provenance),
    `- Matrix job: \`${job}\``,
    `- Prompt revision: \`${revision.slice(0, 12)}\` (prompt hash \`${promptHash.slice(0, 12)}\`)`,
    `- Repository: \`${repository}\``,
    ...(limits ? [`- Limits: ${limits}`] : []), '',
    'Progress, the pull request, CI results and any blockers will be posted on this issue. Nothing is merged until the required checks pass.'].join('\n');
}

/**
 * Claim the selected card. Returns { claimed, ... }. Never throws for a refused claim.
 * io: { comment(repository, issue, body), hasComment(repository, issue, marker), moveToDoing(itemId) }
 */
export async function pickUp(stateDirectory, selected, { job, revision, io, limits = null, now = () => new Date().toISOString() }) {
  return locked(stateDirectory, async () => {
    const state = readState(stateDirectory, { restart: false });
    const active = Object.values(state.tasks).find(task => task.state === 'claimed');
    if (active) return { claimed: false, reason: `Job ${active.job ?? active.id} is already active` };
    let ok;
    try { ok = claim(state, { id: selected.taskId, hash: selected.promptHash }, revision, 2, now()); }
    catch (error) { return { claimed: false, reason: error.message }; }
    if (!ok) { atomic(path.join(stateDirectory, 'state.json'), state); return { claimed: false, reason: 'Attempts exhausted; moved to dead letter' }; }
    Object.assign(state.tasks[selected.taskId], { job, issue: selected.issue, repository: selected.repository,
      itemId: selected.itemId, claimedAt: now(), pickupCommentAt: null,
      pickup: selected.provenance ?? pickupProvenance({ status: selected.status, selectedAt: now(), resumedFrom: state.tasks[selected.taskId].resumedFrom ?? null }) });
    record(state, { event: 'claimed', task: selected.taskId, job, issue: selected.issue });
    atomic(path.join(stateDirectory, 'state.json'), state); // durable before the comment
    return { claimed: true, comment: await postPickupComment(stateDirectory, state, selected.taskId, { revision, io, limits, now }) };
  });
}

// Idempotent: a marker check prevents duplicate comments after a retry or restart.
export async function postPickupComment(stateDirectory, state, taskId, { revision, io, limits = null, now = () => new Date().toISOString() }) {
  const task = state.tasks[taskId];
  if (!task || task.state !== 'claimed' || !task.job) return { posted: false, reason: 'No active claim' };
  if (task.pickupCommentAt) return { posted: false, reason: 'Already commented' };
  try {
    // The claim is durable. Move the card to Doing, then post the starting comment; both are safe to retry.
    if (!task.movedToDoingAt && io.moveToDoing) { await io.moveToDoing(task.itemId); task.movedToDoingAt = now(); }
    if (!(await io.hasComment(task.repository, task.issue, marker(taskId, task.job)))) {
      await io.comment(task.repository, task.issue, pickupComment({ taskId, job: task.job, promptHash: task.hash, revision, repository: task.repository, limits, provenance: task.pickup }));
      if (!task.pickup || task.pickup.reason === UNKNOWN_REASON) record(state, { event: 'pickup-provenance-unknown', task: taskId, job: task.job });
    }
    task.pickupCommentAt = now();
    record(state, { event: 'pickup-comment', task: taskId, job: task.job });
    atomic(path.join(stateDirectory, 'state.json'), state);
    return { posted: true };
  } catch (error) {
    // Keep the claim. The comment is retried by recoverPickupComments; never release or re-pick.
    record(state, { event: 'pickup-comment-failed', task: taskId, job: task.job, reason: String(error.message).slice(0, 200) });
    atomic(path.join(stateDirectory, 'state.json'), state);
    return { posted: false, reason: 'Comment failed; claim kept for retry' };
  }
}

export async function recoverPickupComments(stateDirectory, { revision, io, limits = null, now }) {
  return locked(stateDirectory, async () => {
    const state = readState(stateDirectory, { restart: false }), results = {};
    for (const task of Object.values(state.tasks)) {
      if (task.state === 'claimed' && task.job && !task.pickupCommentAt) results[task.id] = await postPickupComment(stateDirectory, state, task.id, { revision, io, limits, now });
    }
    return results;
  });
}
