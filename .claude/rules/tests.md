---
paths:
  - "**/*.Tests.ps1"
---

# Pester tests

Every bug fix and new cmdlet needs a test. The tests never call a real org or need the Salesforce CLI. Warnings about unapproved verbs while the tests run are expected.

## Loading

- At the top of the file, remove any loaded copies (`Get-Module -Name ... -All | Remove-Module`), then `Import-Module` the manifest by path from `$PSScriptRoot`.
- If the module under test calls another module's cmdlets, import that module's manifest first. `psfdx-logs.Tests.ps1` and `psfdx-development.Tests.ps1` import `psfdx` this way.
- Run tests inside `InModuleScope '<module>'`, so private functions and mocks resolve in the module's scope.
- Add `-ModuleName <module>` to `Mock` and `Assert-MockCalled` whenever the mocked function is called from a different module than the one in scope. `psfdx.Tests.ps1` also passes `-ModuleName $module.Name` inside its own scope. That's redundant but harmless; follow whatever the file you're editing does.

## Mocking and asserting

- Mock `Invoke-Salesforce` and assert the command string. That string is the contract, and asserting it is what catches malformed SOQL. Prefer an exact match:
  `Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf apex log list --target-org me --json' }`.
  Fall back to several `-like` clauses only when part of the string is unpredictable, such as a temp path. A `-like` check on the start of the query alone once let a clobbered SELECT clause through.
- Inside a *single-quoted* expected string, write a literal SOQL quote as `''`: `'... WHERE EventType = ''Login'' ...'`. Inside a *double-quoted* one, write quoted paths as `` `"$($dir.FullName)`" ``.
- Have the mock return realistic JSON (`'{"status":0,"result":{...}}'`) rather than mocking `Show-SalesforceResult`. Then the real result handling runs too. Mock `Show-SalesforceResult` only when the shape is beside the point.
- If the cmdlet delegates to another module (e.g. `Get-SalesforceApexClass` → `Select-SalesforceRecords` in psfdx), mock in that module: `Mock Invoke-Salesforce { $json } -ModuleName 'psfdx'`.
- psfdx-metadata's `-Type` ValidateSet generator runs inside a class at parameter-binding time, so Pester mocks never reach it. Describe blocks that pass `-Type` stub the CLI with `function global:sf { '{"status":0,"result":{"metadataObjects":[]}}' }` in `BeforeAll`, and remove it in `AfterAll`. Call `Clear-SalesforceMetadataTypeCache` when a test depends on the cache.
- For input validation, use `{ ... } | Should -Throw -ExpectedMessage '...'` and then `Assert-MockCalled Invoke-Salesforce -Times 0`. Don't use try/catch with a `$threw` flag.
- Wrap results in `@(...)` before checking `.Count` or indexing. A single result unrolls to a scalar, and a single hashtable's `.Count` is its number of keys, not 1. Several mocks return `@{...}`.
- `$Command` is a string. Don't copy the old `($Command -join ' ')` from psfdx-logs, which dates from the removed `-Arguments` parameter.
- Don't copy the `Mock Describe-SalesforceMetadataTypes ... -ModuleName 'psfdx-metadata'` in `psfdx-development.Tests.ps1`. psfdx-development no longer calls it.

## Files

- New tests write files under `$TestDrive`, which Pester cleans up. Many existing tests create folders under `[System.IO.Path]::GetTempPath()` with try/finally. Don't copy that, and never write into the repo.
- Use `-Skip:(!$IsWindows)` for Windows-only behaviour. That's fine here, because tests run under `pwsh`.
