# psfdx
[![CI](https://github.com/tonygward/psfdx/actions/workflows/ci.yml/badge.svg)](https://github.com/tonygward/psfdx/actions/workflows/ci.yml)
PowerShell module that wraps Salesforce SFDX command line interface
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
## Authentication & Connection Management
* `Connect-Salesforce` - Web-based org authentication
* `Disconnect-Salesforce` - Logout from orgs
* `Connect-SalesforceJwt` - JWT-based authentication
* `Get-SalesforceConnections` - List connected orgs
* `Repair-SalesforceConnections` - Clean up stale connections
### Record Operations
* `Select-SalesforceRecords` - SOQL queries with flexible output formats
* `New-SalesforceObject` - Create records
* `Set-SalesforceObject` - Update records
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
Plugin management functions

## Breaking Changes
- All cmdlets now use `-TargetOrg` instead of `-Username` to specify the org (username or alias). Update scripts accordingly.
