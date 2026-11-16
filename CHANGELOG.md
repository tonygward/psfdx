# Changelog

## Unreleased

- psfdx: The PowerShell Gallery package now lists the MIT licence (`LicenseUri`), and the README has a licence section linking to `LICENSE`.

## 0.8.8 - 2026-11-16

- psfdx-metadata: `Test-SalesforceDeploy -InputDir` now accepts an existing Metadata API ZIP file as well as a directory, matching `sf project deploy validate --metadata-dir`. A missing path or a file that is not a `.zip` gives a clear error.

## 0.8.7 - 2026-11-16

- psfdx-shared: `Invoke-Salesforce` no longer runs commands through `Invoke-Expression`. The command is split into an executable and an argument list and run directly, so characters such as `;`, `|`, `&` and `$(...)` in values are passed to `sf` as plain text instead of being executed. Cmdlet parameters and output are unchanged.
- psfdx-shared: `-Verbose` output now masks the values of `--password`, `--client-secret`, `--sfdx-url`, token and similar options.
- psfdx-shared: On Windows, arguments containing `%`, a double quote or a line break (or `& | < > ^` without spaces) are rejected rather than passed to the `.cmd` shim of `sf`, `npm` or `yarn`, because `cmd.exe` would interpret them.

## 0.8.6 - 2026-11-15

- psfdx-metadata: `Retrieve-SalesforceOrg` now uses `sf project generate manifest` instead of the legacy `sf force source manifest create`. Parameters and behaviour are unchanged.
- psfdx-packages: `Get-SalesforcePackagesInstalled` now uses `sf package installed list` instead of the legacy `sf force package installed list`. Parameters and returned records are unchanged.
- psfdx: `Connect-SalesforceAuthUrl` now uses `sf org login sfdx-url` instead of the legacy `sf auth sfdxurl store`. Parameters and token hiding are unchanged.
- psfdx: `Install-SalesforceCli` and `Update-SalesforceCli` now use npm on macOS too, instead of the outdated `sfdx-cli/tap/sf` Homebrew tap. If you installed with that tap, run `brew uninstall sfdx-cli/tap/sf` first.

## 0.8.5 - 2026-11-15

- psfdx-metadata: Fix `Resume-SalesforceDeploy` (added in 0.8.4). It no longer has a `-TargetOrg` parameter, because `sf project deploy resume` rejects `--target-org` and takes the org from the cached deployment.
- psfdx-metadata: Fix `Test-SalesforceDeploy` (added in 0.8.4). `-TestLevel NoTests` is removed, because `sf project deploy validate` requires tests and rejects `NoTestRun`. Supported levels are `SpecificTests`, `ReferencedTests`, `TestsInFolder`, `TestsInOrg` (default), `TestsInOrgAndPackages` and the new `RelevantTests` (`RunRelevantTests`).

## 0.8.4 - 2026-11-15

- psfdx-metadata: Add deployment lifecycle cmdlets wrapping `sf project deploy`: `Test-SalesforceDeploy` (validate), `Start-SalesforceQuickDeploy` (quick deploy a validated deployment), `Get-SalesforceDeployStatus` (report), `Resume-SalesforceDeploy` and `Stop-SalesforceDeploy` (cancel). Quick deploy and cancel ask for confirmation and support `-WhatIf`. Job IDs are checked before the CLI runs.

## 0.8.3 - 2026-11-15

- Maintenance release.

## 0.8.2 - 2026-11-15

- Maintenance release.

## 0.8.1 - 2026-11-15

### Added

- psfdx: Prepare a single bundled `psfdx` package for the PowerShell Gallery. The modules now also find each other when they are nested in one package. Publishing is switched off until the owner turns it on, so install from a clone or the release zip for now.
- Releases are now published on GitHub with a single zip to download.
- psfdx-logs: `Enable-SalesforceDebugLogging` accepts `-Username`, `-ApexClass` or `-ApexTrigger` as an alternative to `-TracedEntityId`, and looks up the Id for you.
- psfdx-logs: Add `Enable-SalesforceDebugLogging`, `Get-SalesforceDebugLogging` and `Disable-SalesforceDebugLogging`, wrapping `sf apex trace create`, `list` and `delete`. These need a Salesforce CLI release that includes the `apex trace` commands.

### Fixed

