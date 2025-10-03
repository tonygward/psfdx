$resolvePsfdxSharedScript = {
    param(
        [Parameter(Mandatory = $true)][string] $FileName
    )

    $moduleBase = $ExecutionContext.SessionState.Module.ModuleBase
    $candidates = @()
    $candidates += Join-Path -Path $moduleBase -ChildPath (Join-Path '..' (Join-Path 'psfdx-shared' $FileName))

    $moduleRoot = Split-Path -Path $moduleBase -Parent
    if ($moduleRoot) {
        $candidates += Join-Path -Path $moduleRoot -ChildPath (Join-Path 'psfdx-shared' $FileName)
    }

    $psModuleRoots = $env:PSModulePath -split [System.IO.Path]::PathSeparator
    foreach ($root in $psModuleRoots) {
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $candidates += Join-Path -Path $root -ChildPath (Join-Path 'psfdx-shared' $FileName)
        }
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        try {
            $resolved = Resolve-Path -LiteralPath $candidate -ErrorAction Stop
            return $resolved.ProviderPath
        } catch {
            continue
        }
    }

    return $null
}

$importPsfdxSharedScript = {
    param(
        [Parameter(Mandatory = $true)][string] $FileName
    )

    $path = & $resolvePsfdxSharedScript -FileName $FileName
    if ($path) {
        . $path
        return
    }

    throw "Unable to locate psfdx-shared script '$FileName'. Reinstall psfdx to ensure shared scripts are installed."
}

& $importPsfdxSharedScript -FileName 'Invoke-Salesforce.ps1'
& $importPsfdxSharedScript -FileName 'Show-SalesforceResult.ps1'

#region Sandbox Management

function Get-SalesforceSandboxes {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Name
    )

    $command = "sf org list --json"
    $result = Invoke-Salesforce -Command $command
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

    $result = Invoke-Salesforce -Command $command
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

    $result = Invoke-Salesforce -Command $command
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

    $result = Invoke-Salesforce -Command $command
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

    $result = Invoke-Salesforce -Command $command
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

    $infoResult = Invoke-Salesforce -Command $infoCommand | ConvertFrom-Json
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

    $processResult = Invoke-Salesforce -Command $processCommand | ConvertFrom-Json
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
