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
    #   Whichever copy is chosen, its helpers are then bound as private functions of the importing module (see $bindHelpers below).
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

    # psfdx-shared exports nothing, so none of its helpers is a public command (Get-Command -Module psfdx* never lists them).
    # Each module binds the helpers it needs as private functions of its own: a function keeps running in psfdx-shared's own scope,
    # so the helpers still reach each other, and the importing module's manifest decides which of them it exports (the public ones
    # that belong to the core module). Nothing is copied, so a fix in psfdx-shared reaches every module.
    $bindHelpers = {
        param([System.Management.Automation.PSModuleInfo] $Shared)
        $helpers = & $Shared { param($Name) Get-ChildItem -Path function: | Where-Object { $_.ModuleName -eq $Name } } $Shared.Name
        foreach ($helper in $helpers) { Set-Item -Path ('function:script:' + $helper.Name) -Value $helper.ScriptBlock }
    }

    $loaded = @(Get-Module -Name $ModuleName -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending)
    $loadedCompatible = @($loaded | Where-Object { & $isCompatible $_.Version }) | Select-Object -First 1
    if ($loadedCompatible) {
        Import-Module -ModuleInfo $loadedCompatible -ErrorAction Stop
        & $bindHelpers $loadedCompatible
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
            $imported = Import-Module -Name $match.Path -ErrorAction Stop -PassThru
            & $bindHelpers $imported
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

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package list (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetDevHub = --target-dev-hub; -ExtendedPackageDetails = --verbose.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .PARAMETER ExtendedPackageDetails
    Display extended package detail. Adds --verbose.

    .EXAMPLE
    Get-SalesforcePackages -TargetDevHub devhub
    Every package in the Dev Hub.

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

    SALESFORCE CLI
        This cmdlet does not run an sf command.
        It is built on other psfdx cmdlets: Get-SalesforcePackages. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .PARAMETER Name
    Exact name of the package. Required.

    .PARAMETER TargetDevHub
    Passed on to Get-SalesforcePackages -TargetDevHub.

    .PARAMETER ExtendedPackageDetails
    Passed on to Get-SalesforcePackages -ExtendedPackageDetails.

    .EXAMPLE
    Get-SalesforcePackage -Name MyPackage -TargetDevHub devhub
    The package record.

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

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package create (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Name = --name; -PackageType = --package-type; -IsOrgDependent = --org-dependent; -Path = --path; -Description = --description; -ErrorNotificationUsername = --error-notification-username; -NoNamespace = --no-namespace; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

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

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package delete (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Name = --package; -TargetDevHub = --target-dev-hub; -NoPrompt = --no-prompt.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

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

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package installed list (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetOrg = --target-org; -ApiVersion = --api-version.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetOrg
    Username or alias of the org. If omitted, the Salesforce CLI uses the default target org. Passed to sf as --target-org.

    .PARAMETER ApiVersion
    REST API version to use for the request, for example 62.0. Passed as --api-version; this is the one cmdlet that exposes it.

    .EXAMPLE
    Get-SalesforcePackagesInstalled -TargetOrg dev1
    What is installed.

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

function Convert-SalesforcePackage {
    <#
    .SYNOPSIS
    Converts a first-generation managed package into a second-generation managed package.

    .DESCRIPTION
    Runs sf package convert. The first-generation package must be managed and released (it has a released version). The conversion creates a second-generation package and a first package version in the Dev Hub; it can take a long time, so give -WaitMinutes or follow up with Get-SalesforcePackageVersionCreateStatus. Supports -WhatIf and -Confirm; it does not prompt by default.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package convert (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Package = --package; -DefinitionFile = --definition-file; -InstallationKey = --installation-key; -InstallationKeyBypass = --installation-key-bypass; -CodeCoverage = --code-coverage; -PatchVersion = --patch-version; -SeedMetadata = --seed-metadata; -ExtendedDetails = --verbose; -WaitMinutes = --wait; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Package
    ID of the first-generation managed package to convert (starts with 033). Passed to sf as --package. Required.

    .PARAMETER DefinitionFile
    Path to a scratch org definition file used to validate the converted package version. The file must exist. Passed to sf as --definition-file.

    .PARAMETER InstallationKey
    Installation key for the converted package version, a password that subscribers give when they install it. Give -InstallationKey or -InstallationKeyBypass, not both. Passed to sf as --installation-key.

    .PARAMETER InstallationKeyBypass
    Do not protect the converted package version with an installation key. Adds --installation-key-bypass.

    .PARAMETER CodeCoverage
    Calculate and store the code coverage of the converted package version. Adds --code-coverage.

    .PARAMETER PatchVersion
    Patch version number to give the converted package version. Passed to sf as --patch-version.

    .PARAMETER SeedMetadata
    Folder of metadata to include in the converted package version, which is not part of the first-generation package. The folder must exist. Passed to sf as --seed-metadata.

    .PARAMETER ExtendedDetails
    Show extended details of the conversion. Adds --verbose.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the conversion to finish. Passed to sf as --wait.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Convert-SalesforcePackage -Package 033xx0000000001AAA -InstallationKeyBypass -WaitMinutes 30 -TargetDevHub devhub
    Convert the package and wait up to 30 minutes.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

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
        [Parameter(Mandatory = $true)][ValidatePattern('^033[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $Package,
        [Parameter(Mandatory = $false)][string] $DefinitionFile,
        [Parameter(Mandatory = $false)][string] $InstallationKey,
        [Parameter(Mandatory = $false)][switch] $InstallationKeyBypass,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][string] $PatchVersion,
        [Parameter(Mandatory = $false)][string] $SeedMetadata,
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    if ($InstallationKey -and $InstallationKeyBypass) { throw 'Give -InstallationKey or -InstallationKeyBypass, not both.' }
    if ($DefinitionFile -and -not (Test-Path -LiteralPath $DefinitionFile -PathType Leaf)) { throw "Definition file '$DefinitionFile' does not exist." }
    if ($SeedMetadata -and -not (Test-Path -LiteralPath $SeedMetadata -PathType Container)) { throw "Seed metadata folder '$SeedMetadata' does not exist." }
    $arguments = @('package', 'convert', '--package', $Package)
    if ($DefinitionFile) { $arguments += @('--definition-file', $DefinitionFile) }
    if ($InstallationKey) { $arguments += @('--installation-key', $InstallationKey) }
    if ($InstallationKeyBypass) { $arguments += '--installation-key-bypass' }
    if ($CodeCoverage) { $arguments += '--code-coverage' }
    if ($PatchVersion) { $arguments += @('--patch-version', $PatchVersion) }
    if ($SeedMetadata) { $arguments += @('--seed-metadata', $SeedMetadata) }
    if ($ExtendedDetails) { $arguments += '--verbose' }
    if ($WaitMinutes) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess("first-generation package $Package", 'Convert to a second-generation package')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Update-SalesforcePackage {
    <#
    .SYNOPSIS
    Changes the details of a package in the Dev Hub.

    .DESCRIPTION
    Runs sf package update. Only the properties you give are changed. Supports -WhatIf and -Confirm; it does not prompt by default.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package update (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Package = --package; -Name = --name; -Description = --description; -ErrorNotificationUsername = --error-notification-username; -EnableAppAnalytics = --enable-app-analytics; -RecommendedVersionId = --recommended-version-id; -SkipAncestorCheck = --skip-ancestor-check; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Package
    ID (starts with 0Ho) or alias of the package to update. Passed to sf as --package. Required.

    .PARAMETER Name
    New name of the package. Passed to sf as --name.

    .PARAMETER Description
    New description of the package. Passed to sf as --description.

    .PARAMETER ErrorNotificationUsername
    User name of the person who gets emails when a package error happens, such as a failed subscriber install. Passed to sf as --error-notification-username.

    .PARAMETER EnableAppAnalytics
    Turn on AppExchange App Analytics for the managed package. Adds --enable-app-analytics.

    .PARAMETER RecommendedVersionId
    ID of the package version to recommend to subscribers, starting with 04t. Passed to sf as --recommended-version-id.

    .PARAMETER SkipAncestorCheck
    Do not check that the recommended version has the right ancestor. Adds --skip-ancestor-check.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Update-SalesforcePackage -Package MyPkg -Description 'Core features' -TargetDevHub devhub -WhatIf
    Preview the change without making it.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

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
        [Parameter(Mandatory = $true)][string] $Package,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $ErrorNotificationUsername,
        [Parameter(Mandatory = $false)][switch] $EnableAppAnalytics,
        [Parameter(Mandatory = $false)][ValidatePattern('^04t[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $RecommendedVersionId,
        [Parameter(Mandatory = $false)][switch] $SkipAncestorCheck,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('package', 'update', '--package', $Package)
    if ($Name) { $arguments += @('--name', $Name) }
    if ($Description) { $arguments += @('--description', $Description) }
    if ($ErrorNotificationUsername) { $arguments += @('--error-notification-username', $ErrorNotificationUsername) }
    if ($EnableAppAnalytics) { $arguments += '--enable-app-analytics' }
    if ($RecommendedVersionId) { $arguments += @('--recommended-version-id', $RecommendedVersionId) }
    if ($SkipAncestorCheck) { $arguments += '--skip-ancestor-check' }
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($Package, 'Update package')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Uninstall-SalesforcePackage {
    <#
    .SYNOPSIS
    Uninstalls a second-generation package from an org.

    .DESCRIPTION
    Runs sf package uninstall. The package version and its components are removed from the org, which can delete data stored in the package's custom objects. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. Without -WaitMinutes the request is made and returned; follow it with Get-SalesforcePackageUninstallStatus.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package uninstall (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Package = --package; -WaitMinutes = --wait; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Package
    ID (starts with 04t) or alias of the package version to uninstall. Passed to sf as --package. Required.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the uninstall to finish. Passed to sf as --wait.

    .PARAMETER NoPrompt
    Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Uninstall-SalesforcePackage -Package 04txx0000000001AAA -WaitMinutes 10 -TargetOrg dev1 -WhatIf
    Preview the uninstall without starting it.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

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
        [Parameter(Mandatory = $true)][string] $Package,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('package', 'uninstall', '--package', $Package)
    if ($WaitMinutes) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    # -NoPrompt is the caller's decision not to be asked; it does not turn off -WhatIf.
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    $orgLabel = 'the default org'
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $orgLabel = "org $TargetOrg" }
    if (-not $PSCmdlet.ShouldProcess("$Package in $orgLabel", 'Uninstall package')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region Package Versions

function Get-SalesforcePackageVersions {
    <#
    .SYNOPSIS
    Lists package versions in a Dev Hub.

    .DESCRIPTION
    Runs sf package version list, for one package (by -PackageId or -PackageName) or for all. Pipe the result to Remove-SalesforcePackageVersion or Promote-SalesforcePackageVersion.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package version list (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PackageId = --packages; -Released = --released; -Concise = --concise; -ExtendedDetails = --verbose; -ConversionsOnly = --show-conversions-only; -Branch = --branch; -CreatedLastDays = --created-last-days; -ModifiedLastDays = --modified-last-days; -OrderBy = --order-by; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.
        Also calls these psfdx cmdlets: Get-SalesforcePackage.

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

    .PARAMETER CreatedLastDays
    Only versions created in the last this many days. 0 means today. Passed to sf as --created-last-days.

    .PARAMETER ModifiedLastDays
    Only versions modified in the last this many days. 0 means today. Passed to sf as --modified-last-days.

    .PARAMETER OrderBy
    Package version fields to order the list by, separated by commas, for example PatchVersion,MajorVersion. Passed to sf as --order-by.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Get-SalesforcePackageVersions -PackageName MyPackage -Released -TargetDevHub devhub
    Released versions of one package.

    .EXAMPLE
    Get-SalesforcePackageVersions -PackageName MyPackage -CreatedLastDays 30 -OrderBy CreatedDate -TargetDevHub devhub
    Versions made in the last 30 days.

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
        [Parameter(Mandatory = $false)][ValidateRange(0, 3650)][int] $CreatedLastDays,
        [Parameter(Mandatory = $false)][ValidateRange(0, 3650)][int] $ModifiedLastDays,
        [Parameter(Mandatory = $false)][string] $OrderBy,
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
    if ($PSBoundParameters.ContainsKey('CreatedLastDays')) { $arguments += @('--created-last-days', $CreatedLastDays) }
    if ($PSBoundParameters.ContainsKey('ModifiedLastDays')) { $arguments += @('--modified-last-days', $ModifiedLastDays) }
    if ($OrderBy) { $arguments += @('--order-by', $OrderBy) }
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

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package version create (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PackageId = --package; -Name = --version-name; -Description = --version-description; -Tag = --tag; -InstallationKey = --installation-key; -InstallationKeyBypass = --installation-key-bypass; -CodeCoverage = --code-coverage; -SkipValidation = --skip-validation; -WaitMinutes = --wait; -ScratchOrgDefinitionFile = --definition-file; -Path = --path; -Branch = --branch; -VersionNumber = --version-number; -Language = --language; -PostInstallScript = --post-install-script; -UninstallScript = --uninstall-script; -PostInstallUrl = --post-install-url; -ReleaseNotesUrl = --releasenotes-url; -SkipAncestorCheck = --skip-ancestor-check; -AsyncValidation = --async-validation; -GeneratePackageZip = --generate-pkg-zip; -ExtendedDetails = --verbose; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.
        Also calls these psfdx cmdlets: Get-SalesforcePackage.

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

    .PARAMETER Path
    Path to the directory that contains the contents of the package version, as an alternative to -PackageId or -PackageName. Passed to sf as --path. The directory must exist.

    .PARAMETER Branch
    Name of the branch in your source control system that the package version is created from. Passed to sf as --branch.

    .PARAMETER VersionNumber
    Version number of the package version, for example 1.2.0.NEXT. Overrides the sfdx-project.json value. Passed to sf as --version-number.

    .PARAMETER Language
    Language of the package version's metadata, as a language code such as en_US. Passed to sf as --language.

    .PARAMETER PostInstallScript
    Name of the Apex class that runs after the package is installed (managed packages only). Passed to sf as --post-install-script.

    .PARAMETER UninstallScript
    Name of the Apex class that runs when the package is uninstalled (managed packages only). Passed to sf as --uninstall-script.

    .PARAMETER PostInstallUrl
    URL of the post-install instructions. Passed to sf as --post-install-url.

    .PARAMETER ReleaseNotesUrl
    URL of the release notes. Passed to sf as --releasenotes-url.

    .PARAMETER SkipAncestorCheck
    Do not check that the new version has the right ancestor. Adds --skip-ancestor-check.

    .PARAMETER AsyncValidation
    Return the version as soon as it is created and run the validation, including the Apex tests, in the background. Adds --async-validation.

    .PARAMETER GeneratePackageZip
    Also create a zip file of the package contents and keep it, for managed package versions. Adds --generate-pkg-zip.

    .PARAMETER ExtendedDetails
    Show extended details of the version creation. Adds --verbose.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    New-SalesforcePackageVersion -PackageName MyPackage -InstallationKeyBypass -WaitMinutes 30 -TargetDevHub devhub
    Create a version and wait.

    .EXAMPLE
    New-SalesforcePackageVersion -PackageName MyPackage -InstallationKeyBypass -Branch main -VersionNumber 1.4.0.NEXT -AsyncValidation -TargetDevHub devhub
    Create a version from the main branch and let the validation run in the background.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

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
        [Parameter(Mandatory = $false)][string] $Path,
        [Parameter(Mandatory = $false)][string] $Branch,
        [Parameter(Mandatory = $false)][string] $VersionNumber,
        [Parameter(Mandatory = $false)][string] $Language,
        [Parameter(Mandatory = $false)][string] $PostInstallScript,
        [Parameter(Mandatory = $false)][string] $UninstallScript,
        [Parameter(Mandatory = $false)][string] $PostInstallUrl,
        [Parameter(Mandatory = $false)][string] $ReleaseNotesUrl,
        [Parameter(Mandatory = $false)][switch] $SkipAncestorCheck,
        [Parameter(Mandatory = $false)][switch] $AsyncValidation,
        [Parameter(Mandatory = $false)][switch] $GeneratePackageZip,
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )

    if ((! $PackageId ) -and (! $PackageName) -and (! $Path)) {
        throw "Please provide a PackageId, a Package Name or a Path"
    }
    if ($Path -and -not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Path '$Path' does not exist."
    }
    if ((! $PackageId ) -and ($PackageName) ) {
        if ($TargetDevHub) {
            $package = Get-SalesforcePackage -Name $PackageName -TargetDevHub $TargetDevHub
        } else {
            $package = Get-SalesforcePackage -Name $PackageName
        }
        $PackageId = $package.Id
    }

    $arguments = @('package', 'version', 'create')
    if ($PackageId) { $arguments += @('--package', $PackageId) }
    if ($Path) { $arguments += @('--path', $Path) }
    if ($Branch) { $arguments += @('--branch', $Branch) }
    if ($VersionNumber) { $arguments += @('--version-number', $VersionNumber) }
    if ($Language) { $arguments += @('--language', $Language) }
    if ($PostInstallScript) { $arguments += @('--post-install-script', $PostInstallScript) }
    if ($UninstallScript) { $arguments += @('--uninstall-script', $UninstallScript) }
    if ($PostInstallUrl) { $arguments += @('--post-install-url', $PostInstallUrl) }
    if ($ReleaseNotesUrl) { $arguments += @('--releasenotes-url', $ReleaseNotesUrl) }
    if ($SkipAncestorCheck) { $arguments += '--skip-ancestor-check' }
    if ($AsyncValidation) { $arguments += '--async-validation' }
    if ($GeneratePackageZip) { $arguments += '--generate-pkg-zip' }
    if ($ExtendedDetails) { $arguments += '--verbose' }
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

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package version promote (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PackageVersionId = --package; -TargetDevHub = --target-dev-hub; -NoPrompt = --no-prompt.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PackageVersionId
    ID (starts with 04t) or alias of the package version to promote. Passed to sf as --package. Required. Alias: SubscriberPackageVersionId. Accepts input from the pipeline by property name.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .PARAMETER NoPrompt
    Don't prompt to confirm setting the package version as released. Adds --no-prompt.

    .EXAMPLE
    Get-SalesforcePackageVersions -PackageName MyPkg | Select-Object -First 1 | Promote-SalesforcePackageVersion -WhatIf

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

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package version delete (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PackageVersionId = --package; -TargetDevHub = --target-dev-hub; -NoPrompt = --no-prompt.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PackageVersionId
    ID (starts with 04t) or alias of the package version to delete. Passed to sf as --package. Required. Alias: SubscriberPackageVersionId. Accepts input from the pipeline by property name.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .PARAMETER NoPrompt
    Don't prompt before deleting the package version. Adds --no-prompt.

    .EXAMPLE
    Get-SalesforcePackageVersions -PackageName MyPkg | Where-Object { -not $_.IsReleased } | Remove-SalesforcePackageVersion -WhatIf

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

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package install (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PackageVersionId = --package; -TargetOrg = --target-org; -NoPrompt = --no-prompt; -WaitMinutes = --publish-wait; -SecurityType = --security-type; -AsObject = --json; -ApexCompile = --apex-compile; -InstallationKey = --installation-key; -UpgradeType = --upgrade-type.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

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

    .PARAMETER ApexCompile
    Compile all the Apex in the org and the package, or only the Apex in the package, after the install. Passed to sf as --apex-compile. Valid values: all, package. The CLI default is all.

    .PARAMETER InstallationKey
    Installation key of the package version, for a version that is protected by one. Passed to sf as --installation-key.

    .PARAMETER UpgradeType
    What happens to the components that an upgrade removes. Passed to sf as --upgrade-type. Valid values: DeprecateOnly, Mixed, Delete. The CLI default is Mixed. Only used for an upgrade of an unlocked package.

    .EXAMPLE
    Install-SalesforcePackageVersion -PackageVersionId 04t000000000001AAA -TargetOrg dev1 -WhatIf
    Preview the install.

    .EXAMPLE
    Install-SalesforcePackageVersion -PackageVersionId 04t000000000001AAA -InstallationKey $key -ApexCompile package -UpgradeType DeprecateOnly -TargetOrg dev1
    Upgrade an unlocked package, deprecate instead of deleting what it removes, and compile only the package's Apex.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

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
        [Parameter(Mandatory = $false)][switch] $AsObject,
        [Parameter(Mandatory = $false)][ValidateSet('all', 'package')][string] $ApexCompile,
        [Parameter(Mandatory = $false)][string] $InstallationKey,
        [Parameter(Mandatory = $false)][ValidateSet('DeprecateOnly', 'Mixed', 'Delete')][string] $UpgradeType
    )

    $arguments = @('package', 'install')
    $arguments += @('--package', $PackageVersionId)
    if ($ApexCompile) { $arguments += @('--apex-compile', $ApexCompile) }
    if ($InstallationKey) { $arguments += @('--installation-key', $InstallationKey) }
    if ($UpgradeType) { $arguments += @('--upgrade-type', $UpgradeType) }
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

function Get-SalesforcePackageVersion {
    <#
    .SYNOPSIS
    Shows the details of one package version.

    .DESCRIPTION
    Runs sf package version report and returns the version's details (version number, branch, tag, code coverage, validation state, ancestor and more). It only reads. Use Get-SalesforcePackageVersions to list versions.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package version report (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PackageVersionId = --package; -ExtendedDetails = --verbose; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PackageVersionId
    ID (starts with 04t) or alias of the package version. Passed to sf as --package. Required.

    .PARAMETER ExtendedDetails
    Show extended details, such as the package version's ancestry. Adds --verbose.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Get-SalesforcePackageVersion -PackageVersionId 04txx0000000001AAA -TargetDevHub devhub
    The details of one version.

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
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('package', 'version', 'report', '--package', $PackageVersionId)
    if ($ExtendedDetails) { $arguments += '--verbose' }
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Update-SalesforcePackageVersion {
    <#
    .SYNOPSIS
    Changes the details of a package version.

    .DESCRIPTION
    Runs sf package version update. Only the properties you give are changed. A released version can change only some of them. Supports -WhatIf and -Confirm; it does not prompt by default.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package version update (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PackageVersionId = --package; -Branch = --branch; -InstallationKey = --installation-key; -Tag = --tag; -Description = --version-description; -Name = --version-name; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PackageVersionId
    ID (starts with 04t) or alias of the package version to update. Passed to sf as --package. Required.

    .PARAMETER Branch
    New branch of the package version. Passed to sf as --branch.

    .PARAMETER InstallationKey
    New installation key, a password that subscribers give when they install the version. Passed to sf as --installation-key.

    .PARAMETER Tag
    New tag of the package version. Passed to sf as --tag.

    .PARAMETER Description
    New description of the package version. Passed to sf as --version-description.

    .PARAMETER Name
    New name of the package version. Passed to sf as --version-name.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Update-SalesforcePackageVersion -PackageVersionId 04txx0000000001AAA -Tag release-1 -TargetDevHub devhub
    Tag a version.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

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
        [Parameter(Mandatory = $false)][string] $Branch,
        [Parameter(Mandatory = $false)][string] $InstallationKey,
        [Parameter(Mandatory = $false)][string] $Tag,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('package', 'version', 'update', '--package', $PackageVersionId)
    if ($Branch) { $arguments += @('--branch', $Branch) }
    if ($InstallationKey) { $arguments += @('--installation-key', $InstallationKey) }
    if ($Tag) { $arguments += @('--tag', $Tag) }
    if ($Description) { $arguments += @('--version-description', $Description) }
    if ($Name) { $arguments += @('--version-name', $Name) }
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($PackageVersionId, 'Update package version')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Retrieve-SalesforcePackageVersion {
    <#
    .SYNOPSIS
    Downloads the metadata of a package version into a folder.

    .DESCRIPTION
    Runs sf package version retrieve. It works only for second-generation managed package versions and unlocked package versions. The metadata is written under -OutputDir.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package version retrieve (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PackageVersionId = --package; -OutputDir = --output-dir; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PackageVersionId
    ID (starts with 04t) or alias of the package version to retrieve. Passed to sf as --package. Required.

    .PARAMETER OutputDir
    Folder to write the metadata to. By default the CLI uses a temporary folder and reports it. Passed to sf as --output-dir.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Retrieve-SalesforcePackageVersion -PackageVersionId 04txx0000000001AAA -OutputDir .\pkg-source -TargetDevHub devhub
    Download the version's metadata.

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
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('package', 'version', 'retrieve', '--package', $PackageVersionId)
    if ($OutputDir) { $arguments += @('--output-dir', $OutputDir) }
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforcePackageVersionAncestry {
    <#
    .SYNOPSIS
    Shows the ancestry tree of a second-generation managed package.

    .DESCRIPTION
    Runs sf package version displayancestry. The ancestry shows which version each version builds on. It works for second-generation managed packages. With -DotCode the result is DOT graph code that you can draw with Graphviz.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package version displayancestry (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Package = --package; -DotCode = --dot-code; -ExtendedDetails = --verbose; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Package
    ID (starts with 0Ho) or alias of the package, or ID (starts with 04t) or alias of a package version. Passed to sf as --package. Required.

    .PARAMETER DotCode
    Return the ancestry as DOT code for Graphviz. Adds --dot-code.

    .PARAMETER ExtendedDetails
    Show extended details of each version, such as its ID. Adds --verbose.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Get-SalesforcePackageVersionAncestry -Package MyManagedPkg -TargetDevHub devhub
    The ancestry tree of the package.

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
        [Parameter(Mandatory = $true)][string] $Package,
        [Parameter(Mandatory = $false)][switch] $DotCode,
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('package', 'version', 'displayancestry', '--package', $Package)
    if ($DotCode) { $arguments += '--dot-code' }
    if ($ExtendedDetails) { $arguments += '--verbose' }
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforcePackageVersionDependencies {
    <#
    .SYNOPSIS
    Shows the dependency graph of an unlocked or second-generation managed package version.

    .DESCRIPTION
    Runs sf package version displaydependencies. It lists the package versions that the version depends on. The package must have the dependencies set in its project file.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package version displaydependencies (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PackageVersionId = --package; -EdgeDirection = --edge-direction; -InstallationKey = --installation-key; -ExtendedDetails = --verbose; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PackageVersionId
    ID (starts with 04t) or alias of the package version. Passed to sf as --package. Required.

    .PARAMETER EdgeDirection
    Direction of the graph edges. Valid values: root-first, root-last. The CLI default is root-first. Passed to sf as --edge-direction.

    .PARAMETER InstallationKey
    Installation key of the package version, if it has one. Passed to sf as --installation-key.

    .PARAMETER ExtendedDetails
    Show extended details of each dependency. Adds --verbose.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Get-SalesforcePackageVersionDependencies -PackageVersionId 04txx0000000001AAA -TargetDevHub devhub
    What the version depends on.

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
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][ValidateSet('root-first', 'root-last')][string] $EdgeDirection,
        [Parameter(Mandatory = $false)][string] $InstallationKey,
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('package', 'version', 'displaydependencies', '--package', $PackageVersionId)
    if ($EdgeDirection) { $arguments += @('--edge-direction', $EdgeDirection) }
    if ($InstallationKey) { $arguments += @('--installation-key', $InstallationKey) }
    if ($ExtendedDetails) { $arguments += '--verbose' }
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
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

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package version create report (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -RequestId = --package-create-request-id; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

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

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package install report (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -RequestId = --request-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER RequestId
    ID of the package install request you want to check; starts with 0Hf. Passed to sf as --request-id. Required.

    .PARAMETER ThrowOnFailure
    Throw an error (id PsfdxPackageJobFailed) when the installation failed, instead of returning it with Status ERROR. Meant for CI.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    $install = Install-SalesforcePackageVersion -PackageVersionId 04t000000000001 -WaitMinutes 0 -NoPrompt -AsObject -TargetOrg myorg; Get-SalesforcePackageInstallStatus -RequestId $install.Id -TargetOrg myorg

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

function Get-SalesforcePackageVersionCreateRequests {
    <#
    .SYNOPSIS
    Lists the package version creation requests of a Dev Hub.

    .DESCRIPTION
    Runs sf package version create list and returns one object per request (ID, status, package, version, branch, created date). Use Get-SalesforcePackageVersionCreateStatus for one request.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package version create list (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -CreatedLastDays = --created-last-days; -ConversionsOnly = --show-conversions-only; -Status = --status; -ExtendedDetails = --verbose; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER CreatedLastDays
    Only requests created in the last this many days. 0 means today. Passed to sf as --created-last-days.

    .PARAMETER ConversionsOnly
    Only requests that convert a first-generation package. Adds --show-conversions-only.

    .PARAMETER Status
    Only requests with this status. Valid values: Queued, InProgress, Success, Error. Passed to sf as --status.

    .PARAMETER ExtendedDetails
    Show extended details of each request. Adds --verbose.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Get-SalesforcePackageVersionCreateRequests -Status Error -CreatedLastDays 7 -TargetDevHub devhub
    Version creations that failed this week.

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
        [Parameter(Mandatory = $false)][ValidateRange(0, 3650)][int] $CreatedLastDays,
        [Parameter(Mandatory = $false)][switch] $ConversionsOnly,
        [Parameter(Mandatory = $false)][ValidateSet('Queued', 'InProgress', 'Success', 'Error')][string] $Status,
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('package', 'version', 'create', 'list')
    if ($PSBoundParameters.ContainsKey('CreatedLastDays')) { $arguments += @('--created-last-days', $CreatedLastDays) }
    if ($ConversionsOnly) { $arguments += '--show-conversions-only' }
    if ($Status) { $arguments += @('--status', $Status) }
    if ($ExtendedDetails) { $arguments += '--verbose' }
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforcePackageUninstallStatus {
    <#
    .SYNOPSIS
    Shows the status of a package uninstall request.

    .DESCRIPTION
    Runs sf package uninstall report. The request ID comes from Uninstall-SalesforcePackage when it returned without waiting. It only reads.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package uninstall report (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -RequestId = --request-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER RequestId
    ID of the uninstall request, from Uninstall-SalesforcePackage. Passed to sf as --request-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforcePackageUninstallStatus -RequestId 06yxx0000000001AAA -TargetOrg dev1
    The state of the uninstall.

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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $RequestId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('package', 'uninstall', 'report', '--request-id', $RequestId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region Push Upgrades

function New-SalesforcePushUpgrade {
    <#
    .SYNOPSIS
    Schedules a push upgrade of a managed package version to subscriber orgs.

    .DESCRIPTION
    Runs sf package push-upgrade schedule. A push upgrade installs a package version in subscriber orgs without their admins starting it. It cannot be undone once it starts, though a request that has not started can be stopped with Stop-SalesforcePushUpgrade. Give the subscriber orgs as -OrgList or -OrgFile. Asks for confirmation and supports -WhatIf.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package push-upgrade schedule (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Package = --package; -OrgList = --org-list; -OrgFile = --org-file; -StartTime = --start-time; -MigrateTo2gp = --migrate-to-2gp; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Package
    ID (starts with 04t) or alias of the package version to push. Passed to sf as --package. Required.

    .PARAMETER OrgList
    IDs of the subscriber orgs to upgrade (start with 00D). Joined with commas. Passed to sf as --org-list.

    .PARAMETER OrgFile
    Path of a CSV file that lists the subscriber org IDs, one per line. The file must exist. Passed to sf as --org-file.

    .PARAMETER StartTime
    When to start the push upgrade, as a date and time. It is sent in UTC (a time without a time zone is read as local time). By default the upgrade starts as soon as possible. Passed to sf as --start-time.

    .PARAMETER MigrateTo2gp
    Migrate the subscriber orgs from a first-generation to a second-generation package. Adds --migrate-to-2gp.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    New-SalesforcePushUpgrade -Package 04txx0000000001AAA -OrgList 00Dxx0000000001, 00Dxx0000000002 -StartTime '2026-12-01 02:00' -TargetDevHub devhub -WhatIf
    Preview a scheduled push upgrade.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

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
        [Parameter(Mandatory = $true)][string] $Package,
        [Parameter(Mandatory = $false)][ValidatePattern('^00D[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string[]] $OrgList,
        [Parameter(Mandatory = $false)][string] $OrgFile,
        [Parameter(Mandatory = $false)][datetime] $StartTime,
        [Parameter(Mandatory = $false)][switch] $MigrateTo2gp,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    if (@($OrgList | Where-Object { $_ }).Count -eq 0 -and -not $OrgFile) { throw 'Give -OrgList or -OrgFile, the subscriber orgs to upgrade.' }
    if (@($OrgList | Where-Object { $_ }).Count -gt 0 -and $OrgFile) { throw 'Give -OrgList or -OrgFile, not both.' }
    if ($OrgFile -and -not (Test-Path -LiteralPath $OrgFile -PathType Leaf)) { throw "Org file '$OrgFile' does not exist." }
    $arguments = @('package', 'push-upgrade', 'schedule', '--package', $Package)
    if (@($OrgList | Where-Object { $_ }).Count -gt 0) { $arguments += @('--org-list', (@($OrgList | Where-Object { $_ }) -join ',')) }
    if ($OrgFile) { $arguments += @('--org-file', $OrgFile) }
    if ($PSBoundParameters.ContainsKey('StartTime')) {
        $utc = $StartTime.ToUniversalTime()
        $arguments += @('--start-time', $utc.ToString("yyyy-MM-dd'T'HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))
    }
    if ($MigrateTo2gp) { $arguments += '--migrate-to-2gp' }
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $when = 'as soon as possible'
    if ($PSBoundParameters.ContainsKey('StartTime')) { $when = 'at ' + $StartTime.ToUniversalTime().ToString("yyyy-MM-dd HH:mm 'UTC'", [System.Globalization.CultureInfo]::InvariantCulture) }
    if (-not $PSCmdlet.ShouldProcess("package version $Package", "Schedule a push upgrade $when")) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforcePushUpgrades {
    <#
    .SYNOPSIS
    Lists the push upgrade requests of a package.

    .DESCRIPTION
    Runs sf package push-upgrade list and returns one object per request (ID, status, package version, scheduled start and end). It only reads.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package push-upgrade list (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Package = --package; -ScheduledLastDays = --scheduled-last-days; -ShowMigrationsOnly = --show-push-migrations-only; -Status = --status; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Package
    ID (starts with 0Ho) or alias of the package. Passed to sf as --package. Required.

    .PARAMETER ScheduledLastDays
    Only requests scheduled in the last this many days. Passed to sf as --scheduled-last-days.

    .PARAMETER ShowMigrationsOnly
    Only requests that migrate subscribers to a second-generation package. Adds --show-push-migrations-only.

    .PARAMETER Status
    Only requests with this status. Valid values: Created, Cancelled, Pending, In Progress, Failed, Succeeded. Passed to sf as --status.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Get-SalesforcePushUpgrades -Package MyManagedPkg -Status Pending -TargetDevHub devhub
    Push upgrades that have not started.

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
        [Parameter(Mandatory = $true)][string] $Package,
        [Parameter(Mandatory = $false)][ValidateRange(0, 3650)][int] $ScheduledLastDays,
        [Parameter(Mandatory = $false)][switch] $ShowMigrationsOnly,
        [Parameter(Mandatory = $false)][ValidateSet('Created', 'Cancelled', 'Pending', 'In Progress', 'Failed', 'Succeeded')][string] $Status,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('package', 'push-upgrade', 'list', '--package', $Package)
    if ($PSBoundParameters.ContainsKey('ScheduledLastDays')) { $arguments += @('--scheduled-last-days', $ScheduledLastDays) }
    if ($ShowMigrationsOnly) { $arguments += '--show-push-migrations-only' }
    if ($Status) { $arguments += @('--status', $Status) }
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforcePushUpgrade {
    <#
    .SYNOPSIS
    Shows the status of one push upgrade request.

    .DESCRIPTION
    Runs sf package push-upgrade report for the request ID that New-SalesforcePushUpgrade returned. It only reads.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package push-upgrade report (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PushRequestId = --push-request-id; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PushRequestId
    ID of the push upgrade request (starts with 0DV). Passed to sf as --push-request-id. Required.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Get-SalesforcePushUpgrade -PushRequestId 0DVxx0000000001AAA -TargetDevHub devhub
    The state of one push upgrade.

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
        [Parameter(Mandatory = $true)][ValidatePattern('^0DV[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $PushRequestId,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('package', 'push-upgrade', 'report', '--push-request-id', $PushRequestId)
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Stop-SalesforcePushUpgrade {
    <#
    .SYNOPSIS
    Cancels a scheduled push upgrade.

    .DESCRIPTION
    Runs sf package push-upgrade abort. Only a request with the status Created or Pending can be aborted; one that has started cannot. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package push-upgrade abort (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PushRequestId = --push-request-id; -TargetDevHub = --target-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PushRequestId
    ID of the push upgrade request to abort (starts with 0DV). Passed to sf as --push-request-id. Required.

    .PARAMETER NoPrompt
    Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Stop-SalesforcePushUpgrade -PushRequestId 0DVxx0000000001AAA -TargetDevHub devhub -WhatIf
    Preview the abort.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

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
        [Parameter(Mandatory = $true)][ValidatePattern('^0DV[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $PushRequestId,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('package', 'push-upgrade', 'abort', '--push-request-id', $PushRequestId)
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    # -NoPrompt is the caller's decision not to be asked; it does not turn off -WhatIf.
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    if (-not $PSCmdlet.ShouldProcess($PushRequestId, 'Abort push upgrade')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region First-generation packages

# The sf package1 commands work on first-generation (1GP) packages. They are GA, and Convert-SalesforcePackage needs a released 1GP version, so they are wrapped.

function New-SalesforceFirstGenPackageVersion {
    <#
    .SYNOPSIS
    Uploads a new version of a first-generation package.

    .DESCRIPTION
    Runs sf package1 version create in the packaging org that owns the first-generation package. The upload can take a while: give -WaitMinutes, or follow up with Get-SalesforceFirstGenPackageVersionCreateStatus. For second-generation packages use New-SalesforcePackageVersion. Supports -WhatIf and -Confirm; it does not prompt by default.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package1 version create (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PackageId = --package-id; -Name = --name; -Description = --description; -Version = --version; -InstallationKey = --installation-key; -ManagedReleased = --managed-released; -PostInstallUrl = --post-install-url; -ReleaseNotesUrl = --release-notes-url; -WaitMinutes = --wait; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PackageId
    ID of the first-generation package (starts with 033). Passed to sf as --package-id. Required.

    .PARAMETER Name
    Name of the package version. Passed to sf as --name. Required.

    .PARAMETER Description
    Description of the package version. Passed to sf as --description.

    .PARAMETER Version
    Version number of the package version, for example 1.2. Passed to sf as --version.

    .PARAMETER InstallationKey
    Installation key that subscribers give when they install the version. Passed to sf as --installation-key.

    .PARAMETER ManagedReleased
    Upload the version as managed-released, which cannot be deleted or changed. Without it the version is a beta. Adds --managed-released.

    .PARAMETER PostInstallUrl
    URL of the post-install instructions. Passed to sf as --post-install-url.

    .PARAMETER ReleaseNotesUrl
    URL of the release notes. Passed to sf as --release-notes-url.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the upload to finish. Passed to sf as --wait.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceFirstGenPackageVersion -PackageId 033xx0000000001AAA -Name 'Spring release' -Version 2.1 -WaitMinutes 20 -TargetOrg packaging
    Upload a beta version and wait.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

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
        [Parameter(Mandatory = $true)][ValidatePattern('^033[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $PackageId,
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $Version,
        [Parameter(Mandatory = $false)][string] $InstallationKey,
        [Parameter(Mandatory = $false)][switch] $ManagedReleased,
        [Parameter(Mandatory = $false)][string] $PostInstallUrl,
        [Parameter(Mandatory = $false)][string] $ReleaseNotesUrl,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('package1', 'version', 'create', '--package-id', $PackageId, '--name', $Name)
    if ($Description) { $arguments += @('--description', $Description) }
    if ($Version) { $arguments += @('--version', $Version) }
    if ($InstallationKey) { $arguments += @('--installation-key', $InstallationKey) }
    if ($ManagedReleased) { $arguments += '--managed-released' }
    if ($PostInstallUrl) { $arguments += @('--post-install-url', $PostInstallUrl) }
    if ($ReleaseNotesUrl) { $arguments += @('--release-notes-url', $ReleaseNotesUrl) }
    if ($WaitMinutes) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $orgLabel = 'the default org'
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $orgLabel = "org $TargetOrg" }
    if (-not $PSCmdlet.ShouldProcess("package $PackageId in $orgLabel", "Upload version '$Name'")) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceFirstGenPackageVersionCreateStatus {
    <#
    .SYNOPSIS
    Shows the status of a first-generation package version upload.

    .DESCRIPTION
    Runs sf package1 version create get for the request ID from New-SalesforceFirstGenPackageVersion. It only reads.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package1 version create get (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -RequestId = --request-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER RequestId
    ID of the upload request. Passed to sf as --request-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceFirstGenPackageVersionCreateStatus -RequestId 0HD000000000001 -TargetOrg packaging
    The state of the upload.

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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $RequestId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('package1', 'version', 'create', 'get', '--request-id', $RequestId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceFirstGenPackageVersion {
    <#
    .SYNOPSIS
    Shows the details of a first-generation package version.

    .DESCRIPTION
    Runs sf package1 version display. It only reads.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package1 version display (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PackageVersionId = --package-version-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PackageVersionId
    ID of the package version (starts with 04t). Passed to sf as --package-version-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceFirstGenPackageVersion -PackageVersionId 04txx0000000001AAA -TargetOrg packaging
    The details of one version.

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
        [Parameter(Mandatory = $true)][ValidatePattern('^04t[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('package1', 'version', 'display', '--package-version-id', $PackageVersionId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceFirstGenPackageVersions {
    <#
    .SYNOPSIS
    Lists first-generation package versions.

    .DESCRIPTION
    Runs sf package1 version list and returns one object per version. Without -PackageId it lists the versions of every package in the org. It only reads.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf package1 version list (plugin @salesforce/plugin-packaging)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PackageId = --package-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PackageId
    ID of the first-generation package (starts with 033). By default all packages of the org. Passed to sf as --package-id.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceFirstGenPackageVersions -TargetOrg packaging | Format-Table
    Every first-generation version in the org.

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
        [Parameter(Mandatory = $false)][ValidatePattern('^033[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $PackageId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('package1', 'version', 'list')
    if ($PackageId) { $arguments += @('--package-id', $PackageId) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion
