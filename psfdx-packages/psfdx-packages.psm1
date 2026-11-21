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
    <#
    .SYNOPSIS
    Lists the packages in a Dev Hub.

    .DESCRIPTION
    Runs sf package list and returns one object per package.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .PARAMETER ExtendedPackageDetails
    Display extended package detail. Adds --verbose.

    .EXAMPLE
    Get-SalesforcePackages -TargetDevHub devhub
    Every package in the Dev Hub.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf package list (plugin @salesforce/plugin-packaging)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetDevHub = --target-dev-hub; -ExtendedPackageDetails = --verbose.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-packaging

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Finds one package by name.

    .DESCRIPTION
    Lists the packages with Get-SalesforcePackages and returns the one whose name matches exactly, or nothing.

    .PARAMETER Name
    Exact name of the package. Required.

    .PARAMETER TargetDevHub
    Passed on to Get-SalesforcePackages -TargetDevHub.

    .PARAMETER ExtendedPackageDetails
    Passed on to Get-SalesforcePackages -ExtendedPackageDetails.

    .EXAMPLE
    Get-SalesforcePackage -Name MyPackage -TargetDevHub devhub
    The package record.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Get-SalesforcePackages. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Creates a package in a Dev Hub.

    .DESCRIPTION
    Runs sf package create. The package type is unlocked or managed.

    .PARAMETER Name
    Name of the package to create. Passed to sf as --name. Required.

    .PARAMETER PackageType
    Type of package. Passed to sf as --package-type. Default: "Unlocked". Valid values: Managed, Unlocked.

    .PARAMETER IsOrgDependent
    Depends on unpackaged metadata in the installation org; applies to unlocked packages only. Adds --org-dependent.

    .PARAMETER Path
    Path to directory that contains the contents of the package. Passed to sf as --path. Default: "force-app/main/default".

    .PARAMETER Description
    Description of the package. Passed to sf as --description.

    .PARAMETER ErrorNotificationUsername
    Active Dev Hub user designated to receive email notifications for package errors. Passed to sf as --error-notification-username.

    .PARAMETER NoNamespace
    Create the package with no namespace; available only for unlocked packages. Adds --no-namespace.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    New-SalesforcePackage -Name MyPackage -PackageType Unlocked -Path force-app -TargetDevHub devhub
    An unlocked package for the force-app folder.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf package create (plugin @salesforce/plugin-packaging)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -PackageType = --package-type; -IsOrgDependent = --org-dependent; -Path = --path; -Description = --description; -ErrorNotificationUsername = --error-notification-username; -NoNamespace = --no-namespace; -TargetDevHub = --target-dev-hub.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-packaging

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Deletes a package.

    .DESCRIPTION
    Runs sf package delete. Asks for confirmation and supports -WhatIf.

    .PARAMETER Name
    ID (starts with 0Ho) or alias of the package to delete. Passed to sf as --package. Required.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .PARAMETER NoPrompt
    Don't prompt before deleting the package. Adds --no-prompt.

    .EXAMPLE
    Remove-SalesforcePackage -Name MyPackage -TargetDevHub devhub -WhatIf
    Preview the delete.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf package delete (plugin @salesforce/plugin-packaging)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --package; -TargetDevHub = --target-dev-hub; -NoPrompt = --no-prompt.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-packaging

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Lists the packages installed in an org.

    .DESCRIPTION
    Runs sf package installed list and returns one object per installed package version.

    .PARAMETER TargetOrg
    Username or alias of the org. If omitted, the Salesforce CLI uses the default target org. Passed to sf as --target-org.

    .PARAMETER ApiVersion
    REST API version to use for the request, for example 62.0. Passed as --api-version; this is the one cmdlet that exposes it.

    .EXAMPLE
    Get-SalesforcePackagesInstalled -TargetOrg dev1
    What is installed.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf package installed list (plugin @salesforce/plugin-packaging)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org; -ApiVersion = --api-version.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-packaging

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Lists package versions in a Dev Hub.

    .DESCRIPTION
    Runs sf package version list, for one package (by -PackageId or -PackageName) or for all. Pipe the result to Remove-SalesforcePackageVersion or Promote-SalesforcePackageVersion.

    .PARAMETER PackageId
    Comma-delimited list of packages (aliases or 0Ho IDs) to list. Passed to sf as --packages.

    .PARAMETER PackageName
    Name of the package. psfdx finds its ID with Get-SalesforcePackage and passes it as --packages. Use instead of -PackageId.

    .PARAMETER Released
    Display released versions only (IsReleased=true). Adds --released.

    .PARAMETER Concise
    Display limited package version details. Adds --concise.

    .PARAMETER ExtendedDetails
    Display extended package version details. Adds --verbose.

    .PARAMETER ConversionsOnly
    Filter the list output to display only converted package version. Adds --show-conversions-only.

    .PARAMETER Branch
    Branch in your source control system used to filter the results; only package versions based on the specified branch are listed. Passed to sf as --branch.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Get-SalesforcePackageVersions -PackageName MyPackage -Released -TargetDevHub devhub
    Released versions of one package.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf package version list (plugin @salesforce/plugin-packaging)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --created-last-days, --modified-last-days, --order-by
    Parameter to flag: -PackageId = --packages; -Released = --released; -Concise = --concise; -ExtendedDetails = --verbose; -ConversionsOnly = --show-conversions-only; -Branch = --branch; -TargetDevHub = --target-dev-hub.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.
    Also calls these psfdx cmdlets: Get-SalesforcePackage.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-packaging

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Creates a package version.

    .DESCRIPTION
    Runs sf package version create. Without -WaitMinutes the request is queued and its ID (starts with 08c) is returned for Get-SalesforcePackageVersionCreateStatus.

    .PARAMETER PackageId
    ID (starts with 0Ho) or alias of the package to create a version of. Passed to sf as --package.

    .PARAMETER PackageName
    Name of the package. psfdx finds its ID with Get-SalesforcePackage and passes it as --package. Use instead of -PackageId.

    .PARAMETER Name
    Name of the package version to be created; overrides the sfdx-project.json value. Passed to sf as --version-name.

    .PARAMETER Description
    Description of the package version to be created; overrides the sfdx-project.json value. Passed to sf as --version-description.

    .PARAMETER Tag
    Package version's tag. Passed to sf as --tag.

    .PARAMETER InstallationKey
    Installation key for key-protected package. (either --installation-key or --installation-key-bypass is required).

    .PARAMETER InstallationKeyBypass
    Bypass the installation key requirement. (either --installation-key or --installation-key-bypass is required).

    .PARAMETER CodeCoverage
    Calculate and store the code coverage percentage by running the packaged Apex tests included in this package version. Adds --code-coverage.

    .PARAMETER SkipValidation
    Skip validation during package version creation; you can't promote unvalidated package versions. Adds --skip-validation.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the package version to be created. Passed to sf as --wait.

    .PARAMETER ScratchOrgDefinitionFile
    Path to a definition file similar to scratch org definition file that contains the list of features and org preferences that the metadata of the package version depends on. Passed to sf as --definition-file. Default: "config/project-scratch-def.json".

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    New-SalesforcePackageVersion -PackageName MyPackage -InstallationKeyBypass -WaitMinutes 30 -TargetDevHub devhub
    Create a version and wait.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf package version create (plugin @salesforce/plugin-packaging)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --async-validation, --branch, --generate-pkg-zip, --language, --path, --post-install-script, --post-install-url, --releasenotes-url, --skip-ancestor-check, --uninstall-script, --version-number
    Parameter to flag: -PackageId = --package; -Name = --version-name; -Description = --version-description; -Tag = --tag; -InstallationKey = --installation-key; -InstallationKeyBypass = --installation-key-bypass; -CodeCoverage = --code-coverage; -SkipValidation = --skip-validation; -WaitMinutes = --wait; -ScratchOrgDefinitionFile = --definition-file; -TargetDevHub = --target-dev-hub.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.
    Also calls these psfdx cmdlets: Get-SalesforcePackage.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-packaging

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Promotes a package version to released (sf package version promote).

    .DESCRIPTION
    Promotion cannot be undone: a released version can no longer be deleted. The cmdlet asks for confirmation and supports -WhatIf. -NoPrompt means you have
    already decided (as it does for the CLI), so it skips the confirmation and keeps existing unattended scripts working; -WhatIf still makes no call.
    -PackageVersionId can come from the pipeline, through the SubscriberPackageVersionId (04t) of a version from Get-SalesforcePackageVersions.

    .PARAMETER PackageVersionId
    ID (starts with 04t) or alias of the package version to promote. Passed to sf as --package. Required. Alias: SubscriberPackageVersionId. Accepts input from the pipeline by property name.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .PARAMETER NoPrompt
    Don't prompt to confirm setting the package version as released. Adds --no-prompt.

    .EXAMPLE
    Get-SalesforcePackageVersions -PackageName MyPkg | Select-Object -First 1 | Promote-SalesforcePackageVersion -WhatIf

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf package version promote (plugin @salesforce/plugin-packaging)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -PackageVersionId = --package; -TargetDevHub = --target-dev-hub; -NoPrompt = --no-prompt.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-packaging

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)][Alias('SubscriberPackageVersionId')][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    process {

        $arguments = @('package', 'version', 'promote')
        $arguments += @('--package', $PackageVersionId)
        if ($TargetDevHub) { $arguments += @('--target-dev-hub', $TargetDevHub) }
        if ($NoPrompt) { $arguments += '--no-prompt' }
        $arguments += '--json'
        $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
        $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
        # -NoPrompt is the caller's decision not to be asked; it does not turn off -WhatIf.
        if ($NoPrompt) { $ConfirmPreference = 'None' }
        if ($PSCmdlet.ShouldProcess($PackageVersionId, 'Promote package version (cannot be undone)')) {
            $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
            return Show-SalesforceResult -Result $result
        }
    }
}

