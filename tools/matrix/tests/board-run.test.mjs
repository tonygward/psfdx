import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { boardTick, refreshTasks, ghGraphql } from '../board-run.mjs';
import { reconcileDoing } from '../doing.mjs';
import { githubIo, commentMarker } from '../github-io.mjs';
import { extractIds, fetchIds } from '../board-ids.mjs';
import { readState, writeState, emptyState } from '../state.mjs';
import { dailyDue, londonDay } from '../policy.mjs';
import { validateConfig } from '../config.mjs';
import { node, combinedGraphql, fakeIo, goodBody, usageResult, prompt, REPO, NOW } from './fixtures.mjs';
import { normaliseCard } from '../board.mjs';

const temp = t => { const d = fs.mkdtempSync(path.join(os.tmpdir(), 'matrix-tick-')); t.after(() => fs.rmSync(d, { recursive: true, force: true })); return d; };
const REVISION = 'a'.repeat(40);
const file = id => `prompts/${id}-x.md`;
const promptFiles = (...ids) => new Map(ids.map(id => [file(id), `---\nid: ${id}\n---\n# ${id}\n`]));

function setup(t, { cards, pulls = [], files = promptFiles('PSF-01'), dryRun = true, usage = usageResult(), bodies = {}, io = fakeIo({ bodies }), handoff = false, extra = {} } = {}) {
  const dir = temp(t);
  const config = { stateDirectory: dir, idPrefixes: ['PSF', 'AUTO'], promptDirectory: 'prompts', repositorySlug: REPO, claudeUsage: { enabled: false },
    boardPickup: { enabled: true, dryRun, projectId: 'PVT_1', repository: REPO, ownerLogin: 'tonygward' } };
  const deps = { graphql: combinedGraphql([cards], pulls), io, loadUsage: () => usage, loadPrompts: async () => ({ revision: REVISION, files }),
    jobId: 'job-1', clock: () => NOW, handoff, ...extra };
  return { dir, config, deps, io };
}

test('disabled by default', async t => {
  const { config, deps } = setup(t, { cards: [] });
  config.boardPickup.enabled = false;
  assert.deepEqual(await boardTick(config, deps), { ran: false, reason: 'Board pickup is not enabled' });
});

test('a dry run reports the choice and the reasons, and writes nothing at all', async t => {
  const { dir, config, deps, io } = setup(t, { cards: [node({ number: 1, title: 'PSF-01: a', status: 'Todo' })], dryRun: true });
  const report = await boardTick(config, deps);
  assert.equal(report.dryRun, true); assert.equal(report.selected.taskId, 'PSF-01');
  assert.equal(report.decisions[0].reason, 'selected');
  assert.deepEqual(io.writes, []);
  assert.deepEqual(fs.readdirSync(dir), [], 'no state file, no hand-off, no log');
});

test('dryRun defaults to true when unset', async t => {
  const { dir, config, deps, io } = setup(t, { cards: [node({ number: 1, title: 'PSF-01: a' })] });
  delete config.boardPickup.dryRun;
  assert.equal((await boardTick(config, deps)).dryRun, true);
  assert.deepEqual(io.writes, []); assert.deepEqual(fs.readdirSync(dir), []);
});

test('a dry run on an issue with enough detail assesses it without writing', async t => {
  const { dir, config, deps, io } = setup(t, { cards: [node({ number: 2, title: 'PSF-02: new', status: 'Doing' })], files: new Map(), bodies: { 2: goodBody } });
  const report = await boardTick(config, deps);
  assert.equal(report.selected.taskId, 'PSF-02');
  assert.ok(report.selected.generated.text.includes('id: PSF-02'));
  assert.deepEqual(io.writes, []); assert.deepEqual(fs.readdirSync(dir), []);
});

test('a live tick claims one Todo card, moves it, comments, and uses the daily slot', async t => {
  const { dir, config, deps, io } = setup(t, { cards: [node({ number: 1, title: 'PSF-01: a', status: 'Todo' }), node({ number: 2, title: 'PSF-02: b', status: 'Todo' })], files: promptFiles('PSF-01', 'PSF-02'), dryRun: false });
  const report = await boardTick(config, deps);
  assert.equal(report.claim.claimed, true); assert.equal(report.selected.taskId, 'PSF-01');
  assert.deepEqual(io.writes.map(w => w.kind), ['doing', 'comment']);
  const state = readState(dir, { restart: false });
  assert.equal(state.tasks['PSF-01'].state, 'claimed'); assert.equal(state.tasks['PSF-02'].state, 'pending');
  assert.equal(state.lastWorkerDaily, londonDay(new Date(NOW)));
  // The same day, nothing more is picked up: one job is active and the slot is used.
  const again = await boardTick(config, deps);
  assert.equal(again.selected, null); assert.match(again.blocker, /Active job job-1/);
});