- CI: Pin Pester to 5.x. `Install-Module Pester` started pulling Pester 6, where `Assert-MockCalled` no longer loads, so every mock assertion failed.
- psfdx-metadata: The module failed to import on Windows PowerShell 5.1 (`Unable to find type [System.Management.Automation.IValidateSetValuesGenerator]`) despite declaring 5.1 support. `-Type` on `Retrieve-SalesforceComponent` and `Deploy-SalesforceComponent` now uses an argument completer and is validated inside the cmdlet, so binding no longer queries the org and unknown types still throw.
- psfdx-shared: Remove `SupportsShouldProcess` from `Invoke-Salesforce` and `Get-SalesforceApexCliTestParams`. Suppressing them returned `$null` into `Show-SalesforceResult -Result` (a mandatory parameter), so setting `$WhatIfPreference` made nearly every cmdlet fail on a null argument instead of performing a dry run.
- psfdx-logs: `Get-SalesforceLoginHistory -Username` (and therefore `Get-SalesforceLoginFailures -Username`) built invalid SOQL. `LoginHistory` has no `Username` column, so the filter now goes through a `UserId IN (SELECT Id FROM User WHERE Username = ...)` subquery.
- psfdx-development: `New-SalesforceProject -DefaultUserName` threw a parameter-binding error. It called `Set-SalesforceTargetOrg -DefaultUserName -ProjectFolder`, neither of which exists; it now sets `-Value` from inside the generated project.
- psfdx: `Select-SalesforceRecords -ResultFormat csv|human` crashed because the result was always piped through `ConvertFrom-Json`. Non-JSON formats are now returned untouched, and a failed JSON result no longer emits the raw payload before throwing.
- psfdx-metadata: `Retrieve-SalesforceComponent` now throws when `-Type` is omitted instead of emitting `--metadata` with no value.
- psfdx-logs: `Convert-SalesforceDebugLog` and `Out-Notepad` declared `ValueFromPipeline` without a `process` block, silently discarding all but the last piped item.
- psfdx-logs: `Out-Notepad` was a silent no-op on Windows PowerShell 5.1, where `$IsWindows` does not exist.
- psfdx-shared / psfdx-development: Apex test discovery matched class names as bare substrings, so `AccountHelperTest` looked like a test of `Account`. Matching now requires a whole-word reference or a `<Class>Test` / `<Class>Tests` / `Test<Class>` name, via a single shared `Test-SalesforceApexTestReference` helper.
- psfdx-metadata: The `-Type` valid-set generator ran `sf org list metadata-types` on every parameter bind and tab-completion, costing seconds per call. It is now resolved once per session; call `Clear-SalesforceMetadataTypeCache` to refresh it after connecting to an org.
- psfdx-development: `Test-SalesforceApex` raised "You cannot call a method on a null-valued expression" when the CLI returned no test summary.
- psfdx-development: `Get-SalesforceType` and `Get-SalesforceName` no longer fail on empty input or on files the watcher has already seen renamed or deleted.
- psfdx-development: `New-SalesforceApexClass` and `New-SalesforceApexTrigger` declared `-OutputDirectory` defaults that could never apply, since `--output-dir` is only added when the caller passes one. The misleading defaults are removed.
- psfdx: `Get-SalesforceLatestApiVersion` sorted versions as strings, ranking `99.0` above `100.0`.
- psfdx: `Get-SalesforceDataStorage` and `Get-SalesforceApiUsage` threw when the limit row was missing and divided by zero when `max` was 0.
- psfdx-logs: `Get-SalesforceFlowInterviews -Type` was both mandatory and defaulted, so its `All` default never applied and users were prompted.
- psfdx-metadata: `Build-SalesforceQuery` returned `SELECT  FROM <Object>` when every field was excluded; it now returns an empty string.
- psfdx-sandbox: Parse `SandboxProcess.EndDate` with the invariant culture instead of the current one.
- install.ps1 / install-windows.ps1: Resolve module sources from `$PSScriptRoot` rather than the current directory, so running the installer by absolute path from elsewhere no longer silently installs nothing.
- uninstall.ps1: Interpolate `$Scope` in the "nothing found" message and refer to `uninstall.ps1` rather than the nonexistent `uninstall-linux.ps1`.