function Remove-SalesforcePackageVersion {
    <#
    .SYNOPSIS
    Deletes a package version (sf package version delete).

    .DESCRIPTION
    -PackageVersionId can come from the pipeline: a version from Get-SalesforcePackageVersions is used through its SubscriberPackageVersionId (04t).
    Each version is confirmed on its own, so -WhatIf previews every delete.

    .PARAMETER PackageVersionId
    ID (starts with 04t) or alias of the package version to delete. Passed to sf as --package. Required. Alias: SubscriberPackageVersionId. Accepts input from the pipeline by property name.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .PARAMETER NoPrompt
    Don't prompt before deleting the package version. Adds --no-prompt.

    .EXAMPLE
    Get-SalesforcePackageVersions -PackageName MyPkg | Where-Object { -not $_.IsReleased } | Remove-SalesforcePackageVersion -WhatIf

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf package version delete (plugin @salesforce/plugin-packaging)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -PackageVersionId = --package; -TargetDevHub = --target-dev-hub; -NoPrompt = --no-prompt.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-packaging

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)][Alias('SubscriberPackageVersionId')][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    process {

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
}

function Install-SalesforcePackageVersion {
    <#
    .SYNOPSIS
    Installs a package version in an org.

    .DESCRIPTION
    Runs sf package install for a version ID (04t...). With -AsObject the result comes back as an object whose Id is the install request ID for Get-SalesforcePackageInstallStatus; without it the CLI's text is returned. Supports -WhatIf and -Confirm (no prompt by default).

    .PARAMETER PackageVersionId
    ID (starts with 04t) or alias of the package version to install. Passed to sf as --package. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .PARAMETER NoPrompt
    Don't prompt for confirmation. Adds --no-prompt.

    .PARAMETER WaitMinutes
    Maximum number of minutes to wait for the Subscriber Package Version ID to become available in the target org before canceling the install request. Passed to sf as --publish-wait. Default: 10.

    .PARAMETER SecurityType
    Security access type for the installed package. Available options are AdminsOnly and AllUsers. Passed to sf as --security-type. Default: AdminsOnly. Valid values: AllUsers, AdminsOnly.

    .PARAMETER AsObject
    Return the install request as an object (adds --json) instead of the CLI's text. Its Id, which starts with 0Hf, is the request ID for Get-SalesforcePackageInstallStatus.

    .EXAMPLE
    Install-SalesforcePackageVersion -PackageVersionId 04t000000000001AAA -TargetOrg dev1 -WhatIf
    Preview the install.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf package install (plugin @salesforce/plugin-packaging)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --apex-compile, --installation-key, --upgrade-type
    Parameter to flag: -PackageVersionId = --package; -TargetOrg = --target-org; -NoPrompt = --no-prompt; -WaitMinutes = --publish-wait; -SecurityType = --security-type; -AsObject = --json.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-packaging

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][int] $WaitMinutes = 10,
        [Parameter(Mandatory = $false)][ValidateSet('AllUsers','AdminsOnly')][string] $SecurityType = 'AdminsOnly',
        [Parameter(Mandatory = $false)][switch] $AsObject
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
    if ($AsObject) { $arguments += '--json' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $orgLabel = 'the default org'
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $orgLabel = $TargetOrg }
    if (-not $PSCmdlet.ShouldProcess("$PackageVersionId in $orgLabel", 'Install package version')) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    # Without -AsObject the CLI's own text is returned unchanged, as before. With it the install request comes back as an object: its Id (0Hf...)
    # is the request ID for Get-SalesforcePackageInstallStatus, so a later step can report the outcome.
    if ($AsObject) { return Show-SalesforceResult -Result $output }
    $output
}

