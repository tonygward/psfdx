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

#region Projects & Config

function New-SalesforceProject {
    <#
    .SYNOPSIS
    Generates a new Salesforce DX project.

    .DESCRIPTION
    Runs sf template generate project and creates the project folder with sfdx-project.json and the standard layout.

    .PARAMETER Name
    Name of the generated project. Passed to sf as --name. Required.

    .PARAMETER Template
    Template to use for project creation. Passed to sf as --template. Default: standard. Valid values: standard, empty, analytics, reactinternalapp, reactexternalapp, angularinternalapp, angularexternalapp, vueinternalapp, agent.

    .PARAMETER DefaultUserName
    A user name or alias to set as the default target org (target-org) after the project is created. psfdx does this with Set-SalesforceTargetOrg; it is not a flag of the CLI command.

    .PARAMETER OutputDirectory
    Directory for saving the created files. Passed to sf as --output-dir.

    .PARAMETER DefaultPackageDirectory
    Default package directory name. Passed to sf as --default-package-dir.

    .PARAMETER Namespace
    Namespace associated with this project and any connected scratch orgs. Passed to sf as --namespace.

    .PARAMETER GenerateManifest
    Generate a manifest (package.xml) for change-set based development. Adds --manifest.

    .PARAMETER LwcLanguage
    Language of the Lightning web components the project is set up for. Passed to sf as --lwc-language. Valid values: javascript, typescript. The CLI default is javascript.

    .EXAMPLE
    New-SalesforceProject -Name my-project -Template standard
    A standard project in a new folder.

    .EXAMPLE
    New-SalesforceProject -Name my-ts-project -LwcLanguage typescript
    A project that is set up for TypeScript components.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate project (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Template = --template; -OutputDirectory = --output-dir; -DefaultPackageDirectory = --default-package-dir; -Namespace = --namespace; -GenerateManifest = --manifest; -LwcLanguage = --lwc-language.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.
    Also calls these psfdx cmdlets: Set-SalesforceTargetOrg.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string][ValidateSet('standard', 'empty', 'analytics', 'reactinternalapp', 'reactexternalapp', 'angularinternalapp', 'angularexternalapp', 'vueinternalapp', 'agent')] $Template = 'standard',
        [Parameter(Mandatory = $false)][string] $DefaultUserName = $null,

        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $DefaultPackageDirectory,
        [Parameter(Mandatory = $false)][string] $Namespace,
        [Parameter(Mandatory = $false)][switch] $GenerateManifest,
        [Parameter(Mandatory = $false)][ValidateSet('javascript', 'typescript')][string] $LwcLanguage
    )
    $arguments = @('template', 'generate', 'project', '--name', $Name)
    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) {
            throw "Output directory '$OutputDirectory' does not exist."
        }
        $arguments += @('--output-dir', $OutputDirectory)
    }
    if ($DefaultPackageDirectory) { $arguments += @('--default-package-dir', $DefaultPackageDirectory) }
    if ($Namespace) { $arguments += @('--namespace', $Namespace) }
    if ($GenerateManifest) { $arguments += '--manifest' }
    if ($LwcLanguage) { $arguments += @('--lwc-language', $LwcLanguage) }
    $arguments += @('--template', $Template)
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = Show-SalesforceResult -Result $result

    if (($null -ne $DefaultUserName) -and ($DefaultUserName -ne '')) {
        # 'sf config set target-org' writes to whichever project directory it runs in,
        # so set it from inside the newly generated project rather than passing a folder.
        $outputRoot = if ($result.outputDir) { $result.outputDir } else { (Get-Location).Path }
        $projectFolder = Join-Path -Path $outputRoot -ChildPath $Name
        if (-not (Test-Path -LiteralPath $projectFolder -PathType Container)) {
            throw "Generated project folder '$projectFolder' does not exist."
        }
        Push-Location -LiteralPath $projectFolder
        try {
            Set-SalesforceTargetOrg -Value $DefaultUserName @commonParams | Out-Null
        } finally {
            Pop-Location
        }
    }
    return $result
}

function Set-SalesforceTargetOrg {
    <#
    .SYNOPSIS
    Sets the default target org.

    .DESCRIPTION
    Runs sf config set target-org=<value>, for the current project or with -Global for the whole computer. Cmdlets that take -TargetOrg then use this org when you do not give one. Returns the CLI's list of successes.

    .PARAMETER Value
    Username or alias of the org to use by default. Required.

    .PARAMETER Global
    Set it for the whole computer instead of the current project. Adds --global.

    .EXAMPLE
    Set-SalesforceTargetOrg -Value dev1
    Make dev1 the default for this project.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf config set (plugin @salesforce/plugin-settings)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Global = --global.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-settings

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Value,
        [Parameter(Mandatory = $false)][switch] $Global
    )
    $arguments = @('config', 'set', "target-org=$Value")
    if ($Global) { $arguments += '--global' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return (Show-SalesforceResult -Result $result).successes
}

function Get-SalesforceTargetOrg {
    <#
    .SYNOPSIS
    Shows the default target org configured for the CLI.

    .DESCRIPTION
    Runs sf config get target-org and returns the value with where it is set (Local or Global). With -Global only the global setting is returned.

    .PARAMETER Global
    Return only the global value (set for the whole computer), not a project-local one. The filter runs in PowerShell.

    .EXAMPLE
    Get-SalesforceTargetOrg
    The org that cmdlets use when you give no -TargetOrg.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf config get (plugin @salesforce/plugin-settings)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --verbose
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-settings

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Global
    )
    # 'sf config get' has no --global flag. Every entry it returns says whether it is Local or Global, so -Global filters on that.
    $arguments = @('config', 'get', 'target-org', '--json')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $records = Show-SalesforceResult -Result $result
    if ($Global) { return @($records | Where-Object { $_.location -eq 'Global' }) }
    return $records
}

function Remove-SalesforceTargetOrg {
    <#
    .SYNOPSIS
    Clears the default target org setting.

    .DESCRIPTION
    Runs sf config unset target-org, locally or with -Global for the whole computer. Only configuration changes; no org is touched. Returns the CLI's list of successes.

    .PARAMETER Global
    Clear the global setting instead of the one for the current project. Adds --global.

    .EXAMPLE
    Remove-SalesforceTargetOrg
    Forget the project's default target org.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf config unset (plugin @salesforce/plugin-settings)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Global = --global.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-settings

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Global
    )
    $arguments = @('config', 'unset', 'target-org')
    if ($Global) { $arguments += '--global' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return (Show-SalesforceResult -Result $result).successes
}

function Get-SalesforceConfig {
    <#
    .SYNOPSIS
    Lists the Salesforce CLI configuration variables that are set.

    .DESCRIPTION
    Runs sf config list and returns one object per variable (name, value, location: Local or Global).

    .EXAMPLE
    Get-SalesforceConfig
    Every variable that is set.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf config list (plugin @salesforce/plugin-settings)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-settings

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param()
    $arguments = @('config', 'list', '--json')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    Show-SalesforceResult -Result $result
}

function Set-SalesforceTargetDevHub {
    <#
    .SYNOPSIS
    Sets the default Dev Hub.

    .DESCRIPTION
    Runs sf config set target-dev-hub=<value>, for the current project or with -Global for the whole computer. Returns the CLI's list of successes.

    .PARAMETER Value
    Username or alias of the Dev Hub org. Required.

    .PARAMETER Global
    Set it for the whole computer instead of the current project. Adds --global.

    .EXAMPLE
    Set-SalesforceTargetDevHub -Value devhub -Global
    Use the org with alias devhub as the Dev Hub everywhere.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf config set (plugin @salesforce/plugin-settings)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Global = --global.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-settings

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Value,
        [Parameter(Mandatory = $false)][switch] $Global
    )

    $arguments = @('config', 'set', "target-dev-hub=$Value")
    if ($Global) { $arguments += '--global' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return (Show-SalesforceResult -Result $result).successes
}

function Get-SalesforceTargetDevHub {
    <#
    .SYNOPSIS
    Shows the default Dev Hub configured for the CLI.

    .DESCRIPTION
    Runs sf config get target-dev-hub and returns the value with where it is set (Local or Global). With -Global only the global setting is returned.

    .PARAMETER Global
    Return only the global value (set for the whole computer), not a project-local one. The filter runs in PowerShell.

    .EXAMPLE
    Get-SalesforceTargetDevHub
    The Dev Hub that new scratch orgs are created from.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf config get (plugin @salesforce/plugin-settings)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --verbose
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-settings

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Global
    )

    # 'sf config get' has no --global flag. Every entry it returns says whether it is Local or Global, so -Global filters on that.
    $arguments = @('config', 'get', 'target-dev-hub', '--json')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $records = Show-SalesforceResult -Result $result
    if ($Global) { return @($records | Where-Object { $_.location -eq 'Global' }) }
    return $records
}

function Remove-SalesforceTargetDevHub {
    <#
    .SYNOPSIS
    Clears the default Dev Hub setting.

    .DESCRIPTION
    Runs sf config unset target-dev-hub, locally or with -Global for the whole computer. Only configuration changes; no org is touched. Returns the CLI's list of successes.

    .PARAMETER Global
    Clear the global setting instead of the one for the current project. Adds --global.

    .EXAMPLE
    Remove-SalesforceTargetDevHub -Global
    Forget the global default Dev Hub.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf config unset (plugin @salesforce/plugin-settings)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Global = --global.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-settings

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Global
    )
    $arguments = @('config', 'unset', 'target-dev-hub')
    if ($Global) { $arguments += '--global' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return (Show-SalesforceResult -Result $result).successes
}

#endregion

#region Scratch Orgs

