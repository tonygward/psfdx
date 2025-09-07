function Invoke-Sf {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Arguments)
    Write-Verbose $Arguments
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "sf"
    $psi.Arguments = $Arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0 -and $stderr) {
        Write-Debug $stderr
    }
    return $stdout
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
        [Parameter(Mandatory = $false)][switch] $Sandbox,
        [Parameter(Mandatory = $false)][string] $CustomUrl,
        [Parameter(Mandatory = $false)][switch] $SetDefaultDevHub,
        [Parameter(Mandatory = $false)][string] $OAuthClientId,
        [Parameter(Mandatory = $false)][string][ValidateSet('chrome', 'edge', 'firefox')] $Browser
    )

    $arguments = "org login web"
    if ($Sandbox) { $arguments += " --instance-url https://test.salesforce.com" }
    if ($CustomUrl) { $arguments += " --instance-url $CustomUrl" }
    if ($SetDefaultDevHub) { $arguments += " --set-default-dev-hub" }
    if ($OAuthClientId) { $arguments += " --client-id $OAuthClientId" }
    if ($Browser) { $arguments += " --browser $Browser" }
    $arguments += " --json"
    $result = Invoke-Sf -Arguments $arguments
    Show-SfResult -Result $result
}

function Disconnect-Salesforce {
    [CmdletBinding(DefaultParameterSetName = 'TargetOrg')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'All')][switch] $All,
        [Parameter(Mandatory = $true, ParameterSetName = 'TargetOrg')][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $arguments = "org logout"
    if ($PSCmdlet.ParameterSetName -eq 'All') {
        $arguments += " --all"
    }
    else {
        $arguments += " --target-org $TargetOrg"
    }
    if ($NoPrompt) { $arguments += " --no-prompt" }
    $arguments += " --json"
    $result = Invoke-Sf -Arguments $arguments
    Show-SfResult -Result $result
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

    $arguments = "org login jwt --client-id $ConsumerKey --username $TargetOrg --jwt-key-file $JwtKeyfile --instance-url $url"
    if ($SetDefaultUsername) { $arguments += " --set-default" }
    $arguments += " --json"

    $result = Invoke-Sf -Arguments $arguments
    return Show-SfResult -Result $result
}

function Open-Salesforce {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UrlOnly,
        [Parameter(Mandatory = $false)][string][ValidateSet('chrome', 'edge', 'firefox')] $Browser
    )
    $arguments = "org open"
    if ($TargetOrg) { $arguments += " --target-org $TargetOrg" }
    if ($Browser) { $arguments += " --browser $Browser" }
    if ($UrlOnly) { $arguments += " --url-only" }
    Invoke-Sf -Arguments $arguments
}

function Get-SalesforceConnections {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $ShowVerboseDetails
    )
    $arguments = "org list"
    if ($ShowVerboseDetails) { $arguments += " --verbose" }
    $arguments += " --json"
    $result = Invoke-Sf -Arguments $arguments

    $result = $result | ConvertFrom-Json
    $result = $result.result.nonScratchOrgs # Exclude Scratch Orgs
    $result = $result | Select-Object orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias
    return $result
}

function Repair-SalesforceConnections {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][switch] $NoPrompt)
    $arguments = "org list --clean"
    if ($NoPrompt) { $arguments += " --no-prompt" }
    Invoke-Sf -Arguments $arguments
}

function Get-SalesforceAlias {
    [CmdletBinding()]
    $result = Invoke-Sf -Arguments "alias list --json"
    return Show-SfResult -Result $result
}

function Add-SalesforceAlias {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Alias,
        [Parameter(Mandatory = $true)][string] $TargetOrg
    )
    Invoke-Sf -Arguments "alias set $Alias=$TargetOrg"
}

function Remove-SalesforceAlias {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Alias)
    Invoke-Sf -Arguments "alias unset $Alias"
}

