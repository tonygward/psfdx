---
id: PSF-39
priority: medium
effort: medium
dependencies: []
conflicts: []
---

# PSF-39: Report asynchronous package creation and install jobs

**Tracking issue:** https://github.com/tonygward/psfdx/issues/193

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #224. Release: 0.8.33.

## Objective

Let CI recover package build and install results in a later step.

## What was delivered

- `Get-SalesforcePackageVersionCreateStatus` (`sf package version create report`, create request ID 08c, `-TargetDevHub`) and `Get-SalesforcePackageInstallStatus` (`sf package install report`, install request ID 0Hf, `-TargetOrg`).
- Both return Status, Completed, Succeeded, the IDs and Errors. A failed job is returned as a status so a script can read its errors; `-ThrowOnFailure` throws `PsfdxPackageJobFailed` for CI. A queued or running job returns `Completed = $false`.
- The help says which ID to capture: the `Id` (08c) from `New-SalesforcePackageVersion`, and the `Id` (0Hf) from the new `Install-SalesforcePackageVersion -AsObject`, which is additive and leaves the old output unchanged.
- The CLI reports a failed install as an error (name `packageInstallError`, "Encountered errors installing the package!") rather than a result, so that case is read from the error message; the numbered error list in that message is not verified against a real org.

## Tests

Exact argv with and without the Dev Hub or org, in-progress, successful and failed jobs, ID mapping, request ID validation (an install ID is not accepted as a create ID), the real failed-install error with and without details, and the backward-compatible install output.

## Changelog

psfdx-packages: the two status commands and -AsObject.