function Get-SalesforceScratchOrgs {
    <#
    .SYNOPSIS
    Lists the scratch orgs this computer knows about.

    .DESCRIPTION
    Runs sf org list --all and returns the scratch orgs (orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias). With -Last only the most recently used one is returned. 

    .PARAMETER SkipConnectionStatus
    Skip retrieving the connection status of non-scratch orgs. Adds --skip-connection-status.

    .PARAMETER Last
    Return only the scratch org with the latest lastUsed date. The sorting happens in PowerShell.

    .EXAMPLE
    Get-SalesforceScratchOrgs | Where-Object connectedStatus -eq 'Connected'
    Scratch orgs that are reachable.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org list (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -SkipConnectionStatus = --skip-connection-status.
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

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org create scratch (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetDevHub = --target-dev-hub; -SetDefault = --set-default; -DurationDays = --duration-days; -DefinitionFile = --definition-file; -WaitMinutes = --wait; -Async = --async; -Edition = --edition; -Snapshot = --snapshot; -AdminEmail = --admin-email; -Description = --description; -Name = --name; -Release = --release; -SourceOrgId = --source-org; -AdminUsername = --username; -Alias = --alias; -OAuthClientId = --client-id; -NoAncestors = --no-ancestors; -NoNamespace = --no-namespace; -NoTrackSource = --no-track-source.
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

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org resume scratch (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -JobId = --job-id; -WaitMinutes = --wait.
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

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org. Required.

    .PARAMETER NoPrompt
    Don't prompt the user to confirm the deletion. Adds --no-prompt.

    .EXAMPLE
    Remove-SalesforceScratchOrg -TargetOrg ci-1 -WhatIf
    Show which org would be deleted.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org delete scratch (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org; -NoPrompt = --no-prompt.
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

    .EXAMPLE
    Remove-SalesforceScratchOrgs -WhatIf
    List the orgs that would be deleted.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Get-SalesforceScratchOrgs, Remove-SalesforceScratchOrg. They run the sf commands; this cmdlet adds PowerShell logic on top.

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

#region Org Source Tracking

function Enable-SalesforceSourceTracking {
    <#
    .SYNOPSIS
    Turns source tracking on for an org that allows it.

    .DESCRIPTION
    Runs sf org enable tracking. Source tracking lets deploy and retrieve report what changed between your project and the org. It can be enabled only in an org that supports it, such as a sandbox that was created with source tracking turned off. Supports -WhatIf.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Enable-SalesforceSourceTracking -TargetOrg dev1
    Turn source tracking on for dev1.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org enable tracking (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org.
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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('org', 'enable', 'tracking')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $target = if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $TargetOrg } else { 'default target org' }
    if ($PSCmdlet.ShouldProcess($target, 'Enable source tracking')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Disable-SalesforceSourceTracking {
    <#
    .SYNOPSIS
    Turns source tracking off for an org.

    .DESCRIPTION
    Runs sf org disable tracking. After it, deploy and retrieve no longer report what changed between your project and the org, and source tracking may not be possible to turn on again for that org. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question.

    .PARAMETER NoPrompt
    Don't ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Disable-SalesforceSourceTracking -TargetOrg dev1 -WhatIf
    Preview the change without making it.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org disable tracking (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org.
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
    $arguments = @('org', 'disable', 'tracking')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    $target = if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $TargetOrg } else { 'default target org' }
    if ($PSCmdlet.ShouldProcess($target, 'Disable source tracking')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

#endregion

#region Org Shapes and Snapshots

function New-SalesforceOrgShape {
    <#
    .SYNOPSIS
    Creates an org shape from an org.

    .DESCRIPTION
    Runs sf org create shape. An org shape records the edition, features and settings of the source org, so that scratch orgs can be created to match it (see New-SalesforceScratchOrg -SourceOrgId). The org must have Scratch Org Shape turned on.

    .PARAMETER TargetOrg
    Username or alias of the org to take the shape from. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceOrgShape -TargetOrg prod
    Create a shape from the prod org.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org create shape (plugin @salesforce/plugin-signups)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-signups

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('org', 'create', 'shape')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $target = if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $TargetOrg } else { 'default target org' }
    if ($PSCmdlet.ShouldProcess($target, 'Create org shape')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Get-SalesforceOrgShapes {
    <#
    .SYNOPSIS
    Lists the org shapes of the orgs this computer is logged in to.

    .DESCRIPTION
    Runs sf org list shape and returns one object per shape (the org it came from, the shape ID, its status and when it was created).

    .EXAMPLE
    Get-SalesforceOrgShapes | Format-Table
    List every shape.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org list shape (plugin @salesforce/plugin-signups)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-signups

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param()
    $arguments = @('org', 'list', 'shape', '--json')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceOrgShape {
    <#
    .SYNOPSIS
    Deletes the org shapes of an org.

    .DESCRIPTION
    Runs sf org delete shape. This cannot be undone, and scratch orgs can no longer be created from the deleted shape. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time.

    .PARAMETER NoPrompt
    Don't ask for confirmation. Skips the PowerShell confirmation; psfdx always passes --no-prompt to the CLI after it has confirmed.

    .PARAMETER TargetOrg
    Username or alias of the org whose shapes are deleted. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceOrgShape -TargetOrg prod -WhatIf
    Preview the delete.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org delete shape (plugin @salesforce/plugin-signups)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org. psfdx always passes --no-prompt, because it asks first.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-signups

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
    $arguments = @('org', 'delete', 'shape')
    # psfdx asks first (or the caller said not to), so the CLI must not ask a second time.
    $arguments += '--no-prompt'
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    $target = if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $TargetOrg } else { 'default target org' }
    if ($PSCmdlet.ShouldProcess($target, 'Delete org shapes')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function New-SalesforceOrgSnapshot {
    <#
    .SYNOPSIS
    Creates a scratch org snapshot from an org.

    .DESCRIPTION
    Runs sf org create snapshot. A snapshot is a copy of a scratch org that you can create new scratch orgs from (see New-SalesforceScratchOrg -Snapshot). The snapshot is made in the Dev Hub. Snapshots are a pilot feature of Salesforce. Creation is asynchronous: use Get-SalesforceOrgSnapshot to see when it is ready.

    .PARAMETER SourceOrg
    Username or alias of the scratch org to copy. Passed to sf as --source-org. Required.

    .PARAMETER SnapshotName
    Name of the snapshot. Passed to sf as --name. Required.

    .PARAMETER Description
    Description of the snapshot. Passed to sf as --description.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    New-SalesforceOrgSnapshot -SourceOrg my-scratch -SnapshotName Release1 -Description 'Before the upgrade' -TargetDevHub devhub
    Take a snapshot of a scratch org.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org create snapshot (plugin @salesforce/plugin-signups)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -SourceOrg = --source-org; -SnapshotName = --name; -Description = --description; -TargetDevHub = --target-dev-hub.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-signups

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $SourceOrg,
        [Parameter(Mandatory = $true)][string] $SnapshotName,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('org', 'create', 'snapshot', '--source-org', $SourceOrg, '--name', $SnapshotName)
    if ($Description) { $arguments += @('--description', $Description) }
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($PSCmdlet.ShouldProcess($SnapshotName, "Create snapshot of $SourceOrg")) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Get-SalesforceOrgSnapshot {
    <#
    .SYNOPSIS
    Shows one scratch org snapshot, including whether it is ready to use.

    .DESCRIPTION
    Runs sf org get snapshot for the snapshot name or ID. Use Get-SalesforceOrgSnapshots to list them all.

    .PARAMETER Snapshot
    Name or ID of the snapshot. Passed to sf as --snapshot. Required.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Get-SalesforceOrgSnapshot -Snapshot Release1 -TargetDevHub devhub
    Show the status of the snapshot.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org get snapshot (plugin @salesforce/plugin-signups)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Snapshot = --snapshot; -TargetDevHub = --target-dev-hub.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-signups

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Snapshot,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('org', 'get', 'snapshot', '--snapshot', $Snapshot)
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceOrgSnapshots {
    <#
    .SYNOPSIS
    Lists the scratch org snapshots of a Dev Hub.

    .DESCRIPTION
    Runs sf org list snapshot and returns one object per snapshot (name, ID, status, source org and when it was created).

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Get-SalesforceOrgSnapshots -TargetDevHub devhub | Format-Table
    List the snapshots of the Dev Hub.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org list snapshot (plugin @salesforce/plugin-signups)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetDevHub = --target-dev-hub.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-signups

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('org', 'list', 'snapshot')
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceOrgSnapshot {
    <#
    .SYNOPSIS
    Deletes a scratch org snapshot.

    .DESCRIPTION
    Runs sf org delete snapshot. This cannot be undone. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time.

    .PARAMETER Snapshot
    Name or ID of the snapshot to delete. Passed to sf as --snapshot. Required.

    .PARAMETER NoPrompt
    Don't ask for confirmation. Skips the PowerShell confirmation; psfdx always passes --no-prompt to the CLI after it has confirmed.

    .PARAMETER TargetDevHub
    Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

    .EXAMPLE
    Remove-SalesforceOrgSnapshot -Snapshot Release1 -TargetDevHub devhub -WhatIf
    Preview the delete.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org delete snapshot (plugin @salesforce/plugin-signups)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Snapshot = --snapshot; -TargetDevHub = --target-dev-hub. psfdx always passes --no-prompt, because it asks first.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-signups

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string] $Snapshot,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $arguments = @('org', 'delete', 'snapshot', '--snapshot', $Snapshot)
    # psfdx asks first (or the caller said not to), so the CLI must not ask a second time.
    $arguments += '--no-prompt'
    if ($PSBoundParameters.ContainsKey('TargetDevHub') -and -not [string]::IsNullOrWhiteSpace($TargetDevHub)) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    if ($PSCmdlet.ShouldProcess($Snapshot, 'Delete snapshot')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

#endregion

#region Code Analyzer

# Wraps `sf code-analyzer run` and `sf code-analyzer rules`. These commands have no --json flag: the machine-readable output is a file
# written with --output-file, so each call asks for a temporary JSON file and reads it, and uses the process exit code to tell a threshold
# failure (non-zero exit, report written) from a plugin or engine problem (no report).

function Read-SalesforceCodeAnalyzerReport {
    # Private: reads the JSON report file the CLI wrote; returns $null when it is missing or not JSON.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return ($text | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function New-SalesforceCodeAnalyzerReportPath {
    # Private: a unique temporary path for the CLI's JSON report.
    [CmdletBinding()]
    Param()

    return (Join-Path ([System.IO.Path]::GetTempPath()) ('psfdx-code-analyzer-' + [guid]::NewGuid().ToString('N') + '.json'))
}

function Get-SalesforceCodeAnalyzerFailureMessage {
    # Private: the CLI's text output as the message, with install guidance when the code-analyzer command does not exist.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][AllowNull()] $Output
    )

    $message = (@($Output) | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($message)) { $message = 'The Salesforce CLI returned no output.' }
    if ($message -match 'is not a sf command|command code-analyzer.*not found|not.*installed') {
        $message += " Install the plugin with Install-SalesforcePlugin -Name code-analyzer (or 'sf plugins install code-analyzer'). Code Analyzer also needs Java 11 or later for its Java-based engines, and it downloads engine dependencies the first time they are used."
    }
    return $message
}

function Invoke-SalesforceCodeAnalyzer {
    <#
    .SYNOPSIS
    Runs Salesforce Code Analyzer over a workspace and returns the findings as objects (sf code-analyzer run).

    .DESCRIPTION
    Returns one object with Passed, ThresholdExceeded, ViolationCount, a count per severity, Violations (one object per finding with Rule,
    Engine, Severity, Message, File, StartLine, StartColumn, EndLine, EndColumn, Tags, Resources, and Fixes and Suggestions when the CLI reports them), RunDirectory and Versions.
    With -SeverityThreshold the CLI fails when a finding is at or above that severity. That is a threshold failure, not an error: the findings
    are still returned (the exit code is non-zero but the report is written) with Passed = $false and ThresholdExceeded = $true. Add -ThrowOnThreshold to turn it into an error (id
    PsfdxCodeAnalyzerThresholdExceeded, with the result as the target object) so a CI step fails. If the plugin or an engine cannot start there is
    no report, and the cmdlet always throws (id PsfdxCodeAnalyzerFailed) with the CLI message.
    The plugin is installed with the Salesforce CLI or with Install-SalesforcePlugin. Engines such as PMD and the Java-based rules need Java 11 or later;
    the CLI downloads engine dependencies on first use, so the first run can be slow and needs network access.

    .PARAMETER Workspace
    Set of files that make up your workspace. Passed to sf as --workspace.

    .PARAMETER Target
    Subset of files within your workspace to be targeted for analysis. Passed to sf as --target.

    .PARAMETER RuleSelector
    Selection of rules, based on engine name, severity level, rule name, tag, or a combination of criteria separated by colons. Passed to sf as --rule-selector.

    .PARAMETER ConfigFile
    Path to the configuration file used to customize the engines and rules. Passed to sf as --config-file.

    .PARAMETER SeverityThreshold
    Severity level of a found violation that must be met or exceeded to cause this command to fail with a non-zero exit code. Passed to sf as --severity-threshold. Valid values: 1, 2, 3, 4, 5, Critical, High, Moderate, Low, Info.

    .PARAMETER ThrowOnThreshold
    Throw an error (id PsfdxCodeAnalyzerThresholdExceeded, with the result as its target object) when a finding meets -SeverityThreshold, instead of returning the findings with ThresholdExceeded set. Meant for CI.

    .PARAMETER IncludeFixes
    Include fix data for the violations that have one. Each violation then has a Fixes property, as the CLI reports it. Adds --include-fixes.

    .PARAMETER IncludeSuggestions
    Include suggestion data for the violations that have one. Each violation then has a Suggestions property, as the CLI reports it. Adds --include-suggestions.

    .PARAMETER NoSuppressions
    Do not process inline and bulk suppression markers, so suppressed violations are reported again. Adds --no-suppressions.

    .PARAMETER TargetOrg
    Username or alias of the org that remote analysis engines use, such as the engine that needs an org connection. Passed to sf as --target-org.

    .PARAMETER View
    How the CLI displays the results in the terminal. Passed to sf as --view. Valid values: detail, table. The cmdlet reads the results from a report file, so this changes only the text the CLI prints, not the returned object.

    .PARAMETER OutputFile
    Extra files to write the results to, in addition to the object that is returned. The file format follows each extension, such as .csv, .html or .xml. Each one is passed to sf as its own --output-file. The folders must exist.

    .EXAMPLE
    Invoke-SalesforceCodeAnalyzer -Workspace force-app -RuleSelector Recommended -SeverityThreshold 2 -ThrowOnThreshold

    .EXAMPLE
    (Invoke-SalesforceCodeAnalyzer -Workspace . -Target force-app/main/default/classes).Violations | Group-Object Rule | Sort-Object Count -Descending

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf code-analyzer run (plugin @salesforce/plugin-code-analyzer)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Workspace = --workspace; -Target = --target; -RuleSelector = --rule-selector; -ConfigFile = --config-file; -SeverityThreshold = --severity-threshold; -IncludeFixes = --include-fixes; -IncludeSuggestions = --include-suggestions; -NoSuppressions = --no-suppressions; -TargetOrg = --target-org; -View = --view; -OutputFile = --output-file (psfdx also passes its own temporary --output-file to read the results).
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-code-analyzer

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string[]] $Workspace,
        [Parameter(Mandatory = $false)][string[]] $Target,
        [Parameter(Mandatory = $false)][string[]] $RuleSelector,
        [Parameter(Mandatory = $false)][string] $ConfigFile,
        [Parameter(Mandatory = $false)][ValidateSet('1', '2', '3', '4', '5', 'Critical', 'High', 'Moderate', 'Low', 'Info')][string] $SeverityThreshold,
        [Parameter(Mandatory = $false)][switch] $ThrowOnThreshold,
        [Parameter(Mandatory = $false)][switch] $IncludeFixes,
        [Parameter(Mandatory = $false)][switch] $IncludeSuggestions,
        [Parameter(Mandatory = $false)][switch] $NoSuppressions,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][ValidateSet('detail', 'table')][string] $View,
        [Parameter(Mandatory = $false)][string[]] $OutputFile
    )

    foreach ($path in @($Workspace)) {
        if ($path -and -not (Test-Path -LiteralPath $path)) { throw "Workspace path '$path' does not exist." }
    }
    foreach ($file in @($OutputFile)) {
        if (-not $file) { continue }
        $parent = Split-Path -Path $file -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Output folder '$parent' does not exist." }
    }
    if ($ConfigFile -and -not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) { throw "Config file '$ConfigFile' does not exist." }

    $report = New-SalesforceCodeAnalyzerReportPath
    $arguments = @('code-analyzer', 'run')
    foreach ($w in @($Workspace)) { if ($w) { $arguments += @('--workspace', $w) } }
    foreach ($t in @($Target)) { if ($t) { $arguments += @('--target', $t) } }
    foreach ($r in @($RuleSelector)) { if ($r) { $arguments += @('--rule-selector', $r) } }
    if ($ConfigFile) { $arguments += @('--config-file', $ConfigFile) }
    if ($SeverityThreshold) { $arguments += @('--severity-threshold', $SeverityThreshold) }
    if ($IncludeFixes) { $arguments += '--include-fixes' }
    if ($IncludeSuggestions) { $arguments += '--include-suggestions' }
    if ($NoSuppressions) { $arguments += '--no-suppressions' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($View) { $arguments += @('--view', $View) }
    foreach ($file in @($OutputFile)) { if ($file) { $arguments += @('--output-file', $file) } }
    $arguments += @('--output-file', $report)
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('ThrowOnThreshold')

    try {
        $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        # Invoke-Salesforce leaves the process exit code in $global:LASTEXITCODE; without --json it does not throw on a failing exit.
        $exitCode = $global:LASTEXITCODE
        $data = Read-SalesforceCodeAnalyzerReport -Path $report
        $failed = ($exitCode -ne 0)
        if ($null -eq $data) {
            $message = Get-SalesforceCodeAnalyzerFailureMessage -Output $output
            if (-not $failed) { $message = "Code Analyzer finished but wrote no report. $message" }
            $errorRecord = New-Object System.Management.Automation.ErrorRecord ([System.Exception]::new($message)), 'PsfdxCodeAnalyzerFailed', ([System.Management.Automation.ErrorCategory]::InvalidResult), $output
            throw $errorRecord
        }
    } finally {
        if (Test-Path -LiteralPath $report) { Remove-Item -LiteralPath $report -Force -ErrorAction SilentlyContinue }
    }

    $violations = @()
    $reported = @()
    if ($data.PSObject.Properties.Name -contains 'violations' -and $null -ne $data.violations) { $reported = @($data.violations) }
    foreach ($v in $reported) {
        $locations = @()
        if ($v.PSObject.Properties.Name -contains 'locations' -and $null -ne $v.locations) { $locations = @($v.locations) }
        $index = 0
        if ($v.PSObject.Properties.Name -contains 'primaryLocationIndex' -and $null -ne $v.primaryLocationIndex) { $index = [int]$v.primaryLocationIndex }
        $loc = $null
        if ($index -ge 0 -and $index -lt $locations.Count) { $loc = $locations[$index] }
        $field = {
            param($Obj, $Name)
            if ($null -ne $Obj -and $Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
            return $null
        }
        $violations += [pscustomobject]@{
            Rule        = (& $field $v 'rule')
            Engine      = (& $field $v 'engine')
            Severity    = (& $field $v 'severity')
            Message     = (& $field $v 'message')
            File        = (& $field $loc 'file')
            StartLine   = (& $field $loc 'startLine')
            StartColumn = (& $field $loc 'startColumn')
            EndLine     = (& $field $loc 'endLine')
            EndColumn   = (& $field $loc 'endColumn')
            Tags        = @(& $field $v 'tags')
            Resources   = @(& $field $v 'resources')
            Fixes       = (& $field $v 'fixes')
            Suggestions = (& $field $v 'suggestions')
        }
    }

    $counts = $null
    if ($data.PSObject.Properties.Name -contains 'violationCounts') { $counts = $data.violationCounts }
    $countOf = {
        param($Name)
        if ($null -ne $counts -and $counts.PSObject.Properties.Name -contains $Name -and $null -ne $counts.$Name) { return [int]$counts.$Name }
        return 0
    }
    $total = $violations.Count
    if ($null -ne $counts -and $counts.PSObject.Properties.Name -contains 'total' -and $null -ne $counts.total) { $total = [int]$counts.total }
    $thresholdExceeded = $failed
    $runDir = $null
    if ($data.PSObject.Properties.Name -contains 'runDir') { $runDir = $data.runDir }
    $versions = $null
    if ($data.PSObject.Properties.Name -contains 'versions') { $versions = $data.versions }

    $result = [pscustomobject]@{
        Passed            = (-not $thresholdExceeded)
        ThresholdExceeded = $thresholdExceeded
        ViolationCount    = $total
        Critical          = (& $countOf 'sev1')
        High              = (& $countOf 'sev2')
        Moderate          = (& $countOf 'sev3')
        Low               = (& $countOf 'sev4')
        Info              = (& $countOf 'sev5')
        Violations        = $violations
        RunDirectory      = $runDir
        Versions          = $versions
    }
    if ($thresholdExceeded -and $ThrowOnThreshold) {
        $message = "Code Analyzer found $total violation(s) at or above severity threshold '$SeverityThreshold'."
        $errorRecord = New-Object System.Management.Automation.ErrorRecord ([System.Exception]::new($message)), 'PsfdxCodeAnalyzerThresholdExceeded', ([System.Management.Automation.ErrorCategory]::InvalidResult), $result
        throw $errorRecord
    }
    return $result
}

function Get-SalesforceCodeAnalyzerRule {
    <#
    .SYNOPSIS
    Lists the Code Analyzer rules that match a selector (sf code-analyzer rules).

    .DESCRIPTION
    Returns one object per rule (as the CLI reports it: name, engine, severity, tags, description, resources). The CLI has no --json flag, so the rules are read from a temporary JSON report file. With no selector the CLI lists
    its default rules. A selector such as Recommended, Security, pmd or pmd:Security narrows the list. A plugin or engine failure throws the CLI message with install guidance.

    .PARAMETER RuleSelector
    Selection of rules, based on engine name, severity level, rule name, tag, or a combination of criteria separated by colons. Passed to sf as --rule-selector.

    .PARAMETER Workspace
    Set of files that make up your workspace. Passed to sf as --workspace.

    .PARAMETER Target
    Subset of files within your workspace that you want to target for analysis. Passed to sf as --target.

    .PARAMETER ConfigFile
    Path to the configuration file used to customize the engines and rules. Passed to sf as --config-file.

    .PARAMETER View
    How the CLI displays the rules in the terminal. Passed to sf as --view. Valid values: detail, table. The cmdlet reads the rules from a report file, so this changes only the text the CLI prints, not the returned objects.

    .EXAMPLE
    Get-SalesforceCodeAnalyzerRule -RuleSelector Security | Select-Object name, engine, severity

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf code-analyzer rules (plugin @salesforce/plugin-code-analyzer)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -RuleSelector = --rule-selector; -Workspace = --workspace; -Target = --target; -ConfigFile = --config-file; -View = --view.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-code-analyzer

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string[]] $RuleSelector,
        [Parameter(Mandatory = $false)][string[]] $Workspace,
        [Parameter(Mandatory = $false)][string[]] $Target,
        [Parameter(Mandatory = $false)][string] $ConfigFile,
        [Parameter(Mandatory = $false)][ValidateSet('detail', 'table')][string] $View
    )

    foreach ($path in @($Workspace)) {
        if ($path -and -not (Test-Path -LiteralPath $path)) { throw "Workspace path '$path' does not exist." }
    }
    if ($ConfigFile -and -not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) { throw "Config file '$ConfigFile' does not exist." }

    $report = New-SalesforceCodeAnalyzerReportPath
    $arguments = @('code-analyzer', 'rules')
    foreach ($r in @($RuleSelector)) { if ($r) { $arguments += @('--rule-selector', $r) } }
    foreach ($w in @($Workspace)) { if ($w) { $arguments += @('--workspace', $w) } }
    foreach ($t in @($Target)) { if ($t) { $arguments += @('--target', $t) } }
    if ($ConfigFile) { $arguments += @('--config-file', $ConfigFile) }
    if ($View) { $arguments += @('--view', $View) }
    $arguments += @('--output-file', $report)
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters

    try {
        $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        $exitCode = $global:LASTEXITCODE
        $data = Read-SalesforceCodeAnalyzerReport -Path $report
    } finally {
        if (Test-Path -LiteralPath $report) { Remove-Item -LiteralPath $report -Force -ErrorAction SilentlyContinue }
    }

    if ($exitCode -ne 0 -or $null -eq $data) {
        $message = Get-SalesforceCodeAnalyzerFailureMessage -Output $output
        $errorRecord = New-Object System.Management.Automation.ErrorRecord ([System.Exception]::new($message)), 'PsfdxCodeAnalyzerFailed', ([System.Management.Automation.ErrorCategory]::InvalidResult), $output
        throw $errorRecord
    }
    if ($data -is [System.Array]) { return @($data) }
    # A report holding a single bare rule object is unrolled by PowerShell from a one-element array.
    if ($data.PSObject.Properties.Name -contains 'name' -and $data.PSObject.Properties.Name -notcontains 'rules') { return @($data) }
    if ($data.PSObject.Properties.Name -contains 'rules' -and $null -ne $data.rules) { return @($data.rules) }
    return @()
}

function Get-SalesforceCodeAnalyzerConfig {
    <#
    .SYNOPSIS
    Shows the current Code Analyzer configuration as YAML.

    .DESCRIPTION
    Runs sf code-analyzer config and returns the configuration as one YAML string: the top-level settings and the engine and rule overrides for the selected rules, with any code-analyzer.yml in the current folder (or -ConfigFile) applied. The CLI has no --json flag, so the YAML is read from a file. Give -OutputFile to keep that file, for example to save the state as the new code-analyzer.yml (the CLI keeps the values and overwrites the comments); without it a temporary file is used and removed. A plugin or engine failure throws the CLI message with install guidance.

    .PARAMETER Workspace
    Set of files that make up your workspace. Each is passed to sf as its own --workspace. Each must exist. Passed to sf as --workspace.

    .PARAMETER Target
    Subset of files within your workspace to target. Each is passed to sf as its own --target. Passed to sf as --target.

    .PARAMETER RuleSelector
    Selection of rules, based on engine name, severity level, rule name, tag, or a combination of criteria. Each is passed to sf as its own --rule-selector. The CLI default is all. Passed to sf as --rule-selector.

    .PARAMETER ConfigFile
    Path to an existing configuration file to start from. It must exist. Passed to sf as --config-file.

    .PARAMETER OutputFile
    File to write the configuration state to, in YAML. The folder must exist. An existing file is overwritten. Passed to sf as --output-file.

    .PARAMETER IncludeUnmodifiedRules
    Also list the rules whose settings have not been changed, in the rule override settings. Adds --include-unmodified-rules.

    .PARAMETER NoSuppressions
    Leave suppressions out of the output configuration. Adds --no-suppressions.

    .EXAMPLE
    Get-SalesforceCodeAnalyzerConfig
    The YAML for all rules, with the code-analyzer.yml of the current folder applied.

    .EXAMPLE
    Get-SalesforceCodeAnalyzerConfig -ConfigFile .\code-analyzer.yml -OutputFile .\code-analyzer.yml | Out-Null
    Rewrite the configuration file with its current state.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf code-analyzer config (plugin @salesforce/plugin-code-analyzer)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Workspace = --workspace; -Target = --target; -RuleSelector = --rule-selector; -ConfigFile = --config-file; -OutputFile = --output-file; -IncludeUnmodifiedRules = --include-unmodified-rules; -NoSuppressions = --no-suppressions.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-code-analyzer

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string[]] $Workspace,
        [Parameter(Mandatory = $false)][string[]] $Target,
        [Parameter(Mandatory = $false)][string[]] $RuleSelector,
        [Parameter(Mandatory = $false)][string] $ConfigFile,
        [Parameter(Mandatory = $false)][string] $OutputFile,
        [Parameter(Mandatory = $false)][switch] $IncludeUnmodifiedRules,
        [Parameter(Mandatory = $false)][switch] $NoSuppressions
    )
    foreach ($path in @($Workspace)) {
        if ($path -and -not (Test-Path -LiteralPath $path)) { throw "Workspace path '$path' does not exist." }
    }
    if ($ConfigFile -and -not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) { throw "Config file '$ConfigFile' does not exist." }
    if ($OutputFile) {
        $parent = Split-Path -Path $OutputFile -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Output folder '$parent' does not exist." }
    }
    $report = $null
    if ($OutputFile) { $report = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile) }
    if (-not $report) { $report = [System.IO.Path]::ChangeExtension((New-SalesforceCodeAnalyzerReportPath), '.yml') }
    $arguments = @('code-analyzer', 'config')
    foreach ($w in @($Workspace)) { if ($w) { $arguments += @('--workspace', $w) } }
    foreach ($t in @($Target)) { if ($t) { $arguments += @('--target', $t) } }
    foreach ($r in @($RuleSelector)) { if ($r) { $arguments += @('--rule-selector', $r) } }
    if ($ConfigFile) { $arguments += @('--config-file', $ConfigFile) }
    $arguments += @('--output-file', $report)
    if ($IncludeUnmodifiedRules) { $arguments += '--include-unmodified-rules' }
    if ($NoSuppressions) { $arguments += '--no-suppressions' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $yaml = $null
    try {
        $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        $exitCode = $global:LASTEXITCODE
        if (Test-Path -LiteralPath $report -PathType Leaf) { $yaml = [System.IO.File]::ReadAllText($report, [System.Text.Encoding]::UTF8) }
    } finally {
        if (-not $OutputFile -and (Test-Path -LiteralPath $report)) { Remove-Item -LiteralPath $report -Force -ErrorAction SilentlyContinue }
    }
    if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($yaml)) {
        $message = Get-SalesforceCodeAnalyzerFailureMessage -Output $output
        $errorRecord = New-Object System.Management.Automation.ErrorRecord ([System.Exception]::new($message)), 'PsfdxCodeAnalyzerFailed', ([System.Management.Automation.ErrorCategory]::InvalidResult), $output
        throw $errorRecord
    }
    return $yaml
}

function Get-SalesforceCodeAnalyzerAst {
    <#
    .SYNOPSIS
    Shows the syntax tree that PMD builds for a source file.

    .DESCRIPTION
    Runs sf code-analyzer ast-dump. The AST is what PMD sees when it parses the file, which helps you write and debug custom PMD rules. It works for Apex, Visualforce, HTML, XML and JavaScript files, and it needs Java 11 or later. The CLI writes the tree to a file, so psfdx reads that file: with -Format json (the default here) you get one object per node, with its name, attributes, parent and ancestors, as the CLI reports them; with -Format xml you get the raw tree as an XML document. Give -OutputFile to keep the file; without it a temporary file is used and removed.

    .PARAMETER File
    Path of the source file to parse. It must exist and be a file, not a folder. Passed to sf as --file. Required.

    .PARAMETER Language
    Language of the source file. By default the CLI uses apex. Valid values: apex, visualforce, html, xml, javascript. Passed to sf as --language.

    .PARAMETER Format
    Format of the tree. Valid values: json, xml. The CLI default is xml; this cmdlet uses json unless you say otherwise, because it gives objects. Passed to sf as --format.

    .PARAMETER OutputFile
    File to write the tree to. The folder must exist. An existing file is overwritten. Passed to sf as --output-file.

    .EXAMPLE
    Get-SalesforceCodeAnalyzerAst -File .\force-app\main\default\classes\MyClass.cls | Select-Object -First 5
    The first nodes of an Apex class's tree.

    .EXAMPLE
    ([xml](Get-SalesforceCodeAnalyzerAst -File .\page.page -Language visualforce -Format xml)).OuterXml
    The raw XML tree of a Visualforce page.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf code-analyzer ast-dump (plugin @salesforce/plugin-code-analyzer)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -File = --file; -Language = --language; -Format = --format; -OutputFile = --output-file.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-code-analyzer

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $File,
        [Parameter(Mandatory = $false)][ValidateSet('apex', 'visualforce', 'html', 'xml', 'javascript')][string] $Language,
        [Parameter(Mandatory = $false)][ValidateSet('json', 'xml')][string] $Format,
        [Parameter(Mandatory = $false)][string] $OutputFile
    )
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "Source file '$File' does not exist." }
    if (-not $PSBoundParameters.ContainsKey('Format')) { $Format = 'json' }
    if ($OutputFile) {
        $parent = Split-Path -Path $OutputFile -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Output folder '$parent' does not exist." }
    }
    $report = $null
    if ($OutputFile) { $report = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile) }
    if (-not $report) { $report = [System.IO.Path]::ChangeExtension((New-SalesforceCodeAnalyzerReportPath), '.' + $Format) }
    $arguments = @('code-analyzer', 'ast-dump', '--file', $File)
    if ($Language) { $arguments += @('--language', $Language) }
    $arguments += @('--format', $Format, '--output-file', $report)
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $text = $null
    try {
        $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        $exitCode = $global:LASTEXITCODE
        if (Test-Path -LiteralPath $report -PathType Leaf) { $text = [System.IO.File]::ReadAllText($report, [System.Text.Encoding]::UTF8) }
    } finally {
        if (-not $OutputFile -and (Test-Path -LiteralPath $report)) { Remove-Item -LiteralPath $report -Force -ErrorAction SilentlyContinue }
    }
    if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($text)) {
        $message = Get-SalesforceCodeAnalyzerFailureMessage -Output $output
        $errorRecord = New-Object System.Management.Automation.ErrorRecord ([System.Exception]::new($message)), 'PsfdxCodeAnalyzerFailed', ([System.Management.Automation.ErrorCategory]::InvalidResult), $output
        throw $errorRecord
    }
    # The tree comes back as objects (json) or an XML document (xml). If the file is not what the format says, the text is returned as it is.
    if ($Format -eq 'json') {
        # Windows PowerShell 5.1 returns a JSON array as one object, so enumerate it to get one object per node on every version.
        try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop } catch { return $text }
        return @($parsed | ForEach-Object { $_ })
    }
    try { return [xml] $text } catch { return $text }
}

#endregion

#region Apex Testing

function Test-SalesforceApex {
    <#
    .SYNOPSIS
    Runs Apex tests in an org and returns the result.

    .DESCRIPTION
    Runs sf apex run test (waiting up to -WaitMinutes) and returns the result in the format you choose. -TestsInProject runs the test classes found in the local project. With the default json format the result is returned as an object. For a run that returns a run ID to poll, use Start-SalesforceApexTest.

    .PARAMETER ClassName
    Test class to run. psfdx passes it as --tests <ClassName>, or as --tests <ClassName>.<TestName> when -TestName is also given. Ignored with -TestsInProject.

    .PARAMETER TestName
    A single test method to run, used together with -ClassName; psfdx passes --tests <ClassName>.<TestName>. Without -ClassName it has no effect. Ignored with -TestsInProject.

    .PARAMETER ResultFormat
    Format of the test results. Passed to sf as --result-format. Default: json. Valid values: human, tap, junit, json.

    .PARAMETER Concise
    Display only failed test results; works with human-readable output only. Adds --concise.

    .PARAMETER CodeCoverage
    Retrieve code coverage results. Adds --code-coverage.

    .PARAMETER CodeCoverageDetailed
    Display detailed code coverage per test. Adds --detailed-coverage.

    .PARAMETER WaitMinutes
    Sets the streaming client socket timeout in minutes; specify a longer wait time if timeouts occur frequently. Passed to sf as --wait. Default: 10.

    .PARAMETER OutputDirectory
    Directory in which to store test run files. Passed to sf as --output-dir.

    .PARAMETER TestsInProject
    Run every Apex test class found in the local project. psfdx reads the project folder and passes one --tests <class> per class it finds, so there is no matching CLI flag. The cmdlet stops if it finds none. It takes the place of -ClassName and -TestName.

    .PARAMETER PollIntervalSeconds
    Number of seconds to wait between checks while the tests run. Passed to sf as --poll-interval.

    .PARAMETER Synchronous
    Run the test methods of a single Apex class synchronously, so the command waits for the results; without it the tests run asynchronously. It needs -ClassName and cannot be used with -TestsInProject or -TestName. Adds --synchronous.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Test-SalesforceApex -ClassName AccountServiceTest -CodeCoverage -TargetOrg dev1
    Run one test class with coverage.

    .EXAMPLE
    Test-SalesforceApex -ClassName AccountServiceTest -Synchronous -TargetOrg dev1
    Run one test class synchronously.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf apex run test (plugin @salesforce/plugin-apex)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ClassName = --tests; -TestName = --tests; -ResultFormat = --result-format; -Concise = --concise; -CodeCoverage = --code-coverage; -CodeCoverageDetailed = --detailed-coverage; -WaitMinutes = --wait; -OutputDirectory = --output-dir; -TestsInProject = --tests; -PollIntervalSeconds = --poll-interval; -Synchronous = --synchronous; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-apex

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $ClassName,
        [Parameter(Mandatory = $false)][string] $TestName,

        [Parameter(Mandatory = $false)][string][ValidateSet('human', 'tap', 'junit', 'json')] $ResultFormat = 'json',

        [Parameter(Mandatory = $false)][switch] $Concise,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][switch] $CodeCoverageDetailed,
        [Parameter(Mandatory = $false)][int] $WaitMinutes = 10,

        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $TestsInProject,
        [Parameter(Mandatory = $false)][ValidateRange(1, 3600)][int] $PollIntervalSeconds,
        [Parameter(Mandatory = $false)][switch] $Synchronous,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if ($Synchronous) {
        if ($TestsInProject) { throw '-Synchronous runs one Apex class, so it cannot be used with -TestsInProject.' }
        if ($TestName) { throw '-Synchronous runs the methods of one Apex class, so it cannot be used with -TestName.' }
        if (-not $ClassName) { throw '-Synchronous needs -ClassName, the one Apex class to run.' }
    }

    $arguments = @('apex', 'run', 'test')

    $arguments += Get-SalesforceCliApexTestArguments -TestsInProject:$TestsInProject -ClassName $ClassName -TestName $TestName
    if ($Synchronous) { $arguments += '--synchronous' }
    if ($PSBoundParameters.ContainsKey('PollIntervalSeconds')) { $arguments += @('--poll-interval', $PollIntervalSeconds) }

    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) {
            throw "Output directory '$OutputDirectory' does not exist."
        }
        $arguments += @('--output-dir', $OutputDirectory)
    }
    if ($WaitMinutes) { $arguments += @('--wait', $WaitMinutes) }

    if ($Concise) { $arguments += '--concise' }
    if ($CodeCoverage) { $arguments += '--code-coverage' }
    if ($CodeCoverageDetailed) { $arguments += '--detailed-coverage' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += @('--result-format', $ResultFormat)

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters

    if ($ResultFormat -ne 'json') {
        Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return
    }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = $result | ConvertFrom-Json

    $summary = $result.result.summary
    if ($null -eq $summary) {
        Write-Debug ($result | ConvertTo-Json -Depth 10)
        throw "Salesforce CLI returned no test summary. $($result.message)".Trim()
    }

    $result.result.tests
    if ($summary.outcome -ne 'Passed') {
        throw ("$($summary.failing) Tests Failed")
    }

    if ((-not $CodeCoverage) -and (-not $CodeCoverageDetailed)) {
        return
    }

    [int]$codeCoverage = ($summary.testRunCoverage -replace '%')
    if ($codeCoverage -lt 75) {
        $result.result.coverage.coverage
        throw "Insufficient code coverage ${codeCoverage}%"
    }
}

function Get-SalesforceCliApexTestArguments {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $ClassName,
        [Parameter(Mandatory = $false)][string] $TestName,
        [Parameter(Mandatory = $false)][switch] $TestsInProject
    )

    $value = @()
    if ($TestsInProject.IsPresent) {
        $testClassNames = Get-SalesforceApexTestClassNames
        $testClassNames = @($testClassNames | Where-Object { $_ -and $_.Trim() })
        if ($testClassNames.Count -eq 0) {
            throw "No Apex test classes found in the project."
        }
        foreach ($testClassName in $testClassNames) { $value += @('--tests', $testClassName.Trim()) }
    } elseif ($ClassName -and $TestName) {
        $value += @('--tests', "$ClassName.$TestName") # Run specific Test in a Class
    } elseif ((-not $TestName) -and ($ClassName)) {
        $value += @('--tests', $ClassName)     # Run Test Class
    }
    return $value
}

function Get-SalesforceCodeCoverage {
    <#
    .SYNOPSIS
    Shows per-test Apex code coverage as recorded in an org.

    .DESCRIPTION
    Queries the Tooling API object ApexCodeCoverage with Select-SalesforceRecords and returns one object per class, trigger and test method with the percentage covered, the covered and uncovered line counts, and CodeCoverageOK (true at 75 percent or more). -ApexClassOrTrigger filters the result in PowerShell after the query.

    .PARAMETER ApexClassOrTrigger
    Keep only rows where this name is the class or trigger, or the test class. The filter runs in PowerShell, after the query.

    .PARAMETER TargetOrg
    Username or alias of the org to query. If omitted, the Salesforce CLI uses the default target org.

    .EXAMPLE
    Get-SalesforceCodeCoverage -ApexClassOrTrigger MyService -TargetOrg dev1
    Coverage rows for MyService.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Select-SalesforceRecords. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $ApexClassOrTrigger = $null,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $query = "SELECT ApexTestClass.Name, TestMethodName, ApexClassOrTrigger.Name, NumLinesUncovered, NumLinesCovered, Coverage "
    $query += "FROM ApexCodeCoverage "
    $results = Select-SalesforceRecords -Query $query -TargetOrg $TargetOrg -UseToolingApi
    if (($null -ne $ApexClassOrTrigger) -and ($ApexClassOrTrigger -ne '')) {
        $results = $results | Where-Object { $_.ApexClassOrTrigger.Name -eq $ApexClassOrTrigger -or $_.ApexTestClass.Name -eq $ApexClassOrTrigger }
    }

    $values = @()
    foreach ($item in $results) {
        $value = New-Object -TypeName PSObject
        $value | Add-Member -MemberType NoteProperty -Name 'ApexClassOrTrigger' -Value $item.ApexClassOrTrigger.Name
        $value | Add-Member -MemberType NoteProperty -Name 'ApexTestClass' -Value $item.ApexTestClass.Name
        $value | Add-Member -MemberType NoteProperty -Name 'TestMethodName' -Value $item.TestMethodName

        $codeCoverage = 0
        $codeLength = $item.NumLinesCovered + $item.NumLinesUncovered
        if ($codeLength -gt 0) {
            $codeCoverage = $item.NumLinesCovered / $codeLength
        }
        $value | Add-Member -MemberType NoteProperty -Name 'CodeCoverage' -Value $codeCoverage.toString("P")
        $codeCoverageOK = $false
        if ($codeCoverage -ge 0.75) { $codeCoverageOK = $true }

        $value | Add-Member -MemberType NoteProperty -Name 'CodeCoverageOK' -Value $codeCoverageOK
        $value | Add-Member -MemberType NoteProperty -Name 'NumLinesCovered' -Value $item.NumLinesCovered
        $value | Add-Member -MemberType NoteProperty -Name 'NumLinesUncovered' -Value $item.NumLinesUncovered
        $values += $value
    }

    return $values
}

function Watch-SalesforceApex {
    <#
    .SYNOPSIS
    Runs Apex tests and deploys automatically when you save an Apex file.

    .DESCRIPTION
    Watches the project folder with a file system watcher. On each change to an Apex class or trigger file it deploys that one component and, when it finds test classes that reference it in the project, runs them as part of the deployment. It keeps running until you press Ctrl+C. The deployment goes to the default target org; there is no -TargetOrg.

    .PARAMETER ProjectFolder
    Folder of the Salesforce DX project to watch. Defaults to the current folder. It must exist.

    .PARAMETER CooldownMilliseconds
    Ignore repeat events for the same file within this many milliseconds. Default 300. Default: 300.

    .PARAMETER IgnoreErrors
    Keep watching after a deploy or test fails instead of stopping.

    .EXAMPLE
    Watch-SalesforceApex -ProjectFolder .
    Deploy and test on every save.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It does not run sf directly. For each changed Apex file an internal helper (Watch-SalesforceApexAction) runs sf project deploy start --metadata ApexClass:<name> (or ApexTrigger:<name>) --ignore-warnings. When it finds related test classes it adds --test-level RunSpecifiedTests and one --tests per class; otherwise --test-level NoTestRun. -IgnoreErrors adds --ignore-errors. The command is run in the default target org.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $ProjectFolder,
        [Parameter(Mandatory = $false)][int] $CooldownMilliseconds = 300,
        [Parameter(Mandatory = $false)][switch] $IgnoreErrors
    )

    # Default to Current Folder
    if (-not $ProjectFolder) {
        $ProjectFolder = (Get-Location).Path
    }

    # Folder does not Exist
    if (-not (Test-Path -LiteralPath $ProjectFolder -PathType Container)) {
        throw "Project folder '$ProjectFolder' does not exist."
    }

    # Watch File System Changes
    $watcherInfo = Start-SalesforceApexWatcher -ProjectFolder $ProjectFolder
    $sourceIdentifiers = $watcherInfo.SourceIdentifiers
    $recentEvents = [System.Collections.Hashtable]::Synchronized(@{})

    try {
        Write-Host "Watching $($watcherInfo.Project) for Apex changes. Press Ctrl+C to stop." -ForegroundColor Cyan
        while ($true) {
            $apexChangeEvent = Receive-SalesforceApexWatcherEvent -SourceIdentifiers $sourceIdentifiers -TimeoutSeconds 1
            if (-not $apexChangeEvent) {
                continue
            }

            # On File Changed
            try {
                Invoke-SalesforceApexChangeEvent -ApexChangeEvent $apexChangeEvent -ProjectFolder $watcherInfo.Project -RecentEvents $recentEvents -CooldownMilliseconds $CooldownMilliseconds -IgnoreErrors:$IgnoreErrors.IsPresent
            } finally {
                Remove-Event -EventIdentifier $apexChangeEvent.EventIdentifier -ErrorAction SilentlyContinue
            }
        }
    } finally {
        Stop-SalesforceApexWatcher -SourceIdentifiers $sourceIdentifiers -Watcher $watcherInfo.Watcher
    }
}

