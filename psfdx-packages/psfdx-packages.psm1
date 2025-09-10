. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Invoke-Salesforce.ps1')
. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Show-SalesforceResult.ps1')

## Show-SalesforceResult moved to psfdx-shared/Show-SalesforceResult.ps1

function Get-SalesforcePackages {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $DevHubUsername,
        [Parameter(Mandatory = $false)][switch] $IncludeExtendedPackageDetails
    )
    $command = "sf package list --target-dev-hub $DevHubUsername"
    if ($IncludeExtendedPackageDetails) { $command += " --verbose" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Get-SalesforcePackage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $DevHubUsername,
        [Parameter(Mandatory = $false)][switch] $IncludeExtendedPackageDetails
    )
    $packages = Get-SalesforcePackages -DevHubUsername $DevHubUsername -IncludeExtendedPackageDetails:$IncludeExtendedPackageDetails
    return $packages | Where-Object Name -eq $Name
}

function New-SalesforcePackage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $DevHubUsername,
        [Parameter(Mandatory = $false)][string][ValidateSet("Managed", "Unlocked")] $PackageType,
        [Parameter(Mandatory = $false)][switch] $IsOrgDependent,
        [Parameter(Mandatory = $false)][string] $Path = "force-app/main/default",
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][switch] $NoNamespace
    )
    if (! $Description) { $Description = $Name }
    $command = "sf package create --name $Name --description $Description"
    $command += " --path $Path"
    $command += " --package-type $PackageType"
    if ($IsOrgDependent) { $command += " --org-dependent" }
    if ($NoNamespace) { $command += " --no-namespace" }
    $command += " --target-dev-hub $DevHubUsername"
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    $resultSfdx = Show-SalesforceResult -Result $result
    return $resultSfdx.Id
}

function Remove-SalesforcePackage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $DevHubUsername,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $command = "sf package delete --package $Name"
    if ($NoPrompt) { $command += " --no-prompt" }
    $command += " --target-dev-hub $DevHubUsername"
    Invoke-Salesforce -Command $command
}
function New-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $PackageId,
        [Parameter(Mandatory = $false)][string] $PackageName,
        [Parameter(Mandatory = $true)][string] $DevHubUsername,

        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $Tag,

        [Parameter(Mandatory = $false)][string] $InstallationKey,
        [Parameter(Mandatory = $false)][switch] $InstallationKeyBypass,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][switch] $SkipValidation,

        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string] $ScratchOrgDefinitionFile = "config/project-scratch-def.json"
    )

    if ((! $PackageId ) -and (! $PackageName) ) {
        throw "Please provide a PackageId or Package Name"
    }
    if ((! $PackageId ) -and ($PackageName) ) {
        $package = Get-SalesforcePackage -Name $PackageName -DevHubUsername $DevHubUsername
        $PackageId = $package.Id
    }

    $command = "sf package version create --package $PackageId"
    $command += " --target-dev-hub $DevHubUsername"
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

    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Get-SalesforcePackageVersions {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $PackageId,
        [Parameter(Mandatory = $false)][string] $PackageName,

        [Parameter(Mandatory = $true)][string] $DevHubUsername,
        [Parameter(Mandatory = $false)][switch] $Released,
        [Parameter(Mandatory = $false)][switch] $Concise,
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails
    )
    if ((! $PackageId ) -and ($PackageName) ) {
        $package = Get-SalesforcePackage -Name $PackageName -DevHubUsername $DevHubUsername
        $PackageId = $package.Id
    }

    $command = "sf package version list"
    $command += " --target-dev-hub $DevHubUsername"
    if ($PackageId) { $command += " --packages $PackageId" }
    if ($Released) { $command += " --released" }
    if ($Concise) { $command += " --concise" }
    if ($ExtendedDetails) { $command += " --verbose" }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Promote-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $true)][string] $DevHubUsername,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )

    $command = "sf package version promote"
    $command += " --package $PackageVersionId"
    $command += " --target-dev-hub $DevHubUsername"
    if ($NoPrompt) { $command += " --no-prompt" }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $true)][string] $DevHubUsername,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )

    $command = "sf package version delete"
    $command += " --package $PackageVersionId"
    $command += " --target-dev-hub $DevHubUsername"
    if ($NoPrompt) { $command += " --no-prompt" }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Install-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][Alias('Username','DevHubUsername')][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][int] $WaitMinutes = 10
    )

    $command = "sf package install"
    $command += " --package $PackageVersionId"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    if ($NoPrompt) { $command += " --no-prompt" }
    if ($WaitMinutes) {
        $command += " --wait $WaitMinutes"
        $command += " --publish-wait $WaitMinutes"
    }
    Invoke-Salesforce -Command $command
}
