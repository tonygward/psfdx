# psfdx
PowerShell module that wraps Salesforce SFDX command line interface
# Pre-Requisites
You must install Salesforce SFDX
https://developer.salesforce.com/tools/sfdxcli

# Installation
```
git clone https://github.com/tonygward/psfdx
cd psfdx
.\Install-psfdx.ps1
```
# Examples
**1. Connect to a Salesforce Sandbox Org**
```
Import-Module psfdx
Connect-Salesforce -IsSandbox
```
A web browser will appear, login to Salesforce as you would normally.

Uses Salesforce SFDX's standard authentication, credentials are encrypted and stored locally.

Other psfdx commands require a username, typically email address or alias.

**2. Retrieve first 10 Salesforce Accounts**
```
Import-Module psfdx
Select-SalesforceObjects -Query "SELECT Id,Name FROM Account LIMIT 10" -Username my@email.com
```
NB you only need to Import-Module psfdx once per PowerShell session

**3. Create and use a Salesforce Alias**
```
Add-SalesforceAlias -Username my@email.com -Alias myalias
Select-SalesforceObjects -Query "SELECT Id,Name FROM Account LIMIT 10" -Username myalias
```

**4. Retrieve every psfdx cmdlet**
```
Get-Command -Module psfdx
```

**5. Get Last Salesforce Debug Log and Open in Notepad**
```
Get-SalesforceLog -Last -Username my@email.com | Out-Notepad
```