#region "Salesforce Apex Watcher Helpers"

function Invoke-SalesforceApex {
    <#
    .SYNOPSIS
    Runs the anonymous Apex in a file against an org.

    .DESCRIPTION
    Runs sf apex run --file. The code executes in the org with your user's permissions and can change data, so review it first. Returns the execution result (success, compile and run problems, and the debug log).

    .PARAMETER ApexFile
    Path of the local file that holds the Apex statements to run. Passed to sf as --file. Required.

    .PARAMETER DebugLevel
    Debug level for the debug log that the run creates in the org. Passed to sf as --debug-level. Valid values: NONE, DEBUGONLY, DB, PROFILING, CALLOUT, DETAIL. Use it instead of -CategoryLevel, not with it.

    .PARAMETER CategoryLevel
    Log level for one log category of that debug log, written as Category=Level, for example ApexCode=FINEST. Give the parameter several times, or a list, for several categories. Each one is passed to sf as its own --category-level. Use it instead of -DebugLevel, not with it.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Invoke-SalesforceApex -ApexFile .\scripts\apex\hello.apex -TargetOrg dev1
    Run the script.

    .EXAMPLE
    Invoke-SalesforceApex -ApexFile .\scripts\apex\hello.apex -CategoryLevel ApexCode=FINEST, Database=INFO -TargetOrg dev1
    Run the script with a detailed Apex log and a short database log.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf apex run (plugin @salesforce/plugin-apex)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ApexFile = --file; -DebugLevel = --debug-level; -CategoryLevel = --category-level; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-apex

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ApexFile,
        [Parameter(Mandatory = $false)][ValidateSet('NONE', 'DEBUGONLY', 'DB', 'PROFILING', 'CALLOUT', 'DETAIL')][string] $DebugLevel,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z_]+=[A-Za-z]+\z')][string[]] $CategoryLevel,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $categories = @($CategoryLevel | Where-Object { $_ })
    if ($DebugLevel -and $categories.Count -gt 0) { throw 'Use -DebugLevel or -CategoryLevel, not both.' }
    $arguments = @('apex', 'run', '--file', $ApexFile)
    if ($DebugLevel) { $arguments += @('--debug-level', $DebugLevel) }
    foreach ($category in $categories) { $arguments += @('--category-level', $category) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceApexWatcher {
    Param(
        [Parameter(Mandatory = $true)][string] $ProjectFolder
    )

    $project = (Get-Item -LiteralPath $ProjectFolder).FullName
    Write-Verbose ("Watching Project Folder: " + $project)
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $project
    $watcher.Filter = '*.*'
    $watcher.IncludeSubdirectories = $true
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite
    $watcher.EnableRaisingEvents = $true

    return [pscustomobject]@{
        Project = $project
        Watcher = $watcher
    }
}

function Get-SalesforceApexEventPaths {
    Param(
        [Parameter(Mandatory = $true)][System.IO.FileSystemEventArgs] $EventArgs
    )

    return @($EventArgs.FullPath)
}

function Register-SalesforceApexWatcherEvents {
    Param(
        [Parameter(Mandatory = $true)][System.IO.FileSystemWatcher] $Watcher
    )

    $sourcePrefix = "Watch-SalesforceApex_$([guid]::NewGuid())"
    $sourceIdentifiers = @()
    foreach ($eventName in 'Changed', 'Created', 'Renamed') {
        $sourceId = "${sourcePrefix}:$eventName"
        Register-ObjectEvent -InputObject $Watcher -EventName $eventName -SourceIdentifier $sourceId | Out-Null
        $sourceIdentifiers += $sourceId
    }

    return $sourceIdentifiers
}

function Start-SalesforceApexWatcher {
    Param(
        [Parameter(Mandatory = $true)][string] $ProjectFolder
    )

    $watcherInfo = New-SalesforceApexWatcher -ProjectFolder $ProjectFolder
    $sourceIdentifiers = Register-SalesforceApexWatcherEvents -Watcher $watcherInfo.Watcher

    return [pscustomobject]@{
        Project = $watcherInfo.Project
        Watcher = $watcherInfo.Watcher
        SourceIdentifiers = $sourceIdentifiers
    }
}

function Stop-SalesforceApexWatcher {
    Param(
        [Parameter(Mandatory = $true)][string[]] $SourceIdentifiers,
        [Parameter(Mandatory = $true)][System.IO.FileSystemWatcher] $Watcher
    )

    foreach ($identifier in $SourceIdentifiers) {
        Unregister-Event -SourceIdentifier $identifier -ErrorAction SilentlyContinue
    }
    $Watcher.EnableRaisingEvents = $false
    $Watcher.Dispose()
}

function Receive-SalesforceApexWatcherEvent {
    Param(
        [Parameter(Mandatory = $true)][string[]] $SourceIdentifiers,
        [Parameter(Mandatory = $false)][int] $TimeoutSeconds = 1
    )

    $apexChangeEvent = Wait-Event -Timeout $TimeoutSeconds
    if (-not $apexChangeEvent) {
        return $null
    }

    if ($apexChangeEvent.SourceIdentifier -notin $SourceIdentifiers) {
        Remove-Event -EventIdentifier $apexChangeEvent.EventIdentifier -ErrorAction SilentlyContinue
        return $null
    }

    return $apexChangeEvent
}

function Invoke-SalesforceApexChangeEvent {
    Param(
        [Parameter(Mandatory = $true)][System.Management.Automation.PSEventArgs] $ApexChangeEvent,
        [Parameter(Mandatory = $true)][string] $ProjectFolder,
        [Parameter(Mandatory = $true)][System.Collections.Hashtable] $RecentEvents,
        [Parameter(Mandatory = $true)][int] $CooldownMilliseconds,
        [Parameter(Mandatory = $false)][switch] $IgnoreErrors
    )

    $paths = Get-SalesforceApexEventPaths -EventArgs $ApexChangeEvent.SourceEventArgs

    foreach ($path in $paths) {
        if (-not (Wait-SalesforceApexCooldown -Path $path -RecentEvents $RecentEvents -CooldownMilliseconds $CooldownMilliseconds)) {
            continue
        }

        Watch-SalesforceApexAction -FilePath $path -ProjectFolder $ProjectFolder -IgnoreErrors:$IgnoreErrors.IsPresent | Out-Null
        $RecentEvents[$path] = (Get-Date).AddMilliseconds($CooldownMilliseconds)
    }
}

function Wait-SalesforceApexCooldown {
    Param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][System.Collections.Hashtable] $RecentEvents,
        [Parameter(Mandatory = $true)][int] $CooldownMilliseconds
    )

    $now = Get-Date
    $nextAllowed = $RecentEvents[$Path]
    if ($nextAllowed -and ($now -lt $nextAllowed)) {
        return $false
    }

    Start-Sleep -Milliseconds $CooldownMilliseconds
    return $true
}

