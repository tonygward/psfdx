import test from 'node:test';
import assert from 'node:assert/strict';
import { budgetStop, runMinutes, DEFAULT_RUN_MINUTES, tokenStop, tokensUsed } from '../budget.mjs';

const start = Date.parse('2026-11-10T10:00:00Z');
const task = { runStartedAt: new Date(start).toISOString() };

test('the run budget is 120 minutes by default and configurable', () => {
  assert.equal(DEFAULT_RUN_MINUTES, 120);
  assert.equal(runMinutes({}), 120);
  assert.equal(runMinutes({ maximumRunMinutes: 45 }), 45);
});

test('the run stops at the limit, not before, and says why', () => {
  assert.equal(budgetStop(task, {}, start + 119 * 60000 + 59000), null);
  assert.match(budgetStop(task, {}, start + 120 * 60000), /Run time limit of 120 minutes/);
  assert.match(budgetStop(task, { maximumRunMinutes: 30 }, start + 31 * 60000), /30 minutes/);
});

test('no recorded start means no stop (nothing to count from), and bad dates never stop a run by accident', () => {
  assert.equal(budgetStop({}, {}, start + 9e9), null);
  assert.equal(budgetStop({ runStartedAt: 'not a date' }, {}, start + 9e9), null);
});

test('the optional token budget counts input, output and cache writes, not cache reads', () => {
  assert.equal(tokensUsed({ input_tokens: 10, output_tokens: 20, cache_creation_input_tokens: 5, cache_read_input_tokens: 9999 }), 35);
  assert.equal(tokensUsed(undefined), 0);
  assert.equal(tokensUsed({ input_tokens: -3, output_tokens: 'x' }), 0);
});

test('the token budget stops a run once it is used up, and is off when not configured', () => {
  assert.equal(tokenStop({ tokensUsed: 9e9 }, {}), null, 'no maximumTokens: no token limit');
  assert.equal(tokenStop({ tokensUsed: 999 }, { maximumTokens: 1000 }), null);
  assert.match(tokenStop({ tokensUsed: 1000 }, { maximumTokens: 1000 }), /Run token limit of 1000 tokens reached/);
  assert.equal(tokenStop({}, { maximumTokens: 1000 }), null, 'a fresh run starts at zero');
});
