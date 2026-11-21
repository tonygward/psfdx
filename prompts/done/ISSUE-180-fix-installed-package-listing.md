# PSF: Fix installed package listing JSON array handling

**Tracking issue:** https://github.com/tonygward/psfdx/issues/180

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #201, released as 0.8.23.

## Objective

`Get-SalesforcePackagesInstalled` returned nothing because it looked for a `records` list that the CLI does not send.

## What was delivered

- It now reads the result array directly, tolerates a `records` wrapper, and always returns an array.
- The `--target-org` check uses the standard ContainsKey/IsNullOrWhiteSpace guard.

## Tests

Zero, one and many packages, the `records` wrapper, a non-zero status and malformed JSON.

## Release

Version 0.8.23. Changelog: psfdx-packages: `Get-SalesforcePackagesInstalled` now returns the installed packages.
