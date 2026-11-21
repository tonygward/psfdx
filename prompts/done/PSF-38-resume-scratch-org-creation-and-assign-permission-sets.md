---
id: PSF-38
priority: medium
effort: medium
dependencies: []
conflicts: []
---

# PSF-38: Resume scratch org creation and assign permission sets

**Tracking issue:** https://github.com/tonygward/psfdx/issues/192

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #227. Release: 0.8.35.

## Objective

Let provisioning scripts recover an asynchronous scratch org creation and configure access afterward.

## What was delivered

- `Resume-SalesforceScratchOrg` (`sf org resume scratch`) by `-JobId` (2SR...) or `-UseMostRecent`, with `-WaitMinutes`; returns the org with a Completed flag.
- A creation still running when the wait ends (the CLI error StillInProgressError) returns Completed = false with Status InProgress so scripts can poll; failures throw the CLI message.
- `New-SalesforceScratchOrg` gained `-Async`.
- `sf org assign permset` was already wrapped by `Grant-SalesforcePermissionSet` in psfdx, so it was not duplicated; the help example shows create, resume, assign.
- Not run against a real org.

## Tests

Exact argv, completed and still-running creations, failures, invalid inputs, the new -Async flag, exports and examples.

## Changelog

psfdx-development: Resume-SalesforceScratchOrg and -Async.
