# PSF: Comprehensive SOQL builder and CLI result regression coverage

**Tracking issue:** https://github.com/tonygward/psfdx/issues/172

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #203, released as 0.8.25.

## Objective

Cover every place the modules build or run SOQL with regression tests, so malformed literals, escaping, empty results and CLI failures are caught without an org.

## What was delivered

- Table-driven "SOQL regression" tests in psfdx, psfdx-logs, psfdx-development, psfdx-sandbox and psfdx-metadata, using sanitised `sf data query --json` fixtures (success, empty, malformed, no auth).
- `docs/soql-testing.md`: an inventory of the query paths and an optional read-only live-org check (not run).
- Bug found by the tests and fixed: on Windows PowerShell 5.1 `Select-Object -ExcludeProperty attributes` needs `-Property *`, so query results kept the `attributes` property.

## Tests

Pester, run on Ubuntu pwsh, Windows pwsh and Windows PowerShell 5.1.

## Release

Version 0.8.25. Changelog: psfdx, psfdx-sandbox and psfdx-shared: query results no longer include `attributes` on 5.1.
