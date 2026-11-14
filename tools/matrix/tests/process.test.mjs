import test from 'node:test';
import assert from 'node:assert/strict';
import { runProcess, limitedEnvironment } from '../process.mjs';

const node = process.execPath;

test('runs a program without a shell and returns its output', async () => {
  const result = await runProcess(node, ['-e', 'process.stdout.write("hi " + process.argv[1])', '$(echo injected)']);
  assert.equal(result.stdout, 'hi $(echo injected)');
});

test('a failing program rejects with a fixed message and keeps its output out of the message', async () => {
  await assert.rejects(runProcess(node, ['-e', 'console.error("secret"); process.exit(3)']), error => {
    assert.equal(error.message, 'Process failed'); assert.equal(error.exitCode, 3); assert.ok(!error.message.includes('secret')); return true;
  });
});

test('a timeout stops the process', async () => {
  await assert.rejects(runProcess(node, ['-e', 'setTimeout(() => {}, 60000)'], { timeoutMs: 300 }), /timed out/);
});

test('the output limit stops the process', async () => {
  await assert.rejects(runProcess(node, ['-e', 'process.stdout.write("x".repeat(100000))'], { maximumBytes: 1000 }), /Output limit/);
});

test('a missing program is a fixed error', async () => {
  await assert.rejects(runProcess('definitely-not-a-program-xyz', []), /could not start/);
});

test('cancellation stops the process', async () => {
  await assert.rejects(runProcess(node, ['-e', 'setTimeout(() => {}, 60000)'], { cancelled: () => true }), /paused or approval expired/);
});

test('the environment is limited and carries no tokens', () => {
  const env = limitedEnvironment({ PATH: '/bin', HOME: '/h', GH_TOKEN: 'x', ANTHROPIC_API_KEY: 'y', RANDOM: 'z' });
  assert.deepEqual(Object.keys(env).sort(), ['GIT_CONFIG_NOSYSTEM', 'GIT_TERMINAL_PROMPT', 'HOME', 'NO_COLOR', 'PATH']);
  assert.equal(limitedEnvironment({}, { agent: true }).CLAUDE_CODE_MAX_OUTPUT_TOKENS, '8192');
});
