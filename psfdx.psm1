Import-Module ./salesforce-username.ps1 -Force

function Invoke-Sfdx {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Command)
    Write-Verbose $Command
    return Invoke-Expression -Command $Command
}

function Show-SfdxResult {
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
        [Parameter(Mandatory = $false)][string] $DefaultUsername,
        [Parameter(Mandatory = $false)][string] $DefaultAlias,
        [Parameter(Mandatory = $false)][string] $DefaultDevhubUsername,
        [Parameter(Mandatory = $false)][string] $OAuthClientId
    )

    $command = "sfdx force:auth:web:login"
    if ($IsSandbox -eq $true) {
        $command += " --instanceurl https://test.salesforce.com"
    }

    if ($DefaultUsername) {
        $command += " --setdefaultusername $DefaultUsername"
    }
    if ($DefaultAlias) {
        $command += " --setalias $DefaultAlias"
    }
    if ($OAuthClientId) {
        $command += " --clientid $OAuthClientId"
    }
    if ($DefaultDevhubUsername) {
        $command += " --setdefaultdevhubusername $DefaultDevhubUsername"
    }
    $command += " --json"
    $result = Invoke-Sfdx -Command $command
    Show-SfdxResult -Result $result
}

function Disconnect-Salesforce {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $All,
        [Parameter(Mandatory = $false)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $command = "sfdx force:auth:logout"
    if ($All) {
        $command += " --all"
    }
    elseif ($Username) {
        $command += " --targetusername $Username"
    }
    else {
        throw "Please provide either -Username or -All"
    }
    if ($NoPrompt) {
        $command += " --noprompt"
    }
    $command += " --json"
    $result = Invoke-Sfdx -Command $command
    Show-SfdxResult -Result $result
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

    $command = "sfdx force:auth:jwt:grant --clientid $ConsumerKey --username $Username --jwtkeyfile $JwtKeyfile --instanceurl $url "
    if ($SetDefaultUsername) {
        $command += "--setdefaultusername "
    }
    $command += "--json"

    $result = Invoke-Sfdx -Command $command
    return Show-SfdxResult -Result $result
}

function Open-Salesforce {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $UrlOnly
    )
    $command = "sfdx force:org:open"
    $Username = Get-SalesforceUser -Username $Username
    if ($Username) {
        $command += " --targetusername $Username"
    }
    if ($UrlOnly) {
        $command += " --urlonly"
    }
    Invoke-Sfdx -Command $command
}

function Get-SalesforceConnections {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $ShowVerboseDetails
    )
    $command = "sf org list"
    if ($ShowVerboseDetails) {
        $command += " --verbose"
    }
    $command += " --json"
    $result = Invoke-Sfdx -Command $command

    $result = $result | ConvertFrom-Json
    $result = $result.result.nonScratchOrgs # Exclude Scratch Orgs
    $result = $result | Select-Object orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias
    return $result
}

function Clean-SalesforceConnections {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][switch] $NoPrompt)
    $command = "sf org list --clean"
    if ($NoPrompt) {
        $command += " --no-prompt"
    }
    Invoke-Sfdx -Command $command
}

function Get-SalesforceAlias {
    [CmdletBinding()]
    $result = Invoke-Sfdx -Command "sfdx force:alias:list --json"
    return Show-SfdxResult -Result $result
}

function Add-SalesforceAlias {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Alias,
        [Parameter(Mandatory = $true)][string] $Username
    )
    Invoke-Sfdx -Command "sfdx force:alias:set $Alias=$Username"
}

function Remove-SalesforceAlias {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Alias)
    Invoke-Sfdx -Command "sfdx force:alias:set $Alias="
}

function Get-SalesforceLimits {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)
    $result = Invoke-Sfdx -Command "sfdx force:limits:api:display --targetusername $Username --json"
    return Show-SfdxResult -Result $result
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
        [Parameter(Mandatory = $true)][string] $Query,
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    $command = "sfdx force:data:soql:query --query `"$Query`""
    if ($UseToolingApi) {
        $command += " --usetoolingapi"
    }
    $command += " --targetusername $Username"
    $command += " --json"
    Write-Verbose ("Query: " + $Query)
    Write-Verbose $command
    $result = Invoke-Expression -Command $command | ConvertFrom-Json
    if ($result.status -ne 0) {
        $result
        throw $result.message
    }
    return $result.result.records
}

function New-SalesforceObject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true)][string] $FieldUpdates,
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $UseToolkingApi
    )
    Write-Verbose $FieldUpdates
    $command = "sfdx force:data:record:create"
    $command += " --sobjecttype $Type"
    $command += " --values `"$FieldUpdates`""
    if ($UseToolkingApi) {
        $command += " --usetoolingapi"
    }
    $command += " --targetusername $Username"
    $command += " --json"
    return Invoke-Sfdx -Command $command
}

function Set-SalesforceObject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Id,
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true)][string] $FieldUpdates,
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $UseToolkingApi
    )
    Write-Verbose $FieldUpdates
    $command = "sfdx force:data:record:update"
    $command += " --sobjecttype $Type"
    $command += " --sobjectid $Id"
    $command += " --values `"$FieldUpdates`""
    if ($UseToolkingApi) {
        $command += " --usetoolkingapi"
    }
    $command += " --targetusername $Username"
    $command += " --json"
    return Invoke-Sfdx -Command $command
}

function Get-SalesforceRecordType {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectType,
        [Parameter(Mandatory = $true)][string] $Username
    )
    $query = "SELECT Id, SobjectType, Name, DeveloperName, IsActive, IsPersonType"
    $query += " FROM RecordType"
    if ($ObjectType) {
        $query += " WHERE SobjectType = '$ObjectType'"
    }
    $results = Select-SalesforceObjects -Query $query -Username $Username
    return $results | Select-Object Id, SobjectType, Name, DeveloperName, IsActive, IsPersonType
}

function Invoke-SalesforceApexFile {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ApexFile,
        [Parameter(Mandatory = $true)][string] $Username
    )
    $result = Invoke-Sfdx -Command "sfdx force:apex:execute -f $ApexFile --targetusername $Username --json"
    return Show-SfdxResult -Result $result
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
    if ($IsSandbox) {
        $loginUrl = "https://test.salesforce.com/services/oauth2/token"
    }

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
    $command = "sfdx plugins:install $Name"
    Invoke-Sfdx -Command $command
}

function Get-SalesforcePlugins {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $IncludeCore
    )
    $command = "sfdx plugins"
    if ($IncludeCore) {
        $command += " --core"
    }
    Invoke-Sfdx -Command $command
}

function Update-SalesforcePlugins {
    [CmdletBinding()]
    Param()
    Invoke-Sfdx -Command "sfdx plugins:update"
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