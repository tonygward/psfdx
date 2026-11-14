import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { validateConfig, readConfig } from '../config.mjs';
import { usageGate, dailyDue, londonDay, WEEKLY_LIMIT_PERCENT, BATCH_LIMIT, MODEL, MAXIMUM_RUN_MINUTES, MAXIMUM_REPAIRS } from '../policy.mjs';

const good = () => ({
  repositorySlug: 'tonygward/psfdx', baseBranch: 'main', stateDirectory: '/matrix/state', worktreeRoot: '/matrix/worktrees',
  promptDirectory: 'prompts', idPrefixes: ['PSF', 'AUTO'], dailyTime: '02:00', batchLimit: 1,
  claudeUsage: { enabled: true, executable: '/usr/local/bin/claude' },
  worker: { maximumPrompts: 1, maximumTurns: 30, maximumBudgetUsd: 5, timeoutSeconds: 1800, maximumRunMinutes: 120, maximumRepairs: 3, maximumTokens: 1000000 },
  boardPickup: {},
});

test('a good configuration passes, and so does the shipped example', () => {
  assert.doesNotThrow(() => validateConfig(good()));
  const example = new URL('../worker.example.json', import.meta.url);
  assert.doesNotThrow(() => validateConfig(JSON.parse(fs.readFileSync(example, 'utf8'))));
});

const mutations = {
  'an unknown key': c => { c.surprise = 1; },
  'an unknown worker key': c => { c.worker.surprise = 1; },
  'a bad repository slug': c => { c.repositorySlug = 'psfdx'; },
  'a relative state directory': c => { c.stateDirectory = 'state'; },
  'a relative worktree root': c => { c.worktreeRoot = './trees'; },
  'a nested prompt directory': c => { c.promptDirectory = 'docs/prompts'; },
  'a lower-case prefix': c => { c.idPrefixes = ['psf']; },
  'no prefixes': c => { c.idPrefixes = []; },
  'a bad daily time': c => { c.dailyTime = '25:00'; },
  'a batch limit of 2': c => { c.batchLimit = 2; },
  'maximumPrompts of 2': c => { c.worker.maximumPrompts = 2; },
  'a string turn limit': c => { c.worker.maximumTurns = '30'; },
  'a zero timeout': c => { c.worker.timeoutSeconds = 0; },
  'a negative budget': c => { c.worker.maximumBudgetUsd = -1; },
  'a token budget below 10,000': c => { c.worker.maximumTokens = 9999; },
  'a token budget above 100,000,000': c => { c.worker.maximumTokens = 100000001; },
  'a relative Claude executable': c => { c.claudeUsage.executable = 'claude'; },
  'a .cmd Claude wrapper': c => { c.claudeUsage.executable = '/usr/bin/claude.cmd'; },
  'unknown claudeUsage fields': c => { c.claudeUsage.args = ['x']; },
  'a non-object boardPickup': c => { c.boardPickup = []; },
};
for (const [name, mutate] of Object.entries(mutations)) {
  test(`rejects ${name}`, () => { const c = good(); mutate(c); assert.throws(() => validateConfig(c), /Invalid Matrix configuration/); });
}

test('token budget bounds are inclusive', () => {
  for (const maximumTokens of [10000, 100000000]) { const c = good(); c.worker.maximumTokens = maximumTokens; assert.doesNotThrow(() => validateConfig(c)); }
});

test('readConfig reads JSON from disk and refuses anything else', t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'matrix-config-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const file = path.join(dir, 'worker.json');
  fs.writeFileSync(file, JSON.stringify(good()));
  assert.equal(readConfig(file).repositorySlug, 'tonygward/psfdx');
  fs.writeFileSync(file, '{broken');
  assert.throws(() => readConfig(file), /could not be read/);
  assert.throws(() => readConfig(path.join(dir, 'missing.json')), /could not be read/);
});

test('policy constants match the execution policy', () => {
  assert.equal(WEEKLY_LIMIT_PERCENT, 60); assert.equal(BATCH_LIMIT, 1); assert.equal(MODEL, 'sonnet');
  assert.equal(MAXIMUM_RUN_MINUTES, 120); assert.equal(MAXIMUM_REPAIRS, 3);
});

test('usageGate blocks at 60 percent, stale, future-dated and malformed readings', () => {
  const now = Date.parse('2026-11-14T12:00:00Z');
  const snap = (over = {}) => ({ source: 'claude-code-usage-report-weekly-all', percentage: 10, observedAt: new Date(now - 1000).toISOString(), resetsAt: new Date(now + 86400000).toISOString(), ...over });
  assert.equal(usageGate(snap(), now).allowed, true);
  assert.equal(usageGate(snap({ percentage: 60 }), now).allowed, false);
  assert.equal(usageGate(snap({ observedAt: new Date(now - 61000).toISOString() }), now).allowed, false);
  assert.equal(usageGate(snap({ observedAt: new Date(now + 5000).toISOString() }), now).allowed, false);
  assert.equal(usageGate(snap({ resetsAt: new Date(now + 9 * 86400000).toISOString() }), now).allowed, false);
  assert.equal(usageGate(snap({ source: 'cache' }), now).allowed, false);
  assert.equal(usageGate(null, now).allowed, false);
});

test('the daily slot opens once per London day, after 02:00', () => {
  const before = new Date('2026-11-14T01:59:00Z'), after = new Date('2026-11-14T02:01:00Z');
  assert.equal(dailyDue(undefined, '02:00', before), false);
  assert.equal(dailyDue(undefined, '02:00', after), true);
  assert.equal(dailyDue(londonDay(after), '02:00', after), false);
  assert.equal(dailyDue('2026-11-13', '02:00', after), true);
  assert.throws(() => dailyDue(undefined, '2am', after), /Invalid dailyTime/);
});

test('the London day follows British Summer Time', () => {
  // 23:30 UTC on 1 July is 00:30 on 2 July in London.
  assert.equal(londonDay(new Date('2026-07-01T23:30:00Z')), '2026-07-02');
  assert.equal(dailyDue('2026-07-01', '02:00', new Date('2026-07-02T00:30:00Z')), false);
  assert.equal(dailyDue('2026-07-01', '02:00', new Date('2026-07-02T01:30:00Z')), true);
});
