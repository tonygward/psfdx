# Changelog

## Unreleased

## 0.8.61 - 2026-11-24

- psfdx: every command is now discoverable straight after `Install-Module psfdx`, without `Import-Module psfdx` first. In a new session `Get-Command -Module psfdx*` lists every command of every module, not only the core ones, and any command, such as `Get-SalesforceDebugLogs`, autoloads by name. Until `psfdx` has loaded, `Get-Command` shows `psfdx` as the module of every command; once it has loaded (any command, or `Import-Module psfdx`), each shows its own module as before.

## 0.8.60 - 2026-11-24

- psfdx-data: Breaking (a packaging change, not a removal): `psfdx-bulk` is now `psfdx-data`, and the Salesforce data commands moved into it from `psfdx`: `Select-SalesforceRecords`, `Search-SalesforceRecords`, `New-SalesforceRecord`, `Set-SalesforceRecord`, `Get-SalesforceRecord`, `Remove-SalesforceRecord`, `Upsert-SalesforceRecord`, `Get-SalesforceRecordType`, `Get-SalesforceSObjectRecordCount`, `New-SalesforceFile`, `Export-SalesforceTreeData` and `Import-SalesforceTreeData`. They join the eight Bulk API 2.0 commands, so `Get-Command -Module psfdx-data` lists all the data commands. Names, parameters and behaviour are unchanged, and `Install-Module psfdx` still installs everything. Only code that imports `psfdx-bulk` by name or reads the `Source` of these commands needs to change: use `psfdx-data`. The website page `/modules/psfdx-bulk/` is now `/modules/psfdx-data/`, the `psfdx` page lists only core commands, and the `psfdx-data` page groups its commands as Records and queries, Tree data and Bulk API 2.0. As with every module other than `psfdx`, run `Import-Module psfdx` first in a new session: it loads the rest, including `psfdx-data`.

## 0.8.59 - 2026-11-24

- psfdx: Breaking: `psfdx-shared` is now an internal module that exports no commands, so the helpers it holds are no longer public commands and `Get-Command -Module psfdx*` lists only commands meant for you. These twelve were visible before; nine are now internal and unreachable from a script: `Invoke-Salesforce`, `Show-SalesforceResult`, `Get-SalesforceErrorMessage`, `Get-SalesforceDeployFailures`, `Get-SalesforceTestFailure`, `Get-SalesforceApexCliTestArguments`, `Get-SalesforceApexTestClassNamesFromPath`, `Test-SalesforceApexTestReference` and `Get-PsfdxCommonParameterSplat`. Use the documented cmdlets, or run `sf` yourself, instead. The three SOQL converters, `ConvertTo-SalesforceSoqlLiteral`, `ConvertTo-SalesforceSoqlIdentifier` and `ConvertTo-SalesforceSoqlDateTime`, are public commands of the core `psfdx` module now (their names, parameters and behaviour are unchanged, and they show `psfdx` as their module and appear in its command reference). Every psfdx cmdlet works as before, and `Install-Module psfdx` still installs everything. The website no longer has a `psfdx-shared` page.

## 0.8.58 - 2026-11-24

- psfdx-org: Breaking (a packaging change, not a removal): `psfdx-sandbox` is now `psfdx-org`, and the scratch org cmdlets moved into it from `psfdx-development`: `Get-SalesforceScratchOrgs`, `New-SalesforceScratchOrg`, `Resume-SalesforceScratchOrg`, `Remove-SalesforceScratchOrg` and `Remove-SalesforceScratchOrgs`. The command names, parameters and behaviour are unchanged, and the sandbox cmdlets stay as they were. `Install-Module psfdx` still installs everything and `Get-Command -Module psfdx-org` lists the sandbox and scratch org commands together. Only code that imports `psfdx-sandbox` by name, or reads `(Get-Command Get-SalesforceScratchOrgs).Source`, needs to change: use `psfdx-org`. The website page `/modules/psfdx-sandbox/` is now `/modules/psfdx-org/`.

## 0.8.57 - 2026-11-23

- psfdx-plugins: Breaking (a packaging change, not a removal): the Salesforce CLI plugin cmdlets are now their own module, `psfdx-plugins`, instead of part of `psfdx`: `Install-SalesforcePlugin`, `Get-SalesforcePlugins`, `Update-SalesforcePlugins`, `Uninstall-SalesforcePlugin`, `Get-SalesforcePluginDetails`, `Find-SalesforcePlugins`, `Reset-SalesforcePlugins`, `Test-SalesforcePluginSignature` and `Get-`, `Add-` and `Remove-SalesforcePluginAllowlist`. Every name, parameter, result, `-WhatIf` and confirmation, error and help text is unchanged, and `Install-Module psfdx` still installs everything in the one package, with `Import-Module psfdx` loading `psfdx-plugins` too. What differs is the module shown for these commands: `Get-Command -Module psfdx-plugins` lists them and `Get-Command -Module psfdx` no longer does. `Install-SalesforceCli` and `Update-SalesforceCli` stay in `psfdx`, because they install the CLI itself, not a plugin. If you install from a clone or the release zip, import `psfdx-plugins` as well as `psfdx` to keep these cmdlets. There is no separate `psfdx-plugins` package on the Gallery.

## 0.8.56 - 2026-11-23

