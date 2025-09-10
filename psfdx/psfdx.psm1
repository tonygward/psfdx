. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Invoke-Salesforce.ps1')
. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Show-SalesforceResult.ps1')

## Show-SalesforceResult moved to psfdx-shared/Show-SalesforceResult.ps1

function Get-SalesforceDateTime {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][datetime] $Datetime)
    if ($null -eq $Datetime) { $Datetime = Get-Date }
    return $Datetime.ToString('s') + 'Z'
}

function Connect-Salesforce {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Sandbox,
        [Parameter(Mandatory = $false)][string] $CustomUrl,
        [Parameter(Mandatory = $false)][switch] $SetDefaultDevHub,
        [Parameter(Mandatory = $false)][string] $OAuthClientId,
        [Parameter(Mandatory = $false)][string][ValidateSet('chrome', 'edge', 'firefox')] $Browser
    )

    $command = "sf org login web"
    if ($Sandbox) { $command += " --instance-url https://test.salesforce.com" }
    if ($CustomUrl) { $command += " --instance-url $CustomUrl" }
    if ($SetDefaultDevHub) { $command += " --set-default-dev-hub" }
    if ($OAuthClientId) { $command += " --client-id $OAuthClientId" }
    if ($Browser) { $command += " --browser $Browser" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    Show-SalesforceResult -Result $result
}

function Disconnect-Salesforce {
    [CmdletBinding(DefaultParameterSetName = 'TargetOrg')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'All')][switch] $All,
        [Parameter(Mandatory = $true, ParameterSetName = 'TargetOrg')][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $command = "sf org logout"
    if ($PSCmdlet.ParameterSetName -eq 'All') {
        $command += " --all"
    } else {
        $command += " --target-org $TargetOrg"
    }
    if ($NoPrompt) { $command += " --no-prompt" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    Show-SalesforceResult -Result $result
}

function Connect-SalesforceJwt {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ConsumerKey,
        [Parameter(Mandatory = $true)][string] $TargetOrg,
        [Parameter(Mandatory = $true)][string] $JwtKeyfile,
        [Parameter(Mandatory = $false)][switch] $Sandbox,
        [Parameter(Mandatory = $false)][switch] $SetDefaultUsername
    )
    if (-not(Test-Path $JwtKeyfile)) {
        throw "File does not exist: $JwtKeyfile"
    }

    $url = "https://login.salesforce.com"
    if ($Sandbox) { $url = "https://test.salesforce.com" }

    $command = "sf org login jwt --client-id $ConsumerKey --username $TargetOrg --jwt-key-file $JwtKeyfile --instance-url $url"
    if ($SetDefaultUsername) { $command += " --set-default" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Open-Salesforce {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UrlOnly,
        [Parameter(Mandatory = $false)][string][ValidateSet('chrome', 'edge', 'firefox')] $Browser
    )
    $command = "sf org open"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    if ($Browser) { $command += " --browser $Browser" }
    if ($UrlOnly) { $command += " --url-only" }
    Invoke-Salesforce -Command $command
}

function Get-SalesforceConnections {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $ShowVerboseDetails
    )
    $command = "sf org list"
    if ($ShowVerboseDetails) { $command += " --verbose" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command

    $result = $result | ConvertFrom-Json
    $result = $result.result.nonScratchOrgs # Exclude Scratch Orgs
    $result = $result | Select-Object orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias
    return $result
}

function Repair-SalesforceConnections {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][switch] $NoPrompt)
    $command = "sf org list --clean"
    if ($NoPrompt) { $command += " --no-prompt" }
    Invoke-Salesforce -Command $command
}

function Get-SalesforceAlias {
    [CmdletBinding()]
    $command = "sf alias list --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Add-SalesforceAlias {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Alias,
        [Parameter(Mandatory = $true)][string] $TargetOrg
    )
    $command = "sf alias set $Alias=$TargetOrg"
    Invoke-Salesforce -Command $command
}

function Remove-SalesforceAlias {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Alias)
    $command = "sf alias unset $Alias"
    Invoke-Salesforce -Command $command
}

