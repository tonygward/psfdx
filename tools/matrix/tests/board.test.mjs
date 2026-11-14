import test from 'node:test';
import assert from 'node:assert/strict';
import { fetchBoard, fetchPulls, selectFromBoard, matrixBranchTask, pullTaskState, normaliseCard, ownerIssue, BOARD_QUERY } from '../board.mjs';
import { node, boardGraphql, combinedGraphql, prompt, usageOk, REPO, NOW } from './fixtures.mjs';

const clock = () => NOW;
const snapshot = async nodes => fetchBoard(boardGraphql([nodes]), 'PVT_1', { clock });
const pick = (board, prompts, context = {}) => selectFromBoard(board, prompts, {
  now: NOW, usage: usageOk(), repository: REPO, ownerLogin: 'tonygward', statuses: ['Doing', 'Todo'], ...context });

test('the query orders by POSITION and asks for what the gate needs', () => {
  assert.match(BOARD_QUERY, /orderBy: \{ field: POSITION, direction: ASC \}/);
  assert.match(BOARD_QUERY, /authorAssociation/);
  assert.match(BOARD_QUERY, /views\(first: 10\)/);
});

test('cards keep the board position order, never ID or issue number order', async () => {
  const board = await snapshot([
    node({ number: 30, title: 'PSF-30: c', status: 'Todo' }), node({ number: 10, title: 'AUTO-10: a', status: 'Todo' }), node({ number: 20, title: 'PSF-20: b', status: 'Todo' })]);
  assert.equal(board.ok, true);
  assert.deepEqual(board.cards.map(c => c.taskId), ['PSF-30', 'AUTO-10', 'PSF-20']);
  const result = pick(board, [prompt('PSF-30'), prompt('AUTO-10'), prompt('PSF-20')]);
  assert.equal(result.selected.taskId, 'PSF-30');
});

test('pagination reads every page, in order', async () => {
  const pages = [[node({ number: 1, title: 'PSF-01: a' })], [node({ number: 2, title: 'PSF-02: b' })], [node({ number: 3, title: 'PSF-03: c' })]];
  const graphql = boardGraphql(pages);
  const board = await fetchBoard(graphql, 'PVT_1', { clock });
  assert.deepEqual(board.cards.map(c => c.issue), [1, 2, 3]);
  assert.equal(graphql.calls.length, 3);
  assert.equal(graphql.calls[1].variables.after, 'cursor-1');
});

test('fail closed: two views, a partial snapshot, an API error, a missing cursor', async () => {
  const one = [[node({ number: 1, title: 'PSF-01: a' })]];
  assert.match((await fetchBoard(boardGraphql(one, { views: 2 }), 'p', { clock })).reason, /1 view only; found 2/);
  assert.match((await fetchBoard(boardGraphql(one, { total: 5 }), 'p', { clock })).reason, /Partial board snapshot/);
  assert.match((await fetchBoard(boardGraphql(one, { failAt: 0 }), 'p', { clock })).reason, /Board read failed: API error/);
  assert.match((await fetchBoard(async () => ({ data: { node: null } }), 'p', { clock })).reason, /missing items/);
  const noCursor = async () => ({ data: { node: { views: { totalCount: 1 }, items: { totalCount: 2, pageInfo: { hasNextPage: true, endCursor: null }, nodes: [] } } } });
  assert.match((await fetchBoard(noCursor, 'p', { clock })).reason, /cursor missing/);
  const forever = async () => ({ data: { node: { views: { totalCount: 1 }, items: { totalCount: 9999, pageInfo: { hasNextPage: true, endCursor: 'x' }, nodes: [] } } } });
  assert.match((await fetchBoard(forever, 'p', { clock })).reason, /page limit/);
});

test('a failed board read selects nothing and there is no fallback ordering', () => {
  const result = selectFromBoard({ ok: false, reason: 'Partial board snapshot' }, [prompt('PSF-01')], { now: NOW, usage: usageOk(), repository: REPO });
  assert.equal(result.selected, null);
  assert.equal(result.blocker, 'Partial board snapshot');
});

test('a stale snapshot selects nothing', async () => {
  const board = await snapshot([node({ number: 1, title: 'PSF-01: a' })]);
  assert.match(pick(board, [prompt('PSF-01')], { now: NOW + 61000 }).blocker, /Stale/);
});

