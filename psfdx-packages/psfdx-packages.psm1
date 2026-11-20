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

#region Packages

function Get-SalesforcePackages {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $ExtendedPackageDetails
    )
    $arguments = @('package', 'list')
    if ($TargetDevHub) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    if ($ExtendedPackageDetails) { $arguments += '--verbose' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforcePackage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $ExtendedPackageDetails
    )
    if ($TargetDevHub) {
        $packages = Get-SalesforcePackages -TargetDevHub $TargetDevHub -ExtendedPackageDetails:$ExtendedPackageDetails
    } else {
        $packages = Get-SalesforcePackages -ExtendedPackageDetails:$ExtendedPackageDetails
    }
    return $packages | Where-Object Name -eq $Name
}

function New-SalesforcePackage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string][ValidateSet("Managed", "Unlocked")] $PackageType = "Unlocked",
        [Parameter(Mandatory = $false)][switch] $IsOrgDependent,
        [Parameter(Mandatory = $false)][string] $Path = "force-app/main/default",
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $ErrorNotificationUsername,
        [Parameter(Mandatory = $false)][switch] $NoNamespace,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('package', 'create', '--name', $Name)
    $arguments += @('--package-type', $PackageType)
    $arguments += @('--path', $Path)
    if ($IsOrgDependent) { $arguments += '--org-dependent' }
    if ($Description) { $arguments += @('--description', $Description) }
    if ($ErrorNotificationUsername) { $arguments += @('--error-notification-username', $ErrorNotificationUsername) }
    if ($NoNamespace) { $arguments += '--no-namespace' }
    if ($TargetDevHub) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $resultSfdx = Show-SalesforceResult -Result $result
    return $resultSfdx.Id
}

function Remove-SalesforcePackage {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $arguments = @('package', 'delete', '--package', $Name)
    if ($NoPrompt) { $arguments += '--no-prompt' }
    if ($TargetDevHub) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($PSCmdlet.ShouldProcess($Name, 'Delete package')) {
        Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    }
}

function Get-SalesforcePackagesInstalled {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][string] $ApiVersion
    )

    $arguments = @('package', 'installed', 'list')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($ApiVersion) { $arguments += @('--api-version', $ApiVersion) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    # The CLI returns result as a plain array, not a records wrapper.
    $packages = Show-SalesforceResult -Result $result
    if ($null -eq $packages) { return @() }
    if ($null -ne $packages.PSObject.Properties['records']) { $packages = $packages.records }
    if ($null -eq $packages) { return @() }
    return @($packages)
}

#endregion

#region Package Versions

function Get-SalesforcePackageVersions {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $PackageId,
        [Parameter(Mandatory = $false)][string] $PackageName,
        [Parameter(Mandatory = $false)][switch] $Released,
        [Parameter(Mandatory = $false)][switch] $Concise,
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails,
        [Parameter(Mandatory = $false)][switch] $ConversionsOnly,
        [Parameter(Mandatory = $false)][string] $Branch,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    if ((! $PackageId ) -and ($PackageName) ) {
        if ($TargetDevHub) {
            $package = Get-SalesforcePackage -Name $PackageName -TargetDevHub $TargetDevHub
        } else {
            $package = Get-SalesforcePackage -Name $PackageName
        }
        $PackageId = $package.Id
    }

    $arguments = @('package', 'version', 'list')
    if ($PackageId) { $arguments += @('--packages', $PackageId) }
    if ($Released) { $arguments += '--released' }
    if ($Concise) { $arguments += '--concise' }
    if ($ExtendedDetails) { $arguments += '--verbose' }
    if ($ConversionsOnly) { $arguments += '--show-conversions-only' }
    if ($Branch) { $arguments += @('--branch', $Branch) }
    if ($TargetDevHub) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $PackageId,
        [Parameter(Mandatory = $false)][string] $PackageName,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $Tag,

        [Parameter(Mandatory = $false)][string] $InstallationKey,
        [Parameter(Mandatory = $false)][switch] $InstallationKeyBypass,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][switch] $SkipValidation,

        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string] $ScratchOrgDefinitionFile = "config/project-scratch-def.json",
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )

    if ((! $PackageId ) -and (! $PackageName) ) {
        throw "Please provide a PackageId or Package Name"
    }
    if ((! $PackageId ) -and ($PackageName) ) {
        if ($TargetDevHub) {
            $package = Get-SalesforcePackage -Name $PackageName -TargetDevHub $TargetDevHub
        } else {
            $package = Get-SalesforcePackage -Name $PackageName
        }
        $PackageId = $package.Id
    }

    $arguments = @('package', 'version', 'create', '--package', $PackageId)
    if ($Name) { $arguments += @('--version-name', $Name) }
    if ($Description) { $arguments += @('--version-description', $Description) }
    if ($Tag) { $arguments += @('--tag', $Tag) }
    if ($CodeCoverage) { $arguments += '--code-coverage' }
    $arguments += @('--definition-file', $ScratchOrgDefinitionFile)

    if (($InstallationKeyBypass) -or (! $InstallationKey)) {
        $arguments += '--installation-key-bypass'
    } else {
        $arguments += @('--installation-key', $InstallationKey)
    }

    if ($SkipValidation) { $arguments += '--skip-validation' }
    if ($WaitMinutes) { $arguments += @('--wait', $WaitMinutes) }
    if ($TargetDevHub) { $arguments += @('--target-dev-hub', $TargetDevHub) }

    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Promote-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )

    $arguments = @('package', 'version', 'promote')
    $arguments += @('--package', $PackageVersionId)
    if ($TargetDevHub) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    if ($NoPrompt) { $arguments += '--no-prompt' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforcePackageVersion {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )

    $arguments = @('package', 'version', 'delete')
    $arguments += @('--package', $PackageVersionId)
    if ($TargetDevHub) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    if ($NoPrompt) { $arguments += '--no-prompt' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($PSCmdlet.ShouldProcess($PackageVersionId, 'Delete package version')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Install-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][int] $WaitMinutes = 10,
        [Parameter(Mandatory = $false)][ValidateSet('AllUsers','AdminsOnly')][string] $SecurityType = 'AdminsOnly'
    )

    $arguments = @('package', 'install')
    $arguments += @('--package', $PackageVersionId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($NoPrompt) { $arguments += '--no-prompt' }
    if ($SecurityType) { $arguments += @('--security-type', $SecurityType) }
    if ($WaitMinutes) {
        $arguments += @('--wait', $WaitMinutes)
        $arguments += @('--publish-wait', $WaitMinutes)
    }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

#endregion