function Test-SalesforceApexPath {
    Param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string[]] $Extensions
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    $extension = [System.IO.Path]::GetExtension($Path)
    if (-not $extension) { return $false }

    $extension = $extension.ToLowerInvariant()
    if ($extension -notin $Extensions) { return $false }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }

    return $true
}

function Watch-SalesforceApexAction {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $false)][string] $ProjectFolder,
        [Parameter(Mandatory = $false)][switch] $IgnoreErrors
    )

    try {
        Write-Verbose ("Processing file: " + $FilePath)

        if (-not $ProjectFolder) {
            $ProjectFolder = (Get-Location).Path
        }

        $type = Get-SalesforceType -FileName $FilePath
        if (($type -ne 'ApexClass') -and ($type -ne 'ApexTrigger')) {
            return
        }

        $name = Get-SalesforceName -FileName $FilePath
        Write-Host "Deploying $type ${name}..." -ForegroundColor Cyan

        $arguments = @('project', 'deploy', 'start')
        $arguments += @('--metadata', "${type}:${name}")
        $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
        $testClassNames = Get-SalesforceApexTestClassNames -FilePath $FilePath -ProjectFolder $ProjectFolder
        $testLevel = if ($testClassNames -and $testClassNames.Count -gt 0) { 'SpecificTests' } else { 'NoTests' }
        $arguments += Get-SalesforceApexCliTestArguments @commonParams -TestLevel $testLevel -Tests $testClassNames
        $arguments += '--ignore-warnings'
        if ($IgnoreErrors) { $arguments += '--ignore-errors' }
        $arguments += '--json'
        $deployJson = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        Show-SalesforceResult -Result $deployJson

        $successMessage = "Deployed $type ${name}"
        if ($testClassNames -and $testClassNames.Count -gt 0) {
            $successMessage += " and successfully ran tests (" + ($testClassNames -join ', ') + ")"
        }
        $successMessage += "."
        Write-Host $successMessage -ForegroundColor Green
    }
    catch {
        Write-Error $_
    }
}

function Get-SalesforceType {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $FileName)

    if ([string]::IsNullOrWhiteSpace($FileName)) {
        return ""
    }
    if ($FileName.EndsWith(".cls", [System.StringComparison]::OrdinalIgnoreCase)) {
        return "ApexClass"
    }
    if ($FileName.EndsWith(".trigger", [System.StringComparison]::OrdinalIgnoreCase)) {
        return "ApexTrigger"
    }
    return ""
}

function Get-SalesforceName {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $FileName)

    if ([string]::IsNullOrWhiteSpace($FileName)) {
        return ""
    }
    # Parse the path rather than calling Get-Item: the watcher also fires for files that
    # have already been renamed or deleted by the time this runs.
    $name = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    Write-Verbose ("Apex Name: " + $name)
    return $name
}

#endregion

function Get-SalesforceApexTestClassNames {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $FilePath,
        [Parameter(Mandatory = $false)][string] $ProjectFolder
    )

    if ($FilePath) {
        return Get-SalesforceApexTestClassNamesFromFile -FilePath $FilePath
    }

    if (!$ProjectFolder) {
        $ProjectFolder = (Get-Location).Path
    }
    if (-not (Test-Path -LiteralPath $ProjectFolder -PathType Container)) {
        throw "Project folder '$ProjectFolder' does not exist."
    }

    $testFiles = Get-ChildItem -Path $ProjectFolder -Recurse -Filter '*.cls' -File -ErrorAction SilentlyContinue
    $testFiles = $testFiles | Where-Object {
        Select-String -Path $_.FullName -Pattern '@isTest' -SimpleMatch -Quiet
    }

    $testClassNames = $testFiles | ForEach-Object {
        [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    } | Sort-Object -Unique

    return @($testClassNames)
}

function Get-SalesforceApexTestClassNamesFromFile {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $FilePath
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "File '$FilePath' does not exist."
    }

    $parentFolder = Split-Path -Path $FilePath -Parent
    $rootFolder = Split-Path -Path $parentFolder -Parent
    if ([string]::IsNullOrWhiteSpace($rootFolder)) {
        $rootFolder = $parentFolder
    }
    $rootFolder = (Get-Item -LiteralPath $rootFolder).FullName

    $className = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)

    $testFiles = Get-ChildItem -Path $rootFolder -Recurse -Filter '*.cls' -File -ErrorAction SilentlyContinue
    $matchingTests = $testFiles | Where-Object {
        (Select-String -Path $_.FullName -Pattern '@isTest' -SimpleMatch -Quiet) -and
        (Test-SalesforceApexTestReference -Path $_.FullName -ClassName $className)
    }

    $matchingTests | ForEach-Object {
        [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    } | Sort-Object -Unique
}

function Get-SalesforceApexClass {
    <#
    .SYNOPSIS
    Gets an Apex class, including its source, from an org.

    .DESCRIPTION
    Queries ApexClass (Id, Name, Body) through the Tooling API with Select-SalesforceRecords. The name is matched exactly and escaped as a SOQL literal; at most one class is returned.

    .PARAMETER Name
    Exact name of the Apex class. Required.

    .PARAMETER TargetOrg
    Username or alias of the org to query. If omitted, the Salesforce CLI uses the default target org.

    .EXAMPLE
    (Get-SalesforceApexClass -Name MyService -TargetOrg dev1).Body
    The source code of MyService.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Select-SalesforceRecords. They run the sf commands; this cmdlet adds PowerShell logic on top.

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
    $query = "SELECT Id, Name, Body FROM ApexClass WHERE Name = " + (ConvertTo-SalesforceSoqlLiteral -Value $Name) + " LIMIT 1"
    return Select-SalesforceRecords -Query $query -UseToolingApi -TargetOrg $TargetOrg
}

#endregion

#region Apex Test Runs

# The Apex test lifecycle as separate steps, for CI and for scripts that start a run in one session and read it in another:
#   Start-SalesforceApexTest  -> sf apex run test (asynchronous), returns the TestRunId
#   Get-SalesforceApexTestResult -> sf apex get test, returns the structured results for a run
#   Wait-SalesforceApexTest   -> polls Get-SalesforceApexTestResult until the run finishes or a timeout passes
# Test-SalesforceApex is unchanged and still runs and waits in one call. For Flow tests and mixed Flow and Apex runs see
# Test-SalesforceFlow and Test-SalesforceLogic (#191). Results and errors work as for those: a finished run is one object (TestRunId, Summary,
# Tests, Coverage, Completed); failing tests throw PsfdxTestsFailed; a command that could not run throws PsfdxTestRunInvocationFailed.

