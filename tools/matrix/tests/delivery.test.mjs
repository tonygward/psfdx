import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { verifyDelivery, advanceDelivery, finalComment, finalMarker, blockerMarker, recordMerge } from '../delivery.mjs';
import { verifyMerge, verifyVersion, verifyRelease, verifyNotes, verifyPromptArchived, verifyGallery, isDocsOnly, readIo, DOCS_ONLY_PATTERNS } from '../verifiers.mjs';
import { emptyState, writeState, readState } from '../state.mjs';
import { syncMerges } from '../board-run.mjs';
import { standardHousekeeping } from '../housekeeping.mjs';
import { validateConfig } from '../config.mjs';
import { fakeIo, REPO } from './fixtures.mjs';

const temp = t => { const d = fs.mkdtempSync(path.join(os.tmpdir(), 'matrix-delivery-')); t.after(() => fs.rmSync(d, { recursive: true, force: true })); return d; };
const MERGE = 'a'.repeat(40), BUMP = 'b'.repeat(40);
const NOTES = '### Added\n\n- psfdx-logs: a thing.';
const CHANGELOG = `# Changelog\n\n## Unreleased\n\n## 0.8.1 - 2026-11-14\n\n${NOTES}\n\n## 0.8.0 - 2026-01-01\n\n- old\n`;

// A fake io: reads are configurable, writes are recorded and can be made to fail.
function world(over = {}) {
  const w = {
    writes: [], fail: {}, pullFilesList: ['psfdx-logs/psfdx-logs.psm1'],
    pull: { state: 'MERGED', mergeSha: MERGE, url: `https://github.com/${REPO}/pull/12` },
    commits: [{ sha: 'x1', subject: 'Other merge' }, { sha: BUMP, subject: '[release] 0.8.1' }],
    release: { tagName: 'v0.8.1', url: `https://github.com/${REPO}/releases/tag/v0.8.1`, isDraft: false, isPrerelease: false, body: NOTES, assets: [{ name: 'psfdx-0.8.1.zip', size: 1234 }] },
    tagSha: BUMP, changelog: CHANGELOG, archived: true, gallery: false, comments: [], ...over,
  };
  const io = {
    pull: async () => w.pull, pullFiles: async () => w.pullFilesList, commitsAfter: async () => w.commits,
    release: async () => w.release, tagCommit: async () => w.tagSha, fileAt: async () => w.changelog, fileExists: async () => w.archived,
    galleryHas: async () => { if (w.galleryThrows) throw new Error('503'); return w.gallery; },
    hasComment: async (r, i, marker) => w.comments.some(c => c.includes(marker)),
    comment: async (r, i, body) => { if (w.fail.comment) throw new Error('network down'); w.comments.push(body); w.writes.push('comment'); },
    closeIssue: async () => { if (w.fail.close) throw new Error('403'); w.writes.push('close'); },
    moveToDone: async () => { if (w.fail.done) throw new Error('board down'); w.writes.push('done'); },
  };
  w.io = io; return w;
}
const delivery = (extra = {}) => ({ stage: 'pending', repository: REPO, pull: 12, issue: 1, itemId: 'item-1', job: 'job-1', prompt: 'prompts/PSF-01-x.md', ...extra });
const seed = (dir, d = delivery(), task = {}) => { const s = emptyState(); s.tasks['PSF-01'] = { id: 'PSF-01', state: 'awaiting-review', job: 'job-1', ...task }; s.deliveries = { 'PSF-01': d }; writeState(dir, s); };
const stage = dir => readState(dir, { restart: false }).deliveries['PSF-01'].stage;

test('a fully delivered change verifies and records the evidence', async () => {
  const w = world();
  const result = await verifyDelivery(delivery(), w.io);
  assert.equal(result.verified, true); assert.deepEqual(result.missing, []);
  assert.deepEqual(result.evidence.pull, { number: 12, url: w.pull.url, mergeSha: MERGE });
  assert.deepEqual(result.evidence.release, { tag: 'v0.8.1', url: w.release.url, version: '0.8.1', asset: 'psfdx-0.8.1.zip', bumpSha: BUMP });
});

