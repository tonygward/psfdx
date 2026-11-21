function Import-PsfdxSharedModule {
    # Loads psfdx-shared for the module this copy sits in. Keep every copy identical.
    #
    # Contract: the modules release in lockstep, so psfdx-shared must have the same Major.Minor as the importing module and
    # a version no lower than it. A newer patch is fine; an older one, or a different minor, is not.
    #
    # Resolution is deterministic. Versions are compared as [version], never as text.
    #   1. A loaded copy that is compatible (the highest one) is used as it is.
    #   2. Otherwise the first tier that has a compatible copy wins, and the highest version within the tier:
    #      the sibling folder (source checkout, zip install, flat install, Gallery bundle), then sibling version
    #      folders (<Modules>/psfdx-shared/<version>), then PSModulePath.
    #   3. A loaded copy that is not compatible is removed and replaced. If nothing compatible exists the
    #      function throws and says what it found; it never carries on with the wrong version.
    [CmdletBinding()]
    param(
        [string] $ModuleName = 'psfdx-shared',
        [string] $ModuleRoot = $PSScriptRoot,
        [version] $OwnVersion
    )

    $readVersion = {
        param([string] $Manifest)
        try { return [version](Import-PowerShellDataFile -LiteralPath $Manifest).ModuleVersion } catch { return $null }
    }

    # The module's own version comes from its manifest next to this file: the module's version is not set yet while its .psm1 loads.
    if ((-not $PSBoundParameters.ContainsKey('OwnVersion')) -and $PSCommandPath) {
        $ownManifest = [System.IO.Path]::ChangeExtension($PSCommandPath, '.psd1')
        if (Test-Path -LiteralPath $ownManifest) { $OwnVersion = & $readVersion $ownManifest }
    }
    $versionKnown = ($null -ne $OwnVersion) -and ($OwnVersion -gt [version]'0.0')
    $isCompatible = {
        param([version] $Version)
        if (-not $versionKnown) { return $true }
        return (($Version.Major -eq $OwnVersion.Major) -and ($Version.Minor -eq $OwnVersion.Minor) -and ($Version -ge $OwnVersion))
    }

    $loaded = @(Get-Module -Name $ModuleName -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending)
    $loadedCompatible = @($loaded | Where-Object { & $isCompatible $_.Version }) | Select-Object -First 1
    if ($loadedCompatible) {
        Import-Module -ModuleInfo $loadedCompatible -ErrorAction Stop
        return
    }

    $found = @()

    # Tier 1: the sibling folder.
    $tier = @()
    $parent = Split-Path -Path $ModuleRoot -Parent
    if ($parent) {
        $manifest = Join-Path -Path $parent -ChildPath (Join-Path $ModuleName "$ModuleName.psd1")
        if (Test-Path -LiteralPath $manifest) {
            $version = & $readVersion $manifest
            if ($version) { $tier += [pscustomobject]@{ Path = $manifest; Version = $version } }
        }
    }
    $found += , $tier

    # Tier 2: sibling version folders. Only when this module itself sits in a version folder (<Modules>/<name>/<version>).
    $tier = @()
    $ownLeaf = [version] '0.0'
    if ($parent -and [version]::TryParse((Split-Path -Path $ModuleRoot -Leaf), [ref] $ownLeaf)) {
        $modulesRoot = Split-Path -Path $parent -Parent
        if ($modulesRoot) {
            $sharedBase = Join-Path -Path $modulesRoot -ChildPath $ModuleName
            if (Test-Path -LiteralPath $sharedBase) {
                foreach ($dir in @(Get-ChildItem -LiteralPath $sharedBase -Directory -ErrorAction SilentlyContinue)) {
                    $dirVersion = [version] '0.0'
                    if (-not [version]::TryParse($dir.Name, [ref] $dirVersion)) { continue }
                    $manifest = Join-Path -Path $dir.FullName -ChildPath "$ModuleName.psd1"
                    if (Test-Path -LiteralPath $manifest) {
                        $version = & $readVersion $manifest
                        if ($version) { $tier += [pscustomobject]@{ Path = $manifest; Version = $version } }
                    }
                }
            }
        }
    }
    $found += , $tier

    # Tier 3: PSModulePath.
    $tier = @()
    foreach ($item in @(Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue)) {
        if ($item.Path) { $tier += [pscustomobject]@{ Path = $item.Path; Version = $item.Version } }
    }
    $found += , $tier

    foreach ($tier in $found) {
        $match = @($tier | Where-Object { & $isCompatible $_.Version } | Sort-Object -Property Version -Descending) | Select-Object -First 1
        if ($match) {
            # Remove the stale copies first: -Force alone would leave two modules of the same name loaded.
            foreach ($stale in $loaded) { Remove-Module -ModuleInfo $stale -Force -ErrorAction SilentlyContinue }
            Import-Module -Name $match.Path -ErrorAction Stop
            return
        }
    }

    $needs = "$ModuleName $($OwnVersion.Major).$($OwnVersion.Minor).x, version $OwnVersion or newer"
    $message = "Cannot load $ModuleName for module version ${OwnVersion}: it needs $needs."
    $seen = @($loaded | ForEach-Object { "$($_.Version) (loaded)" }) + @($found | ForEach-Object { $_ } | ForEach-Object { "$($_.Version) ($($_.Path))" })
    if ($seen.Count -gt 0) {
        $message += " Found only: $($seen -join '; ')."
    } else {
        $message += " It was not found."
    }
    $message += " Install matching versions of every psfdx module (Install-Module psfdx, or reinstall from the same release)"
    if ($loaded.Count -gt 0) { $message += ", then start a new session or run Remove-Module $ModuleName -Force" }
    throw ($message + '.')
}

Import-PsfdxSharedModule

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

    $arguments = @('org', 'login', 'web')
    if ($Sandbox) { $arguments += @('--instance-url', 'https://test.salesforce.com') }
    if ($CustomUrl) { $arguments += @('--instance-url', $CustomUrl) }

    if ($Alias) { $arguments += @('--alias', $Alias) }
    if ($SetDefault) { $arguments += '--set-default' }
    if ($SetDefaultDevHub) { $arguments += '--set-default-dev-hub' }

    if ($Browser) { $arguments += @('--browser', $Browser) }
    if ($OAuthClientId) { $arguments += @('--client-id', $OAuthClientId) }

    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    Show-SalesforceResult -Result $result
}

function Connect-SalesforceAuthUrl {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $SfdxUrlFile,

        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][switch] $SetDefaultDevHub,
        [Parameter(Mandatory = $false)][switch] $IncludeToken
    )

    if (-not (Test-Path -LiteralPath $SfdxUrlFile)) {
        throw "File does not exist: $SfdxUrlFile"
    }

    $arguments = @('org', 'login', 'sfdx-url', '--sfdx-url-file', $SfdxUrlFile)
    if ($Alias) { $arguments += @('--alias', $Alias) }
    if ($SetDefault) { $arguments += '--set-default' }
    if ($SetDefaultDevHub) { $arguments += '--set-default-dev-hub' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $details = Show-SalesforceResult -Result $result

    # -IncludeToken only passes through what the CLI returned. Current CLI versions do not
    # return tokens or auth URLs from 'sf org login sfdx-url --json', so these may be absent.
    if ($IncludeToken) {
        return $details
    }

    return Remove-SalesforceSensitiveProperty -InputObject $details
}

function Remove-SalesforceSensitiveProperty {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][AllowNull()] $InputObject
    )

    if ($null -eq $InputObject) { return $InputObject }

    $sensitiveKeys = @('accessToken', 'refreshToken', 'sfdxAuthUrl', 'password', 'clientSecret', 'privateKey')
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        return @($InputObject | ForEach-Object {
            if ($_ -is [psobject] -and -not ($_ -is [string])) {
                $_ | Select-Object -Property * -ExcludeProperty $sensitiveKeys
            } else {
                $_
            }
        })
    }

    if ($InputObject -is [psobject] -and -not ($InputObject -is [string])) {
        return $InputObject | Select-Object -Property * -ExcludeProperty $sensitiveKeys
    }

    return $InputObject
}

function Disconnect-Salesforce {
    [CmdletBinding(DefaultParameterSetName = 'TargetOrg', SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'All')][switch] $All,
        [Parameter(Mandatory = $true, ParameterSetName = 'TargetOrg')][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $arguments = @('org', 'logout')
    if ($PSCmdlet.ParameterSetName -eq 'All') {
        $arguments += '--all'
    } else {
        $arguments += @('--target-org', $TargetOrg)
    }
    if ($NoPrompt) { $arguments += '--no-prompt' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $target = if ($PSCmdlet.ParameterSetName -eq 'All') { 'all authenticated orgs' } else { $TargetOrg }
    if ($PSCmdlet.ShouldProcess($target, 'Log out of org')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        Show-SalesforceResult -Result $result
    }
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

    $arguments = @('org', 'login', 'jwt', '--client-id', $ConsumerKey, '--username', $TargetOrg, '--jwt-key-file', $JwtKeyfile, '--instance-url', $url)
    if ($Alias) { $arguments += @('--alias', $Alias) }
    if ($SetDefault) { $arguments += '--set-default' }
    if ($SetDefaultDevHub) { $arguments += '--set-default-dev-hub' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $details = Show-SalesforceResult -Result $result
    return Remove-SalesforceSensitiveProperty -InputObject $details
}

function Open-Salesforce {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UrlOnly,
        [Parameter(Mandatory = $false)][string][ValidateSet('chrome', 'edge', 'firefox')] $Browser,
        [Parameter(Mandatory = $false)][string] $BrowserPrivateMode
    )
    $arguments = @('org', 'open')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($Browser) { $arguments += @('--browser', $Browser) }
    if ($BrowserPrivateMode) { $arguments += @('--private', $BrowserPrivateMode) }
    if ($UrlOnly) { $arguments += '--url-only' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

function Get-SalesforceConnections {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $ShowVerboseDetails
    )
    $arguments = @('org', 'list')
    if ($ShowVerboseDetails) { $arguments += '--verbose' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams

    $details = Show-SalesforceResult -Result $result

    # Exclude scratch orgs. Older CLI versions return 'nonScratchOrgs'; newer ones may only
    # return the 'devHubs', 'sandboxes' and 'other' groups. Absent groups are tolerated.
    $orgs = @()
    if ($null -ne $details) {
        if ($null -ne $details.nonScratchOrgs) {
            $orgs = @($details.nonScratchOrgs)
        } else {
            foreach ($group in @('devHubs', 'sandboxes', 'other')) {
                if ($null -ne $details.$group) { $orgs += @($details.$group) }
            }
        }
    }
    # Only these fields are returned, so tokens and auth URLs are never passed on.
    return $orgs | Select-Object orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias
}

function Repair-SalesforceConnections {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][switch] $NoPrompt)
    $arguments = @('org', 'list', '--clean')
    if ($NoPrompt) { $arguments += '--no-prompt' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

#endregion

#region Aliases & Limits

function Get-SalesforceAlias {
    [CmdletBinding()]
    Param()
    $arguments = @('alias', 'list', '--json')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Add-SalesforceAlias {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Alias,
        [Parameter(Mandatory = $true)][string] $TargetOrg
    )
    $arguments = @('alias', 'set', "$Alias=$TargetOrg")
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

function Remove-SalesforceAlias {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Alias)
    $arguments = @('alias', 'unset', $Alias)
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

#endregion

#region Limits & Usage

function Get-SalesforceLimits {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $arguments = @('limits', 'api', 'display')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDataStorage {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $values = Get-SalesforceLimits -TargetOrg $TargetOrg | Where-Object Name -eq "DataStorageMB"
    if ($null -eq $values) {
        Write-Verbose "No DataStorageMB limit reported for this org"
        return $null
    }
    $inUse = $values.max + ($values.remaining * -1)
    $values | Add-Member -NotePropertyName InUse -NotePropertyValue $inUse
    $values | Add-Member -NotePropertyName Usage -NotePropertyValue (Get-SalesforceUsagePercentage -InUse $inUse -Max $values.max)
    return $values
}

function Get-SalesforceApiUsage {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $values = Get-SalesforceLimits -TargetOrg $TargetOrg | Where-Object Name -eq "DailyApiRequests"
    if ($null -eq $values) {
        Write-Verbose "No DailyApiRequests limit reported for this org"
        return $null
    }
    $inUse = $values.max + ($values.remaining * -1)
    $values | Add-Member -NotePropertyName Usage -NotePropertyValue (Get-SalesforceUsagePercentage -InUse $inUse -Max $values.max)
    return $values
}

function Get-SalesforceUsagePercentage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowNull()][System.Nullable[double]] $InUse,
        [Parameter(Mandatory = $true)][AllowNull()][System.Nullable[double]] $Max
    )
    if ((-not $Max) -or ($Max -eq 0)) { return $null }
    return ($InUse / $Max).ToString('P')
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
    $arguments = @('data', 'query')
    if ($Query) { $arguments += @('--query', $Query) }
    if ($File) { $arguments += @('--file', $File) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) {
        $trimmedTargetOrg = $TargetOrg.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmedTargetOrg)) {
            $arguments += @('--target-org', $trimmedTargetOrg)
        }
    }
    if ($UseToolingApi) { $arguments += '--use-tooling-api' }
    if ($IncludeDeletedRows) { $arguments += '--all-rows' }

    $arguments += @('--result-format', $ResultFormat)
    if ($OutputFile) { $arguments += @('--output-file', $OutputFile) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams

    # csv and human output are not JSON, so hand them back untouched
    if ($ResultFormat -ne 'json') {
        return $result
    }

    $result = $result | ConvertFrom-Json
    if ($result.status -ne 0) {
        Write-Debug ($result | ConvertTo-Json -Depth 10)
        throw $result.message
    }
    # Exclude Salesforce's built-in 'attributes' metadata from each row
    return ($result.result.records | Select-Object -Property * -ExcludeProperty attributes)
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
    if ($Username)   { $filters += ('Username = ' + (ConvertTo-SalesforceSoqlLiteral -Value $Username)) }
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
    $arguments = @('data', 'create', 'record')
    $arguments += @('--sobject', $Type)
    $arguments += @('--values', $FieldUpdates)
    if ($UseToolingApi) { $arguments += '--use-tooling-api' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
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
    $arguments = @('data', 'update', 'record')
    $arguments += @('--sobject', $Type)
    $arguments += @('--record-id', $Id)
    $arguments += @('--values', $FieldUpdates)
    if ($UseToolingApi) { $arguments += '--use-tooling-api' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Upsert-SalesforceRecord {
    # The Salesforce CLI has no `sf data upsert record` (only `sf data upsert bulk`, a CSV job). A single-record upsert is the REST
    # call PATCH /services/data/vXX.X/sobjects/<Type>/<ExternalIdField>/<value>, which `sf api request rest` sends with the org's login.
    # Salesforce answers 201 when it created the record (body has the new Id). When it updated one, API v46.0 and later answer 200 with
    # the Id and created=false, and older versions answer 204 with no body. Id is $null when the response does not carry one.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true)][string] $ExternalIdField,
        [Parameter(Mandatory = $true)][string] $ExternalId,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary] $Fields,
        [Parameter(Mandatory = $false)][string] $ApiVersion,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $objectName = ConvertTo-SalesforceSoqlIdentifier -Value $Type
    $externalIdFieldName = ConvertTo-SalesforceSoqlIdentifier -Value $ExternalIdField
    if ([string]::IsNullOrWhiteSpace($ExternalId)) { throw 'ExternalId is required: an upsert without an external ID value cannot tell a create from an update.' }
    if ($ExternalId -match '[\x00-\x1F\x7F]') { throw 'ExternalId must not contain control characters.' }
    if ($Fields.Count -eq 0) { throw 'Fields is empty: give at least one field to set.' }

    $body = [ordered]@{}
    foreach ($key in $Fields.Keys) {
        $name = ConvertTo-SalesforceSoqlIdentifier -Value ([string] $key)
        if ($name -ieq 'Id') { throw "Fields must not contain Id: an upsert identifies the record by $externalIdFieldName." }
        $value = $Fields[$key]
        if ($value -is [datetime]) { $value = $value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [System.Globalization.CultureInfo]::InvariantCulture) }
        elseif ($value -is [datetimeoffset]) { $value = $value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [System.Globalization.CultureInfo]::InvariantCulture) }
        $body[$name] = $value
    }

    if ([string]::IsNullOrWhiteSpace($ApiVersion)) {
        $latestParams = @{}
        if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $latestParams['TargetOrg'] = $TargetOrg }
        $ApiVersion = Get-SalesforceLatestApiVersion @latestParams
        if ([string]::IsNullOrWhiteSpace($ApiVersion)) { throw 'Could not work out the org API version. Pass -ApiVersion, for example v62.0.' }
    }
    if ($ApiVersion -notmatch '^v?(\d{2,3}\.\d)$') { throw "ApiVersion '$ApiVersion' is not valid. Use a form like v62.0 or 62.0." }
    $version = 'v' + $Matches[1]

    $url = "/services/data/$version/sobjects/$objectName/$externalIdFieldName/" + [uri]::EscapeDataString($ExternalId)

    # The body goes through a file: a JSON body on the command line would carry double quotes, which the Windows .cmd shim rejects.
    $bodyFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ('psfdx-upsert-' + [guid]::NewGuid().ToString('N') + '.json'))
    try {
        [System.IO.File]::WriteAllText($bodyFile, ($body | ConvertTo-Json -Compress -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
        $arguments = @('api', 'request', 'rest', $url, '--method', 'PATCH', '--body', "@$bodyFile")
        if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
        $arguments += '--json'
        $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    } finally {
        Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
    }

    $response = Show-SalesforceResult -Result $result
    $statusCode = 0
    if ($null -ne $response -and $null -ne $response.PSObject.Properties['statusCode']) { $statusCode = [int] $response.statusCode }
    $responseBody = $null
    if ($null -ne $response) { $responseBody = $response.body }

    if ($statusCode -eq 200 -or $statusCode -eq 201 -or $statusCode -eq 204) {
        $created = ($statusCode -eq 201)
        $id = $null
        if ($null -ne $responseBody -and $responseBody -isnot [string]) {
            if ($null -ne $responseBody.PSObject.Properties['id']) { $id = $responseBody.id }
            if ($statusCode -eq 200 -and $null -ne $responseBody.PSObject.Properties['created']) { $created = [bool] $responseBody.created }
        }
        return [pscustomobject]@{
            Operation       = $(if ($created) { 'Created' } else { 'Updated' })
            Created         = $created
            Id              = $id
            Type            = $objectName
            ExternalIdField = $externalIdFieldName
            ExternalId      = $ExternalId
            StatusCode      = $statusCode
        }
    }

    $detail = ''
    if ($responseBody -is [string]) { $detail = $responseBody }
    elseif ($null -ne $responseBody) { $detail = (@($responseBody) | ForEach-Object { if ($_.PSObject.Properties['message']) { "$($_.errorCode): $($_.message)" } else { [string] $_ } }) -join '; ' }
    if ($detail.Length -gt 300) { $detail = $detail.Substring(0, 300) + '...' }
    throw "Upsert of $objectName by $externalIdFieldName failed with HTTP status $statusCode. $detail".TrimEnd()
}

function Get-SalesforceRecordType {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectType,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $query = "SELECT Id, SobjectType, Name, DeveloperName, IsActive"
    $query += " FROM RecordType"
    if ($ObjectType) { $query += (' WHERE SobjectType = ' + (ConvertTo-SalesforceSoqlLiteral -Value $ObjectType)) }
    return Select-SalesforceRecords -Query $query -TargetOrg $TargetOrg
}

#endregion

#region Data Trees

# Wraps `sf data export tree` and `sf data import tree`: copy related records (parent and child) between orgs as JSON files.
# Both use the SObject Tree API, which handles at most 200 records per import and is meant for test data, not bulk loads (see
# Import-SalesforceBulkData for those).

function Export-SalesforceTreeData {
    <#
    .SYNOPSIS
    Exports records, with their related child records, to JSON files for Import-SalesforceTreeData (sf data export tree).
    .DESCRIPTION
    Each -Query is a SOQL query; a query with a subquery exports parent and children together. The queries go to the CLI unchanged, so use
    one line and no double quotes (the Windows CLI shim rejects line breaks and double quotes in an argument).
    Without -Plan the records are returned in Records and the CLI writes one JSON file per query. With -Plan the CLI writes one file per object and
    a plan file that references them, which Import-SalesforceTreeData -Plan reads; Files and PlanFile hold their paths. The CLI creates
    -OutputDirectory if it does not exist.
    .EXAMPLE
    Export-SalesforceTreeData -Query "SELECT Id, Name, (SELECT Id, LastName FROM Contacts) FROM Account WHERE Name LIKE 'Acme%'" -Plan -OutputDirectory .\data -TargetOrg source
    Import-SalesforceTreeData -Plan .\data\Account-Contact-plan.json -TargetOrg scratch
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string[]] $Query,
        [Parameter(Mandatory = $false)][switch] $Plan,
        [Parameter(Mandatory = $false)][string] $Prefix,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $queries = @($Query | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($queries.Count -eq 0) { throw '-Query needs at least one SOQL query.' }
    if ($Prefix -and $Prefix -notmatch '^[A-Za-z0-9_.-]+$') { throw "Prefix '$Prefix' is not valid: use letters, digits, underscore, dot and hyphen only." }
    if ($OutputDirectory -and (Test-Path -LiteralPath $OutputDirectory -PathType Leaf)) { throw "Output directory '$OutputDirectory' is a file." }

    $arguments = @('data', 'export', 'tree')
    foreach ($item in $queries) { $arguments += @('--query', $item) }
    if ($Plan) { $arguments += '--plan' }
    if ($Prefix) { $arguments += @('--prefix', $Prefix) }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceTreeOutput -Output $output -Command 'data export tree'

    $directory = $OutputDirectory
    if (-not $directory) { $directory = (Get-Location).ProviderPath }
    if ($Plan) {
        $entries = @($result)
        $files = @()
        $types = @()
        foreach ($entry in $entries) {
            if ($null -ne $entry.PSObject.Properties['sobject']) { $types += [string] $entry.sobject }
            if ($null -ne $entry.PSObject.Properties['files']) { foreach ($f in @($entry.files)) { $files += (Join-Path -Path $directory -ChildPath ([string] $f)) } }
        }
        # The CLI names the plan file plan.json (no prefix) for several queries, and after the object types (with the prefix) for one.
        if ($queries.Count -gt 1) { $planName = 'plan.json' } else {
            $planName = ($types -join '-') + '-plan.json'
            if ($Prefix) { $planName = "$Prefix-$planName" }
        }
        $planFile = Join-Path -Path $directory -ChildPath $planName
        if (-not (Test-Path -LiteralPath $planFile -PathType Leaf)) { $planFile = $null }
        return [pscustomobject]@{ Plan = $true; OutputDirectory = $directory; PlanFile = $planFile; Files = $files; Records = $null; RecordCount = $null; Result = $entries }
    }
    $records = @()
    if ($null -ne $result -and $null -ne $result.PSObject.Properties['records']) { $records = @($result.records) }
    return [pscustomobject]@{ Plan = $false; OutputDirectory = $directory; PlanFile = $null; Files = @(); Records = $records; RecordCount = $records.Count; Result = $result }
}

function Import-SalesforceTreeData {
    <#
    .SYNOPSIS
    Imports records and their related child records from JSON files into an org (sf data import tree).
    .DESCRIPTION
    Give either -Plan (a plan file from Export-SalesforceTreeData -Plan) or -File (one or more tree JSON files), not both. Asks for confirmation only when
    $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. Returns one object per record created: RefId, Type and Id. If Salesforce
    rejects records, nothing is returned and the cmdlet throws PsfdxTreeImportFailed, whose TargetObject lists each failed reference with its
    StatusCode, Message and Fields. The Tree API imports at most 200 records per call.
    .EXAMPLE
    Import-SalesforceTreeData -Plan .\data\Account-Contact-plan.json -TargetOrg scratch
    .EXAMPLE
    Import-SalesforceTreeData -File .\data\accounts.json, .\data\contacts.json -TargetOrg scratch -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Plan')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Plan')][string] $Plan,
        [Parameter(Mandatory = $true, ParameterSetName = 'Files')][string[]] $File,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('data', 'import', 'tree')
    if ($PSCmdlet.ParameterSetName -eq 'Plan') {
        if (-not (Test-Path -LiteralPath $Plan -PathType Leaf)) { throw "Plan file '$Plan' does not exist." }
        $arguments += @('--plan', $Plan)
        $what = "the plan '$Plan'"
    } else {
        $files = @($File | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($files.Count -eq 0) { throw '-File needs at least one file.' }
        foreach ($item in $files) {
            if ($item.Contains(',')) { throw "File '$item' contains a comma, which the CLI reads as a list separator." }
            if (-not (Test-Path -LiteralPath $item -PathType Leaf)) { throw "File '$item' does not exist." }
        }
        $arguments += @('--files', ($files -join ','))
        $what = "$($files.Count) file(s)"
    }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $orgLabel = 'the default org'
    if (-not [string]::IsNullOrWhiteSpace($TargetOrg)) { $orgLabel = "org $TargetOrg" }
    if (-not $PSCmdlet.ShouldProcess("records from $what in $orgLabel", 'Import tree data')) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceTreeOutput -Output $output -Command 'data import tree'
    return @($result | ForEach-Object { [pscustomobject]@{ RefId = $_.refId; Type = $_.type; Id = $_.id } })
}

function ConvertFrom-SalesforceTreeOutput {
    # Returns the result of a tree command, or throws. A rejected import comes back as an error whose data is the list of failed
    # records; that becomes PsfdxTreeImportFailed with the list as its TargetObject. Any other failure keeps the CLI's message.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][AllowEmptyCollection()] $Output,
        [Parameter(Mandatory = $true)][string] $Command
    )
    $text = [string]::Join([Environment]::NewLine, @($Output | ForEach-Object { [string] $_ })).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { throw "sf $Command returned no output where JSON was expected." }
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop } catch {
        $preview = $text; if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
        throw "sf $Command returned output that is not valid JSON: $preview"
    }
    if ($null -eq $parsed -or $parsed -is [array] -or $null -eq $parsed.PSObject.Properties['status']) { throw "sf $Command returned JSON in an unexpected shape (no status)." }
    if ($parsed.status -eq 0) {
        if ($null -eq $parsed.PSObject.Properties['result']) { throw "sf $Command succeeded but returned no result." }
        return $parsed.result
    }
    if ($null -ne $parsed.PSObject.Properties['data'] -and $null -ne $parsed.data -and $parsed.data -is [array] -and $parsed.data.Count -gt 0) {
        $failed = @($parsed.data | ForEach-Object {
            [pscustomobject]@{ ReferenceId = $_.referenceId; StatusCode = $_.StatusCode; Message = $_.Message; Fields = $_.fields }
        })
        $summary = ($failed | ForEach-Object { "$($_.ReferenceId): $($_.StatusCode) $($_.Message)" }) -join '; '
        if ($summary.Length -gt 400) { $summary = $summary.Substring(0, 400) + '...' }
        $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException "sf $Command failed for $($failed.Count) record(s): $summary"), 'PsfdxTreeImportFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $failed)
        throw $record
    }
    Show-SalesforceResult -Result $text | Out-Null
    throw "sf $Command failed with status $($parsed.status)."
}

