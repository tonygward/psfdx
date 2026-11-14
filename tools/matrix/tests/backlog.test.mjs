import test from 'node:test';
import assert from 'node:assert/strict';
import { parsePrompt, scan, select, readPromptFiles } from '../backlog.mjs';

const file = (name, front = '', body = '# Title\n') => [`prompts/${name}`, front ? `---\n${front}\n---\n${body}` : body];
const files = (...entries) => new Map(entries);
const parse = (name, front) => parsePrompt(`prompts/${name}`, `---\n${front}\n---\n# T\n`);

test('parses the restricted front matter', () => {
  const p = parse('AUTO-07-loop.md', 'id: AUTO-07\npriority: high\neffort: medium\ndependencies: ["AUTO-06", "AUTO-04"]\nconflicts: []');
  assert.equal(p.id, 'AUTO-07'); assert.equal(p.priority, 1); assert.equal(p.effort, 'medium');
  assert.deepEqual(p.dependencies, ['AUTO-06', 'AUTO-04']); assert.deepEqual(p.conflicts, []);
});

test('the ID comes from the file name, and priority may be a number', () => {
  const p = parsePrompt('prompts/PSF-12-thing.md', '---\npriority: 7\n---\nbody');
  assert.equal(p.id, 'PSF-12'); assert.equal(p.priority, 7);
  assert.equal(parsePrompt('prompts/PSF-12-thing.md', 'no front matter').priority, 99);
});

test('status, execution and model are ignored', () => {
  const p = parse('AUTO-07-loop.md', 'status: done\nexecution: now\nmodel: opus\npriority: low');
  assert.equal(p.priority, 90);
});

const rejects = {
  'unknown field': 'colour: red',
  'duplicate field': 'priority: high\npriority: low',
  'empty field': 'priority:',
  'an id that does not match the file': 'id: AUTO-08',
  'nested YAML': 'dependencies:\n  - AUTO-01',
  'a list item line': '- AUTO-01',
  'an alias': 'priority: *high',
  'an anchor': 'priority: &p high',
  'a tag': 'priority: !!str high',
  'a block scalar': 'priority: |',
  'a bare dependency list': 'dependencies: [AUTO-01]',
  'a dependency with a bad ID': 'dependencies: ["lowercase-1"]',
  'a dependency from an unknown prefix': 'dependencies: ["EQ-41"]',
  'an unknown effort': 'effort: huge',
  'a negative priority': 'priority: -1',
  'a non-numeric priority': 'priority: soon',
  'a malformed line': 'Priority High',
};
for (const [name, front] of Object.entries(rejects)) {
  test(`rejects ${name}`, () => assert.throws(() => parse('AUTO-07-loop.md', front)));
}

test('rejects an unterminated block, a bad file name and a wrong prefix', () => {
  assert.throws(() => parsePrompt('prompts/AUTO-07-x.md', '---\nid: AUTO-07\nno end'), /Unterminated/);
  assert.throws(() => parsePrompt('prompts/loop.md', 'x'), /File name/);
  assert.throws(() => parsePrompt('prompts/EQ-41-x.md', 'x'), /File name/);
});

test('scan reads only prompts, skips README, marks done/ as complete', () => {
  const result = scan(files(file('AUTO-07-a.md'), file('done/AUTO-06-b.md'), file('README.md'), ['docs/x.md', 'x']));
  assert.deepEqual(result.prompts.map(p => [p.id, p.complete]), [['AUTO-07', false], ['AUTO-06', true]]);
  assert.equal(result.errors.length, 0);
});

test('an invalid active prompt is an error; an invalid archived one is a warning', () => {
  const result = scan(files(file('AUTO-07-a.md', 'bogus: 1'), file('done/AUTO-06-b.md', 'bogus: 1')));
  assert.equal(result.errors.length, 1); assert.equal(result.warnings.length, 1);
});

test('duplicate IDs are errors', () => {
  const result = scan(files(file('AUTO-07-a.md'), file('AUTO-07-b.md')));
  assert.match(result.errors[0].reason, /Duplicate ID AUTO-07/);
});

test('any scan error blocks all selection with a visible reason', () => {
  const result = select(scan(files(file('AUTO-07-a.md'), file('AUTO-08-b.md', 'bogus: 1'))));
  assert.deepEqual(result.selected, []);
  assert.match(result.blocked, /AUTO-08-b\.md: Unknown metadata field/);
});

