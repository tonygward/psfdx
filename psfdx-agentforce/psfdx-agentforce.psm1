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

#region Plugin availability

function Test-SalesforceAgentPlugin {
    [CmdletBinding()]
    Param()

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $raw = Invoke-Salesforce -FilePath 'sf' -Arguments @('plugins', '--core', '--json') @commonParams
    $text = ($raw | Out-String)
    return ($text -match '@salesforce/plugin-agent')
}

function Assert-SalesforceAgentPlugin {
    # Private: stops with install guidance when the agent plugin is missing.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][hashtable] $CommonParams = @{}
    )

    if (-not (Test-SalesforceAgentPlugin @CommonParams)) {
        throw "The Salesforce CLI plugin '@salesforce/plugin-agent' is not installed. Run Install-SalesforcePlugin -Name @salesforce/plugin-agent (or 'sf plugins install @salesforce/plugin-agent'), then try again."
    }
}

function Assert-SalesforceAgentApiName {
    # Private: agent and test API names are letters, digits and underscores.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Value,
        [Parameter(Mandatory = $true)][string] $What
    )

    if ($Value -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
        throw "$What '$Value' is not a valid API name. Use letters, digits and underscores, starting with a letter."
    }
}

#endregion

#region Agent tests

function Get-SalesforceAgentTests {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'test', 'list')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $parsed = Show-SalesforceResult -Result $result
    if ($null -eq $parsed) { return @() }
    return @($parsed)
}

function Start-SalesforceAgentTest {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ApiName,
        [Parameter(Mandatory = $false)][ValidateRange(1, 1440)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    Assert-SalesforceAgentApiName -Value $ApiName -What 'Agent test'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'test', 'run', '--api-name', $ApiName)
    if ($PSBoundParameters.ContainsKey('WaitMinutes')) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceAgentTestResult {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $JobId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if ($JobId -notmatch '^[A-Za-z0-9]{15,18}$') {
        throw "Job ID '$JobId' is not a valid 15 or 18 character Salesforce ID."
    }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'test', 'results', '--job-id', $JobId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region Agent activation

function Enable-SalesforceAgent {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string] $ApiName,
        [Parameter(Mandatory = $false)][ValidateRange(1, 9999)][int] $Version,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    Assert-SalesforceAgentApiName -Value $ApiName -What 'Agent'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'activate', '--api-name', $ApiName)
    if ($PSBoundParameters.ContainsKey('Version')) { $arguments += @('--version', $Version) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'

    if ($PSCmdlet.ShouldProcess($ApiName, 'Activate agent')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Disable-SalesforceAgent {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string] $ApiName,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    Assert-SalesforceAgentApiName -Value $ApiName -What 'Agent'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'deactivate', '--api-name', $ApiName)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'

    if ($PSCmdlet.ShouldProcess($ApiName, 'Deactivate agent')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

#endregion

#region Authoring bundles

# Wraps `sf agent generate|validate|publish authoring-bundle`, the Agent Script authoring commands of @salesforce/plugin-agent.
# Upstream status: these commands are newer than the agent test and activation commands and may be marked beta; they need a recent
# plugin-agent (sf plugins update) and an org with Agentforce enabled. The live CLI help check confirms the names and flags.

function Get-SalesforceAgentDiagnostic {
    # Private: turns a failed validation into one diagnostic object per problem the CLI reports.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)] $Parsed
    )

    $names = @($Parsed.PSObject.Properties.Name)
    $items = @()
    foreach ($key in 'data', 'errors', 'diagnostics') {
        if ($names -contains $key -and $null -ne $Parsed.$key) {
            $value = $Parsed.$key
            if ($value -is [string]) { $items += $value; continue }
            if ($value.PSObject.Properties.Name -contains 'errors' -and $null -ne $value.errors) { $value = $value.errors }
            foreach ($entry in @($value)) { $items += $entry }
        }
    }
    $diagnostics = @()
    foreach ($item in $items) {
        if ($item -is [string]) {
            $diagnostics += [pscustomobject]@{ Message = $item; Line = $null; Column = $null; Severity = 'Error' }
            continue
        }
        $p = @($item.PSObject.Properties.Name)
        $message = $null
        if ($p -contains 'message') { $message = [string]$item.message } elseif ($p -contains 'description') { $message = [string]$item.description } else { $message = ($item | ConvertTo-Json -Compress -Depth 4) }
        $line = $null
        if ($p -contains 'line') { $line = $item.line } elseif ($p -contains 'lineStart') { $line = $item.lineStart }
        $column = $null
        if ($p -contains 'column') { $column = $item.column } elseif ($p -contains 'colStart') { $column = $item.colStart }
        $severity = 'Error'
        if ($p -contains 'severity' -and $item.severity) { $severity = [string]$item.severity }
        $diagnostics += [pscustomobject]@{ Message = $message; Line = $line; Column = $column; Severity = $severity }
    }
    if ($diagnostics.Count -eq 0 -and $names -contains 'message' -and $Parsed.message) {
        $diagnostics += [pscustomobject]@{ Message = [string]$Parsed.message; Line = $null; Column = $null; Severity = 'Error' }
    }
    return $diagnostics
}

function New-SalesforceAgentAuthoringBundle {
    <#
    .SYNOPSIS
    Generates an authoring bundle (Agent Script) for an agent (sf agent generate authoring-bundle).
    .DESCRIPTION
    Writes files into the project, so it asks for confirmation and supports -WhatIf. The CLI requires -Name (the agent label) and either -Spec
    (an agent spec file made by the agent plugin) or -NoSpec to generate a blank bundle; both are checked before the CLI is called. -OutputDir is where the bundle goes (the CLI default is the project's authoring bundle folder). Returns the CLI result, which includes
    the paths written. Needs the @salesforce/plugin-agent plugin, a recent version, and Agentforce enabled in the org.
    .EXAMPLE
    New-SalesforceAgentAuthoringBundle -Name 'Service Agent' -ApiName Service_Agent -Spec specs/agentSpec.yaml -TargetOrg my-org
    .EXAMPLE
    New-SalesforceAgentAuthoringBundle -Name 'Service Agent' -ApiName Service_Agent -NoSpec -Confirm:$false | Out-Null
    Test-SalesforceAgentAuthoringBundle -ApiName Service_Agent
    Publish-SalesforceAgentAuthoringBundle -ApiName Service_Agent -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $ApiName,
        [Parameter(Mandatory = $false)][string] $Spec,
        [Parameter(Mandatory = $false)][switch] $NoSpec,
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if ($ApiName) { Assert-SalesforceAgentApiName -Value $ApiName -What 'Authoring bundle' }
    if ($Spec -and $NoSpec) { throw 'Specify only one of -Spec or -NoSpec.' }
    if (-not $Spec -and -not $NoSpec) { throw 'Specify -Spec (an agent spec file) or -NoSpec to generate a blank bundle.' }
    if ($Spec -and -not (Test-Path -LiteralPath $Spec -PathType Leaf)) { throw "Spec file '$Spec' does not exist." }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'generate', 'authoring-bundle')
    $arguments += @('--name', $Name)
    if ($ApiName) { $arguments += @('--api-name', $ApiName) }
    if ($Spec) { $arguments += @('--spec', $Spec) }
    if ($NoSpec) { $arguments += '--no-spec' }
    if ($OutputDir) { $arguments += @('--output-dir', $OutputDir) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'

    $target = $Name
    if ($ApiName) { $target = $ApiName }
    if ($PSCmdlet.ShouldProcess($target, 'Generate authoring bundle files')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Test-SalesforceAgentAuthoringBundle {
    <#
    .SYNOPSIS
    Validates an authoring bundle and returns the diagnostics as objects (sf agent validate authoring-bundle).
    .DESCRIPTION
    Read-only. Returns Valid, ApiName and Diagnostics (Message, Line, Column, Severity). Invalid Agent Script is returned as Valid = $false with
    its diagnostics, not thrown, so a script can print or filter them; add -ThrowOnInvalid to fail a CI step (error id PsfdxAgentValidationFailed,
    with the result as the target object). Failures that are not validation problems, such as an unknown org, always throw.
    .EXAMPLE
    $v = Test-SalesforceAgentAuthoringBundle -ApiName Service_Agent -TargetOrg my-org; $v.Diagnostics | Format-Table Line, Message
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ApiName,
        [Parameter(Mandatory = $false)][switch] $ThrowOnInvalid,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    Assert-SalesforceAgentApiName -Value $ApiName -What 'Authoring bundle'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('ThrowOnInvalid')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'validate', 'authoring-bundle', '--api-name', $ApiName)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $text = (@($output) | Out-String).Trim()
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop } catch { $parsed = $null }
    if ($null -eq $parsed) { throw "The Salesforce CLI returned no usable result: $text" }

    $diagnostics = @()
    if ([int]$parsed.status -ne 0) {
        $diagnostics = @(Get-SalesforceAgentDiagnostic -Parsed $parsed)
        $name = ''
        if ($parsed.PSObject.Properties.Name -contains 'name' -and $parsed.name) { $name = [string]$parsed.name }
        $isValidation = ($name -match 'valid|compil|syntax|parse') -or ($parsed.PSObject.Properties.Name -contains 'data' -and $null -ne $parsed.data -and $diagnostics.Count -gt 0)
        if (-not $isValidation) { Show-SalesforceResult -Result $text | Out-Null }
    }
    $valid = ([int]$parsed.status -eq 0)
    $result = [pscustomobject]@{ ApiName = $ApiName; Valid = $valid; Diagnostics = $diagnostics }
    if (-not $valid -and $ThrowOnInvalid) {
        $message = "Authoring bundle '$ApiName' is not valid: $($diagnostics.Count) problem(s)."
        $errorRecord = New-Object System.Management.Automation.ErrorRecord ([System.Exception]::new($message)), 'PsfdxAgentValidationFailed', ([System.Management.Automation.ErrorCategory]::InvalidData), $result
        throw $errorRecord
    }
    return $result
}

function Publish-SalesforceAgentAuthoringBundle {
    <#
    .SYNOPSIS
    Publishes an authoring bundle to the org as an agent (sf agent publish authoring-bundle).
    .DESCRIPTION
    Changes the org, so it asks for confirmation and supports -WhatIf. Returns the CLI result (the published agent). By default the CLI retrieves
    the published agent metadata afterwards; -SkipRetrieve turns that off. Validate first with Test-SalesforceAgentAuthoringBundle.
    .EXAMPLE
    Publish-SalesforceAgentAuthoringBundle -ApiName Service_Agent -TargetOrg my-org
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string] $ApiName,
        [Parameter(Mandatory = $false)][switch] $SkipRetrieve,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    Assert-SalesforceAgentApiName -Value $ApiName -What 'Authoring bundle'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'publish', 'authoring-bundle', '--api-name', $ApiName)
    if ($SkipRetrieve) { $arguments += '--skip-retrieve' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'

    $orgLabel = 'the default org'
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $orgLabel = $TargetOrg }
    if ($PSCmdlet.ShouldProcess("$ApiName in $orgLabel", 'Publish authoring bundle')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

#endregion