test('1. merge: an open or unmerged pull request is not delivery', async () => {
  for (const pull of [{ state: 'OPEN', mergeSha: null }, { state: 'MERGED', mergeSha: null }, { state: 'CLOSED', mergeSha: null }]) {
    assert.deepEqual((await verifyDelivery(delivery(), world({ pull }).io)).missing, ['Pull request is not merged']);
  }
  assert.equal((await verifyMerge(world().io, delivery())).evidence.mergeSha, MERGE);
});

test('2. version: the first [release] commit after the merge, and none yet is waiting', async () => {
  const io = world().io;
  assert.deepEqual((await verifyVersion(io, REPO, MERGE)).evidence, { version: '0.8.1', bumpSha: BUMP });
  const two = world({ commits: [{ sha: 'r1', subject: '[release] 0.8.1' }, { sha: 'r2', subject: '[release] 0.8.2' }] }).io;
  assert.equal((await verifyVersion(two, REPO, MERGE)).evidence.bumpSha, 'r1', 'the first one is the evidence');
  for (const commits of [[], [{ sha: 'x', subject: 'Release 0.8.1' }], [{ sha: 'x', subject: '[release] 0.8' }, { sha: 'y', subject: 'fix: [release] 0.8.1' }]]) {
    assert.deepEqual((await verifyVersion(world({ commits }).io, REPO, MERGE)).missing, ['No [release] commit on main after the merge yet']);
  }
});

test('two tasks that merge before one bump are both delivered by that release', async () => {
  const w = world();
  const a = await verifyDelivery(delivery({ pull: 12 }), w.io), b = await verifyDelivery(delivery({ pull: 13 }), w.io);
  assert.equal(a.evidence.release.version, '0.8.1'); assert.equal(b.evidence.release.version, '0.8.1');
  assert.ok(a.verified && b.verified);
});

test('3. release: missing, draft, pre-release, wrong tag, wrong or extra or empty assets', async () => {
  const check = async over => (await verifyDelivery(delivery(), world(over).io)).missing;
  assert.deepEqual(await check({ release: null }), ['No GitHub release v0.8.1 yet']);
  assert.match((await check({ release: { ...world().release, isDraft: true } }))[0], /still a draft/);
  assert.match((await check({ release: { ...world().release, isPrerelease: true } }))[0], /pre-release/);
  assert.match((await check({ tagSha: 'd'.repeat(40) }))[0], /Tag v0\.8\.1 points at ddddddd, not the bump commit bbbbbbb/);
  const extra = { ...world().release, assets: [{ name: 'psfdx-0.8.1.zip', size: 5 }, { name: 'notes.txt', size: 1 }] };
  assert.match((await check({ release: extra }))[0], /exactly one asset, psfdx-0\.8\.1\.zip; it has psfdx-0\.8\.1\.zip, notes\.txt/);
  assert.match((await check({ release: { ...world().release, assets: [] } }))[0], /it has none/);
  assert.match((await check({ release: { ...world().release, assets: [{ name: 'psfdx-0.8.0.zip', size: 5 }] } }))[0], /exactly one asset/);
  assert.match((await check({ release: { ...world().release, assets: [{ name: 'psfdx-0.8.1.zip', size: 0 }] } }))[0], /is empty/);
});

test('4. notes: empty, different from the changelog section, or a changelog without the version', async () => {
  assert.match((await verifyDelivery(delivery(), world({ release: { ...world().release, body: '  ' } }).io)).missing[0], /has no notes/);
  assert.match((await verifyDelivery(delivery(), world({ release: { ...world().release, body: 'Something else' } }).io)).missing[0], /do not match/);
  assert.match((await verifyDelivery(delivery(), world({ changelog: '# Changelog\n\n## Unreleased\n' }).io)).missing[0], /no section for 0\.8\.1/);
  const crlf = world({ release: { ...world().release, body: NOTES.replace(/\n/g, '\r\n') } });
  assert.equal((await verifyDelivery(delivery(), crlf.io)).verified, true, 'line endings do not matter');
  assert.equal((await verifyNotes(world().io, REPO, '0.8.1', { body: NOTES })).ok, true);
});