- psfdx-bulk: Breaking (a packaging change, not a removal): the Bulk API 2.0 cmdlets are now their own module, `psfdx-bulk`, instead of part of `psfdx`: `Export-SalesforceBulkData`, `Import-SalesforceBulkData`, `Update-SalesforceBulkData`, `Upsert-SalesforceBulkData`, `Remove-SalesforceBulkData`, `Resume-SalesforceBulkJob`, `Get-SalesforceBulkJobStatus` and `Get-SalesforceBulkResult`. Every name, parameter, job result, `-WhatIf` and confirmation, error and help text is unchanged, and `Install-Module psfdx` still installs everything in the one package, with `Import-Module psfdx` loading `psfdx-bulk` too. What differs is the module shown for these commands: `Get-Command -Module psfdx-bulk` lists them and `Get-Command -Module psfdx` no longer does. Single-record create, update, get and delete, SOQL and the data tree cmdlets stay in `psfdx`. If you install from a clone or the release zip, import `psfdx-bulk` as well as `psfdx` to keep these cmdlets. There is no separate `psfdx-bulk` package on the Gallery.

## 0.8.55 - 2026-11-23

- psfdx-devops: Breaking (a packaging change, not a removal): the DevOps Center cmdlets are now their own module, `psfdx-devops`, instead of part of `psfdx-metadata`: the 26 `sf devops` cmdlets (`Get-SalesforceDevOpsProject`, `Start-SalesforceDevOpsPromotion` and the rest) and the 5 beta `sf project deploy pipeline` cmdlets (`Start-SalesforcePipelineDeploy`, `Test-SalesforcePipelineDeploy`, `Start-SalesforcePipelineQuickDeploy`, `Get-SalesforcePipelineDeployStatus`, `Resume-SalesforcePipelineDeploy`), because they all wrap the Salesforce CLI DevOps Center plugin. This is a packaging change, not a removal: every name, parameter, result, `-WhatIf` and confirmation, and help text is unchanged, and `Install-Module psfdx` still installs everything in the one package, with `Import-Module psfdx` loading `psfdx-devops` too. What differs is the module shown for these commands: `Get-Command -Module psfdx-devops` lists them and `Get-Command -Module psfdx-metadata` no longer does. If you install from a clone or the release zip and import `psfdx-metadata` on its own, import `psfdx-devops` as well to keep these cmdlets. There is no separate `psfdx-devops` package on the Gallery.

## 0.8.54 - 2026-11-23

- psfdx: every module now keeps its own identity after `Install-Module psfdx`, which is still one package and one command. Once `psfdx` has loaded (`Import-Module psfdx`, a first core command, or `Get-Command -Module psfdx`), `Get-Command -Module psfdx` shows only the core commands, `Get-Command -Module psfdx-logs` (and `psfdx-metadata`, `psfdx-development`, `psfdx-sandbox`, `psfdx-packages`, `psfdx-agentforce`) shows only that module's commands, and `Get-Command -Module 'psfdx*'` shows all of them with the right module in the `Source` column and no command twice. Before, every command showed `psfdx` as its module. Every command still works as before after `Import-Module psfdx`. PowerShell can only discover one module per installed package, so until `psfdx` has loaded a non-core command is not found by name; start with `Import-Module psfdx` (see docs/install.md). Existing installs update with `Update-Module psfdx`.

## 0.8.53 - 2026-11-23

- psfdx-metadata: every `sf devops` command is now covered, with 26 new cmdlets named `...SalesforceDevOps...`: projects (`Get-`, `New-`, `Update-SalesforceDevOpsProject`), work items (`Get-`, `New-`, `Update-`, `Initialize-` to prepare a one-off promotion, `Join-` to combine, and `New-SalesforceDevOpsReview` for a pull request), pipelines (`Get-SalesforceDevOpsPipeline`, `Get-SalesforceDevOpsPipelineDetails`, `New-`, `Update-` to rename, activate or deactivate), pipeline projects, stages, stage branches and stage environments (`Add-` and `Remove-`), and promotion (`Start-`, `Complete-`, `Test-SalesforceDevOpsPromotion` and `Get-SalesforceDevOpsRequestStatus`). They need a DevOps Center org. Deleting, deploying and activating ask for confirmation, and every change supports `-WhatIf`.

## 0.8.52 - 2026-11-23

