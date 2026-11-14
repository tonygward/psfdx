// When the hosted CI passes for the exact current pull request head, say so once on the original tracking issue.
// A progress note only: it never closes the issue, moves the card, or claims delivery. The trusted controller writes it with the
// board token; the Claude coding process never holds comment access. Failures are kept as retry state and retried on later polls.
import { locked, readState, atomic } from './state.mjs';
import path from 'node:path';

const shortSha = sha => String(sha ?? '').slice(0, 12);
const prNumber = pr => /\/pull\/(\d+)$/.exec(String(pr ?? ''))?.[1] ?? null;

// One marker per task + pull request + head commit + result, so reruns, repeated polls and restarts never repeat a comment.
export const ciMarker = ({ taskId, pr, sha }) => `<!-- matrix-ci-passed:${taskId}:${prNumber(pr) ?? 'unknown'}:${shortSha(sha)}:success -->`;

export function ciPassedComment({ taskId, pr, sha, runUrl, job }) {
  return [ciMarker({ taskId, pr, sha }),
    `✅ CI passed for **${taskId}**.`, '',
    `- Pull request: ${pr}`,
    `- Checked commit: \`${shortSha(sha)}\``,
    `- CI - Pester tests (Ubuntu, Windows, Windows PowerShell 5.1): passed${runUrl ? ` — ${runUrl}` : ''}`,
    ...(job ? [`- Matrix job: \`${job}\``] : []), '',
    'Next: the trusted merge gate merges the pull request once its checks are confirmed, then the patch version is released and delivery is verified. This is a progress note only; the work is not delivered yet, and the card stays in Doing.'].join('\n');
}

/**
 * Post the CI-passed comment for this head commit, once. Never throws. Returns { posted, reason? } and records the outcome on the task:
 *   task.ciComments[sha] = { postedAt } on success, or { pending: true, pr, runUrl, error } so recoverCiComments can retry it.
 * The comment goes only to the linked tracking issue saved at claim time (never guessed from a branch), and never to the pull request.
 */
export async function postCiPassedComment(task, { sha, pr, runUrl }, io, now = () => new Date().toISOString()) {
  task.ciComments ??= {};
  const key = shortSha(sha), kept = task.ciComments[key];
  if (kept?.postedAt) return { posted: false, reason: 'Already commented' };
  const entry = { pending: true, pr, runUrl, sha };
  try {
    const slug = task.repository;
    if (!task.issue || !slug) throw new Error('No linked tracking issue recorded for this task');
    const marker = ciMarker({ taskId: task.id, pr, sha });
    if (!(await io.hasComment(slug, task.issue, marker))) await io.comment(slug, task.issue, ciPassedComment({ taskId: task.id, pr, sha, runUrl, job: task.job }));
    task.ciComments[key] = { postedAt: now(), pr, sha };
    return { posted: true };
  } catch (error) {
    task.ciComments[key] = { ...entry, error: String(error?.message ?? error).slice(0, 200), failedAt: now() };
    return { posted: false, reason: task.ciComments[key].error };
  }
}

// Retry every comment that failed earlier, without recoding anything. Safe to call on every poll.
export async function recoverCiComments(stateDirectory, { io, now }) {
  return locked(stateDirectory, async () => {
    const state = readState(stateDirectory, { restart: false }), results = {};
    for (const task of Object.values(state.tasks)) {
      for (const [key, c] of Object.entries(task.ciComments ?? {})) {
        if (!c.pending) continue;
        results[`${task.id}:${key}`] = await postCiPassedComment(task, { sha: c.sha ?? key, pr: c.pr, runUrl: c.runUrl }, io, now);
      }
    }
    if (Object.keys(results).length) atomic(path.join(stateDirectory, 'state.json'), state);
    return results;
  });
}