- psfdx: Add `Install-SalesforceCli` cmdlet that installs the Salesforce CLI via Homebrew on macOS or global npm elsewhere.
- psfdx: Add `Connect-SalesforceAuthUrl` cmdlet to wrap `sf auth sfdxurl store`, hiding tokens by default with an opt-in `-IncludeToken` switch.
- psfdx-metadata: Allow `Deploy-SalesforceComponent` to use either `-SourceDir` or `-Type`, with `-SourceDir` supporting files or directories.
- Replace `Invoke-Salesforce -Arguments` with `-Command "sf …"` across modules to allow non-`sf` commands where needed.
- Centralize `Invoke-Salesforce` and `Show-SalesforceResult` into `psfdx-shared/` and dot-source across all modules.
- Rename folder `shared/` to `psfdx-shared/`.
- psfdx-development: Rename `$DevhubUsername` to `$TargetDevHub` and update callers.
- Documentation: Add guidance on using `-Command` vs `-Arguments` for shared helpers.
- Add new `psfdx-sandbox` module with helpers for listing, creating, cloning, resuming, checking status, and deleting sandboxes.
- psfdx-sandbox: Make `-TargetOrg` optional for `New-SalesforceSandbox` to fall back to CLI defaults.
- psfdx-sandbox: Restrict `-LicenseType` to `Developer`, `Developer_Pro`, `Partial`, or `Full` and default to `Developer`.
- psfdx-sandbox: Add `-NoTrackSource` to `New-SalesforceSandbox` to skip source tracking setup.
- psfdx-sandbox: Remove clone-specific parameters from `New-SalesforceSandbox` to align with current CLI support.
- psfdx-sandbox: Remove `Get-SalesforceSandboxStatus`; use the Salesforce CLI directly if needed.
- psfdx-sandbox: Simplify `Remove-SalesforceSandbox` to allow omitting `-TargetOrg` when the CLI default is set.
- psfdx-sandbox: Make `-TargetOrg` optional for `Resume-SalesforceSandbox`.
- psfdx-sandbox: Add `Get-SalesforceSandboxRefreshStatus` for refresh cadence insights using Tooling API queries.

 - Breaking: Move `Invoke-SalesforceApexFile` from `psfdx` to `psfdx-development` to align Apex workflows with development tooling. Import `psfdx-development` or update scripts to reference the new module.
 - Breaking: Move `Get-SalesforceApexClass` from `psfdx-metadata` to `psfdx-development` to co-locate Apex helpers. Update imports accordingly.
 - Breaking: Rename `Invoke-SalesforceApexFile` to `Invoke-SalesforceApex` for consistency. Update scripts and imports accordingly.
 - Breaking: Rename `Test-Salesforce` to `Test-SalesforceApex` to clarify scope. Update scripts and imports accordingly.
- Breaking: Rename psfdx-logs functions with plural suffix from `*SalesforceLogs` to `*SalesforceDebugLogs` (`Watch-`, `Get-`, `Export-`). Update scripts and imports accordingly.
- Breaking: Rename `Get-SalesforceLog` to `Get-SalesforceDebugLog`.
- Breaking: Rename `Get-SalesforceDebugLog` to `Get-SalesforceDebugLogs` to reflect multi-source support. Update scripts and imports accordingly.
 - Breaking: Rename `Convert-SalesforceLog` to `Convert-SalesforceDebugLog`.
- psfdx-metadata: Add `-IgnoreConflicts` switch to `Retrieve-SalesforceComponent`, mapping to `sf project retrieve start --ignore-conflicts`.
- psfdx-metadata: Extend `Retrieve-SalesforceComponent` with `-ChildName` for retrieving sub-components (`Type:Name.ChildName`) and enforce pairing with `-Name`.
- psfdx-metadata: Add optional `-OutputDir` parameter to `Retrieve-SalesforceComponent` to map to `--output-dir` when retrieving to an existing folder, support `-Wait` passthrough, and generate the type validate set dynamically from `Describe-SalesforceMetadataTypes`.
- psfdx-metadata: Add `Retrieve-SalesforceMetadata` cmdlet for manifest-driven retrieval with directory validation plus optional wait and unzip support.
- psfdx-metadata: Add `Retrieve-SalesforcePackage` cmdlet to retrieve by package name with wait, target org, and output directory validation.
- psfdx-metadata: Extend `Deploy-SalesforceComponent` with wait, dry-run, result verbosity, and conflict/warning/error suppression flags.
- psfdx-metadata: Add `Deploy-SalesforceMetadata` for manifest, metadata directory, or single-package deployments with conflict/warning/error suppression support.
- psfdx-metadata: Refactor `Retrieve-SalesforceField` to reuse `Retrieve-SalesforceComponent` for command construction.
- psfdx-metadata: Refactor `Retrieve-SalesforceValidationRule` to reuse `Retrieve-SalesforceComponent` for command construction.
- psfdx-metadata: Simplify `Describe-SalesforceObjects` by removing the category parameter and listing all objects by default.
- psfdx-packages: Rename `Promote-SalesforcePackageVersion` to approved verb `Publish-SalesforcePackageVersion` while exporting the original name as an alias to avoid unapproved verb warnings.
