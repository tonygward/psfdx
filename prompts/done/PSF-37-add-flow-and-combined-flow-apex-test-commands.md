---
id: PSF-37
priority: medium
effort: medium
dependencies: []
conflicts: []
---

# PSF-37: Add Flow and combined Flow/Apex test commands

**Tracking issue:** https://github.com/tonygward/psfdx/issues/191

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #213, released as 0.8.28.

## Objective

Let teams run Flow tests, and mixed Flow and Apex suites, from PowerShell CI.

## What was delivered

- `Test-SalesforceFlow` and `Get-SalesforceFlowTestResult` (`sf flow run test`, `sf flow get test`); `Test-SalesforceLogic` and `Get-SalesforceLogicTestResult` (`sf logic run test`, `sf logic get test`, beta in the CLI). `Test-SalesforceApex` is unchanged.
- Asynchronous by default, returning `TestRunId`; `-Synchronous` (and `-WaitMinutes` for logic) wait. A finished run returns one object with `Summary`, `Tests` and `Coverage`.
- Failed tests throw `PsfdxTestsFailed` after the result is written; a command that could not run throws `PsfdxTestRunInvocationFailed`, with a plugin install hint when the plugin is missing.
- A synchronous run omits `--json`, because with it the CLI returns a run ID at once for any run except RunSpecifiedTests. `-TestCategory` needs `-TestLevel`, as the CLI requires.
- Not run against a real org; flags were checked against the plugin sources and the live CLI help lane.

## Tests

Exact argument lists for every command, passed, failed, asynchronous, not-run and missing-plugin results, coverage, malformed output and input validation.

## Release

Version 0.8.28. Changelog: psfdx-development: the four new commands.