#endregion

#region Bulk API 2.0

# Wraps `sf data export|import|update|upsert bulk`, their `resume` commands and `sf data bulk results`. Without -WaitMinutes the CLI
# creates the job and returns at once with a job ID; with it, the CLI polls and returns the counts. Each cmdlet returns a plain object.
#
# A job that finishes with failed rows, or fails or aborts, makes the CLI exit with an error. That error is rethrown as
# PsfdxBulkJobFailed, and its TargetObject holds JobId, State and Message, so a script can fetch the row-level results with
# Get-SalesforceBulkResult. Any other CLI error (no authorisation, a bad file, a bad flag) is thrown with the CLI's message.

function Export-SalesforceBulkData {
    <#
    .SYNOPSIS
    Exports the records of a SOQL query to a file with Bulk API 2.0 (sf data export bulk).
    .DESCRIPTION
    Give the query as -Query or -QueryFile (a file avoids line breaks, which the Windows CLI shim rejects as an argument). The query is
    passed to the CLI unchanged. Without -WaitMinutes the job is created and its JobId returned; finish it later with
    Resume-SalesforceBulkJob -Operation Export. With -WaitMinutes the cmdlet waits and returns TotalSize.
    .EXAMPLE
    Export-SalesforceBulkData -Query 'SELECT Id, Name FROM Account' -OutputFile .\accounts.csv -WaitMinutes 10 -TargetOrg myorg
    .EXAMPLE
    $job = Export-SalesforceBulkData -QueryFile .\big.soql -OutputFile .\big.csv -TargetOrg myorg; Resume-SalesforceBulkJob -Operation Export -JobId $job.JobId
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $OutputFile,
        [Parameter(Mandatory = $false)][string] $Query,
        [Parameter(Mandatory = $false)][string] $QueryFile,
        [Parameter(Mandatory = $false)][ValidateSet('csv', 'json')][string] $ResultFormat = 'csv',
        [Parameter(Mandatory = $false)][switch] $AllRows,
        [Parameter(Mandatory = $false)][ValidateSet('BACKQUOTE', 'CARET', 'COMMA', 'PIPE', 'SEMICOLON', 'TAB')][string] $ColumnDelimiter,
        [Parameter(Mandatory = $false)][ValidateSet('LF', 'CRLF')][string] $LineEnding,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $hasQuery = -not [string]::IsNullOrWhiteSpace($Query)
    $hasQueryFile = -not [string]::IsNullOrWhiteSpace($QueryFile)
    if ($hasQuery -eq $hasQueryFile) { throw 'Give exactly one of -Query and -QueryFile.' }
    if ($hasQueryFile -and -not (Test-Path -LiteralPath $QueryFile -PathType Leaf)) { throw "Query file '$QueryFile' does not exist." }
    $outputParent = Split-Path -Path $OutputFile -Parent
    if ($outputParent -and -not (Test-Path -LiteralPath $outputParent -PathType Container)) { throw "Output directory '$outputParent' does not exist." }

    $arguments = @('data', 'export', 'bulk')
    if ($hasQuery) { $arguments += @('--query', $Query) } else { $arguments += @('--query-file', $QueryFile) }
    $arguments += @('--output-file', $OutputFile, '--result-format', $ResultFormat)
    if ($AllRows) { $arguments += '--all-rows' }
    if ($ColumnDelimiter) { $arguments += @('--column-delimiter', $ColumnDelimiter) }
    if ($LineEnding) { $arguments += @('--line-ending', $LineEnding) }
    if ($WaitMinutes -gt 0) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data export bulk'
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation 'Export'
}

function Import-SalesforceBulkData {
    <#
    .SYNOPSIS
    Inserts the rows of a CSV file with Bulk API 2.0 (sf data import bulk).
    .DESCRIPTION
    Creates records. Asks for confirmation only when $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. Without
    -WaitMinutes the job is created and its JobId returned; with it the cmdlet waits and returns the counts. A job with failed rows
    throws PsfdxBulkJobFailed (see Get-SalesforceBulkResult for the row results).
    .EXAMPLE
    Import-SalesforceBulkData -File '.\new accounts.csv' -Object Account -WaitMinutes 10 -TargetOrg myorg
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $File,
        [Parameter(Mandatory = $true)][string] $Object,
        [Parameter(Mandatory = $false)][ValidateSet('BACKQUOTE', 'CARET', 'COMMA', 'PIPE', 'SEMICOLON', 'TAB')][string] $ColumnDelimiter,
        [Parameter(Mandatory = $false)][ValidateSet('LF', 'CRLF')][string] $LineEnding,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $objectName = ConvertTo-SalesforceSoqlIdentifier -Value $Object
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "CSV file '$File' does not exist." }

    $arguments = @('data', 'import', 'bulk', '--file', $File, '--sobject', $objectName)
    if ($ColumnDelimiter) { $arguments += @('--column-delimiter', $ColumnDelimiter) }
    if ($LineEnding) { $arguments += @('--line-ending', $LineEnding) }
    if ($WaitMinutes -gt 0) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess((Get-SalesforceBulkTargetLabel -Object $objectName -File $File -TargetOrg $TargetOrg), 'Bulk insert')) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data import bulk'
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation 'Import' -Object $objectName
}