test('5. prompt archived: missing is reported, a task without a prompt file is not blocked on it', async () => {
  assert.match((await verifyDelivery(delivery(), world({ archived: false }).io)).missing[0], /not archived in prompts\/done\/ yet: PSF-01-x\.md/);
  assert.equal((await verifyPromptArchived(world().io, REPO, null)).ok, true);
  let asked; const io = { ...world().io, fileExists: async (r, file, ref) => { asked = [file, ref]; return true; } };
  await verifyPromptArchived(io, REPO, 'prompts/AUTO-07-loop.md');
  assert.deepEqual(asked, ['prompts/done/AUTO-07-loop.md', 'main']);
});

test('6. the Gallery is only checked when switched on, and the comment says so while it is off', async () => {
  const off = await verifyDelivery(delivery(), world().io, { psGallery: false });
  assert.equal(off.verified, true);
  assert.match(finalComment({ taskId: 'PSF-01', job: 'j', evidence: off.evidence }), /Not published to the PowerShell Gallery yet/);
  const missing = await verifyDelivery(delivery(), world({ gallery: false }).io, { psGallery: true });
  assert.deepEqual(missing.missing, ['The psfdx package 0.8.1 is not on the PowerShell Gallery yet']);
  const on = await verifyDelivery(delivery(), world({ gallery: true }).io, { psGallery: true });
  assert.equal(on.verified, true);
  const text = finalComment({ taskId: 'PSF-01', job: 'j', evidence: on.evidence });
  assert.match(text, /Install-Module psfdx -RequiredVersion 0\.8\.1/); assert.match(text, /powershellgallery\.com\/packages\/psfdx\/0\.8\.1/);
  const unavailable = await verifyDelivery(delivery(), world({ galleryThrows: true }).io, { psGallery: true });
  assert.match(unavailable.missing[0], /PowerShell Gallery could not be verified: 503/);
  assert.equal((await verifyGallery(world({ gallery: true }).io, '0.8.1')).ok, true);
});

test('a docs-only task needs no release: versions, release and notes are replaced by one plain sentence', async () => {
  const w = world({ pullFilesList: ['prompts/AUTO-01-x.md', 'docs/execution-policy.md', 'CLAUDE.md'], commits: [], release: null });
  const result = await verifyDelivery(delivery(), w.io);
  assert.equal(result.verified, true); assert.equal(result.evidence.docsOnly, true);
  assert.match(finalComment({ taskId: 'AUTO-01', job: 'j', evidence: result.evidence }), /No release needed \(docs only\)/);
  assert.doesNotMatch(finalComment({ taskId: 'AUTO-01', job: 'j', evidence: result.evidence }), /Download|Gallery/);
  const stillNeedsArchive = await verifyDelivery(delivery(), world({ pullFilesList: ['prompts/x.md'], archived: false }).io);
  assert.equal(stillNeedsArchive.verified, false);
  assert.equal(isDocsOnly(['psfdx/x.psm1', 'docs/x.md']), false); assert.equal(isDocsOnly([]), false); assert.equal(isDocsOnly(['tools/matrix/x.mjs', 'images/a.png']), true);
});

test('the docs-only rule matches the CI and bump workflows', () => {
  for (const file of ['ci.yml', 'cd-bump-version.yml']) {
    const text = fs.readFileSync(new URL(`../../../.github/workflows/${file}`, import.meta.url), 'utf8');
    const line = /^\s*\*\.md\|[^)]*\) ;;/m.exec(text)?.[0];
    assert.ok(line, `${file} has the docs-only case line`);
    const globs = line.trim().replace(/\) ;;$/, '').split('|');
    const covers = sample => globs.some(g => new RegExp(`^${g.replace(/[.+?^${}()[\]\\]/g, '\\$&').replace(/\*/g, '.*')}$`).test(sample));
    for (const sample of ['README.md', 'prompts/x.txt', 'docs/a/b.txt', 'tools/matrix/x.mjs', 'images/x.bin', 'a.png', 'a.jpg', 'a.jpeg', 'a.gif', 'a.svg']) assert.equal(covers(sample), true, `${file}: ${sample}`);
    for (const sample of ['psfdx/x.psm1', 'scripts/x.mjs', '.github/workflows/ci.yml', 'VERSION', 'modules.ps1']) assert.equal(covers(sample), false, `${file}: ${sample}`);
  }
  assert.ok(DOCS_ONLY_PATTERNS.length >= 6);
});

