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

#region Sandbox Management

function Get-SalesforceSandboxes {
    <#
    .SYNOPSIS
    Lists the sandboxes this computer is logged in to.

    .DESCRIPTION
    Runs sf org list and returns the connected orgs that are sandboxes. With -Name, only those whose sandbox name, user name or alias equals it. It reads the local list of orgs; there is no -TargetOrg.

    .PARAMETER Name
    Keep only sandboxes whose sandbox name, user name or alias equals this value. The filter runs in PowerShell.

    .EXAMPLE
    Get-SalesforceSandboxes
    Every sandbox this computer knows about.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org list (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-org

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Name
    )

    $arguments = @('org', 'list', '--json')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
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
    <#
    .SYNOPSIS
    Creates a sandbox from production.

    .DESCRIPTION
    Runs sf org create sandbox. A sandbox uses a license of your production org. The CLI waits only when you give -WaitMinutes; otherwise finish with Resume-SalesforceSandbox.

    .PARAMETER SandboxName
    Name of the sandbox org. Passed to sf as --name. Required.

    .PARAMETER Alias
    Alias for the sandbox org. Passed to sf as --alias.

    .PARAMETER DefinitionFile
    Path to a sandbox definition file. Passed to sf as --definition-file.

    .PARAMETER LicenseType
    Type of sandbox license. Passed to sf as --license-type. Default: Developer. Valid values: Developer, Developer_Pro, Partial, Full.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the sandbox org to be ready. Passed to sf as --wait.

    .PARAMETER NoPrompt
    Don't prompt for confirmation about the sandbox configuration. Adds --no-prompt.

    .PARAMETER NoTrackSource
    Do not use source tracking for this sandbox. Adds --no-track-source.

    .PARAMETER TargetOrg
    Username or alias of the production org that contains the sandbox license. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceSandbox -SandboxName dev2 -LicenseType Developer -TargetOrg prod
    Create a developer sandbox.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org create sandbox (plugin @salesforce/plugin-org)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --async, --poll-interval, --set-default, --source-id
    Parameter to flag: -SandboxName = --name; -Alias = --alias; -DefinitionFile = --definition-file; -LicenseType = --license-type; -WaitMinutes = --wait; -NoPrompt = --no-prompt; -NoTrackSource = --no-track-source; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-org

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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

    $arguments = @('org', 'create', 'sandbox', '--name', $SandboxName)
    if ($Alias) { $arguments += @('--alias', $Alias) }

    if ($DefinitionFile) { $arguments += @('--definition-file', $DefinitionFile) }
    if ($LicenseType) { $arguments += @('--license-type', $LicenseType) }
    if ($WaitMinutes) { $arguments += @('--wait', $WaitMinutes) }
    if ($NoPrompt) { $arguments += '--no-prompt' }
    if ($NoTrackSource) { $arguments += '--no-track-source' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Resume-SalesforceSandbox {
    <#
    .SYNOPSIS
    Checks a sandbox creation and logs in to it when it is ready.

    .DESCRIPTION
    Runs sf org resume sandbox for the sandbox name. Use it after New-SalesforceSandbox returned without waiting.

    .PARAMETER SandboxName
    Name of the sandbox org. Passed to sf as --name. Required.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the sandbox org to be ready. Passed to sf as --wait.

    .PARAMETER TargetOrg
    Username or alias of the production org that contains the sandbox license. Passed to sf as --target-org.

    .EXAMPLE
    Resume-SalesforceSandbox -SandboxName dev2 -WaitMinutes 30 -TargetOrg prod
    Wait up to 30 minutes.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org resume sandbox (plugin @salesforce/plugin-org)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --job-id, --use-most-recent
    Parameter to flag: -SandboxName = --name; -WaitMinutes = --wait; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-org

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $SandboxName,
        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $arguments = @('org', 'resume', 'sandbox', '--name', $SandboxName)
    if ($WaitMinutes) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Copy-SalesforceSandbox {
    <#
    .SYNOPSIS
    Creates a sandbox as a copy of another sandbox.

    .DESCRIPTION
    Runs sf org create sandbox with --source-sandbox-name, which clones an existing sandbox. The CLI waits only when you give -WaitMinutes.

    .PARAMETER SourceSandboxName
    Name of the sandbox org to clone. Passed to sf as --source-sandbox-name. Required.

    .PARAMETER CloneSandboxName
    Name of the sandbox org. Passed to sf as --name. Required.

    .PARAMETER LicenseType
    Type of sandbox license. Passed to sf as --license-type.

    .PARAMETER Alias
    Alias for the sandbox org. Passed to sf as --alias.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the sandbox org to be ready. Passed to sf as --wait.

    .PARAMETER NoPrompt
    Don't prompt for confirmation about the sandbox configuration. Adds --no-prompt.

    .PARAMETER TargetOrg
    Username or alias of the production org that contains the sandbox license. Passed to sf as --target-org.

    .EXAMPLE
    Copy-SalesforceSandbox -SourceSandboxName dev1 -CloneSandboxName dev2 -TargetOrg prod
    Clone dev1 as dev2.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org create sandbox (plugin @salesforce/plugin-org)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --async, --poll-interval, --set-default, --source-id
    Parameter to flag: -SourceSandboxName = --source-sandbox-name; -CloneSandboxName = --name; -LicenseType = --license-type; -Alias = --alias; -WaitMinutes = --wait; -NoPrompt = --no-prompt; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-org

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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

    # 'sf org clone sandbox' no longer exists; cloning is 'sf org create sandbox --source-sandbox-name'.
    $arguments = @('org', 'create', 'sandbox', '--source-sandbox-name', $SourceSandboxName, '--name', $CloneSandboxName)
    if ($LicenseType) { $arguments += @('--license-type', $LicenseType) }
    if ($Alias) { $arguments += @('--alias', $Alias) }
    if ($WaitMinutes) { $arguments += @('--wait', $WaitMinutes) }
    if ($NoPrompt) { $arguments += '--no-prompt' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceSandbox {
    <#
    .SYNOPSIS
    Deletes a sandbox.

    .DESCRIPTION
    Runs sf org delete sandbox. This cannot be undone. Asks for confirmation and supports -WhatIf; -NoPrompt also turns off the CLI's own question.

    .PARAMETER NoPrompt
    Don't prompt the user to confirm the deletion. Adds --no-prompt.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceSandbox -TargetOrg dev2 -WhatIf
    Preview the delete.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org delete sandbox (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -NoPrompt = --no-prompt; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-org

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $arguments = @('org', 'delete', 'sandbox')
    if ($NoPrompt) { $arguments += '--no-prompt' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $target = if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $TargetOrg } else { 'default target org' }
    if ($PSCmdlet.ShouldProcess($target, 'Delete sandbox')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Get-SalesforceSandboxRefreshStatus {
    <#
    .SYNOPSIS
    Shows when a sandbox was last refreshed and its refresh state.

    .DESCRIPTION
    Runs sf data query on the Tooling API objects SandboxInfo and SandboxProcess (two queries) for the sandbox name, and combines them. The name is escaped as a SOQL literal.

    .PARAMETER Name
    Name of the sandbox. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceSandboxRefreshStatus -Name dev1 -TargetOrg prod
    The refresh status of dev1.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data query (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-data

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $nameLiteral = ConvertTo-SalesforceSoqlLiteral -Value $Name

    $infoQuery = "SELECT SandboxName, LicenseType FROM SandboxInfo WHERE SandboxName = $nameLiteral"
    $infoArguments = @('data', 'query', '--use-tooling-api', '--result-format', 'json', '--query', $infoQuery)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $infoArguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $infoResult = Invoke-Salesforce -FilePath 'sf' -Arguments $infoArguments @commonParams | ConvertFrom-Json
    if ($infoResult.status -ne 0) {
        Write-Debug ($infoResult | ConvertTo-Json -Depth 5)
        throw $infoResult.message
    }

    $infoRecords = @($infoResult.result.records | Select-Object -Property * -ExcludeProperty attributes)
    if ($infoRecords.Count -eq 0) {
        return @()
    }

    $licenseType = $infoRecords[0].LicenseType

    $processQuery = "SELECT SandboxName, StartDate, EndDate FROM SandboxProcess WHERE SandboxName = $nameLiteral ORDER BY StartDate DESC LIMIT 1"
    $processArguments = @('data', 'query', '--use-tooling-api', '--result-format', 'json', '--query', $processQuery)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $processArguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $processResult = Invoke-Salesforce -FilePath 'sf' -Arguments $processArguments @commonParams | ConvertFrom-Json
    if ($processResult.status -ne 0) {
        Write-Debug ($processResult | ConvertTo-Json -Depth 5)
        throw $processResult.message
    }

    $processRecords = @($processResult.result.records | Select-Object -Property * -ExcludeProperty attributes)

    $lastRefreshed = $null
    if ($processRecords.Count -gt 0 -and $processRecords[0].EndDate) {
        try {
            # Parse with the invariant culture: the CLI always returns ISO 8601, which a
            # culture like de-DE or ar-SA would otherwise misread.
            $lastRefreshed = [datetime]::Parse($processRecords[0].EndDate, [System.Globalization.CultureInfo]::InvariantCulture)
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
