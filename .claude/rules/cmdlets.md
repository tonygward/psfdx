---
paths:
  - "**/*.psm1"
  - "psfdx-shared/*.ps1"
---

# Writing cmdlets

Each cmdlet builds a command string, runs it with `Invoke-Salesforce` (`psfdx-shared/Invoke-Salesforce.ps1`) and usually converts the JSON with `Show-SalesforceResult` (`psfdx-shared/Show-SalesforceResult.ps1`).

## Pattern 1: JSON result (the default)

Use this whenever the `sf` command supports `--json` and returns once:

```powershell
function Verb-SalesforceNoun {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $command = "sf some command --name $Name"
    if ($OutputDir) { $command += " --output-dir `"$OutputDir`"" }
    if ($NoPrompt) { $command += " --no-prompt" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -Command $command @commonParams
    return Show-SalesforceResult -Result $result
}
```

- `--target-org` uses the `ContainsKey(...) -and -not IsNullOrWhiteSpace(...)` guard shown above. Almost every cmdlet does this, so wrappers can pass `-TargetOrg $TargetOrg` through even when it's empty. `--target-dev-hub` uses a plain `if ($TargetDevHub)`.
- `--json` goes last.
- For SOQL, run `sf data query ... --result-format json` and call `Show-SalesforceResult -Result $raw -ReturnRecords`, which strips `attributes`. Or call `Select-SalesforceRecords` (psfdx).
- `Show-SalesforceResult` throws on a non-zero `status`, with deploy and test failures folded into the message.

## Pattern 2: pass-through (no `--json`)

Return the `Invoke-Salesforce` output unchanged for commands that stream, are interactive, or aren't `sf` commands. Examples: `sf apex log tail`, `sf org open`, `sf plugins`, `sf lightning dev app`, `npm`/`yarn`/`brew`. Never pipe non-JSON output (including `csv`/`human` result formats) into `Show-SalesforceResult`; `Select-SalesforceRecords` shows how to branch on `-ResultFormat`.

Run non-`sf` commands through `Invoke-Salesforce` too, so tests can mock them and `-Verbose` shows them.

## Always

- Forward common parameters with `Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters` and splat `@commonParams`, so that `-Verbose` prints the command.
- **`Invoke-Salesforce` runs the string through `Invoke-Expression`.** Wrap every path and every free-text value (descriptions, names with spaces, queries) in escaped quotes, like `` `"$Value`" ``. Validate paths with `Test-Path -LiteralPath` before building the command, and throw `"Output directory '$X' does not exist."`-style messages.
- Escape values interpolated into SOQL: `$Value -replace "'", "''"`. See `Get-SalesforceSandboxRefreshStatus` and `Get-SalesforceLoginHistory`.
- `Invoke-Salesforce` deliberately has **no** `SupportsShouldProcess` (see the comment in the file). New destructive cmdlets declare `[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]` themselves, and wrap the `Invoke-Salesforce` call in `if ($PSCmdlet.ShouldProcess(...))`. No existing cmdlet does this yet.
- Group cmdlets in `#region` / `#endregion` blocks.
- Keep the `Retrieve-`, `Describe-` and `Promote-` verbs, even though PowerShell doesn't approve them.

## Existing code not to copy

Some older code predates these rules. Don't treat it as precedent:
- Unquoted paths and free text: `--output-dir $OutputDirectory` (psfdx-development), `--file $ApexFile`, `--definition-file`, `--output-file`, and `--description $Description` (psfdx-packages, which breaks on spaces).
- Unescaped SOQL: `Get-SalesforceUsers -Username`, `Get-SalesforceRecordType`, `Get-SalesforceApexClass`, and the `EventType` filters in psfdx-logs.
- The plain `if ($TargetOrg)` in `Get-SalesforcePackagesInstalled`.

## Modules and helpers

- Each module `.psm1` starts with a copy of `Import-PsfdxSharedModule`. The psfdx, logs, metadata, sandbox and packages copies are identical. The psfdx-development copy also has a `-ForceImport` switch. If you change the function, change all six and keep that difference.
- Helpers that every module needs go in `psfdx-shared/` and are exported from `psfdx-shared.psd1`. A module's private helpers stay out of its own `FunctionsToExport`.
- Watch for near-identical names. `Get-SalesforceApexCliTestParams` (shared) maps `-TestLevel`/`-Tests` to deploy flags. `Get-SalesforceCliApexTestParams` (psfdx-development, private) builds `--tests` for `sf apex run test`.
- To call a cmdlet from another module (e.g. `Select-SalesforceRecords` or `Get-SalesforceUsers` from psfdx), add that module to `RequiredModules` in your manifest, as `psfdx-logs.psd1` does. `psfdx-development.psd1` currently calls psfdx without declaring it.