test('a verifier that throws cannot hide the others, and a failure to list the files stops verification', async () => {
  const w = world({ archived: false }); w.io.release = async () => { throw new Error('API 500'); };
  const result = await verifyDelivery(delivery(), w.io);
  assert.match(result.missing[0], /Release could not be verified: API 500/); assert.match(result.missing[1], /not archived/);
  const files = world(); files.io.pullFiles = async () => { throw new Error('boom'); };
  assert.match((await verifyDelivery(delivery(), files.io)).missing[0], /Changed files could not be verified: boom/);
  const merge = world(); merge.io.pull = async () => { throw new Error('gh failed'); };
  assert.match((await verifyDelivery(delivery(), merge.io)).missing[0], /Verification could not complete: gh failed/);
});

test('missing delivery: one comment listing what is missing, repeated only when the list changes; issue open, card in Doing', async t => {
  const dir = temp(t); seed(dir);
  const w = world({ release: null });
  const first = await advanceDelivery(dir, 'PSF-01', w.io);
  assert.equal(first.stage, 'pending'); assert.match(first.blocked, /No GitHub release v0\.8\.1 yet/);
  assert.equal(w.comments.length, 1); assert.match(w.comments[0], /merged, waiting for delivery/); assert.deepEqual(w.writes, ['comment']);
  await advanceDelivery(dir, 'PSF-01', w.io);
  assert.equal(w.comments.length, 1, 'the same missing list is not repeated');
  w.release = { ...world().release, assets: [] };
  await advanceDelivery(dir, 'PSF-01', w.io);
  assert.equal(w.comments.length, 2, 'a changed list is a new comment');
  assert.ok(!w.writes.includes('close') && !w.writes.includes('done'));
  assert.equal(stage(dir), 'pending');
  assert.match(w.comments[0], new RegExp(blockerMarker('PSF-01', '[0-9a-f]{12}').replace(/[<>!]/g, m => `\\${m}`)));
});

test('the full path: verified, one final comment, issue closed, card Done, task complete', async t => {
  const dir = temp(t); seed(dir);
  const w = world();
  const result = await advanceDelivery(dir, 'PSF-01', w.io, { now: () => '2026-11-14T12:00:00Z' });
  assert.deepEqual(result, { stage: 'done', blocked: null });
  assert.deepEqual(w.writes, ['comment', 'close', 'done']);
  assert.ok(w.comments[0].startsWith(finalMarker('PSF-01')));
  assert.match(w.comments[0], /Pull request: https[\s\S]*merge commit `aaaaaaaaaaaa`[\s\S]*Release: v0\.8\.1[\s\S]*Download: https[\s\S]*psfdx-0\.8\.1\.zip/);
  const state = readState(dir, { restart: false });
  assert.equal(state.deliveries['PSF-01'].doneAt, '2026-11-14T12:00:00Z'); assert.equal(state.tasks['PSF-01'].state, 'complete');
  assert.deepEqual(await advanceDelivery(dir, 'PSF-01', w.io), { stage: 'done', blocked: null });
  assert.deepEqual(w.writes, ['comment', 'close', 'done'], 'nothing is repeated');
});

test('a failed final comment blocks closing and Done, and retrying posts it once', async t => {
  const dir = temp(t); seed(dir);
  const w = world(); w.fail.comment = true;
  const result = await advanceDelivery(dir, 'PSF-01', w.io);
  assert.match(result.blocked, /Final comment failed: network down/);
  assert.equal(stage(dir), 'verified'); assert.deepEqual(w.writes, []);
  w.fail.comment = false;
  assert.equal((await advanceDelivery(dir, 'PSF-01', w.io)).stage, 'done');
  assert.equal(w.comments.length, 1); assert.deepEqual(w.writes, ['comment', 'close', 'done']);
});

