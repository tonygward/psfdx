. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Invoke-Salesforce.ps1')
. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Show-SalesforceResult.ps1')

## Show-SalesforceResult moved to psfdx-shared/Show-SalesforceResult.ps1

function Get-SalesforcePackages {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $DevHubUsername,
        [Parameter(Mandatory = $false)][switch] $IncludeExtendedPackageDetails
    )
    $arguments = "package list --target-dev-hub $DevHubUsername"
    if ($IncludeExtendedPackageDetails) {
        $arguments += " --verbose"
    }
    $arguments += " --json"
    $result = Invoke-Salesforce -Command ("sf " + $arguments)
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
    if (! $Description) {
        $Description = $Name
    }
    $arguments = "package create --name $Name --description $Description"
    $arguments += " --path $Path"
    $arguments += " --package-type $PackageType"
    if ($IsOrgDependent) {
        $arguments += " --org-dependent"
    }
    if ($NoNamespace) {
        $arguments += " --no-namespace"
    }
    $arguments += " --target-dev-hub $DevHubUsername"
    $arguments += " --json"
    $result = Invoke-Salesforce -Command ("sf " + $arguments)
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
    $arguments = "package delete --package $Name"
    if ($NoPrompt) {
        $arguments += " --no-prompt"
    }
    $arguments += " --target-dev-hub $DevHubUsername"
    Invoke-Salesforce -Command ("sf " + $arguments)
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

    $arguments = "package version create --package $PackageId"
    $arguments += " --target-dev-hub $DevHubUsername"
    if ($Name) {
        $arguments += " --version-name $Name"
    }
    if ($Description) {
        $arguments += " --version-description $Description"
    }
    if ($Tag) {
        $arguments += " --tag $Tag"
    }
    if ($CodeCoverage) {
        $arguments += " --code-coverage"
    }
    $arguments += " --definition-file $ScratchOrgDefinitionFile"

    if (($InstallationKeyBypass) -or (! $InstallationKey)) {
        $arguments += " --installation-key-bypass"
    }
    else {
        $arguments += " --installation-key $InstallationKey"
    }

    if ($SkipValidation) {
        $arguments += " --skip-validation"
    }
    if ($WaitMinutes) {
        $arguments += " --wait $WaitMinutes"
    }

    $arguments += " --json"
    $result = Invoke-Salesforce -Command ("sf " + $arguments)
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

    $arguments = "package version list"
    $arguments += " --target-dev-hub $DevHubUsername"
    if ($PackageId) {
        $arguments += " --packages $PackageId"
    }
    if ($Released) {
        $arguments += " --released"
    }
    if ($Concise) {
        $arguments += " --concise"
    }
    if ($ExtendedDetails) {
        $arguments += " --verbose"
    }
    $arguments += " --json"

    $result = Invoke-Salesforce -Command ("sf " + $arguments)
    return Show-SalesforceResult -Result $result
}

function Promote-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $true)][string] $DevHubUsername,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )

    $arguments = "package version promote"
    $arguments += " --package $PackageVersionId"
    $arguments += " --target-dev-hub $DevHubUsername"
    if ($NoPrompt) {
        $arguments += " --no-prompt"
    }
    $arguments += " --json"

    $result = Invoke-Salesforce -Command ("sf " + $arguments)
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $true)][string] $DevHubUsername,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )

    $arguments = "package version delete"
    $arguments += " --package $PackageVersionId"
    $arguments += " --target-dev-hub $DevHubUsername"
    if ($NoPrompt) {
        $arguments += " --no-prompt"
    }
    $arguments += " --json"

    $result = Invoke-Salesforce -Command ("sf " + $arguments)
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

    $arguments = "package install"
    $arguments += " --package $PackageVersionId"
    if ($TargetOrg) { $arguments += " --target-org $TargetOrg" }
    if ($NoPrompt) {
        $arguments += " --no-prompt"
    }
    if ($WaitMinutes) {
        $arguments += " --wait $WaitMinutes"
        $arguments += " --publish-wait $WaitMinutes"
    }
    Invoke-Salesforce -Command ("sf " + $arguments)
}