function Start-SalesforceApexTest {
    <#
    .SYNOPSIS
    Starts an Apex test run in an org and returns its TestRunId without waiting (sf apex run test).

    .DESCRIPTION
    Name tests with -ClassName (all tests in the classes), -TestName (Class.method) or -SuiteName, one kind at a time, or give none to run
    the local tests. Salesforce only records code coverage for a run that asked for it, so give -CodeCoverage here if you will want coverage later;
    asking only when you fetch the results retrieves nothing new. The returned TestRunId works from any later session on any computer: pass it to
    Get-SalesforceApexTestResult or Wait-SalesforceApexTest. To run and wait in one call use Test-SalesforceApex.

    .PARAMETER ClassName
    Apex test classes to run. Passed as --class-names, one flag per class. Cannot be combined with -TestName or -SuiteName.

    .PARAMETER TestName
    Individual test methods to run, written Class.method. Passed as --tests, one flag per test. Cannot be combined with -ClassName or -SuiteName.

    .PARAMETER SuiteName
    Apex test suites to run. Passed as --suite-names, one flag per suite. Cannot be combined with -ClassName or -TestName.

    .PARAMETER TestLevel
    Level of tests to run; default is RunLocalTests. Passed to sf as --test-level. Valid values: RunLocalTests, RunAllTestsInOrg, RunSpecifiedTests.

    .PARAMETER CodeCoverage
    Retrieve code coverage results. Adds --code-coverage.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    $run = Start-SalesforceApexTest -TestLevel RunLocalTests -CodeCoverage -TargetOrg myorg; $run.TestRunId

    .EXAMPLE
    # Later, in another shell:
    Wait-SalesforceApexTest -TestRunId 707xx0000000001 -TimeoutMinutes 30 -CodeCoverage -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf apex run test (plugin @salesforce/plugin-apex)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --poll-interval, --synchronous
    Parameter to flag: -TestLevel = --test-level; -CodeCoverage = --code-coverage; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-apex

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string[]] $ClassName,
        [Parameter(Mandatory = $false)][string[]] $TestName,
        [Parameter(Mandatory = $false)][string[]] $SuiteName,
        [Parameter(Mandatory = $false)][ValidateSet('RunLocalTests', 'RunAllTestsInOrg', 'RunSpecifiedTests')][string] $TestLevel,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $classes = @($ClassName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $tests = @($TestName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $suites = @($SuiteName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ((@($classes.Count, $tests.Count, $suites.Count) | Where-Object { $_ -gt 0 }).Count -gt 1) { throw 'Use only one of -ClassName, -TestName and -SuiteName.' }
    if (($classes.Count + $tests.Count + $suites.Count) -gt 0 -and $TestLevel -and $TestLevel -ne 'RunSpecifiedTests') {
        throw "Naming classes, tests or suites needs -TestLevel RunSpecifiedTests, not $TestLevel."
    }

    $arguments = @('apex', 'run', 'test')
    foreach ($item in $classes) { $arguments += @('--class-names', $item) }
    foreach ($item in $tests) { $arguments += @('--tests', $item) }
    foreach ($item in $suites) { $arguments += @('--suite-names', $item) }
    if ($TestLevel) { $arguments += @('--test-level', $TestLevel) }
    if ($CodeCoverage) { $arguments += '--code-coverage' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += @('--result-format', 'json', '--json')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceTestRunOutput -Output $output -ResultFormat 'json' -Plugin '@salesforce/plugin-apex' -Command 'apex run test'
    if ($null -eq $result -or $null -eq $result.PSObject.Properties['TestRunId'] -or [string]::IsNullOrWhiteSpace([string] $result.TestRunId)) {
        throw 'The Salesforce CLI did not return a test run ID.'
    }
    return [pscustomobject]@{ TestRunId = [string] $result.TestRunId; Completed = $false }
}

function Get-SalesforceApexTestResult {
    <#
    .SYNOPSIS
    Gets the results of an Apex test run by its TestRunId (sf apex get test).

    .DESCRIPTION
    Returns one object: TestRunId, Summary (outcome, counts, times), Tests (one per test method with Outcome, RunTime, Message and StackTrace),
    Coverage (only with -CodeCoverage, and only if the run was started with coverage) and Completed. A run that is still queued or processing returns
    Completed = $false at once (the status is checked with a query first, because the CLI itself would wait) and does not throw;
    use Wait-SalesforceApexTest to wait. A finished run with failing tests writes the object and then throws PsfdxTestsFailed (TargetObject is the
    summary). Coverage is returned, never judged: there is no threshold here.

    .PARAMETER TestRunId
    ID of the test run. Passed to sf as --test-run-id. Required.

    .PARAMETER CodeCoverage
    Retrieve code coverage results. Adds --code-coverage.

    .PARAMETER CodeCoverageDetailed
    Display detailed code coverage per test. Adds --detailed-coverage.

    .PARAMETER Concise
    Display only failed test results; works with human-readable output only. Adds --concise.

    .PARAMETER OutputDirectory
    Directory in which to store test result files. Passed to sf as --output-dir.

    .PARAMETER ResultFormat
    Format of the results. Passed to sf as --result-format. Default: json, which returns the object described above. With human, tap or junit the CLI's text is returned as it is, and a run that is still queued or processing returns nothing but a warning. Valid values: human, tap, junit, json.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    $r = Get-SalesforceApexTestResult -TestRunId 707xx0000000001 -CodeCoverage -TargetOrg myorg; $r.Tests | Where-Object Outcome -ne 'Pass'

    .EXAMPLE
    Get-SalesforceApexTestResult -TestRunId 707xx0000000001 -ResultFormat junit -OutputDirectory .\results -TargetOrg myorg
    Write the results as JUnit XML for a CI system.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf apex get test (plugin @salesforce/plugin-apex)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TestRunId = --test-run-id; -CodeCoverage = --code-coverage; -CodeCoverageDetailed = --detailed-coverage; -Concise = --concise; -OutputDirectory = --output-dir; -ResultFormat = --result-format; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.
    Also calls these psfdx cmdlets: Select-SalesforceRecords.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-apex

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^707[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $TestRunId,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][switch] $CodeCoverageDetailed,
        [Parameter(Mandatory = $false)][switch] $Concise,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][ValidateSet('human', 'tap', 'junit', 'json')][string] $ResultFormat = 'json',
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($CodeCoverageDetailed -and -not $CodeCoverage) { throw '-CodeCoverageDetailed needs -CodeCoverage.' }
    if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory)) { throw "Output directory '$OutputDirectory' does not exist." }

    # sf apex get test WAITS for a run that has not finished. Ask for the run's status first, with a query that returns at once, so a run
    # still queued or processing comes back as Completed = $false instead of blocking the call (and any timeout built on it).
    $statusParams = @{ Query = "SELECT Status FROM ApexTestQueueItem WHERE ParentJobId = $(ConvertTo-SalesforceSoqlLiteral -Value $TestRunId)" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $statusParams['TargetOrg'] = $TargetOrg }
    $queueItems = @(Select-SalesforceRecords @statusParams)
    $pending = @($queueItems | Where-Object { $_.Status -in @('Queued', 'Preparing', 'Processing', 'Holding') })
    if ($pending.Count -gt 0) {
        # A text format (junit, tap, human) is often redirected to a report file, so give it a warning and no object.
        if ($ResultFormat -ne 'json') {
            Write-Warning "Test run $TestRunId has not finished ($($pending.Count) of $($queueItems.Count) tests are still queued or running), so there are no $ResultFormat results yet. Use Wait-SalesforceApexTest to wait for it."
            return
        }
        return [pscustomobject]@{ TestRunId = $TestRunId; Summary = $null; Tests = @(); Coverage = $null; Completed = $false; PendingTests = $pending.Count; TotalTests = $queueItems.Count }
    }

    $arguments = @('apex', 'get', 'test', '--test-run-id', $TestRunId)
    if ($Concise) { $arguments += '--concise' }
    if ($CodeCoverage) { $arguments += '--code-coverage' }
    if ($CodeCoverageDetailed) { $arguments += '--detailed-coverage' }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += @('--result-format', $ResultFormat)
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    if ($ResultFormat -ne 'json') {
        # human, tap and junit are text, so the CLI's output is handed back as it is.
        return Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    }
    $arguments += '--json'
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    ConvertFrom-SalesforceTestRunOutput -Output $output -ResultFormat 'json' -Plugin '@salesforce/plugin-apex' -Command 'apex get test'
}

function Wait-SalesforceApexTest {
    <#
    .SYNOPSIS
    Waits for an Apex test run to finish and returns its results.

    .DESCRIPTION
    Polls Get-SalesforceApexTestResult every -PollSeconds until the run is no longer queued or processing, then returns the same object. If
    -TimeoutMinutes pass first it throws PsfdxTestRunTimeout, whose TargetObject is the TestRunId, and the run carries on in the org. Failing
    tests and CLI errors surface exactly as for Get-SalesforceApexTestResult.

    .PARAMETER TestRunId
    ID of the test run to wait for, as returned by Start-SalesforceApexTest or Test-SalesforceApex. It must start with 707. Required.

    .PARAMETER TimeoutMinutes
    How long to wait, in minutes, before giving up with PsfdxTestRunTimeout. The run carries on in the org. Default 10. Default: 10. Range: 1 to 1440.

    .PARAMETER PollSeconds
    Seconds to wait between checks of the run's status. Default 10. Default: 10. Range: 1 to 600.

    .PARAMETER CodeCoverage
    Include code coverage in the result. Passed on to Get-SalesforceApexTestResult as --code-coverage; the run must have been started with coverage.

    .PARAMETER CodeCoverageDetailed
    Include line-by-line code coverage. Passed on to Get-SalesforceApexTestResult as --detailed-coverage.

    .PARAMETER Concise
    Show only failing tests in human-readable output. Passed on to Get-SalesforceApexTestResult as --concise.

    .PARAMETER OutputDirectory
    Folder to write the result files to. Passed on to Get-SalesforceApexTestResult as --output-dir.

    .PARAMETER TargetOrg
    Username or alias of the org the run is in. If omitted, the Salesforce CLI uses the default target org.

    .EXAMPLE
    $run = Start-SalesforceApexTest -TargetOrg myorg; Wait-SalesforceApexTest -TestRunId $run.TestRunId -TimeoutMinutes 30 -CodeCoverage -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Get-SalesforceApexTestResult. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^707[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $TestRunId,
        [Parameter(Mandatory = $false)][ValidateRange(1, 1440)][int] $TimeoutMinutes = 10,
        [Parameter(Mandatory = $false)][ValidateRange(1, 600)][int] $PollSeconds = 10,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][switch] $CodeCoverageDetailed,
        [Parameter(Mandatory = $false)][switch] $Concise,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $getParams = @{ TestRunId = $TestRunId }
    if ($CodeCoverage) { $getParams['CodeCoverage'] = $true }
    if ($CodeCoverageDetailed) { $getParams['CodeCoverageDetailed'] = $true }
    if ($Concise) { $getParams['Concise'] = $true }
    if ($OutputDirectory) { $getParams['OutputDirectory'] = $OutputDirectory }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $getParams['TargetOrg'] = $TargetOrg }
    foreach ($name in 'Verbose', 'Debug') { if ($PSBoundParameters.ContainsKey($name)) { $getParams[$name] = $PSBoundParameters[$name] } }

    # The wait is counted in polls rather than read from the clock, so it is the same however long each CLI call takes.
    $maxPolls = [int] [math]::Ceiling(($TimeoutMinutes * 60) / $PollSeconds)
    for ($poll = 1; $poll -le $maxPolls; $poll++) {
        $result = Get-SalesforceApexTestResult @getParams
        if ($null -ne $result -and $result.PSObject.Properties['Completed'] -and $result.Completed) { return $result }
        if ($poll -lt $maxPolls) { Start-Sleep -Seconds $PollSeconds }
    }
    $message = "Apex test run $TestRunId did not finish within $TimeoutMinutes minute(s). It is still running in the org; call Wait-SalesforceApexTest or Get-SalesforceApexTestResult again later."
    $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.TimeoutException $message), 'PsfdxTestRunTimeout', [System.Management.Automation.ErrorCategory]::OperationTimeout, $TestRunId)
    throw $record
}

#endregion

#region Flow and Logic Testing

# `sf flow run test` runs Flow tests; `sf logic run test` runs Flow and Apex tests together. Both start the run asynchronously by
# default and answer with a test run ID; -Synchronous waits for the results. Both plugins ship with the CLI (the Flow plugin is
# installed on first use). Test-SalesforceApex is unchanged.

function Test-SalesforceFlow {
    <#
    .SYNOPSIS
    Runs Flow tests in an org (sf flow run test).

    .DESCRIPTION
    By default the run is asynchronous: the cmdlet returns an object with a TestRunId, and Get-SalesforceFlowTestResult fetches the
    results later. With -Synchronous (one flow only) it waits and returns the results. Needs the "View All Data" permission.

    A finished run returns one object with Summary, Tests and Coverage (Coverage is empty unless -CodeCoverage was given), and TestRunId.
    Without -Synchronous the CLI starts the run and returns at once.

    Failed tests and a command that could not run are different errors. A failed test run writes the result object to the pipeline, then
    throws an error whose FullyQualifiedErrorId is PsfdxTestsFailed (the CLI summary is the error's TargetObject).
    Everything else, such as no authorisation or a missing plugin, throws PsfdxTestRunInvocationFailed.

    Code coverage is returned but never judged; there is no coverage threshold.

    .PARAMETER FlowName
    Flows to test (--class-names). Cannot be combined with -TestName or -SuiteName.

    .PARAMETER TestName
    Specific tests in Flow.Test form (--tests).

    .PARAMETER SuiteName
    Test suites to run (--suite-names).

    .PARAMETER TestLevel
    RunLocalTests (the CLI default), RunAllTestsInOrg or RunSpecifiedTests. Naming flows or tests needs RunSpecifiedTests, which is the default then.

    .PARAMETER Synchronous
    Run flow tests for one flow synchronously; if not specified, tests are run asynchronously. Adds --synchronous.

    .PARAMETER ResultFormat
    Format of the test results. Passed to sf as --result-format. Default: json. Valid values: human, tap, junit, json.

    .PARAMETER Concise
    Display only failed test results; works with human-readable output only. Adds --concise.

    .PARAMETER CodeCoverage
    Retrieve code coverage results. Adds --code-coverage.

    .PARAMETER OutputDirectory
    Directory in which to store test result files. Passed to sf as --output-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Test-SalesforceFlow -TestLevel RunLocalTests -TargetOrg myorg

    .EXAMPLE
    Test-SalesforceFlow -FlowName Order_Flow -Synchronous -TargetOrg myorg

    .EXAMPLE
    $run = Test-SalesforceFlow -TestLevel RunLocalTests -TargetOrg myorg; Get-SalesforceFlowTestResult -TestRunId $run.TestRunId -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf flow run test (plugin @salesforce/plugin-flow)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -SuiteName = --suite-names; -TestLevel = --test-level; -Synchronous = --synchronous; -ResultFormat = --result-format; -Concise = --concise; -CodeCoverage = --code-coverage; -OutputDirectory = --output-dir; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-flow

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string[]] $FlowName,
        [Parameter(Mandatory = $false)][string[]] $TestName,
        [Parameter(Mandatory = $false)][string[]] $SuiteName,
        [Parameter(Mandatory = $false)][ValidateSet('RunLocalTests', 'RunAllTestsInOrg', 'RunSpecifiedTests')][string] $TestLevel,
        [Parameter(Mandatory = $false)][switch] $Synchronous,
        [Parameter(Mandatory = $false)][ValidateSet('human', 'tap', 'junit', 'json')][string] $ResultFormat = 'json',
        [Parameter(Mandatory = $false)][switch] $Concise,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $FlowName = @($FlowName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $TestName = @($TestName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $SuiteName = @($SuiteName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ((@($FlowName.Count, $TestName.Count, $SuiteName.Count) | Where-Object { $_ -gt 0 }).Count -gt 1) {
        throw 'Use only one of -FlowName, -TestName and -SuiteName.'
    }
    $selected = ($FlowName.Count + $TestName.Count + $SuiteName.Count) -gt 0
    if ($selected -and $TestLevel -and $TestLevel -ne 'RunSpecifiedTests') {
        throw "Naming flows, tests or suites needs -TestLevel RunSpecifiedTests, not $TestLevel."
    }
    if ($Synchronous -and ($SuiteName.Count -gt 0 -or $FlowName.Count -gt 1)) {
        throw 'A synchronous run can include tests from only one flow. Drop -Synchronous or name one flow.'
    }

    $arguments = @('flow', 'run', 'test')
    foreach ($item in $FlowName) { $arguments += @('--class-names', $item) }
    foreach ($item in $TestName) { $arguments += @('--tests', $item) }
    foreach ($item in $SuiteName) { $arguments += @('--suite-names', $item) }
    if ($TestLevel) { $arguments += @('--test-level', $TestLevel) }
    if ($Synchronous) { $arguments += '--synchronous' }
    if ($Concise) { $arguments += '--concise' }
    if ($CodeCoverage) { $arguments += '--code-coverage' }
    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) { throw "Output directory '$OutputDirectory' does not exist." }
        $arguments += @('--output-dir', $OutputDirectory)
    }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += @('--result-format', $ResultFormat)
    # --json makes the CLI return a run ID straight away for any run except RunSpecifiedTests, so a synchronous run asks for the JSON format only.
    if ($ResultFormat -eq 'json' -and -not $Synchronous) { $arguments += '--json' }

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    ConvertFrom-SalesforceTestRunOutput -Output $output -ResultFormat $ResultFormat -Plugin '@salesforce/plugin-flow' -Command 'flow run test'
}

function Get-SalesforceFlowTestResult {
    <#
    .SYNOPSIS
    Gets the results of an earlier Flow test run (sf flow get test).

    .DESCRIPTION
    Takes the TestRunId that Test-SalesforceFlow returned. Failed tests throw PsfdxTestsFailed and a command that could not run
    throws PsfdxTestRunInvocationFailed, as for Test-SalesforceFlow. A run that has not finished yet is reported by the CLI as
    an invocation failure or as its current counts, depending on the CLI version.

    .PARAMETER TestRunId
    ID of the test run. Passed to sf as --test-run-id. Required.

    .PARAMETER ResultFormat
    Format of the test results. Passed to sf as --result-format. Default: json. Valid values: human, tap, junit, json.

    .PARAMETER Concise
    Display only failed test results; works with human-readable output only. Adds --concise.

    .PARAMETER CodeCoverage
    Retrieve code coverage results. Adds --code-coverage.

    .PARAMETER CodeCoverageDetailed
    Not available for flow tests. Adds --detailed-coverage.

    .PARAMETER OutputDirectory
    Directory in which to store test result files. Passed to sf as --output-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceFlowTestResult -TestRunId 707xx0000000001 -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf flow get test (plugin @salesforce/plugin-flow)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TestRunId = --test-run-id; -ResultFormat = --result-format; -Concise = --concise; -CodeCoverage = --code-coverage; -CodeCoverageDetailed = --detailed-coverage; -OutputDirectory = --output-dir; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-flow

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^707[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $TestRunId,
        [Parameter(Mandatory = $false)][ValidateSet('human', 'tap', 'junit', 'json')][string] $ResultFormat = 'json',
        [Parameter(Mandatory = $false)][switch] $Concise,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][switch] $CodeCoverageDetailed,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($CodeCoverageDetailed -and -not $CodeCoverage) { throw '-CodeCoverageDetailed needs -CodeCoverage.' }

    $arguments = @('flow', 'get', 'test', '--test-run-id', $TestRunId)
    if ($Concise) { $arguments += '--concise' }
    if ($CodeCoverage) { $arguments += '--code-coverage' }
    if ($CodeCoverageDetailed) { $arguments += '--detailed-coverage' }
    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) { throw "Output directory '$OutputDirectory' does not exist." }
        $arguments += @('--output-dir', $OutputDirectory)
    }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += @('--result-format', $ResultFormat)
    if ($ResultFormat -eq 'json') { $arguments += '--json' }

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    ConvertFrom-SalesforceTestRunOutput -Output $output -ResultFormat $ResultFormat -Plugin '@salesforce/plugin-flow' -Command 'flow get test'
}

