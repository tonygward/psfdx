import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { shipsRelease, shipsNothing, needsPester, testsNeeded } from './changes.mjs';

test('product files ship; infrastructure, tests and docs do not', () => {
  for (const f of ['psfdx/psfdx.psm1', 'psfdx-shared/Invoke-Salesforce.ps1', 'psfdx-logs/psfdx-logs.psd1', 'modules.ps1', 'install.ps1', 'uninstall-windows.ps1', 'VERSION', 'scripts/release/Build-GalleryPackage.ps1']) {
    assert.equal(shipsRelease(f), true, f);
  }
  for (const f of ['psfdx-logs/psfdx-logs.Tests.ps1', 'README.md', 'CHANGELOG.md', 'scripts/release/bump.mjs', 'scripts/matrix/automerge.mjs',
    '.github/workflows/ci.yml', 'tools/matrix/worker.mjs', 'tools/matrix-linux/Dockerfile', 'tests/Repository.Tests.ps1', 'docs/release.md',
    'prompts/PSF-1-x.md', 'scripts/release/Build-GalleryPackage.Tests.ps1', 'scripts/release/Test-PsfdxSuite.ps1', 'scripts/release/gallery.json']) {
    assert.equal(shipsRelease(f), false, f);
  }
});

test('a change ships nothing only when it has files and none ship; an empty list is never "nothing"', () => {
  assert.equal(shipsNothing(['.github/workflows/ci.yml', 'scripts/release/bump.mjs']), true);
  assert.equal(shipsNothing(['.github/workflows/ci.yml', 'psfdx/psfdx.psm1']), false);
  assert.equal(shipsNothing(['.github/workflows/ci.yml', 'scripts/release/Build-GalleryPackage.ps1']), false, 'a change to the package build releases');
  assert.equal(shipsNothing([]), false);
});

test('Pester is skipped only for docs, prompts, images and Matrix Node/container files, never for the Agent Skill', () => {
  for (const f of ['README.md', 'prompts/x.txt', 'docs/a/b.txt', 'images/x.bin', 'a.png', 'a.svg', 'tools/matrix/x.mjs', 'tools/matrix-linux/Dockerfile', 'tools/matrix-linux/entrypoint.sh']) {
    assert.equal(needsPester(f), false, f);
  }
  for (const f of ['psfdx/x.psm1', 'scripts/release/New-ReleaseZip.ps1', 'scripts/release/New-ReleaseZip.Tests.ps1', '.github/workflows/ci.yml', 'VERSION', 'modules.ps1',
    'tests/Repository.Tests.ps1', 'tools/matrix-linux/Start-MatrixPsfdx.ps1', 'tools/matrix-linux/Start-MatrixPsfdx.Tests.ps1',
    'skills/psfdx/SKILL.md', 'skills/psfdx/references/psfdx-data.md', 'skills/psfdx/AgentSkill.Tests.ps1']) {
    assert.equal(needsPester(f), true, f);
  }
  assert.equal(testsNeeded([]), false);
  assert.equal(testsNeeded(['README.md', 'psfdx/x.psm1']), true);
  assert.equal(testsNeeded(['skills/psfdx/SKILL.md']), true, 'the skill tests run the examples in SKILL.md');
  assert.equal(shipsRelease('skills/psfdx/SKILL.md'), false, 'the Agent Skill is not in the Gallery package');
});

test('the workflows use this file instead of their own copy of the rule', () => {
  for (const file of ['ci.yml', 'cd-bump-version.yml']) {
    const text = fs.readFileSync(new URL(`../../.github/workflows/${file}`, import.meta.url), 'utf8');
    assert.match(text, /node scripts\/release\/changes\.mjs (?:tests|ships)/, file);
    assert.doesNotMatch(text, /\*\.md\|prompts/, `${file} still has its own copy of the rule`);
  }
});
