![PSFDX](images/psfdx-logo.png)
[![CI](https://github.com/tonygward/psfdx/actions/workflows/ci.yml/badge.svg)](https://github.com/tonygward/psfdx/actions/workflows/ci.yml)
Cross platform PowerShell modules that wrap the Salesforce CLI.

# Pre-Requisites
1. Salesforce SFDX
https://developer.salesforce.com/tools/sfdxcli

2. PowerShell for Windows or Linux
https://github.com/PowerShell/PowerShell/releases

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

**2. Create and use a Salesforce Alias**
```
Add-SalesforceAlias -TargetOrg my@email.com -Alias myalias
Select-SalesforceRecords -Query "SELECT Id,Name FROM Account LIMIT 10" -TargetOrg myalias
```
**3. Retrieve first 10 Salesforce Accounts**
```
Select-SalesforceRecords -Query "SELECT Id,Name FROM Account LIMIT 10" -TargetOrg my@email.com
```
NB you only need to Import-Module psfdx once per PowerShell session

**4. Export Salesforce Debug Logs to Files**
```
Import-Module psfdx-logs
Export-SalesforceDebugLogs -TargetOrg my@email.com
```

**5. List every cmdlet**
```
Get-Command -Module psfdx*
```

## Modules
| Module | Description |
| :--- | :--- |
| `psfdx` | Core cmdlets for authentication, record operations, org management, and utilities. |
| `psfdx-logs` | Debug Logs, Login History and Event Monitoring. |
| `psfdx-metadata` | Retrieve, deploy and describe Salesforce metadata. |
| `psfdx-development` | Salesforce DX development (projects, scratch orgs, tests, deploy). |
| `psfdx-sandbox` | Salesforce sandbox lifecycle management. |
| `psfdx-packages` | Salesforce packages: create, version, promote, install. |


### psfdx

`Import-Module psfdx`

### Authentication & Orgs

| Cmdlet | Description |
| :--- | :--- |
| `Connect-Salesforce` | Web-based org authentication. |
| `Disconnect-Salesforce` | Logout from orgs. |
| `Connect-SalesforceJwt` | JWT-based authentication. |
| `Open-Salesforce` | Open org in a browser or get URL. |
| `Get-SalesforceConnections` | List connected orgs (non-scratch by default). |
| `Repair-SalesforceConnections` | Clean up stale connections. |

### Aliases

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforceAlias` | List configured aliases. |
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
| `New-SalesforceRecord` | Create a record. |
| `Set-SalesforceRecord` | Update a record. |
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
| `Install-SalesforcePlugin` | Install an `sf` plugin. |
| `Get-SalesforcePlugins` | List installed plugins (optionally core). |
| `Update-SalesforcePlugins` | Update installed plugins. |

### Utilities

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforceDateTime` | Format current/custom datetime in Salesforce sortable UTC. |


### psfdx-metadata

`Import-Module psfdx-metadata`

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

### Describe

| Cmdlet | Description |
| :--- | :--- |
| `Describe-SalesforceObjects` | List sObjects for a target org. |
| `Describe-SalesforceObject` | Describe a specific sObject (supports tooling API). |
| `Describe-SalesforceFields` | List fields for an sObject. |
| `Describe-SalesforceMetadataTypes` | List available metadata types. |

### Utilities

| Cmdlet | Description |
| :--- | :--- |
| `Build-SalesforceQuery` | Build a SELECT for all fields on an sObject. |

### psfdx-development

`Import-Module psfdx-development`

### Projects & Config

| Cmdlet | Description |
| :--- | :--- |
| `New-SalesforceProject` | Create a new SFDX project. |
| `Set-SalesforceTargetOrg` | Write `.sfdx/sfdx-config.json` default username. |
| `Get-SalesforceTargetOrg` | Read project default username. |
| `Get-SalesforceProjectUser` | Read project default username (current folder). |
| `Set-SalesforceProjectUser` | Set `target-org` for the project. |
| `New-SalesforceProjectAndScratchOrg` | Scaffold project and create scratch org. |
| `Get-SalesforceConfig` | Show SFDX config (JSON). |
| `Set-SalesforceDefaultDevHub` | Set default Dev Hub (`--global`). |
| `Remove-SalesforceDefaultDevHub` | Unset default Dev Hub. |

### Scratch Orgs

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforceScratchOrgs` | List scratch orgs (optionally last-used). |
| `New-SalesforceScratchOrg` | Create scratch org (wait/duration/def file). |
| `Remove-SalesforceScratchOrg` | Delete a scratch org. |
| `Remove-SalesforceScratchOrgs` | Delete all scratch orgs found. |

### Apex Testing & Automation

| Cmdlet | Description |
| :--- | :--- |
| `Test-SalesforceApex` | Run Apex tests (sync/async, coverage, output dir). |
| `Get-SalesforceCodeCoverage` | Compute coverage per class/test method. |
| `Invoke-SalesforceApex` | Execute Apex from a file. |
| `Watch-SalesforceApex` | On-save deploy/test Apex from a project. |
| `Get-SalesforceApexClass` | Lookup ApexClass by name (tooling API SOQL). |

### Apex Scaffolding

| Cmdlet | Description |
| :--- | :--- |
| `New-SalesforceApexClass` | Generate an Apex class from a template. |
| `New-SalesforceApexTrigger` | Generate an Apex trigger from a template. |

### LWC Dev Server

| Cmdlet | Description |
| :--- | :--- |
| `Install-SalesforceLwcDevServer` | Install LWC dev server dependencies. |
| `Start-SalesforceLwcDevServer` | Start LWC dev server. |

### LWC/Jest Testing

| Cmdlet | Description |
| :--- | :--- |
| `Install-SalesforceJest` | Add `@salesforce/sfdx-lwc-jest` via yarn/npm. |
| `New-SalesforceJestTest` | Create Jest test for an LWC. |
| `Test-SalesforceJest` | Run Jest tests. |
| `Debug-SalesforceJest` | Run Jest in debug mode. |
| `Watch-SalesforceJest` | Run Jest in watch mode. |

### psfdx-sandbox

`Import-Module psfdx-sandbox`

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforceSandboxes` | List sandboxes that belong to the production org. |
| `New-SalesforceSandbox` | Request creation of a sandbox using a definition file or license type. |
| `Get-SalesforceSandboxRefreshStatus` | Show the most recent refresh details and next eligible refresh date for a sandbox. |
| `Copy-SalesforceSandbox` | Clone an existing sandbox into a new sandbox. |
| `Resume-SalesforceSandbox` | Resume a pending or paused sandbox copy. |
| `Remove-SalesforceSandbox` | Delete a sandbox from the production org, optionally specifying the target org. |

### psfdx-logs

`Import-Module psfdx-logs`

### Debug Logs

| Cmdlet | Description |
| :--- | :--- |
| `Watch-SalesforceDebugLogs` | Watch for latest Debug logs. |
| `Select-SalesforceDebugLogs` | List Debug logs. |
| `Get-SalesforceDebugLogs` | Get most recent or specific Debug log. |
| `Export-SalesforceDebugLogs` | Export Debug logs to files. |
| `Convert-SalesforceDebugLog` | Parse Debug log. |

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

`Import-Module psfdx-packages`

### Packages

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforcePackages` | List packages in a Dev Hub. |
| `Get-SalesforcePackage` | Get a specific package by name. |
| `New-SalesforcePackage` | Create a package (managed/unlocked, org-dependent, path, description, no-namespace). |
| `Remove-SalesforcePackage` | Delete a package by name. |

### Package Versions

| Cmdlet | Description |
| :--- | :--- |
| `Get-SalesforcePackageVersions` | List versions (filters: released/concise/verbose). |
| `New-SalesforcePackageVersion` | Create a new package version (coverage, tag, def file, waits, key). |
| `Promote-SalesforcePackageVersion` | Promote a version (optional no-prompt). |
| `Remove-SalesforcePackageVersion` | Delete a version (optional no-prompt). |
| `Install-SalesforcePackageVersion` | Install a version to a target org (waits/publish-wait, no-prompt). |