test('Doing runs before Todo, each in board order', async () => {
  const board = await snapshot([
    node({ number: 1, title: 'PSF-01: a', status: 'Todo' }), node({ number: 2, title: 'PSF-02: b', status: 'Doing' }), node({ number: 3, title: 'PSF-03: c', status: 'Doing' })]);
  const result = pick(board, [prompt('PSF-01'), prompt('PSF-02'), prompt('PSF-03')]);
  assert.equal(result.selected.taskId, 'PSF-02');
  assert.equal(result.decisions.find(d => d.taskId === 'PSF-03').reason, 'eligible; one task per run');
});

test('Todo cards are not offered when the daily slot is not open', async () => {
  const board = await snapshot([node({ number: 1, title: 'PSF-01: a', status: 'Todo' })]);
  assert.equal(pick(board, [prompt('PSF-01')], { statuses: ['Doing'] }).selected, null);
});

test('Backlog, Blocked, Done and no-status cards never run', async () => {
  const board = await snapshot(['Backlog', 'Blocked', 'Done', null].map((status, i) => node({ number: i + 1, title: `PSF-0${i + 1}: x`, status })));
  const result = pick(board, [1, 2, 3, 4].map(i => prompt(`PSF-0${i}`)));
  assert.equal(result.selected, null);
  assert.deepEqual(result.decisions, []);
});

test('wording such as deferred or not queued in the title holds nothing; only the column does', async () => {
  const board = await snapshot([node({ number: 1, title: 'PSF-01: deferred, not queued', status: 'Todo' })]);
  assert.equal(pick(board, [prompt('PSF-01', { body: 'This is deferred. Do not build.' })]).selected.taskId, 'PSF-01');
});

test('unmet dependencies skip the card without blocking later cards', async () => {
  const board = await snapshot([node({ number: 1, title: 'PSF-02: b' }), node({ number: 2, title: 'PSF-03: c' })]);
  const result = pick(board, [prompt('PSF-02', { dependencies: ['PSF-01'] }), prompt('PSF-03'), prompt('PSF-01')]);
  assert.match(result.decisions[0].reason, /unmet dependencies: PSF-01/);
  assert.equal(result.selected.taskId, 'PSF-03');
  const met = pick(board, [prompt('PSF-02', { dependencies: ['PSF-01'] }), prompt('PSF-03'), prompt('PSF-01', { complete: true })]);
  assert.equal(met.selected.taskId, 'PSF-02');
});

test('a task that conflicts with active work is skipped', async () => {
  const board = await snapshot([node({ number: 1, title: 'PSF-02: b' }), node({ number: 2, title: 'PSF-03: c' })]);
  const tasks = { 'PSF-09': { id: 'PSF-09', state: 'interrupted' } };
  const result = pick(board, [prompt('PSF-02', { conflicts: ['PSF-09'] }), prompt('PSF-03'), prompt('PSF-09')], { tasks });
  assert.equal(result.decisions[0].reason, 'conflicts with active work');
  assert.equal(result.selected.taskId, 'PSF-03');
});

test('merged work goes to delivery and is never recoded, and an open pull request holds the card', async () => {
  const board = await snapshot([node({ number: 1, title: 'PSF-01: a' }), node({ number: 2, title: 'PSF-02: b' }), node({ number: 3, title: 'PSF-03: c' }), node({ number: 4, title: 'PSF-04: d' })]);
  const result = pick(board, [prompt('PSF-01'), prompt('PSF-02'), prompt('PSF-03', { complete: true }), prompt('PSF-04')], { mergedTaskIds: new Set(['PSF-01']), openPullTaskIds: new Set(['PSF-02']) });
  assert.match(result.decisions[0].reason, /merged; delivery pending/);
  assert.match(result.decisions[1].reason, /open pull request/);
  assert.match(result.decisions[2].reason, /merged/);
  assert.equal(result.selected.taskId, 'PSF-04');
  const resume = pick(board, [prompt('PSF-02')], { openPullTaskIds: new Set(['PSF-02']), tasks: { 'PSF-02': { id: 'PSF-02', state: 'pending', resumeWork: true } } });
  assert.equal(resume.selected.taskId, 'PSF-02');
});

test('only the repository owner in this repository is built from', async () => {
  const board = await snapshot([
    node({ number: 1, title: 'PSF-01: a', association: 'NONE', author: 'stranger' }),
    node({ number: 2, title: 'PSF-02: b', repo: 'someone/else' }),
    node({ number: 3, title: 'PSF-03: c', association: 'COLLABORATOR', author: 'tonygward' }),
    node({ number: 4, title: 'PSF-04: d' })]);
  const result = pick(board, ['PSF-01', 'PSF-02', 'PSF-03', 'PSF-04'].map(id => prompt(id)));
  assert.match(result.decisions[0].reason, /not written by the repository owner/);
  assert.match(result.decisions[1].reason, /not written by the repository owner/);
  assert.equal(result.selected.taskId, 'PSF-03', 'owner login matches even without OWNER association');
  assert.equal(ownerIssue({ repository: REPO, authorAssociation: 'MEMBER', author: 'x' }, REPO, 'tonygward'), false);
});

