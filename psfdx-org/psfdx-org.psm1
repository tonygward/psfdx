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

#region Sandboxes

function Get-SalesforceSandboxes {
    <#
    .SYNOPSIS
    Lists the sandboxes this computer is logged in to.

    .DESCRIPTION
    Runs sf org list and returns the connected orgs that are sandboxes. With -Name, only those whose sandbox name, user name or alias equals it. It reads the local list of orgs; there is no -TargetOrg.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org list (plugin @salesforce/plugin-org)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Name
    Keep only sandboxes whose sandbox name, user name or alias equals this value. The filter runs in PowerShell.

    .EXAMPLE
    Get-SalesforceSandboxes
    Every sandbox this computer knows about.

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org create sandbox (plugin @salesforce/plugin-org)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -SandboxName = --name; -Alias = --alias; -DefinitionFile = --definition-file; -LicenseType = --license-type; -WaitMinutes = --wait; -NoPrompt = --no-prompt; -NoTrackSource = --no-track-source; -Async = --async; -PollIntervalSeconds = --poll-interval; -SetDefault = --set-default; -SourceId = --source-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

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

    .PARAMETER Async
    Request the sandbox and return at once, without waiting for it to be ready. Finish with Resume-SalesforceSandbox. Adds --async.

    .PARAMETER PollIntervalSeconds
    Number of seconds to wait between checks while waiting for the sandbox. Passed to sf as --poll-interval.

    .PARAMETER SetDefault
    Set the sandbox as your default org once it is ready. Adds --set-default.

    .PARAMETER SourceId
    ID of the sandbox to clone, as an alternative to -SourceSandboxName of Copy-SalesforceSandbox. Passed to sf as --source-id.

    .PARAMETER TargetOrg
    Username or alias of the production org that contains the sandbox license. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceSandbox -SandboxName dev2 -LicenseType Developer -TargetOrg prod
    Create a developer sandbox.

    .EXAMPLE
    New-SalesforceSandbox -SandboxName dev2 -Async -TargetOrg prod
    Request the sandbox and return at once; finish later with Resume-SalesforceSandbox.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

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
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][ValidateRange(1, 2147483647)][int] $PollIntervalSeconds,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][string] $SourceId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $arguments = @('org', 'create', 'sandbox', '--name', $SandboxName)
    if ($Alias) { $arguments += @('--alias', $Alias) }

    if ($DefinitionFile) { $arguments += @('--definition-file', $DefinitionFile) }
    if ($LicenseType) { $arguments += @('--license-type', $LicenseType) }
    if ($WaitMinutes) { $arguments += @('--wait', $WaitMinutes) }
    if ($NoPrompt) { $arguments += '--no-prompt' }
    if ($NoTrackSource) { $arguments += '--no-track-source' }
    if ($Async) { $arguments += '--async' }
    if ($PSBoundParameters.ContainsKey('PollIntervalSeconds')) { $arguments += @('--poll-interval', $PollIntervalSeconds) }
    if ($SetDefault) { $arguments += '--set-default' }
    if ($SourceId) { $arguments += @('--source-id', $SourceId) }
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
    Runs sf org resume sandbox. Use it after New-SalesforceSandbox, Copy-SalesforceSandbox or Update-SalesforceSandbox returned without waiting. Say which sandbox with -SandboxName, with the -JobId of the sandbox process, or with -UseMostRecent for the latest one.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org resume sandbox (plugin @salesforce/plugin-org)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -SandboxName = --name; -JobId = --job-id; -UseMostRecent = --use-most-recent; -WaitMinutes = --wait; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER SandboxName
    Name of the sandbox org. Passed to sf as --name. Required unless you give -JobId or -UseMostRecent.

    .PARAMETER JobId
    ID of the sandbox creation or refresh process (the SandboxProcess ID, starting 0GR). Passed to sf as --job-id. Use it instead of -SandboxName.

    .PARAMETER UseMostRecent
    Resume the most recent sandbox creation or refresh. Adds --use-most-recent. Use it instead of -SandboxName.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the sandbox org to be ready. Passed to sf as --wait.

    .PARAMETER TargetOrg
    Username or alias of the production org that contains the sandbox license. Passed to sf as --target-org.

    .EXAMPLE
    Resume-SalesforceSandbox -SandboxName dev2 -WaitMinutes 30 -TargetOrg prod
    Wait up to 30 minutes.

    .EXAMPLE
    Resume-SalesforceSandbox -UseMostRecent -WaitMinutes 30
    Resume the latest sandbox creation or refresh.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-org

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Name')][string] $SandboxName,
        [Parameter(Mandatory = $true, ParameterSetName = 'JobId')][string] $JobId,
        [Parameter(Mandatory = $true, ParameterSetName = 'MostRecent')][switch] $UseMostRecent,
        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $arguments = @('org', 'resume', 'sandbox')
    switch ($PSCmdlet.ParameterSetName) {
        'Name' { $arguments += @('--name', $SandboxName) }
        'JobId' { $arguments += @('--job-id', $JobId) }
        'MostRecent' { $arguments += '--use-most-recent' }
    }
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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org create sandbox (plugin @salesforce/plugin-org)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -SourceSandboxName = --source-sandbox-name; -SourceId = --source-id; -CloneSandboxName = --name; -LicenseType = --license-type; -Alias = --alias; -WaitMinutes = --wait; -NoPrompt = --no-prompt; -Async = --async; -PollIntervalSeconds = --poll-interval; -SetDefault = --set-default; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER SourceSandboxName
    Name of the sandbox org to clone. Passed to sf as --source-sandbox-name. Required unless you give -SourceId.

    .PARAMETER SourceId
    ID of the sandbox to clone, instead of its name. Passed to sf as --source-id. Use it instead of -SourceSandboxName.

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

    .PARAMETER Async
    Request the clone and return at once, without waiting for it to be ready. Finish with Resume-SalesforceSandbox. Adds --async.

    .PARAMETER PollIntervalSeconds
    Number of seconds to wait between checks while waiting for the sandbox. Passed to sf as --poll-interval.

    .PARAMETER SetDefault
    Set the sandbox as your default org once it is ready. Adds --set-default.

    .PARAMETER TargetOrg
    Username or alias of the production org that contains the sandbox license. Passed to sf as --target-org.

    .EXAMPLE
    Copy-SalesforceSandbox -SourceSandboxName dev1 -CloneSandboxName dev2 -TargetOrg prod
    Clone dev1 as dev2.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-org

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Name')][string] $SourceSandboxName,
        [Parameter(Mandatory = $true, ParameterSetName = 'Id')][string] $SourceId,
        [Parameter(Mandatory = $true)][string] $CloneSandboxName,
        [Parameter(Mandatory = $false)][string] $LicenseType,
        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][ValidateRange(1, 2147483647)][int] $PollIntervalSeconds,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    # 'sf org clone sandbox' no longer exists; cloning is 'sf org create sandbox --source-sandbox-name' (or --source-id).
    $arguments = @('org', 'create', 'sandbox')
    if ($PSCmdlet.ParameterSetName -eq 'Id') { $arguments += @('--source-id', $SourceId) } else { $arguments += @('--source-sandbox-name', $SourceSandboxName) }
    $arguments += @('--name', $CloneSandboxName)
    if ($LicenseType) { $arguments += @('--license-type', $LicenseType) }
    if ($Alias) { $arguments += @('--alias', $Alias) }
    if ($WaitMinutes) { $arguments += @('--wait', $WaitMinutes) }
    if ($NoPrompt) { $arguments += '--no-prompt' }
    if ($Async) { $arguments += '--async' }
    if ($PSBoundParameters.ContainsKey('PollIntervalSeconds')) { $arguments += @('--poll-interval', $PollIntervalSeconds) }
    if ($SetDefault) { $arguments += '--set-default' }
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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org delete sandbox (plugin @salesforce/plugin-org)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -NoPrompt = --no-prompt; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER NoPrompt
    Don't prompt the user to confirm the deletion. Adds --no-prompt.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceSandbox -TargetOrg dev2 -WhatIf
    Preview the delete.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

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

function Update-SalesforceSandbox {
    <#
    .SYNOPSIS
    Refreshes a sandbox from production or from another sandbox.

    .DESCRIPTION
    Runs sf org refresh sandbox. A refresh replaces the sandbox's data and metadata with a fresh copy, so everything in it that is not in the source is lost. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time. The CLI waits only when you give -WaitMinutes; otherwise finish with Resume-SalesforceSandbox. Give the sandbox with -SandboxName, or put its name in a -DefinitionFile.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org refresh sandbox (plugin @salesforce/plugin-org)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -SandboxName = --name; -DefinitionFile = --definition-file; -SourceSandboxName = --source-sandbox-name; -SourceId = --source-id; -NoAutoActivate = --no-auto-activate; -Async = --async; -WaitMinutes = --wait; -PollIntervalSeconds = --poll-interval; -TargetOrg = --target-org. psfdx always passes --no-prompt, because it asks first.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER SandboxName
    Name of the sandbox to refresh. Passed to sf as --name.

    .PARAMETER DefinitionFile
    Path to a sandbox definition file that holds the refresh settings, such as the license type. Passed to sf as --definition-file.

    .PARAMETER SourceSandboxName
    Name of the sandbox to refresh from, instead of production. Passed to sf as --source-sandbox-name.

    .PARAMETER SourceId
    ID of the sandbox to refresh from, instead of its name. Passed to sf as --source-id.

    .PARAMETER NoAutoActivate
    Do not activate the sandbox when the refresh finishes; you activate it yourself later. Adds --no-auto-activate.

    .PARAMETER Async
    Start the refresh and return at once, without waiting for it to finish. Finish with Resume-SalesforceSandbox. Adds --async.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the refresh to finish. Passed to sf as --wait.

    .PARAMETER PollIntervalSeconds
    Number of seconds to wait between checks while waiting for the refresh. Passed to sf as --poll-interval.

    .PARAMETER NoPrompt
    Don't ask for confirmation. Skips the PowerShell confirmation; psfdx always passes --no-prompt to the CLI after it has confirmed.

    .PARAMETER TargetOrg
    Username or alias of the production org that owns the sandbox. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Update-SalesforceSandbox -SandboxName dev1 -TargetOrg prod -WhatIf
    Preview the refresh without starting it.

    .EXAMPLE
    Update-SalesforceSandbox -SandboxName dev1 -SourceSandboxName uat -Async -NoPrompt -TargetOrg prod
    Refresh dev1 from the uat sandbox and return at once, without any question.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

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
        [Parameter(Mandatory = $false)][string] $SandboxName,
        [Parameter(Mandatory = $false)][string] $DefinitionFile,
        [Parameter(Mandatory = $false)][string] $SourceSandboxName,
        [Parameter(Mandatory = $false)][string] $SourceId,
        [Parameter(Mandatory = $false)][switch] $NoAutoActivate,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][ValidateRange(1, 2147483647)][int] $PollIntervalSeconds,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if (-not $SandboxName -and -not $DefinitionFile) { throw 'Specify -SandboxName, or a -DefinitionFile that names the sandbox.' }
    if ($SourceSandboxName -and $SourceId) { throw 'Specify -SourceSandboxName or -SourceId, not both.' }
    if ($DefinitionFile -and -not (Test-Path -LiteralPath $DefinitionFile)) { throw "Definition file '$DefinitionFile' does not exist." }

    $arguments = @('org', 'refresh', 'sandbox')
    if ($SandboxName) { $arguments += @('--name', $SandboxName) }
    if ($DefinitionFile) { $arguments += @('--definition-file', $DefinitionFile) }
    if ($SourceSandboxName) { $arguments += @('--source-sandbox-name', $SourceSandboxName) }
    if ($SourceId) { $arguments += @('--source-id', $SourceId) }
    if ($NoAutoActivate) { $arguments += '--no-auto-activate' }
    if ($Async) { $arguments += '--async' }
    if ($WaitMinutes) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('PollIntervalSeconds')) { $arguments += @('--poll-interval', $PollIntervalSeconds) }
    # psfdx asks first (or the caller said not to), so the CLI must not ask a second time.
    $arguments += '--no-prompt'
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')

    # -NoPrompt is the caller's decision not to be asked; it does not turn off -WhatIf.
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    $target = if ($SandboxName) { $SandboxName } else { $DefinitionFile }
    if ($PSCmdlet.ShouldProcess($target, 'Refresh sandbox (replaces its data and metadata)')) {
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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf data query (plugin @salesforce/plugin-data)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Name
    Name of the sandbox. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceSandboxRefreshStatus -Name dev1 -TargetOrg prod
    The refresh status of dev1.

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

#region Scratch Orgs

function Get-SalesforceScratchOrgs {
    <#
    .SYNOPSIS
    Lists the scratch orgs this computer knows about.

    .DESCRIPTION
    Runs sf org list --all and returns the scratch orgs (orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias). With -Last only the most recently used one is returned.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org list (plugin @salesforce/plugin-org)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -SkipConnectionStatus = --skip-connection-status.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER SkipConnectionStatus
    Skip retrieving the connection status of non-scratch orgs. Adds --skip-connection-status.

    .PARAMETER Last
    Return only the scratch org with the latest lastUsed date. The sorting happens in PowerShell.

    .EXAMPLE
    Get-SalesforceScratchOrgs | Where-Object connectedStatus -eq 'Connected'
    Scratch orgs that are reachable.

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
        [Parameter(Mandatory = $false)][switch] $SkipConnectionStatus,
        [Parameter(Mandatory = $false)][switch] $Last
    )

    $arguments = @('org', 'list', '--all')
    if ($SkipConnectionStatus) {
        $arguments += '--skip-connection-status'
    }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams

    $result = $result | ConvertFrom-Json
    $result = $result.result.scratchOrgs
    $result = $result | Select-Object orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias
    if ($Last) {
        $result = $result | Sort-Object lastUsed -Descending | Select-Object -First 1
    }
    return $result
}

