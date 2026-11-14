// Blocked outcomes and explicit resume.
// A task that stops (interrupted, dead-lettered, limit reached) gets one checkpoint comment on its issue and its card moves to
// Blocked. It is never re-queued by a poll. Moving the card back to Todo or Doing is the explicit resume. Both steps are
// idempotent and safe to retry: the comment is deduplicated by a marker and the saved state records what already happened.
import path from 'node:path';
import { atomic, locked, readState, record } from './state.mjs';

export const blockedMarker = (id, job) => `<!-- matrix-blocked:${id}:${job ?? 'unknown'} -->`;
export const heldMarker = (id, job) => `<!-- matrix-resume-held:${id}:${job ?? 'unknown'} -->`;
const STOPPED = ['interrupted', 'dead-letter'];
const stopped = task => STOPPED.includes(task.state) && task.issue;
// Committed work has a branch and probably a pull request. Starting again would duplicate it, so it is held for the owner.
const hasWork = task => Boolean(task.commit || task.pr);

export function blockedComment(task) {
  const lines = [blockedMarker(task.id, task.job), `**${task.id} is Blocked.**`, '',
    `- Reason: ${task.reason ?? 'The run stopped'}`,
    `- Matrix job: \`${task.job ?? 'unknown'}\`; attempts used: ${task.attempts ?? 0}`,
    ...(task.branch ? [`- Branch: \`${task.branch}\`${task.worktree ? ' (worktree retained)' : ''}`] : []),
    ...(task.pr ? [`- Pull request: ${task.pr}`] : []),
    ...(task.runStartedAt ? [`- Run started: ${task.runStartedAt}`] : []), '',
    hasWork(task)
      ? '**To resume:** move this card back to Todo or Doing. Matrix carries on from the saved branch and pull request with a fresh budget, and does not start the work again from scratch.'
      : '**To resume:** move this card back to Todo or Doing. Matrix starts the task again from a clean worktree; nothing was committed.',
    'The issue stays open. Matrix will not retry on its own.'];
  return lines.join('\n');
}

/**
 * Comment and move the card for every stopped task that has not been reported yet.
 * io: { comment(repo, issue, body), hasComment(repo, issue, marker), moveToBlocked(itemId) }
 * Returns the item ids moved, so the caller can refresh its view of the board.
 */
export async function blockStopped(stateDirectory, io, { now = () => new Date().toISOString() } = {}) {
  return locked(stateDirectory, async () => {
    const state = readState(stateDirectory, { restart: false }), moved = [];
    for (const task of Object.values(state.tasks)) {
      if (!stopped(task) || task.blockedCommentAt || state.deliveries?.[task.id]) continue;
      try {
        if (!task.movedBlockedAt && task.itemId && io.moveToBlocked) { await io.moveToBlocked(task.itemId); task.movedBlockedAt = now(); moved.push(task.itemId); }
        const slug = task.repository;
        if (!(await io.hasComment(slug, task.issue, blockedMarker(task.id, task.job)))) await io.comment(slug, task.issue, blockedComment(task));
        task.blockedCommentAt = now();
        record(state, { event: 'blocked', task: task.id, job: task.job });
      } catch (error) {
        record(state, { event: 'blocked-failed', task: task.id, job: task.job, reason: String(error.message).slice(0, 200) });
      }
      atomic(path.join(stateDirectory, 'state.json'), state);
    }
    return { moved };
  });
}

/**
 * A blocked task whose card has been moved back to Todo or Doing is an explicit resume, with a fresh budget.
 * Without committed work it starts again from a clean worktree. With committed work it carries on from the saved branch and
 * pull request (resumeWork), so nothing is coded twice. Two cases are never resumed: work whose pull request has merged
 * (delivery owns it) and work whose pull request was closed without merging (held: one comment, card back to Blocked).
 * pulls: [{ headRefName, state }] from the board tick.
 */
export async function resumeBlocked(stateDirectory, board, io, { now = () => new Date().toISOString(), pulls = [] } = {}) {
  return locked(stateDirectory, async () => {
    const state = readState(stateDirectory, { restart: false }), resumed = [], held = [];
    for (const task of Object.values(state.tasks)) {
      if (!stopped(task) || !task.blockedCommentAt) continue;
      const card = board.cards.find(c => c.taskId === task.id && c.issue === task.issue);
      if (!card || !['Todo', 'Doing'].includes(card.status)) continue;
      const mine = task.branch ? pulls.filter(p => p.headRefName === task.branch) : [];
      if (mine.some(p => p.state === 'MERGED')) continue; // merged: the delivery lifecycle takes over, never recode
      const closedOnly = mine.length > 0 && !mine.some(p => p.state === 'OPEN');
      if (!hasWork(task) || !closedOnly) {
        // Remember where the work stopped, so the next starting comment can say this is a resume and from what.
        task.resumedFrom = { job: task.job, reason: task.reason, branch: task.branch, pr: task.pr, checkpoint: task.phase };
        const keep = hasWork(task) ? ['commit', 'pr'] : [];
        for (const key of ['blockedCommentAt', 'movedBlockedAt', 'pickupCommentAt', 'movedToDoingAt', 'claimedAt', 'runStartedAt', 'job', 'reason', 'phase', 'commit', 'pr', 'pickup']) if (!keep.includes(key)) delete task[key];
        Object.assign(task, { state: 'pending', attempts: 0, resumedAt: now() });
        if (hasWork(task)) task.resumeWork = true;
        record(state, { event: 'resumed', task: task.id, withWork: hasWork(task) });
        resumed.push(task.id);
      } else {
        try {
          if (io.moveToBlocked && task.itemId) await io.moveToBlocked(task.itemId);
          const slug = task.repository;
          if (!(await io.hasComment(slug, task.issue, heldMarker(task.id, task.job)))) {
            await io.comment(slug, task.issue, `${heldMarker(task.id, task.job)}\n**${task.id} was not restarted.** Its pull request${task.pr ? ` (${task.pr})` : ''} was closed without merging, so continuing on \`${task.branch ?? 'its branch'}\` would duplicate or contradict that decision. An owner needs to decide what happens to that work; the card is back in Blocked.`);
          }
          record(state, { event: 'resume-held', task: task.id, job: task.job });
          held.push(task.id);
        } catch (error) { record(state, { event: 'resume-held-failed', task: task.id, reason: String(error.message).slice(0, 200) }); }
      }
      atomic(path.join(stateDirectory, 'state.json'), state);
    }
    return { resumed, held };
  });
}
