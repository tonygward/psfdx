import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { runTask, branchFor, ciOutcome, resolveChangelogConflict, resumePathsValid, limitsText, preflight, baseEnvironment, tickReport } from '../worker.mjs';
import { readState } from '../state.mjs';
import { readHandoff } from '../handoff.mjs';
import { makeWorld, PROMPT_TEXT, PASSING_XML, failingXml, PR_URL, REVISION } from './worker-harness.mjs';
import { usageResult } from './fixtures.mjs';

const stateOf = world => readState(world.dir, { restart: false }).tasks['PSF-01'];
const pushes = world => world.remoteCalls.filter(c => c.args[0] === 'push');
const commits = world => world.gitCalls.filter(c => c.args.includes('commit'));
const kinds = world => world.io.writes.map(w => w.kind);

test('claim to pull request, end to end against fakes', async t => {
  const world = makeWorld(t); world.seed();
  const result = await runTask(world.config, world.deps);
  assert.deepEqual([result.outcome, result.id, result.pr], ['awaiting-review', 'PSF-01', PR_URL]);
  // Claim and starting comment come before any code.
  assert.deepEqual(kinds(world).slice(0, 2), ['move', 'comment']);
  assert.match(world.io.writes[1].body, /Matrix has picked up \*\*PSF-01\*\*[\s\S]*Run now \(Doing\)[\s\S]*Limits: up to 30 Claude turns/);
  // Worktree is under the worktree root on a matrix/<ID>-<slug> branch from origin/main.
  const add = world.gitCalls.find(c => c.args[0] === 'worktree').args;
  assert.deepEqual(add.slice(0, 3), ['worktree', 'add', '-b']);
  assert.equal(add[3], 'matrix/PSF-01-do-the-thing'); assert.equal(add.at(-1), 'refs/remotes/origin/main');
  assert.ok(add.at(-2).startsWith(world.config.worktreeRoot));
  // Instructions are outside the repository; Claude only gets a short fixed line pointing at them.
  const call = world.claudeCalls[0];
  assert.ok(fs.existsSync(path.join(world.config.worktreeRoot, 'PSF-01', 'instructions.md')));
  assert.equal(call.cwd, path.join(world.config.worktreeRoot, 'PSF-01', 'repo'));
  assert.ok(!call.input.includes('Build the thing'), 'the untrusted prompt body is not in the instruction line');
  assert.match(call.input, /instructions\.md/);
  assert.ok(call.args.includes('--tools') && call.args[call.args.indexOf('--tools') + 1] === 'Read,Edit,Write,Glob,Grep');
  assert.ok(!call.args.some(a => /Bash|WebFetch|WebSearch/.test(a)));
  assert.deepEqual(call.args.slice(call.args.indexOf('--add-dir'), call.args.indexOf('--add-dir') + 2), ['--add-dir', path.join(world.config.worktreeRoot, 'PSF-01')]);
  // Local tests ran before the push; the push and a draft pull request followed.
  assert.equal(world.sandboxCalls.length, 1);
  assert.equal(commits(world).length, 1); assert.equal(pushes(world).length, 1);
  const create = world.created;
  assert.ok(create.includes('--draft')); assert.equal(create[create.indexOf('--title') + 1], 'PSF-01: Do the thing');
  const body = fs.readFileSync(create[create.indexOf('--body-file') + 1], 'utf8');
  assert.match(body, /^Matrix job: job-1$/m);
  assert.match(body, /Local tests \(Matrix, PowerShell 7 on Linux\)[\s\S]*20 passed, 0 failed/);
  assert.match(body, /Not yet verified against a real org/);
  // CI on the exact head commit, then ready for review, then the CI-passed note.
  assert.ok(world.ghCalls.some(a => a[0] === 'pr' && a[1] === 'ready'));
  assert.ok(world.io.writes.some(w => w.kind === 'comment' && /CI passed for \*\*PSF-01\*\*/.test(w.body)));
  const task = stateOf(world);
  assert.equal(task.state, 'awaiting-review'); assert.equal(task.phase, 'awaiting-review'); assert.equal(task.pr, PR_URL);
  assert.equal(task.localTests.status, 'passed'); assert.equal(task.localTests.pesterVersion, null);
  assert.equal(task.tokensUsed, 160, 'input + output + cache writes, not cache reads');
});

