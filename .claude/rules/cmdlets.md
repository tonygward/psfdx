---
paths:
  - "**/*.psm1"
  - "psfdx-shared/*.ps1"
---

# Writing cmdlets

Each cmdlet builds an argument array, runs it with `Invoke-Salesforce` (`psfdx-shared/Invoke-Salesforce.ps1`) and usually converts the JSON with `Show-SalesforceResult` (`psfdx-shared/Show-SalesforceResult.ps1`).

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
    $arguments = @('some', 'command', '--name', $Name)
    if ($OutputDir) { $arguments += @('--output-dir', $OutputDir) }
    if ($NoPrompt) { $arguments += '--no-prompt' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}
```

- `--target-org` uses the `ContainsKey(...) -and -not IsNullOrWhiteSpace(...)` guard shown above. Almost every cmdlet does this, so wrappers can pass `-TargetOrg $TargetOrg` through even when it's empty. `--target-dev-hub` uses a plain `if ($TargetDevHub)`.
- `--json` goes last.
- For SOQL, run `sf data query ... --result-format json` and call `Show-SalesforceResult -Result $raw -ReturnRecords`, which strips `attributes`. Or call `Select-SalesforceRecords` (psfdx).
- `Show-SalesforceResult` throws on a non-zero `status`, with deploy and test failures folded into the message.

### Preferred form: structured argv

Every cmdlet builds an array and call `Invoke-Salesforce -FilePath 'sf' -Arguments $arguments`. Nothing is quoted; each element is one argument exactly as given. Windows `.cmd` shims still reject double quotes, line breaks and bare shell metacharacters, and `%` is passed literally.

```powershell
$arguments = @('package', 'create', '--name', $Name, '--path', $Path)
if ($Description) { $arguments += @('--description', $Description) }
if ($PSBoundParameters.ContainsKey('TargetDevHub') -and $TargetDevHub) { $arguments += @('--target-dev-hub', $TargetDevHub) }
$arguments += '--json'
$commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
$result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
return Show-SalesforceResult -Result $result
```

Assert it with `Assert-MockCalled Invoke-Salesforce -ParameterFilter { ($Arguments -join '|') -eq 'package|create|--name|MyPkg|...|--json' }`. The CLI compatibility scan reads the leading words of `$arguments = @(...)` as the command. The `-Command` string form still works for backwards compatibility, but no module uses it and new code shouldn't.

## Pattern 2: pass-through (no `--json`)

Return the `Invoke-Salesforce` output unchanged for commands that stream, are interactive, or aren't `sf` commands. Examples: `sf apex log tail`, `sf org open`, `sf plugins`, `sf lightning dev app`, `npm`/`yarn`/`brew`. Never pipe non-JSON output (including `csv`/`human` result formats) into `Show-SalesforceResult`; `Select-SalesforceRecords` shows how to branch on `-ResultFormat`.

Run non-`sf` commands through `Invoke-Salesforce` too, so tests can mock them and `-Verbose` shows them.

## Always

- Always declare a `Param()` block, even an empty one. Without it `[CmdletBinding()]` has no effect and `-Verbose` is silently ignored (`psfdx.Tests.ps1` checks this for `Get-SalesforceAlias`).
- Forward common parameters with `Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters` and splat `@commonParams`, so that `-Verbose` prints the command.
- **`Invoke-Salesforce` runs the executable directly with your argument array.** It never uses `Invoke-Expression` or a shell, so `;`, `|`, `&` and `$(...)` in a value are literal text, and nothing needs quoting or escaping: pass each value as its own array element. Validate paths with `Test-Path -LiteralPath` before building the arguments, and throw `"Output directory '$X' does not exist."`-style messages. Join a flag and its value into one element only when the CLI expects that (`--name=allMetadata`, `Type:Name` for `--metadata`). Don't add `Invoke-Expression`, and don't call anything but `Invoke-Salesforce` to run a program. Secret-bearing options such as `--password` and `--sfdx-url` are masked in `-Verbose` output by their option name. On Windows, a `.cmd` shim (`sf`, `npm`, `yarn`) rejects an argument containing a double quote or line break.
- Never interpolate a value into SOQL yourself. Use `ConvertTo-SalesforceSoqlLiteral -Value $x` (psfdx-shared). It returns the quoted literal with SOQL's backslash escapes (an apostrophe becomes `\'`; doubling the quote is not valid SOQL), refuses control characters, and is safe inside the `--query "..."` argument. Add `-Like` to match `%` and `_` literally in a `LIKE`. Object and field names cannot be quoted, so pass them through `ConvertTo-SalesforceSoqlIdentifier`. See `Get-SalesforceSandboxRefreshStatus`. A caller-authored `Select-SalesforceRecords -Query` is passed through unchanged.
- `Invoke-Salesforce` deliberately has **no** `SupportsShouldProcess` (see the comment in the file). New destructive cmdlets declare `[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]` themselves, and wrap the `Invoke-Salesforce` call in `if ($PSCmdlet.ShouldProcess(...))`. No existing cmdlet does this yet.
  `Get-PsfdxCommonParameterSplat` also forwards `WhatIf` and `Confirm`, and `Invoke-Salesforce` doesn't accept them, so `-Confirm:$false` fails with "A parameter cannot be found that matches parameter name 'Confirm'". In these cmdlets, remove both keys before splatting:
  ```powershell
  $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
  $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
  if ($PSCmdlet.ShouldProcess($TargetOrg, 'Delete sandbox')) {
      $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
  }
  ```
  The better long-term fix is to stop the helper forwarding them.
- Group cmdlets in `#region` / `#endregion` blocks.
- Keep the `Retrieve-`, `Describe-` and `Promote-` verbs, even though PowerShell doesn't approve them.

## Existing code not to copy

Some older code predates these rules. Don't treat it as precedent:
- The plain `if ($TargetOrg)` in `Get-SalesforcePackagesInstalled`.
- `$Date.ToString('s') + 'Z'`. It labels local time as UTC, so in BST 12:00 local is sent as `12:00:00Z` instead of `11:00:00Z`. Use `ConvertTo-SalesforceSoqlDateTime -Value $Date` (psfdx-shared). A test fails if a module uses the old pattern.

## Modules and helpers

- Each module `.psm1` starts with a copy of `Import-PsfdxSharedModule`. All seven copies are identical (a repository test checks it). psfdx-shared must have the importing module's Major.Minor and be no older than it; the function prefers a compatible loaded copy, then the sibling folder, then sibling version folders, then PSModulePath, compares versions as `[version]`, and throws with an actionable message when nothing fits. Its tests are in `psfdx-shared/psfdx-shared.Tests.ps1`.
- Helpers that every module needs go in `psfdx-shared/` and are exported from `psfdx-shared.psd1`. A module's private helpers stay out of its own `FunctionsToExport`.
- Watch for near-identical names. `Get-SalesforceApexCliTestArguments` (shared) maps `-TestLevel`/`-Tests` to deploy flags. `Get-SalesforceCliApexTestArguments` (psfdx-development, private) builds `--tests` for `sf apex run test`.
- To call a cmdlet from another module (e.g. `Select-SalesforceRecords` or `Get-SalesforceUsers` from psfdx), add that module to `RequiredModules` in your manifest, as `psfdx-logs.psd1` does. `psfdx-development.psd1` currently calls psfdx without declaring it.