test('the Todo slot is closed after it has been used, but Doing still runs', async t => {
  const dir = temp(t);
  const s = emptyState(); s.lastWorkerDaily = londonDay(new Date(NOW)); writeState(dir, s);
  const cards = [node({ number: 1, title: 'PSF-01: a', status: 'Todo' }), node({ number: 2, title: 'PSF-02: b', status: 'Doing' })];
  const config = { stateDirectory: dir, idPrefixes: ['PSF'], promptDirectory: 'prompts', repositorySlug: REPO, boardPickup: { enabled: true, dryRun: true, projectId: 'p', repository: REPO, ownerLogin: 'tonygward' } };
  const deps = { graphql: combinedGraphql([cards]), io: fakeIo(), loadUsage: () => usageResult(), loadPrompts: async () => ({ revision: REVISION, files: promptFiles('PSF-01', 'PSF-02') }), jobId: 'j', clock: () => NOW };
  assert.equal((await boardTick(config, deps)).selected.taskId, 'PSF-02');
  config.boardPickup.projectId = 'p';
  deps.graphql = combinedGraphql([[cards[0]]]);
  assert.match((await boardTick(config, deps)).blocker, /No eligible card/);
});

test('Todo waits until after 02:00 London time', async t => {
  const { config, deps } = setup(t, { cards: [node({ number: 1, title: 'PSF-01: a', status: 'Todo' })] });
  deps.clock = () => Date.parse('2026-11-14T01:59:00Z');
  deps.loadUsage = () => usageResult(10, deps.clock());
  assert.match((await boardTick(config, deps)).blocker, /No eligible card/);
  deps.clock = () => Date.parse('2026-11-14T02:00:00Z');
  assert.equal((await boardTick(config, deps)).selected.taskId, 'PSF-01');
});

test('one Todo card per London day, including the clock changes', () => {
  // Spring forward: 29 March 2026, 01:00 GMT becomes 02:00 BST, so 02:00 London is 01:00 UTC.
  assert.equal(dailyDue('2026-03-28', '02:00', new Date('2026-03-29T00:59:00Z')), false);
  assert.equal(dailyDue('2026-03-28', '02:00', new Date('2026-03-29T01:00:00Z')), true);
  assert.equal(dailyDue('2026-03-29', '02:00', new Date('2026-03-29T05:00:00Z')), false);
  // Fall back: 25 October 2026, 02:00 BST becomes 01:00 GMT, so 02:00 London is 02:00 UTC.
  assert.equal(dailyDue('2026-10-24', '02:00', new Date('2026-10-25T01:30:00Z')), false);
  assert.equal(dailyDue('2026-10-24', '02:00', new Date('2026-10-25T02:00:00Z')), true);
  assert.equal(dailyDue('2026-10-25', '02:00', new Date('2026-10-25T23:59:00Z')), false);
  assert.equal(dailyDue('2026-10-25', '02:00', new Date('2026-10-26T02:00:00Z')), true);
});

test('a board read that fails closed picks nothing and writes nothing', async t => {
  const { dir, config, deps, io } = setup(t, { cards: [node({ number: 1, title: 'PSF-01: a' })], dryRun: false });
  deps.graphql = combinedGraphql([[node({ number: 1, title: 'PSF-01: a' })]], [], { views: 2 });
  const report = await boardTick(config, deps);
  assert.match(report.blocker, /1 view only/);
  assert.deepEqual(io.writes, []); assert.deepEqual(fs.readdirSync(dir), []);
});

test('blocked usage means no pickup this tick, with the reason', async t => {
  const { config, deps, io } = setup(t, { cards: [node({ number: 1, title: 'PSF-01: a' })], dryRun: false, usage: { allowed: false, reason: 'Weekly usage at or above 60%', extraUsageEnabled: false } });
  const report = await boardTick(config, deps);
  assert.equal(report.blocker, 'Weekly usage at or above 60%');
  assert.deepEqual(io.writes, []);
  const unknown = await boardTick(config, { ...deps, loadUsage: () => ({ ...usageResult(), extraUsageEnabled: null }) });
  assert.ok(unknown.blocker);
});

test('a broken prompt blocks new pickup but housekeeping still runs', async t => {
  const files = new Map([[file('PSF-01'), '---\nbogus: 1\n---\n']]);
  let ran = false;
  const { config, deps } = setup(t, { cards: [node({ number: 1, title: 'PSF-01: a' })], files, dryRun: false, extra: { housekeeping: [async () => { ran = true; }] } });
  const report = await boardTick(config, deps);
  assert.match(report.blocker, /Nothing new is picked up: Prompt scan has 1 error/);
  assert.equal(ran, true);
});

