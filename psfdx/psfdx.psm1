. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Invoke-Salesforce.ps1')
. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Show-SalesforceResult.ps1')

#region Authentication & Orgs

function Connect-Salesforce {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Sandbox,
        [Parameter(Mandatory = $false)][string] $CustomUrl,

        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][switch] $SetDefaultDevHub,

        [Parameter(Mandatory = $false)][string][ValidateSet('chrome', 'edge', 'firefox')] $Browser,
        [Parameter(Mandatory = $false)][string] $OAuthClientId
    )

    $command = "sf org login web"
    if ($Sandbox) { $command += " --instance-url https://test.salesforce.com" }
    if ($CustomUrl) { $command += " --instance-url $CustomUrl" }

    if ($Alias) { $command += " --alias $Alias" }
    if ($SetDefault) { $command += " --set-default" }
    if ($SetDefaultDevHub) { $command += " --set-default-dev-hub" }

    if ($Browser) { $command += " --browser $Browser" }
    if ($OAuthClientId) { $command += " --client-id $OAuthClientId" }

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

        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][switch] $SetDefaultDevHub
    )
    if (-not(Test-Path $JwtKeyfile)) {
        throw "File does not exist: $JwtKeyfile"
    }

    $url = "https://login.salesforce.com"
    if ($Sandbox) { $url = "https://test.salesforce.com" }

    $command = "sf org login jwt --client-id $ConsumerKey --username $TargetOrg --jwt-key-file `"$JwtKeyfile`" --instance-url $url"
    if ($Alias) { $command += " --alias $Alias" }
    if ($SetDefault) { $command += " --set-default" }
    if ($SetDefaultDevHub) { $command += " --set-default-dev-hub" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Open-Salesforce {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UrlOnly,
        [Parameter(Mandatory = $false)][string][ValidateSet('chrome', 'edge', 'firefox')] $Browser,
        [Parameter(Mandatory = $false)][string] $BrowserPrivateMode
    )
    $command = "sf org open"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    if ($Browser) { $command += " --browser $Browser" }
    if ($BrowserPrivateMode) { $command += " --private $BrowserPrivateMode" }
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

#endregion

#region Aliases & Limits

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

#endregion

#region Limits & Usage

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

#endregion

#region Data Management

function Select-SalesforceRecords {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Query,
        [Parameter(Mandatory = $false)][string] $File,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi,
        [Parameter(Mandatory = $false)][switch] $IncludeDeletedRows,
        [Parameter(Mandatory = $false)][string][ValidateSet('human', 'json', 'csv')] $ResultFormat = 'json',
        [Parameter(Mandatory = $false)][string] $OutputFile
    )
    $command = "sf data query"
    if ($Query) { $command += " --query `"$Query`"" }
    if ($File) { $command += " --file `"$File`"" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) {
        $command += " --target-org `"$($TargetOrg.Trim())`""
    }
    if ($UseToolingApi) { $command += " --use-tooling-api" }
    if ($IncludeDeletedRows) { $command += " --all-rows" }

    $command += " --result-format $ResultFormat"
    if ($OutputFile) { $command += " --output-file $OutputFile" }

    $result = Invoke-Salesforce -Command $command | ConvertFrom-Json
    if ($result.status -ne 0) {
        $result
        throw $result.message
    }
    # Exclude Salesforce's built-in 'attributes' metadata from each row
    return ($result.result.records | Select-Object -ExcludeProperty attributes)
}

function Get-SalesforceUsers {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $ActiveOnly,
        [Parameter(Mandatory = $false)][int] $Limit = 200,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $fields = 'Id, Name, Username, Email, IsActive, LastLoginDate'
    $query = "SELECT $fields FROM User"
    $filters = @()
    if ($ActiveOnly) { $filters += 'IsActive = true' }
    if ($Username)   { $filters += "Username = '$Username'" }
    if ($filters.Count -gt 0) { $query += ' WHERE ' + ($filters -join ' AND ') }
    $query += ' ORDER BY LastLoginDate DESC'
    $query += " LIMIT $Limit"

    return Select-SalesforceRecords -Query $query -TargetOrg $TargetOrg -ResultFormat json
}

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
    $query = "SELECT Id, SobjectType, Name, DeveloperName, IsActive"
    $query += " FROM RecordType"
    if ($ObjectType) { $query += " WHERE SobjectType = '$ObjectType'" }
    return Select-SalesforceRecords -Query $query -TargetOrg $TargetOrg
}

#endregion

#region Salesforce REST API

function Connect-SalesforceApi {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $TargetOrg,
        [Parameter(Mandatory = $true)][string] $Password,
        [Parameter(Mandatory = $true)][string] $Token,
        [Parameter(Mandatory = $true)][string] $ClientId,
        [Parameter(Mandatory = $true)][string] $ClientSecret,
        [Parameter(Mandatory = $false)][switch] $Sandbox,
        [Parameter(Mandatory = $false)][string] $CustomUrl
    )

    $loginUrl = "https://login.salesforce.com/services/oauth2/token"
    if ($Sandbox) { $loginUrl = "https://test.salesforce.com/services/oauth2/token" }
    if ($CustomUrl) { $loginUrl = "$CustomUrl/services/oauth2/token" }

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

function Get-SalesforceApiVersions {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $command = "sf api request rest /services/data"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    $result = Invoke-Salesforce -Command $command
    return $result | ConvertFrom-Json
}

function Get-SalesforceLatestApiVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $versions = Get-SalesforceApiVersions -TargetOrg $TargetOrg
    if ($versions.Count -eq 0) { return $null }
    $latest = $versions | Sort-Object -Property version -Descending | Select-Object
    $version = $latest[0].version
    return "v$version"
}

#endregion

#region Plugins

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

#endregion

#region Utilities

function Get-SalesforceDateTime {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][datetime] $Datetime)
    if ($null -eq $Datetime) { $Datetime = Get-Date }
    return $Datetime.ToString('s') + 'Z'
}

#endregion