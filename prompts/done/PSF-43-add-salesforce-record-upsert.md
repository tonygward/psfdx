---
id: PSF-43
priority: medium
effort: medium
dependencies: []
conflicts: []
---

# PSF-43: Add Salesforce record upsert and repeatable data mutation workflows

**Tracking issue:** https://github.com/tonygward/psfdx/issues/206

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #212, released as 0.8.27.

## Objective

Support idempotent single-record upserts with PowerShell-native parameters and structured results.

## What was delivered

- `Upsert-SalesforceRecord` (psfdx). The CLI has no `sf data upsert record` (only `sf data upsert bulk`), so it sends PATCH `/services/data/vXX.X/sobjects/<Type>/<ExternalIdField>/<value>` through `sf api request rest`.
- Result: `Operation` (Created or Updated), `Created`, `Id` and `StatusCode`. HTTP 201 is a create with an Id; 200 (API v46 and later) is an update with an Id; 204 (older versions) is an update with no Id. Anything else, including 300 and 4xx, throws.
- The JSON body goes through a temporary file (`--body @file`) because the Windows `.cmd` shim rejects double quotes; the file is removed afterwards. Object and field names are validated and the external ID is URL-escaped.
- Bulk upserts (#188) and single-record get/delete (#195) are separate and not duplicated.

## Tests

Create, both update forms, missing external ID, malformed input, CLI error, HTTP errors, multiple match, argument safety and the export.

## Release

Version 0.8.27. Changelog: psfdx: new `Upsert-SalesforceRecord`.