function New-SalesforceScratchOrg {
    <#
    .SYNOPSIS
    Creates a scratch org.

    .DESCRIPTION
    Runs sf org create scratch from a scratch org definition file. Use -Async to return before the org is ready, then finish with Resume-SalesforceScratchOrg. Scratch orgs use your Dev Hub's allocation and expire after the duration.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org create scratch (plugin @salesforce/plugin-org)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetDevHub = --target-dev-hub; -SetDefault = --set-default; -DurationDays = --duration-days; -DefinitionFile = --definition-file; -WaitMinutes = --wait; -Async = --async; -Edition = --edition; -Snapshot = --snapshot; -AdminEmail = --admin-email; -Description = --description; -Name = --name; -Release = --release; -SourceOrgId = --source-org; -AdminUsername = --username; -Alias = --alias; -OAuthClientId = --client-id; -NoAncestors = --no-ancestors; -NoNamespace = --no-namespace; -NoTrackSource = --no-track-source.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Passed to sf as --target-dev-hub.

    .PARAMETER SetDefault
    Set the scratch org as your default org. Adds --set-default.

    .PARAMETER DurationDays
    Number of days before the org expires. Passed to sf as --duration-days.

    .PARAMETER DefinitionFile
    Path to a scratch org definition file. Passed to sf as --definition-file. Default: config/project-scratch-def.json.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the scratch org to be ready. Passed to sf as --wait.

    .PARAMETER Async
    Request the org, but don't wait for it to complete. Adds --async.

    .PARAMETER Edition
    Salesforce edition of the scratch org. Overrides the value of the "edition" option in the definition file, if set. Passed to sf as --edition. Valid values: developer, enterprise, group, professional, partner-developer, partner-enterprise, partner-group, partner-professional.

    .PARAMETER Snapshot
    Name of the snapshot to use when creating this scratch org. Overrides the value of the "snapshot" option in the defintion file, if set. Passed to sf as --snapshot.

    .PARAMETER AdminEmail
    Email address that will be applied to the org's admin user. Overrides the value of the "adminEmail" option in the definition file, if set. Passed to sf as --admin-email.

    .PARAMETER Description
    Description of the scratch org in the Dev Hub. Overrides the value of the "description" option in the definition file, if set. Passed to sf as --description.

    .PARAMETER Name
    Name of the org, such as "Acme Company". Overrides the value of the "orgName" option in the definition file, if set. Passed to sf as --name.

    .PARAMETER Release
    Release of the scratch org as compared to the Dev Hub release. Passed to sf as --release. Valid values: preview, previous.

    .PARAMETER SourceOrgId
    15-character ID of the org shape that the new scratch org is based on. Overrides the value of the "sourceOrg" option in the definition file, if set. Passed to sf as --source-org.

    .PARAMETER AdminUsername
    Username of the scratch org admin user. Overrides the value of the "username" option in the definition file, if set. Passed to sf as --username.

    .PARAMETER Alias
    Alias for the scratch org. Passed to sf as --alias.

    .PARAMETER OAuthClientId
    OAuth client ID (also called consumer key) of your connected app, used to log in to the new scratch org. Passed to sf as --client-id.

    .PARAMETER NoAncestors
    Don't include second-generation managed package (2GP) ancestors in the scratch org. Adds --no-ancestors.

    .PARAMETER NoNamespace
    Create the scratch org without the namespace of the Dev Hub or the project, even if the project has one. Adds --no-namespace.

    .PARAMETER NoTrackSource
    Create the scratch org without source tracking. Scratch orgs have source tracking on by default. Adds --no-track-source.

    .EXAMPLE
    New-SalesforceScratchOrg -DefinitionFile config/project-scratch-def.json -Name ci-1 -DurationDays 3 -SetDefault
    Create a three-day scratch org and make it the default.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

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
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][int] $DurationDays,
        [Parameter(Mandatory = $false)][string] $DefinitionFile = 'config/project-scratch-def.json',
        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][string][ValidateSet('developer', 'enterprise', 'group', 'professional', 'partner-developer', 'partner-enterprise', 'partner-group', 'partner-professional')] $Edition,
        [Parameter(Mandatory = $false)][string] $Snapshot,
        [Parameter(Mandatory = $false)][string] $AdminEmail,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string][ValidateSet('preview', 'previous')] $Release,
        [Parameter(Mandatory = $false)][string] $SourceOrgId,
        [Parameter(Mandatory = $false)][string] $AdminUsername,
        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][string] $OAuthClientId,
        [Parameter(Mandatory = $false)][switch] $NoAncestors,
        [Parameter(Mandatory = $false)][switch] $NoNamespace,
        [Parameter(Mandatory = $false)][switch] $NoTrackSource
    )
    $arguments = @('org', 'create', 'scratch')
    if ($TargetDevHub) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    if ($SetDefault) { $arguments += '--set-default' }
    if ($DurationDays) { $arguments += @('--duration-days', $DurationDays) }
    $arguments += @('--definition-file', $DefinitionFile)
    if ($WaitMinutes) { $arguments += @('--wait', $WaitMinutes) }
    if ($Async) { $arguments += '--async' }
    if ($Edition) { $arguments += @('--edition', $Edition) }
    if ($Snapshot) { $arguments += @('--snapshot', $Snapshot) }
    if ($AdminEmail) { $arguments += @('--admin-email', $AdminEmail) }
    if ($Description) { $arguments += @('--description', $Description) }
    if ($Name) { $arguments += @('--name', $Name) }
    if ($Release) { $arguments += @('--release', $Release) }
    if ($SourceOrgId) { $arguments += @('--source-org', $SourceOrgId) }
    if ($AdminUsername) { $arguments += @('--username', $AdminUsername) }
    if ($Alias) { $arguments += @('--alias', $Alias) }
    if ($OAuthClientId) { $arguments += @('--client-id', $OAuthClientId) }
    if ($NoAncestors) { $arguments += '--no-ancestors' }
    if ($NoNamespace) { $arguments += '--no-namespace' }
    if ($NoTrackSource) { $arguments += '--no-track-source' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    Show-SalesforceResult -Result $result
}