- psfdx: new cmdlets for the rest of the Salesforce CLI: `Get-SalesforceCommunityTemplates`, `New-SalesforceCommunity` and `Publish-SalesforceCommunity` (Experience Cloud sites; publishing asks first), `Invoke-SalesforceGraphQL` and `Invoke-SalesforceRestRequest` (call the API as the CLI's logged-in user; a mutation or a write asks first and supports `-WhatIf`, and an error response throws with the response text), and `Invoke-SalesforceDoctor` (`-CreateIssue` shares your diagnostics on GitHub, so it asks first). On Windows the CLI cannot take a double quote in an argument, so use `-QueryFile` or `-BodyFile` for JSON there.
- psfdx: plugin management is complete: `Uninstall-SalesforcePlugin`, `Get-SalesforcePluginDetails`, `Find-SalesforcePlugins`, `Reset-SalesforcePlugins`, `Test-SalesforcePluginSignature` and the allowlist cmdlets (`Get-`, `Add-` and `Remove-SalesforcePluginAllowlist`). Anything that removes a plugin or relaxes the signature check asks for confirmation. `Install-SalesforcePlugin` gains `-Force`, `-Silent` and `-ExtendedDetails`, and `Update-SalesforcePlugins` gains `-ExtendedDetails`.
- psfdx: `Remove-SalesforceAlias` gains `-All` to remove every alias. It asks first (`-NoPrompt` skips the question, `-WhatIf` works); removing one alias works as before.
- psfdx-metadata: `Describe-SalesforceObjects` gains `-Category` (all, standard or custom).
- psfdx-development: new `Start-SalesforceUiBundleDevServer` previews a UI bundle on your computer in front of your own dev server, with `-Name`, `-Url`, `-Port` and `-Open`.

## 0.8.51 - 2026-11-23

- psfdx-agentforce: every `sf agent` command is now covered, plus `sf org create agent-user` and `sf org open agent`: 35 new cmdlets. Create and describe agents (`New-SalesforceAgent`, `New-SalesforceAgentSpec`, `New-SalesforceAgentTemplate`, `New-SalesforceAgentTestSpec`, `New-SalesforceAgentUser`, `Open-SalesforceAgent`); more agent tests (`New-SalesforceAgentTest`, `Resume-SalesforceAgentTest`, `Start-SalesforceAgentEvaluation`); preview sessions a script can drive (`Start-`, `Send-`, `Stop-SalesforceAgentPreview`, `Get-SalesforceAgentPreviewSessions`) and the interactive `Invoke-SalesforceAgentPreview`; trace files (`Get-SalesforceAgentTraces`, `Read-SalesforceAgentTrace`, `Remove-SalesforceAgentTrace`); ten Agentforce Data Library cmdlets (`...SalesforceAgentDataLibrary...`); and eight MCP server cmdlets (`...SalesforceMcp...`, preview). Everything that deletes asks for confirmation and supports `-WhatIf`. The MCP client secret is a `SecureString`. The interactive commands need a terminal and stop with a clear message without one.
- psfdx-agentforce: `Start-SalesforceAgentTest` and `Get-SalesforceAgentTestResult` gain `-ResultFormat` (junit, tap and human return the CLI text), `-OutputDir`, `-TestRunner` and `-ExtendedDetails`; `New-SalesforceAgentAuthoringBundle` gains `-ForceOverwrite`; `Publish-SalesforceAgentAuthoringBundle` gains `-Concise`, `-ExtendedDetails` and `-SourceType`.

## 0.8.50 - 2026-11-22

- psfdx-development: every `sf template generate` command is now covered, with 14 new generators: `New-SalesforceLightningComponent`, `New-SalesforceLightningApp`, `New-SalesforceLightningEvent`, `New-SalesforceLightningInterface`, `New-SalesforceLightningTest`, `New-SalesforceLightningOutApp`, `New-SalesforceUiEmbedding`, `New-SalesforceUiBundle`, `New-SalesforceFlexiPage` (beta), `New-SalesforceVisualforcePage`, `New-SalesforceVisualforceComponent`, `New-SalesforceStaticResource`, `New-SalesforceAnalyticsTemplate` and `New-SalesforceExperienceSite` (preview). They return the files they created. Because the Salesforce CLI replaces a generated file that differs from the template without asking, each stops when its target already exists and needs `-Force` to go ahead. `New-SalesforceApexClass` and `New-SalesforceApexTrigger` still do not check.
- psfdx-development: `New-SalesforceProject` gains `-LwcLanguage` and every template the CLI offers, `New-SalesforceApexClass` reaches all its templates, `New-SalesforceApexTrigger` gains `-Template`, and `Start-SalesforceLwcDevServer` gains `-DeviceId`, `-ClientSelect` and the `desktop` device type.

## 0.8.49 - 2026-11-22

- psfdx-development: every `sf apex` and `sf code-analyzer` command is now covered. New cmdlets: `Get-SalesforceApexCompileStatus` (classes and triggers that do not compile cleanly), `Get-SalesforceCodeAnalyzerConfig` (the current configuration as YAML, optionally saved to a file) and `Get-SalesforceCodeAnalyzerAst` (the syntax tree PMD builds for a file; needs Java).
- psfdx-development: `Invoke-SalesforceCodeAnalyzer` gains `-IncludeFixes`, `-IncludeSuggestions` (each violation then has `Fixes` and `Suggestions`), `-NoSuppressions`, `-TargetOrg`, `-View` and `-OutputFile` for extra result files; `Get-SalesforceCodeAnalyzerRule` gains `-View`. `Invoke-SalesforceApex` gains `-DebugLevel` and `-CategoryLevel`, `Test-SalesforceApex` gains `-Synchronous` and `-PollIntervalSeconds`, and `Get-SalesforceApexTestResult` gains `-ResultFormat` so you can get junit, tap or human text.

## 0.8.48 - 2026-11-22

- psfdx-metadata: all four `sf schema generate` commands are now covered: `New-SalesforceCustomObject`, `New-SalesforceCustomField`, `New-SalesforcePlatformEvent` and `New-SalesforceCustomTab`. The first three are interactive, as the CLI commands are: they ask questions, so run them in a terminal as plain commands. In a session without a terminal they stop with a clear message instead of waiting. `New-SalesforceCustomTab` takes everything from its parameters and says so clearly when the tabs folder does not exist.

## 0.8.47 - 2026-11-22

- psfdx-metadata: all five `sf cmdt generate` commands are now covered, so you can build custom metadata in a project from PowerShell: `New-SalesforceCustomMetadataType`, `New-SalesforceCustomMetadataField`, `New-SalesforceCustomMetadataRecord` (field values as a hashtable), `New-SalesforceCustomMetadataRecordsFromCsv` and `New-SalesforceCustomMetadataTypeFromOrg`. They write files into the current project; only `...FromOrg` reads an org.

## 0.8.46 - 2026-11-22

- psfdx-packages: every `sf package` and `sf package1` command is now covered. New cmdlets for second-generation packages: `Convert-SalesforcePackage`, `Update-SalesforcePackage`, `Uninstall-SalesforcePackage` (asks for confirmation) with `Get-SalesforcePackageUninstallStatus`, `Get-SalesforcePackageVersion`, `Update-SalesforcePackageVersion`, `Retrieve-SalesforcePackageVersion`, `Get-SalesforcePackageVersionAncestry`, `Get-SalesforcePackageVersionDependencies` and `Get-SalesforcePackageVersionCreateRequests`. Push upgrades: `New-SalesforcePushUpgrade` and `Stop-SalesforcePushUpgrade` ask for confirmation and support `-WhatIf`; `Get-SalesforcePushUpgrades` and `Get-SalesforcePushUpgrade` read. First-generation packages: `New-SalesforceFirstGenPackageVersion`, `Get-SalesforceFirstGenPackageVersionCreateStatus`, `Get-SalesforceFirstGenPackageVersion` and `Get-SalesforceFirstGenPackageVersions`.
- psfdx-packages: `New-SalesforcePackageVersion` gains `-Path`, `-Branch`, `-VersionNumber`, `-Language`, `-PostInstallScript`, `-UninstallScript`, `-PostInstallUrl`, `-ReleaseNotesUrl`, `-SkipAncestorCheck`, `-AsyncValidation`, `-GeneratePackageZip` and `-ExtendedDetails`. `Install-SalesforcePackageVersion` gains `-InstallationKey`, `-ApexCompile` and `-UpgradeType`, and `Get-SalesforcePackageVersions` gains `-CreatedLastDays`, `-ModifiedLastDays` and `-OrderBy`.
- psfdx: `-Verbose` output now hides the value of `--installation-key` (the `--installation-key-bypass` switch is left alone), as it already did for passwords and tokens.

## 0.8.45 - 2026-11-22

- psfdx: every `sf data` command is now covered. New cmdlets: `Search-SalesforceRecords` (SOSL search, returns objects with their `SObject`), `New-SalesforceFile` (upload a file, optionally attached to a record), `Remove-SalesforceBulkData` (bulk delete from a CSV; asks for confirmation, supports `-WhatIf`, `-HardDelete` deletes permanently) and `Get-SalesforceBulkJobStatus`. `Resume-SalesforceBulkJob` can now resume a delete job (`-Operation Delete`) and any job by `-UseMostRecent`. `New-SalesforceRecord` and `Set-SalesforceRecord` gain `-SkipAssignmentRules`, and `Set-SalesforceRecord` can select the record with `-Where` as well as `-Id`.

## 0.8.44 - 2026-11-22

- psfdx: every applicable `sf org` command is now covered. New cmdlets: `Get-SalesforceOrgDetails` (tokens and auth URLs are removed unless `-IncludeToken`), `Get-SalesforceAuthorizations`, `Connect-SalesforceAccessToken` (the token is a SecureString and reaches `sf` through its environment, never the command line) and `Get-SalesforceSObjectRecordCount`. `Connect-Salesforce` gains `-ClientApp`, `-Scopes` and `-Username`, `Disconnect-Salesforce` gains `-ClientApp`, and `Open-Salesforce` gains `-Path` and `-SourceFile`. The three `sf org auth show-*` commands that print a token, an auth URL or a password are deliberately left out.
- psfdx-sandbox: new `Update-SalesforceSandbox` refreshes a sandbox (asks for confirmation, supports `-WhatIf`). `New-SalesforceSandbox` and `Copy-SalesforceSandbox` gain `-Async`, `-PollIntervalSeconds` and `-SetDefault`; `New-SalesforceSandbox` gains `-SourceId` and `Copy-SalesforceSandbox` can clone by `-SourceId`. `Resume-SalesforceSandbox` can resume by `-JobId` or `-UseMostRecent` as well as by name.
- psfdx-development: new `Enable-SalesforceSourceTracking` and `Disable-SalesforceSourceTracking`, org shape cmdlets (`New-SalesforceOrgShape`, `Get-SalesforceOrgShapes`, `Remove-SalesforceOrgShape`) and snapshot cmdlets (`New-SalesforceOrgSnapshot`, `Get-SalesforceOrgSnapshot`, `Get-SalesforceOrgSnapshots`, `Remove-SalesforceOrgSnapshot`). The ones that delete or turn something off ask for confirmation and support `-WhatIf`. `New-SalesforceScratchOrg` gains `-Alias`, `-OAuthClientId`, `-NoAncestors`, `-NoNamespace` and `-NoTrackSource`.
- psfdx-metadata: new `Get-SalesforceMetadataComponents` lists the components of one metadata type in an org, and `Describe-SalesforceMetadataTypes` gains `-OutputFile`.

## 0.8.43 - 2026-11-22

- psfdx: `Connect-SalesforceApi` now accepts `-Password`, `-Token` and `-ClientSecret` as a SecureString, which is the recommended form: it is turned into text only when the login request is built and never appears in verbose, debug or error output. Plain strings still work, but each one now writes a warning because it stays readable in your session history. Nothing is removed yet.

## 0.8.42 - 2026-11-22

- psfdx-metadata: every `sf project` command (project, deploy and retrieve) is now covered, with every flag. New cmdlets: `New-SalesforceManifest`, `ConvertTo-SalesforceSourceFormat`, `ConvertTo-SalesforceMdapiFormat`, `Enable-SalesforceSourceBehavior`, `Get-SalesforceIgnoredFiles`, `Remove-SalesforceSource`, `Remove-SalesforceSourceTracking` and `Reset-SalesforceSourceTracking`. The ones that delete or reset ask for confirmation and support `-WhatIf`; `-NoPrompt` skips the question, and `Remove-SalesforceSource -CheckOnly` validates without deleting.
- psfdx-metadata: new beta DevOps Center pipeline cmdlets `Start-SalesforcePipelineDeploy`, `Test-SalesforcePipelineDeploy`, `Start-SalesforcePipelineQuickDeploy`, `Get-SalesforcePipelineDeployStatus` and `Resume-SalesforcePipelineDeploy`. They run the beta `sf project deploy pipeline` commands, need a DevOps Center org, and may change when the Salesforce CLI changes them.
- psfdx-metadata: `Deploy-SalesforceMetadata` and `Deploy-SalesforceComponent` gain `-Async`, `-CoverageFormatters`, `-Junit` and `-ResultsDir`; `Deploy-SalesforceMetadata` also gains `-PreDestructiveChanges`, `-PostDestructiveChanges` and `-PurgeOnDelete`, and `Deploy-SalesforceComponent -TestLevel` accepts `RelevantTests`. `Test-SalesforceDeploy` gains `-Metadata` and the same destructive-changes and results options. `Get-SalesforceDeployStatus` and `Resume-SalesforceDeploy` gain `-CoverageFormatters`, `-Junit` and `-ResultsDir`. The deploy and retrieve previews gain `-ConciseResults`. `Retrieve-SalesforceComponent` gains `-SourceDir` and `-RootTypeWithDependencies`, and `Retrieve-SalesforceMetadata` gains `-SinglePackage` and `-ZipFileName`.
- psfdx-metadata: two error messages changed because there are more ways to name what to deploy or retrieve: `Test-SalesforceDeploy` now says "Specify exactly one of -Manifest, -SourceDir, -InputDir, or -Metadata." and `Retrieve-SalesforceComponent` says "Specify -Type or -SourceDir when retrieving a component."

## 0.8.41 - 2026-11-22

- psfdx, psfdx-development, psfdx-logs: the cmdlets now run the current Salesforce CLI command names instead of deprecated aliases and reordered words: `Get-SalesforceLimits` runs `sf org list limits`, `New-SalesforceProject` runs `sf template generate project`, `New-SalesforceApexClass` and `New-SalesforceApexTrigger` run `sf template generate apex class` and `trigger`, and the debug log cmdlets run `sf apex list log`, `get log` and `tail log`. Results are the same, but a CLI release that removes the old names no longer breaks them.

## 0.8.40 - 2026-11-21

- All modules: every exported command now has complete help, shown by `Get-Help <command> -Full`, `-Examples` and `-Parameter *`: a synopsis, a description, one entry for every parameter (with its default, valid values and the CLI flag it feeds), examples and links. The notes have a "Salesforce CLI mapping" section that names the exact `sf` command or commands the cmdlet runs, the old name or word order it is run by when that differs from the current command, the flags and values it cannot pass, and says when a cmdlet does not run `sf` at all. The helpers that `psfdx-shared` exports are labelled as internal, and `Test-SalesforceApexTestReference` says it only reads a local file. A test checks all of this, and the Gallery install check now checks the help of the published package.
- psfdx: Breaking: `Open-Salesforce -BrowserPrivateMode` is now a switch. It was a string written as `--private <value>`, but the CLI's `--private` takes no value, so any use of it failed. Use `-BrowserPrivateMode` with no value.

## 0.8.39 - 2026-11-21

- psfdx: Breaking: `Connect-SalesforceApi -CustomUrl` and `Invoke-SalesforceApi -Url` now accept only an absolute https:// URL. They send a password, client secret or access token, which must not travel over plain http. Before this, an http URL was used as given.
- psfdx-packages: `Promote-SalesforcePackageVersion` now asks for confirmation and supports `-WhatIf`, because a promoted version can no longer be deleted. `-NoPrompt` skips the question, so existing unattended scripts keep working. `Install-SalesforcePackageVersion` now supports `-WhatIf` and `-Confirm` without asking by default.
- psfdx-metadata: `Deploy-SalesforceMetadata` and `Deploy-SalesforceComponent` now support `-WhatIf` and `-Confirm` without asking by default. A validation-only deploy (`-DryRun`) still runs under `-WhatIf`.
- psfdx: `Install-SalesforceCli`, `Update-SalesforceCli`, `Install-SalesforcePlugin` and `Update-SalesforcePlugins` now support `-WhatIf` and `-Confirm` without asking by default. `Install-SalesforcePlugin` refuses a name that starts with a dash or contains spaces or control characters. `New-SalesforceRecord` and `Set-SalesforceRecord` no longer repeat the field values on the verbose stream.
- psfdx-logs: `Export-SalesforceEventFile` and `Get-SalesforceEventFile` check that `-Id` is a Salesforce ID, so an ID such as `..\..\x` can no longer write outside the output folder.
- All modules: ID and name checks now reject a value that ends in a line break, which the old checks let through.
- On Windows, a command that is too long for `cmd.exe` (over about 7800 characters through the `sf.cmd` shim) now stops with a message to shorten the query or use `--file`, instead of returning cmd.exe's error text as a result. Calls that run at the same time in one session no longer share a temporary environment variable. The security audit and its findings are in docs/security-findings.md.

## 0.8.38 - 2026-11-21

- psfdx, psfdx-packages: records, package versions and trace flags now work in pipelines. `Remove-`, `Get-` and `Set-SalesforceRecord` take the ID from piped records, `Remove-` and `Promote-SalesforcePackageVersion` take the version from `Get-SalesforcePackageVersions`, and `Disable-SalesforceDebugLogging` already took trace flags. Each piped object is confirmed and honours `-WhatIf` on its own. `New-SalesforceRecord` and `Set-SalesforceRecord` now support `-WhatIf` and `-Confirm` (they still do not prompt by default). Existing calls work unchanged. The README has a new Pipelines section on empty results, single versus many results and errors.

## 0.8.37 - 2026-11-21

- psfdx-agentforce: new `New-SalesforceAgentAuthoringBundle`, `Test-SalesforceAgentAuthoringBundle` and `Publish-SalesforceAgentAuthoringBundle` script the Agent Script flow of generate, validate and publish. Validation returns its diagnostics as objects (and `-ThrowOnInvalid` fails a CI step); generating files and publishing ask for confirmation and support `-WhatIf`. These upstream commands are newer and may be beta, so they need a recent `@salesforce/plugin-agent`.

## 0.8.36 - 2026-11-21

- psfdx-development: new `Invoke-SalesforceCodeAnalyzer` and `Get-SalesforceCodeAnalyzerRule` wrap `sf code-analyzer run` and `sf code-analyzer rules`. The run returns each finding as an object (rule, engine, severity, message, file and position). A run that fails your `-SeverityThreshold` still returns its findings with `ThresholdExceeded`, and `-ThrowOnThreshold` turns that into an error for CI; a missing plugin or an engine that cannot start always throws, with install guidance (Java 11 or later for the Java-based engines).

## 0.8.35 - 2026-11-21

- psfdx-development: new `Resume-SalesforceScratchOrg` picks up a scratch org creation that was started with `-Async` or timed out, by `-JobId` or `-UseMostRecent`, and returns the org with a `Completed` flag. `New-SalesforceScratchOrg` gained `-Async`. To give the new org access, follow with `Grant-SalesforcePermissionSet` from psfdx, which already wraps `sf org assign permset`.

## 0.8.34 - 2026-11-21

- psfdx-metadata: new `Get-SalesforceDeployPreview` and `Get-SalesforceRetrievePreview` show what a deploy or retrieve would change, and any conflicts, before you run it. They are read-only and return the changes, deletes, conflicts and ignored files as lists, with `HasChanges` and `HasConflicts`. They need an org with source tracking; for other orgs they return the CLI error with guidance.

## 0.8.33 - 2026-11-21

- psfdx: new `Get-SalesforceRecord` and `Remove-SalesforceRecord` complete single-record create, read, update and delete. Select the record with `-Id`, or with `-Where` (a hashtable of field values that identify exactly one record); the two are alternatives. Get returns the record without the internal `attributes` property. Remove asks for confirmation, naming the object, record and org, supports `-WhatIf`, and returns the CLI result; a missing record or a `-Where` that matches several throws the CLI message. Unattended scripts need `-Confirm:$false`.

- psfdx-packages: new `Get-SalesforcePackageVersionCreateStatus` and `Get-SalesforcePackageInstallStatus` let a later CI step recover the outcome of a package build or install. They return the status, IDs and error messages as an object, with `Completed` and `Succeeded`, and `-ThrowOnFailure` for CI. Capture the create request `Id` (08c...) from `New-SalesforcePackageVersion`, and the install request `Id` (0Hf...) from `Install-SalesforcePackageVersion -AsObject`. `-AsObject` is new; without it `Install-SalesforcePackageVersion` behaves as before.

## 0.8.32 - 2026-11-21

- psfdx-development: the Apex test lifecycle in separate steps. `Start-SalesforceApexTest` starts a run and returns its `TestRunId` straight away; `Get-SalesforceApexTestResult` fetches the structured results (summary, each test's outcome and run time, optional coverage) for a run from any later session; `Wait-SalesforceApexTest` polls until the run finishes or a timeout passes (`PsfdxTestRunTimeout`). Failing tests write the results and then throw `PsfdxTestsFailed`; a command that could not run throws `PsfdxTestRunInvocationFailed`. A run that is still queued or processing returns `Completed = $false. The Flow and combined Flow/Apex test commands now also report `Completed`. `Test-SalesforceApex` is unchanged.

## 0.8.31 - 2026-11-21

- psfdx: new `Export-SalesforceTreeData` and `Import-SalesforceTreeData` copy related records (a parent with its children) between orgs as JSON, for example from a sandbox into a scratch org: `Export-SalesforceTreeData -Query "SELECT Id, Name, (SELECT Id, LastName FROM Contacts) FROM Account" -Plan -OutputDirectory .\data -TargetOrg source` then `Import-SalesforceTreeData -Plan .\data\Account-Contact-plan.json -TargetOrg scratch`. Import takes `-Plan` or `-File` (not both), supports `-WhatIf`, returns the created records (`RefId`, `Type`, `Id`), and throws `PsfdxTreeImportFailed` listing each rejected record. The Tree API suits test data (up to 200 records per import); use the Bulk API commands for large loads.

## 0.8.30 - 2026-11-21

- Maintenance release.

## 0.8.29 - 2026-11-21

- psfdx: Bulk API 2.0 commands. `Export-SalesforceBulkData`, `Import-SalesforceBulkData`, `Update-SalesforceBulkData` and `Upsert-SalesforceBulkData` wrap `sf data export|import|update|upsert bulk`; `Resume-SalesforceBulkJob` resumes a job by `-JobId` in a later step; `Get-SalesforceBulkResult` returns a job's counts and saves its success, failed and unprocessed rows as CSV files. Without `-WaitMinutes` a command creates the job and returns its `JobId`. A job with failed rows throws an error with the id `PsfdxBulkJobFailed` whose target holds the `JobId`. The three write commands support `-WhatIf` and name the object, file and org. The CLI remembers jobs it created on this computer, so `Resume-SalesforceBulkJob` cannot resume a job created elsewhere; use `Get-SalesforceBulkResult -TargetOrg` for that.

- psfdx: user administration. `Get-SalesforceAuthenticatedUser` and `Get-SalesforceOrgUser` read the users the CLI has authorised here; `New-SalesforceUser` creates a user; `New-SalesforceUserPassword` generates a password and returns it as a SecureString; `Grant-SalesforcePermissionSet` and `Grant-SalesforcePermissionSetLicense` assign permission sets and licences, and report `Assigned`, `AlreadyAssigned` or `Failed` for each so a script can run again safely. Everything that changes a user supports `-WhatIf`; the password and permission commands ask for confirmation, so unattended scripts need `-Confirm:$false`. Access tokens are never returned, and a password only as a SecureString from `New-SalesforceUserPassword`; `Get-SalesforceOrgUser` reports `HasPassword` because the CLI redacts the real value. The CLI lists only the users it has authorised on this computer; use `Get-SalesforceUsers` to query all users.

## 0.8.28 - 2026-11-21

- psfdx-development: new `Test-SalesforceFlow` and `Get-SalesforceFlowTestResult` run Flow tests and fetch their results (`sf flow run test` and `sf flow get test`), and new `Test-SalesforceLogic` and `Get-SalesforceLogicTestResult` run Flow and Apex tests together (`sf logic run test` and `sf logic get test`). A run is asynchronous by default and returns a `TestRunId`; use `-Synchronous` (or `-WaitMinutes` for the combined command) to wait for the results, which come back as one object with `Summary`, `Tests` and `Coverage`. `-TestCategory` needs `-TestLevel`, as the Salesforce CLI requires. A run with failing tests throws an error with the id `PsfdxTestsFailed` after writing the results; a command that could not run (no authorisation, missing plugin) throws `PsfdxTestRunInvocationFailed`, so CI can tell them apart. `Test-SalesforceApex` is unchanged.

## 0.8.27 - 2026-11-20

- psfdx: new `Upsert-SalesforceRecord` creates or updates a single record by external ID, for example `Upsert-SalesforceRecord -Type Account -ExternalIdField Ext_Id__c -ExternalId 'A-100' -Fields @{ Name = 'Acme' } -TargetOrg myalias`. It returns `Operation` (`Created` or `Updated`), `Created` and `StatusCode`, plus the new `Id` when a record was created (older API versions do not return the Id for an update, so it is empty then). The Salesforce CLI has no single-record upsert command, so this uses the REST API through `sf api request rest`; it uses the org's latest API version unless you pass `-ApiVersion`. For bulk loads use `sf data upsert bulk`.

## 0.8.26 - 2026-11-20

- All modules: loading the shared helpers (`psfdx-shared`) is now predictable. Versions are compared as version numbers (0.8.10 is newer than 0.8.9), only a copy with the same release series and no older than the module is accepted, a stale copy already loaded in the session is replaced instead of silently used, and a missing or mismatched copy now fails with a message that says what was found and how to fix it.

## 0.8.25 - 2026-11-20

- psfdx, psfdx-sandbox, psfdx-shared: on Windows PowerShell 5.1, query results (`Select-SalesforceRecords`, and every cmdlet that returns query records) no longer include Salesforce's internal `attributes` property.

## 0.8.24 - 2026-11-20

- psfdx, psfdx-development, psfdx-packages, psfdx-sandbox: `Disconnect-Salesforce`, `Remove-SalesforceScratchOrg`, `Remove-SalesforceScratchOrgs`, `Remove-SalesforceSandbox`, `Remove-SalesforcePackage` and `Remove-SalesforcePackageVersion` now ask for confirmation and support `-WhatIf` (which changes nothing). `Remove-SalesforceScratchOrgs` asks once, naming every scratch org it will delete. Scripts that run these unattended must now pass `-Confirm:$false`; `-NoPrompt` still only controls the Salesforce CLI prompt.

## 0.8.23 - 2026-11-20

- psfdx-packages: `Get-SalesforcePackagesInstalled` now returns the installed packages; it previously returned nothing because it looked for a `records` list the CLI does not send.

## 0.8.22 - 2026-11-19
- psfdx, psfdx-development, psfdx-logs, psfdx-metadata: every cmdlet now passes each value to the Salesforce CLI as its own argument, so paths, names, queries, descriptions and tags with spaces, quotes or apostrophes reach `sf` exactly as typed. This covers authentication, aliases, queries, projects, scratch orgs, Apex tests and generators, LWC and Jest, debug logs, trace flags, event log files, and retrieve, deploy and describe. Together with the earlier psfdx-packages, psfdx-sandbox and psfdx-agentforce changes, no cmdlet builds a command string any more.
- psfdx-development: `Test-SalesforceApex -TestsInProject` now says "No Apex test classes found in the project." when there are none, instead of a parameter validation error.
- psfdx-shared: `Get-SalesforceApexCliTestParams` and `ConvertTo-SalesforceCliApexTestParams` (command-string helpers) are removed; use `Get-SalesforceApexCliTestArguments`.

## 0.8.21 - 2026-11-19

- psfdx-sandbox: the sandbox cmdlets now pass each value to the Salesforce CLI as its own argument, so values with spaces or quotes reach `sf` exactly as typed.

## 0.8.20 - 2026-11-19

- psfdx-agentforce: the agent cmdlets now pass each value to the Salesforce CLI as its own argument, so values with spaces or quotes reach `sf` exactly as typed.

## 0.8.19 - 2026-11-19

- psfdx-shared: Salesforce CLI failures now stop with a clear error. Every cmdlet that reads `sf --json` output throws for empty output, text that is not JSON, malformed JSON, or JSON with no `status`, and shows a short redacted preview instead of a parser error. If the CLI process exits with an error and prints no JSON, the error gives the exit code. Tokens and auth URLs are never shown. Commands without `--json` return their output as before.
- psfdx-packages: package cmdlets now pass each value to the Salesforce CLI as its own argument. Names, descriptions, tags, installation keys, paths and branches with spaces, apostrophes, quotes or `%` reach `sf` exactly as typed. Before, `New-SalesforcePackage -Description "My description"` split the description into several arguments. On Windows PowerShell 5.1, double quotes inside an argument are now kept when running a real program such as `sf.exe`.
- psfdx-shared: `Invoke-Salesforce` accepts `-FilePath` and `-Arguments` (an exact argument array) as well as the existing `-Command` string.

## 0.8.18 - 2026-11-19

- Maintenance release.

## 0.8.17 - 2026-11-18

- psfdx, psfdx-logs: dates sent to Salesforce are now converted to UTC before the `Z` is added. Before, local time was labelled as UTC, so in British Summer Time `Get-SalesforceDateTime` and the `-After` and `-Before` filters of `Get-SalesforceFlowInterviews`, `Get-SalesforceLoginHistory`, `Select-SalesforceEventFiles` and `Export-SalesforceEventFiles` were an hour out. A date with no time zone, such as one parsed from `'2026-11-18 12:00'`, is read as your local time.
- psfdx-shared: new `ConvertTo-SalesforceSoqlDateTime` helper.

## 0.8.16 - 2026-11-18
- psfdx, psfdx-development, psfdx-logs, psfdx-sandbox: values that cmdlets put into generated SOQL are now escaped the way SOQL requires. This covers `Get-SalesforceUsers -Username`, `Get-SalesforceRecordType -ObjectType`, `Get-SalesforceApexClass -Name`, `Select-SalesforceEventFiles` and `Export-SalesforceEventFiles -EventType`, `Get-SalesforceLoginHistory -Username`, `Get-SalesforceSandboxRefreshStatus -Name`, and the user, class and trigger lookups in `Enable-SalesforceDebugLogging`. A value with an apostrophe or a backslash no longer breaks the query or changes its meaning. Names such as `O'Brien` used to be rejected by Salesforce and now work. A value with a control character is refused with a clear message. Your own queries passed to `Select-SalesforceRecords -Query` are unchanged.
- psfdx-metadata: `Build-SalesforceQuery` refuses an object name that is not a plain API name.
- psfdx-shared: new `ConvertTo-SalesforceSoqlLiteral` and `ConvertTo-SalesforceSoqlIdentifier` helpers.

## 0.8.15 - 2026-11-18

- psfdx-sandbox: `Copy-SalesforceSandbox` works again. It ran `sf org clone sandbox`, which the Salesforce CLI no longer has, and now runs `sf org create sandbox --source-sandbox-name ... --name ...`. Parameters are unchanged.
- psfdx-development: `Get-SalesforceTargetOrg -Global` and `Get-SalesforceTargetDevHub -Global` work again. They passed `--global` to `sf config get`, which the Salesforce CLI rejects. They now return the setting only when it is set globally, using the location the CLI reports.

## 0.8.14 - 2026-11-17

- psfdx, psfdx-sandbox, psfdx-shared: The module manifests now declare Windows PowerShell 5.1 as the minimum version and both the Desktop and Core editions, matching the other modules, so the PowerShell Gallery shows the same requirements for every module.

- psfdx: psfdx is now on the PowerShell Gallery: install it with `Install-Module psfdx`.

## 0.8.13 - 2026-11-17

- psfdx-agentforce: New module for the Salesforce CLI agent plugin. It can list, run and read results of agent tests (`Get-SalesforceAgentTests`, `Start-SalesforceAgentTest`, `Get-SalesforceAgentTestResult`), activate and deactivate agents (`Enable-SalesforceAgent`, `Disable-SalesforceAgent`, both ask for confirmation and support `-WhatIf`), and check the plugin is installed (`Test-SalesforceAgentPlugin`). Beta commands are not wrapped.
- psfdx: Added an offline Salesforce CLI compatibility check to the test suite. It flags removed commands, legacy flags and unknown command families in any module, naming the file, function and a suggested replacement, and writes a machine-readable report with the pinned CLI version. No org or credentials are needed.

## 0.8.12 - 2026-11-17

- psfdx: The Salesforce CLI no longer returns access tokens, refresh tokens or auth URLs in ordinary `--json` output, so `Connect-SalesforceAuthUrl -IncludeToken` returns them only if your CLI version supplies them; nothing is fetched on your behalf. Tokens and auth URLs are still stripped by default, and `Connect-SalesforceJwt` now strips them too. No migration is needed unless you relied on `-IncludeToken` returning a token; use `sf org display --verbose --json` yourself for that.
- psfdx: `Get-SalesforceConnections` now stops with the CLI's error message on failure, and also works when the CLI returns `devHubs`, `sandboxes` and `other` instead of `nonScratchOrgs`.
- psfdx-shared: Debug output and error handling for failed commands now mask access tokens, refresh tokens, passwords and SFDX auth URLs.

## 0.8.11 - 2026-11-17

- psfdx-development: `Start-SalesforceLwcDevServer` now supports `-Mode App|Component|Site` (default `App`, as before) with `-Name`, `-DeviceType` and `-TargetOrg`, and stops with a clear message pointing to `Install-SalesforceLwcDevServer` when the `@salesforce/plugin-lightning-dev` plugin is not installed.
- psfdx-development: Breaking: `New-SalesforceJestTest` no longer calls the removed `sf force lightning lwc test create` command. It now writes `__tests__/<name>.test.js` itself, returns the created file instead of the CLI result, checks that the component exists, and refuses to overwrite an existing test unless `-Force` is used. New `-ProjectPath` and `-Force` parameters.

## 0.8.10 - 2026-11-17

- psfdx-shared: On Windows, `%` is no longer rejected in arguments passed to the `sf` `.cmd` shim, so SOQL wildcard queries such as `Select-SalesforceRecords -Query "SELECT Id FROM Account WHERE Name LIKE 'Acme%'"` work again, and a literal `%NAME%` is passed to `sf` unchanged instead of being expanded. Double quotes and line breaks are still rejected, and `-Verbose` still masks secrets.

## 0.8.9 - 2026-11-17

- psfdx: psfdx is now released under the MIT licence. The `LICENSE` file ships in the release ZIP and the PowerShell Gallery package, the Gallery package lists it (`LicenseUri`), and the README links to it.

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