function Test-SalesforceLogic {
    <#
    .SYNOPSIS
    Runs Flow and Apex tests together in an org (sf logic run test).

    .DESCRIPTION
    Like Test-SalesforceFlow, but -TestName and -ClassName also accept Apex tests, and -TestCategory picks Apex, Flow or both.
    The run is asynchronous unless -Synchronous or -WaitMinutes is given; an asynchronous run, or a wait that times out, returns
    an object with a TestRunId for Get-SalesforceLogicTestResult. Failed tests throw PsfdxTestsFailed; a command that could not
    run throws PsfdxTestRunInvocationFailed. -TestCategory needs -TestLevel. The command is in beta in the CLI. Test-SalesforceApex still runs Apex alone.

    .PARAMETER ClassName
    Test classes to run. Passed as --class-names. Use only one of -ClassName, -TestName, -SuiteName and -TestCategory.

    .PARAMETER TestName
    Individual tests to run: Apex as Class.method, flows as FlowName.TestName. Passed as --tests. Use only one of -ClassName, -TestName, -SuiteName and -TestCategory.

    .PARAMETER SuiteName
    Test suites to run. Passed as --suite-names. Use only one of -ClassName, -TestName, -SuiteName and -TestCategory.

    .PARAMETER TestCategory
    Run Apex tests, Flow tests or both, with -TestLevel. Passed as --test-category, one flag per category. Use only one of -ClassName, -TestName, -SuiteName and -TestCategory. Valid values: Apex, Flow.

    .PARAMETER TestLevel
    Level of tests to run; default is RunLocalTests. Passed to sf as --test-level. Valid values: RunLocalTests, RunAllTestsInOrg, RunSpecifiedTests.

    .PARAMETER Synchronous
    Runs test methods from a single Apex class synchronously; if not specified, tests are run asynchronously. Adds --synchronous.

    .PARAMETER WaitMinutes
    Sets the streaming client socket timeout in minutes; specify a longer wait time if timeouts occur frequently. Passed to sf as --wait. Range: 0 to 1440.

    .PARAMETER ResultFormat
    Format of the test results. Passed to sf as --result-format. Default: json. Valid values: human, tap, junit, json.

    .PARAMETER Concise
    Display only failed test results; works with human-readable output only. Adds --concise.

    .PARAMETER CodeCoverage
    Retrieve code coverage results. Adds --code-coverage.

    .PARAMETER CodeCoverageDetailed
    Display detailed code coverage per test. Adds --detailed-coverage.

    .PARAMETER OutputDirectory
    Directory in which to store test run files. Passed to sf as --output-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Test-SalesforceLogic -TestCategory Apex, Flow -TestLevel RunLocalTests -Synchronous -TargetOrg myorg

    .EXAMPLE
    Test-SalesforceLogic -TestName 'OrderFlow.Test1', 'OrderTest.testSave' -WaitMinutes 10 -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf logic run test (beta) (plugin @salesforce/plugin-apex)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TestLevel = --test-level; -Synchronous = --synchronous; -WaitMinutes = --wait; -ResultFormat = --result-format; -Concise = --concise; -CodeCoverage = --code-coverage; -CodeCoverageDetailed = --detailed-coverage; -OutputDirectory = --output-dir; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-apex

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string[]] $ClassName,
        [Parameter(Mandatory = $false)][string[]] $TestName,
        [Parameter(Mandatory = $false)][string[]] $SuiteName,
        [Parameter(Mandatory = $false)][ValidateSet('Apex', 'Flow')][string[]] $TestCategory,
        [Parameter(Mandatory = $false)][ValidateSet('RunLocalTests', 'RunAllTestsInOrg', 'RunSpecifiedTests')][string] $TestLevel,
        [Parameter(Mandatory = $false)][switch] $Synchronous,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][ValidateSet('human', 'tap', 'junit', 'json')][string] $ResultFormat = 'json',
        [Parameter(Mandatory = $false)][switch] $Concise,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][switch] $CodeCoverageDetailed,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $ClassName = @($ClassName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $TestName = @($TestName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $SuiteName = @($SuiteName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $categories = @($TestCategory | Where-Object { $_ })
    if ((@($ClassName.Count, $TestName.Count, $SuiteName.Count, $categories.Count) | Where-Object { $_ -gt 0 }).Count -gt 1) {
        throw 'Use only one of -ClassName, -TestName, -SuiteName and -TestCategory.'
    }
    $selected = ($ClassName.Count + $TestName.Count + $SuiteName.Count) -gt 0
    if ($selected -and $TestLevel -and $TestLevel -ne 'RunSpecifiedTests') {
        throw "Naming classes, tests or suites needs -TestLevel RunSpecifiedTests, not $TestLevel."
    }
    if ($categories.Count -gt 0 -and -not $TestLevel) { throw '-TestCategory needs -TestLevel (for example RunLocalTests); the Salesforce CLI rejects a category without a test level.' }
    if ($Synchronous -and ($SuiteName.Count -gt 0 -or $ClassName.Count -gt 1)) { throw 'A synchronous run can include tests from only one class or flow. Drop -Synchronous or name one.' }
    if ($CodeCoverageDetailed -and -not $CodeCoverage) { throw '-CodeCoverageDetailed needs -CodeCoverage.' }

    $arguments = @('logic', 'run', 'test')
    foreach ($item in $ClassName) { $arguments += @('--class-names', $item) }
    foreach ($item in $TestName) { $arguments += @('--tests', $item) }
    foreach ($item in $SuiteName) { $arguments += @('--suite-names', $item) }
    foreach ($item in $categories) { $arguments += @('--test-category', $item) }
    if ($TestLevel) { $arguments += @('--test-level', $TestLevel) }
    if ($Synchronous) { $arguments += '--synchronous' }
    if ($PSBoundParameters.ContainsKey('WaitMinutes')) { $arguments += @('--wait', $WaitMinutes) }
    if ($Concise) { $arguments += '--concise' }
    if ($CodeCoverage) { $arguments += '--code-coverage' }
    if ($CodeCoverageDetailed) { $arguments += '--detailed-coverage' }
    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) { throw "Output directory '$OutputDirectory' does not exist." }
        $arguments += @('--output-dir', $OutputDirectory)
    }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += @('--result-format', $ResultFormat)
    # --json makes the CLI return a run ID straight away for any run except RunSpecifiedTests, so a synchronous run asks for the JSON format only.
    if ($ResultFormat -eq 'json' -and -not $Synchronous) { $arguments += '--json' }

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    ConvertFrom-SalesforceTestRunOutput -Output $output -ResultFormat $ResultFormat -Plugin '@salesforce/plugin-apex' -Command 'logic run test'
}

function Get-SalesforceLogicTestResult {
    <#
    .SYNOPSIS
    Gets the results of an earlier Flow and Apex test run (sf logic get test).

    .DESCRIPTION
    Takes the TestRunId that Test-SalesforceLogic returned. Errors are the same as for Test-SalesforceLogic.

    .PARAMETER TestRunId
    ID of the test run. Passed to sf as --test-run-id. Required.

    .PARAMETER ResultFormat
    Format of the test results. Passed to sf as --result-format. Default: json. Valid values: human, tap, junit, json.

    .PARAMETER Concise
    Display only failed test results; works with human-readable output only. Adds --concise.

    .PARAMETER CodeCoverage
    Retrieve code coverage results. Adds --code-coverage.

    .PARAMETER CodeCoverageDetailed
    Display detailed code coverage per test. Adds --detailed-coverage.

    .PARAMETER OutputDirectory
    Directory in which to store test result files. Passed to sf as --output-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceLogicTestResult -TestRunId 707xx0000000001 -CodeCoverage -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf logic get test (beta) (plugin @salesforce/plugin-apex)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TestRunId = --test-run-id; -ResultFormat = --result-format; -Concise = --concise; -CodeCoverage = --code-coverage; -CodeCoverageDetailed = --detailed-coverage; -OutputDirectory = --output-dir; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-apex

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^707[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $TestRunId,
        [Parameter(Mandatory = $false)][ValidateSet('human', 'tap', 'junit', 'json')][string] $ResultFormat = 'json',
        [Parameter(Mandatory = $false)][switch] $Concise,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][switch] $CodeCoverageDetailed,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($CodeCoverageDetailed -and -not $CodeCoverage) { throw '-CodeCoverageDetailed needs -CodeCoverage.' }

    $arguments = @('logic', 'get', 'test', '--test-run-id', $TestRunId)
    if ($Concise) { $arguments += '--concise' }
    if ($CodeCoverage) { $arguments += '--code-coverage' }
    if ($CodeCoverageDetailed) { $arguments += '--detailed-coverage' }
    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) { throw "Output directory '$OutputDirectory' does not exist." }
        $arguments += @('--output-dir', $OutputDirectory)
    }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += @('--result-format', $ResultFormat)
    if ($ResultFormat -eq 'json') { $arguments += '--json' }

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    ConvertFrom-SalesforceTestRunOutput -Output $output -ResultFormat $ResultFormat -Plugin '@salesforce/plugin-apex' -Command 'logic get test'
}

function ConvertFrom-SalesforceTestRunOutput {
    # Turns the output of a flow/logic test command into objects, keeping a failed test run apart from a command that could not run.
    #   summary present  -> the run finished: write TestRunId, Summary, Tests and Coverage; if the outcome is not Passed, throw PsfdxTestsFailed
    #   testRunId only   -> an asynchronous run, or a wait that timed out: return the run ID
    #   anything else    -> the command failed (no auth, bad flag, plugin missing...): throw PsfdxTestRunInvocationFailed
    # Other result formats are text for people or a CI system and are returned unchanged.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][AllowEmptyCollection()] $Output,
        [Parameter(Mandatory = $true)][string] $ResultFormat,
        [Parameter(Mandatory = $true)][string] $Plugin,
        [Parameter(Mandatory = $true)][string] $Command
    )
    if ($ResultFormat -ne 'json') { return $Output }

    $fail = {
        param([string] $Message, $Target)
        $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException $Message), 'PsfdxTestRunInvocationFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Target)
        throw $record
    }

    $text = [string]::Join([Environment]::NewLine, @($Output | ForEach-Object { [string] $_ })).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { & $fail "sf $Command returned no output where JSON was expected." $null }
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop } catch {
        $preview = $text; if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
        & $fail "sf $Command returned output that is not valid JSON: $preview" $null
    }

    $result = $null
    if ($null -ne $parsed -and $null -ne $parsed.PSObject.Properties['result']) { $result = $parsed.result }

    if ($null -ne $result -and $null -ne $result.PSObject.Properties['summary'] -and $null -ne $result.summary) {
        $tests = @()
        if ($null -ne $result.PSObject.Properties['tests']) { $tests = @($result.tests) }
        $coverage = $null
        if ($null -ne $result.PSObject.Properties['coverage']) { $coverage = $result.coverage }
        $runId = $null
        if ($null -ne $result.summary.PSObject.Properties['testRunId']) { $runId = [string] $result.summary.testRunId }
        $inProgress = $result.summary.outcome -in @('Queued', 'Holding', 'Preparing', 'Processing')
        [pscustomobject]@{ TestRunId = $runId; Summary = $result.summary; Tests = $tests; Coverage = $coverage; Completed = (-not $inProgress) }
        if ($inProgress) { return }
        if ($result.summary.outcome -ne 'Passed') {
            $message = "Tests did not pass: outcome $($result.summary.outcome), $($result.summary.failing) failing of $($result.summary.testsRan) run."
            $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException $message), 'PsfdxTestsFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $result.summary)
            throw $record
        }
        return
    }

    if ($null -ne $result -and $null -ne $result.PSObject.Properties['testRunId'] -and -not [string]::IsNullOrWhiteSpace([string] $result.testRunId)) {
        return [pscustomobject]@{ TestRunId = [string] $result.testRunId; Completed = $false }
    }

    $detail = ''
    if ($null -ne $parsed -and $null -ne $parsed.PSObject.Properties['message'] -and $parsed.message) { $detail = [string] $parsed.message }
    $message = "sf $Command failed"
    if ($null -ne $parsed -and $null -ne $parsed.PSObject.Properties['status']) { $message += " with status $($parsed.status)" }
    if ($detail) { $message += ": $detail" } else { $message += '.' }
    if ($detail -match '(?i)not a sf command|command .*not found|not installed|plugin') {
        $message += " The command comes from $Plugin; if the plugin is missing, install it with 'sf plugins install $Plugin' or update the Salesforce CLI ('sf update')."
    }
    & $fail $message $parsed
}

#endregion

#region Apex Scaffolding

function New-SalesforceApexClass {
    <#
    .SYNOPSIS
    Generates a new Apex class in the project.

    .DESCRIPTION
    Runs sf template generate apex class and writes the .cls and .cls-meta.xml files. The output folder must already exist.

    .PARAMETER Name
    Name of the generated Apex class. Passed to sf as --name. Required.

    .PARAMETER Template
    Template to use for file creation. Passed to sf as --template. Default: DefaultApexClass. Valid values: DefaultApexClass, ApexUnitTest, InboundEmailService, ApexException, BasicUnitTest, Batchable, Queueable.

    .PARAMETER OutputDirectory
    Directory for saving the created files. Passed to sf as --output-dir.

    .EXAMPLE
    New-SalesforceApexClass -Name AccountService -OutputDirectory force-app/main/default/classes
    A default class in the usual folder.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate apex class (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
      Values psfdx cannot pass: --template ApexException, BasicUnitTest, Batchable, Queueable
    Parameter to flag: -Name = --name; -Template = --template; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string]
            [ValidateSet('DefaultApexClass', 'ApexUnitTest', 'InboundEmailService', 'ApexException', 'BasicUnitTest', 'Batchable', 'Queueable')]
            $Template = 'DefaultApexClass',
        # No default: when omitted, --output-dir is left off so the CLI picks the
        # project's own default package directory.
        [Parameter(Mandatory = $false)][string] $OutputDirectory
    )
    $arguments = @('template', 'generate', 'apex', 'class')
    $arguments += @('--name', $Name)
    $arguments += @('--template', $Template)
    if ($PSBoundParameters.ContainsKey('OutputDirectory') -and -not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) {
            throw "Output directory '$OutputDirectory' does not exist."
        }
        $arguments += @('--output-dir', $OutputDirectory)
    }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

function New-SalesforceApexTrigger {
    <#
    .SYNOPSIS
    Generates a new Apex trigger in the project.

    .DESCRIPTION
    Runs sf template generate apex trigger and writes the .trigger and .trigger-meta.xml files. The output folder must already exist.

    .PARAMETER Name
    Name of the generated Apex trigger. Passed to sf as --name. Required.

    .PARAMETER Event
    The trigger event. Default: before insert. Passed to sf as --event. Default: before insert. Valid values: before insert, before update, before delete, after insert, after update, after delete, after undelete.

    .PARAMETER SObject
    Salesforce object to generate a trigger on. Passed to sf as --sobject.

    .PARAMETER Template
    Template to use. Passed to sf as --template. Valid value: ApexTrigger, which is also the CLI default.

    .PARAMETER OutputDirectory
    Directory for saving the created files. Passed to sf as --output-dir.

    .EXAMPLE
    New-SalesforceApexTrigger -Name AccountTrigger -SObject Account -Event 'before insert'
    A before-insert trigger on Account.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate apex trigger (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Event = --event; -SObject = --sobject; -Template = --template; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string]
            [ValidateSet('before insert', 'before update', 'before delete', 'after insert', 'after update', 'after delete', 'after undelete')]
            $Event = 'before insert',
        [Parameter(Mandatory = $false)][string] $SObject,
        [Parameter(Mandatory = $false)][ValidateSet('ApexTrigger')][string] $Template,
        # No default: when omitted, --output-dir is left off so the CLI picks the
        # project's own default package directory.
        [Parameter(Mandatory = $false)][string] $OutputDirectory
    )
    $arguments = @('template', 'generate', 'apex', 'trigger')
    $arguments += @('--name', $Name)
    $arguments += @('--event', $Event)
    if ($SObject) { $arguments += @('--sobject', $SObject) }
    if ($Template) { $arguments += @('--template', $Template) }
    if ($PSBoundParameters.ContainsKey('OutputDirectory') -and -not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) {
            throw "Output directory '$OutputDirectory' does not exist."
        }
        $arguments += @('--output-dir', $OutputDirectory)
    }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

#endregion

#region LWC Dev Server

function Install-SalesforceLwcDevServer {
    <#
    .SYNOPSIS
    Installs the Salesforce CLI plugin that provides the LWC local dev server.

    .DESCRIPTION
    Runs sf plugins install @salesforce/plugin-lightning-dev. Start-SalesforceLwcDevServer stops with a message pointing here until the plugin is installed.

    .EXAMPLE
    Install-SalesforceLwcDevServer
    Install the plugin.

    .NOTES
    Installs or updates software on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins install (plugin @oclif/plugin-plugins)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --force, --help, --silent, --verbose
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
    Param()
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments @('plugins', 'install', '@salesforce/plugin-lightning-dev') @commonParams
}

function Test-SalesforceLightningDevPluginInstalled {
    [CmdletBinding()]
    Param()
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $raw = Invoke-Salesforce -FilePath 'sf' -Arguments @('plugins', '--core', '--json') @commonParams
    $text = ($raw | Out-String)
    return ($text -match '@salesforce/plugin-lightning-dev')
}

