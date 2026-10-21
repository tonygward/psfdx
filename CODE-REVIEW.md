# psfdx — Code Review

**Date:** 2026-10-21
**Commit reviewed:** `737dd29` (branch `main`, clean tree)
**Scope:** all six modules, shared helpers, manifests, CI workflow, docs
**Test suite at time of review:** 149/149 Pester tests passing (PowerShell 7.6). Every module was also imported under Windows PowerShell 5.1.

This replaces the review from 2026-09-09 (commit `0817630`). The items from that review that have since been fixed are listed at the end.

---

## Overall

The codebase is in better shape than at the last review. The blocking bugs are gone, every module now has a test file, and the suite has nearly doubled. However, the manifests declare Windows PowerShell 5.1 support that one module doesn't have, and the `Invoke-Expression` problem has moved from theoretical to reproduced.

Findings are ordered worst-first. Everything marked *reproduced* was run against the working tree, not just inferred from reading the code.

---

## Blocking

### 1. `psfdx-metadata` does not load on Windows PowerShell 5.1 (*reproduced*)

`psfdx-metadata/psfdx-metadata.psm1:63`, `:297`, `:429`

```
PS 5.1> Import-Module ./psfdx-metadata/psfdx-metadata.psd1
Unable to find type [System.Management.Automation.IValidateSetValuesGenerator].
```

`IValidateSetValuesGenerator` and `[ValidateSet([Type])]` require PowerShell 6 or later. The manifest declares `PowerShellVersion = '5.1'` and `CompatiblePSEditions = @('Desktop','Core')`.

**Fix:** replace the ValidateSet with an `[ArgumentCompleter({...})]` that calls `Get-SalesforceMetadataTypeValidValues`, and validate `-Type` inside the function. An argument completer never blocks parameter binding, so binding also stops needing the org.

### 2. CI cannot catch #1

`.github/workflows/ci.yml` runs only on `ubuntu-latest` under `pwsh`, and only for `pull_request`.

**Fix:** add a `windows-latest` job with `shell: powershell` (Windows PowerShell 5.1), and also trigger on `push` to `master`.

---

## Security

### 3. Code execution through `Invoke-Expression` (*reproduced*)

`psfdx-shared/Invoke-Salesforce.ps1`

Every value interpolated inside a double-quoted `--query "..."` is evaluated by `Invoke-Expression`. The repro used a harmless payload:

```powershell
Get-SalesforceUsers -Username 'bob$(Write-Host PWNED)@example.com'
# PWNED
# sf receives: ... WHERE Username = 'bob@example.com'
```

SOQL escaping (`'` → `''`) does not help, so the cmdlets that already escape (`Get-SalesforceLoginHistory`, `Get-SalesforceSandboxRefreshStatus`) are affected as well. This is the outstanding `& sf @args` refactor. Treat it as the top non-blocking item: change `Invoke-Salesforce` to accept an argument array, then migrate one module at a time.

### 4. Unescaped SOQL values

These break the CLAUDE.md rule `$Value -replace "'", "''"`:

- `Get-SalesforceUsers -Username` (`psfdx/psfdx.psm1:379`)
- `Get-SalesforceRecordType -ObjectType` (`psfdx/psfdx.psm1:437`)
- `Get-SalesforceApexClass -Name` (`psfdx-development/psfdx-development.psm1:772`)
- `-EventType` in `Select-SalesforceEventFiles` and `Export-SalesforceEventFiles` (`psfdx-logs/psfdx-logs.psm1:343`, `:419`)

As a side effect, `Get-SalesforceLoginHistory` escapes `$Username` for its own query but then passes the raw value to `Get-SalesforceUsers` (`psfdx-logs/psfdx-logs.psm1:283`). A username containing `'` therefore breaks the second query.

### 5. Secrets in `-Verbose` output

- `Invoke-Salesforce` calls `Write-Verbose $Command`, so `New-SalesforcePackageVersion -InstallationKey` prints the key (`psfdx-packages/psfdx-packages.psm1:226`).
- `Connect-SalesforceApi` still takes `-Password`, `-Token` and `-ClientSecret` as plain `[string]`, so they end up in history and transcripts. Use `[securestring]` or `[pscredential]`.

