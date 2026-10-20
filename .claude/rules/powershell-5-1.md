---
paths:
  - "**/*.psm1"
  - "**/*.psd1"
  - "psfdx-shared/*.ps1"
  - "*-windows.ps1"
  - "modules.ps1"
---

# Windows PowerShell 5.1 compatibility

Module code and the Windows install scripts should run on Windows PowerShell 5.1 as well as PowerShell 7. CI only runs `pwsh` on Ubuntu, so it won't catch 5.1 breakage. `install.ps1` and `uninstall.ps1` are the Mac/Linux scripts and only need `pwsh`.

The development, logs, metadata and packages manifests declare `PowerShellVersion = '5.1'` and `CompatiblePSEditions = @('Desktop','Core')`. `psfdx.psd1`, `psfdx-sandbox.psd1` and `psfdx-shared.psd1` declare neither, but the same rules apply to them.

## Don't use

- Ternary `?:`, `??`, `??=`, `?.`, or the pipeline-chain operators `&&` and `||`.
- `Join-Path` with more than two arguments. Nest it instead: `Join-Path $a (Join-Path $b $c)`.
- `$IsWindows`, `$IsMacOS` or `$IsLinux`, which are `$null` on 5.1. Use `Test-SalesforceIsWindows` (psfdx-logs) or `Test-SalesforceIsMacOS` (psfdx). They aren't in psfdx-shared, so calling either from another module adds a dependency. Tests may use `$IsWindows`, since they only run under `pwsh`.
- PowerShell classes and `IValidateSetValuesGenerator`. **Known exception:** psfdx-metadata's `SalesforceMetadataTypeGenerator` class, used as `[ValidateSet([SalesforceMetadataTypeGenerator])]`, is PowerShell 6+ only, so that module doesn't load on 5.1 today. Don't spread the pattern. For dynamic values, prefer an `[ArgumentCompleter]`.

## Culture

- Build SOQL datetime literals with `$Date.ToString('s') + 'Z'`, as `Get-SalesforceDateTime` and the psfdx-logs query builders do.
- Parse dates and numbers with `[System.Globalization.CultureInfo]::InvariantCulture`, as `Get-SalesforceSandboxRefreshStatus` does.
- Use `ToLowerInvariant()` and `[System.StringComparison]::OrdinalIgnoreCase` for comparisons, as the Apex watcher helpers do.
