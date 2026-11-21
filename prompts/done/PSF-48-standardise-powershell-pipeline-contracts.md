---
id: PSF-48
priority: low
effort: medium
dependencies: []
conflicts: []
---

# PSF-48: Standardise PowerShell pipeline input and output contracts across resource cmdlets

**Tracking issue:** https://github.com/tonygward/psfdx/issues/211

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #231. Release: 0.8.38.

## Objective

Make common psfdx resource operations compose reliably in idiomatic PowerShell pipelines without surprising output shapes.

## What was delivered

- Audit: only `Disable-SalesforceDebugLogging` took pipeline input among the resource cmdlets. The records, trace flags and package versions family was adopted.
- `Get-`, `Remove-` and `Set-SalesforceRecord` take `-Id` from the pipeline (alias `RecordId`); `-Type` stays explicit because query results carry no object type.
- `Remove-` and `Promote-SalesforcePackageVersion` take `SubscriberPackageVersionId` from `Get-SalesforcePackageVersions`.
- Every piped object is its own `ShouldProcess`. `New-` and `Set-SalesforceRecord` gained `-WhatIf` and `-Confirm` (ConfirmImpact Medium, so no new prompts by default).
- Empty results emit nothing (wrap in `@(...)` for an empty array); a single result is unrolled; a CLI failure throws its message; an invalid piped ID is an error for that record. All documented in a README Pipelines section.
- No breaking change. Other families (metadata, sandboxes, logs) are follow-ups.

## Tests

Pipe a query into delete, get and update; `-WhatIf` makes no call; the `RecordId` alias; empty query; single-record unrolling; invalid piped ID; a failed delete mid-pipeline; package version delete and promote; trace flag delete; existing explicit-parameter calls unchanged.

## Changelog

psfdx, psfdx-packages: pipeline contracts for records, package versions and trace flags.
