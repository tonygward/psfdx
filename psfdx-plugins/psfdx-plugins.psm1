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

#region Private helpers

# A copy of a private helper of psfdx, which the REST and GraphQL cmdlets there also use. psfdx keeps its own copy;
# tests/Repository.Tests.ps1 fails if this copy differs from the one in psfdx.

function Invoke-SalesforceText {
    # Private: runs an sf command whose result is text (a response body, plugin output). Invoke-Salesforce only checks the exit code in JSON mode,
    # so a failure would otherwise come back as if it had worked. The text goes in the error's message and in its TargetObject. When the Windows
    # .cmd launcher refuses an argument, the Hint says what to do instead.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [Parameter(Mandatory = $false)][hashtable] $CommonParams = @{},
        [Parameter(Mandatory = $false)][string] $Hint
    )
    $global:LASTEXITCODE = 0
    try { $output = Invoke-Salesforce -FilePath 'sf' -Arguments $Arguments @CommonParams }
    catch {
        if ($Hint -and $_.Exception.Message -like '*cannot be passed safely*') { throw "$Hint ($($_.Exception.Message))" }
        throw
    }
    $exitCode = $global:LASTEXITCODE
    $text = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string] $_ })).Trim()
    if ($exitCode -ne 0) {
        $shown = $text
        if ($shown.Length -gt 4000) { $shown = $shown.Substring(0, 4000) + '...' }
        $command = ($Arguments | Where-Object { $_ -and -not $_.StartsWith('-') } | Select-Object -First 3) -join ' '
        $message = "sf $command exited with code $exitCode."
        if ($shown) { $message += " $shown" }
        $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException $message), 'PsfdxRequestFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $text)
        throw $record
    }
    return $text
}

#endregion

#region Plugins

function Install-SalesforcePlugin {
    <#
    .SYNOPSIS
    Installs a Salesforce CLI plugin (sf plugins install).

    .DESCRIPTION
    A plugin is code that runs with your permissions, so install only plugins you trust: the CLI may ask you to confirm one that is not on its
    allow list. -Name is an npm package name (optionally scoped and with a version, such as @salesforce/plugin-agent@latest) or a GitHub URL. A
    value that starts with a dash or contains spaces or control characters is refused, so it cannot be read as a CLI option. Supports -WhatIf and -Confirm.

    .PARAMETER Name
    The plugin to install: an npm package name such as @salesforce/plugin-agent, optionally with a version, or a GitHub URL. A value that starts with a dash or contains spaces or control characters is refused, so it cannot be read as a CLI option. Required.

    .PARAMETER Force
    Make npm fetch the plugin again even if a copy is already on disk. Adds --force.

    .PARAMETER Silent
    Silence the output of npm. Adds --silent.

    .PARAMETER ExtendedDetails
    Show the verbose output of npm. Adds --verbose.

    .EXAMPLE
    Install-SalesforcePlugin -Name @salesforce/plugin-agent -WhatIf

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins install (plugin @oclif/plugin-plugins)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --help
    Parameter to flag: -Force = --force; -Silent = --silent; -ExtendedDetails = --verbose.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/oclif/plugin-plugins

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][switch] $Force,
        [Parameter(Mandatory = $false)][switch] $Silent,
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails
    )
    if ($Name -notmatch '^[A-Za-z0-9@][A-Za-z0-9@._~/:+#-]*\z') {
        throw "Plugin name '$Name' is not valid. Use an npm package name such as @salesforce/plugin-agent, or a GitHub URL; it must not start with a dash or contain spaces."
    }
    $arguments = @('plugins', 'install', $Name)
    if ($Force) { $arguments += '--force' }
    if ($Silent) { $arguments += '--silent' }
    if ($ExtendedDetails) { $arguments += '--verbose' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($PSCmdlet.ShouldProcess($Name, 'Install Salesforce CLI plugin')) {
        Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    }
}