test('a failed close retries on its own without a second comment', async t => {
  const dir = temp(t); seed(dir);
  const w = world(); w.fail.close = true;
  assert.match((await advanceDelivery(dir, 'PSF-01', w.io)).blocked, /Closing the issue failed: 403/);
  assert.equal(stage(dir), 'commented');
  w.fail.close = false;
  assert.equal((await advanceDelivery(dir, 'PSF-01', w.io)).stage, 'done');
  assert.equal(w.comments.length, 1, 'no second comment');
});

test('a failed Done retries on its own; the card stays in Doing until it works', async t => {
  const dir = temp(t); seed(dir);
  const w = world(); w.fail.done = true;
  assert.match((await advanceDelivery(dir, 'PSF-01', w.io)).blocked, /Setting the card to Done failed: board down/);
  assert.equal(stage(dir), 'closed'); assert.equal(readState(dir, { restart: false }).tasks['PSF-01'].state, 'awaiting-review');
  w.fail.done = false;
  assert.equal((await advanceDelivery(dir, 'PSF-01', w.io)).stage, 'done');
  assert.deepEqual(w.writes.filter(x => x === 'close'), ['close'].slice(0, 1), 'closed once');
});

test('a restart between every stage resumes at that stage and never repeats an earlier write', async t => {
  for (const failing of ['comment', 'close', 'done']) {
    const dir = temp(t); seed(dir);
    const first = world(); first.fail[failing] = true;
    await advanceDelivery(dir, 'PSF-01', first.io);
    // A brand new io (as after a restart): the comment marker is already on the issue for stages after the comment.
    const second = world({ comments: first.comments }); second.fail = {};
    const result = await advanceDelivery(dir, 'PSF-01', second.io);
    assert.equal(result.stage, 'done', failing);
    const all = [...first.writes, ...second.writes];
    assert.equal(all.filter(x => x === 'comment').length, 1, `${failing}: one final comment`);
    assert.equal(all.filter(x => x === 'close').length, 1, `${failing}: closed once`);
    assert.equal(all.filter(x => x === 'done').length, 1, `${failing}: Done once`);
  }
});

test('a crash after commenting but before saving does not post twice (the marker is checked)', async t => {
  const dir = temp(t); seed(dir, delivery({ stage: 'verified', evidence: { pull: { number: 12, url: 'u', mergeSha: MERGE }, release: { tag: 'v0.8.1', url: 'r', version: '0.8.1', asset: 'psfdx-0.8.1.zip' }, psGallery: { enabled: false } } }));
  const w = world({ comments: [finalMarker('PSF-01')] });
  assert.equal((await advanceDelivery(dir, 'PSF-01', w.io)).stage, 'done');
  assert.equal(w.writes.filter(x => x === 'comment').length, 0);
});

test('no delivery recorded is reported, not invented', async t => {
  const dir = temp(t); writeState(dir, emptyState());
  assert.deepEqual(await advanceDelivery(dir, 'PSF-01', world().io), { stage: null, blocked: 'No delivery recorded for this task' });
});

test('a merged Matrix pull request enters delivery once; work with no pickup record is refused', () => {
  const state = emptyState();
  state.tasks['PSF-01'] = { id: 'PSF-01', state: 'awaiting-review', job: 'job-1', issue: 1, itemId: 'item-1', repository: REPO, file: 'prompts/PSF-01-x.md' };
  const pulls = [{ number: 12, state: 'MERGED', headRefName: 'matrix/PSF-01-x', repository: REPO }, { number: 13, state: 'MERGED', headRefName: 'docs/mention-PSF-01', repository: REPO }];
  assert.deepEqual(syncMerges(state, pulls), ['PSF-01']);
  assert.deepEqual(syncMerges(state, pulls), [], 'recorded once');
  assert.equal(state.deliveries['PSF-01'].pull, 12); assert.equal(state.deliveries['PSF-01'].prompt, 'prompts/PSF-01-x.md');
  assert.throws(() => recordMerge(emptyState(), 'PSF-09', { pull: 1 }), /no pickup record/);
});

