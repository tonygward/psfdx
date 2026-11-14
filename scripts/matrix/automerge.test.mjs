import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  evaluate, inScope, inCoreScope, promptIdFromBranch, archivePath, markDone, rebaseLinks, relinkMoved,
  BUILD_RUN, CORE_RUN, REQUIRED_JOBS, CORE_STATEMENT, ARCHIVE_STATEMENT,
} from './automerge.mjs';

const SHA = 'a'.repeat(40);
const goodJobs = REQUIRED_JOBS.map(name => ({ name, conclusion: 'success' }));

function task(overrides = {}) {
  return {
    repository: 'tonygward/psfdx',
    agentLogin: 'agent',
    pr: {
      state: 'OPEN', baseRefName: 'main', headRefName: 'matrix/PSF-12-field-usage', headRefOid: SHA,
      headRepository: 'tonygward/psfdx', author: 'agent', body: 'Implements PSF-12.\n\nMatrix job: job-123\n',
    },
    files: ['psfdx-logs/psfdx-logs.psm1', 'tests/x.Tests.ps1', 'CHANGELOG.md'],
    jobs: goodJobs,
    otherRuns: [],
    run: { name: BUILD_RUN, conclusion: 'success', event: 'pull_request', head_sha: SHA },
    ...overrides,
  };
}
const withPr = (facts, patch) => ({ ...facts, pr: { ...facts.pr, ...patch } });

test('a clean Matrix pull request merges', () => {
  const result = evaluate(task());
  assert.deepEqual(result, { merge: true, reasons: [], lane: 'task' });
});

test('a person (not the agent) never merges', () => {
  const result = evaluate(withPr(task(), { author: 'someone-else' }));
  assert.equal(result.merge, false);
  assert.match(result.reasons.join(), /agent identity/);
});

test('missing agentLogin refuses', () => {
  assert.equal(evaluate(task({ agentLogin: undefined })).merge, false);
});

test('missing Matrix job line refuses', () => {
  const result = evaluate(withPr(task(), { body: 'Implements PSF-12.' }));
  assert.match(result.reasons.join(), /Matrix job/);
});

test('a non-matrix branch refuses', () => {
  assert.equal(evaluate(withPr(task(), { headRefName: 'feature/x' })).merge, false);
});

test('a fork pull request refuses', () => {
  const result = evaluate(withPr(task(), { headRepository: 'evil/psfdx' }));
  assert.match(result.reasons.join(), /another repository/);
});

test('a closed pull request or wrong base refuses', () => {
  assert.equal(evaluate(withPr(task(), { state: 'CLOSED' })).merge, false);
  assert.equal(evaluate(withPr(task(), { baseRefName: 'master' })).merge, false);
});

test('a stale head refuses', () => {
  const result = evaluate(task({ run: { name: BUILD_RUN, conclusion: 'success', event: 'pull_request', head_sha: 'b'.repeat(40) } }));
  assert.match(result.reasons.join(), /older commit/);
});

test('a failed or wrong run refuses', () => {
  assert.equal(evaluate(task({ run: { name: BUILD_RUN, conclusion: 'failure', event: 'pull_request', head_sha: SHA } })).merge, false);
  assert.equal(evaluate(task({ run: { name: 'Other', conclusion: 'success', event: 'pull_request', head_sha: SHA } })).merge, false);
  assert.equal(evaluate(task({ run: { name: BUILD_RUN, conclusion: 'success', event: 'push', head_sha: SHA } })).merge, false);
});

test('a skipped required job refuses', () => {
  const jobs = goodJobs.map(j => (j.name === 'Pester (windows, powershell 5.1)' ? { ...j, conclusion: 'skipped' } : j));
  const result = evaluate(task({ jobs }));
  assert.match(result.reasons.join(), /5\.1/);
});

test('a missing required job refuses', () => {
  assert.equal(evaluate(task({ jobs: goodJobs.slice(1) })).merge, false);
});

test('another failed run refuses; advisory runs do not', () => {
  assert.equal(evaluate(task({ otherRuns: [{ name: 'CI - Release scripts', conclusion: 'failure' }] })).merge, false);
  assert.equal(evaluate(task({ otherRuns: [{ name: 'Housekeeping - Claude code review', conclusion: 'failure' }] })).merge, true);
});

test('files outside scope refuse', () => {
  for (const file of ['.github/workflows/ci.yml', 'scripts/release/bump.mjs', 'VERSION', 'install.ps1', '.gitignore', 'Dockerfile', 'tools/matrix/x.mjs', '../x']) {
    const result = evaluate(task({ files: ['CHANGELOG.md', file] }));
    assert.equal(result.merge, false, file);
  }
});

test('no files or too many files refuse', () => {
  assert.equal(evaluate(task({ files: [] })).merge, false);
  assert.equal(evaluate(task({ files: Array.from({ length: 101 }, (_, i) => `docs/${i}.md`) })).merge, false);
});

test('scope helper', () => {
  assert.ok(inScope('psfdx-shared/Invoke-Salesforce.ps1'));
  assert.ok(inScope('modules.ps1'));
  assert.ok(!inScope('psfdx/../.github/x'));
  assert.ok(!inScope('docs\\x.md'));
});

