// Local tests before any push. The trusted worker, not Claude, runs Pester in the worktree through a sandbox wrapper
// (built by AUTO-09): a separate test user with no network and no access to secrets, state or other worktrees, a time
// limit and a process-tree kill. The code under test was written by the agent, so it gets no more access than the agent.
import fs from 'node:fs';
import path from 'node:path';
import { runProcess } from './process.mjs';

export const DEFAULT_TEST_TIMEOUT_SECONDS = 600;
export const DEFAULT_LOCAL_REPAIRS = 5;

// Exit codes of the sandbox wrapper: 0 tests ran and passed, 1 tests ran and failed, 124 timed out, 125 refused
// (it tried to reach the network or the secrets), anything else is a sandbox error.
export const EXIT = Object.freeze({ passed: 0, failed: 1, timeout: 124, refused: 125 });

// The command the wrapper runs inside the sandbox. Pester 5 comes from the image; the repository tests are included.
export function pesterCommand(resultsFile) {
  const out = String(resultsFile).replace(/'/g, "''");
  return ['pwsh', '-NoProfile', '-NonInteractive', '-Command',
    `Import-Module Pester -MinimumVersion 5.0.0 -MaximumVersion 5.99.99; $c = New-PesterConfiguration; $c.Run.Path = '.'; $c.Run.Exit = $true; $c.TestResult.Enabled = $true; $c.TestResult.OutputPath = '${out}'; Invoke-Pester -Configuration $c`];
}

// Reads a Pester NUnit file. Returns counts and the failing tests with their messages.
export function summariseResults(xml) {
  const text = String(xml ?? '');
  const head = /<test-results\b[^>]*>/.exec(text)?.[0];
  if (!head) throw new Error('Pester results file is not valid');
  const num = name => Number(new RegExp(`\\b${name}="(\\d+)"`).exec(head)?.[1] ?? NaN);
  const total = num('total'), failures = num('failures'), errors = num('errors'), skipped = num('not-run');
  if (![total, failures, errors].every(Number.isFinite)) throw new Error('Pester results file has no totals');
  const failing = [];
  for (const match of text.matchAll(/<test-case\b([^>]*)>([\s\S]*?)<\/test-case>/g)) {
    if (!/\bresult="(?:Failure|Error)"/.test(match[1])) continue;
    const name = /\bname="([^"]*)"/.exec(match[1])?.[1] ?? 'unknown test';
    const message = /<message>\s*(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))\s*<\/message>/.exec(match[2]);
    failing.push({ name: decode(name), message: decode((message?.[1] ?? message?.[2] ?? '').trim()).slice(0, 2000) });
  }
  const pesterVersion = /Pester[^"\n]*?(5\.\d+\.\d+)/.exec(text)?.[1] ?? null;
  return { total, failed: failures + errors, passed: Math.max(0, total - failures - errors - (Number.isFinite(skipped) ? skipped : 0)), failing, pesterVersion };
}
const decode = text => text.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');

// The real sandbox adapter: `testRunner` is the wrapper's absolute path. Tests inject a fake instead.
export function sandboxRunner(testRunner, run = runProcess) {
  return async ({ worktree, resultsFile, timeoutSeconds }) => {
    const started = Date.now();
    try {
      await run(testRunner, [worktree, resultsFile, String(timeoutSeconds), ...pesterCommand(resultsFile)], { cwd: path.dirname(worktree), timeoutMs: (timeoutSeconds + 30) * 1000 });
      return { exitCode: EXIT.passed, durationMs: Date.now() - started };
    } catch (error) {
      if (error.exitCode !== undefined) return { exitCode: error.exitCode, durationMs: Date.now() - started };
      if (/timed out/.test(error.message)) return { exitCode: EXIT.timeout, durationMs: Date.now() - started };
      throw new Error('The test sandbox could not be started');
    }
  };
}

/**
 * Runs the tests once. Returns { status: 'passed'|'failed'|'timeout'|'refused'|'error', ...details, failureFile? }.
 * On failure the failing tests and messages go to a file the next attempt can read; they are never pasted into prompts.
 */
export async function runLocalTests({ sandbox, worktree, taskFolder, timeoutSeconds = DEFAULT_TEST_TIMEOUT_SECONDS }) {
  const resultsFile = path.join(taskFolder, 'testResults.xml');
  const failureFile = path.join(taskFolder, 'local-test-failure.txt');
  fs.rmSync(resultsFile, { force: true });
  let outcome;
  try { outcome = await sandbox({ worktree, resultsFile, timeoutSeconds }); }
  catch (error) { return { status: 'error', summary: String(error.message).slice(0, 200) }; }
  const { exitCode, durationMs = 0 } = outcome;
  if (exitCode === EXIT.timeout) return { status: 'timeout', durationMs, summary: `The local tests did not finish within ${timeoutSeconds} seconds` };
  if (exitCode === EXIT.refused) return { status: 'refused', durationMs, summary: 'The sandbox refused the test run (it tried to reach the network or the secrets)' };
  if (exitCode !== EXIT.passed && exitCode !== EXIT.failed) return { status: 'error', durationMs, summary: `The test sandbox failed (exit code ${exitCode})` };
  let results;
  try { results = summariseResults(fs.readFileSync(resultsFile, 'utf8')); }
  catch { return { status: 'error', durationMs, summary: 'The local tests produced no readable results file' }; }
  const passed = exitCode === EXIT.passed && results.failed === 0;
  const details = { durationMs, passed: results.passed, failed: results.failed, total: results.total, pesterVersion: results.pesterVersion };
  if (passed) { fs.rmSync(failureFile, { force: true }); return { status: 'passed', ...details }; }
  const lines = [`Local Pester run: ${results.failed} failed, ${results.passed} passed.`, '', ...results.failing.flatMap(f => [`FAILED: ${f.name}`, f.message, ''])];
  fs.writeFileSync(failureFile, lines.join('\n'));
  return { status: 'failed', ...details, failureFile, summary: `${results.failed} local test(s) failed` };
}