### 6. No `SupportsShouldProcess` anywhere

No public cmdlet supports `-WhatIf` or `-Confirm`. The most urgent case is `Remove-SalesforceScratchOrgs`, which deletes **every** scratch org with `--no-prompt` and asks for no confirmation. These also need it:

- `Remove-SalesforceScratchOrg`
- `Remove-SalesforceSandbox`
- `Remove-SalesforcePackage`
- `Remove-SalesforcePackageVersion`
- `Disconnect-Salesforce`

Use `ConfirmImpact = 'High'` on the bulk and delete cmdlets.

---

## Correctness

### 7. Local time sent as UTC (*reproduced*)

At 08:47 BST, `Get-SalesforceDateTime` returned `2026-10-21T08:47:12Z`, an hour out. The `$dt.ToString('s') + 'Z'` pattern appears in:

- `Get-SalesforceDateTime` (`psfdx/psfdx.psm1:579`)
- `Get-SalesforceFlowInterviews -After` (`psfdx-logs/psfdx-logs.psm1:229`)
- `Get-SalesforceLoginHistory -After/-Before` (`:260`, `:261`)
- `Select-SalesforceEventFiles` and `Export-SalesforceEventFiles` `-After/-Before` (`:344`, `:345`, `:420`, `:421`)

**Fix:** call `.ToUniversalTime()` first, using one shared helper.

### 8. `Get-SalesforcePackagesInstalled` probably always returns `@()`

`psfdx-packages/psfdx-packages.psm1:137-143`

The function calls `Show-SalesforceResult -ReturnRecords`, but `sf package installed list --json` returns `result` as an array, not as `{ records: [] }`. The test mocks the wrong shape, so it passes anyway. The command it runs, `sf force package installed list`, is also deprecated; use `sf package installed list`. *Verify the JSON shape against a real org.*

### 9. Unquoted paths and free text break on spaces

Under `Invoke-Expression`, these values split into extra arguments:

- `New-SalesforcePackage`: `--description`, `--path` (`psfdx-packages/psfdx-packages.psm1:103`, `:105`)
- `New-SalesforcePackageVersion`: `--version-name`, `--version-description`, `--definition-file` (`:217`, `:218`, `:221`)
- `--output-dir` in `New-SalesforceProject`, `Test-SalesforceApex`, `New-SalesforceApexClass` and `New-SalesforceApexTrigger` (`psfdx-development/psfdx-development.psm1:79`, `:318`, `:798`, `:824`)
- `Invoke-SalesforceApex --file` (`:471`) and `New-SalesforceScratchOrg --definition-file` (`:248`)
- `Select-SalesforceRecords --output-file` (`psfdx/psfdx.psm1:348`)