function Start-SalesforceLwcDevServer {
    <#
    .SYNOPSIS
    Starts the local Lightning dev server for an app, a component or an Experience site.

    .DESCRIPTION
    Runs sf lightning dev app, component or site, chosen by -Mode, and keeps running until you stop it. Needs the @salesforce/plugin-lightning-dev plugin (Install-SalesforceLwcDevServer). -DeviceType only applies to -Mode App.

    .PARAMETER Mode
    What to preview: App (the default), Component or Site. psfdx runs the CLI command with that last word. Default: App. Valid values: App, Component, Site.

    .PARAMETER Name
    Name of the app, component or site to preview. Passed as --name.

    .PARAMETER DeviceType
    Type of device to display the app preview. Passed to sf as --device-type. Valid values: desktop, ios, android. Only with -Mode App.

    .PARAMETER DeviceId
    ID of the mobile device to show the preview on, when -DeviceType is ios or android. By default the CLI uses the first mobile device it finds. Passed to sf as --device-id. Only with -Mode App.

    .PARAMETER ClientSelect
    Open the component preview without choosing a component first, so you pick one in the browser. Adds --client-select. Only with -Mode Component.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Start-SalesforceLwcDevServer -Mode Component -Name accountCard -TargetOrg dev1
    Preview one component.

    .EXAMPLE
    Start-SalesforceLwcDevServer -Mode App -Name Sales -DeviceType ios -DeviceId 8A1B2C3D -TargetOrg dev1
    Preview an app on a specific iOS simulator.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf lightning dev app (plugin @salesforce/plugin-lightning-dev)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Command run: sf lightning dev component (plugin @salesforce/plugin-lightning-dev)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Command run: sf lightning dev site (plugin @salesforce/plugin-lightning-dev)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -DeviceType = --device-type; -DeviceId = --device-id; -ClientSelect = --client-select; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.
    Before it starts, an internal helper (Test-SalesforceLightningDevPluginInstalled) runs sf plugins --core --json to check that @salesforce/plugin-lightning-dev is listed.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-lightning-dev

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][ValidateSet('App', 'Component', 'Site')][string] $Mode = 'App',
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][ValidateSet('desktop', 'ios', 'android')][string] $DeviceType,
        [Parameter(Mandatory = $false)][string] $DeviceId,
        [Parameter(Mandatory = $false)][switch] $ClientSelect,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($PSBoundParameters.ContainsKey('DeviceType') -and $Mode -ne 'App') {
        throw "-DeviceType is only supported with -Mode App."
    }
    if ($DeviceId -and $Mode -ne 'App') { throw '-DeviceId is only supported with -Mode App.' }
    if ($DeviceId -and $DeviceType -eq 'desktop') { throw '-DeviceId is for a mobile device, so use it with -DeviceType ios or android.' }
    if ($ClientSelect -and $Mode -ne 'Component') { throw '-ClientSelect is only supported with -Mode Component.' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    if (-not (Test-SalesforceLightningDevPluginInstalled @commonParams)) {
        throw "The Salesforce CLI plugin '@salesforce/plugin-lightning-dev' is not installed. Run Install-SalesforceLwcDevServer, then try again."
    }
    $arguments = @('lightning', 'dev', $($Mode.ToLowerInvariant()))
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $arguments += @('--name', $Name)
    }
    if ($DeviceType) { $arguments += @('--device-type', $DeviceType) }
    if ($DeviceId) { $arguments += @('--device-id', $DeviceId) }
    if ($ClientSelect) { $arguments += '--client-select' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

#endregion

#region LWC / Jest Testing

function Install-SalesforceJest {
    <#
    .SYNOPSIS
    Installs the LWC Jest test runner into the current project.

    .DESCRIPTION
    Runs yarn add -D @salesforce/sfdx-lwc-jest when yarn is on the PATH, otherwise npm install -D @salesforce/sfdx-lwc-jest. This downloads and runs code from the package registry. Node.js is required.

    .EXAMPLE
    Install-SalesforceJest
    Add the Jest runner as a dev dependency.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It runs npm (or yarn when it is on the PATH) through Invoke-Salesforce, which runs a program with an argument array. The program is found on the PATH when the cmdlet runs.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param()
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    if (Get-Command yarn -ErrorAction SilentlyContinue) {
        Invoke-Salesforce -FilePath 'yarn' -Arguments @('add', '-D', '@salesforce/sfdx-lwc-jest') @commonParams
    } else {
        Invoke-Salesforce -FilePath 'npm' -Arguments @('install', '-D', '@salesforce/sfdx-lwc-jest') @commonParams
    }
}

function New-SalesforceJestTest {
    <#
    .SYNOPSIS
    Writes a starter Jest test for a Lightning web component.

    .DESCRIPTION
    Does not use the Salesforce CLI (the old sf force lightning lwc test create command was removed). It writes <name>.test.js into the component's __tests__ folder, with a test that renders the component. It refuses to overwrite an existing test unless you pass -Force.

    .PARAMETER LwcName
    Name of the Lightning web component (letters, digits and underscores, starting with a letter). Its folder must exist under force-app/main/default/lwc. Required.

    .PARAMETER ProjectPath
    Root folder of the Salesforce DX project. It must exist. Default: ..

    .PARAMETER Force
    Overwrite the test file if it already exists.

    .EXAMPLE
    New-SalesforceJestTest -LwcName accountCard -ProjectPath .
    Create force-app/main/default/lwc/accountCard/__tests__/accountCard.test.js.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It works locally in PowerShell and .NET.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $LwcName,
        [Parameter(Mandatory = $false)][string] $ProjectPath = '.',
        [Parameter(Mandatory = $false)][switch] $Force
    )
    # The legacy 'sf force lightning lwc test create' command was removed from the Salesforce CLI,
    # so the Jest test scaffold is written directly.
    if ($LwcName -notmatch '^[A-Za-z][A-Za-z0-9_]*\z') {
        throw "LWC name '$LwcName' is not valid. Use letters, numbers and underscores, starting with a letter."
    }
    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
        throw "Project path '$ProjectPath' does not exist."
    }
    $lwcDir = Join-Path $ProjectPath (Join-Path 'force-app' (Join-Path 'main' (Join-Path 'default' (Join-Path 'lwc' $LwcName))))
    $componentFile = Join-Path $lwcDir "$LwcName.js"
    if (-not (Test-Path -LiteralPath $componentFile -PathType Leaf)) {
        throw "LWC component file '$componentFile' does not exist."
    }
    $testsDir = Join-Path $lwcDir '__tests__'
    $testFile = Join-Path $testsDir "$LwcName.test.js"
    if ((Test-Path -LiteralPath $testFile) -and -not $Force) {
        throw "Jest test '$testFile' already exists. Use -Force to overwrite it."
    }
    if (-not (Test-Path -LiteralPath $testsDir)) {
        New-Item -ItemType Directory -Path $testsDir | Out-Null
    }
    $tag = ($LwcName -creplace '([A-Z])', '-$1').ToLowerInvariant()
    $content = @"
import { createElement } from 'lwc';
import $LwcName from 'c/$LwcName';

describe('c-$tag', () => {
    afterEach(() => {
        // The jsdom instance is shared across test cases in a single file so reset the DOM
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders', () => {
        const element = createElement('c-$tag', { is: $LwcName });
        document.body.appendChild(element);
        expect(element).not.toBeNull();
    });
});
"@
    $content = $content -replace "`r`n", "`n"
    $fullPath = Join-Path (Resolve-Path -LiteralPath $testsDir).ProviderPath "$LwcName.test.js"
    [System.IO.File]::WriteAllText($fullPath, $content, (New-Object System.Text.UTF8Encoding($false)))
    return Get-Item -LiteralPath $fullPath
}

function Test-SalesforceJest {
    <#
    .SYNOPSIS
    Runs the LWC Jest tests of the current project once.

    .DESCRIPTION
    Runs npm run test:unit in the current folder, so the project's package.json must define that script.

    .EXAMPLE
    Test-SalesforceJest
    Run every Jest test.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It runs npm through Invoke-Salesforce, which runs a program with an argument array. The program is found on the PATH when the cmdlet runs.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param()
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'npm' -Arguments @('run', 'test:unit') @commonParams
}

function Debug-SalesforceJest {
    <#
    .SYNOPSIS
    Runs the LWC Jest tests of the current project in debug mode.

    .DESCRIPTION
    Runs npm run test:unit:debug in the current folder, so the project's package.json must define that script (the sfdx project template does). Output is returned as text.

    .EXAMPLE
    Debug-SalesforceJest
    Start the Jest tests with the Node debugger.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It runs npm through Invoke-Salesforce, which runs a program with an argument array. The program is found on the PATH when the cmdlet runs.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param()
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'npm' -Arguments @('run', 'test:unit:debug') @commonParams
}

function Watch-SalesforceJest {
    <#
    .SYNOPSIS
    Runs the LWC Jest tests and re-runs them when files change.

    .DESCRIPTION
    Runs npm run test:unit:watch in the current folder, so the project's package.json must define that script. It keeps running until you stop it.

    .EXAMPLE
    Watch-SalesforceJest
    Watch mode for Jest.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It runs npm through Invoke-Salesforce, which runs a program with an argument array. The program is found on the PATH when the cmdlet runs.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param()
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'npm' -Arguments @('run', 'test:unit:watch') @commonParams
}

#endregion

#region Apex compile status

function Get-SalesforceApexCompileStatus {
    <#
    .SYNOPSIS
    Lists the Apex classes and triggers in an org that do not compile cleanly.

    .DESCRIPTION
    Runs sf apex get compile-status. It returns the compile results of only the Apex classes and triggers that are invalid or have warnings, instead of compiling the whole org, so it is a quick check after a deploy or an upgrade. It only reads. No result means that everything compiles.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceApexCompileStatus -TargetOrg dev1
    The classes and triggers in dev1 with compile errors or warnings.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf apex get compile-status (plugin @salesforce/plugin-apex)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-apex

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('apex', 'get', 'compile-status')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region Template generators

# Wraps the sf template generate commands that write Lightning, Visualforce, static resource, FlexiPage, UI bundle and similar source files into the current project. The CLI replaces a file that differs from the template without asking, so each generator checks for its target first and needs -Force to go ahead.

function Assert-SalesforceGeneratedPathFree {
    # Private: stops when a generator's target already exists, because the CLI replaces a file that differs from the template without asking.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][AllowNull()][AllowEmptyString()][string] $Directory,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]] $RelativePath,
        [Parameter(Mandatory = $true)][string] $What,
        [Parameter(Mandatory = $false)][switch] $Force
    )
    if ($Force) { return }
    $base = $Directory
    if ([string]::IsNullOrWhiteSpace($base)) { $base = '.' }
    $existing = @()
    foreach ($relative in @($RelativePath | Where-Object { $_ })) {
        $candidate = Join-Path $base $relative
        if (Test-Path -LiteralPath $candidate) { $existing += $candidate }
    }
    if ($existing.Count -gt 0) {
        throw "The $What already exists ($($existing -join ', ')). Generating it again replaces any file that differs from the template, without asking, and your changes in it are lost. Use -Force to generate it anyway."
    }
}