function Update-SalesforceBulkData {
    <#
    .SYNOPSIS
    Updates records from the rows of a CSV file with Bulk API 2.0 (sf data update bulk).
    .DESCRIPTION
    The CSV needs an Id column. Asks for confirmation only when $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call.
    Results are as for Import-SalesforceBulkData.
    .EXAMPLE
    Update-SalesforceBulkData -File .\changes.csv -Object Contact -WaitMinutes 10 -TargetOrg myorg
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $File,
        [Parameter(Mandatory = $true)][string] $Object,
        [Parameter(Mandatory = $false)][ValidateSet('BACKQUOTE', 'CARET', 'COMMA', 'PIPE', 'SEMICOLON', 'TAB')][string] $ColumnDelimiter,
        [Parameter(Mandatory = $false)][ValidateSet('LF', 'CRLF')][string] $LineEnding,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $objectName = ConvertTo-SalesforceSoqlIdentifier -Value $Object
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "CSV file '$File' does not exist." }

    $arguments = @('data', 'update', 'bulk', '--file', $File, '--sobject', $objectName)
    if ($ColumnDelimiter) { $arguments += @('--column-delimiter', $ColumnDelimiter) }
    if ($LineEnding) { $arguments += @('--line-ending', $LineEnding) }
    if ($WaitMinutes -gt 0) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess((Get-SalesforceBulkTargetLabel -Object $objectName -File $File -TargetOrg $TargetOrg), 'Bulk update')) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data update bulk'
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation 'Update' -Object $objectName
}

function Upsert-SalesforceBulkData {
    <#
    .SYNOPSIS
    Inserts or updates records from the rows of a CSV file by external ID with Bulk API 2.0 (sf data upsert bulk).
    .DESCRIPTION
    -ExternalIdField names the external ID field the CSV matches on, and its column must be in the file. Asks for confirmation only when
    $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. For one record use Upsert-SalesforceRecord.
    .EXAMPLE
    Upsert-SalesforceBulkData -File .\accounts.csv -Object Account -ExternalIdField Ext_Id__c -WaitMinutes 10 -TargetOrg myorg
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $File,
        [Parameter(Mandatory = $true)][string] $Object,
        [Parameter(Mandatory = $true)][string] $ExternalIdField,
        [Parameter(Mandatory = $false)][ValidateSet('BACKQUOTE', 'CARET', 'COMMA', 'PIPE', 'SEMICOLON', 'TAB')][string] $ColumnDelimiter,
        [Parameter(Mandatory = $false)][ValidateSet('LF', 'CRLF')][string] $LineEnding,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $objectName = ConvertTo-SalesforceSoqlIdentifier -Value $Object
    $externalIdFieldName = ConvertTo-SalesforceSoqlIdentifier -Value $ExternalIdField
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "CSV file '$File' does not exist." }

    $arguments = @('data', 'upsert', 'bulk', '--file', $File, '--sobject', $objectName, '--external-id', $externalIdFieldName)
    if ($ColumnDelimiter) { $arguments += @('--column-delimiter', $ColumnDelimiter) }
    if ($LineEnding) { $arguments += @('--line-ending', $LineEnding) }
    if ($WaitMinutes -gt 0) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess((Get-SalesforceBulkTargetLabel -Object $objectName -File $File -TargetOrg $TargetOrg), "Bulk upsert on $externalIdFieldName")) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data upsert bulk'
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation 'Upsert' -Object $objectName
}

function Resume-SalesforceBulkJob {
    <#
    .SYNOPSIS
    Resumes a Bulk API 2.0 job started without -WaitMinutes (sf data export|import|update|upsert resume).
    .DESCRIPTION
    Pass the JobId from the earlier step and the -Operation that created it. The CLI remembers jobs it created on this computer, so import,
    update and export resumes find the org from that record; they do not take -TargetOrg (it is ignored with a warning), and a job created
    elsewhere cannot be resumed here: use Get-SalesforceBulkResult with -TargetOrg instead. Export resumes do not take -WaitMinutes.
    Resuming only continues the existing job, so it does not ask for confirmation. Errors are as for the cmdlet that created the job.
    .EXAMPLE
    Resume-SalesforceBulkJob -Operation Upsert -JobId 750xx0000000001 -WaitMinutes 10 -TargetOrg myorg
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidateSet('Export', 'Import', 'Update', 'Upsert')][string] $Operation,
        [Parameter(Mandatory = $true)][ValidatePattern('^750[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$')][string] $JobId,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $hasTargetOrg = $PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)
    if ($hasTargetOrg -and $Operation -ne 'Upsert') { Write-Warning "-TargetOrg is ignored for a $Operation resume: the CLI finds the org from its record of the job." }
    if ($WaitMinutes -gt 0 -and $Operation -eq 'Export') { Write-Warning '-WaitMinutes is ignored for an Export resume.' }

    switch ($Operation) {
        'Export' { $arguments = @('data', 'export', 'resume', '--job-id', $JobId); $command = 'data export resume' }
        'Import' { $arguments = @('data', 'import', 'resume', '--job-id', $JobId); $command = 'data import resume' }
        'Update' { $arguments = @('data', 'update', 'resume', '--job-id', $JobId); $command = 'data update resume' }
        'Upsert' { $arguments = @('data', 'upsert', 'resume', '--job-id', $JobId); $command = 'data upsert resume' }
    }
    if ($WaitMinutes -gt 0 -and $Operation -ne 'Export') { $arguments += @('--wait', $WaitMinutes) }
    if ($hasTargetOrg -and $Operation -eq 'Upsert') { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command $command
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation $Operation -JobId $JobId
}