test('the best priority is selected, one at a time', () => {
  const result = select(scan(files(file('PSF-01-a.md', 'priority: low'), file('PSF-02-b.md', 'priority: high'), file('PSF-03-c.md', 'priority: high'))));
  assert.deepEqual(result.selected.map(p => p.id), ['PSF-02']);
  assert.equal(result.decisions.find(d => d.id === 'PSF-03').reason, 'batch capacity');
});

test('a dependency is met only when its prompt is in done/', () => {
  const active = select(scan(files(file('AUTO-06-a.md'), file('AUTO-07-b.md', 'dependencies: ["AUTO-06"]'))));
  assert.deepEqual(active.selected.map(p => p.id), ['AUTO-06']);
  assert.match(active.decisions.find(d => d.id === 'AUTO-07').reason, /not merged/);
  const done = select(scan(files(file('done/AUTO-06-a.md'), file('AUTO-07-b.md', 'dependencies: ["AUTO-06"]'))));
  assert.deepEqual(done.selected.map(p => p.id), ['AUTO-07']);
});

test('missing, self and circular dependencies skip the task but not others', () => {
  const result = select(scan(files(
    file('AUTO-01-a.md', 'dependencies: ["AUTO-99"]'),
    file('AUTO-02-b.md', 'dependencies: ["AUTO-02"]'),
    file('AUTO-03-c.md', 'dependencies: ["AUTO-04"]'),
    file('AUTO-04-d.md', 'dependencies: ["AUTO-03"]'),
    file('AUTO-05-e.md'),
  )));
  const reason = id => result.decisions.find(d => d.id === id).reason;
  assert.match(reason('AUTO-01'), /no prompt/);
  assert.equal(reason('AUTO-02'), 'self dependency');
  assert.equal(reason('AUTO-03'), 'circular dependency');
  assert.equal(reason('AUTO-04'), 'circular dependency');
  assert.deepEqual(result.selected.map(p => p.id), ['AUTO-05']);
});

test('conflicts are symmetric, against selected and running work', () => {
  const a = select(scan(files(file('PSF-01-a.md', 'conflicts: ["PSF-02"]'), file('PSF-02-b.md'))), {}, 2);
  assert.deepEqual(a.selected.map(p => p.id), ['PSF-01']);
  assert.equal(a.decisions.find(d => d.id === 'PSF-02').reason, 'conflicts with other work');
  const running = select(scan(files(file('PSF-01-a.md', 'conflicts: ["PSF-02"]'), file('PSF-02-b.md'))), { 'PSF-02': { id: 'PSF-02', state: 'claimed' } });
  assert.equal(running.decisions.find(d => d.id === 'PSF-01').reason, 'conflicts with other work');
});

test('tasks already claimed, interrupted, awaiting review, dead or complete are skipped', () => {
  for (const state of ['claimed', 'interrupted', 'awaiting-review', 'dead-letter', 'complete']) {
    const result = select(scan(files(file('PSF-01-a.md'))), { 'PSF-01': { id: 'PSF-01', state } });
    assert.deepEqual(result.selected, [], state);
  }
  assert.equal(select(scan(files(file('PSF-01-a.md'))), { 'PSF-01': { id: 'PSF-01', state: 'withdrawn' } }).selected.length, 1);
});

test('reads prompts from the fetched base revision with git ls-tree and git show', () => {
  const calls = [];
  const sha = 'a'.repeat(40);
  const run = (exe, args, options) => {
    calls.push(args);
    assert.equal(options.shell, false);
    if (args[0] === 'rev-parse') return { status: 0, stdout: `${sha}\n` };
    if (args[0] === 'ls-tree') return { status: 0, stdout: 'prompts/AUTO-07-a.md\nprompts/notes.txt\n' };
    return { status: 0, stdout: `content of ${args[1]}` };
  };
  const { revision, files: read } = readPromptFiles({ cwd: '/x', run });
  assert.equal(revision, sha);
  assert.deepEqual([...read.keys()], ['prompts/AUTO-07-a.md']);
  assert.deepEqual(calls[0], ['rev-parse', '--verify', 'refs/remotes/origin/main^{commit}']);
  assert.deepEqual(calls[1], ['ls-tree', '-r', '--name-only', sha, '--', 'prompts']);
  assert.deepEqual(calls[2], ['show', `${sha}:prompts/AUTO-07-a.md`]);
});

test('a git failure or a non-commit revision is an error', () => {
  assert.throws(() => readPromptFiles({ cwd: '/x', run: () => ({ status: 128, stdout: '' }) }), /Git could not read/);
  assert.throws(() => readPromptFiles({ cwd: '/x', run: () => ({ status: 0, stdout: 'nonsense' }) }), /not a commit/);
});