// Core lane
function core(overrides = {}) {
  const base = task({
    files: ['tools/matrix/worker.mjs', 'tools/matrix/tests/worker.test.mjs'],
    run: { name: CORE_RUN, conclusion: 'success', event: 'pull_request', head_sha: SHA },
    jobs: [],
  });
  return { ...base, pr: { ...base.pr, headRefName: 'matrix/core/loop-fix', body: `x\n${CORE_STATEMENT}` }, ...overrides };
}

test('core lane merges Matrix code after the orchestration tests', () => {
  assert.deepEqual(evaluate(core()), { merge: true, reasons: [], lane: 'core' });
});

test('core lane needs the statement, the agent and the right run', () => {
  assert.equal(evaluate(withPr(core(), { body: 'no statement' })).merge, false);
  assert.equal(evaluate(withPr(core(), { author: 'x' })).merge, false);
  assert.equal(evaluate(core({ run: { name: BUILD_RUN, conclusion: 'success', event: 'pull_request', head_sha: SHA } })).merge, false);
});

test('core lane never covers the gate, workflows or scripts', () => {
  for (const file of ['scripts/matrix/automerge.mjs', '.github/workflows/gate-auto-merge.yml', 'tools/matrix/run.ps1', 'tools/matrix/Dockerfile', 'psfdx/psfdx.psm1']) {
    assert.equal(evaluate(core({ files: [file] })).merge, false, file);
  }
  assert.ok(inCoreScope('docs/execution-policy.md'));
  assert.ok(!inCoreScope('tools/matrix/sub/x.mjs'));
});

test('core lane with Markdown only uses the quick CI run', () => {
  const facts = core({
    files: ['tools/matrix/README.md'],
    run: { name: BUILD_RUN, conclusion: 'success', event: 'pull_request', head_sha: SHA },
    jobs: goodJobs,
  });
  assert.equal(evaluate(facts).merge, true);
});

// Archive lane
function archive(overrides = {}) {
  const base = task({ files: ['prompts/README.md', 'prompts/done/AUTO-01-x.md', 'prompts/AUTO-01-x.md'] });
  return { ...base, pr: { ...base.pr, headRefName: 'housekeeping/archive-AUTO-01', body: ARCHIVE_STATEMENT }, ...overrides };
}

test('archive lane merges a prompts-only pull request', () => {
  assert.deepEqual(evaluate(archive()), { merge: true, reasons: [], lane: 'archive' });
});

test('archive lane refuses other files, a wrong author or a missing statement', () => {
  assert.equal(evaluate(archive({ files: ['prompts/x.md', 'psfdx/psfdx.psm1'] })).merge, false);
  assert.equal(evaluate(withPr(archive(), { author: 'x' })).merge, false);
  assert.equal(evaluate(withPr(archive(), { body: '' })).merge, false);
});

// Archive helpers
test('task ID from branch', () => {
  assert.equal(promptIdFromBranch('matrix/AUTO-07-bounded-loop'), 'AUTO-07');
  assert.equal(promptIdFromBranch('matrix/PSF-12'), 'PSF-12');
  assert.equal(promptIdFromBranch('matrix/core/x'), null);
  assert.equal(promptIdFromBranch('feature/x'), null);
});

test('archive path', () => {
  assert.equal(archivePath('prompts/AUTO-01-x.md'), 'prompts/done/AUTO-01-x.md');
  assert.equal(archivePath('prompts/done/AUTO-01-x.md'), null);
  assert.equal(archivePath('prompts/README.md'), null);
  assert.equal(archivePath('docs/x.md'), null);
});

test('markDone strips status lines, keeps line endings and rebases links', () => {
  const text = '---\r\nid: AUTO-01\r\nstatus: x\r\nmodel: opus\r\npriority: high\r\n---\r\n\r\nSee [policy](../docs/execution-policy.md) and [next](AUTO-02-x.md) and [web](https://a.b/c).\r\n';
  const out = markDone(text, 'prompts/AUTO-01-x.md', 'prompts/done/AUTO-01-x.md');
  assert.equal(out, '---\r\nid: AUTO-01\r\npriority: high\r\n---\r\n\r\nSee [policy](../../docs/execution-policy.md) and [next](../AUTO-02-x.md) and [web](https://a.b/c).\r\n');
});

test('rebaseLinks keeps fragments', () => {
  assert.equal(rebaseLinks('[a](../docs/x.md#y)', 'prompts/p.md', 'prompts/done/p.md'), '[a](../../docs/x.md#y)');
});

test('relinkMoved updates links to the moved file only', () => {
  const readme = '| [one](AUTO-01-x.md) | [two](AUTO-02-x.md#top) | [ext](https://x/AUTO-01-x.md) |';
  const out = relinkMoved(readme, 'prompts/README.md', 'prompts/AUTO-01-x.md', 'prompts/done/AUTO-01-x.md');
  assert.equal(out, '| [one](done/AUTO-01-x.md) | [two](AUTO-02-x.md#top) | [ext](https://x/AUTO-01-x.md) |');
  const blob = relinkMoved('https://github.com/o/r/blob/main/prompts/AUTO-01-x.md', 'README.md', 'prompts/AUTO-01-x.md', 'prompts/done/AUTO-01-x.md');
  assert.equal(blob, 'https://github.com/o/r/blob/main/prompts/done/AUTO-01-x.md');
});