function Get-SalesforceLimits {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $command = "sf limits api display"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDataStorage {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $values = Get-SalesforceLimits -TargetOrg $TargetOrg | Where-Object Name -eq "DataStorageMB"
    $values | Add-Member -NotePropertyName InUse -NotePropertyValue ($values.max + ($values.remaining * -1))
    $values | Add-Member -NotePropertyName Usage -NotePropertyValue (($values.max + ($values.remaining * -1)) / $values.max).ToString('P')
    return $values
}

function Get-SalesforceApiUsage {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $values = Get-SalesforceLimits -TargetOrg $TargetOrg | Where-Object Name -eq "DailyApiRequests"
    $values | Add-Member -NotePropertyName Usage -NotePropertyValue (($values.max + ($values.remaining * -1)) / $values.max).ToString('P')
    return $values
}

function Select-SalesforceRecords {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Query,
        [Parameter(Mandatory = $false)][string] $File,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][string][ValidateSet('human', 'json', 'csv')] $ResultFormat = 'json',
        [Parameter(Mandatory = $false)][switch] $UseToolingApi,
        [Parameter(Mandatory = $false)][switch] $IncludeDeletedRows
    )
    $command = "sf data query"
    if ($Query) { $command += " --query `"$Query`"" }
    if ($File) { $command += " --file $File" }
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    if ($UseToolingApi) { $command += " --use-tooling-api" }
    if ($IncludeDeletedRows) { $command += " --all-rows" }
    $command += " --result-format $ResultFormat"
    Write-Verbose ("Query: " + $Query)
    Write-Verbose $command
    $result = Invoke-Salesforce -Command $command | ConvertFrom-Json
    if ($result.status -ne 0) {
        $result
        throw $result.message
    }
    # Exclude Salesforce's built-in 'attributes' metadata from each row
    return ($result.result.records | Select-Object -ExcludeProperty attributes)
}

<#
.SYNOPSIS
Creates a new Salesforce record.
.PARAMETER Type
The sObject type to create.
.PARAMETER FieldUpdates
Comma-separated field=value pairs for the new record.
.PARAMETER TargetOrg
Target org username or alias.
.PARAMETER UseToolingApi
Use the Salesforce Tooling API for the request.
.EXAMPLE
New-SalesforceRecord -Type Account -FieldUpdates 'Name=Acme' -TargetOrg me@example.com -UseToolingApi
#>
function New-SalesforceRecord {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true)][string] $FieldUpdates,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    Write-Verbose $FieldUpdates
    $command = "sf data create record"
    $command += " --sobject $Type"
    $command += " --values `"$FieldUpdates`""
    if ($UseToolingApi) { $command += " --use-tooling-api" }
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

<#
.SYNOPSIS
Updates an existing Salesforce record.
.PARAMETER Id
The record identifier to update.
.PARAMETER Type
The sObject type of the record.
.PARAMETER FieldUpdates
Comma-separated field=value pairs for the update.
.PARAMETER TargetOrg
Target org username or alias.
.PARAMETER UseToolingApi
Use the Salesforce Tooling API for the request.
.EXAMPLE
Set-SalesforceRecord -Id 001xx000003DGbV -Type Account -FieldUpdates 'Name=Updated' -TargetOrg me@example.com -UseToolingApi
#>
function Set-SalesforceRecord {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Id,
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true)][string] $FieldUpdates,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    Write-Verbose $FieldUpdates
    $command = "sf data update record"
    $command += " --sobject $Type"
    $command += " --record-id $Id"
    $command += " --values `"$FieldUpdates`""
    if ($UseToolingApi) { $command += " --use-tooling-api" }
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceRecordType {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectType,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $query = "SELECT Id, SobjectType, Name, DeveloperName, IsActive, IsPersonType"
    $query += " FROM RecordType"
    if ($ObjectType) { $query += " WHERE SobjectType = '$ObjectType'" }
    $results = Select-SalesforceRecords -Query $query -TargetOrg $TargetOrg
    return $results | Select-Object Id, SobjectType, Name, DeveloperName, IsActive, IsPersonType
}

function Invoke-SalesforceApexFile {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ApexFile,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $command = "sf apex run --file $ApexFile"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Connect-SalesforceApi {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $TargetOrg,
        [Parameter(Mandatory = $true)][string] $Password,
        [Parameter(Mandatory = $true)][string] $Token,
        [Parameter(Mandatory = $true)][string] $ClientId,
        [Parameter(Mandatory = $true)][string] $ClientSecret,
        [Parameter(Mandatory = $false)][switch] $Sandbox
    )

    $loginUrl = "https://login.salesforce.com/services/oauth2/token"
    if ($Sandbox) { $loginUrl = "https://test.salesforce.com/services/oauth2/token" }

    return Invoke-RestMethod -Uri $loginUrl `
        -Method Post `
        -Body @{
        grant_type    = "password"
        client_id     = "$ClientId"
        client_secret = "$ClientSecret"
        username      = "$TargetOrg"
        password      = ($Password + $Token)
    }
}

function Invoke-SalesforceApi {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Url,
        [Parameter(Mandatory = $true)][string] $AccessToken,
        [Parameter(Mandatory = $false)][string][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')] $Method = "GET"
    )
    return Invoke-RestMethod -Uri $Url -Method $Method -Headers @{Authorization = "Bearer " + $AccessToken }
}

function Install-SalesforcePlugin {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name
    )
    $command = "sf plugins install $Name"
    Invoke-Salesforce -Command $command
}

function Get-SalesforcePlugins {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $IncludeCore
    )
    $command = "sf plugins"
    if ($IncludeCore) { $command += " --core" }
    Invoke-Salesforce -Command $command
}

function Update-SalesforcePlugins {
    [CmdletBinding()]
    Param()
    $command = "sf plugins update"
    Invoke-Salesforce -Command $command
}
