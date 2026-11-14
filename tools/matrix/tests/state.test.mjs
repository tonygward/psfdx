import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { atomic, locked, readState, writeState, logEvent, reconcile, claim, finish, record, emptyState } from '../state.mjs';

const temp = t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'matrix-state-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
};
const prompt = (id, extra = {}) => ({ id, file: `prompts/${id}-x.md`, hash: 'h1', complete: false, ...extra });

test('atomic replaces the file and leaves no temporary file', t => {
  const dir = temp(t), file = path.join(dir, 'a.json');
  atomic(file, { n: 1 }); atomic(file, { n: 2 });
  assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')), { n: 2 });
  assert.deepEqual(fs.readdirSync(dir), ['a.json']);
});

test('the lock is exclusive, released afterwards and released on error', t => {
  const dir = temp(t);
  const result = locked(dir, () => {
    assert.throws(() => locked(dir, () => 1), /locked/);
    return 'ok';
  });
  assert.equal(result, 'ok');
  assert.equal(fs.existsSync(path.join(dir, 'worker.lock')), false);
  assert.throws(() => locked(dir, () => { throw new Error('boom'); }), /boom/);
  assert.equal(fs.existsSync(path.join(dir, 'worker.lock')), false);
});

test('an async function keeps the lock until it finishes', async t => {
  const dir = temp(t);
  const pending = locked(dir, async () => { await new Promise(r => setTimeout(r, 20)); return 'done'; });
  assert.equal(fs.existsSync(path.join(dir, 'worker.lock')), true);
  assert.equal(await pending, 'done');
  assert.equal(fs.existsSync(path.join(dir, 'worker.lock')), false);
});

test('a stale lock is never stolen', t => {
  const dir = temp(t);
  fs.writeFileSync(path.join(dir, 'worker.lock'), JSON.stringify({ pid: 1, started: '2000-01-01T00:00:00Z' }));
  assert.throws(() => locked(dir, () => 1), /person must remove worker\.lock/);
  assert.equal(fs.existsSync(path.join(dir, 'worker.lock')), true);
});

test('a missing state file is empty, and a corrupt one is refused and left alone', t => {
  const dir = temp(t);
  assert.deepEqual(readState(dir), emptyState());
  const file = path.join(dir, 'state.json');
  for (const bad of ['{not json', '{"schema":2}', '{"schema":1,"tasks":{}}', 'null']) {
    fs.writeFileSync(file, bad);
    assert.throws(() => readState(dir), /restore a verified backup/);
    assert.equal(fs.readFileSync(file, 'utf8'), bad, 'the file was not replaced');
  }
});

test('a claimed task becomes interrupted on load', t => {
  const dir = temp(t);
  const state = emptyState();
  state.tasks['AUTO-07'] = { id: 'AUTO-07', state: 'claimed' };
  state.tasks['AUTO-08'] = { id: 'AUTO-08', state: 'pending' };
  writeState(dir, state);
  const loaded = readState(dir);
  assert.equal(loaded.tasks['AUTO-07'].state, 'interrupted');
  assert.match(loaded.tasks['AUTO-07'].reason, /restarted/);
  assert.equal(loaded.tasks['AUTO-08'].state, 'pending');
});

test('the log is append-only JSON lines and drops secrets and raw output', t => {
  const dir = temp(t);
  logEvent(dir, { event: 'one', token: 'ghp_x', stderr: 'private', rawOutput: 'x', task: 'AUTO-07' });
  logEvent(dir, { event: 'two' });
  const lines = fs.readFileSync(path.join(dir, 'logs', 'worker.jsonl'), 'utf8').trim().split('\n').map(l => JSON.parse(l));
  assert.equal(lines.length, 2);
  assert.deepEqual(Object.keys(lines[0]).sort(), ['event', 'task', 'time']);
  assert.ok(!JSON.stringify(lines).includes('ghp_x'));
});

test('reconcile creates, withdraws and completes tasks', () => {
  const state = emptyState();
  reconcile(state, [prompt('AUTO-07'), prompt('AUTO-08')], 'r1');
  assert.equal(state.tasks['AUTO-07'].state, 'pending');
  reconcile(state, [prompt('AUTO-08')], 'r2');
  assert.equal(state.tasks['AUTO-07'].state, 'withdrawn');
  reconcile(state, [prompt('AUTO-07'), prompt('AUTO-08', { complete: true })], 'r3');
  assert.equal(state.tasks['AUTO-07'].state, 'pending');
  assert.equal(state.tasks['AUTO-08'].state, 'complete');
});

test('claim requires a pending task with the same hash and revision, and records the run start once', () => {
  const state = emptyState();
  reconcile(state, [prompt('AUTO-07')], 'r1');
  assert.throws(() => claim(state, prompt('AUTO-07', { hash: 'other' }), 'r1'), /Claim rejected/);
  assert.throws(() => claim(state, prompt('AUTO-07'), 'r2'), /Claim rejected/);
  assert.equal(claim(state, prompt('AUTO-07'), 'r1', 2, '2026-11-14T10:00:00Z'), true);
  assert.equal(state.tasks['AUTO-07'].state, 'claimed');
  assert.equal(state.tasks['AUTO-07'].runStartedAt, '2026-11-14T10:00:00Z');
  assert.throws(() => claim(state, prompt('AUTO-07'), 'r1'), /Claim rejected/);
});

test('too many attempts go to dead-letter instead of being claimed', () => {
  const state = emptyState();
  reconcile(state, [prompt('AUTO-07')], 'r1');
  state.tasks['AUTO-07'].attempts = 2;
  assert.equal(claim(state, prompt('AUTO-07'), 'r1', 2), false);
  assert.equal(state.tasks['AUTO-07'].state, 'dead-letter');
});

test('finish only moves a claimed task to an allowed state, never to complete', () => {
  const state = emptyState();
  reconcile(state, [prompt('AUTO-07')], 'r1');
  assert.throws(() => finish(state, 'AUTO-07', 'awaiting-review'), /Invalid finish/);
  claim(state, prompt('AUTO-07'), 'r1');
  assert.throws(() => finish(state, 'AUTO-07', 'complete'), /Invalid finish/);
  finish(state, 'AUTO-07', 'awaiting-review', { pullRequest: 12 });
  assert.equal(state.tasks['AUTO-07'].state, 'awaiting-review');
  assert.equal(state.tasks['AUTO-07'].pullRequest, 12);
});

test('history is capped', () => {
  const state = emptyState();
  for (let i = 0; i < 1100; i++) record(state, { i });
  assert.equal(state.history.length, 1000);
  assert.equal(state.history.at(-1).i, 1099);
});
