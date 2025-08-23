function Invoke-Sf {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Command)
    Write-Verbose $Command
    return Invoke-Expression -Command $Command
}

function Show-SfResult {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][psobject] $Result)
    $result = $Result | ConvertFrom-Json
    if ($result.status -ne 0) {
        Write-Debug $result
        throw ($result.message)
    }
    return $result.result
}

function Get-SalesforceDateTime {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][datetime] $Datetime)
    if ($null -eq $Datetime) { $Datetime = Get-Date }
    return $Datetime.ToString('s') + 'Z'
}

function Connect-Salesforce {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $IsSandbox,
        [Parameter(Mandatory = $false)][string] $CustomUrl,
        [Parameter(Mandatory = $false)][string] $DefaultDevhubUsername,
        [Parameter(Mandatory = $false)][string] $OAuthClientId
    )

    $command = "sf org login web"
    if ($IsSandbox -eq $true) { $command += " --instance-url https://test.salesforce.com" }
    if ($CustomUrl) { $command += " --instance-url $CustomUrl" }
    if ($OAuthClientId) { $command += " --client-id $OAuthClientId" }
    if ($DefaultDevhubUsername) { $command += " --set-default-dev-hub $DefaultDevhubUsername" }
    $command += " --json"
    $result = Invoke-Sf -Command $command
    Show-SfResult -Result $result
}

function Disconnect-Salesforce {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $All,
        [Parameter(Mandatory = $false)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $command = "sf org logout"
    if ($All) { $command += " --all" }
    elseif ($Username) { $command += " --target-org $Username" }
    else { throw "Please provide either -Username or -All" }

    if ($NoPrompt) { $command += " --no-prompt" }
    $command += " --json"
    $result = Invoke-Sf -Command $command
    Show-SfResult -Result $result
}

function Grant-SalesforceJWT {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ConsumerKey,
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $true)][string] $JwtKeyfile,
        [Parameter(Mandatory = $false)][switch] $IsSandbox,
        [Parameter(Mandatory = $false)][switch] $SetDefaultUsername
    )
    if (-not(Test-Path $JwtKeyfile)) {
        throw "File does not exist: $JwtKeyfile"
    }

    $url = "https://login.salesforce.com/"
    if ($IsSandbox) { $url = "https://test.salesforce.com" }

    $command = "sf org login jwt --client-id $ConsumerKey --username $Username --jwt-key-file $JwtKeyfile --instance-url $url"
    if ($SetDefaultUsername) { $command += " --set-default" }
    $command += " --json"

    $result = Invoke-Sf -Command $command
    return Show-SfResult -Result $result
}

function Open-Salesforce {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $UrlOnly,
        [Parameter(Mandatory = $false)][string][ValidateSet('chrome', 'edge', 'firefox')] $Browser
    )
    $command = "sf org open"
    if ($Username) { $command += " --target-org $Username" }
    if ($Browser) { $command += " --browser $Browser" }
    if ($UrlOnly) { $command += " --url-only" }
    Invoke-Sf -Command $command
}

function Get-SalesforceConnections {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $ShowVerboseDetails
    )
    $command = "sf org list"
    if ($ShowVerboseDetails) { $command += " --verbose" }
    $command += " --json"
    $result = Invoke-Sf -Command $command

    $result = $result | ConvertFrom-Json
    $result = $result.result.nonScratchOrgs # Exclude Scratch Orgs
    $result = $result | Select-Object orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias
    return $result
}

function Clean-SalesforceConnections {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][switch] $NoPrompt)
    $command = "sf org list --clean"
    if ($NoPrompt) { $command += " --no-prompt" }
    Invoke-Sf -Command $command
}

function Get-SalesforceAlias {
    [CmdletBinding()]
    $result = Invoke-Sf -Command "sf alias list --json"
    return Show-SfResult -Result $result
}

function Add-SalesforceAlias {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Alias,
        [Parameter(Mandatory = $true)][string] $Username
    )
    Invoke-Sf -Command "sf alias set $Alias $Username"
}

function Remove-SalesforceAlias {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Alias)
    Invoke-Sf -Command " sf alias unset $Alias"
}

function Get-SalesforceLimits {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)
    $result = Invoke-Sf -Command "sf limits api display --target-org $Username --json"
    return Show-SfResult -Result $result
}

function Get-SalesforceDataStorage {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)
    $values = Get-SalesforceLimits -Username $Username | Where-Object Name -eq "DataStorageMB"
    $values | Add-Member -NotePropertyName InUse -NotePropertyValue ($values.max + ($values.remaining * -1))
    $values | Add-Member -NotePropertyName Usage -NotePropertyValue (($values.max + ($values.remaining * -1)) / $values.max).ToString('P')
    return $values
}

function Get-SalesforceApiUsage {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)
    $values = Get-SalesforceLimits -Username $Username | Where-Object Name -eq "DailyApiRequests"
    $values | Add-Member -NotePropertyName Usage -NotePropertyValue (($values.max + ($values.remaining * -1)) / $values.max).ToString('P')
    return $values
}

