---
id: PSF-41
priority: medium
effort: medium
dependencies: []
conflicts: []
---

# PSF-41: Add dedicated Salesforce record get and delete commands

**Tracking issue:** https://github.com/tonygward/psfdx/issues/195

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #224. Release: 0.8.33.

## Objective

Complete single-record CRUD alongside the existing create and update cmdlets.

## What was delivered

- `Get-SalesforceRecord` (`sf data get record`) and `Remove-SalesforceRecord` (`sf data delete record`) in the core module. The record is selected by `-Id` or by `-Where` (a hashtable of field values), as separate parameter sets, matching the CLI's either/or; `-UseToolingApi` is supported.
- Get returns the record without the `attributes` property. Remove is ConfirmImpact High, names the object, record and org, makes no CLI call under `-WhatIf`, and returns the CLI result; a missing record or a `-Where` that matches several throws the CLI message.
- `-Where` values are written as `Field='value'`. A value with a quote or control character is refused because the CLI has no escape for it; the help points to `-Id` or SOQL instead.
- Not run against a real org.

## Tests

Exact argv for ID and field selectors, the Tooling API, result shape, not-found and multiple-match errors, conflicting selectors, input validation, and zero delete calls under WhatIf.

## Changelog

psfdx: the two record commands.
