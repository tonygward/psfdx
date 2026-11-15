// Delivery lifecycle. A merged pull request is not delivery. The order is fixed:
// verify the release -> final issue comment -> close the issue -> board Done.
// Each stage is saved, so a crash resumes at the failed stage. A failed final comment blocks closing and Done; a failed close
// or Done is retried on its own without a second comment. Merged work is never recoded while delivery is pending.
// Verification reads only through injected functions, so this module holds no credentials and writes nothing itself.
import path from 'node:path';
import { createHash } from 'node:crypto';
import { atomic, locked, readState, record } from './state.mjs';
import { verifyMerge, verifyVersion, verifyRelease, verifyNotes, verifyPromptArchived, verifyGallery, shipsNothing, assetName } from './verifiers.mjs';

export const STAGES = ['pending', 'verified', 'commented', 'closed', 'done'];
export const finalMarker = task => `<!-- matrix-final:${task} -->`;
export const blockerMarker = (task, hash) => `<!-- matrix-blocker:${task}:${hash} -->`;
const short = sha => String(sha ?? '').slice(0, 12);

/**
 * io (reads): pull, pullFiles, commitsAfter, release, tagCommit, fileAt, fileExists, galleryHas
 * io (writes): hasComment, comment, closeIssue, moveToDone
 * options.psGallery: when true, the bundled psfdx package must be listed on the Gallery at the released version.
 */
export async function verifyDelivery(delivery, io, { psGallery = false } = {}) {
  const missing = [], evidence = { psGallery: { enabled: psGallery } };
  const attempt = async (label, fn) => { try { return await fn(); } catch (error) { missing.push(`${label} could not be verified: ${String(error.message).slice(0, 120)}`); return null; } };
  try {
    const merge = await verifyMerge(io, delivery);
    if (!merge.ok) return { verified: false, missing: merge.missing, evidence };
    evidence.pull = merge.evidence;
    // A change that ships nothing was not bumped or released: there is nothing to verify beyond the merge and the archive.
    const files = await attempt('Changed files', () => io.pullFiles(delivery.repository, delivery.pull));
    if (files === null) return { verified: false, missing, evidence };
    if (shipsNothing(files)) {
      evidence.docsOnly = true;
    } else {
      const version = await verifyVersion(io, delivery.repository, merge.evidence.mergeSha);
      if (!version.ok) { missing.push(...version.missing); }
      else {
        const { version: v, bumpSha } = version.evidence;
        const release = await attempt('Release', () => verifyRelease(io, delivery.repository, v, bumpSha));
        if (release) {
          missing.push(...release.missing);
          evidence.release = { tag: release.evidence.tag, url: release.evidence.url, version: v, asset: release.evidence.asset, bumpSha };
          // Each check runs on its own, so one unavailable verifier cannot hide the others' findings.
          if (release.evidence.body !== undefined && release.missing.length === 0) {
            const notes = await attempt('Release notes', () => verifyNotes(io, delivery.repository, v, { body: release.evidence.body }));
            if (notes) missing.push(...notes.missing);
          }
          if (psGallery) {
            const gallery = await attempt('PowerShell Gallery', () => verifyGallery(io, v));
            if (gallery) { missing.push(...gallery.missing); if (gallery.ok) evidence.psGallery = { enabled: true, ...gallery.evidence }; }
          }
        }
      }
    }
    // Every finished task keeps a canonical prompt, including one generated from its issue.
    const archived = await attempt('Archived prompt', () => verifyPromptArchived(io, delivery.repository, delivery.prompt));
    if (archived) missing.push(...archived.missing);
  } catch (error) {
    return { verified: false, missing: [`Verification could not complete: ${String(error.message).slice(0, 160)}`], evidence };
  }
  return { verified: missing.length === 0, missing, evidence };
}

export function finalComment({ taskId, job, evidence }) {
  const { pull, release, psGallery, docsOnly } = evidence;
  return [finalMarker(taskId), `**${taskId} is done.**`, '',
    `- Pull request: ${pull.url ?? `#${pull.number}`} (merge commit \`${short(pull.mergeSha)}\`)`,
    `- Matrix job: \`${job}\``,
    ...(docsOnly
      ? ['- Release: No release needed (nothing in this change ships).']
      : [`- Release: ${release.tag} (${release.url})`, `- Download: ${release.url} (\`${release.asset}\`)`]),
    ...(docsOnly ? [] : psGallery?.url
      ? [`- PowerShell Gallery: \`Install-Module psfdx -RequiredVersion ${release.version}\` (${psGallery.url})`]
      : ['- PowerShell Gallery: Not published to the PowerShell Gallery yet']), '',
    'Closing this issue and moving the card to Done.'].join('\n');
}