test('the delivery step runs from the board tick for every unfinished delivery', async t => {
  const dir = temp(t); seed(dir);
  const w = world();
  const step = standardHousekeeping()[2];
  await step({ dir, io: w.io, config: { delivery: { psGallery: { enabled: false } } } });
  assert.equal(stage(dir), 'done');
  const gallery = temp(t); seed(gallery);
  const g = world({ gallery: false });
  await step({ dir: gallery, io: g.io, config: { delivery: { psGallery: { enabled: true } } } });
  assert.equal(stage(gallery), 'pending');
});

test('the real readers call gh with fixed arguments and no shell, and decode missing files as false', async () => {
  const calls = [];
  const gh = async args => {
    calls.push(args);
    if (args[0] === 'pr') return JSON.stringify({ state: 'MERGED', mergeCommit: { oid: MERGE }, url: 'u' });
    if (args.some(a => a.includes('/compare/'))) return `{"sha":"s1","subject":"Other"}\n{"sha":"${BUMP}","subject":"[release] 0.8.1"}\n`;
    if (args.some(a => a.includes('contents/prompts/done/missing.md'))) throw Object.assign(new Error('gh: Not Found (HTTP 404)'), { stderr: '' });
    if (args.some(a => a.includes('contents/prompts/done/broken.md'))) throw new Error('HTTP 500');
    if (args[0] === 'release') throw new Error('release not found');
    return '.sha-output\n';
  };
  const io = readIo(gh);
  assert.deepEqual(await io.pull(REPO, 12), { state: 'MERGED', mergeSha: MERGE, url: 'u' });
  assert.deepEqual((await io.commitsAfter(REPO, MERGE)).map(c => c.subject), ['Other', '[release] 0.8.1']);
  assert.ok(calls.find(a => a.some(x => x.includes(`compare/${MERGE}...main`))));
  assert.equal(await io.release(REPO, 'v9.9.9'), null, 'a missing release is null, not an error');
  assert.equal(await io.fileExists(REPO, 'prompts/done/missing.md', 'main'), false);
  await assert.rejects(io.fileExists(REPO, 'prompts/done/broken.md', 'main'), /HTTP 500/);
  assert.equal(await io.tagCommit(REPO, 'v0.8.1'), '.sha-output');
  await io.fileAt(REPO, 'CHANGELOG.md', 'v0.8.1');
  assert.deepEqual(calls.at(-1), ['api', '-H', 'Accept: application/vnd.github.raw', `repos/${REPO}/contents/CHANGELOG.md?ref=v0.8.1`]);
});

test('the Gallery reader maps 200 to listed, 404 to not listed, and anything else to an error', async () => {
  const reader = status => readIo(async () => '', { fetchFn: async url => { assert.match(url, /Packages\(Id='psfdx',Version='0\.8\.1'\)/); return { status }; } });
  assert.equal(await reader(200).galleryHas('0.8.1'), true);
  assert.equal(await reader(404).galleryHas('0.8.1'), false);
  await assert.rejects(reader(503).galleryHas('0.8.1'), /returned 503/);
});

test('delivery configuration only allows psGallery.enabled', () => {
  const base = { repositorySlug: REPO, baseBranch: 'main', stateDirectory: '/s', worktreeRoot: '/w', promptDirectory: 'prompts', idPrefixes: ['PSF'] };
  assert.doesNotThrow(() => validateConfig({ ...base, delivery: { psGallery: { enabled: true } } }));
  assert.doesNotThrow(() => validateConfig({ ...base, delivery: {} }));
  for (const bad of [{ other: 1 }, { psGallery: { enabled: 'yes' } }, { psGallery: { enabled: true, extra: 1 } }, { psGallery: null }, []]) {
    assert.throws(() => validateConfig({ ...base, delivery: bad }), /Invalid Matrix configuration/);
  }
});
