function Import-PsfdxSharedModule {
    [CmdletBinding()]
    param(
        [string] $ModuleName = 'psfdx-shared'
    )

    if (Get-Module -Name $ModuleName -ErrorAction SilentlyContinue) {
        return
    }

    $candidates = @()

    $repoManifest = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path '..' (Join-Path $ModuleName "$ModuleName.psd1"))
    $candidates += $repoManifest

    $moduleParent = Split-Path -Path $PSScriptRoot -Parent
    if ($moduleParent) {
        $siblingManifest = Join-Path -Path $moduleParent -ChildPath (Join-Path $ModuleName "$ModuleName.psd1")
        $candidates += $siblingManifest

        $moduleRoot = Split-Path -Path $moduleParent -Parent
        if ($moduleRoot) {
            $sharedBase = Join-Path -Path $moduleRoot -ChildPath $ModuleName
            if (Test-Path -LiteralPath $sharedBase) {
                try {
                    $versionDirectories = Get-ChildItem -Path $sharedBase -Directory -ErrorAction Stop | Sort-Object -Property Name -Descending
                    foreach ($dir in $versionDirectories) {
                        $candidates += Join-Path -Path $dir.FullName -ChildPath "$ModuleName.psd1"
                    }
                } catch {
                    # ignore directory inspection failures
                }
                $candidates += Join-Path -Path $sharedBase -ChildPath "$ModuleName.psd1"
            }
        }
    }

    $available = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending
    foreach ($item in $available) {
        if ($item.Path) {
            $candidates += $item.Path
        }
    }

    foreach ($candidate in $candidates | Where-Object { $_ } | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate) {
            Import-Module -Name $candidate -ErrorAction Stop
            return
        }
    }

    Import-Module -Name $ModuleName -ErrorAction Stop
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
