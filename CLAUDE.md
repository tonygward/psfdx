# CLAUDE.md

psfdx is a set of cross-platform PowerShell modules that wrap the Salesforce CLI (`sf`). Each cmdlet builds an `sf ... --json` command string, runs it, and converts the JSON result into PowerShell objects.

## Layout

| Path | Purpose |
| :--- | :--- |
| `psfdx/` | Core: auth, aliases, SOQL/records, limits, REST API, CLI/plugin install |
| `psfdx-metadata/` | Retrieve / deploy / describe metadata |
| `psfdx-development/` | Projects, config, scratch orgs, Apex tests, `Watch-SalesforceApex`, LWC/Jest |
| `psfdx-logs/` | Debug logs, flow interviews, login history, event log files |
| `psfdx-sandbox/` | Sandbox lifecycle |
| `psfdx-packages/` | Packages and package versions |
| `psfdx-shared/` | Internal helpers (`Invoke-Salesforce`, `Show-SalesforceResult`, Apex test-param helpers, `Get-PsfdxCommonParameterSplat`) |
| `modules.ps1` | Canonical module list used by the install/uninstall scripts |

Each module has `<name>.psd1` (manifest), `<name>.psm1` (code) and `<name>.Tests.ps1` (Pester).

## Commands

```powershell
Invoke-Pester -Path . -CI                                   # full suite (what CI runs)
Invoke-Pester -Path ./psfdx-logs/psfdx-logs.Tests.ps1       # one module
./install.ps1  # or ./install-windows.ps1 — copies modules into the user module path
```

The tests mock all `sf` calls, so they need no org and no Salesforce CLI. Warnings about unapproved verbs while the tests run are expected.

## Cmdlet pattern

Follow the existing idiom exactly. Don't introduce a new style in a single function:

```powershell
function Verb-SalesforceNoun {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $command = "sf some command --name $Name"
    if ($NoPrompt) { $command += " --no-prompt" }
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -Command $command @commonParams
    return Show-SalesforceResult -Result $result        # add -ReturnRecords for SOQL queries
}
```

- Always forward common parameters with `Get-PsfdxCommonParameterSplat`, so `-Verbose` shows the `sf` command.
- `Show-SalesforceResult` throws on a non-zero `status`. Don't pipe non-JSON output (`csv`/`human` result formats) into it.
- `Invoke-Salesforce` deliberately has **no** `SupportsShouldProcess` (see the comment in `psfdx-shared/Invoke-Salesforce.ps1`). Put `ShouldProcess` on the public cmdlet instead.
- **`Invoke-Salesforce` runs the string through `Invoke-Expression`.** Wrap paths and free text in quotes (`` " --file `"$Path`"" ``). Escape values that go into SOQL with `$Value -replace "'", "''"`.
- The `Retrieve-`, `Describe-` and `Promote-` verbs are intentional, even though PowerShell doesn't approve them. Keep using them for consistency.
- Each `.psm1` starts with an identical copy of `Import-PsfdxSharedModule`. If you change it, change all six.
- Use `#region` / `#endregion` blocks to group cmdlets, as the existing files do.

## Compatibility

Manifests declare `PowerShellVersion = '5.1'` and `CompatiblePSEditions = @('Desktop','Core')`, so code must run on Windows PowerShell 5.1:
- Don't use ternary `?:`, `??`, `?.` or `&&`/`||` in module code.
- Use `Join-Path` with two arguments only (nest it for deeper paths).
- `$IsWindows`/`$IsMacOS` are `$null` on 5.1. Use the existing `Test-SalesforceIsWindows` (`psfdx-logs`) and `Test-SalesforceIsMacOS` (`psfdx`) helpers instead.
- Parse dates and numbers with the invariant culture.

## Tests

- Load the module from its manifest after removing any copies already loaded (see the top of each `.Tests.ps1`), then test inside `InModuleScope`.
- Mock `Invoke-Salesforce` (and `Show-SalesforceResult` where needed). Assert the exact `-Command` string with `Assert-MockCalled ... -ParameterFilter { $Command -eq '...' }` or `-like`. That string is the contract, and checking it is what catches bugs like malformed SOQL.
- Never call a real org. Write any files to `$TestDrive`, not the repo.
- Every bug fix or new cmdlet needs a test.

## Checklist for adding or changing a public cmdlet

1. Implement it in the module `.psm1`.
2. Add it to `FunctionsToExport` in the module `.psd1`. Exports come from the manifest; there is no `Export-ModuleMember`.
3. Add a Pester test.
4. Add or update its row in the module's table in `README.md`.
5. Add an entry under `## Unreleased` in `CHANGELOG.md`, prefixed with the module name (`- psfdx-logs: ...`). Mark renames and moves as `Breaking:`.
6. A new module also needs adding to `modules.ps1`.

## Git

- PRs target `master`. CI (`.github/workflows/ci.yml`) runs Pester on `ubuntu-latest` for pull requests only.
- `CODE-REVIEW.md` is a review from 2026-09-09. Many of its findings have since been fixed (see `CHANGELOG.md`), so check the current code before acting on it. The `Invoke-Expression` → `& sf @args` refactor is still outstanding.