#endregion

#region Package job reports

# Package creation and installation can run for a long time, so each has a "start" command that can return at once and a "report" command that
# fetches the outcome later, from another step or session. Capture the right ID from the start command:
#   New-SalesforcePackageVersion    -> the result's Id (starts with 08c) is the create REQUEST ID for Get-SalesforcePackageVersionCreateStatus
#   Install-SalesforcePackageVersion -AsObject -> the result's Id (starts with 0Hf) is the install REQUEST ID for Get-SalesforcePackageInstallStatus
# These are not the package version ID (04t) that you install; the request ID names the job.

function Get-SalesforcePackageVersionCreateStatus {
    <#
    .SYNOPSIS
    Gets the status of a package version create request (sf package version create report).

    .DESCRIPTION
    Pass the create request ID: the Id (08c...) of the object that New-SalesforcePackageVersion returned. It is asked of the Dev Hub that owns the
    package (-TargetDevHub). The result has Status, Completed and Succeeded, the IDs (RequestId, PackageId, PackageVersionId, SubscriberPackageVersionId,
    the 04t ID to install) and Errors, a list of messages when the job failed. A job still queued or running returns Completed = $false. A failed job
    is returned as a status (Status = Error) rather than thrown, so a script can read its Errors; add -ThrowOnFailure to make a failed job throw
    PsfdxPackageJobFailed after the object is written, for CI.

    .PARAMETER RequestId
    ID (starts with 08c) of the package version creation request you want to display. Passed to sf as --package-create-request-id. Required.

    .PARAMETER ThrowOnFailure
    Throw an error (id PsfdxPackageJobFailed) when the version creation failed, instead of returning it with its status. Meant for CI.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    $create = New-SalesforcePackageVersion -PackageName MyPkg -TargetDevHub devhub; Get-SalesforcePackageVersionCreateStatus -RequestId $create.Id -TargetDevHub devhub

    .EXAMPLE
    # In a later step: wait for success, then install the version
    $s = Get-SalesforcePackageVersionCreateStatus -RequestId 08c000000000001 -TargetDevHub devhub -ThrowOnFailure; $s.SubscriberPackageVersionId

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf package version create report (plugin @salesforce/plugin-packaging)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -RequestId = --package-create-request-id; -TargetDevHub = --target-dev-hub.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-packaging

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^08c[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $RequestId,
        [Parameter(Mandatory = $false)][switch] $ThrowOnFailure,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('package', 'version', 'create', 'report', '--package-create-request-id', $RequestId)
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('ThrowOnFailure')
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $data = Show-SalesforceResult -Result $result
    $record = @($data)[0]
    if ($null -eq $record -or $null -eq $record.PSObject.Properties['Status']) { throw "The Salesforce CLI returned no status for package create request $RequestId." }

    $get = { param([string] $Name) if ($null -ne $record.PSObject.Properties[$Name]) { return $record.$Name } return $null }
    $status = [string] $record.Status
    $errors = @(& $get 'Error' | Where-Object { $_ } | ForEach-Object { [string] $_ })
    $succeeded = ($status -eq 'Success')
    $failed = ($status -eq 'Error')
    $out = [pscustomobject]@{
        RequestId                  = [string] (& $get 'Id')
        Status                     = $status
        Completed                  = ($succeeded -or $failed)
        Succeeded                  = $succeeded
        PackageId                  = & $get 'Package2Id'
        PackageVersionId           = & $get 'Package2VersionId'
        SubscriberPackageVersionId = & $get 'SubscriberPackageVersionId'
        Tag                        = & $get 'Tag'
        Branch                     = & $get 'Branch'
        CreatedDate                = & $get 'CreatedDate'
        Errors                     = $errors
    }
    $out
    if ($ThrowOnFailure -and $failed) {
        $message = "Package version create request $RequestId failed."
        if ($errors.Count -gt 0) { $message += ' ' + (($errors | Select-Object -First 5) -join '; ') }
        $record2 = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException $message), 'PsfdxPackageJobFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $out)
        throw $record2
    }
}

