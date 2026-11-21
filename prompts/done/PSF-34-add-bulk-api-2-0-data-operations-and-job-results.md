---
id: PSF-34
priority: medium
effort: high
dependencies: []
conflicts: []
---

# PSF-34: Add Bulk API 2.0 data operations and job results

**Tracking issue:** https://github.com/tonygward/psfdx/issues/188

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #215, released as 0.8.29.

## Objective

Let PowerShell scripts move large datasets and inspect asynchronous job outcomes.

## What was delivered

- `Export-SalesforceBulkData`, `Import-SalesforceBulkData`, `Update-SalesforceBulkData` and `Upsert-SalesforceBulkData` wrap `sf data export|import|update|upsert bulk`; `Resume-SalesforceBulkJob` wraps the four `resume` commands; `Get-SalesforceBulkResult` wraps `sf data bulk results` and saves the CLI's success, failed and unprocessed CSVs into `-OutputDirectory`.
- Without `-WaitMinutes` a command creates the job and returns its `JobId`; with it the counts come back. The upsert commands return `{ jobInfo, records }`, which is normalised to the same object as the others.
- A job with failed rows, or one that fails or aborts, throws `PsfdxBulkJobFailed` (TargetObject holds `JobId` and `State`), including an upsert the CLI reports as a success. `Get-SalesforceBulkResult` warns about failed rows but does not throw.
- The three write commands use `ShouldProcess` (ConfirmImpact Medium, so no prompt by default) and name the object, file and org; `-WhatIf` makes no CLI call.
- Limitation: import, update and export resumes find the org from the CLI's local record of the job, so a job created elsewhere cannot be resumed there; `Get-SalesforceBulkResult -TargetOrg` works for any job.
- Not run against a real org; flags were checked against the plugin-data source and the live CLI help lane. `sf data delete bulk` was not in scope.

## Tests

Exact argv for every command, CSV paths with spaces, upsert validation, both result shapes, partial failure, CLI failures, malformed output, and no CLI call under `-WhatIf`.

## Release

Version 0.8.29. Changelog: psfdx: the Bulk API 2.0 commands.
