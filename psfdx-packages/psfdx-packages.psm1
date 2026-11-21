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
    <#
    .SYNOPSIS
    Promotes a package version to released (sf package version promote).
    .DESCRIPTION
    Promotion cannot be undone: a released version can no longer be deleted. The cmdlet asks for confirmation and supports -WhatIf. -NoPrompt means you have
    already decided (as it does for the CLI), so it skips the confirmation and keeps existing unattended scripts working; -WhatIf still makes no call.
    -PackageVersionId can come from the pipeline, through the SubscriberPackageVersionId (04t) of a version from Get-SalesforcePackageVersions.
    .EXAMPLE
    Get-SalesforcePackageVersions -PackageName MyPkg | Select-Object -First 1 | Promote-SalesforcePackageVersion -WhatIf
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
    .EXAMPLE
    Get-SalesforcePackageVersions -PackageName MyPkg | Where-Object { -not $_.IsReleased } | Remove-SalesforcePackageVersion -WhatIf
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
    .EXAMPLE
    $create = New-SalesforcePackageVersion -PackageName MyPkg -TargetDevHub devhub; Get-SalesforcePackageVersionCreateStatus -RequestId $create.Id -TargetDevHub devhub
    .EXAMPLE
    # In a later step: wait for success, then install the version
    $s = Get-SalesforcePackageVersionCreateStatus -RequestId 08c000000000001 -TargetDevHub devhub -ThrowOnFailure; $s.SubscriberPackageVersionId
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
    .EXAMPLE
    $install = Install-SalesforcePackageVersion -PackageVersionId 04t000000000001 -WaitMinutes 0 -NoPrompt -AsObject -TargetOrg myorg; Get-SalesforcePackageInstallStatus -RequestId $install.Id -TargetOrg myorg
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