test('a Todo pickup uses the daily slot and a Doing pickup does not', async t => {
  const todo = makeWorld(t); todo.seed({ status: 'Todo' });
  await runTask(todo.config, todo.deps);
  assert.ok(readState(todo.dir, { restart: false }).lastWorkerDaily);
  const doing = makeWorld(t); doing.seed({ status: 'Doing' });
  await runTask(doing.config, doing.deps);
  assert.equal(readState(doing.dir, { restart: false }).lastWorkerDaily, undefined);
});

test('a stale, missing or changed hand-off does nothing', async t => {
  const none = makeWorld(t); none.seed(); fs.rmSync(path.join(none.dir, 'board-handoff.json'));
  assert.equal((await runTask(none.config, none.deps)).outcome, 'idle');
  const changed = makeWorld(t); changed.seed({ hash: 'someone-edited-the-prompt' });
  assert.match((await runTask(changed.config, changed.deps)).reason, /changed/);
  const stale = makeWorld(t); stale.seed(); stale.clockNow += 16 * 60000;
  assert.equal((await runTask(stale.config, stale.deps)).outcome, 'idle');
  for (const world of [none, changed, stale]) { assert.equal(world.claudeCalls.length, 0); assert.deepEqual(kinds(world), []); }
});

test('blocked usage stops before the claim', async t => {
  const world = makeWorld(t); world.seed();
  world.deps.loadUsage = () => usageResult(60, world.clockNow);
  assert.equal((await runTask(world.config, world.deps)).outcome, 'usage-blocked');
  assert.equal(stateOf(world).state, 'pending'); assert.equal(world.claudeCalls.length, 0);
});

test('if the starting comment fails, no code is written and the task is parked', async t => {
  const world = makeWorld(t, { failComment: true }); world.seed();
  const result = await runTask(world.config, world.deps);
  assert.equal(result.outcome, 'interrupted');
  assert.equal(world.claudeCalls.length, 0); assert.equal(world.gitCalls.filter(c => c.args[0] === 'worktree').length, 0);
  assert.match(stateOf(world).reason, /no code written/);
});

test('a symlink or submodule in the index stops the run before Claude', async t => {
  const world = makeWorld(t, { symlink: true }); world.seed();
  assert.equal((await runTask(world.config, world.deps)).outcome, 'interrupted');
  assert.equal(world.claudeCalls.length, 0);
});

test('local tests fail, then pass: the failure goes to a file, the second push happens only after a pass', async t => {
  const world = makeWorld(t); world.seed();
  world.sandboxScript = [{ exit: 1, xml: failingXml('Thing.fails', 'Expected 1, but got 2') }, { exit: 0, xml: PASSING_XML }];
  let pushesDuringFirstRepair = null;
  world.agentScript = [async () => { world.untracked = ['psfdx-logs/psfdx-logs.psm1']; },
    async () => { pushesDuringFirstRepair = pushes(world).length; }];
  assert.equal((await runTask(world.config, world.deps)).outcome, 'awaiting-review');
  assert.equal(pushesDuringFirstRepair, 0, 'nothing was pushed after the local failure');
  const second = world.claudeCalls[1].input;
  const failureFile = path.join(world.config.worktreeRoot, 'PSF-01', 'local-test-failure.txt');
  assert.ok(second.includes(failureFile));
  assert.ok(!second.includes('Expected 1, but got 2'), 'failure text is never pasted into the instruction');
  assert.equal(fs.existsSync(failureFile), false, 'the failure file is removed once the tests pass');
  assert.equal(stateOf(world).localRepairs, 1);
  assert.equal(world.sandboxCalls.length, 2);
});

test('the failing tests and messages are written to a file the agent can read', async t => {
  const world = makeWorld(t); world.seed();
  world.sandboxScript = [{ exit: 1, xml: failingXml('Thing.fails', 'Expected 1, but got 2') }];
  world.config.worker.maximumLocalRepairs = 0;
  await runTask(world.config, world.deps);
  const text = fs.readFileSync(path.join(world.config.worktreeRoot, 'PSF-01', 'local-test-failure.txt'), 'utf8');
  assert.match(text, /1 failed, 19 passed/); assert.match(text, /FAILED: Thing\.fails\nExpected 1, but got 2/);
});

test('the local repair limit stops the run in Blocked with the last failure, and pushes nothing', async t => {
  const world = makeWorld(t); world.seed();
  world.sandboxScript = [{ exit: 1, xml: failingXml() }];
  const result = await runTask(world.config, world.deps);
  assert.equal(result.outcome, 'interrupted');
  assert.match(result.reason, /Reached the local test repair limit \(2\); 1 local test\(s\) failed\. Nothing new was pushed/);
  assert.equal(pushes(world).length, 0); assert.equal(world.created, undefined);
  assert.equal(world.claudeCalls.length, 3, 'one attempt plus two local repairs');
  assert.equal(stateOf(world).state, 'interrupted');
});

test('a test run that times out or is refused by the sandbox blocks with nothing pushed', async t => {
  for (const [exit, text] of [[124, /did not finish within 600 seconds/], [125, /sandbox refused the test run/], [3, /sandbox failed \(exit code 3\)/]]) {
    const world = makeWorld(t); world.seed(); world.sandboxScript = [{ exit }];
    const result = await runTask(world.config, world.deps);
    assert.equal(result.outcome, 'interrupted'); assert.match(result.reason, text); assert.match(result.reason, /nothing was pushed/);
    assert.equal(pushes(world).length, 0); assert.equal(world.claudeCalls.length, 1, 'a refusal is not repaired');
  }
  const broken = makeWorld(t); broken.seed(); broken.sandboxScript = [{ exit: 0 }];
  assert.match((await runTask(broken.config, broken.deps)).reason, /no readable results file/);
});

test('the tests run in the worktree with the configured time limit, results outside the repository', async t => {
  const world = makeWorld(t, { worker: { testTimeoutSeconds: 123 } }); world.seed();
  await runTask(world.config, world.deps);
  const call = world.sandboxCalls[0];
  assert.equal(call.timeoutSeconds, 123);
  assert.equal(call.worktree, path.join(world.config.worktreeRoot, 'PSF-01', 'repo'));
  assert.equal(path.dirname(call.resultsFile), path.join(world.config.worktreeRoot, 'PSF-01'));
});

test('changes outside the allowed scope are reverted and reported; an empty change blocks', async t => {
  const world = makeWorld(t); world.seed();
  world.tracked = ['.github/workflows/ci.yml', 'psfdx/psfdx.psm1'];
  world.untracked = ['scripts/x.mjs', 'prompts/PSF-01-do-the-thing.md', 'tests/new.Tests.ps1'];
  world.agentScript = [async ({ cwd }) => { fs.mkdirSync(path.join(cwd, 'scripts'), { recursive: true }); fs.writeFileSync(path.join(cwd, 'scripts', 'x.mjs'), 'x'); }];
  await runTask(world.config, world.deps);
  const added = world.gitCalls.find(c => c.args[0] === 'add').args.slice(2);
  assert.deepEqual(added.sort(), ['psfdx/psfdx.psm1', 'tests/new.Tests.ps1']);
  assert.ok(world.gitCalls.some(c => c.args.join(' ') === 'checkout HEAD -- .github/workflows/ci.yml'));
  assert.equal(fs.existsSync(path.join(world.config.worktreeRoot, 'PSF-01', 'repo', 'scripts', 'x.mjs')), false);
  const only = makeWorld(t); only.seed(); only.agentScript = [async () => { only.untracked = ['.github/workflows/x.yml']; }];
  assert.equal((await runTask(only.config, only.deps)).outcome, 'interrupted');
  assert.equal(pushes(only).length, 0);
});