As a result, a multi-word `-Description` fails today, and so does any path under a profile such as `C:\Users\Jane Doe`. The `& sf @args` refactor (#3) makes this whole class of bug go away.

### 10. `Open-Salesforce -BrowserPrivateMode` should be a switch

`psfdx/psfdx.psm1:199`, `:204`

The parameter is a `[string]` and is emitted as `--private <value>`, but `sf org open --private` is a boolean flag.

### 11. Package-name lookups silently fall through

- `Get-SalesforcePackageVersions -PackageName X` lists versions for *all* packages when `X` doesn't exist.
- `New-SalesforcePackageVersion -PackageName X` emits `--package ` with no value.

Both should throw "package not found".

### 12. `Retrieve-SalesforceOrg` uses a deprecated command

`psfdx-metadata/psfdx-metadata.psm1:404`

It runs `sf force source manifest create`; the current command is `sf project generate manifest`. It also hard-codes the output to `.`.

### 13. `psfdx-development` depends on `psfdx` without declaring it

`Get-SalesforceCodeCoverage` and `Get-SalesforceApexClass` call `Select-SalesforceRecords` from `psfdx`, but `psfdx-development.psd1` declares `RequiredModules = @()`. This only works through command autoloading. `psfdx-logs` declares the same dependency correctly.

---

## Consistency / maintainability

- **`Import-PsfdxSharedModule` has drifted in `psfdx-development`.** That copy adds `-ForceImport`, which breaks the "identical in all six modules" rule. The parameter exists only for a defensive re-import in `Get-SalesforceCliApexTestParams` (`psfdx-development/psfdx-development.psm1:370`), which shouldn't be needed. Remove the re-import and restore the identical copy.
- **`Get-SalesforceCliApexTestParams` (development) and `Get-SalesforceApexCliTestParams` (shared)** have near-identical names but do different jobs. Rename one, or fold it into the shared helper.
- **`Export-SalesforceEventFiles` still duplicates the query builder** from `Select-SalesforceEventFiles`. It should call `Select-SalesforceEventFiles`.
- **Some error handling bypasses `Show-SalesforceResult`**: `Select-SalesforceRecords`, `Get-SalesforceSandboxRefreshStatus` and `Get-SalesforceDebugLogs -Raw`. Their errors therefore lose the deploy and test failure detail.
- **`Export-SalesforceDebugLogs`** never calls `Write-Progress -Completed`.

---

## Tests & docs

- **25 exported cmdlets have no test**, against the CLAUDE.md rule. Notable ones are `Remove-SalesforceScratchOrgs`, `Get-SalesforceCodeCoverage`, `New-SalesforceScratchOrg`, `Disconnect-Salesforce`, `Open-Salesforce`, `Export-SalesforceDebugLogs`, `Get-SalesforceEventFile`, `Promote-SalesforcePackageVersion` and `Remove-SalesforcePackageVersion`.
- **Mocks that return the wrong JSON shape hide real bugs** (see #8). Mock with captured `sf ... --json` output.
- **README** has no rows for `Get-SalesforceLatestApiVersion` or `Clear-SalesforceMetadataTypeCache`.
- **CHANGELOG** says `Promote-SalesforcePackageVersion` was renamed to `Publish-SalesforcePackageVersion` with an alias. The code still has `Promote-` and `AliasesToExport = @()`. Correct the entry.
- **CLAUDE.md** says every manifest declares `PowerShellVersion = '5.1'`. `psfdx`, `psfdx-sandbox` and `psfdx-shared` don't.

---

## Still open from 2026-09-09

- `Invoke-Expression` → `& sf @args` (now #3), SOQL escaping (#4), plain-string credentials (#5), `SupportsShouldProcess` (#6).
- `psfdx-development` `RequiredModules` (#13).
- `Prerelease = 'beta'` is still set in `psfdx-development.psd1`.
- `psfdx.psd1` and `psfdx-sandbox.psd1` still lack `PowerShellVersion`, `CompatiblePSEditions` and `PrivateData.PSData`.
- There is no LICENSE file, and no manifest has a `LicenseUri`.
- No exported function has comment-based help.
- There is no PSScriptAnalyzer step in CI. CI also has no Windows job and doesn't run on push (#2).

## Fixed since 2026-09-09

- The metadata `-Type` ValidateSet stringified objects, and it called the org on every bind. It is now cached per session.
- `Export-SalesforceEventFiles` clobbered its SELECT clause.
- `New-SalesforceProject -DefaultUserName` threw.
- The `Get-SalesforceLoginHistory -Username` SOQL was invalid.
- `Select-SalesforceRecords -ResultFormat csv|human` crashed, and failed queries emitted the payload before throwing.
- `Out-Notepad` didn't work on 5.1, and the pipeline cmdlets lacked `process` blocks.
- The duplicate `ApexUnitTest` ValidateSet entry is gone.
- The installers now use `$PSScriptRoot`, and the `uninstall.ps1` message and help text are corrected.
- `psfdx-metadata` now has a test file, and `psfdx-shared` now has a manifest.

---

## Suggested order of work

Use one branch or PR per step, each with tests and a CHANGELOG entry.

1. **5.1 compatibility:** #1 and #2. Verify with `powershell.exe -NoProfile -Command "Import-Module ./psfdx-metadata/psfdx-metadata.psd1"`.
2. **Quick correctness:** #7, #10, #11, #8 and #4.
3. **Safety:** #6 and #5.
4. **`& sf @args` refactor (#3).** This also fixes #9, so skip piecemeal quoting fixes unless the refactor slips. Every `-Command` assertion in the tests will change.
5. **Cleanup:** #12, #13, then the consistency, tests and docs items.
