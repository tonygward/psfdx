---
id: PSF-40
priority: medium
effort: medium
dependencies: []
conflicts: []
---

# PSF-40: Add Salesforce Code Analyzer commands

**Tracking issue:** https://github.com/tonygward/psfdx/issues/194

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #228. Release: 0.8.36.

## Objective

Let teams script static analysis and report on rules and violations in PowerShell.

## What was delivered

- `Invoke-SalesforceCodeAnalyzer` (`sf code-analyzer run`) and `Get-SalesforceCodeAnalyzerRule` (`sf code-analyzer rules`) in psfdx-development.
- The CLI commands have no `--json` flag, so findings are read from a temporary JSON report file and the process exit code decides the outcome.
- A threshold failure (non-zero exit, report written) is returned as ThresholdExceeded with the findings, or thrown with `-ThrowOnThreshold` (PsfdxCodeAnalyzerThresholdExceeded). No report is a plugin or engine failure and always throws PsfdxCodeAnalyzerFailed, with install and Java guidance.
- Not run against a real CLI; the report JSON shape comes from the documentation.

## Tests

Exact argv with a temporary report, finding mapping, report cleanup, threshold results, startup failures, missing plugin, rule listing and exports.

## Changelog

psfdx-development: the two Code Analyzer commands.
