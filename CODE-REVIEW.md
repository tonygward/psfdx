# psfdx — Code Review

**Date:** 2026-09-09
**Commit reviewed:** `0817630` (branch `master`, clean tree)
**Scope:** all six modules, shared helpers, install/uninstall scripts, CI workflow, docs
**Test suite at time of review:** 79/79 Pester tests passing

---

## Overall

Well-organised for what it is: a thin, consistent wrapper over the `sf` CLI. Six modules with clear separation, a shared `Invoke-Salesforce`/`Show-SalesforceResult` pair, a real test suite, and CI. The consistent `if ($X) { $command += " --flag $X" }` idiom makes the code easy to scan.

Findings below are ordered worst-first. Everything marked *reproduced* was executed against the working tree, not inferred from reading.

---

## Blocking bugs

### 1. `psfdx-metadata`: the `-Type` ValidateSet rejects every real metadata type

`psfdx-metadata/psfdx-metadata.psm1:4`

`Describe-SalesforceMetadataTypes` ends with `Select-Object xmlName` (`psfdx-metadata/psfdx-metadata.psm1:274`), returning `PSCustomObject`s rather than strings. `SalesforceMetadataTypeGenerator.GetValidValues()` then stringifies them into `@{xmlName=ApexClass}`.

Reproduced:

```
PS> Retrieve-SalesforceComponent -Type 'ApexClass' -Name 'Foo'
Cannot validate argument on parameter 'Type'. The argument "ApexClass" does not belong
to the set "CustomField,ValidationRule" specified by the ValidateSet attribute.
```

`Retrieve-SalesforceComponent` and `Deploy-SalesforceComponent` are therefore unusable for anything except `CustomField` / `ValidationRule` (the two literals appended by hand in the generator). `Retrieve-SalesforceField` and `Retrieve-SalesforceValidationRule` still work for that reason.

**Fix:** `Select-Object -ExpandProperty xmlName`.

**Two related problems in the same generator:**

- It shells out to `sf org list metadata-types` during *parameter binding*, so every call — and every tab-completion — makes an authenticated network round-trip. It fails outright when unauthenticated or offline.
- Consider a static list, or dropping the `ValidateSet` in favour of an `ArgumentCompleter`, which does not block binding.

### 2. `Export-SalesforceEventFiles` builds invalid SOQL

`psfdx-logs/psfdx-logs.psm1:350` — `=` instead of `+=`, clobbering the SELECT clause.

Reproduced (mocked `Invoke-Salesforce`, captured command):

```
sf data query --query " FROM EventLogFile WHERE EventType = 'ApiEvent' ORDER BY LogDate DESC LIMIT 5" --result-format json
```

The function can never succeed. `Select-SalesforceEventFiles`, ten lines above, builds the same query correctly — the two should share one query builder.

### 3. `New-SalesforceProject -DefaultUserName` throws

`psfdx-development/psfdx-development.psm1:37`

Calls `Set-SalesforceTargetOrg -DefaultUserName ... -ProjectFolder ...`, but that function accepts only `-Value` and `-Global`. Parameter-binding error. The surrounding code also creates a `.sfdx` directory that `sf config set` does not consume that way.

---

## Security

### 4. `Invoke-Salesforce` runs `Invoke-Expression` on a concatenated string

`psfdx-shared/Invoke-Salesforce.ps1:8`

Every parameter in the repo is interpolated into that string unquoted, so any value containing `;`, a backtick, `$(...)`, or `|` executes as PowerShell.

Reproduced:

```powershell
$Alias = 'x; Write-Host "INJECTED: arbitrary code ran"'
# → alias-set-x
#   INJECTED: arbitrary code ran
```

Low risk when arguments are typed by hand; a real hole the moment a value comes from a CSV, a CI variable, or an org record.

**Structural fix:** build `$args` as an array and invoke `& sf @args`. No `Invoke-Expression`, no quoting concerns. This is a large refactor, but it also removes the scattered `` `"$X`" `` quoting that currently only some parameters receive.

### 5. SOQL injection in query builders

Interpolate straight into SOQL with no escaping:

- `Get-SalesforceUsers -Username` (`psfdx/psfdx.psm1`)
- `Get-SalesforceApexClass -Name` (`psfdx-development/psfdx-development.psm1`)
- `Get-SalesforceRecordType -ObjectType` (`psfdx/psfdx.psm1`)
- `Select-SalesforceEventFiles -EventType` (`psfdx-logs/psfdx-logs.psm1`)

`Get-SalesforceSandboxRefreshStatus` and `Get-SalesforceLoginHistory` already do it right (`$Name -replace "'", "''"`). Apply that consistently.

### 6. Credentials typed as plain `[string]`

`Connect-SalesforceApi` takes `$Password`, `$Token`, and `$ClientSecret` as `[string]`, so they land in PowerShell history and transcripts. `[securestring]` or `[pscredential]` would be idiomatic.

### 7. No `SupportsShouldProcess` on destructive cmdlets

- `Remove-SalesforceScratchOrgs` — deletes *every* scratch org, no prompt
- `Remove-SalesforceSandbox`
- `Remove-SalesforcePackage`
- `Remove-SalesforcePackageVersion`
- `Disconnect-Salesforce -All`