/**
 * Moves one merged task through delivery. Safe to call repeatedly; each call resumes at the stage that failed.
 */
export async function advanceDelivery(stateDirectory, taskId, io, { now = () => new Date().toISOString(), psGallery = false } = {}) {
  return locked(stateDirectory, async () => {
    const state = readState(stateDirectory, { restart: false });
    const delivery = state.deliveries?.[taskId];
    if (!delivery) return { stage: null, blocked: 'No delivery recorded for this task' };
    const save = () => atomic(path.join(stateDirectory, 'state.json'), state);
    const slug = delivery.repository;
    const stop = (reason, event) => { record(state, { event, task: taskId, reason: reason.slice(0, 200) }); save(); return { stage: delivery.stage, blocked: reason }; };

    if (delivery.stage === 'pending') {
      const result = await verifyDelivery(delivery, io, { psGallery });
      if (!result.verified) {
        // One blocker comment per distinct set of reasons; no heartbeat spam.
        const hash = createHash('sha256').update(result.missing.join('|')).digest('hex').slice(0, 12);
        if (delivery.blockerHash !== hash) {
          try {
            if (!(await io.hasComment(slug, delivery.issue, blockerMarker(taskId, hash)))) {
              await io.comment(slug, delivery.issue, [blockerMarker(taskId, hash), `**${taskId}: merged, waiting for delivery.**`, '', ...result.missing.map(m => `- ${m}`), '',
                'The implementation is merged and will not be coded again. The issue stays open and the card stays in Doing until delivery is verified.'].join('\n'));
            }
            delivery.blockerHash = hash;
          } catch { /* the comment is retried next run; it never blocks recording the blocker */ }
        }
        return stop(result.missing.join('; '), 'delivery-blocked');
      }
      Object.assign(delivery, { stage: 'verified', evidence: result.evidence, verifiedAt: now() });
      record(state, { event: 'delivery-verified', task: taskId }); save();
    }
    if (delivery.stage === 'verified') {
      try {
        if (!(await io.hasComment(slug, delivery.issue, finalMarker(taskId)))) await io.comment(slug, delivery.issue, finalComment({ taskId, job: delivery.job, evidence: delivery.evidence }));
      } catch (error) { return stop(`Final comment failed: ${error.message}`, 'final-comment-failed'); }
      Object.assign(delivery, { stage: 'commented', commentedAt: now() }); record(state, { event: 'final-comment', task: taskId }); save();
    }
    if (delivery.stage === 'commented') {
      try { await io.closeIssue(slug, delivery.issue); } catch (error) { return stop(`Closing the issue failed: ${error.message}`, 'close-failed'); }
      Object.assign(delivery, { stage: 'closed', closedAt: now() }); record(state, { event: 'issue-closed', task: taskId }); save();
    }
    if (delivery.stage === 'closed') {
      try { await io.moveToDone(delivery.itemId); } catch (error) { return stop(`Setting the card to Done failed: ${error.message}`, 'done-failed'); }
      Object.assign(delivery, { stage: 'done', doneAt: now() });
      // Delivered work leaves the active states, so a finished task can never hold the single job slot.
      const task = state.tasks[taskId]; if (task && ['claimed', 'awaiting-review'].includes(task.state)) task.state = 'complete';
      record(state, { event: 'card-done', task: taskId }); save();
    }
    return { stage: delivery.stage, blocked: null };
  });
}

// Called when a pull request for a claimed task merges. Idempotent.
export function recordMerge(state, taskId, { repository, pull }) {
  const task = state.tasks[taskId];
  if (!task?.job || !task.issue || !task.itemId) throw new Error('Task has no pickup record');
  state.deliveries ??= {};
  state.deliveries[taskId] ??= { stage: 'pending', repository: repository ?? task.repository, pull, issue: task.issue, itemId: task.itemId, job: task.job, prompt: task.file ?? null, mergedRecordedAt: new Date().toISOString() };
  return state.deliveries[taskId];
}

export { assetName };