test('usage, scoped usage and an active job stop the whole run, and the queue is not walked down', async () => {
  const board = await snapshot([node({ number: 1, title: 'PSF-01: a' })]);
  const prompts = [prompt('PSF-01')];
  assert.match(pick(board, prompts, { usage: usageOk(60) }).blocker, /at or above 60%/);
  assert.match(pick(board, prompts, { usage: null }).blocker, /No verified/);
  assert.match(pick(board, prompts, { scopedUsagePercent: [61] }).blocker, /Scoped weekly usage/);
  assert.match(pick(board, prompts, { scopedUsagePercent: [NaN] }).blocker, /Scoped weekly usage/);
  assert.match(pick(board, prompts, { activeJob: 'job-1' }).blocker, /Active job job-1/);
});

test('non-issue cards, missing IDs, closed issues, duplicates and missing prompts are skipped with reasons', async () => {
  const board = await snapshot([
    node({ title: 'A draft', status: 'Todo' }), node({ number: 2, title: 'No id here' }), node({ number: 3, title: 'PSF-03: closed', state: 'CLOSED' }),
    node({ number: 4, title: 'PSF-04: first' }), node({ number: 5, title: 'PSF-04: duplicate' }), node({ number: 6, title: 'PSF-06: no prompt' })]);
  const reasons = pick(board, [prompt('PSF-03'), prompt('PSF-04')]).decisions.map(d => d.reason);
  assert.deepEqual(reasons, ['not an issue card (pull request or draft)', 'no task ID in issue title', 'issue is closed', 'selected', 'duplicate card for task', 'no canonical prompt found']);
});

test('tasks already claimed, interrupted, dead or complete are skipped', async () => {
  const board = await snapshot([node({ number: 1, title: 'PSF-01: a' })]);
  for (const state of ['claimed', 'interrupted', 'awaiting-review', 'complete', 'dead-letter', 'withdrawn']) {
    assert.equal(pick(board, [prompt('PSF-01')], { tasks: { 'PSF-01': { id: 'PSF-01', state } } }).selected, null, state);
  }
});

test('pull requests: open and merged are read, and only matrix/<ID> branches count as implementation', async () => {
  const pulls = [
    { number: 1, state: 'OPEN', title: 'PSF-05: manual work', headRefName: 'feature/x' },
    { number: 2, state: 'OPEN', title: 'unrelated', headRefName: 'matrix/AUTO-07-loop' },
    { number: 3, state: 'MERGED', title: 'x', headRefName: 'matrix/PSF-01-thing' },
    { number: 4, state: 'MERGED', title: 'PSF-02: mentions only', headRefName: 'docs/x' },
    { number: 5, state: 'MERGED', title: 'x', headRefName: 'housekeeping/archive-PSF-03' },
    { number: 6, state: 'MERGED', title: 'x', headRefName: 'matrix/core/loop' }];
  const result = await fetchPulls(combinedGraphql([[]], pulls), REPO);
  assert.equal(result.ok, true); assert.equal(result.pulls.length, 6);
  const { merged, open } = pullTaskState(result.pulls);
  assert.deepEqual([...merged], ['PSF-01']);
  assert.deepEqual([...open].sort(), ['AUTO-07', 'PSF-05']);
  assert.equal(matrixBranchTask({ headRefName: 'matrix/core/loop' }), null);
  assert.equal(matrixBranchTask({ headRefName: 'matrix/AUTO-07' }), 'AUTO-07');
});

test('a pull request read failure is reported, not swallowed', async () => {
  assert.match((await fetchPulls(async () => { throw new Error('boom'); }, REPO)).reason, /Pull request read failed: boom/);
  assert.match((await fetchPulls(async () => ({ data: {} }), REPO)).reason, /response missing/);
});

test('normaliseCard handles drafts and missing status', () => {
  const card = normaliseCard({ id: 'x', status: null, content: { __typename: 'DraftIssue', title: 'Draft' } }, 3);
  assert.deepEqual([card.position, card.status, card.issue, card.taskId, card.title], [3, null, null, null, 'Draft']);
});
