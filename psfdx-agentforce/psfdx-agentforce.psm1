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

#region Plugin availability

function Test-SalesforceAgentPlugin {
    <#
    .SYNOPSIS
    Checks whether the Salesforce CLI agent plugin is installed.

    .DESCRIPTION
    Runs sf plugins --core --json and returns $true when @salesforce/plugin-agent is listed, otherwise $false. The other agent cmdlets run this check first.

    .EXAMPLE
    if (-not (Test-SalesforceAgentPlugin)) { Install-SalesforcePlugin -Name @salesforce/plugin-agent }
    Install the plugin when it is missing.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins (plugin @oclif/plugin-plugins)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
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
    $raw = Invoke-Salesforce -FilePath 'sf' -Arguments @('plugins', '--core', '--json') @commonParams
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

    if ($Value -notmatch '^[A-Za-z][A-Za-z0-9_]*\z') {
        throw "$What '$Value' is not a valid API name. Use letters, digits and underscores, starting with a letter."
    }
}

#endregion

#region Agent tests

function Get-SalesforceAgentTests {
    <#
    .SYNOPSIS
    Lists the agent tests available in an org.

    .DESCRIPTION
    Runs sf agent test list and returns the test definitions as objects (an empty array when there are none). Needs the @salesforce/plugin-agent plugin.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceAgentTests -TargetOrg dev1
    Agent tests in the org.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent test list (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-agent

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'test', 'list')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $parsed = Show-SalesforceResult -Result $result
    if ($null -eq $parsed) { return @() }
    return @($parsed)
}

