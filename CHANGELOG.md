# Changelog

## Unreleased

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