function Select-SalesforceObjects {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Query,
        [Parameter(Mandatory = $false)][string] $File,
        [Parameter(Mandatory = $false)][string] $Username,
        [Parameter(Mandatory = $false)][string][ValidateSet('human', 'json', 'csv')] $ResultFormat = 'json',
        [Parameter(Mandatory = $false)][switch] $UseBulkApi,
        [Parameter(Mandatory = $false)][switch] $UseBulkApiAsync,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    $command = "sf data query"
    if ($Query) { $command += " --query `"$Query`""}
    if ($File) { $command += " --file $File"}
    if ($Username) { $command += " --target-org $Username" }
    if ($UseBulkApi) { $command += " --bulk" }
    if ($UseBulkApi) { $command += " --async" }
    if ($UseToolingApi) { $command += " --use-tooling-api" }
    $command += " --result-format $ResultFormat"
    Write-Verbose ("Query: " + $Query)
    Write-Verbose $command
    $result = Invoke-Expression -Command $command | ConvertFrom-Json
    if ($result.status -ne 0) {
        $result
        throw $result.message
    }
    return $result.result.records
}

<#
.SYNOPSIS
Creates a new Salesforce record.
.PARAMETER Type
The sObject type to create.
.PARAMETER FieldUpdates
Comma-separated field=value pairs for the new record.
.PARAMETER Username
Target org username or alias.
.PARAMETER UseToolingApi
Use the Salesforce Tooling API for the request.
.EXAMPLE
New-SalesforceObject -Type Account -FieldUpdates 'Name=Acme' -Username me@example.com -UseToolingApi
#>
function New-SalesforceObject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true)][string] $FieldUpdates,
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    Write-Verbose $FieldUpdates
    $command = "sf data create record"
    $command += " --sobject $Type"
    $command += " --values `"$FieldUpdates`""
    if ($UseToolingApi) { $command += " --use-tooling-api" }
    $command += " --target-org $Username"
    $command += " --json"
    return Invoke-Sf -Command $command
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
.PARAMETER Username
Target org username or alias.
.PARAMETER UseToolingApi
Use the Salesforce Tooling API for the request.
.EXAMPLE
Set-SalesforceObject -Id 001xx000003DGbV -Type Account -FieldUpdates 'Name=Updated' -Username me@example.com -UseToolingApi
#>
function Set-SalesforceObject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Id,
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true)][string] $FieldUpdates,
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    Write-Verbose $FieldUpdates
    $command = "sf data update record"
    $command += " --sobject $Type"
    $command += " --record-id $Id"
    $command += " --values `"$FieldUpdates`""
    if ($UseToolingApi) { $command += " --use-tooling-api" }
    $command += " --target-org $Username"
    $command += " --json"
    return Invoke-Sf -Command $command
}

function Get-SalesforceRecordType {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectType,
        [Parameter(Mandatory = $true)][string] $Username
    )
    $query = "SELECT Id, SobjectType, Name, DeveloperName, IsActive, IsPersonType"
    $query += " FROM RecordType"
    if ($ObjectType) { $query += " WHERE SobjectType = '$ObjectType'" }
    $results = Select-SalesforceObjects -Query $query -Username $Username
    return $results | Select-Object Id, SobjectType, Name, DeveloperName, IsActive, IsPersonType
}

function Invoke-SalesforceApexFile {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ApexFile,
        [Parameter(Mandatory = $true)][string] $Username
    )
    $result = Invoke-Sf -Command "sf apex run --file $ApexFile --target-org $Username --json"
    return Show-SfResult -Result $result
}

function Login-SalesforceApi {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $true)][string] $Password,
        [Parameter(Mandatory = $true)][string] $Token,
        [Parameter(Mandatory = $true)][string] $ClientId,
        [Parameter(Mandatory = $true)][string] $ClientSecret,
        [Parameter(Mandatory = $false)][switch] $IsSandbox
    )

    $loginUrl = "https://login.salesforce.com/services/oauth2/token"
    if ($IsSandbox) { $loginUrl = "https://test.salesforce.com/services/oauth2/token" }

    return Invoke-RestMethod -Uri $loginUrl `
        -Method Post `
        -Body @{
        grant_type    = "password"
        client_id     = "$ClientId"
        client_secret = "$ClientSecret"
        username      = "$Username"
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
    return Invoke-RestMethod -Uri $Url -Method $Method -Headers @{Authorization = "OAuth " + $AccessToken }
}

function Install-SalesforcePlugin {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name
    )
    $command = "sf plugins install $Name"
    Invoke-Sf -Command $command
}

function Get-SalesforcePlugins {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $IncludeCore
    )
    $command = "sf plugins"
    if ($IncludeCore) { $command += " --core" }
    Invoke-Sf -Command $command
}

function Update-SalesforcePlugins {
    [CmdletBinding()]
    Param()
    Invoke-Sf -Command "sf plugins update"
}

Export-ModuleMember Get-SalesforceDateTime
Export-ModuleMember Connect-Salesforce
Export-ModuleMember Disconnect-Salesforce
Export-ModuleMember Grant-SalesforceJWT
Export-ModuleMember Open-Salesforce
Export-ModuleMember Get-SalesforceConnections
Export-ModuleMember Clean-SalesforceConnections

Export-ModuleMember Get-SalesforceAlias
Export-ModuleMember Add-SalesforceAlias
Export-ModuleMember Remove-SalesforceAlias

Export-ModuleMember Get-SalesforceLimits
Export-ModuleMember Get-SalesforceDataStorage
Export-ModuleMember Get-SalesforceApiUsage

Export-ModuleMember Select-SalesforceObjects

Export-ModuleMember New-SalesforceObject
Export-ModuleMember Set-SalesforceObject
Export-ModuleMember Get-SalesforceRecordType

Export-ModuleMember Invoke-SalesforceApexFile

Export-ModuleMember Login-SalesforceApi
Export-ModuleMember Invoke-SalesforceApi

Export-ModuleMember Install-SalesforcePlugin
Export-ModuleMember Get-SalesforcePlugins
Export-ModuleMember Update-SalesforcePlugins