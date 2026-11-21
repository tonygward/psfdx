---
id: PSF-44
priority: medium
effort: high
dependencies: []
conflicts: []
---

# PSF-44: Complete asynchronous Apex test run and result lifecycle

**Tracking issue:** https://github.com/tonygward/psfdx/issues/207

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #220. Release: 0.8.32.

## Objective

Make Apex test runs, asynchronous reporting and coverage usable end-to-end from PowerShell and CI.

## What was delivered

- Audit: `Test-SalesforceApex` (run and wait in one call) and `Get-SalesforceCodeCoverage` are unchanged and a test pins the old behaviour.
- `Start-SalesforceApexTest` (`sf apex run test`, asynchronous) returns the `TestRunId`; `-CodeCoverage` must be given here because Salesforce only collects coverage for a run that asked for it.
- `Get-SalesforceApexTestResult` (`sf apex get test`) returns Summary, per-test Outcome and RunTime, optional Coverage and `Completed`. `sf apex get test` waits for an unfinished run, so the cmdlet first checks the run's queue items with a query and returns `Completed = $false` at once for a run still queued or processing.
- `Wait-SalesforceApexTest` polls until the run finishes or `-TimeoutMinutes` pass (`PsfdxTestRunTimeout`, with the run ID as TargetObject). Failing tests write the results then throw `PsfdxTestsFailed`; invocation failures throw `PsfdxTestRunInvocationFailed`.
- The help has a start-now, read-later-in-another-shell example. The Flow and combined commands from #191 share the result helper and now also report `Completed`.
- Not run against a real org.

## Tests

Synchronous compatibility, asynchronous start, in-progress, finished, failing, timeout, malformed and CLI-error paths, with exact argv.

## Changelog

psfdx-development: the three lifecycle commands.
