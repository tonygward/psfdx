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
- `$IsWindows`, `$IsMacOS` or `$IsLinux`, which are `$null` on 5.1. Use `[System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)` (or `::OSX` / `::Linux`). `Test-SalesforceIsWindows` (psfdx-logs) and `Test-SalesforceIsMacOS` (psfdx) wrap this, but they're private: neither is in `FunctionsToExport`, so other modules can't call them. If a third module needs one, move it into psfdx-shared. Tests may use `$IsWindows`, since they only run under `pwsh`.
- PowerShell classes and `IValidateSetValuesGenerator` (`[ValidateSet([SomeType])]`), which are PowerShell 6+ only. For dynamic values, use an `[ArgumentCompleter]` and validate inside the function, as psfdx-metadata's `-Type` does. The completer scriptblock runs in the caller's scope, so to reach a private helper it has to call back into the module: `& (Get-Module psfdx-metadata | Select-Object -First 1) { Complete-SalesforceMetadataType @args } @args`.

## Culture

- Build SOQL datetime literals with `$Date.ToUniversalTime().ToString('s') + 'Z'`. `'s'` is culture-invariant, and `ToUniversalTime()` is what makes the `Z` true. The existing `$Date.ToString('s') + 'Z'` in `Get-SalesforceDateTime` and the psfdx-logs query builders leaves out the conversion and is off by the UTC offset. Don't copy it.
- Parse dates and numbers with `[System.Globalization.CultureInfo]::InvariantCulture`, as `Get-SalesforceSandboxRefreshStatus` does.
- Use `ToLowerInvariant()` and `[System.StringComparison]::OrdinalIgnoreCase` for comparisons, as the Apex watcher helpers do.
