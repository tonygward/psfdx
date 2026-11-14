import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { BUILD_RUN, CORE_RUN, REQUIRED_JOBS } from './automerge.mjs';

const dir = new URL('../../.github/workflows/', import.meta.url);
const workflows = fs.readdirSync(dir).filter(f => f.endsWith('.yml')).map(file => {
  const text = fs.readFileSync(new URL(file, dir), 'utf8');
  const name = /^name:\s*(.+?)\s*$/m.exec(text)?.[1];
  return { file, text, name };
});
const names = workflows.map(w => w.name);

test('every workflow name follows the prefix rule', () => {
  for (const w of workflows) assert.match(w.name ?? '', /^(CI|Gate|CD|Housekeeping) - /, w.file);
});

test('workflow_run triggers name workflows that exist', () => {
  for (const w of workflows) {
    const block = /workflow_run:\s*\n\s*workflows:\s*\[(.*?)\]/s.exec(w.text);
    if (!block) continue;
    for (const listed of block[1].split(',').map(s => s.trim().replace(/^["']|["']$/g, '')).filter(Boolean)) {
      assert.ok(names.includes(listed), `${w.file} waits for "${listed}", which does not exist`);
    }
  }
});

test('the gate constants match the workflow files', () => {
  assert.ok(names.includes(BUILD_RUN), `${BUILD_RUN} is not a workflow name`);
  const ci = workflows.find(w => w.name === BUILD_RUN);
  for (const job of REQUIRED_JOBS) {
    assert.ok(ci.text.includes(`name: ${job}`), `CI is missing the job name "${job}"`);
  }
  // The orchestration tests arrive later; once they exist their name must match.
  const core = workflows.find(w => /orchestration/i.test(w.name ?? ''));
  if (core) assert.equal(core.name, CORE_RUN);
});

test('only main-trusted gate runs from workflow_run and never checks out PR code', () => {
  const gate = workflows.find(w => w.file === 'gate-auto-merge.yml');
  assert.match(gate.text, /ref: main/);
  assert.doesNotMatch(gate.text, /pull_request_target/);
});