function Get-SalesforceBulkResult {
    <#
    .SYNOPSIS
    Gets the outcome of a Bulk API 2.0 ingest job and saves its row results as CSV files (sf data bulk results).
    .DESCRIPTION
    The CLI writes <JobId>-success-records.csv, <JobId>-failed-records.csv and <JobId>-unprocessed-records.csv into its working directory, so
    the cmdlet runs it in -OutputDirectory (the current directory by default) and returns the full paths of the files it wrote. Records that
    failed do not make this cmdlet throw: check HasFailures or FailedRecords. A job that has not finished is an error. Works for any job in
    the org, including ones this computer did not create.
    .EXAMPLE
    $r = Get-SalesforceBulkResult -JobId 750xx0000000001 -OutputDirectory .\bulk -TargetOrg myorg; if ($r.HasFailures) { Import-Csv $r.FailedFilePath }
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^750[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$')][string] $JobId,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $directory = (Get-Location).ProviderPath
    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw "Output directory '$OutputDirectory' does not exist." }
        $directory = (Resolve-Path -LiteralPath $OutputDirectory).ProviderPath
    }

    $arguments = @('data', 'bulk', 'results', '--job-id', $JobId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Push-Location -LiteralPath $directory
    try {
        $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    } finally {
        Pop-Location
    }
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data bulk results' -AllowFailedRecords

    $pathOf = {
        param([string] $Name)
        if ($null -ne $result.PSObject.Properties[$Name] -and -not [string]::IsNullOrWhiteSpace([string] $result.$Name)) { return (Join-Path -Path $directory -ChildPath ([string] $result.$Name)) }
        return $null
    }
    $failed = 0
    if ($null -ne $result.PSObject.Properties['failedRecords'] -and $null -ne $result.failedRecords) { $failed = [int] $result.failedRecords }
    if ($failed -gt 0) { Write-Warning "$failed record(s) failed in job $JobId. See the failed records file in $directory." }
    return [pscustomobject]@{
        JobId               = $JobId
        Status              = $result.status
        Operation           = $result.operation
        Object              = $result.object
        ProcessedRecords    = $result.processedRecords
        SuccessfulRecords   = $result.successfulRecords
        FailedRecords       = $failed
        HasFailures         = ($failed -gt 0)
        SuccessFilePath     = & $pathOf 'successFilePath'
        FailedFilePath      = & $pathOf 'failedFilePath'
        UnprocessedFilePath = & $pathOf 'unprocessedFilePath'
    }
}

function Get-SalesforceBulkTargetLabel {
    # Names what a bulk write will touch, for the ShouldProcess prompt and -WhatIf: the object, the file and the org.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Object,
        [Parameter(Mandatory = $true)][string] $File,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $org = 'the default org'
    if (-not [string]::IsNullOrWhiteSpace($TargetOrg)) { $org = "org $TargetOrg" }
    return "$Object records from '$File' in $org"
}

function ConvertFrom-SalesforceBulkOutput {
    # Returns the result of a bulk command, or throws. A failed job (failed rows, Failed or Aborted) becomes PsfdxBulkJobFailed with the
    # job ID, so a script can fetch the row results; any other failure is thrown as the CLI described it.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][AllowEmptyCollection()] $Output,
        [Parameter(Mandatory = $true)][string] $Command,
        [Parameter(Mandatory = $false)][switch] $AllowFailedRecords
    )
    $text = [string]::Join([Environment]::NewLine, @($Output | ForEach-Object { [string] $_ })).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { throw "sf $Command returned no output where JSON was expected." }
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop } catch {
        $preview = $text; if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
        throw "sf $Command returned output that is not valid JSON: $preview"
    }
    if ($null -eq $parsed -or $parsed -is [array] -or $null -eq $parsed.PSObject.Properties['status']) {
        throw "sf $Command returned JSON in an unexpected shape (no status)."
    }
    # Upsert and its resume return { jobInfo, records } instead of the flat counts, and the CLI can send that with a failing status when rows failed.
    $hasResult = ($null -ne $parsed.PSObject.Properties['result']) -and ($null -ne $parsed.result)
    if ($hasResult -and $null -ne $parsed.result.PSObject.Properties['jobInfo'] -and $null -ne $parsed.result.jobInfo) {
        $info = $parsed.result.jobInfo
        $state = $null; if ($null -ne $info.PSObject.Properties['state']) { $state = [string] $info.state }
        $flat = [ordered]@{ jobId = [string] $info.id; state = $state }
        if ($state -eq 'JobComplete') {
            $processed = 0; if ($null -ne $info.PSObject.Properties['numberRecordsProcessed'] -and $null -ne $info.numberRecordsProcessed) { $processed = [int] $info.numberRecordsProcessed }
            $failedRows = 0; if ($null -ne $info.PSObject.Properties['numberRecordsFailed'] -and $null -ne $info.numberRecordsFailed) { $failedRows = [int] $info.numberRecordsFailed }
            $flat['processedRecords'] = $processed
            $flat['failedRecords'] = $failedRows
            $flat['successfulRecords'] = $processed - $failedRows
        }
        if (-not $AllowFailedRecords) {
            $message = ''
            if ($state -eq 'Failed' -or $state -eq 'Aborted') {
                if ($null -ne $info.PSObject.Properties['errorMessage'] -and $info.errorMessage) { $message = [string] $info.errorMessage }
                $message = "The job is $state. $message".Trim()
            } elseif ($flat.Contains('failedRecords') -and $flat['failedRecords'] -gt 0) {
                $message = "Job finished being processed but $($flat['failedRecords']) records failed to process."
            }
            if ($message) {
                $full = "sf $Command reported a problem with bulk job $($flat['jobId']): $message Get-SalesforceBulkResult -JobId $($flat['jobId']) lists the rows that failed."
                $target = [pscustomobject]@{ JobId = $flat['jobId']; State = $state; Message = $message }
                $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException $full), 'PsfdxBulkJobFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $target)
                throw $record
            }
        }
        return [pscustomobject] $flat
    }

    if ($parsed.status -eq 0) {
        if (-not $hasResult) { throw "sf $Command succeeded but returned no result." }
        return $parsed.result
    }

    $jobId = $null; $state = $null
    if ($null -ne $parsed.PSObject.Properties['data'] -and $null -ne $parsed.data) {
        if ($null -ne $parsed.data.PSObject.Properties['jobId']) { $jobId = [string] $parsed.data.jobId }
        if ($null -ne $parsed.data.PSObject.Properties['state']) { $state = [string] $parsed.data.state }
    }
    $message = ''
    if ($null -ne $parsed.PSObject.Properties['message'] -and $parsed.message) { $message = [string] $parsed.message }
    if (-not $jobId -and $message -match '\b(750[A-Za-z0-9]{12}(?:[A-Za-z0-9]{3})?)\b') { $jobId = $Matches[1] }
    if ($jobId) {
        $full = "sf $Command reported a problem with bulk job ${jobId}: $message Get-SalesforceBulkResult -JobId $jobId lists the rows that failed.".Replace('  ', ' ')
        $target = [pscustomobject]@{ JobId = $jobId; State = $state; Message = $message }
        $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException $full), 'PsfdxBulkJobFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $target)
        throw $record
    }
    # No job ID: an ordinary CLI failure, with the same message handling as every other cmdlet.
    Show-SalesforceResult -Result $text | Out-Null
    throw "sf $Command failed with status $($parsed.status). $message".Trim()
}

function ConvertTo-SalesforceBulkJobObject {
    # One shape for every bulk command. Properties the CLI did not report (an asynchronous job has no counts yet) are $null.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)] $Result,
        [Parameter(Mandatory = $true)][string] $Operation,
        [Parameter(Mandatory = $false)][string] $Object,
        [Parameter(Mandatory = $false)][string] $JobId
    )
    $get = {
        param([string] $Name)
        if ($null -ne $Result.PSObject.Properties[$Name]) { return $Result.$Name }
        return $null
    }
    $id = & $get 'jobId'
    if (-not $id) { $id = $JobId }
    $processed = & $get 'processedRecords'
    $total = & $get 'totalSize'
    $state = & $get 'state'
    return [pscustomobject]@{
        JobId             = $id
        Operation         = $Operation
        Object            = $(if ($Object) { $Object } else { $null })
        Completed         = (($null -ne $processed) -or ($null -ne $total))
        State             = $state
        ProcessedRecords  = $processed
        SuccessfulRecords = & $get 'successfulRecords'
        FailedRecords     = & $get 'failedRecords'
        TotalSize         = $total
        FilePath          = & $get 'filePath'
    }
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
    $arguments = @('api', 'request', 'rest', '/services/data')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return $result | ConvertFrom-Json
}

function Get-SalesforceLatestApiVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $versions = Get-SalesforceApiVersions -TargetOrg $TargetOrg
    if (-not $versions -or (@($versions).Count -eq 0)) { return $null }
    # Sort numerically: a string sort ranks '99.0' above '100.0'
    $latest = @($versions) |
        Where-Object { $_.version } |
        Sort-Object -Property { [double] $_.version } -Descending |
        Select-Object -First 1
    if (-not $latest) { return $null }
    return "v$($latest.version)"
}

#endregion

#region Users and Permissions

# Wraps the Salesforce CLI `org` user commands: list users, display user, create user, generate password, assign permset and permsetlicense.
# Secrets never reach the output stream, -Verbose or error messages: access tokens are dropped from every result, and a password is returned
# only as a SecureString and only when it was asked for.
#
# Limits of the CLI: `org list users` and `org display user` read the CLI's local authorisation files, so they list the users the CLI knows
# here, not every user in the org (use Get-SalesforceUsers for a query). The caller needs the org permissions for the action (Manage Users
# to create a user or assign permission sets, and for a password the "Manage Users" and "Reset User Passwords and Unlock Users" permissions);
# Salesforce rejects the call otherwise and the cmdlet throws the CLI's message.

function Get-SalesforceAuthenticatedUser {
    <#
    .SYNOPSIS
    Lists the users of an org that the Salesforce CLI has authorised on this computer (sf org list users).
    .DESCRIPTION
    Tokens are removed from the result. To search all users in the org, use Get-SalesforceUsers.
    .EXAMPLE
    Get-SalesforceAuthenticatedUser -TargetOrg myscratch
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('org', 'list', 'users')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $users = Show-SalesforceResult -Result $result
    return @($users | ForEach-Object { Remove-SalesforceSecretProperty -InputObject $_ })
}

function Get-SalesforceOrgUser {
    <#
    .SYNOPSIS
    Shows the user the CLI is signed in as in an org (sf org display user).
    .DESCRIPTION
    The access token and password are never returned: current Salesforce CLI versions replace both with a redaction message in this command, so
    there is nothing real to return. HasPassword says whether the CLI holds a password for the user. To set a known password, use
    New-SalesforceUserPassword.
    .EXAMPLE
    Get-SalesforceOrgUser -TargetOrg myscratch
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('org', 'display', 'user')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $user = Show-SalesforceResult -Result $result
    $clean = Remove-SalesforceSecretProperty -InputObject $user
    $hasPassword = ($null -ne $user.PSObject.Properties['password']) -and -not [string]::IsNullOrEmpty([string] $user.password)
    $clean | Add-Member -NotePropertyName HasPassword -NotePropertyValue $hasPassword -Force
    return $clean
}

function New-SalesforceUser {
    <#
    .SYNOPSIS
    Creates a user in an org and authorises it in the CLI (sf org create user).
    .DESCRIPTION
    Give the user's fields in a definition file (-DefinitionFile), in -Field, or both; fields in -Field override the file. Asks for confirmation
    only when $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. Field values go to the CLI as separate arguments, so quotes
    and spaces need no escaping, but a value with a double quote or a line break is rejected by the Windows CLI shim. Needs the Manage Users
    permission. The CLI creates users for scratch orgs and sandboxes it can sign in to.
    .EXAMPLE
    New-SalesforceUser -Field @{ username = 'qa1@example.org'; profileName = 'Standard User'; lastName = 'QA' } -SetAlias qa1 -TargetOrg myscratch
    .EXAMPLE
    New-SalesforceUser -DefinitionFile .\config\user-def.json -SetUniqueUsername -TargetOrg myscratch -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $false)][string] $DefinitionFile,
        [Parameter(Mandatory = $false)][System.Collections.IDictionary] $Field,
        [Parameter(Mandatory = $false)][string] $SetAlias,
        [Parameter(Mandatory = $false)][switch] $SetUniqueUsername,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($DefinitionFile -and -not (Test-Path -LiteralPath $DefinitionFile -PathType Leaf)) { throw "Definition file '$DefinitionFile' does not exist." }
    $pairs = @()
    if ($null -ne $Field) {
        foreach ($key in $Field.Keys) {
            $name = [string] $key
            if ($name -cnotmatch '^[A-Za-z][A-Za-z0-9_]*$') { throw "'$name' is not a valid user field name." }
            $value = [string] $Field[$key]
            if ($value -match '[\x00-\x1F\x7F]') { throw "The value of field '$name' must not contain control characters." }
            $pairs += "$name=$value"
        }
    }

    $arguments = @('org', 'create', 'user')
    if ($DefinitionFile) { $arguments += @('--definition-file', $DefinitionFile) }
    if ($SetAlias) { $arguments += @('--set-alias', $SetAlias) }
    if ($SetUniqueUsername) { $arguments += '--set-unique-username' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += $pairs
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $orgLabel = 'the default org'
    if (-not [string]::IsNullOrWhiteSpace($TargetOrg)) { $orgLabel = "org $TargetOrg" }
    if (-not $PSCmdlet.ShouldProcess("a user in $orgLabel", 'Create user')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $created = Show-SalesforceResult -Result $result
    return Remove-SalesforceSecretProperty -InputObject $created
}

function New-SalesforceUserPassword {
    <#
    .SYNOPSIS
    Generates a new password for a user and returns it as a SecureString (sf org generate password).
    .DESCRIPTION
    This changes the user's password, so it asks for confirmation by default; -WhatIf makes no CLI call. The password is returned only as a
    SecureString in Password, and is never written to -Verbose, -Debug or error output by this cmdlet. Length is 20 to 1000 and complexity 3 to
    5 (higher is stronger), as the CLI allows. One user at a time (-OnBehalfOf takes a single username or alias). Needs the Manage Users and
    Reset User Passwords and Unlock Users permissions.
    .EXAMPLE
    $p = New-SalesforceUserPassword -OnBehalfOf qa1 -TargetOrg myscratch -Confirm:$false; $p.Username
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $false)][string] $OnBehalfOf,
        [Parameter(Mandatory = $false)][ValidateRange(20, 1000)][int] $Length = 20,
        [Parameter(Mandatory = $false)][ValidateRange(3, 5)][int] $Complexity = 5,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($OnBehalfOf -and $OnBehalfOf.Contains(',')) { throw '-OnBehalfOf takes one username or alias, not a list.' }
    $arguments = @('org', 'generate', 'password')
    if ($OnBehalfOf) { $arguments += @('--on-behalf-of', $OnBehalfOf) }
    $arguments += @('--length', $Length, '--complexity', $Complexity)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $who = $OnBehalfOf
    if (-not $who) { $who = 'the target org user' }
    if (-not $PSCmdlet.ShouldProcess($who, 'Generate a new password')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $data = Show-SalesforceResult -Result $result
    $out = @()
    foreach ($item in @($data)) {
        if ($null -eq $item -or $null -eq $item.PSObject.Properties['password'] -or [string]::IsNullOrEmpty([string] $item.password)) { continue }
        $username = $null
        if ($null -ne $item.PSObject.Properties['username']) { $username = [string] $item.username }
        $out += [pscustomobject]@{ Username = $username; Password = (ConvertTo-SecureString -String ([string] $item.password) -AsPlainText -Force) }
    }
    if ($out.Count -eq 0) { throw 'The Salesforce CLI did not return a password.' }
    return $out
}

function Grant-SalesforcePermissionSet {
    <#
    .SYNOPSIS
    Assigns permission sets to users (sf org assign permset).
    .DESCRIPTION
    Without -OnBehalfOf the permission sets go to the target org's own user. Returns one object per user and permission set with Status
    Assigned or AlreadyAssigned; assigning a set the user already has is not an error, so a script can run again safely. Failures (a missing
    set, no permission) are returned with Status Failed and the cmdlet then throws PsfdxPermissionAssignmentFailed, whose TargetObject lists
    them. Asks for confirmation by default; -WhatIf makes no CLI call. Needs the Assign Permission Sets permission.
    .EXAMPLE
    Grant-SalesforcePermissionSet -Name Sales_Admin, Reports_User -OnBehalfOf qa1, qa2 -TargetOrg myscratch -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string[]] $Name,
        [Parameter(Mandatory = $false)][string[]] $OnBehalfOf,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $names = Test-SalesforceAssignmentNames -Name $Name -OnBehalfOf $OnBehalfOf
    $users = @($OnBehalfOf | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $arguments = @('org', 'assign', 'permset')
    foreach ($item in $names) { $arguments += @('--name', $item) }
    foreach ($item in $users) { $arguments += @('--on-behalf-of', $item) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $who = 'the target org user'
    if ($users.Count -gt 0) { $who = $users -join ', ' }
    if (-not $PSCmdlet.ShouldProcess($who, "Assign permission set $($names -join ', ')")) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    ConvertFrom-SalesforceAssignmentOutput -Output $output -Command 'org assign permset' -Names $names
}

function Grant-SalesforcePermissionSetLicense {
    <#
    .SYNOPSIS
    Assigns permission set licenses to users (sf org assign permsetlicense).
    .DESCRIPTION
    Results, idempotency, failures and confirmation work as for Grant-SalesforcePermissionSet. The org must have the licence available.
    .EXAMPLE
    Grant-SalesforcePermissionSetLicense -Name SalesforceCPQ_Admin -OnBehalfOf qa1 -TargetOrg myscratch -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string[]] $Name,
        [Parameter(Mandatory = $false)][string[]] $OnBehalfOf,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $names = Test-SalesforceAssignmentNames -Name $Name -OnBehalfOf $OnBehalfOf
    $users = @($OnBehalfOf | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $arguments = @('org', 'assign', 'permsetlicense')
    foreach ($item in $names) { $arguments += @('--name', $item) }
    foreach ($item in $users) { $arguments += @('--on-behalf-of', $item) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $who = 'the target org user'
    if ($users.Count -gt 0) { $who = $users -join ', ' }
    if (-not $PSCmdlet.ShouldProcess($who, "Assign permission set license $($names -join ', ')")) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    ConvertFrom-SalesforceAssignmentOutput -Output $output -Command 'org assign permsetlicense' -Names $names
}

function Test-SalesforceAssignmentNames {
    # Cleans and checks the names and users given to an assignment, and returns the names.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]] $Name,
        [Parameter(Mandatory = $false)][string[]] $OnBehalfOf
    )
    $names = @($Name | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    if ($names.Count -eq 0) { throw '-Name needs at least one name.' }
    foreach ($item in $names) { if ($item -match '[,\x00-\x1F\x7F]') { throw "'$item' is not a valid name: give one name per value, without commas." } }
    foreach ($item in @($OnBehalfOf | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if ($item -match '[,\x00-\x1F\x7F]') { throw "'$item' is not a valid username or alias: give one per value, without commas." }
    }
    return $names
}

function ConvertFrom-SalesforceAssignmentOutput {
    # Turns the result of `sf org assign permset|permsetlicense` into one object per assignment. The CLI exits with status 68 when some
    # assignments failed but still returns the successes and failures, so the result is read whatever the status is.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][AllowEmptyCollection()] $Output,
        [Parameter(Mandatory = $true)][string] $Command,
        [Parameter(Mandatory = $true)][string[]] $Names
    )
    $text = [string]::Join([Environment]::NewLine, @($Output | ForEach-Object { [string] $_ })).Trim()
    $parsed = $null
    if (-not [string]::IsNullOrWhiteSpace($text)) { try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop } catch { $parsed = $null } }
    $result = $null
    if ($null -ne $parsed -and $null -ne $parsed.PSObject.Properties['result']) { $result = $parsed.result }
    $hasLists = ($null -ne $result) -and (($null -ne $result.PSObject.Properties['successes']) -or ($null -ne $result.PSObject.Properties['failures']))
    if (-not $hasLists) {
        # Not an assignment result: an ordinary CLI failure (no authorisation, unknown flag...) or unusable output.
        Show-SalesforceResult -Result $text | Out-Null
        throw "sf $Command returned no assignment result."
    }

    $items = @()
    if ($null -ne $result.PSObject.Properties['successes']) {
        foreach ($s in @($result.successes)) {
            $items += [pscustomobject]@{ Username = [string] $s.name; PermissionSet = [string] $s.value; Status = 'Assigned'; Message = $null }
        }
    }
    $failed = @()
    if ($null -ne $result.PSObject.Properties['failures']) {
        foreach ($f in @($result.failures)) {
            $message = [string] $f.message
            $status = 'Failed'
            if ($message -match '(?i)duplicate') { $status = 'AlreadyAssigned' }
            $permSet = $null
            if ($Names.Count -eq 1) { $permSet = $Names[0] }
            $item = [pscustomobject]@{ Username = [string] $f.name; PermissionSet = $permSet; Status = $status; Message = $message }
            $items += $item
            if ($status -eq 'Failed') { $failed += $item }
        }
    }
    $items
    if ($failed.Count -gt 0) {
        $summary = ($failed | ForEach-Object { "$($_.Username): $($_.Message)" }) -join '; '
        if ($summary.Length -gt 400) { $summary = $summary.Substring(0, 400) + '...' }
        $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException "sf $Command failed for $($failed.Count) assignment(s): $summary"), 'PsfdxPermissionAssignmentFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $failed)
        throw $record
    }
}

function Remove-SalesforceSecretProperty {
    # Returns a copy of a CLI result without credential properties, so a token or password cannot leak through the pipeline.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][AllowNull()] $InputObject
    )
    if ($null -eq $InputObject) { return $null }
    return ($InputObject | Select-Object -Property * -ExcludeProperty accessToken, refreshToken, password, sfdxAuthUrl, clientSecret, privateKey)
}

#endregion

#region Plugins

function Test-SalesforceIsMacOS {
    [CmdletBinding()]
    Param()
    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
}

function Install-SalesforceCli {
    [CmdletBinding()]
    Param()
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    # npm is the Salesforce-supported install on Windows, Linux and macOS
    Invoke-Salesforce -FilePath 'npm' -Arguments @('install', '--global', '@salesforce/cli') @commonParams
}

function Update-SalesforceCli {
    [CmdletBinding()]
    Param()
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'npm' -Arguments @('update', '--global', '@salesforce/cli') @commonParams
}

function Install-SalesforcePlugin {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name
    )
    $arguments = @('plugins', 'install', $Name)
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

function Get-SalesforcePlugins {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $IncludeCore
    )
    $arguments = @('plugins')
    if ($IncludeCore) { $arguments += '--core' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

function Update-SalesforcePlugins {
    [CmdletBinding()]
    Param()
    $arguments = @('plugins', 'update')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

#endregion

#region Utilities

function Get-SalesforceDateTime {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][datetime] $Datetime)
    if ($null -eq $Datetime) { $Datetime = Get-Date }
    return ConvertTo-SalesforceSoqlDateTime -Value $Datetime
}

#endregion