function Get-SalesforcePlugins {
    <#
    .SYNOPSIS
    Lists the Salesforce CLI plugins that are installed.

    .DESCRIPTION
    Runs sf plugins and returns the CLI's own text output, one plugin per line. Add -IncludeCore to include the plugins that ship with the CLI.

    .PARAMETER IncludeCore
    Also list the plugins that ship with the Salesforce CLI. Adds --core.

    .EXAMPLE
    Get-SalesforcePlugins -IncludeCore
    Every plugin, including the bundled ones.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins (plugin @oclif/plugin-plugins)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -IncludeCore = --core.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/oclif/plugin-plugins

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $IncludeCore
    )
    $arguments = @('plugins')
    if ($IncludeCore) { $arguments += '--core' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

function Update-SalesforcePlugins {
    <#
    .SYNOPSIS
    Updates the installed Salesforce CLI plugins.

    .DESCRIPTION
    Runs sf plugins update. Supports -WhatIf and -Confirm.

    .PARAMETER ExtendedDetails
    Show the verbose output of the update. Adds --verbose.

    .EXAMPLE
    Update-SalesforcePlugins -WhatIf
    Show what would be updated.

    .NOTES
    Installs or updates software on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins update (plugin @oclif/plugin-plugins)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --help
    Parameter to flag: -ExtendedDetails = --verbose.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/oclif/plugin-plugins

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails
    )
    $arguments = @('plugins', 'update')
    if ($ExtendedDetails) { $arguments += '--verbose' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($PSCmdlet.ShouldProcess('installed Salesforce CLI plugins', 'Update')) {
        Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    }
}

#endregion

#region Plugin management

# The rest of sf plugins: uninstall, inspect, discover, reset and the trust commands. Install-SalesforcePlugin, Update-SalesforcePlugins and Get-SalesforcePlugins are in the Plugins region.

function Uninstall-SalesforcePlugin {
    <#
    .SYNOPSIS
    Removes plugins from the Salesforce CLI.

    .DESCRIPTION
    Runs sf plugins uninstall for each name. Commands the plugin provided stop working, and psfdx cmdlets that need it (for example the agent cmdlets need @salesforce/plugin-agent) will say it is missing. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. The CLI command has no prompt of its own.

    .PARAMETER Name
    Plugins to remove, as npm package names such as @salesforce/plugin-agent. Each must be a plain name: it must not start with a dash or contain spaces. Required.

    .PARAMETER ExtendedDetails
    Show more detail of what the CLI does. Adds --verbose.

    .PARAMETER NoPrompt
    Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.

    .EXAMPLE
    Uninstall-SalesforcePlugin -Name @salesforce/plugin-agent -WhatIf
    Preview removing a plugin.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins uninstall (plugin @oclif/plugin-plugins)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ExtendedDetails = --verbose.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/@oclif/plugin-plugins

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9@][A-Za-z0-9@._~/:+#-]*\z')][string[]] $Name,
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $names = @($Name | Where-Object { $_ })
    if ($names.Count -eq 0) { throw 'Give at least one plugin -Name.' }
    $arguments = @('plugins', 'uninstall')
    $arguments += $names
    if ($ExtendedDetails) { $arguments += '--verbose' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    if (-not $PSCmdlet.ShouldProcess(($names -join ', '), 'Uninstall Salesforce CLI plugin')) { return }
    return Invoke-SalesforceText -Arguments $arguments -CommonParams $commonParams
}

function Get-SalesforcePluginDetails {
    <#
    .SYNOPSIS
    Shows the installation details of plugins.

    .DESCRIPTION
    Runs sf plugins inspect for each plugin and returns what the CLI knows about it, such as its version and where it is installed. It only reads. For the list of installed plugins see Get-SalesforcePlugins.

    .PARAMETER Name
    Plugins to inspect, as npm package names such as @salesforce/plugin-agent. Required.

    .PARAMETER ExtendedDetails
    Show more detail. Adds --verbose.

    .EXAMPLE
    Get-SalesforcePluginDetails -Name @salesforce/plugin-agent
    Version and location of one plugin.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins inspect (plugin @oclif/plugin-plugins)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ExtendedDetails = --verbose.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/@oclif/plugin-plugins

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9@][A-Za-z0-9@._~/:+#-]*\z')][string[]] $Name,
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails
    )
    $names = @($Name | Where-Object { $_ })
    if ($names.Count -eq 0) { throw 'Give at least one plugin -Name.' }
    $arguments = @('plugins', 'inspect')
    $arguments += $names
    if ($ExtendedDetails) { $arguments += '--verbose' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    # sf plugins inspect is an oclif command, not an sf one: with --json it prints a bare array of plugins, with no status wrapper.
    $text = ([string]::Join([Environment]::NewLine, @($result | ForEach-Object { [string] $_ }))).Trim()
    if ($text.StartsWith('[')) { return @($text | ConvertFrom-Json) }
    return Show-SalesforceResult -Result $result
}

function Find-SalesforcePlugins {
    <#
    .SYNOPSIS
    Lists third-party plugins you can install.

    .DESCRIPTION
    Runs sf plugins discover and returns the third-party plugins that Salesforce lists. It reads a list on the internet and changes nothing. Install one with Install-SalesforcePlugin.

    .EXAMPLE
    Find-SalesforcePlugins
    The plugins you can add.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins discover (plugin @salesforce/plugin-marketplace)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-marketplace

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(

    )
    $arguments = @('plugins', 'discover', '--json')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Reset-SalesforcePlugins {
    <#
    .SYNOPSIS
    Removes every plugin you installed or linked in the Salesforce CLI.

    .DESCRIPTION
    Runs sf plugins reset. All user-installed and linked plugins are uninstalled, so commands that came from them stop working until you install them again (or use -Reinstall). Plugins that ship with the CLI stay. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. The CLI command has no prompt of its own.

    .PARAMETER Hard
    Also delete node_modules and the package manager files, not only uninstall the plugins. Adds --hard.

    .PARAMETER Reinstall
    Install all the plugins again after removing them. Adds --reinstall.

    .PARAMETER NoPrompt
    Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.

    .EXAMPLE
    Reset-SalesforcePlugins -Reinstall -WhatIf
    Preview a clean reinstall of the plugins.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins reset (plugin @oclif/plugin-plugins)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Hard = --hard; -Reinstall = --reinstall.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/@oclif/plugin-plugins

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $false)][switch] $Hard,
        [Parameter(Mandatory = $false)][switch] $Reinstall,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $arguments = @('plugins', 'reset')
    if ($Hard) { $arguments += '--hard' }
    if ($Reinstall) { $arguments += '--reinstall' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    if (-not $PSCmdlet.ShouldProcess('every user-installed and linked Salesforce CLI plugin', 'Remove')) { return }
    return Invoke-SalesforceText -Arguments $arguments -CommonParams $commonParams
}

function Test-SalesforcePluginSignature {
    <#
    .SYNOPSIS
    Checks the digital signature of an npm plugin package.

    .DESCRIPTION
    Runs sf plugins trust verify, which checks that the signature of the npm package matches the signature and key stored at the URLs the CLI expects. It tells you whether the plugin is signed by Salesforce before you install it. It only reads.

    .PARAMETER Npm
    The npm package name, which can include a tag or version, for example @salesforce/plugin-agent@latest. Passed to sf as --npm. Required.

    .PARAMETER Registry
    The npm registry to use. It must be an absolute https:// URL. The CLI default is the registry npm uses. Passed to sf as --registry.

    .EXAMPLE
    Test-SalesforcePluginSignature -Npm @salesforce/plugin-agent
    Is the package signed?

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins trust verify (plugin @salesforce/plugin-trust)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Npm = --npm; -Registry = --registry.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-trust

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9@][A-Za-z0-9@._~/:+#-]*\z')][string] $Npm,
        [Parameter(Mandatory = $false)][string] $Registry
    )
    if ($Registry -and (-not [System.Uri]::TryCreate($Registry, [System.UriKind]::Absolute, [ref]$null) -or -not $Registry.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase))) { throw "-Registry must be an absolute https:// URL. Got '$Registry'." }
    $arguments = @('plugins', 'trust', 'verify', '--npm', $Npm)
    if ($Registry) { $arguments += @('--registry', $Registry) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforcePluginAllowlist {
    <#
    .SYNOPSIS
    Lists the plugins the CLI is allowed to install without a Salesforce signature.

    .DESCRIPTION
    Runs sf plugins trust allowlist list. Plugins on the allowlist can be installed even though they are not signed by Salesforce. It only reads.

    .EXAMPLE
    Get-SalesforcePluginAllowlist
    The allowed unsigned plugins.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins trust allowlist list (plugin @salesforce/plugin-trust)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-trust

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(

    )
    $arguments = @('plugins', 'trust', 'allowlist', 'list', '--json')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Add-SalesforcePluginAllowlist {
    <#
    .SYNOPSIS
    Allows plugins that Salesforce has not signed to be installed.

    .DESCRIPTION
    Runs sf plugins trust allowlist add. This lowers a safety check of the CLI: a plugin on the allowlist installs without a Salesforce signature, so only add a plugin whose code you trust. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. The CLI command has no prompt of its own.

    .PARAMETER Name
    Plugins to allow, as npm package names. Each is passed to sf as its own --name. Passed to sf as --name. Required.

    .PARAMETER NoPrompt
    Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.

    .EXAMPLE
    Add-SalesforcePluginAllowlist -Name my-company-plugin -WhatIf
    Preview allowing a plugin.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins trust allowlist add (plugin @salesforce/plugin-trust)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-trust

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9@][A-Za-z0-9@._~/:+#-]*\z')][string[]] $Name,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $names = @($Name | Where-Object { $_ })
    if ($names.Count -eq 0) { throw 'Give at least one plugin -Name.' }
    $arguments = @('plugins', 'trust', 'allowlist', 'add')
    foreach ($item in $names) { $arguments += @('--name', $item) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    if (-not $PSCmdlet.ShouldProcess(($names -join ', '), 'Allow without a Salesforce signature')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforcePluginAllowlist {
    <#
    .SYNOPSIS
    Takes plugins off the allowlist of unsigned plugins.

    .DESCRIPTION
    Runs sf plugins trust allowlist remove. The plugins can no longer be installed without a Salesforce signature. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. The CLI command has no prompt of its own.

    .PARAMETER Name
    Plugins to remove from the allowlist. Each is passed to sf as its own --name. Passed to sf as --name. Required.

    .PARAMETER NoPrompt
    Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.

    .EXAMPLE
    Remove-SalesforcePluginAllowlist -Name my-company-plugin -WhatIf
    Preview taking a plugin off the list.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins trust allowlist remove (plugin @salesforce/plugin-trust)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-trust

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9@][A-Za-z0-9@._~/:+#-]*\z')][string[]] $Name,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $names = @($Name | Where-Object { $_ })
    if ($names.Count -eq 0) { throw 'Give at least one plugin -Name.' }
    $arguments = @('plugins', 'trust', 'allowlist', 'remove')
    foreach ($item in $names) { $arguments += @('--name', $item) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    if (-not $PSCmdlet.ShouldProcess(($names -join ', '), 'Remove from the allowlist')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion
