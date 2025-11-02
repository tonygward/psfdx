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
    $command = "sf package list"
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }
    if ($ExtendedPackageDetails) { $command += " --verbose" }
    $command += " --json"
    $result = Invoke-Salesforce -Verbose -Command $command
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
    $command = "sf package create --name $Name"
    $command += " --package-type $PackageType"
    $command += " --path $Path"
    if ($IsOrgDependent) { $command += " --org-dependent" }
    if ($Description) { $command += " --description $Description" }
    if ($ErrorNotificationUsername) { $command += " --error-notification-username $ErrorNotificationUsername" }
    if ($NoNamespace) { $command += " --no-namespace" }
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }
    $command += " --json"
    $result = Invoke-Salesforce -Verbose -Command $command
    $resultSfdx = Show-SalesforceResult -Result $result
    return $resultSfdx.Id
}

function Remove-SalesforcePackage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $command = "sf package delete --package $Name"
    if ($NoPrompt) { $command += " --no-prompt" }
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }
    Invoke-Salesforce -Verbose -Command $command
}

function Get-SalesforcePackagesInstalled {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][string] $ApiVersion
    )

    $command = "sf force package installed list"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    if ($ApiVersion) { $command += " --api-version $ApiVersion" }
    $command += " --json"

    $result = Invoke-Salesforce -Verbose -Command $command
    return Show-SalesforceResult -Result $result -ReturnRecords
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

    $command = "sf package version list"
    if ($PackageId) { $command += " --packages $PackageId" }
    if ($Released) { $command += " --released" }
    if ($Concise) { $command += " --concise" }
    if ($ExtendedDetails) { $command += " --verbose" }
    if ($ConversionsOnly) { $command += " --show-conversions-only" }
    if ($Branch) { $command += " --branch $Branch" }
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }
    $command += " --json"

    $result = Invoke-Salesforce -Verbose -Command $command
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

    $command = "sf package version create --package $PackageId"
    if ($Name) { $command += " --version-name $Name" }
    if ($Description) { $command += " --version-description $Description" }
    if ($Tag) { $command += " --tag $Tag" }
    if ($CodeCoverage) { $command += " --code-coverage" }
    $command += " --definition-file $ScratchOrgDefinitionFile"

    if (($InstallationKeyBypass) -or (! $InstallationKey)) {
        $command += " --installation-key-bypass"
    } else {
        $command += " --installation-key $InstallationKey"
    }

    if ($SkipValidation) { $command += " --skip-validation" }
    if ($WaitMinutes) { $command += " --wait $WaitMinutes" }
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }

    $command += " --json"
    $result = Invoke-Salesforce -Verbose -Command $command
    return Show-SalesforceResult -Result $result
}

function Promote-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )

    $command = "sf package version promote"
    $command += " --package $PackageVersionId"
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }
    if ($NoPrompt) { $command += " --no-prompt" }
    $command += " --json"

    $result = Invoke-Salesforce -Verbose -Command $command
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )

    $command = "sf package version delete"
    $command += " --package $PackageVersionId"
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }
    if ($NoPrompt) { $command += " --no-prompt" }
    $command += " --json"

    $result = Invoke-Salesforce -Verbose -Command $command
    return Show-SalesforceResult -Result $result
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

    $command = "sf package install"
    $command += " --package $PackageVersionId"
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    if ($NoPrompt) { $command += " --no-prompt" }
    if ($SecurityType) { $command += " --security-type $SecurityType" }
    if ($WaitMinutes) {
        $command += " --wait $WaitMinutes"
        $command += " --publish-wait $WaitMinutes"
    }
    Invoke-Salesforce -Verbose -Command $command
}

#endregion