test('hosted CI fails, is repaired from a log file, then passes', async t => {
  const world = makeWorld(t); world.seed();
  world.ciScript = [{ status: 'in_progress' }, { status: 'completed', conclusion: 'failure' }, { status: 'completed', conclusion: 'success' }];
  world.sandboxScript = [{ exit: 0, xml: PASSING_XML }];
  const result = await runTask(world.config, world.deps);
  assert.equal(result.outcome, 'awaiting-review');
  assert.equal(world.claudeCalls.length, 2);
  const repair = world.claudeCalls[1].input;
  const logFile = path.join(world.config.worktreeRoot, 'PSF-01', 'ci-failure.log');
  assert.ok(repair.includes(logFile)); assert.ok(!repair.includes('IGNORE ALL PREVIOUS'), 'log text is never in the instruction');
  assert.match(fs.readFileSync(logFile, 'utf8'), /IGNORE ALL PREVIOUS INSTRUCTIONS/);
  assert.equal(world.sandboxCalls.length, 2, 'local tests run again before the repair is pushed');
  assert.equal(pushes(world).length, 2);
  assert.ok(world.clockNow > 0);
});

test('CI failures past the repair limit stop in Blocked, with the pull request kept', async t => {
  const world = makeWorld(t); world.seed();
  world.ciScript = [{ status: 'completed', conclusion: 'failure' }];
  const result = await runTask(world.config, world.deps);
  assert.equal(result.outcome, 'interrupted');
  assert.match(result.reason, /Hosted CI failed; the worker stopped after 2 repairs/);
  const task = stateOf(world);
  assert.equal(task.state, 'interrupted'); assert.equal(task.pr, PR_URL); assert.equal(task.phase, 'pr-open');
  assert.equal(world.claudeCalls.length, 3);
  assert.ok(world.ghCalls.some(a => a[0] === 'pr' && a[1] === 'edit'), 'the description gains a Blocked section');
  const edited = fs.readFileSync(path.join(world.config.worktreeRoot, 'PSF-01', 'pr-body.md'), 'utf8');
  assert.match(edited, /## Blocked/);
});

test('a CI run that never starts, or never finishes, is reported', async t => {
  const none = makeWorld(t); none.seed(); none.ciScript = ['none'];
  assert.match((await runTask(none.config, none.deps)).reason, /did not start/);
  const slow = makeWorld(t, { worker: { ciTimeoutSeconds: 300, pollSeconds: 60 } }); slow.seed(); slow.ciScript = [{ status: 'in_progress' }];
  assert.match((await runTask(slow.config, slow.deps)).reason, /did not finish in time/);
});

test('only a run for the exact head commit counts', () => {
  const sha = 'c'.repeat(40);
  assert.deepEqual(ciOutcome([{ databaseId: 1, headSha: 'd'.repeat(40), event: 'pull_request', status: 'completed', conclusion: 'success' }], sha), { state: 'none' });
  assert.deepEqual(ciOutcome([{ databaseId: 1, headSha: sha, event: 'push', status: 'completed', conclusion: 'success' }], sha), { state: 'none' });
  assert.equal(ciOutcome([{ databaseId: 1, headSha: sha, event: 'pull_request', status: 'completed', conclusion: 'failure' }, { databaseId: 2, headSha: sha, event: 'pull_request', status: 'completed', conclusion: 'success' }], sha).state, 'success');
  assert.equal(ciOutcome([{ databaseId: 3, headSha: sha, event: 'pull_request', status: 'queued' }], sha).state, 'pending');
  assert.equal(ciOutcome('nonsense', sha).state, 'none');
});

test('the run time limit stops the run, counted from the claim and including CI waiting', async t => {
  const world = makeWorld(t, { worker: { maximumRunMinutes: 30, pollSeconds: 300 } }); world.seed();
  world.ciScript = [{ status: 'in_progress' }];
  const result = await runTask(world.config, world.deps);
  assert.match(result.reason, /Run time limit of 30 minutes reached/);
  assert.equal(stateOf(world).state, 'interrupted');
});

test('the optional token budget stops a repair', async t => {
  const world = makeWorld(t, { worker: { maximumTokens: 100 } }); world.seed();
  world.sandboxScript = [{ exit: 1, xml: failingXml() }];
  const result = await runTask(world.config, world.deps);
  assert.match(result.reason, /Run token limit of 100 tokens reached \(160 used\)/);
  assert.equal(world.claudeCalls.length, 1);
});

test('the usage gate is checked again before each repair', async t => {
  const world = makeWorld(t); world.seed();
  world.sandboxScript = [{ exit: 1, xml: failingXml() }];
  let calls = 0;
  world.deps.loadUsage = () => (++calls === 1 ? usageResult(10, world.clockNow) : usageResult(61, world.clockNow));
  const result = await runTask(world.config, world.deps);
  assert.match(result.reason, /Repair stopped by the usage policy/);
  assert.equal(world.claudeCalls.length, 1);
});

test('a configured Claude limit is explained, not reported as a generic failure', async t => {
  for (const [subtype, error, text] of [['error_max_turns', undefined, /turn limit \(30 turns\)/], ['error_max_budget_usd', undefined, /cost limit \(5 dollars\)/], [undefined, 'Process timed out', /time limit for one attempt \(30 minutes\)/]]) {
    const world = makeWorld(t); world.seed();
    world.agentScript = [async () => ({ throw: Object.assign(new Error(error ?? 'Process failed'), { stdout: subtype ? JSON.stringify({ subtype, num_turns: 31, total_cost_usd: 1 }) : '' }) })];
    const result = await runTask(world.config, world.deps);
    assert.match(result.reason, text); assert.equal(pushes(world).length, 0);
  }
  const unexplained = makeWorld(t); unexplained.seed();
  unexplained.agentScript = [async () => ({ throw: Object.assign(new Error('Process failed'), { stdout: 'garbage', exitCode: 1 }) })];
  assert.equal((await runTask(unexplained.config, unexplained.deps)).reason, null);
  assert.match(stateOf(unexplained).reason, /Execution interrupted; inspect the retained worktree/);
});

test('an agent that overruns the runaway guard is stopped', async t => {
  const world = makeWorld(t); world.seed();
  world.agentScript = [async () => ({ result: { num_turns: 91 } })];
  assert.equal((await runTask(world.config, world.deps)).outcome, 'interrupted');
  assert.equal(pushes(world).length, 0);
});

test('restart safety: an existing open pull request is reused, never duplicated', async t => {
  const world = makeWorld(t); world.seed();
  world.prs = [{ url: PR_URL, headRefOid: 'x', state: 'OPEN' }];
  assert.equal((await runTask(world.config, world.deps)).outcome, 'awaiting-review');
  assert.equal(world.created, undefined);
  assert.ok(world.ghCalls.some(a => a[0] === 'pr' && a[1] === 'list'), 'it looked up before creating');
});

test('restart safety: a closed pull request or two for the branch needs a person', async t => {
  for (const prs of [[{ url: PR_URL, state: 'CLOSED' }], [{ url: PR_URL, state: 'OPEN' }, { url: `${PR_URL}3`, state: 'OPEN' }]]) {
    const world = makeWorld(t); world.seed(); world.prs = prs;
    assert.equal((await runTask(world.config, world.deps)).outcome, 'interrupted');
    assert.equal(world.created, undefined);
  }
});

test('an unverified pull request URL is refused', async t => {
  const world = makeWorld(t); world.seed();
  const gh = world.deps.gh; world.deps.gh = async args => (args[0] === 'pr' && args[1] === 'create' ? 'https://evil.example/pull/1' : gh(args));
  assert.equal((await runTask(world.config, world.deps)).outcome, 'interrupted');
});

test('if the pull request merged while CI ran, nothing more is pushed', async t => {
  const world = makeWorld(t); world.seed(); world.prState = 'MERGED'; world.behind = true;
  assert.equal((await runTask(world.config, world.deps)).outcome, 'awaiting-review');
  assert.equal(pushes(world).length, 1);
});

test('main is merged into the branch before pushing; a changelog-only conflict is resolved, any other blocks', async t => {
  const resolved = makeWorld(t); resolved.seed(); resolved.behind = true; resolved.mergeConflict = 'CHANGELOG.md';
  resolved.agentScript = [async ({ cwd }) => { resolved.untracked = ['CHANGELOG.md']; fs.writeFileSync(path.join(cwd, 'CHANGELOG.md'), '<<<<<<< HEAD\n- mine\n=======\n- theirs\n>>>>>>> origin/main\n'); }];
  const result = await runTask(resolved.config, resolved.deps);
  assert.equal(result.outcome, 'awaiting-review');
  assert.equal(fs.readFileSync(path.join(resolved.config.worktreeRoot, 'PSF-01', 'repo', 'CHANGELOG.md'), 'utf8'), '- mine\n\n- theirs\n');
  const other = makeWorld(t); other.seed(); other.behind = true; other.mergeConflict = 'psfdx/psfdx.psm1';
  const blocked = await runTask(other.config, other.deps);
  assert.match(blocked.reason, /Main changed in files this change touches/);
  assert.ok(other.gitCalls.some(c => c.args.join(' ') === 'merge --abort'));
  assert.equal(pushes(other).length, 0);
});

test('resolveChangelogConflict keeps both sides, and gives up when unsure', () => {
  assert.equal(resolveChangelogConflict('a\n<<<<<<< HEAD\n- mine\n=======\n- theirs\n>>>>>>> x\nz\n'), 'a\n- mine\n\n- theirs\nz\n');
  assert.equal(resolveChangelogConflict('<<<<<<< a\n1\n=======\n2\n>>>>>>> b\n<<<<<<< c\n3\n=======\n4\n>>>>>>> d\n'), null);
  assert.equal(resolveChangelogConflict('no conflict'), null);
  assert.equal(resolveChangelogConflict('<<<<<<< a\r\n1\r\n=======\r\n2\r\n>>>>>>> b\r\n'), '1\n\n2\r\n');
});

test('a generated prompt is saved in the same pull request', async t => {
  const world = makeWorld(t); world.files = new Map();
  const text = '---\nid: PSF-01\npriority: medium\neffort: medium\ndependencies: []\nconflicts: []\n---\n\n# PSF-01: Do the thing\n\nBuild the thing.\n';
  const { writeHandoff } = await import('../handoff.mjs'); const { parsePrompt } = await import('../backlog.mjs');
  const generated = parsePrompt('prompts/PSF-01-do-the-thing.md', text);
  writeHandoff(world.dir, { selected: { taskId: 'PSF-01', promptHash: generated.hash, status: 'Doing', issue: 1, itemId: 'i', repository: 'tonygward/psfdx', generated: { file: generated.file, text } }, job: 'job-1', revision: REVISION, now: world.clockNow });
  world.branch = 'matrix/PSF-01-do-the-thing';
  assert.equal((await runTask(world.config, world.deps)).outcome, 'awaiting-review');
  assert.equal(fs.readFileSync(path.join(world.config.worktreeRoot, 'PSF-01', 'repo', 'prompts', 'PSF-01-do-the-thing.md'), 'utf8'), text);
  assert.ok(world.gitCalls.find(c => c.args[0] === 'add').args.includes('prompts/PSF-01-do-the-thing.md'));
});

test('resume with committed work: it asks CI first and only runs Claude when that build failed', async t => {
  const resumed = (extra = {}) => ({ commit: 'f'.repeat(40), pr: PR_URL, resumeWork: true, resumedAt: 'x', resumedFrom: { job: 'job-0', reason: 'CI repair limit' },
    branch: 'matrix/PSF-01-do-the-thing', worktree: null, ...extra });
  const green = makeWorld(t); green.seed({ extraTask: resumed({ worktree: path.join(green.config.worktreeRoot, 'PSF-01', 'repo') }) });
  fs.mkdirSync(path.join(green.config.worktreeRoot, 'PSF-01', 'repo'), { recursive: true });
  green.prs = [{ url: PR_URL, state: 'OPEN' }];
  assert.equal((await runTask(green.config, green.deps)).outcome, 'awaiting-review');
  assert.equal(green.claudeCalls.length, 0, 'build was green: no agent');
  assert.equal(green.gitCalls.filter(c => c.args[0] === 'worktree').length, 0, 'the retained worktree is reused');
  assert.equal(commits(green).length, 0);
  const red = makeWorld(t); red.seed({ extraTask: resumed({ worktree: path.join(red.config.worktreeRoot, 'PSF-01', 'repo') }) });
  fs.mkdirSync(path.join(red.config.worktreeRoot, 'PSF-01', 'repo'), { recursive: true });
  red.prs = [{ url: PR_URL, state: 'OPEN' }];
  red.ciScript = [{ status: 'completed', conclusion: 'failure' }, { status: 'completed', conclusion: 'success' }];
  assert.equal((await runTask(red.config, red.deps)).outcome, 'awaiting-review');
  assert.equal(red.claudeCalls.length, 1);
  assert.match(red.claudeCalls[0].input, /resuming this task[\s\S]*CI repair limit/);
});

test('resume refuses paths outside the worktree root, a worktree on the wrong branch, and a lost commit', async t => {
  const outside = makeWorld(t); outside.seed({ extraTask: { commit: 'f'.repeat(40), resumeWork: true, branch: 'matrix/PSF-01-x', worktree: '/etc/elsewhere' } });
  assert.match((await runTask(outside.config, outside.deps)).reason, /not where Matrix keeps them/);
  const wrong = makeWorld(t); const dir = path.join(wrong.config.worktreeRoot, 'PSF-01', 'repo'); fs.mkdirSync(dir, { recursive: true });
  wrong.seed({ extraTask: { commit: 'f'.repeat(40), resumeWork: true, branch: 'matrix/PSF-01-x', worktree: dir } }); wrong.branchOverride = 'main';
  assert.match((await runTask(wrong.config, wrong.deps)).reason, /not on the saved branch/);
  const lost = makeWorld(t); const dir2 = path.join(lost.config.worktreeRoot, 'PSF-01', 'repo'); fs.mkdirSync(dir2, { recursive: true });
  lost.seed({ extraTask: { commit: 'f'.repeat(40), resumeWork: true, branch: 'matrix/PSF-01-x', worktree: dir2 } }); lost.branchOverride = 'matrix/PSF-01-x'; lost.notAncestor = true;
  assert.match((await runTask(lost.config, lost.deps)).reason, /no longer contains the last commit/);
  assert.equal(resumePathsValid({ worktree: '/trees/PSF-01/repo', branch: 'matrix/PSF-01-x' }, '/trees'), true);
  assert.equal(resumePathsValid({ worktree: '/trees/../x', branch: 'matrix/PSF-01-x' }, '/trees'), false);
  assert.equal(resumePathsValid({ worktree: '/trees/a', branch: 'feature/x' }, '/trees'), false);
});

test('a pause file stops the worker before it does anything', async t => {
  const world = makeWorld(t); world.seed(); fs.writeFileSync(path.join(world.dir, 'PAUSED'), '');
  assert.equal((await runTask(world.config, world.deps)).outcome, 'paused');
  assert.ok(readHandoff(world.dir, { now: world.clockNow }), 'the hand-off is untouched');
});

test('a task claimed before a restart is interrupted when the worker starts, and is never re-run', async t => {
  const world = makeWorld(t); world.seed();
  const state = readState(world.dir, { restart: false }); state.tasks['PSF-01'].state = 'claimed'; state.tasks['PSF-01'].job = 'old';
  fs.writeFileSync(path.join(world.dir, 'state.json'), JSON.stringify(state));
  assert.equal((await runTask(world.config, world.deps)).outcome, 'idle');
  assert.equal(world.claudeCalls.length, 0);
});

test('branch names, limits text and helpers', () => {
  assert.equal(branchFor({ id: 'AUTO-07', file: 'prompts/AUTO-07-bounded-agent-loop.md' }), 'matrix/AUTO-07-bounded-agent-loop');
  assert.equal(branchFor({ id: 'PSF-01', file: 'prompts/PSF-01-.md' }), 'matrix/PSF-01');
  assert.match(branchFor({ id: 'PSF-01', file: `prompts/PSF-01-${'a'.repeat(100)}.md` }), /^matrix\/PSF-01-a{40}$/);
  assert.match(limitsText({ worker: { maximumRepairs: 3, maximumRunMinutes: 120, maximumTokens: 5000000 } }), /3 CI repairs, 120 minutes in total per run, 5000000 tokens in total per run; no new work at or above 60%/);
});

test('preflight fails closed', () => {
  const ok = { env: { HTTPS_PROXY: 'http://proxy:3128' }, exists: () => false, status: () => 'CapEff:\t0000000000000000\n', uid: 1000 };
  assert.doesNotThrow(() => preflight(ok));
  assert.throws(() => preflight({ ...ok, uid: 0 }), /root/);
  assert.throws(() => preflight({ ...ok, uid: null }), /root/);
  assert.throws(() => preflight({ ...ok, exists: p => p === '/var/run/docker.sock' }), /Docker socket/);
  assert.throws(() => preflight({ ...ok, env: { ...ok.env, GH_TOKEN: 'x' } }), /credentials in environment \(GH_TOKEN\)/);
  assert.throws(() => preflight({ ...ok, env: {} }), /egress proxy/);
  assert.throws(() => preflight({ ...ok, status: () => 'CapEff:\t00000000000000c0\n' }), /capabilities/);
  assert.throws(() => preflight({ ...ok, status: () => { throw new Error('no'); } }), /cannot read process status/);
});

test('the base environment carries no tokens', () => {
  const env = baseEnvironment({ PATH: '/bin', HTTPS_PROXY: 'p', GH_TOKEN: 'x', ANTHROPIC_API_KEY: 'y', RELEASE_TOKEN: 'z' });
  assert.deepEqual(Object.keys(env).sort(), ['DISABLE_AUTOUPDATER', 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM', 'GIT_TERMINAL_PROMPT', 'HTTPS_PROXY', 'NO_COLOR', 'PATH']);
});

test('tickReport: idle when nothing is selected, the choice and reasons in a dry run, and null (run the worker) otherwise', () => {
  assert.deepEqual(tickReport({ selected: null, blocker: 'No eligible card' }), { ran: true, idle: true, blocker: 'No eligible card' });
  assert.deepEqual(tickReport({ selected: null }), { ran: true, idle: true, blocker: null });
  const dry = tickReport({ dryRun: true, selected: { id: 'PSF-28' }, decisions: [{ id: 'PSF-28', reason: 'first eligible' }] });
  assert.equal(dry.dryRun, true);
  assert.equal(dry.ran, true);
  assert.deepEqual(dry.wouldPick, { id: 'PSF-28' });
  assert.equal(dry.decisions.length, 1);
  assert.equal(tickReport({ dryRun: false, selected: { id: 'PSF-28' } }), null);
});