function Get-SalesforceLimits {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $arguments = "limits api display"
    if ($TargetOrg) { $arguments += " --target-org $TargetOrg" }
    $arguments += " --json"
    $result = Invoke-Sf -Arguments $arguments
    return Show-SfResult -Result $result
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
    $arguments = "data query"
    if ($Query) { $arguments += " --query `"$Query`"" }
    if ($File) { $arguments += " --file $File" }
    if ($TargetOrg) { $arguments += " --target-org $TargetOrg" }
    if ($UseToolingApi) { $arguments += " --use-tooling-api" }
    if ($IncludeDeletedRows) { $arguments += " --all-rows" }
    $arguments += " --result-format $ResultFormat"
    Write-Verbose ("Query: " + $Query)
    Write-Verbose $arguments
    $result = Invoke-Sf -Arguments $arguments | ConvertFrom-Json
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
.PARAMETER TargetOrg
Target org username or alias.
.PARAMETER UseToolingApi
Use the Salesforce Tooling API for the request.
.EXAMPLE
New-SalesforceObject -Type Account -FieldUpdates 'Name=Acme' -TargetOrg me@example.com -UseToolingApi
#>
function New-SalesforceObject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true)][string] $FieldUpdates,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    Write-Verbose $FieldUpdates
    $arguments = "data create record"
    $arguments += " --sobject $Type"
    $arguments += " --values `"$FieldUpdates`""
    if ($UseToolingApi) { $arguments += " --use-tooling-api" }
    if ($TargetOrg) { $arguments += " --target-org $TargetOrg" }
    $arguments += " --json"
    $result = Invoke-Sf -Arguments $arguments
    return Show-SfResult -Result $result
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
Set-SalesforceObject -Id 001xx000003DGbV -Type Account -FieldUpdates 'Name=Updated' -TargetOrg me@example.com -UseToolingApi
#>
function Set-SalesforceObject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Id,
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true)][string] $FieldUpdates,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    Write-Verbose $FieldUpdates
    $arguments = "data update record"
    $arguments += " --sobject $Type"
    $arguments += " --record-id $Id"
    $arguments += " --values `"$FieldUpdates`""
    if ($UseToolingApi) { $arguments += " --use-tooling-api" }
    if ($TargetOrg) { $arguments += " --target-org $TargetOrg" }
    $arguments += " --json"
    $result = Invoke-Sf -Arguments $arguments
    return Show-SfResult -Result $result
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
    $arguments = "apex run --file $ApexFile"
    if ($TargetOrg) { $arguments += " --target-org $TargetOrg" }
    $arguments += " --json"
    $result = Invoke-Sf -Arguments $arguments
    return Show-SfResult -Result $result
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
    $arguments = "plugins install $Name"
    Invoke-Sf -Arguments $arguments
}

function Get-SalesforcePlugins {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $IncludeCore
    )
    $arguments = "plugins"
    if ($IncludeCore) { $arguments += " --core" }
    Invoke-Sf -Arguments $arguments
}

function Update-SalesforcePlugins {
    [CmdletBinding()]
    Param()
    Invoke-Sf -Arguments "plugins update"
}

Export-ModuleMember Get-SalesforceDateTime
Export-ModuleMember Connect-Salesforce
Export-ModuleMember Disconnect-Salesforce
Export-ModuleMember Connect-SalesforceJwt
Export-ModuleMember Open-Salesforce
Export-ModuleMember Get-SalesforceConnections
Export-ModuleMember Repair-SalesforceConnections

Export-ModuleMember Get-SalesforceAlias
Export-ModuleMember Add-SalesforceAlias
Export-ModuleMember Remove-SalesforceAlias

Export-ModuleMember Get-SalesforceLimits
Export-ModuleMember Get-SalesforceDataStorage
Export-ModuleMember Get-SalesforceApiUsage

Export-ModuleMember Select-SalesforceRecords

Export-ModuleMember New-SalesforceObject
Export-ModuleMember Set-SalesforceObject
Export-ModuleMember Get-SalesforceRecordType

Export-ModuleMember Invoke-SalesforceApexFile

Export-ModuleMember Connect-SalesforceApi
Export-ModuleMember Invoke-SalesforceApi

Export-ModuleMember Install-SalesforcePlugin
Export-ModuleMember Get-SalesforcePlugins
Export-ModuleMember Update-SalesforcePlugins
