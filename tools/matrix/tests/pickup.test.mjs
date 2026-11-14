import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pickupProvenance, provenanceLines, pickupComment, pickUp, recoverPickupComments, marker, UNKNOWN_REASON } from '../pickup.mjs';
import { readState, writeState, reconcile, emptyState } from '../state.mjs';
import { writeHandoff, readHandoff, adoptHandoff, clearHandoff, boardFields } from '../handoff.mjs';
import { fakeIo, prompt, REPO } from './fixtures.mjs';

const temp = t => { const d = fs.mkdtempSync(path.join(os.tmpdir(), 'matrix-pickup-')); t.after(() => fs.rmSync(d, { recursive: true, force: true })); return d; };
const selected = (extra = {}) => ({ taskId: 'PSF-01', promptHash: 'hash-PSF-01-0000000000', status: 'Todo', issue: 1, itemId: 'item-1', repository: REPO, ...extra });
const seed = (dir, ids = ['PSF-01']) => { const s = emptyState(); reconcile(s, ids.map(id => prompt(id)), 'r'.repeat(40)); writeState(dir, s); };
const REVISION = 'r'.repeat(40);

test('Todo is Scheduled with the London date', () => {
  const p = pickupProvenance({ status: 'Todo', selectedAt: '2026-11-14T10:00:00Z' });
  assert.equal(p.reason, 'Scheduled (Todo)'); assert.equal(p.scheduleDate, '2026-11-14'); assert.equal(p.preClaimStatus, 'Todo');
});

test('Doing is Run now, and the person who moved it is reported as unknown', () => {
  const p = pickupProvenance({ status: 'Doing', selectedAt: '2026-11-14T10:00:00Z' });
  assert.equal(p.reason, 'Run now (Doing)'); assert.match(p.initiator, /^Unknown/);
});