`uninstall.ps1` gets this right; the modules should too, with `ConfirmImpact='High'`.

---

## Correctness / usability

- **Installers only work from the repo directory.** `install.ps1:25` and `install-windows.ps1:29` use `(Get-Location).Path` instead of `$PSScriptRoot`. Running `pwsh -File C:\dev\psfdx\install.ps1` from anywhere else silently installs nothing — the skip goes to `Write-Verbose`. Same bug in both files.
- **`Out-Notepad` is a silent no-op on Windows PowerShell 5.1** (`psfdx-logs/psfdx-logs.psm1:390`). `$IsWindows` does not exist there, so it evaluates to `$null`. The manifest claims `Desktop` edition support.
- **`Select-SalesforceRecords -ResultFormat csv|human` crashes** (`psfdx/psfdx.psm1:194`). The result is unconditionally piped to `ConvertFrom-Json`. Either drop the non-JSON choices or branch on them, as `Test-SalesforceApex` does.
- **`Get-SalesforceFlowInterviews -Type` is `Mandatory` *and* has a default** (`psfdx-logs/psfdx-logs.psm1:148`). The `= 'All'` never applies; users get prompted.
- **Duplicate ValidateSet entry**: `'ApexUnitTest'` listed twice at `psfdx-development/psfdx-development.psm1:580`.
- **`Convert-SalesforceDebugLog` and `Out-Notepad` declare `ValueFromPipeline` but have no `process` block** — piping multiple items silently processes only the last.
- **`Select-SalesforceRecords` writes `$result` to the pipeline before throwing** on error, emitting a bogus object alongside the exception.
- `Convert-SalesforceDebugLog`'s `Get-Variable`/`Set-Variable` loop over `@('dt','lt','st','de')` does by reflection what four plain `if` statements would do more clearly.
- `uninstall.ps1:52` uses single quotes around a message containing `$Scope`, so the variable is printed literally rather than interpolated.
- `uninstall.ps1` help text refers to `uninstall-linux.ps1`, a filename that no longer exists in the repo.

---

## Packaging

- **`psfdx-development` declares `RequiredModules = @('psfdx-metadata')` but actually depends on `psfdx`.** `Get-SalesforceCodeCoverage` and `Get-SalesforceApexClass` call `Select-SalesforceRecords`, which lives in `psfdx`. It works today only because the tests import `psfdx` manually.
- **`psfdx-shared` is installed as a module directory but contains no manifest**, and the modules reach it via `Join-Path $PSScriptRoot '..' 'psfdx-shared'`. That sibling-directory coupling blocks PowerShell Gallery publishing and breaks if a module is installed alone.
- **`Prerelease = 'beta'`** in `psfdx-development.psd1` marks the whole module prerelease — likely unintended at v0.8.
- **`psfdx.psd1` and `psfdx-sandbox.psd1` are missing** `PowerShellVersion`, `CompatiblePSEditions`, and `PrivateData.PSData`, which the other four manifests have.
- **No LICENSE file** anywhere in the repo, and no `LicenseUri` in any manifest.
- **Unapproved verbs** (`Retrieve-`, `Describe-`, `Promote-`) produce an import warning on every load. If you keep them, `Export-ModuleMember` an approved-verb alias (`Get-` / `Publish-`).
- **No comment-based help on any of the ~90 exported functions** — `Get-Help Connect-Salesforce -Examples` returns nothing. The README carries all of it.
- **CHANGELOG**: everything sits under `## Unreleased` while all six manifests report `ModuleVersion = '0.8'`.

---

## Tests & CI

The suite is genuinely useful — 79 tests, good `Invoke-Salesforce` mocking, and it asserts exact command strings, which is the right shape for a CLI wrapper. Gaps:

- **`psfdx-metadata` has no test file at all** — which is precisely why finding #1 shipped. It is also the module with the most logic (the type generator, `Build-SalesforceQuery`).
- **`Export-SalesforceEventFiles` has a passing test** despite emitting invalid SOQL, because the test never asserts the query string. Asserting `--query` content would have caught it.
- **CI runs on `pull_request` only** — nothing validates pushes to `master`. The three doc-only commits at the tip of `master` never ran.
- **The `os` matrix has `fail-fast: false` and matrix scaffolding for exactly one OS** (`ubuntu-latest`). For a project that ships a separate `install-windows.ps1` and has `$IsWindows` branching, add `windows-latest`.
- **No PSScriptAnalyzer step.** It would flag several items above mechanically.
- Running the suite writes a `.csv` into the repo root (from the `Export-SalesforceEventFiles` test). Tests should write to `$TestDrive`.

---

## Suggested order of work

1. Fix findings #1, #2, #3 — three small edits, each turning a dead command back on.
2. Add a `psfdx-metadata` test file; assert query strings in the logs tests.
3. Fix `$PSScriptRoot` in both installers.
4. Add `SupportsShouldProcess` to the six destructive cmdlets, and SOQL-escape the four injection points.
5. Plan the `Invoke-Expression` → `& sf @args` refactor as its own change, behind the now-solid test suite.
