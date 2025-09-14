![PSFDX](images/psfdx-logo.png)
[![CI](https://github.com/tonygward/psfdx/actions/workflows/ci.yml/badge.svg)](https://github.com/tonygward/psfdx/actions/workflows/ci.yml)
PowerShell modules that wraps the Salesforce CLI.

## Modules
| Module | Description |
| --- | --- |
| `psfdx` | Core cmdlets for authentication, record operations, org management, and utilities. |
| `psfdx-development` | Helpers for Salesforce DX development workflows (projects, scratch orgs, tests, deploy). |
| `psfdx-logs` | Tools for working with Salesforce Apex logs. |
| `psfdx-metadata` | Commands for retrieving, deploying, and describing Salesforce metadata. |
| `psfdx-packages` | Helpers for managing Salesforce packages: list, create, version, promote, install. |
# Pre-Requisites
You must install Salesforce SFDX
https://developer.salesforce.com/tools/sfdxcli

# Installation

### Linux
```
git clone https://github.com/tonygward/psfdx
cd psfdx
./install-linux.ps1
```

### Windows
```
git clone https://github.com/tonygward/psfdx
cd psfdx
./install-windows.ps1
```

# Examples
**1. Connect to a Salesforce Sandbox Org**
```
Import-Module psfdx
Connect-Salesforce -Sandbox
```
A web browser will appear, login to Salesforce as you would normally.

**-Verbose** switch reveals the underlying Salesfore CLI
![Connect-Salesforce with Verbose](images/connect-verbose.png)

**2. Retrieve first 10 Salesforce Accounts**
```
Import-Module psfdx
Select-SalesforceRecords -Query "SELECT Id,Name FROM Account LIMIT 10" -TargetOrg my@email.com
```
NB you only need to Import-Module psfdx once per PowerShell session

**3. Create and use a Salesforce Alias**
```
Add-SalesforceAlias -TargetOrg my@email.com -Alias myalias
Select-SalesforceRecords -Query "SELECT Id,Name FROM Account LIMIT 10" -TargetOrg myalias
```

**4. Retrieve every psfdx cmdlet**
```
Get-Command -Module psfdx
```

## Cmdlets by Module

### psfdx

`Import-Module psfdx`

| Cmdlet | Category | Description |
| --- | --- | --- |
| `Connect-Salesforce` | Authentication & Orgs | Web-based org authentication. |
| `Disconnect-Salesforce` | Authentication & Orgs | Logout from orgs. |
| `Connect-SalesforceJwt` | Authentication & Orgs | JWT-based authentication. |
| `Open-Salesforce` | Authentication & Orgs | Open org in a browser or get URL. |
| `Get-SalesforceConnections` | Authentication & Orgs | List connected orgs (non-scratch by default). |
| `Repair-SalesforceConnections` | Authentication & Orgs | Clean up stale connections. |
| `Get-SalesforceAlias` | Aliases | List configured aliases. |
| `Add-SalesforceAlias` | Aliases | Create/update an alias. |
| `Remove-SalesforceAlias` | Aliases | Remove an alias. |
| `Get-SalesforceLimits` | Limits & Usage | Retrieve org limits (API, storage, etc.). |
| `Get-SalesforceDataStorage` | Limits & Usage | Calculate data storage usage and percent. |
| `Get-SalesforceApiUsage` | Limits & Usage | Calculate API usage percent. |
| `Select-SalesforceRecords` | Data & SOQL | Run SOQL and return records. |
| `Get-SalesforceUsers` | Data & SOQL | List users with optional filters (username, active only, limit). |
| `New-SalesforceRecord` | Data & SOQL | Create a record. |
| `Set-SalesforceRecord` | Data & SOQL | Update a record. |
| `Get-SalesforceRecordType` | Data & SOQL | List record types (optionally by object). |
| `Connect-SalesforceApi` | REST API | OAuth2 password flow (non-SFDX REST). |
| `Invoke-SalesforceApi` | REST API | Invoke REST API with bearer token. |
| `Install-SalesforcePlugin` | Plugins | Install an `sf` plugin. |
| `Get-SalesforcePlugins` | Plugins | List installed plugins (optionally core). |
| `Update-SalesforcePlugins` | Plugins | Update installed plugins. |
| `Get-SalesforceDateTime` | Utilities | Format current/custom datetime in Salesforce sortable UTC. |

### psfdx-development

`Import-Module psfdx-development`

| Cmdlet | Category | Description |
| --- | --- | --- |
| `New-SalesforceProject` | Projects & Config | Create a new SFDX project. |
| `Set-SalesforceProject` | Projects & Config | Write `.sfdx/sfdx-config.json` default username. |
| `Get-SalesforceDefaultUserName` | Projects & Config | Read project default username. |
| `Get-SalesforceProjectUser` | Projects & Config | Read project default username (current folder). |
| `Set-SalesforceProjectUser` | Projects & Config | Set `target-org` for the project. |
| `New-SalesforceProjectAndScratchOrg` | Projects & Config | Scaffold project and create scratch org. |
| `Get-SalesforceConfig` | Projects & Config | Show SFDX config (JSON). |
| `Set-SalesforceDefaultDevHub` | Projects & Config | Set default Dev Hub (`--global`). |
| `Remove-SalesforceDefaultDevHub` | Projects & Config | Unset default Dev Hub. |
| `Get-SalesforceScratchOrgs` | Scratch Orgs | List scratch orgs (optionally last-used). |
| `New-SalesforceScratchOrg` | Scratch Orgs | Create scratch org (wait/duration/def file). |
| `Remove-SalesforceScratchOrg` | Scratch Orgs | Delete a scratch org. |
| `Remove-SalesforceScratchOrgs` | Scratch Orgs | Delete all scratch orgs found. |
| `Test-SalesforceApex` | Apex Testing & Automation | Run Apex tests (sync/async, coverage, output dir). |
| `Get-SalesforceCodeCoverage` | Apex Testing & Automation | Compute coverage per class/test method. |
| `Invoke-SalesforceApex` | Apex Testing & Automation | Execute Apex from a file. |
| `Watch-SalesforceApex` | Apex Testing & Automation | On-save deploy/test Apex from a project. |
| `Get-SalesforceApexClass` | Apex Testing & Automation | Lookup ApexClass by name (tooling API SOQL). |
| `New-SalesforceApexClass` | Apex Scaffolding | Generate an Apex class from a template. |
| `New-SalesforceApexTrigger` | Apex Scaffolding | Generate an Apex trigger from a template. |
| `Install-SalesforceLwcDevServer` | LWC Dev Server | Install LWC dev server dependencies. |
| `Start-SalesforceLwcDevServer` | LWC Dev Server | Start LWC dev server. |
| `Install-SalesforceJest` | LWC/Jest Testing | Add `@salesforce/sfdx-lwc-jest` via yarn/npm. |
| `New-SalesforceJestTest` | LWC/Jest Testing | Create Jest test for an LWC. |
| `Test-SalesforceJest` | LWC/Jest Testing | Run Jest tests. |
| `Debug-SalesforceJest` | LWC/Jest Testing | Run Jest in debug mode. |
| `Watch-SalesforceJest` | LWC/Jest Testing | Run Jest in watch mode. |

### psfdx-logs

`Import-Module psfdx-logs`

| Cmdlet | Category | Description |
| --- | --- | --- |
| `Watch-SalesforceDebugLogs` | Debug Logs | Tail Apex logs (color, debug level, skip trace flag). |
| `Get-SalesforceDebugLogs` | Debug Logs | List Apex logs (JSON). |
| `Get-SalesforceDebugLog` | Debug Logs | Get a specific or most recent log text. |
| `Export-SalesforceDebugLogs` | Debug Logs | Export logs to files. |
| `Convert-SalesforceDebugLog` | Debug Logs | Parse pipe-delimited logs into objects. |
| `Get-SalesforceFlowInterviews` | Flows | Query FlowInterview by status and start time. |
| `Get-SalesforceLoginHistory` | Logins | Query LoginHistory with optional username/time filters. |
| `Get-SalesforceLoginFailures` | Logins | Filter LoginHistory results to failed statuses. |
| `Select-SalesforceEventFiles` | Events | Query EventLogFile records and return objects. |
| `Export-SalesforceEventFiles` | Events | Query EventLogFile and export results to CSV. |
| `Get-SalesforceEventFile` | Events | Download a single EventLogFile by Id and return CSV content. |
| `Export-SalesforceEventFile` | Events | Download a single EventLogFile by Id and write `<Id>.csv`. |
| `Out-Notepad` | Utilities | Convenience helper to open a temp file (Windows). |

### psfdx-metadata

`Import-Module psfdx-metadata`

| Cmdlet | Category | Description |
| --- | --- | --- |
| `Retrieve-SalesforceComponent` | Retrieve | Retrieve specific metadata component by type/name. |
| `Retrieve-SalesforceField` | Retrieve | Retrieve a specific custom field. |
| `Retrieve-SalesforceValidationRule` | Retrieve | Retrieve a specific validation rule. |
| `Retrieve-SalesforceOrg` | Retrieve | Retrieve entire Salesforce Org. |
| `Deploy-SalesforceComponent` | Deploy | Deploy specific metadata by type/name. |
| `Describe-SalesforceObjects` | Describe | List sObjects (all/custom/standard). |
| `Describe-SalesforceObject` | Describe | Describe a specific sObject (supports tooling API). |
| `Describe-SalesforceFields` | Describe | List fields for an sObject. |
| `Get-SalesforceMetaTypes` | Types & Helpers | List available metadata types. |
| `Build-SalesforceQuery` | Types & Helpers | Build a SELECT for all fields on an sObject. |

### psfdx-packages

`Import-Module psfdx-packages`

| Cmdlet | Category | Description |
| --- | --- | --- |
| `Get-SalesforcePackages` | Packages | List packages in a Dev Hub. |
| `Get-SalesforcePackage` | Packages | Get a specific package by name. |
| `New-SalesforcePackage` | Packages | Create a package (managed/unlocked, org-dependent, path, description, no-namespace). |
| `Remove-SalesforcePackage` | Packages | Delete a package by name. |
| `Get-SalesforcePackageVersions` | Package Versions | List versions (filters: released/concise/verbose). |
| `New-SalesforcePackageVersion` | Package Versions | Create a new package version (coverage, tag, def file, waits, key). |
| `Promote-SalesforcePackageVersion` | Package Versions | Promote a version (optional no-prompt). |
| `Remove-SalesforcePackageVersion` | Package Versions | Delete a version (optional no-prompt). |
| `Install-SalesforcePackageVersion` | Package Versions | Install a version to a target org (waits/publish-wait, no-prompt). |