function Start-SalesforceAgentTest {
    <#
    .SYNOPSIS
    Starts an Agentforce agent test and optionally waits for it.

    .DESCRIPTION
    Runs sf agent test run for the test API name. Without -WaitMinutes the run is started and the job ID is returned; fetch the outcome later with Get-SalesforceAgentTestResult. Needs the @salesforce/plugin-agent plugin.

    .PARAMETER ApiName
    API name of the agent test to run; corresponds to the name of the AiEvaluationDefinition metadata component that implements the agent test. Passed to sf as --api-name. Required.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the command to complete and display results to the terminal window. Passed to sf as --wait. Range: 1 to 1440.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Start-SalesforceAgentTest -ApiName Service_Agent_Test -WaitMinutes 10 -TargetOrg dev1
    Run the test and wait up to ten minutes.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent test run (plugin @salesforce/plugin-agent)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --output-dir, --result-format, --test-runner, --verbose
    Parameter to flag: -ApiName = --api-name; -WaitMinutes = --wait; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-agent

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ApiName,
        [Parameter(Mandatory = $false)][ValidateRange(1, 1440)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    Assert-SalesforceAgentApiName -Value $ApiName -What 'Agent test'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'test', 'run', '--api-name', $ApiName)
    if ($PSBoundParameters.ContainsKey('WaitMinutes')) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceAgentTestResult {
    <#
    .SYNOPSIS
    Gets the results of an Agentforce agent test run.

    .DESCRIPTION
    Runs sf agent test results for a job ID returned by Start-SalesforceAgentTest. Needs the @salesforce/plugin-agent plugin.

    .PARAMETER JobId
    Job ID of the completed agent test run. Passed to sf as --job-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceAgentTestResult -JobId 4KBxx0000000001 -TargetOrg dev1
    Results of that run.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent test results (plugin @salesforce/plugin-agent)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --output-dir, --result-format, --test-runner, --verbose
    Parameter to flag: -JobId = --job-id; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-agent

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $JobId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if ($JobId -notmatch '^[A-Za-z0-9]{15,18}\z') {
        throw "Job ID '$JobId' is not a valid 15 or 18 character Salesforce ID."
    }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'test', 'results', '--job-id', $JobId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region Agent activation

function Enable-SalesforceAgent {
    <#
    .SYNOPSIS
    Activates an Agentforce agent in an org.

    .DESCRIPTION
    Runs sf agent activate for the agent API name and, optionally, a version. Activating makes the agent available to users. Needs the @salesforce/plugin-agent plugin. Asks for confirmation and supports -WhatIf.

    .PARAMETER ApiName
    API name of the agent to activate; if not specified, the command provides a list that you choose from. Passed to sf as --api-name. Required.

    .PARAMETER Version
    Version number of the agent to activate; if not specified, the command provides a list that you choose from. Passed to sf as --version. Range: 1 to 9999.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Enable-SalesforceAgent -ApiName Service_Agent -Version 2 -TargetOrg dev1 -WhatIf
    Preview activating version 2.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent activate (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ApiName = --api-name; -Version = --version; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-agent

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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

    $arguments = @('agent', 'activate', '--api-name', $ApiName)
    if ($PSBoundParameters.ContainsKey('Version')) { $arguments += @('--version', $Version) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'

    if ($PSCmdlet.ShouldProcess($ApiName, 'Activate agent')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Disable-SalesforceAgent {
    <#
    .SYNOPSIS
    Deactivates an Agentforce agent in an org.

    .DESCRIPTION
    Runs sf agent deactivate for the agent API name. The plugin @salesforce/plugin-agent must be installed; the cmdlet stops with install guidance if it is not. Asks for confirmation and supports -WhatIf.

    .PARAMETER ApiName
    API name of the agent to deactivate; if not specified, the command provides a list that you choose from. Passed to sf as --api-name. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Disable-SalesforceAgent -ApiName Service_Agent -TargetOrg dev1 -WhatIf
    Show what would be deactivated.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent deactivate (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ApiName = --api-name; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-agent

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string] $ApiName,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    Assert-SalesforceAgentApiName -Value $ApiName -What 'Agent'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'deactivate', '--api-name', $ApiName)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'

    if ($PSCmdlet.ShouldProcess($ApiName, 'Deactivate agent')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

#endregion

#region Authoring bundles

# Wraps `sf agent generate|validate|publish authoring-bundle`, the Agent Script authoring commands of @salesforce/plugin-agent.
# Upstream status: these commands are newer than the agent test and activation commands and may be marked beta; they need a recent
# plugin-agent (sf plugins update) and an org with Agentforce enabled. The live CLI help check confirms the names and flags.

function Get-SalesforceAgentDiagnostic {
    # Private: turns a failed validation into one diagnostic object per problem the CLI reports.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)] $Parsed
    )

    $names = @($Parsed.PSObject.Properties.Name)
    $items = @()
    foreach ($key in 'data', 'errors', 'diagnostics') {
        if ($names -contains $key -and $null -ne $Parsed.$key) {
            $value = $Parsed.$key
            if ($value -is [string]) { $items += $value; continue }
            if ($value.PSObject.Properties.Name -contains 'errors' -and $null -ne $value.errors) { $value = $value.errors }
            foreach ($entry in @($value)) { $items += $entry }
        }
    }
    $diagnostics = @()
    foreach ($item in $items) {
        if ($item -is [string]) {
            $diagnostics += [pscustomobject]@{ Message = $item; Line = $null; Column = $null; Severity = 'Error' }
            continue
        }
        $p = @($item.PSObject.Properties.Name)
        $message = $null
        if ($p -contains 'message') { $message = [string]$item.message } elseif ($p -contains 'description') { $message = [string]$item.description } else { $message = ($item | ConvertTo-Json -Compress -Depth 4) }
        $line = $null
        if ($p -contains 'line') { $line = $item.line } elseif ($p -contains 'lineStart') { $line = $item.lineStart }
        $column = $null
        if ($p -contains 'column') { $column = $item.column } elseif ($p -contains 'colStart') { $column = $item.colStart }
        $severity = 'Error'
        if ($p -contains 'severity' -and $item.severity) { $severity = [string]$item.severity }
        $diagnostics += [pscustomobject]@{ Message = $message; Line = $line; Column = $column; Severity = $severity }
    }
    if ($diagnostics.Count -eq 0 -and $names -contains 'message' -and $Parsed.message) {
        $diagnostics += [pscustomobject]@{ Message = [string]$Parsed.message; Line = $null; Column = $null; Severity = 'Error' }
    }
    return $diagnostics
}

function New-SalesforceAgentAuthoringBundle {
    <#
    .SYNOPSIS
    Generates an authoring bundle (Agent Script) for an agent (sf agent generate authoring-bundle).

    .DESCRIPTION
    Writes files into the project, so it asks for confirmation and supports -WhatIf. The CLI requires -Name (the agent label) and either -Spec
    (an agent spec file made by the agent plugin) or -NoSpec to generate a blank bundle; both are checked before the CLI is called. -OutputDir is where the bundle goes (the CLI default is the project's authoring bundle folder). Returns the CLI result, which includes
    the paths written. Needs the @salesforce/plugin-agent plugin, a recent version, and Agentforce enabled in the org.

    .PARAMETER Name
    Name (label) of the authoring bundle; if not specified, you're prompted for the name. Passed to sf as --name. Required.

    .PARAMETER ApiName
    API name of the new authoring bundle; if not specified, the API name is derived from the authoring bundle name (label); the API name can't exist in the org. Passed to sf as --api-name.

    .PARAMETER Spec
    Path to the agent spec YAML file. If you don't specify the flag, the command provides a list that you can choose from. Use the --no-spec flag to skip using an agent spec entirely.

    .PARAMETER NoSpec
    Skip prompting for an agent spec and use the default Agent Script boilerplate in the generated authoring bundle. Adds --no-spec.

    .PARAMETER OutputDir
    Directory where the authoring bundle files are generated. Passed to sf as --output-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceAgentAuthoringBundle -Name 'Service Agent' -ApiName Service_Agent -Spec specs/agentSpec.yaml -TargetOrg my-org

    .EXAMPLE
    New-SalesforceAgentAuthoringBundle -Name 'Service Agent' -ApiName Service_Agent -NoSpec -Confirm:$false | Out-Null
    Test-SalesforceAgentAuthoringBundle -ApiName Service_Agent
    Publish-SalesforceAgentAuthoringBundle -ApiName Service_Agent -Confirm:$false

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent generate authoring-bundle (plugin @salesforce/plugin-agent)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --force-overwrite
    Parameter to flag: -Name = --name; -ApiName = --api-name; -Spec = --spec; -NoSpec = --no-spec; -OutputDir = --output-dir; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-agent

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $ApiName,
        [Parameter(Mandatory = $false)][string] $Spec,
        [Parameter(Mandatory = $false)][switch] $NoSpec,
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if ($ApiName) { Assert-SalesforceAgentApiName -Value $ApiName -What 'Authoring bundle' }
    if ($Spec -and $NoSpec) { throw 'Specify only one of -Spec or -NoSpec.' }
    if (-not $Spec -and -not $NoSpec) { throw 'Specify -Spec (an agent spec file) or -NoSpec to generate a blank bundle.' }
    if ($Spec -and -not (Test-Path -LiteralPath $Spec -PathType Leaf)) { throw "Spec file '$Spec' does not exist." }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'generate', 'authoring-bundle')
    $arguments += @('--name', $Name)
    if ($ApiName) { $arguments += @('--api-name', $ApiName) }
    if ($Spec) { $arguments += @('--spec', $Spec) }
    if ($NoSpec) { $arguments += '--no-spec' }
    if ($OutputDir) { $arguments += @('--output-dir', $OutputDir) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'

    $target = $Name
    if ($ApiName) { $target = $ApiName }
    if ($PSCmdlet.ShouldProcess($target, 'Generate authoring bundle files')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Test-SalesforceAgentAuthoringBundle {
    <#
    .SYNOPSIS
    Validates an authoring bundle and returns the diagnostics as objects (sf agent validate authoring-bundle).

    .DESCRIPTION
    Read-only. Returns Valid, ApiName and Diagnostics (Message, Line, Column, Severity). Invalid Agent Script is returned as Valid = $false with
    its diagnostics, not thrown, so a script can print or filter them; add -ThrowOnInvalid to fail a CI step (error id PsfdxAgentValidationFailed,
    with the result as the target object). Failures that are not validation problems, such as an unknown org, always throw.

    .PARAMETER ApiName
    API name of the authoring bundle you want to validate; if not specified, the command provides a list that you can choose from. Passed to sf as --api-name. Required.

    .PARAMETER ThrowOnInvalid
    Throw an error (id PsfdxAgentValidationFailed, with the result as its target object) when the bundle is not valid, instead of returning Valid = $false with its diagnostics. Meant for CI.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    $v = Test-SalesforceAgentAuthoringBundle -ApiName Service_Agent -TargetOrg my-org; $v.Diagnostics | Format-Table Line, Message

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent validate authoring-bundle (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ApiName = --api-name; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-agent

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ApiName,
        [Parameter(Mandatory = $false)][switch] $ThrowOnInvalid,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    Assert-SalesforceAgentApiName -Value $ApiName -What 'Authoring bundle'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('ThrowOnInvalid')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'validate', 'authoring-bundle', '--api-name', $ApiName)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $text = (@($output) | Out-String).Trim()
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop } catch { $parsed = $null }
    if ($null -eq $parsed) { throw "The Salesforce CLI returned no usable result: $text" }

    $diagnostics = @()
    if ([int]$parsed.status -ne 0) {
        $diagnostics = @(Get-SalesforceAgentDiagnostic -Parsed $parsed)
        $name = ''
        if ($parsed.PSObject.Properties.Name -contains 'name' -and $parsed.name) { $name = [string]$parsed.name }
        $isValidation = ($name -match 'valid|compil|syntax|parse') -or ($parsed.PSObject.Properties.Name -contains 'data' -and $null -ne $parsed.data -and $diagnostics.Count -gt 0)
        if (-not $isValidation) { Show-SalesforceResult -Result $text | Out-Null }
    }
    $valid = ([int]$parsed.status -eq 0)
    $result = [pscustomobject]@{ ApiName = $ApiName; Valid = $valid; Diagnostics = $diagnostics }
    if (-not $valid -and $ThrowOnInvalid) {
        $message = "Authoring bundle '$ApiName' is not valid: $($diagnostics.Count) problem(s)."
        $errorRecord = New-Object System.Management.Automation.ErrorRecord ([System.Exception]::new($message)), 'PsfdxAgentValidationFailed', ([System.Management.Automation.ErrorCategory]::InvalidData), $result
        throw $errorRecord
    }
    return $result
}

function Publish-SalesforceAgentAuthoringBundle {
    <#
    .SYNOPSIS
    Publishes an authoring bundle to the org as an agent (sf agent publish authoring-bundle).

    .DESCRIPTION
    Changes the org, so it asks for confirmation and supports -WhatIf. Returns the CLI result (the published agent). By default the CLI retrieves
    the published agent metadata afterwards; -SkipRetrieve turns that off. Validate first with Test-SalesforceAgentAuthoringBundle.

    .PARAMETER ApiName
    API name of the authoring bundle you want to publish; if not specified, the command provides a list that you can choose from. Passed to sf as --api-name. Required.

    .PARAMETER SkipRetrieve
    Don't retrieve the metadata associated with the agent to your DX project. Adds --skip-retrieve.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Publish-SalesforceAgentAuthoringBundle -ApiName Service_Agent -TargetOrg my-org

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent publish authoring-bundle (plugin @salesforce/plugin-agent)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --concise, --source-type, --verbose
    Parameter to flag: -ApiName = --api-name; -SkipRetrieve = --skip-retrieve; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-agent

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string] $ApiName,
        [Parameter(Mandatory = $false)][switch] $SkipRetrieve,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    Assert-SalesforceAgentApiName -Value $ApiName -What 'Authoring bundle'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'publish', 'authoring-bundle', '--api-name', $ApiName)
    if ($SkipRetrieve) { $arguments += '--skip-retrieve' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'

    $orgLabel = 'the default org'
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $orgLabel = $TargetOrg }
    if ($PSCmdlet.ShouldProcess("$ApiName in $orgLabel", 'Publish authoring bundle')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

#endregion