test('a resume names the earlier job, branch and pull request', () => {
  const p = pickupProvenance({ status: 'Doing', selectedAt: '2026-11-14T10:00:00Z', resumedFrom: { job: 'job-1', reason: 'CI repair limit', pr: '#12', branch: 'matrix/PSF-01' } });
  assert.equal(p.reason, 'Resumed (Doing)');
  const text = provenanceLines(p).join('\n');
  assert.match(text, /job `job-1` \(CI repair limit\), #12, branch `matrix\/PSF-01`/);
});

test('anything else is Unknown (provenance unavailable)', () => {
  for (const input of [{}, { status: 'Backlog', selectedAt: '2026-11-14T10:00:00Z' }, { status: 'Todo', selectedAt: 'not a date' }]) {
    assert.equal(pickupProvenance(input).reason, UNKNOWN_REASON);
  }
  assert.deepEqual(provenanceLines(null), [`- Pickup reason: ${UNKNOWN_REASON}`]);
});

test('the selection time is shown in London time, across the clock change', () => {
  assert.match(provenanceLines(pickupProvenance({ status: 'Todo', selectedAt: '2026-07-01T23:30:00Z' })).join('\n'), /2026-07-02 00:30 Europe\/London/);
  assert.match(provenanceLines(pickupProvenance({ status: 'Todo', selectedAt: '2026-11-14T10:00:00Z' })).join('\n'), /2026-11-14 10:00 Europe\/London/);
});

test('a pickup persists the claim before commenting, moves the card and posts one comment with the marker', async t => {
  const dir = temp(t); seed(dir);
  const io = fakeIo();
  const result = await pickUp(dir, selected(), { job: 'job-1', revision: REVISION, io, now: () => '2026-11-14T10:00:00Z' });
  assert.equal(result.claimed, true); assert.equal(result.comment.posted, true);
  assert.deepEqual(io.writes.map(w => w.kind), ['doing', 'comment']);
  assert.ok(io.writes[1].body.startsWith(marker('PSF-01', 'job-1')));
  assert.match(io.writes[1].body, /Pickup reason: Scheduled \(Todo\)/);
  const task = readState(dir, { restart: false }).tasks['PSF-01'];
  assert.equal(task.state, 'claimed'); assert.equal(task.job, 'job-1'); assert.equal(task.runStartedAt, '2026-11-14T10:00:00Z');
  assert.ok(task.pickupCommentAt);
});

test('only one job may be active, and a stale selection is refused', async t => {
  const dir = temp(t); seed(dir, ['PSF-01', 'PSF-02']);
  const io = fakeIo();
  await pickUp(dir, selected(), { job: 'job-1', revision: REVISION, io });
  const second = await pickUp(dir, selected({ taskId: 'PSF-02', promptHash: 'hash-PSF-02-0000000000' }), { job: 'job-2', revision: REVISION, io });
  assert.equal(second.claimed, false); assert.match(second.reason, /already active/);
  const stale = await pickUp(dir, selected({ taskId: 'PSF-02', promptHash: 'changed' }), { job: 'job-3', revision: REVISION, io: fakeIo() });
  assert.equal(stale.claimed, false);
});

test('a failed comment keeps the claim and is retried once, without a second job', async t => {
  const dir = temp(t); seed(dir);
  const failing = fakeIo({ failComment: true });
  const result = await pickUp(dir, selected(), { job: 'job-1', revision: REVISION, io: failing });
  assert.equal(result.claimed, true); assert.equal(result.comment.posted, false);
  assert.equal(readState(dir, { restart: false }).tasks['PSF-01'].state, 'claimed');
  const io = fakeIo();
  const recovered = await recoverPickupComments(dir, { revision: REVISION, io });
  assert.equal(recovered['PSF-01'].posted, true);
  assert.equal(io.writes.filter(w => w.kind === 'comment').length, 1);
  assert.equal(io.writes.filter(w => w.kind === 'doing').length, 0, 'the card had already moved before the comment failed');
  assert.deepEqual(await recoverPickupComments(dir, { revision: REVISION, io }), {}, 'nothing left to recover');
});

test('a retry never posts a second comment when the marker is already there', async t => {
  const dir = temp(t); seed(dir);
  const io = fakeIo({ comments: [marker('PSF-01', 'job-1')] });
  await pickUp(dir, selected(), { job: 'job-1', revision: REVISION, io });
  assert.equal(io.writes.filter(w => w.kind === 'comment').length, 0);
});

test('the pickup reason survives a restart: the comment is rendered from the saved copy', async t => {
  const dir = temp(t); seed(dir);
  const failing = fakeIo({ failComment: true });
  await pickUp(dir, selected({ provenance: pickupProvenance({ status: 'Todo', selectedAt: '2026-11-14T10:00:00Z' }) }), { job: 'job-1', revision: REVISION, io: failing, now: () => '2026-11-14T10:00:00Z' });
  // A different clock and a different card status at retry time must not change the reason.
  const io = fakeIo();
  await recoverPickupComments(dir, { revision: REVISION, io, now: () => '2026-12-25T03:00:00Z' });
  assert.match(io.writes.find(w => w.kind === 'comment').body, /Pickup reason: Scheduled \(Todo\)[\s\S]*Selected at: 2026-11-14 10:00 Europe\/London[\s\S]*London schedule date: 2026-11-14/);
});

test('a worker restart marks the claim interrupted, but a board tick read does not', async t => {
  const dir = temp(t); seed(dir);
  await pickUp(dir, selected(), { job: 'job-1', revision: REVISION, io: fakeIo() });
  assert.equal(readState(dir, { restart: false }).tasks['PSF-01'].state, 'claimed');
  assert.equal(readState(dir).tasks['PSF-01'].state, 'interrupted');
});

test('the comment lists the limits when given', () => {
  assert.match(pickupComment({ taskId: 'PSF-01', job: 'j', promptHash: 'h'.repeat(20), revision: 'r'.repeat(40), repository: REPO, limits: '120 minutes' }), /- Limits: 120 minutes/);
});

test('hand-off: written, read back, adopted, and refused when stale or changed', t => {
  const dir = temp(t);
  writeHandoff(dir, { selected: selected(), job: 'job-1', revision: REVISION, now: Date.parse('2026-11-14T10:00:00Z') });
  const handoff = readHandoff(dir, { now: Date.parse('2026-11-14T10:05:00Z') });
  assert.equal(handoff.taskId, 'PSF-01'); assert.equal(handoff.provenance.reason, 'Scheduled (Todo)');
  assert.equal(readHandoff(dir, { now: Date.parse('2026-11-14T10:16:00Z') }), null, 'older than 15 minutes');
  assert.equal(readHandoff(dir, { now: Date.parse('2026-11-14T09:59:00Z') }), null, 'from the future');
  const state = emptyState(); reconcile(state, [prompt('PSF-01')], REVISION);
  assert.ok(adoptHandoff(state, [prompt('PSF-01')], handoff).prompt);
  assert.match(adoptHandoff(state, [prompt('PSF-01', { hash: 'new' })], handoff).reason, /changed/);
  assert.match(adoptHandoff(state, [], handoff).reason, /no longer exists/);
  state.tasks['PSF-01'].state = 'claimed';
  assert.match(adoptHandoff(state, [prompt('PSF-01')], handoff).reason, /not pending/);
  assert.equal(boardFields(handoff).issue, 1);
  clearHandoff(dir);
  assert.equal(readHandoff(dir), null);
});

test('hand-off: corrupt or incomplete files are ignored', t => {
  const dir = temp(t);
  fs.writeFileSync(path.join(dir, 'board-handoff.json'), '{broken');
  assert.equal(readHandoff(dir), null);
  fs.writeFileSync(path.join(dir, 'board-handoff.json'), JSON.stringify({ schema: 1, createdAt: new Date().toISOString(), taskId: 'PSF-01' }));
  assert.equal(readHandoff(dir), null);
});
