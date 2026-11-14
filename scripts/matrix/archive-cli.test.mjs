import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const cli = new URL('./archive-cli.mjs', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

function run(dir, arg) {
  return spawnSync(process.execPath, [cli, arg], { cwd: dir, encoding: 'utf8' });
}

test('archive CLI moves the prompt and repairs README links', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'archive-'));
  fs.mkdirSync(path.join(dir, 'prompts'));
  fs.writeFileSync(path.join(dir, 'prompts', 'AUTO-09-box.md'), '---\nid: AUTO-09\nstatus: x\n---\n\nSee [p](../docs/p.md).\n');
  fs.writeFileSync(path.join(dir, 'prompts', 'README.md'), '| [AUTO-09](AUTO-09-box.md) |\n');
  const result = run(dir, 'matrix/AUTO-09-box');
  assert.equal(result.status, 0, result.stderr);
  assert.ok(!fs.existsSync(path.join(dir, 'prompts', 'AUTO-09-box.md')));
  const moved = fs.readFileSync(path.join(dir, 'prompts', 'done', 'AUTO-09-box.md'), 'utf8');
  assert.ok(!moved.includes('status:'));
  assert.ok(moved.includes('](../../docs/p.md)'));
  assert.equal(fs.readFileSync(path.join(dir, 'prompts', 'README.md'), 'utf8'), '| [AUTO-09](done/AUTO-09-box.md) |\n');
  fs.rmSync(dir, { recursive: true, force: true });
});

test('archive CLI exits 3 when there is nothing to do and 2 for a bad argument', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'archive-'));
  assert.equal(run(dir, 'AUTO-77').status, 3);
  assert.equal(run(dir, 'nonsense').status, 2);
  fs.rmSync(dir, { recursive: true, force: true });
});
