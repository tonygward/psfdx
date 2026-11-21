---
id: PSF-35
priority: medium
effort: high
dependencies: []
conflicts: []
---

# PSF-35: Add Salesforce data tree export and import

**Tracking issue:** https://github.com/tonygward/psfdx/issues/189

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #218. Release: 0.8.31.

## Objective

Let teams copy related test records into scratch orgs and sandboxes.

## What was delivered

- `Export-SalesforceTreeData` (`sf data export tree`): one or more `-Query`, `-Plan`, `-Prefix`, `-OutputDirectory`. It returns the records, or with `-Plan` the file paths and the plan file (named `plan.json` for several queries, otherwise after the object types, as the CLI does).
- `Import-SalesforceTreeData` (`sf data import tree`): `-Plan` or `-File` as separate parameter sets, so they are mutually exclusive; `ShouldProcess` (Medium); returns `RefId`, `Type` and `Id`; rejected records throw `PsfdxTreeImportFailed` listing each reference, status code, message and fields.
- A parent-child example is in the help and changelog. The Tree API suits test data (200 records per import); Bulk API commands cover large loads.
- Not run against a real org.

## Tests

Exact argv for queries, plan, files with spaces, plan file naming, WhatIf, exclusive inputs, missing files, failed imports and CLI errors.

## Changelog

psfdx: the two data tree commands.
