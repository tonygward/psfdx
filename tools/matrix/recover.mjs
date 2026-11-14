// In-flight recovery. A worker restart marks a claimed task interrupted, but a task whose branch is pushed and whose
// pull request is open is not lost: the hosted Build and the merge gate carry on without the worker. This looks the work up
// again from GitHub, using the branch and the exact head commit, and either hands it back to the gate (awaiting-review) or
// leaves it interrupted so it is reported and parked in Blocked. It never starts the agent and never pushes.
import path from 'node:path';
import { postCiPassedComment } from './ci-comment.mjs';
import { atomic, locked, readState, record } from './state.mjs';

export const CI_TIMEOUT_MS = 5400 * 1000;
const RESTARTED = /^Worker restarted/;

export const recoverable = task => Boolean(task.branch && task.commit && task.issue &&
  ((task.state === 'interrupted' && RESTARTED.test(task.reason ?? '')) || (task.state === 'awaiting-review' && task.recoveredAt)));

/** Reduce a pull request's check roll-up to success | pending | failure. No checks yet counts as pending. */
export function checkState(rollup) {
  const rows = Array.isArray(rollup) ? rollup : [];
  if (!rows.length) return 'pending';
  const done = row => (row.status ?? 'COMPLETED') === 'COMPLETED';
  if (rows.some(row => done(row) && ['FAILURE', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED', 'STARTUP_FAILURE'].includes(row.conclusion ?? row.state))) return 'failure';
  if (rows.some(row => !done(row))) return 'pending';
  return 'success';
}

/**
 * io.prChecks(repository, number) -> { headSha, checks }
 * Returns { recovered: [ids], failed: [ids] }.
 */
export async function recoverInFlight(stateDirectory, pulls, io, { now = () => Date.now() } = {}) {
  return locked(stateDirectory, async () => {
    const state = readState(stateDirectory, { restart: false }), recovered = [], failed = [];
    for (const task of Object.values(state.tasks)) {
      if (!recoverable(task) || state.deliveries?.[task.id]) continue;
      const pull = pulls.find(p => p.headRefName === task.branch && p.state === 'OPEN');
      if (!pull) continue; // merged work goes to delivery; closed or missing work stays interrupted and is reported
      const hold = reason => { Object.assign(task, { state: 'interrupted', reason }); delete task.recoveredAt; record(state, { event: 'recovery-held', task: task.id, reason }); failed.push(task.id); };
      try {
        const { headSha, checks } = await io.prChecks(pull.repository, pull.number);
        if (headSha !== task.commit) hold(`The pull request head (${String(headSha).slice(0, 7)}) is not the commit Matrix pushed (${task.commit.slice(0, 7)}); owner review needed`);
        else {
          const verdict = checkState(checks);
          if (verdict === 'failure') hold('The hosted Build failed on the pushed commit after a restart; the repair needs an explicit resume');
          else if (task.recoveredAt && verdict === 'pending' && now() - Date.parse(task.recoveredAt) > CI_TIMEOUT_MS) hold('The hosted Build did not finish within 90 minutes of recovery');
          else if (verdict === 'success' || !task.recoveredAt) {
            if (task.state !== 'awaiting-review') { Object.assign(task, { state: 'awaiting-review', pr: pull.url ?? `https://github.com/${pull.repository}/pull/${pull.number}`, recoveredAt: new Date(now()).toISOString() }); delete task.reason; record(state, { event: 'recovered', task: task.id, pr: pull.number, ci: verdict }); recovered.push(task.id); }
          }
          // The build passed for the exact pushed commit; the one-time CI note goes on the issue (idempotent, never blocks).
          if (verdict === 'success' && task.state === 'awaiting-review' && io.comment) await postCiPassedComment(task, { sha: headSha, pr: task.pr ?? pull.url, runUrl: null }, io, () => new Date(now()).toISOString());
        }
      } catch (error) { record(state, { event: 'recovery-failed', task: task.id, reason: String(error.message).slice(0, 200) }); }
    }
    atomic(path.join(stateDirectory, 'state.json'), state);
    return { recovered, failed };
  });
}