function New-SalesforceLightningApp {
    <#
    .SYNOPSIS
    Creates the files of a new Aura Lightning app in the project.

    .DESCRIPTION
    Runs sf template generate lightning app. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the Lightning app already exists in the output folder the cmdlet stops, unless you pass -Force.

    .PARAMETER Name
    Name of the Lightning app. Letters, digits and underscores only. Passed to sf as --name. Required.

    .PARAMETER Template
    Template to use. Valid value: DefaultLightningApp, which is also the CLI default. Passed to sf as --template.

    .PARAMETER OutputDirectory
    Folder to save the created files in. It must be a folder named aura, such as force-app/main/default/aura, or the CLI refuses. The CLI default is the current folder. Passed to sf as --output-dir.

    .PARAMETER Force
    Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

    .EXAMPLE
    New-SalesforceLightningApp -Name MyApp -OutputDirectory force-app/main/default/aura
    Generate the Lightning app.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate lightning app (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Template = --template; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Name,
        [Parameter(Mandatory = $false)][ValidateSet('DefaultLightningApp')][string] $Template,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $Force
    )
    Assert-SalesforceGeneratedPathFree -Directory $OutputDirectory -RelativePath @($Name) -What 'Lightning app' -Force:$Force
    $arguments = @('template', 'generate', 'lightning', 'app', '--name', $Name)
    if ($Template) { $arguments += @('--template', $Template) }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceLightningEvent {
    <#
    .SYNOPSIS
    Creates the files of a new Aura Lightning event in the project.

    .DESCRIPTION
    Runs sf template generate lightning event. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the Lightning event already exists in the output folder the cmdlet stops, unless you pass -Force.

    .PARAMETER Name
    Name of the Lightning event. Letters, digits and underscores only. Passed to sf as --name. Required.

    .PARAMETER Template
    Template to use. Valid value: DefaultLightningEvt, which is also the CLI default. Passed to sf as --template.

    .PARAMETER OutputDirectory
    Folder to save the created files in. It must be a folder named aura, such as force-app/main/default/aura, or the CLI refuses. The CLI default is the current folder. Passed to sf as --output-dir.

    .PARAMETER Force
    Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

    .EXAMPLE
    New-SalesforceLightningEvent -Name MyEvent -OutputDirectory force-app/main/default/aura
    Generate the Lightning event.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate lightning event (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Template = --template; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Name,
        [Parameter(Mandatory = $false)][ValidateSet('DefaultLightningEvt')][string] $Template,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $Force
    )
    Assert-SalesforceGeneratedPathFree -Directory $OutputDirectory -RelativePath @($Name) -What 'Lightning event' -Force:$Force
    $arguments = @('template', 'generate', 'lightning', 'event', '--name', $Name)
    if ($Template) { $arguments += @('--template', $Template) }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceLightningInterface {
    <#
    .SYNOPSIS
    Creates the files of a new Aura Lightning interface in the project.

    .DESCRIPTION
    Runs sf template generate lightning interface. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the Lightning interface already exists in the output folder the cmdlet stops, unless you pass -Force.

    .PARAMETER Name
    Name of the Lightning interface. Letters, digits and underscores only. Passed to sf as --name. Required.

    .PARAMETER Template
    Template to use. Valid value: DefaultLightningIntf, which is also the CLI default. Passed to sf as --template.

    .PARAMETER OutputDirectory
    Folder to save the created files in. It must be a folder named aura, such as force-app/main/default/aura, or the CLI refuses. The CLI default is the current folder. Passed to sf as --output-dir.

    .PARAMETER Force
    Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

    .EXAMPLE
    New-SalesforceLightningInterface -Name MyInterface -OutputDirectory force-app/main/default/aura
    Generate the Lightning interface.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate lightning interface (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Template = --template; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Name,
        [Parameter(Mandatory = $false)][ValidateSet('DefaultLightningIntf')][string] $Template,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $Force
    )
    Assert-SalesforceGeneratedPathFree -Directory $OutputDirectory -RelativePath @($Name) -What 'Lightning interface' -Force:$Force
    $arguments = @('template', 'generate', 'lightning', 'interface', '--name', $Name)
    if ($Template) { $arguments += @('--template', $Template) }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceLightningTest {
    <#
    .SYNOPSIS
    Creates the static resource of a new Lightning test in the project.

    .DESCRIPTION
    Runs sf template generate lightning test. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the Lightning test already exists in the output folder the cmdlet stops, unless you pass -Force.

    .PARAMETER Name
    Name of the Lightning test. Letters, digits and underscores only. Passed to sf as --name. Required.

    .PARAMETER Template
    Template to use. Valid value: DefaultLightningTest, which is also the CLI default. Passed to sf as --template.

    .PARAMETER OutputDirectory
    Folder to save the created files in. It is created if it does not exist. The CLI default is the current folder. Passed to sf as --output-dir.

    .PARAMETER Force
    Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

    .EXAMPLE
    New-SalesforceLightningTest -Name MyTest -OutputDirectory force-app/main/default/staticresources
    Generate the Lightning test.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate lightning test (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Template = --template; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Name,
        [Parameter(Mandatory = $false)][ValidateSet('DefaultLightningTest')][string] $Template,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $Force
    )
    Assert-SalesforceGeneratedPathFree -Directory $OutputDirectory -RelativePath @("$Name.resource", "$Name.resource-meta.xml") -What 'Lightning test' -Force:$Force
    $arguments = @('template', 'generate', 'lightning', 'test', '--name', $Name)
    if ($Template) { $arguments += @('--template', $Template) }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceVisualforceComponent {
    <#
    .SYNOPSIS
    Creates the files of a new Visualforce component in the project.

    .DESCRIPTION
    Runs sf template generate visualforce component. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the Visualforce component already exists in the output folder the cmdlet stops, unless you pass -Force.

    .PARAMETER Name
    Name of the Visualforce component. Letters, digits and underscores only. Passed to sf as --name. Required.

    .PARAMETER Label
    Label of the Visualforce item, as shown in Setup. Passed to sf as --label. Required.

    .PARAMETER Template
    Template to use. Valid value: DefaultVFComponent, which is also the CLI default. Passed to sf as --template.

    .PARAMETER OutputDirectory
    Folder to save the created files in. It is created if it does not exist. The CLI default is the current folder. Passed to sf as --output-dir.

    .PARAMETER Force
    Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

    .EXAMPLE
    New-SalesforceVisualforceComponent -Name MyComponent -Label 'My Component' -OutputDirectory force-app/main/default/components
    Generate the Visualforce component.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate visualforce component (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Label = --label; -Template = --template; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Name,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Label,
        [Parameter(Mandatory = $false)][ValidateSet('DefaultVFComponent')][string] $Template,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $Force
    )
    Assert-SalesforceGeneratedPathFree -Directory $OutputDirectory -RelativePath @("$Name.component", "$Name.component-meta.xml") -What 'Visualforce component' -Force:$Force
    $arguments = @('template', 'generate', 'visualforce', 'component', '--name', $Name, '--label', $Label)
    if ($Template) { $arguments += @('--template', $Template) }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceVisualforcePage {
    <#
    .SYNOPSIS
    Creates the files of a new Visualforce page in the project.

    .DESCRIPTION
    Runs sf template generate visualforce page. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the Visualforce page already exists in the output folder the cmdlet stops, unless you pass -Force.

    .PARAMETER Name
    Name of the Visualforce page. Letters, digits and underscores only. Passed to sf as --name. Required.

    .PARAMETER Label
    Label of the Visualforce item, as shown in Setup. Passed to sf as --label. Required.

    .PARAMETER OutputDirectory
    Folder to save the created files in. It is created if it does not exist. The CLI default is the current folder. Passed to sf as --output-dir.

    .PARAMETER Force
    Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

    .EXAMPLE
    New-SalesforceVisualforcePage -Name MyPage -Label 'My Page' -OutputDirectory force-app/main/default/pages
    Generate the Visualforce page.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate visualforce page (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Label = --label; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Name,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Label,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $Force
    )
    Assert-SalesforceGeneratedPathFree -Directory $OutputDirectory -RelativePath @("$Name.page", "$Name.page-meta.xml") -What 'Visualforce page' -Force:$Force
    $arguments = @('template', 'generate', 'visualforce', 'page', '--name', $Name, '--label', $Label)
    
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceAnalyticsTemplate {
    <#
    .SYNOPSIS
    Creates the files of a simple CRM Analytics template in the project.

    .DESCRIPTION
    Runs sf template generate analytics template. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the Analytics template already exists in the output folder the cmdlet stops, unless you pass -Force.

    .PARAMETER Name
    Name of the Analytics template. Letters, digits and underscores only. Passed to sf as --name. Required.

    .PARAMETER OutputDirectory
    Folder to save the created files in. It must be a folder named waveTemplates, such as force-app/main/default/waveTemplates, or the CLI refuses. The CLI default is the current folder. Passed to sf as --output-dir.

    .PARAMETER Force
    Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

    .EXAMPLE
    New-SalesforceAnalyticsTemplate -Name SalesDashboard -OutputDirectory force-app/main/default/waveTemplates
    Generate the Analytics template.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate analytics template (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Name,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $Force
    )
    Assert-SalesforceGeneratedPathFree -Directory $OutputDirectory -RelativePath @($Name) -What 'Analytics template' -Force:$Force
    $arguments = @('template', 'generate', 'analytics', 'template', '--name', $Name)
    
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceLightningComponent {
    <#
    .SYNOPSIS
    Creates the files of a new Lightning web component or Aura component in the project.

    .DESCRIPTION
    Runs sf template generate lightning component. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the component already exists in the output folder the cmdlet stops, unless you pass -Force. The output folder must be named lwc for a web component and aura for an Aura component.

    .PARAMETER Name
    Name of the component. Letters, digits and underscores only. Passed to sf as --name. Required.

    .PARAMETER Type
    Kind of component. Valid values: aura, lwc. The CLI default is lwc. Passed to sf as --type.

    .PARAMETER Template
    Template to use. Valid values: default, analyticsDashboard, analyticsDashboardWithStep, typescript. The CLI default is default. Passed to sf as --template.

    .PARAMETER OutputDirectory
    Folder to save the created files in. It must be named lwc for -Type lwc and aura for -Type aura, or the CLI refuses. The CLI default is the current folder. Passed to sf as --output-dir.

    .PARAMETER Force
    Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

    .EXAMPLE
    New-SalesforceLightningComponent -Name accountCard -Type lwc -OutputDirectory force-app/main/default/lwc
    Generate a Lightning web component.

    .EXAMPLE
    New-SalesforceLightningComponent -Name accountCard -Type lwc -Template typescript -OutputDirectory force-app/main/default/lwc
    Generate a TypeScript component.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate lightning component (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Type = --type; -Template = --template; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Name,
        [Parameter(Mandatory = $false)][ValidateSet('aura', 'lwc')][string] $Type,
        [Parameter(Mandatory = $false)][ValidateSet('default', 'analyticsDashboard', 'analyticsDashboardWithStep', 'typescript')][string] $Template,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $Force
    )
    Assert-SalesforceGeneratedPathFree -Directory $OutputDirectory -RelativePath @($Name) -What 'Lightning component' -Force:$Force
    $arguments = @('template', 'generate', 'lightning', 'component', '--name', $Name)
    if ($Type) { $arguments += @('--type', $Type) }
    if ($Template) { $arguments += @('--template', $Template) }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceStaticResource {
    <#
    .SYNOPSIS
    Creates the files of a new static resource in the project.

    .DESCRIPTION
    Runs sf template generate static-resource. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. It writes the metadata file and an empty folder for the content. If the static resource already exists in the output folder the cmdlet stops, unless you pass -Force.

    .PARAMETER Name
    Name of the static resource. Letters, digits and underscores only. Passed to sf as --name. Required.

    .PARAMETER Type
    Content (MIME) type of the static resource. The CLI default is application/zip. Passed to sf as --type.

    .PARAMETER OutputDirectory
    Folder to save the created files in. It is created if it does not exist. The CLI default is the current folder. Passed to sf as --output-dir.

    .PARAMETER Force
    Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

    .EXAMPLE
    New-SalesforceStaticResource -Name Logos -Type application/zip -OutputDirectory force-app/main/default/staticresources
    Generate a zip static resource.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate static-resource (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Type = --type; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Name,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]*/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]*\z')][string] $Type,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $Force
    )
    Assert-SalesforceGeneratedPathFree -Directory $OutputDirectory -RelativePath @("$Name", "$Name.resource-meta.xml") -What 'static resource' -Force:$Force
    $arguments = @('template', 'generate', 'static-resource', '--name', $Name)
    if ($Type) { $arguments += @('--type', $Type) }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceUiBundle {
    <#
    .SYNOPSIS
    Creates a UI bundle: the code and metadata of a React, Angular or Vue experience.

    .DESCRIPTION
    Runs sf template generate ui-bundle, which writes a bundle for a UI built with a non-native framework such as React or Angular, under a uiBundles folder in the output folder. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the bundle already exists the cmdlet stops, unless you pass -Force.

    .PARAMETER Name
    Name of the UI bundle. Letters, digits and underscores only. Passed to sf as --name. Required.

    .PARAMETER Label
    Label of the UI bundle. By default the CLI uses the name. Passed to sf as --label.

    .PARAMETER Template
    Template to use. Valid values: default, reactbasic, angularbasic, vuebasic. The CLI default is default. Passed to sf as --template.

    .PARAMETER OutputDirectory
    Folder to save the created files in. It is created if it does not exist. The CLI default is the current folder. Passed to sf as --output-dir.

    .PARAMETER Force
    Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

    .EXAMPLE
    New-SalesforceUiBundle -Name Storefront -Label Storefront -Template reactbasic -OutputDirectory force-app/main/default
    Generate a React bundle.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate ui-bundle (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Label = --label; -Template = --template; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Name,
        [Parameter(Mandatory = $false)][string] $Label,
        [Parameter(Mandatory = $false)][ValidateSet('default', 'reactbasic', 'angularbasic', 'vuebasic')][string] $Template,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $Force
    )
    Assert-SalesforceGeneratedPathFree -Directory $OutputDirectory -RelativePath @((Join-Path 'uiBundles' $Name)) -What 'UI bundle' -Force:$Force
    $arguments = @('template', 'generate', 'ui-bundle', '--name', $Name)
    if ($Label) { $arguments += @('--label', $Label) }
    if ($Template) { $arguments += @('--template', $Template) }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceUiEmbedding {
    <#
    .SYNOPSIS
    Creates a Lightning web component that embeds a web page with lightning-ui-embedding.

    .DESCRIPTION
    Runs sf template generate ui-embedding, which writes a Lightning web component that wraps the lightning-ui-embedding base component and shows -Src in a sandboxed frame. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. The output folder must be named lwc. If the component already exists the cmdlet stops, unless you pass -Force.

    .PARAMETER Name
    Name of the component. Letters, digits and underscores only. Passed to sf as --name. Required.

    .PARAMETER Src
    URL of the page to embed. It must be an absolute https:// URL. Passed to sf as --src. Required.

    .PARAMETER Title
    Title of the embedded frame. Passed to sf as --title. Required.

    .PARAMETER Sandbox
    What the embedded page may do: one or more sandbox permissions. Each is passed to sf as its own --sandbox. Valid values: allow-forms, allow-modals, allow-orientation-lock, allow-pointer-lock, allow-popups, allow-popups-to-escape-sandbox, allow-presentation, allow-same-origin, allow-scripts, allow-storage-access-by-user-activation, allow-top-navigation, allow-top-navigation-by-user-activation. Passed to sf as --sandbox. Required.

    .PARAMETER OutputDirectory
    Folder to save the created files in. It must be a folder named lwc, such as force-app/main/default/lwc, or the CLI refuses. The CLI default is the current folder. Passed to sf as --output-dir.

    .PARAMETER Force
    Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

    .EXAMPLE
    New-SalesforceUiEmbedding -Name statusPage -Src https://status.example.com -Title 'Status' -Sandbox allow-scripts, allow-forms -OutputDirectory force-app/main/default/lwc
    Embed a status page.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate ui-embedding (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Src = --src; -Title = --title; -Sandbox = --sandbox; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Name,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Src,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Title,
        [Parameter(Mandatory = $true)][ValidateSet('allow-forms', 'allow-modals', 'allow-orientation-lock', 'allow-pointer-lock', 'allow-popups', 'allow-popups-to-escape-sandbox', 'allow-presentation', 'allow-same-origin', 'allow-scripts', 'allow-storage-access-by-user-activation', 'allow-top-navigation', 'allow-top-navigation-by-user-activation')][string[]] $Sandbox,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $Force
    )
    if (-not [System.Uri]::TryCreate($Src, [System.UriKind]::Absolute, [ref]$null) -or -not $Src.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) { throw "-Src must be an absolute https:// URL. Got '$Src'." }
    Assert-SalesforceGeneratedPathFree -Directory $OutputDirectory -RelativePath @($Name) -What 'component' -Force:$Force
    $arguments = @('template', 'generate', 'ui-embedding', '--name', $Name, '--src', $Src, '--title', $Title)
    foreach ($item in @($Sandbox | Where-Object { $_ })) { $arguments += @('--sandbox', $item) }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceFlexiPage {
    <#
    .SYNOPSIS
    Creates a FlexiPage (Lightning page) in the project. Beta.

    .DESCRIPTION
    Runs sf template generate flexipage, which writes a record page, app page or home page under a flexipages folder in the output folder. This CLI command is in beta, so its flags and output can change in a later release. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. A record page needs -SObject. If the page already exists the cmdlet stops, unless you pass -Force.

    .PARAMETER Name
    API name of the FlexiPage. Letters, digits and underscores only. Passed to sf as --name. Required.

    .PARAMETER Template
    Kind of page. Valid values: RecordPage, AppPage, HomePage. Passed to sf as --template. Required.

    .PARAMETER SObject
    API name of the object the page is for. Required for a RecordPage. Passed to sf as --sobject.

    .PARAMETER Label
    Label of the page. By default the CLI uses the name. Passed to sf as --label.

    .PARAMETER Description
    Description of the page. Passed to sf as --description.

    .PARAMETER PrimaryField
    Primary field of the highlights header, usually Name. Only for a RecordPage. Passed to sf as --primary-field.

    .PARAMETER SecondaryFields
    Secondary fields of the highlights header, at most 11. Each is passed to sf as its own --secondary-fields. Only for a RecordPage. Passed to sf as --secondary-fields.

    .PARAMETER DetailFields
    Fields to show in the Details tab, split into two columns. Each is passed to sf as its own --detail-fields. Only for a RecordPage. Passed to sf as --detail-fields.

    .PARAMETER OutputDirectory
    Folder to save the created files in. It is created if it does not exist. The CLI default is the current folder. Passed to sf as --output-dir.

    .PARAMETER Force
    Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

    .EXAMPLE
    New-SalesforceFlexiPage -Name Account_Record_Page -Template RecordPage -SObject Account -PrimaryField Name -SecondaryFields Industry, Phone -OutputDirectory force-app/main/default
    Generate a record page for Account.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate flexipage (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Template = --template; -SObject = --sobject; -Label = --label; -Description = --description; -PrimaryField = --primary-field; -SecondaryFields = --secondary-fields; -DetailFields = --detail-fields; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Name,
        [Parameter(Mandatory = $true)][ValidateSet('RecordPage', 'AppPage', 'HomePage')][string] $Template,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $SObject,
        [Parameter(Mandatory = $false)][string] $Label,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $PrimaryField,
        [Parameter(Mandatory = $false)][string[]] $SecondaryFields,
        [Parameter(Mandatory = $false)][string[]] $DetailFields,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $Force
    )
    if ($Template -eq 'RecordPage' -and -not $SObject) { throw 'A RecordPage needs -SObject, the object the page is for.' }
    if ($Template -ne 'RecordPage' -and ($PrimaryField -or $SecondaryFields -or $DetailFields)) { throw '-PrimaryField, -SecondaryFields and -DetailFields are only for a RecordPage.' }
    $secondary = @($SecondaryFields | Where-Object { $_ })
    if ($secondary.Count -gt 11) { throw "-SecondaryFields takes at most 11 fields, not $($secondary.Count)." }
    Assert-SalesforceGeneratedPathFree -Directory $OutputDirectory -RelativePath @((Join-Path 'flexipages' "$Name.flexipage-meta.xml")) -What 'FlexiPage' -Force:$Force
    $arguments = @('template', 'generate', 'flexipage', '--name', $Name, '--template', $Template)
    if ($SObject) { $arguments += @('--sobject', $SObject) }
    if ($Label) { $arguments += @('--label', $Label) }
    if ($Description) { $arguments += @('--description', $Description) }
    if ($PrimaryField) { $arguments += @('--primary-field', $PrimaryField) }
    foreach ($item in $secondary) { $arguments += @('--secondary-fields', $item) }
    foreach ($item in @($DetailFields | Where-Object { $_ })) { $arguments += @('--detail-fields', $item) }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceLightningOutApp {
    <#
    .SYNOPSIS
    Creates the metadata of a Lightning Out 2.0 app, with its External Client App.

    .DESCRIPTION
    Runs sf template generate lightning-out, which scaffolds the files for a Lightning Out 2.0 app that puts Lightning web components in an outside web page. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. The CLI needs the External Client App name, contact email and callback URL, the runtime and the host domains. Give them as parameters, or in a -DefinitionFile JSON file; a parameter replaces the same value in the file. Without a file all of them are needed, and the cmdlet says which are missing before it runs sf.

    .PARAMETER AppName
    Developer name of the new Lightning Out 2.0 app. Passed to sf as --app-name.

    .PARAMETER Components
    Components the app exposes, written as namespace/myComponent for a Lightning web component (c/myComponent for your own) or namespace:Name for an Aura component. Each is passed to sf as its own --components. They replace, not merge with, the components in the definition file. Passed to sf as --components.

    .PARAMETER DefinitionFile
    Path of a JSON file that describes the app. It must exist. Parameters replace the matching values in it. Passed to sf as --definition-file.

    .PARAMETER EcaName
    Developer name of the External Client App of the app. Passed to sf as --eca-name.

    .PARAMETER EcaContactEmail
    Contact email of the External Client App. Passed to sf as --eca-contact-email.

    .PARAMETER EcaCallbackUrl
    OAuth callback URL of the External Client App. It must be an absolute https:// URL. Passed to sf as --eca-callback-url.

    .PARAMETER HostDomains
    HTTP or HTTPS origins of the outside pages that embed the app. Each is passed to sf as its own --host-domains. They replace, not merge with, the host domains in the definition file. Passed to sf as --host-domains.

    .PARAMETER Runtime
    Runtime that serves the app. Valid values: LWR_CORE, CLWR. Passed to sf as --runtime.

    .PARAMETER OutputDirectory
    Folder to save the created files in. It is created if it does not exist. The CLI default is the current folder. Passed to sf as --output-dir.

    .PARAMETER Force
    Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

    .EXAMPLE
    New-SalesforceLightningOutApp -AppName StoreWidget -Components storeCart -EcaName StoreWidgetEca -EcaContactEmail dev@example.com -EcaCallbackUrl https://shop.example.com/callback -HostDomains https://shop.example.com -Runtime LWR_CORE -OutputDirectory force-app/main/default
    Generate the app with every required value given.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate lightning-out (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -AppName = --app-name; -Components = --components; -DefinitionFile = --definition-file; -EcaName = --eca-name; -EcaContactEmail = --eca-contact-email; -EcaCallbackUrl = --eca-callback-url; -HostDomains = --host-domains; -Runtime = --runtime; -OutputDirectory = --output-dir.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $AppName,
        [Parameter(Mandatory = $false)][string[]] $Components,
        [Parameter(Mandatory = $false)][string] $DefinitionFile,
        [Parameter(Mandatory = $false)][string] $EcaName,
        [Parameter(Mandatory = $false)][string] $EcaContactEmail,
        [Parameter(Mandatory = $false)][string] $EcaCallbackUrl,
        [Parameter(Mandatory = $false)][string[]] $HostDomains,
        [Parameter(Mandatory = $false)][ValidateSet('LWR_CORE', 'CLWR')][string] $Runtime,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $Force
    )
    if ($DefinitionFile -and -not (Test-Path -LiteralPath $DefinitionFile -PathType Leaf)) { throw "Definition file '$DefinitionFile' does not exist." }
    if ($EcaCallbackUrl -and -not ([System.Uri]::TryCreate($EcaCallbackUrl, [System.UriKind]::Absolute, [ref]$null) -and $EcaCallbackUrl.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase))) { throw "-EcaCallbackUrl must be an absolute https:// URL. Got '$EcaCallbackUrl'." }
    if (-not $DefinitionFile) {
        $missing = @()
        if (-not $EcaName) { $missing += '-EcaName' }
        if (-not $Runtime) { $missing += '-Runtime' }
        if (@($HostDomains | Where-Object { $_ }).Count -eq 0) { $missing += '-HostDomains' }
        if (-not $EcaContactEmail) { $missing += '-EcaContactEmail' }
        if (-not $EcaCallbackUrl) { $missing += '-EcaCallbackUrl' }
        if ($missing.Count -gt 0) { throw "Without a -DefinitionFile the CLI needs $($missing -join ', ')." }
    }
    Assert-SalesforceGeneratedPathFree -Directory $OutputDirectory -RelativePath @($AppName | Where-Object { $_ }) -What 'Lightning Out app' -Force:$Force
    $arguments = @('template', 'generate', 'lightning-out')
    if ($AppName) { $arguments += @('--app-name', $AppName) }
    foreach ($item in @($Components | Where-Object { $_ })) { $arguments += @('--components', $item) }
    if ($DefinitionFile) { $arguments += @('--definition-file', $DefinitionFile) }
    if ($EcaName) { $arguments += @('--eca-name', $EcaName) }
    if ($EcaContactEmail) { $arguments += @('--eca-contact-email', $EcaContactEmail) }
    if ($EcaCallbackUrl) { $arguments += @('--eca-callback-url', $EcaCallbackUrl) }
    foreach ($item in @($HostDomains | Where-Object { $_ })) { $arguments += @('--host-domains', $item) }
    if ($Runtime) { $arguments += @('--runtime', $Runtime) }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceExperienceSite {
    <#
    .SYNOPSIS
    Creates the files of a new Experience Cloud site in the project. Preview.

    .DESCRIPTION
    Runs sf template generate digital-experience site. This CLI command is a preview, so its flags, templates and output can change in a later release. It writes the site files into the project; it does not create the site in an org (deploy the files for that). It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput.

    .PARAMETER Name
    Name of the Experience Cloud site. Passed to sf as --name. Required.

    .PARAMETER TemplateName
    Template to build the site from. Valid value: Build Your Own (LWR). Passed to sf as --template-name. Required.

    .PARAMETER AdminEmail
    Email address of the site administrator. By default the CLI uses the user name of the authenticated user. Passed to sf as --admin-email.

    .PARAMETER UrlPathPrefix
    URL path prefix of the site. Letters and digits only. Passed to sf as --url-path-prefix.

    .PARAMETER OutputDirectory
    Folder to generate the site files in. Passed to sf as --output-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceExperienceSite -Name 'Partner Portal' -TemplateName 'Build Your Own (LWR)' -UrlPathPrefix partners -TargetOrg dev1
    Generate the files of an LWR site.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf template generate digital-experience site (plugin @salesforce/plugin-templates)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -TemplateName = --template-name; -AdminEmail = --admin-email; -UrlPathPrefix = --url-path-prefix; -OutputDirectory = --output-dir; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-templates

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $true)][ValidateSet('Build Your Own (LWR)')][string] $TemplateName,
        [Parameter(Mandatory = $false)][string] $AdminEmail,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]+\z')][string] $UrlPathPrefix,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('template', 'generate', 'digital-experience', 'site', '--name', $Name, '--template-name', $TemplateName)
    if ($AdminEmail) { $arguments += @('--admin-email', $AdminEmail) }
    if ($UrlPathPrefix) { $arguments += @('--url-path-prefix', $UrlPathPrefix) }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion
