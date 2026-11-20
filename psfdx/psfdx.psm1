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
    # Salesforce answers 201 when it created the record (body has the new Id) and 204, with no body, when it updated one. The 204
    # carries no Id, so Id is $null for an update rather than a guess.
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

    if ($statusCode -eq 201 -or $statusCode -eq 204) {
        $created = ($statusCode -eq 201)
        $id = $null
        if ($created -and $null -ne $responseBody -and $null -ne $responseBody.PSObject.Properties['id']) { $id = $responseBody.id }
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
