![PSFDX](images/psfdx-logo.png)
[![CI](https://github.com/tonygward/psfdx/actions/workflows/ci.yml/badge.svg)](https://github.com/tonygward/psfdx/actions/workflows/ci.yml)
Cross platform PowerShell modules that wrap the Salesforce CLI.

# Installation

## 1. Pre-Requisites
PowerShell 7 (Windows, Linux or macOS) or Windows PowerShell 5.1
https://github.com/PowerShell/PowerShell/releases


## 2. Install psfdx

```
Install-Module psfdx
```

PowerShell asks about the untrusted PSGallery repository. Answer `Y` or `A`:

![Install-Module psfdx asks about the untrusted PSGallery repository](images/psfdx-install-trust-prompt.png)

## 3. See the commands

```
Get-Command -Module psfdx
```

## 4. Update psfdx

```
Update-Module psfdx
```

## 5. Salesforce CLI

   You can install the Salesforce CLI by running:

   ```powershell
   Import-Module psfdx
   Install-SalesforceCli
   ```
   On Windows, Linux and macOS it uses npm (`npm install --global @salesforce/cli`), the install method Salesforce supports. `Update-SalesforceCli` runs `npm update --global @salesforce/cli`.<br>
   If you installed the CLI with the old Homebrew tap (`sfdx-cli/tap/sf`), uninstall it with `brew uninstall sfdx-cli/tap/sf` before running `Install-SalesforceCli`.<br>
   psfdx is tested against the latest stable Salesforce CLI: CI installs it and checks every `sf` command and flag psfdx uses against its help, and logs the exact version. No CLI version is pinned. See [docs/cli-compatibility.md](docs/cli-compatibility.md).

# Examples
**1. Connect to a Salesforce Sandbox Org**
```
Import-Module psfdx
Connect-Salesforce -Sandbox
```
A web browser will appear, login to Salesforce as you would normally.

If you enable Verbose messages
```$VerbosePreference = "Continue```

Then **-Verbose** switch reveals the Salesforce CLI commands
![Connect-Salesforce with Verbose](images/connect-verbose.png)

**2. Create and use a Salesforce Alias**
```
Add-SalesforceAlias -TargetOrg my@email.com -Alias myalias
Select-SalesforceRecords -Query "SELECT Id, Name FROM Account LIMIT 10" -TargetOrg myalias
```
**3. Retrieve first 10 Salesforce Accounts**
```
Select-SalesforceRecords -Query "SELECT Id, Name FROM Account LIMIT 10" -TargetOrg my@email.com
```
NB you only need to Import-Module psfdx once per PowerShell session

**4. Export Salesforce Debug Logs to Files**
```
Export-SalesforceDebugLogs -TargetOrg my@email.com
```

**5. List every psfdx cmdlet**
```
Get-Command -Module psfdx*
```


## Working on psfdx
The Gallery is the supported way to install psfdx. If you want to change psfdx itself, clone the repository and run `./install.ps1` (Mac or Linux) or `./install-windows.ps1` (Windows). That installs the modules separately, so each one is imported on its own (for example `Import-Module psfdx-logs`). Don't combine it with the Gallery install on the same machine. See [CLAUDE.md](CLAUDE.md) and [docs/](docs/) for how the project is built and tested.


## Licence

psfdx is released under the MIT licence. See [LICENSE](LICENSE).

## Modules
| Module | Description |
| :--- | :--- |
| `psfdx` | Core cmdlets for authentication, record operations, org management, and utilities. |
| `psfdx-logs` | Debug Logs, Login History and Event Monitoring. |
| `psfdx-metadata` | Retrieve, deploy and describe Salesforce metadata. |
| `psfdx-development` | Salesforce DX development (projects, scratch orgs, tests, deploy). |
| `psfdx-sandbox` | Salesforce sandbox lifecycle management. |
| `psfdx-packages` | Salesforce packages: create, version, promote, install. |
| `psfdx-agentforce` | Agentforce agent tests and activation through the Salesforce CLI agent plugin. |


### psfdx

Included in the `psfdx` package.

### Authentication & Orgs

| Cmdlet | Description |
| :--- | :--- |
| `Connect-Salesforce` | Web-based org authentication. |
| `Connect-SalesforceAuthUrl` | Authenticate using a stored SFDX auth URL file (supports alias/default flags and hides tokens and auth URLs unless `-IncludeToken`; `-IncludeToken` only returns what the CLI itself provides). |
| `Disconnect-Salesforce` | Logout from Salesforce org (asks for confirmation, supports `-WhatIf`). |
| `Connect-SalesforceJwt` | JWT-based authentication. |
| `Open-Salesforce` | Open org in a browser or get URL. |
| `Get-SalesforceConnections` | List connected orgs (excluding scratch orgs). |
| `Repair-SalesforceConnections` | Clean up stale connections. |

### Aliases

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforceAlias` | List Salesforce aliases. |
| `Add-SalesforceAlias` | Create/update an alias. |
| `Remove-SalesforceAlias` | Remove an alias. |

### Limits & Usage

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforceLimits` | Retrieve org limits (API, storage, etc.). |
| `Get-SalesforceDataStorage` | Calculate data storage usage and percent. |
| `Get-SalesforceApiUsage` | Calculate API usage percent. |

### Data & SOQL

| Cmdlet | Description |
| :--- | :--- |
| `Select-SalesforceRecords` | Run SOQL and return records. |
| `Get-SalesforceUsers` | List users with optional filters (username, active only, limit). |
| `Get-SalesforceAuthenticatedUser` | List the users of an org that the CLI has authorised here (`sf org list users`); tokens removed. |
| `Get-SalesforceOrgUser` | Show the user the CLI is signed in as (`sf org display user`); never returns the token or password (the CLI redacts them), only `HasPassword`. |
| `New-SalesforceUser` | Create a user from a definition file and/or `-Field` values (`sf org create user`). Supports `-WhatIf`. |
| `New-SalesforceUserPassword` | Generate a password for a user, returned as a SecureString (`sf org generate password`). Asks for confirmation. |
| `Grant-SalesforcePermissionSet` | Assign permission sets to users (`sf org assign permset`); re-running is safe (`AlreadyAssigned`). Asks for confirmation. |
| `Grant-SalesforcePermissionSetLicense` | Assign permission set licences to users (`sf org assign permsetlicense`). Asks for confirmation. |
| `New-SalesforceRecord` | Create a record. |
| `Set-SalesforceRecord` | Update a record. |
| `Get-SalesforceRecord` | Get one record by `-Id`, or by `-Where` field values that identify exactly one (`sf data get record`). |
| `Remove-SalesforceRecord` | Delete one record by `-Id` or `-Where` (`sf data delete record`). Asks for confirmation; supports `-WhatIf`. |
| `Upsert-SalesforceRecord` | Create or update one record by external ID. The CLI has no single-record upsert, so this calls the REST API through `sf api request rest`. Returns `Operation` (Created or Updated), `Created`, `Id` (known only on create) and `StatusCode`. |
| `Export-SalesforceTreeData` | Export records with their child records to JSON (and with `-Plan`, a plan file) for copying test data between orgs (`sf data export tree`). |
| `Import-SalesforceTreeData` | Import tree JSON files or a plan into an org (`sf data import tree`); `-Plan` or `-File`, not both. Supports `-WhatIf`. |
| `Export-SalesforceBulkData` | Export a SOQL query to a file with Bulk API 2.0 (`sf data export bulk`). Returns a `JobId` at once, or the row count with `-WaitMinutes`. |
| `Import-SalesforceBulkData` | Insert the rows of a CSV with Bulk API 2.0 (`sf data import bulk`). Supports `-WhatIf`. |
| `Update-SalesforceBulkData` | Update records from a CSV with Bulk API 2.0 (`sf data update bulk`). Supports `-WhatIf`. |
| `Upsert-SalesforceBulkData` | Upsert records from a CSV by external ID with Bulk API 2.0 (`sf data upsert bulk`). Supports `-WhatIf`. |
| `Resume-SalesforceBulkJob` | Resume an export, import, update or upsert job by `-JobId` in a later step. The CLI finds the org from its record of the job, so it must have been created on this computer. |
| `Get-SalesforceBulkResult` | Get a bulk ingest job's counts and save its success, failed and unprocessed row CSVs to `-OutputDirectory` (`sf data bulk results`). Works for any job in the org. |
| `Get-SalesforceRecordType` | List record types (optionally by object). |

### REST API

| Cmdlet | Description |
| :--- | :--- |
| `Connect-SalesforceApi` | OAuth2 password flow (non-SFDX REST). |
| `Invoke-SalesforceApi` | Invoke REST API with bearer token. |
| `Get-SalesforceApiVersions` | Current Salesforce API versions. |
| `Get-SalesforceApiVersions` | Latest Salesforce API version. |

### Plugins

| Cmdlet | Description |
| :--- | :--- |
| `Install-SalesforceCli` | Install the Salesforce CLI. |
| `Update-SalesforceCli` | Update the Salesforce CLI. |
| `Install-SalesforcePlugin` | Install a Salesforce CLI plugin. |
| `Get-SalesforcePlugins` | List installed plugins (optionally core). |
| `Update-SalesforcePlugins` | Update installed plugins. |

### Utilities

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforceDateTime` | Format the current or a given datetime as a Salesforce UTC literal. Local time is converted to UTC first. |


### psfdx-metadata

Included in the `psfdx` package.

### Retrieve

| Cmdlet | Description |
| :--- | :--- |
| `Retrieve-SalesforceComponent` | Retrieve specific metadata component by type/name. |
| `Retrieve-SalesforceMetadata` | Retrieve metadata using a package.xml manifest. |
| `Retrieve-SalesforcePackage` | Retrieve metadata for an unlocked package. |
| `Retrieve-SalesforceField` | Retrieve a specific custom field. |
| `Retrieve-SalesforceValidationRule` | Retrieve a specific validation rule. |
| `Retrieve-SalesforceOrg` | Retrieve entire Salesforce Org. |

### Deploy

| Cmdlet | Description |
| :--- | :--- |
| `Deploy-SalesforceComponent` | Deploy specific metadata by type/name. |
| `Deploy-SalesforceMetadata` | Deploy using a manifest, metadata directory, or single-package artifact. |
| `Test-SalesforceDeploy` | Validate a deployment without saving it (check-only); use `-Manifest`, `-SourceDir` or `-InputDir` (a Metadata API directory or `.zip`); returns a job ID for quick deploy. Tests always run (`NoTests` is not allowed); `-TestLevel` is `SpecificTests`, `ReferencedTests`, `TestsInFolder`, `TestsInOrg` (default), `TestsInOrgAndPackages` or `RelevantTests`. |
| `Start-SalesforceQuickDeploy` | Quick deploy a validated deployment by `-JobId` or `-UseMostRecent` (asks for confirmation). |
| `Get-SalesforceDeployStatus` | Report the status of a deployment by `-JobId` or `-UseMostRecent`. |
| `Resume-SalesforceDeploy` | Resume watching a deployment that is still running, by `-JobId` or `-UseMostRecent`. The org comes from the cached deployment, so there is no `-TargetOrg`. |
| `Get-SalesforceDeployPreview` | Read-only preview of what a deploy would send, with conflicts, deletes and ignored files, from `sf project deploy preview`. Needs a source-tracked org. Narrow with `-SourceDir`, `-Manifest` or `-Metadata`. |
| `Get-SalesforceRetrievePreview` | Read-only preview of what a retrieve would bring down and any conflicts, from `sf project retrieve preview`. Needs a source-tracked org. |
| `Stop-SalesforceDeploy` | Cancel a running deployment (asks for confirmation). |

Validate, then quick deploy, and resume or report on a running deployment:

```powershell
$validation = Test-SalesforceDeploy -SourceDir force-app -TestLevel TestsInOrg -TargetOrg prod -Wait 30
Start-SalesforceQuickDeploy -JobId $validation.id -TargetOrg prod

Resume-SalesforceDeploy -UseMostRecent -Wait 10
Get-SalesforceDeployStatus -JobId 0AfXXXXXXXXXXXXXXX -TargetOrg prod
Stop-SalesforceDeploy -JobId 0AfXXXXXXXXXXXXXXX -WhatIf
```

### Describe

| Cmdlet | Description |
| :--- | :--- |
| `Describe-SalesforceObjects` | List Objects for a target org. |
| `Describe-SalesforceObject` | Describe a specific Object (supports tooling API). |
| `Describe-SalesforceFields` | List fields for an Object. |
| `Describe-SalesforceMetadataTypes` | List available metadata types. |

### Utilities

| Cmdlet | Description |
| :--- | :--- |
| `Build-SalesforceQuery` | Build a SELECT for all fields on an Object. |

### psfdx-development

Included in the `psfdx` package.

### Projects & Config

| Cmdlet | Description |
| :--- | :--- |
| `New-SalesforceProject` | Create a new Salesforce project. |
| `Set-SalesforceTargetOrg` | Set default Target Org (project or global). |
| `Get-SalesforceTargetOrg` | Get default Target Org (project or global). |
| `Remove-SalesforceTargetOrg` | Unset default Target Org (project or global). |
| `Set-SalesforceTargetDevHub` | Set default Dev Hub (project or global). |
| `Get-SalesforceTargetDevHub` | Get default Dev Hub (project or global). |
| `Remove-SalesforceTargetDevHub` | Unset default Dev Hub (project or global). |
| `Get-SalesforceConfig` | Get all Salesforce Config values per project or global. |
### Scratch Orgs

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforceScratchOrgs` | List scratch orgs. |
| `New-SalesforceScratchOrg` | Create scratch org. `-Async` returns before the org is ready. |
| `Resume-SalesforceScratchOrg` | Resume a scratch org creation by `-JobId` (2SR...) or `-UseMostRecent`. Returns the org with `Completed`. Assign permission sets afterwards with `Grant-SalesforcePermissionSet`. |
| `New-SalesforceScratchOrg` | Create scratch org. |
| `Invoke-SalesforceCodeAnalyzer` | Run Code Analyzer (`sf code-analyzer run`) over `-Workspace` and `-Target` with `-RuleSelector`, `-ConfigFile` and `-SeverityThreshold`. Returns findings as objects. A threshold failure is returned (`ThresholdExceeded`) rather than thrown, unless `-ThrowOnThreshold`; a plugin or engine failure always throws. |
| `Get-SalesforceCodeAnalyzerRule` | List the rules a selector matches (`sf code-analyzer rules`). |
| `Remove-SalesforceScratchOrg` | Delete a scratch org (asks for confirmation, supports `-WhatIf`). |
| `Remove-SalesforceScratchOrgs` | Delete all scratch orgs found; one confirmation lists every org (asks for confirmation, supports `-WhatIf`). |

### Apex Testing & Automation

| Cmdlet | Description |
| :--- | :--- |
| `Test-SalesforceApex` | Run Apex tests and wait for the result in one call. |
| `Start-SalesforceApexTest` | Start an Apex test run without waiting and return its `TestRunId` (`sf apex run test`). |
| `Get-SalesforceApexTestResult` | Get a run's structured results by `-TestRunId`: summary, per-test outcome and run time, optional coverage (`sf apex get test`). |
| `Wait-SalesforceApexTest` | Poll a run until it finishes or `-TimeoutMinutes` pass. |
| `Get-SalesforceCodeCoverage` | Compute coverage per class/test method. |
| `Test-SalesforceFlow` | Run Flow tests (`sf flow run test`). Asynchronous by default, returning a `TestRunId`; `-Synchronous` waits for results. Failed tests and a command that could not run are different errors. |
| `Get-SalesforceFlowTestResult` | Get the results of a Flow test run by `-TestRunId` (`sf flow get test`). |
| `Test-SalesforceLogic` | Run Flow and Apex tests together (`sf logic run test`, beta in the CLI), by class, test, suite or `-TestCategory`. |
| `Get-SalesforceLogicTestResult` | Get the results of a combined Flow and Apex test run by `-TestRunId` (`sf logic get test`). |
| `Invoke-SalesforceApex` | Execute Apex from a file. |
| `Watch-SalesforceApex` | On-save deploy and test Apex. |
| `Get-SalesforceApexClass` | Get Apex Class details from Org. |

### Apex Scaffolding

| Cmdlet | Description |
| :--- | :--- |
| `New-SalesforceApexClass` | Generate an Apex class from a template. |
| `New-SalesforceApexTrigger` | Generate an Apex trigger from a template. |

### LWC Dev Server

| Cmdlet | Description |
| :--- | :--- |
| `Install-SalesforceLwcDevServer` | Install the `@salesforce/plugin-lightning-dev` CLI plugin. |
| `Start-SalesforceLwcDevServer` | Start Lightning dev (`sf lightning dev app`, `component` or `site` via `-Mode`; optional `-Name`, `-DeviceType`, `-TargetOrg`). Fails with install guidance if the plugin is missing. |

### LWC/Jest Testing

| Cmdlet | Description |
| :--- | :--- |
| `Install-SalesforceJest` | Add `@salesforce/sfdx-lwc-jest` via yarn/npm. |
| `New-SalesforceJestTest` | Scaffold a Jest test in the LWC's `__tests__` folder (`-ProjectPath`, `-Force`). |
| `Test-SalesforceJest` | Run Jest tests. |
| `Debug-SalesforceJest` | Run Jest in debug mode. |
| `Watch-SalesforceJest` | Run Jest in watch mode. |

### psfdx-sandbox

Included in the `psfdx` package.

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforceSandboxes` | List sandboxes that belong to the production org. |
| `New-SalesforceSandbox` | Request creation of a sandbox using a definition file or license type. |
| `Get-SalesforceSandboxRefreshStatus` | Show the most recent refresh details and next eligible refresh date for a sandbox. |
| `Copy-SalesforceSandbox` | Clone an existing sandbox into a new sandbox. |
| `Resume-SalesforceSandbox` | Resume a pending or paused sandbox copy. |
| `Remove-SalesforceSandbox` | Delete a sandbox from the production org, optionally specifying the target org (asks for confirmation, supports `-WhatIf`). |

### psfdx-agentforce

Included in the `psfdx` package.

Needs the Salesforce CLI agent plugin (`@salesforce/plugin-agent`, bundled with recent CLI versions; otherwise `sf plugins install @salesforce/plugin-agent`). Each cmdlet stops with install guidance if it is missing. Beta and developer-preview commands (authoring bundles, preview, agent creation) are not wrapped. See [docs/agentforce-parity.md](docs/agentforce-parity.md).

| Cmdlet | Description |
| :--- | :--- |
| `Test-SalesforceAgentPlugin` | Check that the agent CLI plugin is installed. |
| `Get-SalesforceAgentTests` | List agent test definitions in the org. |
| `Start-SalesforceAgentTest` | Run an agent test by `-ApiName`; optional `-WaitMinutes`. Returns the job or results. |
| `Get-SalesforceAgentTestResult` | Get the results of an agent test run by `-JobId`. |
| `Enable-SalesforceAgent` | Activate an agent by `-ApiName` (optional `-Version`); asks for confirmation, supports `-WhatIf`. |
| `Disable-SalesforceAgent` | Deactivate an agent by `-ApiName`; asks for confirmation, supports `-WhatIf`. |
| `New-SalesforceAgentAuthoringBundle` | Generate an Agent Script authoring bundle (`sf agent generate authoring-bundle`) from `-Spec` (or a blank one with `-NoSpec`; `-Name` is required); asks for confirmation, supports `-WhatIf`. |
| `Test-SalesforceAgentAuthoringBundle` | Validate a bundle by `-ApiName`. Returns `Valid` and `Diagnostics` (message, line, column); `-ThrowOnInvalid` fails a CI step. |
| `Publish-SalesforceAgentAuthoringBundle` | Publish a bundle to the org as an agent; asks for confirmation, supports `-WhatIf`. The authoring commands are newer upstream (possibly beta) and need a recent `@salesforce/plugin-agent`. |

### psfdx-logs

Included in the `psfdx` package.

### Debug Logs

| Cmdlet | Description |
| :--- | :--- |
| `Watch-SalesforceDebugLogs` | Watch for latest Debug logs. |
| `Select-SalesforceDebugLogs` | List Debug logs. |
| `Get-SalesforceDebugLogs` | Get most recent or specific Debug log. |
| `Export-SalesforceDebugLogs` | Export Debug logs to files. |
| `Convert-SalesforceDebugLog` | Parse Debug log. |

### Debug Logging

| Cmdlet | Description |
| :--- | :--- |
| `Enable-SalesforceDebugLogging` | Turn on debug logging for a user, Apex class or trigger by creating a trace flag. Name it with `-Username`, `-ApexClass` or `-ApexTrigger`, or pass `-TracedEntityId` (debug level, log type, duration in minutes). |
| `Get-SalesforceDebugLogging` | List trace flags with their debug level, traced entity and Active/Expired status. |
| `Disable-SalesforceDebugLogging` | Turn off debug logging early by deleting a trace flag (accepts pipeline input from `Get-SalesforceDebugLogging`; supports `-WhatIf`). |

### Flows

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforceFlowInterviews` | Query FlowInterview by status and start time. |

### Logins

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforceLoginHistory` | Query LoginHistory with optional username/time filters. |
| `Get-SalesforceLoginFailures` | Filter LoginHistory results to failed statuses. |

### Event Monitoring

| Cmdlet | Description |
| :--- | :--- |
| `Select-SalesforceEventFiles` | Query EventLogFile records and return objects. |
| `Export-SalesforceEventFiles` | Query EventLogFile and export results to CSV. |
| `Get-SalesforceEventFile` | Download a single EventLogFile by Id and return CSV content. |
| `Export-SalesforceEventFile` | Download a single EventLogFile by Id and write `<Id>.csv`. |

### Utilities

| Cmdlet | Description |
| :--- | :--- |
| `Out-Notepad` | Convenience helper to open a temp file (Windows). |

### psfdx-packages

Included in the `psfdx` package.

### Packages

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforcePackages` | List packages in a Dev Hub. |
| `Get-SalesforcePackage` | Get a specific package by name. |
| `New-SalesforcePackage` | Create a package (managed/unlocked, org-dependent, path, description, no-namespace). |
| `Remove-SalesforcePackage` | Delete a package by name (asks for confirmation, supports `-WhatIf`). |
| `Get-SalesforcePackagesInstalled` | List installed packages in a target org (supports API version override). |

### Package Versions

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforcePackageVersions` | List versions (filters: released/concise/verbose). |
| `New-SalesforcePackageVersion` | Create a new package version (coverage, tag, def file, waits, key). |
| `Promote-SalesforcePackageVersion` | Promote a version (optional no-prompt). |
| `Remove-SalesforcePackageVersion` | Delete a version (optional no-prompt; asks for confirmation, supports `-WhatIf`). |
| `Install-SalesforcePackageVersion` | Install a version to a target org (waits/publish-wait, no-prompt). `-AsObject` returns the install request, whose `Id` (0Hf...) goes to `Get-SalesforcePackageInstallStatus`. |
| `Get-SalesforcePackageVersionCreateStatus` | Get a package version create request's status, IDs and errors by the `Id` (08c...) that `New-SalesforcePackageVersion` returned (`sf package version create report`). |
| `Get-SalesforcePackageInstallStatus` | Get a package install request's status and errors by its `-RequestId` (`sf package install report`). |

### psfdx-shared

| Cmdlet | Description |
| :--- | :--- |
| `Invoke-Salesforce` | Internal executor. Runs `sf` (and `npm`/`yarn`) with an argument array, never through `Invoke-Expression`; secret values are masked in `-Verbose` output. |
