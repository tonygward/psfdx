import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  bumpPatch, parseVersion, assertInStep, writeManifestVersion, readManifestVersion,
  moveUnreleased, sectionFor, zipEntries,
} from './bump-lib.mjs';

test('patch bump', () => {
  assert.equal(bumpPatch('0.8.0'), '0.8.1');
  assert.equal(bumpPatch('1.2.9'), '1.2.10');
});

test('rejects a bad version', () => {
  assert.throws(() => parseVersion('0.8'));
});

test('manifest rewrite changes only the ModuleVersion line', () => {
  const text = "@{\r\n    RootModule = 'a.psm1'\r\n    ModuleVersion     = '0.8.0'\r\n    Author = 'x'\r\n}\r\n";
  const out = writeManifestVersion(text, '0.8.1');
  assert.equal(out, text.replace("'0.8.0'", "'0.8.1'"));
  assert.equal(readManifestVersion(out), '0.8.1');
});

test('manifests out of step are refused', () => {
  const ok = { name: 'a', text: "ModuleVersion = '0.8.0'" };
  const bad = { name: 'b', text: "ModuleVersion = '0.7.0'" };
  assert.doesNotThrow(() => assertInStep('0.8.0', [ok]));
  assert.throws(() => assertInStep('0.8.0', [ok, bad]), /b has 0.7.0/);
});

test('changelog: moves Unreleased, no earlier versions', () => {
  const out = moveUnreleased('# Changelog\n\n## Unreleased\n\n- a: one\n- a: two\n', '0.8.1', '2026-11-14');
  assert.equal(out, '# Changelog\n\n## Unreleased\n\n## 0.8.1 - 2026-11-14\n\n- a: one\n- a: two\n');
});

test('changelog: keeps earlier versions below', () => {
  const out = moveUnreleased('# Changelog\n\n## Unreleased\n\n- new\n\n## 0.8.0 - 2026-01-01\n\n- old\n', '0.8.1', '2026-11-14');
  assert.match(out, /## Unreleased\n\n## 0\.8\.1 - 2026-11-14\n\n- new\n\n## 0\.8\.0 - 2026-01-01\n\n- old/);
});

test('changelog: empty Unreleased gets a maintenance line', () => {
  const out = moveUnreleased('# Changelog\n\n## Unreleased\n\n', '0.8.1', '2026-11-14');
  assert.match(out, /## 0\.8\.1 - 2026-11-14\n\n- Maintenance release\./);
});

test('changelog: Windows line endings are kept', () => {
  const out = moveUnreleased('# Changelog\r\n\r\n## Unreleased\r\n\r\n- a\r\n', '0.8.1', '2026-11-14');
  assert.ok(out.includes('\r\n'));
  assert.ok(!/[^\r]\n/.test(out));
});

test('sectionFor returns one version notes', () => {
  const text = '# Changelog\n\n## Unreleased\n\n## 0.8.1 - 2026-11-14\n\n- new\n\n## 0.8.0 - x\n\n- old\n';
  assert.equal(sectionFor(text, '0.8.1'), '- new');
  assert.equal(sectionFor(text, '9.9.9'), null);
});

test('zip entries list modules plus installers, no tests or docs', () => {
  const list = zipEntries(['psfdx', 'psfdx-shared']);
  assert.deepEqual(list.slice(0, 2), ['psfdx', 'psfdx-shared']);
  assert.ok(list.includes('install.ps1') && list.includes('CHANGELOG.md'));
  assert.ok(!list.some((e) => /docs|prompts|\.github|tests/.test(e)));
});
