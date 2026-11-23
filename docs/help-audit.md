# Help audit

The comment-based help of every exported psfdx command was written or completed against the code and cross-checked against the generated [CLI parity report](cli-parity.md) (CLI **2.159.7**) as part of [#240](https://github.com/tonygward/psfdx/issues/240). This page records what the audit found. `tests/Help.Tests.ps1` now enforces the same cross-check on every pull request, and `scripts/release/Test-PsfdxHelp.ps1` checks the help of the published package.

## What every command's help has

`Get-Help <command> -Full` shows a synopsis, a description, one entry for every parameter (with its default, valid values, whether it is required, and the CLI flag it feeds), written examples, notes and links. The notes always carry a **Salesforce CLI mapping** section:

- for a command that runs `sf`: the executable (found on the PATH at run time; no path or version is stored), the exact command or commands it runs, the old name or word order it is invoked by when that differs from the canonical command, the flags of that command that no psfdx cmdlet passes, the values it cannot pass, and how each parameter maps to a flag;
- for a command that does not: a statement that it does not run an `sf` command and how it works instead (REST API, npm, other psfdx cmdlets, or PowerShell and .NET only).

The help describes only what the code does. A flag or value the parity report lists as unsupported is named as unsupported, never described as available. Where the CLI's own flag summary exists it is used for the parameter text, so the wording follows the CLI.

## How the 157 exported commands work

| Mechanism | Commands |
| :--- | ---: |
| sf command | 114 |
| other psfdx cmdlets | 17 |
| PowerShell and .NET only | 17 |
| npm | 5 |
| REST API (Invoke-RestMethod) | 2 |
| npm or yarn | 1 |
| sf command, through an internal helper | 1 |

## Public API and the shared helpers

`psfdx-shared` exports 12 functions: `ConvertTo-SalesforceSoqlDateTime`, `ConvertTo-SalesforceSoqlIdentifier`, `ConvertTo-SalesforceSoqlLiteral`, `Get-PsfdxCommonParameterSplat`, `Get-SalesforceApexCliTestArguments`, `Get-SalesforceApexTestClassNamesFromPath`, `Get-SalesforceDeployFailures`, `Get-SalesforceErrorMessage`, `Get-SalesforceTestFailure`, `Invoke-Salesforce`, `Show-SalesforceResult`, `Test-SalesforceApexTestReference`. They are implementation helpers (`Invoke-Salesforce` runs a program, `Show-SalesforceResult` parses its output, the `ConvertTo-SalesforceSoql*` functions escape SOQL, and the rest build messages and test arguments). They are exported because the other modules import them from `psfdx-shared`, and the Gallery bundle exports the union of every module's exports, so they appear in `Get-Command -Module psfdx`.

**Decision: keep them exported and document them as internal helpers.** Removing them would break the modules that import them and any script that already calls them, and PowerShell has no module-private-but-shared-across-modules scope. Each one's help now says it is a shared helper that may change without notice, and `Test-SalesforceApexTestReference` (the example in the issue) says in its notes that it does not run `sf`: it reads a local Apex file with `Select-String` and .NET regular expressions. If the public surface should shrink later, the way is a separate, breaking change that moves the helpers behind a module that is not exported from the bundle; that is a decision for the owner and would be listed as Breaking in the changelog.

## Discrepancies found, and what was done

1. **`Open-Salesforce -BrowserPrivateMode` could never work.** It was a `[string]` parameter written as `--private <value>`, but `--private` is a boolean flag of `sf org open` that takes no value, so any use passed an unexpected argument. Fixed: it is now a `[switch]` that adds `--private`. This changes the parameter's type; the old form failed in the CLI, so no working script is affected. (Changelog, with a test.)
2. **Four commands run a deprecated alias.** `Get-SalesforceLimits` runs `sf limits api display` (current: `sf org list limits`), `New-SalesforceProject` runs `sf project generate` (current: `sf template generate project`), `New-SalesforceApexClass` runs `sf apex generate class` (current: `sf template generate apex class`), and `New-SalesforceApexTrigger` runs `sf apex generate trigger` (current: `sf template generate apex trigger`). The CLI still accepts them but prints a deprecation warning and may remove them. The help names both, as the issue asks, and does not substitute the new command. Moving to the current names is tracked in [#241](https://github.com/tonygward/psfdx/issues/241).
3. **Three commands run the words in another order.** `Select-SalesforceDebugLogs`, `Get-SalesforceDebugLogs` and `Watch-SalesforceDebugLogs` run `sf apex log list`, `get` and `tail`; the canonical commands are `sf apex list log`, `get log` and `tail log`. The CLI accepts both orders. Documented in the help and in #241.
4. **Values the CLI lists that psfdx cannot pass** are named in the help of the cmdlets concerned and recorded in the parity report: `apex get test --result-format` (`human`, `tap`, `junit`), `api request rest --method` (`POST`, `PUT`, `HEAD`, `DELETE`, `OPTIONS`, `TRACE`), `lightning dev app --device-type` (`desktop`), `project deploy start --test-level` (`RunRelevantTests`), `project generate manifest --include-packages` (`managed`), and some `--template` values of `template generate apex class` and `template generate project`.
5. **Two internal helpers run `sf` for an exported cmdlet.** `Watch-SalesforceApex` deploys through the private `Watch-SalesforceApexAction` (`sf project deploy start`), and `Start-SalesforceLwcDevServer` checks for its plugin through `Test-SalesforceLightningDevPluginInstalled` (`sf plugins --core`). Both are written into the help of the exported cmdlet.
6. **Cmdlets that do not run `sf`.** `Connect-SalesforceApi` and `Invoke-SalesforceApi` call the REST API directly; `Install-SalesforceCli`, `Update-SalesforceCli` and the Jest cmdlets run npm (or yarn); `Get-SalesforceApiUsage`, `Get-SalesforceDataStorage`, `Export-SalesforceDebugLogs` and similar are built on other psfdx cmdlets; `New-SalesforceJestTest`, `Convert-SalesforceDebugLog`, `Out-Notepad` and `Test-SalesforceApexTestReference` work locally. Each says so instead of naming a CLI command.
7. **No command psfdx runs was missing from the CLI.** The live CLI help check already guarantees every command and flag psfdx passes exists in the latest stable CLI, and the parity report resolved every command the modules run to a real command or a known old name, with no unresolved references.

Not verified: nothing here was run against a real org. The help was checked against the code, the CLI's own command data (`sf commands --json`, which is what the parity report is built from) and the parity report, not by running each command.

## Cross-check, cmdlet by cmdlet

"Runs" is the command as psfdx writes it; "Canonical" appears only when that is an old name or a different word order.

| Cmdlet | Module | How it works | Runs | Canonical |
| :--- | :--- | :--- | :--- | :--- |
| `Add-SalesforceAlias` | psfdx | sf command | `sf alias set` |  |
| `Connect-Salesforce` | psfdx | sf command | `sf org login web` |  |
| `Connect-SalesforceApi` | psfdx | REST API (Invoke-RestMethod) |  |  |
| `Connect-SalesforceAuthUrl` | psfdx | sf command | `sf org login sfdx-url` |  |
| `Connect-SalesforceJwt` | psfdx | sf command | `sf org login jwt` |  |
| `Disconnect-Salesforce` | psfdx | sf command | `sf org logout` |  |
| `Export-SalesforceBulkData` | bulk | sf command | `sf data export bulk` |  |
| `Export-SalesforceTreeData` | psfdx | sf command | `sf data export tree` |  |
| `Get-SalesforceAlias` | psfdx | sf command | `sf alias list` |  |
| `Get-SalesforceApiUsage` | psfdx | other psfdx cmdlets |  |  |
| `Get-SalesforceApiVersions` | psfdx | sf command | `sf api request rest` |  |
| `Get-SalesforceAuthenticatedUser` | psfdx | sf command | `sf org list users` |  |
| `Get-SalesforceBulkResult` | bulk | sf command | `sf data bulk results` |  |
| `Get-SalesforceConnections` | psfdx | sf command | `sf org list` |  |
| `Get-SalesforceDataStorage` | psfdx | other psfdx cmdlets |  |  |
| `Get-SalesforceDateTime` | psfdx | PowerShell and .NET only |  |  |
| `Get-SalesforceLatestApiVersion` | psfdx | other psfdx cmdlets |  |  |
| `Get-SalesforceLimits` | psfdx | sf command | `sf limits api display` | `sf org list limits` (deprecated alias) |
| `Get-SalesforceOrgUser` | psfdx | sf command | `sf org display user` |  |
| `Get-SalesforcePlugins` | plugins | sf command | `sf plugins` |  |
| `Get-SalesforceRecord` | psfdx | sf command | `sf data get record` |  |
| `Get-SalesforceRecordType` | psfdx | other psfdx cmdlets |  |  |
| `Get-SalesforceUsers` | psfdx | other psfdx cmdlets |  |  |
| `Grant-SalesforcePermissionSet` | psfdx | sf command | `sf org assign permset` |  |
| `Grant-SalesforcePermissionSetLicense` | psfdx | sf command | `sf org assign permsetlicense` |  |
| `Import-SalesforceBulkData` | bulk | sf command | `sf data import bulk` |  |
| `Import-SalesforceTreeData` | psfdx | sf command | `sf data import tree` |  |
| `Install-SalesforceCli` | psfdx | npm |  |  |
| `Install-SalesforcePlugin` | plugins | sf command | `sf plugins install` |  |
| `Invoke-SalesforceApi` | psfdx | REST API (Invoke-RestMethod) |  |  |
| `New-SalesforceRecord` | psfdx | sf command | `sf data create record` |  |
| `New-SalesforceUser` | psfdx | sf command | `sf org create user` |  |
| `New-SalesforceUserPassword` | psfdx | sf command | `sf org generate password` |  |
| `Open-Salesforce` | psfdx | sf command | `sf org open` |  |
| `Remove-SalesforceAlias` | psfdx | sf command | `sf alias unset` |  |
| `Remove-SalesforceRecord` | psfdx | sf command | `sf data delete record` |  |
| `Repair-SalesforceConnections` | psfdx | sf command | `sf org list` |  |
| `Resume-SalesforceBulkJob` | bulk | sf command | `sf data export resume`<br>`sf data import resume`<br>`sf data update resume`<br>`sf data upsert resume` |  |
| `Select-SalesforceRecords` | psfdx | sf command | `sf data query` |  |
| `Set-SalesforceRecord` | psfdx | sf command | `sf data update record` |  |
| `Update-SalesforceBulkData` | bulk | sf command | `sf data update bulk` |  |
| `Update-SalesforceCli` | psfdx | npm |  |  |
| `Update-SalesforcePlugins` | plugins | sf command | `sf plugins update` |  |
| `Upsert-SalesforceBulkData` | bulk | sf command | `sf data upsert bulk` |  |
| `Upsert-SalesforceRecord` | psfdx | sf command | `sf api request rest` |  |
| `Disable-SalesforceAgent` | agentforce | sf command | `sf agent deactivate` |  |
| `Enable-SalesforceAgent` | agentforce | sf command | `sf agent activate` |  |
| `Get-SalesforceAgentTestResult` | agentforce | sf command | `sf agent test results` |  |
| `Get-SalesforceAgentTests` | agentforce | sf command | `sf agent test list` |  |
| `New-SalesforceAgentAuthoringBundle` | agentforce | sf command | `sf agent generate authoring-bundle` |  |
| `Publish-SalesforceAgentAuthoringBundle` | agentforce | sf command | `sf agent publish authoring-bundle` |  |
| `Start-SalesforceAgentTest` | agentforce | sf command | `sf agent test run` |  |
| `Test-SalesforceAgentAuthoringBundle` | agentforce | sf command | `sf agent validate authoring-bundle` |  |
| `Test-SalesforceAgentPlugin` | agentforce | sf command | `sf plugins` |  |
| `Debug-SalesforceJest` | development | npm |  |  |
| `Get-SalesforceApexClass` | development | other psfdx cmdlets |  |  |
| `Get-SalesforceApexTestResult` | development | sf command | `sf apex get test` |  |
| `Get-SalesforceCodeAnalyzerRule` | development | sf command | `sf code-analyzer rules` |  |
| `Get-SalesforceCodeCoverage` | development | other psfdx cmdlets |  |  |
| `Get-SalesforceConfig` | development | sf command | `sf config list` |  |
| `Get-SalesforceFlowTestResult` | development | sf command | `sf flow get test` |  |
| `Get-SalesforceLogicTestResult` | development | sf command | `sf logic get test` |  |
| `Get-SalesforceScratchOrgs` | development | sf command | `sf org list` |  |
| `Get-SalesforceTargetDevHub` | development | sf command | `sf config get` |  |
| `Get-SalesforceTargetOrg` | development | sf command | `sf config get` |  |
| `Install-SalesforceJest` | development | npm or yarn |  |  |
| `Install-SalesforceLwcDevServer` | development | sf command | `sf plugins install` |  |
| `Invoke-SalesforceApex` | development | sf command | `sf apex run` |  |
| `Invoke-SalesforceCodeAnalyzer` | development | sf command | `sf code-analyzer run` |  |
| `New-SalesforceApexClass` | development | sf command | `sf apex generate class` | `sf template generate apex class` (deprecated alias) |
| `New-SalesforceApexTrigger` | development | sf command | `sf apex generate trigger` | `sf template generate apex trigger` (deprecated alias) |
| `New-SalesforceJestTest` | development | PowerShell and .NET only |  |  |
| `New-SalesforceProject` | development | sf command | `sf project generate` | `sf template generate project` (deprecated alias) |
| `New-SalesforceScratchOrg` | development | sf command | `sf org create scratch` |  |
| `Remove-SalesforceScratchOrg` | development | sf command | `sf org delete scratch` |  |
| `Remove-SalesforceScratchOrgs` | development | other psfdx cmdlets |  |  |
| `Remove-SalesforceTargetDevHub` | development | sf command | `sf config unset` |  |
| `Remove-SalesforceTargetOrg` | development | sf command | `sf config unset` |  |
| `Resume-SalesforceScratchOrg` | development | sf command | `sf org resume scratch` |  |
| `Set-SalesforceTargetDevHub` | development | sf command | `sf config set` |  |
| `Set-SalesforceTargetOrg` | development | sf command | `sf config set` |  |
| `Start-SalesforceApexTest` | development | sf command | `sf apex run test` |  |
| `Start-SalesforceLwcDevServer` | development | sf command | `sf lightning dev app`<br>`sf lightning dev component`<br>`sf lightning dev site` |  |
| `Test-SalesforceApex` | development | sf command | `sf apex run test` |  |
| `Test-SalesforceFlow` | development | sf command | `sf flow run test` |  |
| `Test-SalesforceJest` | development | npm |  |  |
| `Test-SalesforceLogic` | development | sf command | `sf logic run test` |  |
| `Wait-SalesforceApexTest` | development | other psfdx cmdlets |  |  |
| `Watch-SalesforceApex` | development | sf command, through an internal helper | `sf project deploy start` (internal helper) |  |
| `Watch-SalesforceJest` | development | npm |  |  |
| `Convert-SalesforceDebugLog` | logs | PowerShell and .NET only |  |  |
| `Disable-SalesforceDebugLogging` | logs | sf command | `sf apex trace delete` |  |
| `Enable-SalesforceDebugLogging` | logs | sf command | `sf apex trace create` |  |
| `Export-SalesforceDebugLogs` | logs | other psfdx cmdlets |  |  |
| `Export-SalesforceEventFile` | logs | other psfdx cmdlets |  |  |
| `Export-SalesforceEventFiles` | logs | sf command | `sf data query` |  |
| `Get-SalesforceDebugLogging` | logs | sf command | `sf apex trace list` |  |
| `Get-SalesforceDebugLogs` | logs | sf command | `sf apex log get` | `sf apex get log` (words reordered) |
| `Get-SalesforceEventFile` | logs | sf command | `sf api request rest` |  |
| `Get-SalesforceFlowInterviews` | logs | sf command | `sf data query` |  |
| `Get-SalesforceLoginFailures` | logs | other psfdx cmdlets |  |  |
| `Get-SalesforceLoginHistory` | logs | sf command | `sf data query` |  |
| `Out-Notepad` | logs | PowerShell and .NET only |  |  |
| `Select-SalesforceDebugLogs` | logs | sf command | `sf apex log list` | `sf apex list log` (words reordered) |
| `Select-SalesforceEventFiles` | logs | sf command | `sf data query` |  |
| `Watch-SalesforceDebugLogs` | logs | sf command | `sf apex log tail` | `sf apex tail log` (words reordered) |
| `Build-SalesforceQuery` | metadata | other psfdx cmdlets |  |  |
| `Clear-SalesforceMetadataTypeCache` | metadata | PowerShell and .NET only |  |  |
| `Deploy-SalesforceComponent` | metadata | sf command | `sf project deploy start` |  |
| `Deploy-SalesforceMetadata` | metadata | sf command | `sf project deploy start` |  |
| `Describe-SalesforceFields` | metadata | other psfdx cmdlets |  |  |
| `Describe-SalesforceMetadataTypes` | metadata | sf command | `sf org list metadata-types` |  |
| `Describe-SalesforceObject` | metadata | sf command | `sf sobject describe` |  |
| `Describe-SalesforceObjects` | metadata | sf command | `sf sobject list` |  |
| `Get-SalesforceDeployPreview` | metadata | sf command | `sf project deploy preview` |  |
| `Get-SalesforceDeployStatus` | metadata | sf command | `sf project deploy report` |  |
| `Get-SalesforceRetrievePreview` | metadata | sf command | `sf project retrieve preview` |  |
| `Resume-SalesforceDeploy` | metadata | sf command | `sf project deploy resume` |  |
| `Retrieve-SalesforceComponent` | metadata | sf command | `sf project retrieve start` |  |
| `Retrieve-SalesforceField` | metadata | other psfdx cmdlets |  |  |
| `Retrieve-SalesforceMetadata` | metadata | sf command | `sf project retrieve start` |  |
| `Retrieve-SalesforceOrg` | metadata | sf command | `sf project generate manifest`<br>`sf project retrieve start` |  |
| `Retrieve-SalesforcePackage` | metadata | sf command | `sf project retrieve start` |  |
| `Retrieve-SalesforceValidationRule` | metadata | other psfdx cmdlets |  |  |
| `Start-SalesforceQuickDeploy` | metadata | sf command | `sf project deploy quick` |  |
| `Stop-SalesforceDeploy` | metadata | sf command | `sf project deploy cancel` |  |
| `Test-SalesforceDeploy` | metadata | sf command | `sf project deploy validate` |  |
| `Get-SalesforcePackage` | packages | other psfdx cmdlets |  |  |
| `Get-SalesforcePackageInstallStatus` | packages | sf command | `sf package install report` |  |
| `Get-SalesforcePackages` | packages | sf command | `sf package list` |  |
| `Get-SalesforcePackagesInstalled` | packages | sf command | `sf package installed list` |  |
| `Get-SalesforcePackageVersionCreateStatus` | packages | sf command | `sf package version create report` |  |
| `Get-SalesforcePackageVersions` | packages | sf command | `sf package version list` |  |
| `Install-SalesforcePackageVersion` | packages | sf command | `sf package install` |  |
| `New-SalesforcePackage` | packages | sf command | `sf package create` |  |
| `New-SalesforcePackageVersion` | packages | sf command | `sf package version create` |  |
| `Promote-SalesforcePackageVersion` | packages | sf command | `sf package version promote` |  |
| `Remove-SalesforcePackage` | packages | sf command | `sf package delete` |  |
| `Remove-SalesforcePackageVersion` | packages | sf command | `sf package version delete` |  |
| `Copy-SalesforceSandbox` | sandbox | sf command | `sf org create sandbox` |  |
| `Get-SalesforceSandboxes` | sandbox | sf command | `sf org list` |  |
| `Get-SalesforceSandboxRefreshStatus` | sandbox | sf command | `sf data query` |  |
| `New-SalesforceSandbox` | sandbox | sf command | `sf org create sandbox` |  |
| `Remove-SalesforceSandbox` | sandbox | sf command | `sf org delete sandbox` |  |
| `Resume-SalesforceSandbox` | sandbox | sf command | `sf org resume sandbox` |  |
| `ConvertTo-SalesforceSoqlDateTime` | shared | PowerShell and .NET only |  |  |
| `ConvertTo-SalesforceSoqlIdentifier` | shared | PowerShell and .NET only |  |  |
| `ConvertTo-SalesforceSoqlLiteral` | shared | PowerShell and .NET only |  |  |
| `Get-PsfdxCommonParameterSplat` | shared | PowerShell and .NET only |  |  |
| `Get-SalesforceApexCliTestArguments` | shared | PowerShell and .NET only |  |  |
| `Get-SalesforceApexTestClassNamesFromPath` | shared | PowerShell and .NET only |  |  |
| `Get-SalesforceDeployFailures` | shared | PowerShell and .NET only |  |  |
| `Get-SalesforceErrorMessage` | shared | PowerShell and .NET only |  |  |
| `Get-SalesforceTestFailure` | shared | PowerShell and .NET only |  |  |
| `Invoke-Salesforce` | shared | PowerShell and .NET only |  |  |
| `Show-SalesforceResult` | shared | PowerShell and .NET only |  |  |
| `Test-SalesforceApexTestReference` | shared | PowerShell and .NET only |  |  |