function Resume-SalesforceScratchOrg {
    <#
    .SYNOPSIS
    Resumes a scratch org creation that was started with New-SalesforceScratchOrg -Async or that timed out (sf org resume scratch).

    .DESCRIPTION
    Select the creation by -JobId (the scratch org info ID, starting 2SR, reported when the creation was started) or by -UseMostRecent.
    The CLI keeps a local record of the job, so there is no -TargetOrg; resume from the machine that started it.
    Returns the CLI result (org ID, username, instance URL) with Completed: true once the org is ready. A creation that is still running
    when -WaitMinutes ends (the CLI's StillInProgressError) returns Completed: false with Status InProgress, so a script can poll; a failed creation throws the CLI message.
    Permission sets are assigned afterwards with Grant-SalesforcePermissionSet (psfdx), which asks for confirmation.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org resume scratch (plugin @salesforce/plugin-org)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -JobId = --job-id; -WaitMinutes = --wait.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER JobId
    Job ID of the incomplete scratch org create that you want to resume. Passed to sf as --job-id.

    .PARAMETER UseMostRecent
    Resume the creation the CLI started most recently. Passed as --use-most-recent. Use instead of -JobId.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the scratch org to be ready. Passed to sf as --wait. Range: 1 to 1440.

    .EXAMPLE
    New-SalesforceScratchOrg -Async -Name ci-1 | Out-Null
    Resume-SalesforceScratchOrg -UseMostRecent -WaitMinutes 10
    Grant-SalesforcePermissionSet -Name MyPermSet -TargetOrg ci-1

    .EXAMPLE
    Resume-SalesforceScratchOrg -JobId 2SR000000000001AAA -WaitMinutes 5

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
        [Parameter(Mandatory = $false)][string] $JobId,
        [Parameter(Mandatory = $false)][switch] $UseMostRecent,
        [Parameter(Mandatory = $false)][ValidateRange(1, 1440)][int] $WaitMinutes
    )

    if ($JobId -and $UseMostRecent) { throw 'Specify only one of -JobId or -UseMostRecent.' }
    if (-not $JobId -and -not $UseMostRecent) { throw 'Specify -JobId or -UseMostRecent.' }
    if ($JobId -and $JobId -notmatch '^2SR[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z') {
        throw "Job ID '$JobId' is not a valid scratch org info ID. Expected a 15 or 18 character ID starting with 2SR."
    }

    $arguments = @('org', 'resume', 'scratch')
    if ($JobId) { $arguments += @('--job-id', $JobId) } else { $arguments += '--use-most-recent' }
    if ($PSBoundParameters.ContainsKey('WaitMinutes')) { $arguments += @('--wait', $WaitMinutes) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    # A creation that is still running when the wait ends is reported by the CLI as the error StillInProgressError; that is a normal pending state.
    $body = $null
    try { $body = ((@($result) | Out-String).Trim() | ConvertFrom-Json -ErrorAction Stop) } catch { $body = $null }
    if ($null -ne $body -and $body.PSObject.Properties.Name -contains 'name' -and [string]$body.name -eq 'StillInProgressError') {
        $pending = ''
        if ($body.PSObject.Properties.Name -contains 'message') { $pending = [string]$body.message }
        return [pscustomobject]@{ Completed = $false; Status = 'InProgress'; Message = $pending }
    }
    $parsed = Show-SalesforceResult -Result $result
    if ($null -eq $parsed) { return $null }
    $names = @($parsed.PSObject.Properties.Name)
    $completed = ($names -contains 'username') -and -not [string]::IsNullOrWhiteSpace([string]$parsed.username)
    if ($names -contains 'status' -and [string]$parsed.status -match '^(Creating|Waiting|Queued|New|Pending)') { $completed = $false }
    $parsed | Add-Member -NotePropertyName Completed -NotePropertyValue $completed -Force
    return $parsed
}

function Remove-SalesforceScratchOrg {
    <#
    .SYNOPSIS
    Deletes a scratch org.

    .DESCRIPTION
    Runs sf org delete scratch. This cannot be undone. Asks for confirmation and supports -WhatIf; -NoPrompt also turns off the CLI's own question.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org delete scratch (plugin @salesforce/plugin-org)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetOrg = --target-org; -NoPrompt = --no-prompt.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org. Required.

    .PARAMETER NoPrompt
    Don't prompt the user to confirm the deletion. Adds --no-prompt.

    .EXAMPLE
    Remove-SalesforceScratchOrg -TargetOrg ci-1 -WhatIf
    Show which org would be deleted.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

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
        [Parameter(Mandatory = $true)][string] $TargetOrg,
        [Parameter()][switch] $NoPrompt
    )
    $arguments = @('org', 'delete', 'scratch', '--target-org', $TargetOrg)
    if ($NoPrompt) {
        $arguments += '--no-prompt'
    }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($PSCmdlet.ShouldProcess($TargetOrg, 'Delete scratch org')) {
        Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    }
}

function Remove-SalesforceScratchOrgs {
    <#
    .SYNOPSIS
    Deletes every scratch org this computer knows about.

    .DESCRIPTION
    Lists scratch orgs with Get-SalesforceScratchOrgs and deletes each one with Remove-SalesforceScratchOrg -NoPrompt. One confirmation names all of them. This cannot be undone. Supports -WhatIf.

    SALESFORCE CLI
        This cmdlet does not run an sf command.
        It is built on other psfdx cmdlets: Get-SalesforceScratchOrgs, Remove-SalesforceScratchOrg. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .EXAMPLE
    Remove-SalesforceScratchOrgs -WhatIf
    List the orgs that would be deleted.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param()

    $usernames = @(Get-SalesforceScratchOrgs | ForEach-Object { $_.username } | Where-Object { $_ })
    if ($usernames.Count -eq 0) { return }
    # One confirmation names every org; the per-org confirmation is then skipped.
    $target = "$($usernames.Count) scratch org(s): $($usernames -join ', ')"
    if ($PSCmdlet.ShouldProcess($target, 'Delete all scratch orgs')) {
        foreach ($username in $usernames) {
            Remove-SalesforceScratchOrg -TargetOrg $username -NoPrompt -Confirm:$false
        }
    }
}

#endregion
