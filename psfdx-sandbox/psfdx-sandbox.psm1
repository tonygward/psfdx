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

#region Sandbox Management

function Get-SalesforceSandboxes {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Name
    )

    $command = "sf org list --json"
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -Command $command @commonParams
    $parsed = Show-SalesforceResult -Result $result
    if (-not $parsed) { return @() }

    $nonScratch = $parsed.nonScratchOrgs
    if ($null -eq $nonScratch) { return @() }

    $sandboxes = @($nonScratch | Where-Object { $_.isSandbox })
    if ($Name) {
        $sandboxes = $sandboxes | Where-Object {
            ($_.sandboxName -eq $Name) -or
            ($_.username -eq $Name) -or
            ($_.alias -eq $Name)
        }
    }
    return $sandboxes
}

function New-SalesforceSandbox {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $SandboxName,
        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][string] $DefinitionFile,
        [Parameter(Mandatory = $false)][ValidateSet('Developer', 'Developer_Pro', 'Partial', 'Full')][string] $LicenseType = 'Developer',
        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][switch] $NoTrackSource,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $command = "sf org create sandbox --name $SandboxName"
    if ($Alias) { $command += " --alias $Alias" }

    if ($DefinitionFile) { $command += " --definition-file `"$DefinitionFile`"" }
    if ($LicenseType) { $command += " --license-type $LicenseType" }
    if ($WaitMinutes) { $command += " --wait $WaitMinutes" }
    if ($NoPrompt) { $command += " --no-prompt" }
    if ($NoTrackSource) { $command += " --no-track-source" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -Command $command @commonParams
    return Show-SalesforceResult -Result $result
}

function Resume-SalesforceSandbox {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $SandboxName,
        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $command = "sf org resume sandbox --name $SandboxName"
    if ($WaitMinutes) { $command += " --wait $WaitMinutes" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -Command $command @commonParams
    return Show-SalesforceResult -Result $result
}

function Copy-SalesforceSandbox {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $SourceSandboxName,
        [Parameter(Mandatory = $true)][string] $CloneSandboxName,
        [Parameter(Mandatory = $false)][string] $LicenseType,
        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $command = "sf org clone sandbox --name $SourceSandboxName --clone-name $CloneSandboxName"
    if ($LicenseType) { $command += " --license-type $LicenseType" }
    if ($Alias) { $command += " --alias $Alias" }
    if ($WaitMinutes) { $command += " --wait $WaitMinutes" }
    if ($NoPrompt) { $command += " --no-prompt" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -Command $command @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceSandbox {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $command = "sf org delete sandbox"
    if ($NoPrompt) { $command += " --no-prompt" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -Command $command @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceSandboxRefreshStatus {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $escapedName = $Name -replace "'", "''"

    $infoQuery = "SELECT SandboxName, LicenseType FROM SandboxInfo WHERE SandboxName = '$escapedName'"
    $infoCommand = "sf data query --use-tooling-api --result-format json --query `"$infoQuery`""
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $infoCommand += " --target-org $TargetOrg" }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $infoResult = Invoke-Salesforce -Command $infoCommand @commonParams | ConvertFrom-Json
    if ($infoResult.status -ne 0) {
        Write-Debug ($infoResult | ConvertTo-Json -Depth 5)
        throw $infoResult.message
    }

    $infoRecords = @($infoResult.result.records | Select-Object -ExcludeProperty attributes)
    if ($infoRecords.Count -eq 0) {
        return @()
    }

    $licenseType = $infoRecords[0].LicenseType

    $processQuery = "SELECT SandboxName, StartDate, EndDate FROM SandboxProcess WHERE SandboxName = '$escapedName' ORDER BY StartDate DESC LIMIT 1"
    $processCommand = "sf data query --use-tooling-api --result-format json --query `"$processQuery`""
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $processCommand += " --target-org $TargetOrg" }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $processResult = Invoke-Salesforce -Command $processCommand @commonParams | ConvertFrom-Json
    if ($processResult.status -ne 0) {
        Write-Debug ($processResult | ConvertTo-Json -Depth 5)
        throw $processResult.message
    }

    $processRecords = @($processResult.result.records | Select-Object -ExcludeProperty attributes)

    $lastRefreshed = $null
    if ($processRecords.Count -gt 0 -and $processRecords[0].EndDate) {
        try {
            $lastRefreshed = [datetime]::Parse($processRecords[0].EndDate)
        } catch {
            Write-Warning "Unable to parse sandbox EndDate '$($processRecords[0].EndDate)' as datetime."
        }
    }

    $nextRefresh = $null
    if ($lastRefreshed) {
        switch ($licenseType) {
            'Developer' { $nextRefresh = $lastRefreshed.AddDays(1) }
            'Developer_Pro' { $nextRefresh = $lastRefreshed.AddDays(1) }
            'Partial' { $nextRefresh = $lastRefreshed.AddDays(5) }
            'Full' { $nextRefresh = $lastRefreshed.AddDays(29) }
        }
    }

    return @([pscustomobject]@{
        Name = $Name
        LicenseType = $licenseType
        LastRefreshed = $lastRefreshed
        NextRefreshDate = $nextRefresh
    })
}

#endregion