function Get-SalesforcePackageInstallStatus {
    <#
    .SYNOPSIS
    Gets the status of a package install request (sf package install report).

    .DESCRIPTION
    Pass the install request ID: the Id (0Hf...) of the object that Install-SalesforcePackageVersion returned when run with -AsObject. The result has
    Status (IN_PROGRESS, SUCCESS, ERROR or UNKNOWN), Completed, Succeeded, the SubscriberPackageVersionKey (04t) and Errors. A job still running returns
    Completed = $false. A failed install is returned as a status with its Errors; add -ThrowOnFailure to make it throw PsfdxPackageJobFailed after the
    object is written. The report is read from the org the package is being installed into (-TargetOrg).

    .PARAMETER RequestId
    ID of the package install request you want to check; starts with 0Hf. Passed to sf as --request-id. Required.

    .PARAMETER ThrowOnFailure
    Throw an error (id PsfdxPackageJobFailed) when the installation failed, instead of returning it with Status ERROR. Meant for CI.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    $install = Install-SalesforcePackageVersion -PackageVersionId 04t000000000001 -WaitMinutes 0 -NoPrompt -AsObject -TargetOrg myorg; Get-SalesforcePackageInstallStatus -RequestId $install.Id -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf package install report (plugin @salesforce/plugin-packaging)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -RequestId = --request-id; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-packaging

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^0Hf[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $RequestId,
        [Parameter(Mandatory = $false)][switch] $ThrowOnFailure,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('package', 'install', 'report', '--request-id', $RequestId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('ThrowOnFailure')
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams

    $text = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string] $_ })).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'sf package install report returned no output where JSON was expected.' }
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop } catch { throw 'sf package install report returned output that is not valid JSON.' }
    if ($null -eq $parsed -or $parsed -is [array] -or $null -eq $parsed.PSObject.Properties['status']) { throw 'sf package install report returned JSON in an unexpected shape (no status).' }

    $record = $null
    $errors = @()
    $status = $null
    if ($parsed.status -eq 0 -and $null -ne $parsed.PSObject.Properties['result'] -and $null -ne $parsed.result) {
        $record = $parsed.result
        $status = [string] $record.Status
        if ($null -ne $record.PSObject.Properties['Errors'] -and $null -ne $record.Errors -and $null -ne $record.Errors.PSObject.Properties['errors']) {
            $errors = @($record.Errors.errors | ForEach-Object { if ($null -ne $_.PSObject.Properties['message']) { [string] $_.message } else { [string] $_ } })
        }
    } elseif ($parsed.status -ne 0 -and (
            (($null -ne $parsed.PSObject.Properties['name']) -and ([string] $parsed.name -eq 'packageInstallError')) -or
            (($null -ne $parsed.PSObject.Properties['message']) -and ([string] $parsed.message -match '(?i)errors installing the package|installation errors:|package installation failed')))) {
        # A failed install makes the CLI exit with an error (name packageInstallError, "Encountered errors installing the package! ...") rather than
        # a result: report it as a status, not a lost job. The numbered errors are listed in the message, or it says <empty> when there are none.
        $status = 'ERROR'
        $message = ''
        if ($null -ne $parsed.PSObject.Properties['message'] -and $parsed.message) { $message = [string] $parsed.message }
        $errors = @([regex]::Matches($message, '(?m)^\s*\d+\)\s*(.+)$') | ForEach-Object { $_.Groups[1].Value.Trim() })
    } else {
        Show-SalesforceResult -Result $text | Out-Null
        throw "sf package install report returned no install request for $RequestId."
    }

    $key = $null
    if ($null -ne $record -and $null -ne $record.PSObject.Properties['SubscriberPackageVersionKey']) { $key = $record.SubscriberPackageVersionKey }
    $id = $RequestId
    if ($null -ne $record -and $null -ne $record.PSObject.Properties['Id'] -and $record.Id) { $id = [string] $record.Id }
    $succeeded = ($status -eq 'SUCCESS')
    $failed = ($status -eq 'ERROR')
    $out = [pscustomobject]@{
        RequestId                  = $id
        Status                     = $status
        Completed                  = ($succeeded -or $failed)
        Succeeded                  = $succeeded
        SubscriberPackageVersionKey = $key
        Errors                     = $errors
    }
    $out
    if ($ThrowOnFailure -and $failed) {
        $summary = "Package install request $RequestId failed."
        if ($errors.Count -gt 0) { $summary += ' ' + (($errors | Select-Object -First 5) -join '; ') }
        $record2 = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException $summary), 'PsfdxPackageJobFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $out)
        throw $record2
    }
}

#endregion
