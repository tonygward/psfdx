# psfdx
[![CI](https://github.com/tonygward/psfdx/actions/workflows/ci.yml/badge.svg)](https://github.com/tonygward/psfdx/actions/workflows/ci.yml)
PowerShell modules that wrap the Salesforce SFDX command line interface.

## Modules
| Module | Description |
| --- | --- |
| `psfdx` | Core cmdlets for authentication, record operations, org management, and utilities. |
| `psfdx-development` | Helpers for Salesforce DX development workflows (projects, scratch orgs, tests, deploy). |
| `psfdx-logs` | Tools for working with Salesforce DX Apex logs. |
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

Uses Salesforce SFDX's standard authentication, credentials are encrypted and stored locally.

Other psfdx commands require a target org (username or alias).

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

## Cmdlet Reference
### Authentication & Connection Management
* `Connect-Salesforce` - Web-based org authentication
* `Disconnect-Salesforce` - Logout from orgs
* `Connect-SalesforceJwt` - JWT-based authentication
* `Get-SalesforceConnections` - List connected orgs
* `Repair-SalesforceConnections` - Clean up stale connections
### Record Operations
* `Select-SalesforceRecords` - SOQL queries with flexible output formats
* `New-SalesforceRecord` - Create records
* `Set-SalesforceRecord` - Update records
* `Get-SalesforceRecordType` - Retrieve record type metadata
### Org Management
* `Open-Salesforce` - Open org in browser
* `Get-SalesforceLimits` - API and storage limits
* `Get-SalesforceDataStorage` - Data storage usage analysis
* `Get-SalesforceApiUsage` - API usage tracking
### Utilities
* `Add-SalesforceAlias` / `Remove-SalesforceAlias` -  Alias management
* `Invoke-SalesforceApexFile` - Execute Apex code
* `Connect-SalesforceApi` / `Invoke-SalesforceApi` - Direct REST API access

### Development
* `New-SalesforceProject` - Scaffold a new SFDX project
* `Get-SalesforceScratchOrgs` - List existing scratch orgs
* `New-SalesforceScratchOrg` - Create a new scratch org
* `Set-SalesforceDefaultDevHub` - Set the default Dev Hub
* `Install-SalesforceLwcDevServer` - Install the LWC development server

### Logs
* `Watch-SalesforceLogs` - Stream Apex logs in real time
* `Get-SalesforceLogs` - Retrieve available logs
* `Export-SalesforceLogs` - Save logs to disk
* `Convert-SalesforceLog` - Convert logs to a readable format

### Metadata
* `Retrieve-SalesforceOrg` - Pull metadata from an org
* `Retrieve-SalesforceComponent` - Retrieve a specific component
* `Deploy-SalesforceComponent` - Deploy metadata to an org
* `Describe-SalesforceObject` - Inspect object metadata
* `Get-SalesforceMetaTypes` - List available metadata types

### Packages
* `Get-SalesforcePackages` - List packages in the org
* `New-SalesforcePackage` - Create a package
* `New-SalesforcePackageVersion` - Create a package version
* `Promote-SalesforcePackageVersion` - Promote a package version
* `Install-SalesforcePackageVersion` - Install a package version

## Breaking Changes
- All cmdlets now use `-TargetOrg` instead of `-Username` to specify the org (username or alias). Update scripts accordingly.
