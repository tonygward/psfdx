import test from 'node:test';
import assert from 'node:assert/strict';
import { assessIssue, sections, promptFromIssue, promptPath, resolveFromIssues, needsDetailComment, needsDetailMarker, notOwnerMarker } from '../issue-prompt.mjs';
import { parsePrompt } from '../backlog.mjs';
import { node, fakeIo, goodBody, REPO } from './fixtures.mjs';
import { normaliseCard } from '../board.mjs';

const board = (...nodes) => ({ ok: true, cards: nodes.map((n, i) => normaliseCard(n, i)) });
const base = { statuses: ['Doing', 'Todo'], repository: REPO, ownerLogin: 'tonygward', dryRun: false };

test('a detailed issue is assessed as ready', () => {
  assert.deepEqual(assessIssue(goodBody), { ok: true, missing: [] });
});

test('each missing section is named', () => {
  const result = assessIssue('## Objective\nMake the thing work so that users can rely on it every day.\n');
  assert.equal(result.ok, false);
  assert.equal(result.missing.length, 3);
  assert.match(result.missing[0], /scope or implementation/);
});

test('thin sections do not count, and a combined heading covers the tests', () => {
  assert.equal(assessIssue(goodBody.replace('The cmdlet returns the expected records for a successful result.', 'ok')).ok, false);
  const combined = ['## Objective', 'Make the thing work so that users can rely on it every day.', '## Implementation', 'Change the module so that it builds the correct command string.',
    '## Acceptance criteria and tests', 'The cmdlet returns records and a Pester test asserts the exact command.'].join('\n');
  assert.deepEqual(assessIssue(combined), { ok: true, missing: [] });
});

test('bold labels count as headings and Windows line endings are fine', () => {
  const body = goodBody.replaceAll('## ', '**').replace(/\*\*(Objective|Scope|Acceptance criteria|Tests)/g, '**$1**').replace(/\n/g, '\r\n');
  assert.equal(assessIssue(body).ok, true);
  assert.ok(sections(body).length >= 4);
});

test('the generated prompt follows the contract and has no status, execution or model', () => {
  const prompt = promptFromIssue({ taskId: 'PSF-14', title: 'PSF-14: Get-SalesforceFieldUsage', issue: 14 }, goodBody, { issueUrl: 'https://github.com/tonygward/psfdx/issues/14' });
  assert.equal(prompt.generated.file, 'prompts/PSF-14-get-salesforcefieldusage.md');
  assert.doesNotMatch(prompt.generated.text, /^(status|execution|model):/m);
  assert.match(prompt.generated.text, /^id: PSF-14$/m);
  assert.match(prompt.generated.text, /issues\/14/);
  const reparsed = parsePrompt(prompt.generated.file, prompt.generated.text);
  assert.equal(reparsed.id, 'PSF-14'); assert.equal(reparsed.hash, prompt.hash);
  assert.equal(promptPath('AUTO-07', 'AUTO-07: Bounded loop!'), 'prompts/AUTO-07-bounded-loop.md');
});

test('a ready issue yields a generated prompt and writes nothing', async () => {
  const io = fakeIo({ bodies: { 1: goodBody } });
  const result = await resolveFromIssues({ ...base, board: board(node({ number: 1, title: 'PSF-01: thing' })), prompts: [], io });
  assert.equal(result.prompts.length, 1); assert.equal(result.prompts[0].id, 'PSF-01');
  assert.deepEqual(io.writes, []);
});

