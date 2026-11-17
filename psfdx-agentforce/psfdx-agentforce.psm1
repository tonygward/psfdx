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

#region Plugin availability

function Test-SalesforceAgentPlugin {
    [CmdletBinding()]
    Param()

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $raw = Invoke-Salesforce -Command "sf plugins --core --json" @commonParams
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

    $command = "sf agent test list"
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command @commonParams
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

    $command = "sf agent test run --api-name $ApiName"
    if ($PSBoundParameters.ContainsKey('WaitMinutes')) { $command += " --wait $WaitMinutes" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command @commonParams
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

    $command = "sf agent test results --job-id $JobId"
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command @commonParams
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

    $command = "sf agent activate --api-name $ApiName"
    if ($PSBoundParameters.ContainsKey('Version')) { $command += " --version $Version" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"

    if ($PSCmdlet.ShouldProcess($ApiName, 'Activate agent')) {
        $result = Invoke-Salesforce -Command $command @commonParams
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

    $command = "sf agent deactivate --api-name $ApiName"
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"

    if ($PSCmdlet.ShouldProcess($ApiName, 'Deactivate agent')) {
        $result = Invoke-Salesforce -Command $command @commonParams
        return Show-SalesforceResult -Result $result
    }
}

#endregion