test('merged work is not recoded and is recorded for delivery', async t => {
  const cards = [node({ number: 1, title: 'PSF-01: a', status: 'Doing' }), node({ number: 2, title: 'PSF-02: b', status: 'Doing' })];
  const pulls = [{ number: 9, state: 'MERGED', title: 'x', headRefName: 'matrix/PSF-01-a' }];
  const { dir, config, deps } = setup(t, { cards, pulls, files: promptFiles('PSF-01', 'PSF-02'), dryRun: false });
  const report = await boardTick(config, deps);
  assert.equal(report.selected.taskId, 'PSF-02');
  assert.equal(report.decisions.find(d => d.taskId === 'PSF-01').reason, 'implementation merged; delivery pending, do not recode');
  assert.ok(readState(dir, { restart: false }).tasks['PSF-02']);
});

test('a hand-off tick writes board-handoff.json and claims nothing', async t => {
  const { dir, config, deps, io } = setup(t, { cards: [node({ number: 1, title: 'PSF-01: a', status: 'Doing' })], dryRun: false, handoff: true });
  const report = await boardTick(config, deps);
  assert.equal(report.handoff, true);
  assert.ok(fs.existsSync(path.join(dir, 'board-handoff.json')));
  assert.equal(readState(dir, { restart: false }).tasks['PSF-01'].state, 'pending');
  assert.deepEqual(io.writes, []);
});

test('refreshTasks keeps a live claim intact', () => {
  const state = emptyState(); state.tasks['PSF-01'] = { id: 'PSF-01', state: 'claimed', job: 'j', hash: 'old' };
  refreshTasks(state, [prompt('PSF-01', { hash: 'new' }), prompt('PSF-02')], REVISION);
  assert.equal(state.tasks['PSF-01'].state, 'claimed'); assert.equal(state.tasks['PSF-01'].hash, 'old');
  assert.equal(state.tasks['PSF-02'].state, 'pending');
});

test('Doing reconciliation finds each kind of card', () => {
  const cards = [
    node({ number: 1, title: 'PSF-01: requested', status: 'Doing' }), node({ number: 2, title: 'PSF-02: active', status: 'Doing' }),
    node({ number: 3, title: 'PSF-03: in review', status: 'Doing' }), node({ number: 4, title: 'PSF-04: merged', status: 'Doing' }),
    node({ number: 5, title: 'PSF-05: no prompt', status: 'Doing' }), node({ number: 6, title: 'PSF-06: interrupted', status: 'Doing' })];
  const snapshot = { ok: true, cards: cards.map((n, i) => normaliseCard(n, i)) };
  const pulls = [{ number: 30, state: 'OPEN', title: 'x', headRefName: 'matrix/PSF-03' }, { number: 40, state: 'MERGED', title: 'x', headRefName: 'matrix/PSF-04' }];
  const tasks = { 'PSF-02': { id: 'PSF-02', state: 'claimed', job: 'j' }, 'PSF-06': { id: 'PSF-06', state: 'interrupted' } };
  const ids = ['PSF-01', 'PSF-02', 'PSF-03', 'PSF-04', 'PSF-06'];
  const result = reconcileDoing(snapshot, ids.map(id => prompt(id)), pulls, tasks);
  assert.deepEqual(result.findings.map(f => f.kind), ['requested', 'active', 'in-review', 'delivery-pending', 'unready', 'blocked']);
  assert.equal(result.enableAllowed, false, 'an interrupted card blocks enabling until a person decides');
});

test('Doing reconciliation flags disagreements between the board and the state', () => {
  const snapshot = { ok: true, cards: [normaliseCard(node({ number: 1, title: 'PSF-01: a', status: 'Backlog' }), 0), normaliseCard(node({ number: 2, title: 'PSF-02: closed', status: 'Doing', state: 'CLOSED' }), 1)] };
  const result = reconcileDoing(snapshot, [prompt('PSF-01'), prompt('PSF-02')], [], { 'PSF-01': { id: 'PSF-01', state: 'claimed' } });
  assert.deepEqual(result.findings.map(f => f.kind), ['inconsistent', 'inconsistent']);
  assert.equal(reconcileDoing({ ok: false, reason: 'x' }, [], [], {}).ok, false);
});

test('github io: markers, moves with the configured IDs, and no shell', async () => {
  const calls = [];
  const gh = async args => { calls.push(args); return args[0] === 'issue' && args.includes('comments') ? JSON.stringify({ comments: [{ body: `hi ${commentMarker('pickup', 'PSF-01', 'j')}` }] }) : args.includes('body') ? JSON.stringify({ body: 'text' }) : ''; };
  const io = githubIo(gh, { projectId: 'P', statusFieldId: 'F', options: { doing: 'D', blocked: 'B', done: 'X' } });
  assert.equal(await io.hasComment(REPO, 1, commentMarker('pickup', 'PSF-01', 'j')), true);
  assert.equal(await io.hasComment(REPO, 1, commentMarker('pickup', 'PSF-01', 'other')), false);
  assert.equal(await io.issueBody(REPO, 1), 'text');
  await io.comment(REPO, 1, 'a "quoted" $(body)');
  await io.moveToDoing('item-1'); await io.moveToBlocked('item-2'); await io.moveToDone('item-3');
  assert.deepEqual(calls.find(a => a[1] === 'comment'), ['issue', 'comment', '1', '--repo', REPO, '--body', 'a "quoted" $(body)']);
  const moves = calls.filter(a => a[0] === 'api').map(a => a.filter(x => /^(i|o)=/.test(x)).join(','));
  assert.deepEqual(moves, ['i=item-1,o=D', 'i=item-2,o=B', 'i=item-3,o=X']);
  assert.equal(commentMarker('kind', 'PSF-01', 'd'), '<!-- matrix:kind:PSF-01:d -->');
});

test('github io: a missing field is an error and a failed write is never reported as success', async () => {
  const io = githubIo(async () => '', { projectId: 'P', statusFieldId: 'F', options: {} });
  await assert.rejects(io.moveToDoing('i'), /Doing field is not configured|doing field is not configured/i);
  const failing = githubIo(async () => { throw new Error('403'); }, { projectId: 'P', statusFieldId: 'F', options: { done: 'X' } });
  await assert.rejects(failing.moveToDone('i'), /403/);
  await assert.rejects(failing.comment(REPO, 1, 'x'), /403/);
});

test('ghGraphql passes variables as typed arguments and parses the reply', async () => {
  const seen = [];
  const graphql = ghGraphql(async args => { seen.push(args); return '{"data":{"ok":true}}'; });
  assert.deepEqual(await graphql('query', { id: 'X', after: null, n: 3, states: ['OPEN'] }), { data: { ok: true } });
  assert.deepEqual(seen[0], ['api', 'graphql', '-f', 'query=query', '-f', 'id=X', '-F', 'n=3', '-f', 'states[]=OPEN']);
});

test('board-ids prints the IDs and explains what is missing', () => {
  const response = { data: { user: { projectV2: { id: 'PVT_1', title: 'Psfdx', fields: { nodes: [{}, { id: 'F1', name: 'Status', options: ['Backlog', 'Todo', 'Doing', 'Blocked', 'Done'].map(name => ({ id: `o-${name}`, name })) }] } } } } };
  assert.deepEqual(extractIds(response), { projectId: 'PVT_1', statusFieldId: 'F1', options: { backlog: 'o-Backlog', todo: 'o-Todo', doing: 'o-Doing', blocked: 'o-Blocked', done: 'o-Done' } });
  assert.throws(() => extractIds({ data: { user: null } }), /Project not found/);
  const noBlocked = structuredClone(response); noBlocked.data.user.projectV2.fields.nodes[1].options.splice(3, 1);
  assert.throws(() => extractIds(noBlocked), /no option named Blocked/);
  assert.throws(() => extractIds({ data: { user: { projectV2: { id: 'x', fields: { nodes: [] } } } } }), /no single-select field named Status/);
  const run = (exe, args, options) => { assert.equal(exe, 'gh'); assert.equal(options.shell, false); return { status: 0, stdout: JSON.stringify(response) }; };
  assert.equal(fetchIds('tonygward', 3, { run }).statusFieldId, 'F1');
  assert.throws(() => fetchIds('tonygward', 3, { run: () => ({ status: 1, stdout: '' }) }), /gh could not read/);
});

test('boardPickup configuration is validated, and complete once enabled', () => {
  const base = { repositorySlug: REPO, baseBranch: 'main', stateDirectory: '/s', worktreeRoot: '/w', promptDirectory: 'prompts', idPrefixes: ['PSF'] };
  const board = { enabled: true, dryRun: true, projectId: 'P', statusFieldId: 'F', ownerLogin: 'tonygward', tokenFile: '/secrets/t', repository: REPO,
    options: { backlog: 'a', todo: 'b', doing: 'c', blocked: 'd', done: 'e' } };
  assert.doesNotThrow(() => validateConfig({ ...base, boardPickup: board }));
  assert.doesNotThrow(() => validateConfig({ ...base, boardPickup: { enabled: false } }));
  for (const bad of [{ ...board, surprise: 1 }, { ...board, enabled: 'yes' }, { ...board, tokenFile: 'relative' }, { ...board, projectId: undefined },
    { ...board, options: { ...board.options, done: undefined } }, { ...board, options: { ...board.options, extra: 'x' } }, { ...board, repository: 'bad' }]) {
    assert.throws(() => validateConfig({ ...base, boardPickup: bad }), /Invalid Matrix configuration/);
  }
});