test('an issue without enough detail gets one comment, deduplicated, and the card moves to Blocked', async () => {
  const io = fakeIo({ bodies: { 1: '## Objective\nMake the thing work so that users can rely on it every day.' } });
  const first = await resolveFromIssues({ ...base, board: board(node({ number: 1, title: 'PSF-01: thing' })), prompts: [], io });
  assert.deepEqual(first.blocked, ['PSF-01']);
  assert.deepEqual(io.writes.map(w => w.kind), ['comment', 'blocked']);
  assert.match(io.writes[0].body, /scope or implementation/);
  // The same issue text again: the comment is not repeated, but the card is still parked.
  await resolveFromIssues({ ...base, board: board(node({ number: 1, title: 'PSF-01: thing' })), prompts: [], io });
  assert.equal(io.writes.filter(w => w.kind === 'comment').length, 1);
  // The issue changes: a new comment.
  io.issueBody = async () => '## Objective\nA different objective that is still not enough detail to build from.';
  await resolveFromIssues({ ...base, board: board(node({ number: 1, title: 'PSF-01: thing' })), prompts: [], io });
  assert.equal(io.writes.filter(w => w.kind === 'comment').length, 2);
});

test('the marker includes a hash of the missing list and the issue text', () => {
  assert.notEqual(needsDetailMarker('PSF-01', 'aaa'), needsDetailMarker('PSF-01', 'bbb'));
  assert.match(needsDetailComment('PSF-01', ['x'], 'abc123'), /^<!-- matrix:needs-detail:PSF-01:abc123 -->/);
});

test('an issue the owner did not write is never used: one comment, Blocked, body never read', async () => {
  const io = fakeIo({ bodies: { 1: goodBody } });
  let read = false;
  const original = io.issueBody; io.issueBody = async (...args) => { read = true; return original(...args); };
  const result = await resolveFromIssues({ ...base, board: board(node({ number: 1, title: 'PSF-01: thing', association: 'NONE', author: 'stranger' })), prompts: [], io });
  assert.equal(result.prompts.length, 0); assert.deepEqual(result.blocked, ['PSF-01']);
  assert.equal(read, false);
  assert.match(io.writes[0].body, /only builds from issues written by the repository owner/);
  await resolveFromIssues({ ...base, board: board(node({ number: 1, title: 'PSF-01: thing', association: 'NONE', author: 'stranger' })), prompts: [], io });
  assert.equal(io.writes.filter(w => w.kind === 'comment').length, 1);
  assert.match(notOwnerMarker('PSF-01', 1), /matrix:not-owner:PSF-01:1/);
});

test('an issue in another repository is not used', async () => {
  const io = fakeIo({ bodies: { 1: goodBody } });
  const result = await resolveFromIssues({ ...base, board: board(node({ number: 1, title: 'PSF-01: thing', repo: 'someone/else' })), prompts: [], io });
  assert.equal(result.prompts.length, 0); assert.equal(io.writes[0].kind, 'comment');
});

test('a dry run assesses and writes nothing', async () => {
  const io = fakeIo({ bodies: { 1: 'too short', 2: goodBody } });
  const result = await resolveFromIssues({ ...base, dryRun: true, board: board(node({ number: 1, title: 'PSF-01: a' }), node({ number: 2, title: 'PSF-02: b', association: 'NONE', author: 'x' })), prompts: [], io });
  assert.deepEqual(io.writes, []); assert.deepEqual(result.blocked, []);
  assert.equal(result.notes.length, 2);
});

test('cards with a prompt, outside the run statuses, merged, or with an open pull request are left alone', async () => {
  const io = fakeIo({ bodies: { 1: goodBody, 2: goodBody, 3: goodBody, 4: goodBody } });
  const cards = board(node({ number: 1, title: 'PSF-01: a' }), node({ number: 2, title: 'PSF-02: b', status: 'Backlog' }), node({ number: 3, title: 'PSF-03: c' }), node({ number: 4, title: 'PSF-04: d' }));
  const result = await resolveFromIssues({ ...base, board: cards, prompts: [{ id: 'PSF-01' }], io, merged: new Set(['PSF-03']), open: new Set(['PSF-04']) });
  assert.deepEqual(result.prompts, []);
  assert.deepEqual(io.writes, []);
});

test('a read failure is noted and writes nothing', async () => {
  const io = fakeIo(); io.issueBody = async () => { throw new Error('network'); };
  const result = await resolveFromIssues({ ...base, board: board(node({ number: 1, title: 'PSF-01: a' })), prompts: [], io });
  assert.match(result.notes[0], /could not assess/); assert.deepEqual(io.writes, []);
});
