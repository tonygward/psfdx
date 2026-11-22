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

    .PARAMETER ExtendedDetails
    Show the generated data, such as the full response of each test, in the results. Adds --verbose.

    .PARAMETER OutputDir
    Folder to write the results files to. Passed to sf as --output-dir.

    .PARAMETER ResultFormat
    Format of the results. Passed to sf as --result-format. Valid values: json, human, junit, tap. Without it the cmdlet returns the result as an object, as before. With json it does too; with human, junit or tap the CLI text is returned as it is.

    .PARAMETER TestRunner
    The test runner that holds the test. Passed to sf as --test-runner. Valid values: agentforce-studio, testing-center.

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
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ApiName = --api-name; -WaitMinutes = --wait; -ExtendedDetails = --verbose; -OutputDir = --output-dir; -ResultFormat = --result-format; -TestRunner = --test-runner; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails,
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][ValidateSet('json', 'human', 'junit', 'tap')][string] $ResultFormat,
        [Parameter(Mandatory = $false)][ValidateSet('agentforce-studio', 'testing-center')][string] $TestRunner,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    Assert-SalesforceAgentApiName -Value $ApiName -What 'Agent test'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'test', 'run', '--api-name', $ApiName)
    if ($PSBoundParameters.ContainsKey('WaitMinutes')) { $arguments += @('--wait', $WaitMinutes) }
    if ($ExtendedDetails) { $arguments += '--verbose' }
    if ($OutputDir) { $arguments += @('--output-dir', $OutputDir) }
    if ($TestRunner) { $arguments += @('--test-runner', $TestRunner) }
    if ($ResultFormat) { $arguments += @('--result-format', $ResultFormat) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    # human, junit and tap are text, so the CLI's output is handed back as it is.
    if ($ResultFormat -and $ResultFormat -ne 'json') { return Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams }
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

    .PARAMETER ExtendedDetails
    Show the generated data, such as the full response of each test, in the results. Adds --verbose.

    .PARAMETER OutputDir
    Folder to write the results files to. Passed to sf as --output-dir.

    .PARAMETER ResultFormat
    Format of the results. Passed to sf as --result-format. Valid values: json, human, junit, tap. Without it the cmdlet returns the result as an object, as before. With json it does too; with human, junit or tap the CLI text is returned as it is.

    .PARAMETER TestRunner
    The test runner that holds the test. Passed to sf as --test-runner. Valid values: agentforce-studio, testing-center.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceAgentTestResult -JobId 4KBxx0000000001 -TargetOrg dev1
    Results of that run.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent test results (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -JobId = --job-id; -ExtendedDetails = --verbose; -OutputDir = --output-dir; -ResultFormat = --result-format; -TestRunner = --test-runner; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails,
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][ValidateSet('json', 'human', 'junit', 'tap')][string] $ResultFormat,
        [Parameter(Mandatory = $false)][ValidateSet('agentforce-studio', 'testing-center')][string] $TestRunner,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if ($JobId -notmatch '^[A-Za-z0-9]{15,18}\z') {
        throw "Job ID '$JobId' is not a valid 15 or 18 character Salesforce ID."
    }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'test', 'results', '--job-id', $JobId)
    if ($ExtendedDetails) { $arguments += '--verbose' }
    if ($OutputDir) { $arguments += @('--output-dir', $OutputDir) }
    if ($TestRunner) { $arguments += @('--test-runner', $TestRunner) }
    if ($ResultFormat) { $arguments += @('--result-format', $ResultFormat) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    # human, junit and tap are text, so the CLI's output is handed back as it is.
    if ($ResultFormat -and $ResultFormat -ne 'json') { return Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams }
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

    .PARAMETER ForceOverwrite
    Overwrite an existing authoring bundle of that name without asking. Without it the CLI refuses to replace one. Adds --force-overwrite.

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
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -ApiName = --api-name; -Spec = --spec; -NoSpec = --no-spec; -OutputDir = --output-dir; -ForceOverwrite = --force-overwrite; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][switch] $ForceOverwrite,
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
    if ($ForceOverwrite) { $arguments += '--force-overwrite' }
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

    .PARAMETER Concise
    Show a short summary of the publish instead of the full detail. Adds --concise.

    .PARAMETER ExtendedDetails
    Show more detail of the publish, such as each step. Adds --verbose. Cannot be used with -Concise.

    .PARAMETER SourceType
    The kind of agent source that is published. Passed to sf as --source-type. Valid value: Bot, which is also the CLI default.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Publish-SalesforceAgentAuthoringBundle -ApiName Service_Agent -TargetOrg my-org

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent publish authoring-bundle (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ApiName = --api-name; -SkipRetrieve = --skip-retrieve; -Concise = --concise; -ExtendedDetails = --verbose; -SourceType = --source-type; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][switch] $Concise,
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails,
        [Parameter(Mandatory = $false)][ValidateSet('Bot')][string] $SourceType,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($Concise -and $ExtendedDetails) { throw 'Use -Concise or -ExtendedDetails, not both.' }

    Assert-SalesforceAgentApiName -Value $ApiName -What 'Authoring bundle'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams

    $arguments = @('agent', 'publish', 'authoring-bundle', '--api-name', $ApiName)
    if ($SkipRetrieve) { $arguments += '--skip-retrieve' }
    if ($Concise) { $arguments += '--concise' }
    if ($ExtendedDetails) { $arguments += '--verbose' }
    if ($SourceType) { $arguments += @('--source-type', $SourceType) }
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

#region Agent users and Builder

# Wraps org create agent-user and org open agent, the org commands for agents.

function New-SalesforceAgentUser {
    <#
    .SYNOPSIS
    Creates the default user that an agent runs as.

    .DESCRIPTION
    Runs sf org create agent-user, which creates the Einstein Agent user an agent uses to run its actions. Without the name parameters the CLI picks defaults. Supports -WhatIf and -Confirm; it does not prompt by default.

    .PARAMETER BaseUsername
    User name to base the new agent user's name on. The CLI adds a unique suffix. Passed to sf as --base-username.

    .PARAMETER FirstName
    First name of the agent user. Passed to sf as --first-name.

    .PARAMETER LastName
    Last name of the agent user. Passed to sf as --last-name.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceAgentUser -FirstName Service -LastName Agent -TargetOrg dev1 -WhatIf
    Preview creating the agent user.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org create agent-user (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -BaseUsername = --base-username; -FirstName = --first-name; -LastName = --last-name; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][string] $BaseUsername,
        [Parameter(Mandatory = $false)][string] $FirstName,
        [Parameter(Mandatory = $false)][string] $LastName,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('org', 'create', 'agent-user')
    if ($BaseUsername) { $arguments += @('--base-username', $BaseUsername) }
    if ($FirstName) { $arguments += @('--first-name', $FirstName) }
    if ($LastName) { $arguments += @('--last-name', $LastName) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($(if ($TargetOrg) { $TargetOrg } else { 'the default org' }), 'Create the agent user')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Open-SalesforceAgent {
    <#
    .SYNOPSIS
    Opens an agent in Agentforce Builder, or prints the link.

    .DESCRIPTION
    Runs sf org open agent. The URL contains a session token, so treat it like a password; -UrlOnly prints it instead of opening a browser. Give -ApiName for a published agent or -AuthoringBundle for a local Agent Script agent.

    .PARAMETER ApiName
    API name of the agent to open. Use it or -AuthoringBundle, not both. Passed to sf as --api-name.

    .PARAMETER AuthoringBundle
    API name of the authoring bundle to open. Use it or -ApiName, not both. Passed to sf as --authoring-bundle.

    .PARAMETER Version
    Version of the agent to open. Passed to sf as --version.

    .PARAMETER Browser
    Browser to open the agent in. Valid values: chrome, edge, firefox. Passed to sf as --browser.

    .PARAMETER BrowserPrivateMode
    Open the agent in the browser's private (incognito) mode. Adds --private.

    .PARAMETER UrlOnly
    Show the URL but do not open a browser. Adds --url-only.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Open-SalesforceAgent -ApiName Service_Agent -UrlOnly -TargetOrg dev1
    Print the Builder link of a published agent.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org open agent (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ApiName = --api-name; -AuthoringBundle = --authoring-bundle; -Version = --version; -Browser = --browser; -BrowserPrivateMode = --private; -UrlOnly = --url-only; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $ApiName,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $AuthoringBundle,
        [Parameter(Mandatory = $false)][ValidateRange(1, 9999)][int] $Version,
        [Parameter(Mandatory = $false)][ValidateSet('chrome', 'edge', 'firefox')][string] $Browser,
        [Parameter(Mandatory = $false)][switch] $BrowserPrivateMode,
        [Parameter(Mandatory = $false)][switch] $UrlOnly,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($ApiName -and $AuthoringBundle) { throw 'Use -ApiName or -AuthoringBundle, not both.' }
    $arguments = @('org', 'open', 'agent')
    if ($ApiName) { $arguments += @('--api-name', $ApiName) }
    if ($AuthoringBundle) { $arguments += @('--authoring-bundle', $AuthoringBundle) }
    if ($PSBoundParameters.ContainsKey('Version')) { $arguments += @('--version', $Version) }
    if ($Browser) { $arguments += @('--browser', $Browser) }
    if ($BrowserPrivateMode) { $arguments += '--private' }
    if ($UrlOnly) { $arguments += '--url-only' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    return Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

#endregion

#region Agent creation and specs

# Wraps sf agent create and the agent generate commands. The generators write local files; New-SalesforceAgentSpec with -FullInterview and New-SalesforceAgentTestSpec ask questions, so they run through Invoke-Salesforce -Interactive.

function Assert-SalesforceAgentInteractiveSession {
    # Private: stops with a clear message when the session cannot ask questions, so an interactive command does not wait for input that never comes.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Command
    )
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw "$Command asks questions, so it needs a terminal. Run it in an interactive PowerShell session, not in a script, job or pipeline whose input or output is redirected."
    }
}

function ConvertTo-SalesforceAgentPlainText {
    # Private: turns a SecureString into text at the moment the command is built.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][System.Security.SecureString] $Value
    )
    $bstr = [IntPtr]::Zero
    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}

function New-SalesforceAgent {
    <#
    .SYNOPSIS
    Creates an agent in an org from a local agent spec file.

    .DESCRIPTION
    Runs sf agent create. The agent spec is the YAML file made by New-SalesforceAgentSpec. With -Preview the CLI shows what it would create without creating it. Supports -WhatIf and -Confirm; it does not prompt by default.

    .PARAMETER Spec
    Path of the agent spec YAML file. It must exist. Passed to sf as --spec.

    .PARAMETER Name
    Name (label) of the agent. By default the CLI uses the name in the spec. Passed to sf as --name.

    .PARAMETER ApiName
    API name of the new agent. By default the CLI derives it from the name. Passed to sf as --api-name.

    .PARAMETER Preview
    Show what would be created, without creating the agent. Adds --preview.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceAgent -Spec .\specs\service-agent.yaml -Name 'Service Agent' -TargetOrg dev1 -WhatIf
    Preview the create.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent create (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Spec = --spec; -Name = --name; -ApiName = --api-name; -Preview = --preview; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][string] $Spec,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $ApiName,
        [Parameter(Mandatory = $false)][switch] $Preview,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($Spec -and -not (Test-Path -LiteralPath $Spec -PathType Leaf)) { throw "Spec file '$Spec' does not exist." }
    $arguments = @('agent', 'create')
    if ($Spec) { $arguments += @('--spec', $Spec) }
    if ($Name) { $arguments += @('--name', $Name) }
    if ($ApiName) { $arguments += @('--api-name', $ApiName) }
    if ($Preview) { $arguments += '--preview' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if ($Preview) { $ConfirmPreference = 'None' }
    if (-not $PSCmdlet.ShouldProcess($(if ($ApiName) { $ApiName } elseif ($Name) { $Name } else { $Spec }), 'Create agent')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceAgentSpec {
    <#
    .SYNOPSIS
    Generates an agent spec: a YAML file that describes what an agent can do, with AI-suggested topics.

    .DESCRIPTION
    Runs sf agent generate agent-spec. The model of your org uses the role and company details to propose the agent's topics; edit the file afterwards, then create the agent with New-SalesforceAgent. Give the details as parameters and the cmdlet returns the CLI result. With -FullInterview the CLI asks for every property, so it is interactive: it needs a terminal, and you should run it as a plain command (an assigned or piped result hides the questions). To improve an existing spec, give it as -Spec.

    .PARAMETER Role
    The role of the agent in your company. Passed to sf as --role.

    .PARAMETER CompanyName
    Name of your company. Passed to sf as --company-name.

    .PARAMETER CompanyDescription
    Description of your company. Passed to sf as --company-description.

    .PARAMETER CompanyWebsite
    Website of your company. Passed to sf as --company-website.

    .PARAMETER Type
    Kind of agent. Valid values: customer, internal. Passed to sf as --type.

    .PARAMETER Tone
    Tone of the agent. Valid values: formal, casual, neutral. Passed to sf as --tone.

    .PARAMETER AgentUser
    User name of the agent user that the agent runs as. Passed to sf as --agent-user.

    .PARAMETER MaxTopics
    Number of topics to propose. Passed to sf as --max-topics.

    .PARAMETER GroundingContext
    Extra text that grounds the model, such as products or policies. Passed to sf as --grounding-context.

    .PARAMETER PromptTemplate
    API name of the prompt template to use to generate the topics. Passed to sf as --prompt-template.

    .PARAMETER EnrichLogs
    Whether to add the generated data to the agent logs. Valid values: true, false. Passed to sf as --enrich-logs.

    .PARAMETER Spec
    An existing spec file to improve. It must exist. Passed to sf as --spec.

    .PARAMETER OutputFile
    File to write the spec to. The CLI default is specs/agentSpec.yaml. The folder must exist. Passed to sf as --output-file.

    .PARAMETER ForceOverwrite
    Overwrite the output file without asking if it already exists. Adds --force-overwrite.

    .PARAMETER FullInterview
    Let the CLI ask for every property. Interactive: needs a terminal. Adds --full-interview.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceAgentSpec -Role 'Answers order questions' -CompanyName Acme -CompanyDescription 'We sell anvils' -Type customer -Tone casual -OutputFile .\specs\orders.yaml -TargetOrg dev1
    Generate a spec without any questions.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent generate agent-spec (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Role = --role; -CompanyName = --company-name; -CompanyDescription = --company-description; -CompanyWebsite = --company-website; -Type = --type; -Tone = --tone; -AgentUser = --agent-user; -MaxTopics = --max-topics; -GroundingContext = --grounding-context; -PromptTemplate = --prompt-template; -EnrichLogs = --enrich-logs; -Spec = --spec; -OutputFile = --output-file; -ForceOverwrite = --force-overwrite; -FullInterview = --full-interview; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][string] $Role,
        [Parameter(Mandatory = $false)][string] $CompanyName,
        [Parameter(Mandatory = $false)][string] $CompanyDescription,
        [Parameter(Mandatory = $false)][string] $CompanyWebsite,
        [Parameter(Mandatory = $false)][ValidateSet('customer', 'internal')][string] $Type,
        [Parameter(Mandatory = $false)][ValidateSet('formal', 'casual', 'neutral')][string] $Tone,
        [Parameter(Mandatory = $false)][string] $AgentUser,
        [Parameter(Mandatory = $false)][ValidateRange(1, 100)][int] $MaxTopics,
        [Parameter(Mandatory = $false)][string] $GroundingContext,
        [Parameter(Mandatory = $false)][string] $PromptTemplate,
        [Parameter(Mandatory = $false)][ValidateSet('true', 'false')][string] $EnrichLogs,
        [Parameter(Mandatory = $false)][string] $Spec,
        [Parameter(Mandatory = $false)][string] $OutputFile,
        [Parameter(Mandatory = $false)][switch] $ForceOverwrite,
        [Parameter(Mandatory = $false)][switch] $FullInterview,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($Spec -and -not (Test-Path -LiteralPath $Spec -PathType Leaf)) { throw "Spec file '$Spec' does not exist." }
    if ($OutputFile) {
        $parent = Split-Path -Path $OutputFile -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Output folder '$parent' does not exist." }
    }
    $arguments = @('agent', 'generate', 'agent-spec')
    if ($Role) { $arguments += @('--role', $Role) }
    if ($CompanyName) { $arguments += @('--company-name', $CompanyName) }
    if ($CompanyDescription) { $arguments += @('--company-description', $CompanyDescription) }
    if ($CompanyWebsite) { $arguments += @('--company-website', $CompanyWebsite) }
    if ($Type) { $arguments += @('--type', $Type) }
    if ($Tone) { $arguments += @('--tone', $Tone) }
    if ($AgentUser) { $arguments += @('--agent-user', $AgentUser) }
    if ($PSBoundParameters.ContainsKey('MaxTopics')) { $arguments += @('--max-topics', $MaxTopics) }
    if ($GroundingContext) { $arguments += @('--grounding-context', $GroundingContext) }
    if ($PromptTemplate) { $arguments += @('--prompt-template', $PromptTemplate) }
    if ($EnrichLogs) { $arguments += @('--enrich-logs', $EnrichLogs) }
    if ($Spec) { $arguments += @('--spec', $Spec) }
    if ($OutputFile) { $arguments += @('--output-file', $OutputFile) }
    if ($ForceOverwrite) { $arguments += '--force-overwrite' }
    if ($FullInterview) { $arguments += '--full-interview' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if ($FullInterview) {
        Assert-SalesforceAgentInteractiveSession -Command 'sf agent generate agent-spec --full-interview'
        Invoke-Salesforce -FilePath 'sf' -Arguments $arguments -Interactive @commonParams
        return
    }
    $arguments += '--json'
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceAgentTemplate {
    <#
    .SYNOPSIS
    Generates an agent template from an agent in the project, to package in a managed package.

    .DESCRIPTION
    Runs sf agent generate template. It reads the agent from the project and the org it came from, and writes a template that you can put in a second-generation managed package so others can install it. It writes local files and reads the source org.

    .PARAMETER AgentFile
    Path of the agent's bot metadata file in the project. It must exist. Passed to sf as --agent-file. Required.

    .PARAMETER AgentVersion
    Version of the agent to turn into a template. Passed to sf as --agent-version. Required.

    .PARAMETER SourceOrg
    Username or alias of the org the agent was retrieved from. Passed to sf as --source-org. Required.

    .PARAMETER OutputDir
    Folder to write the template to. The CLI default is the project's default package folder. Passed to sf as --output-dir.

    .EXAMPLE
    New-SalesforceAgentTemplate -AgentFile force-app/main/default/bots/Service_Agent/Service_Agent.bot-meta.xml -AgentVersion 1 -SourceOrg dev1
    Generate a template from version 1 of the agent.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent generate template (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -AgentFile = --agent-file; -AgentVersion = --agent-version; -SourceOrg = --source-org; -OutputDir = --output-dir.
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
        [Parameter(Mandatory = $true)][string] $AgentFile,
        [Parameter(Mandatory = $true)][ValidateRange(1, 9999)][int] $AgentVersion,
        [Parameter(Mandatory = $true)][string] $SourceOrg,
        [Parameter(Mandatory = $false)][string] $OutputDir
    )
    if (-not (Test-Path -LiteralPath $AgentFile -PathType Leaf)) { throw "Agent file '$AgentFile' does not exist." }
    $arguments = @('agent', 'generate', 'template', '--agent-file', $AgentFile, '--agent-version', $AgentVersion, '--source-org', $SourceOrg)
    if ($OutputDir) { $arguments += @('--output-dir', $OutputDir) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceAgentTestSpec {
    <#
    .SYNOPSIS
    Generates an agent test spec: a YAML file that lists the test cases of an agent.

    .DESCRIPTION
    Runs sf agent generate test-spec, the first step of making an agent test. By default the CLI asks questions (the agent, then the utterances, expected topic, actions and outcome of each test case), so it is interactive: it needs a terminal, and you should run it as a plain command (an assigned or piped result hides the questions). With -FromDefinition it converts an existing test definition file instead and asks nothing. It reads the project and writes a local file; it never looks in your org. Create the test in the org with New-SalesforceAgentTest.

    .PARAMETER FromDefinition
    Path of an existing test definition file to convert into a spec, instead of answering questions. It must exist. Passed to sf as --from-definition.

    .PARAMETER OutputFile
    File to write the spec to. The CLI default is specs/<agent>-testSpec.yaml. The folder must exist. Passed to sf as --output-file.

    .PARAMETER ForceOverwrite
    Overwrite the output file without asking if it already exists. Adds --force-overwrite.

    .PARAMETER TestRunner
    The test runner that holds or runs the test. Valid values: agentforce-studio, testing-center. Passed to sf as --test-runner.

    .EXAMPLE
    New-SalesforceAgentTestSpec -OutputFile .\specs\orders-testSpec.yaml
    Answer the questions to build a spec.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent generate test-spec (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -FromDefinition = --from-definition; -OutputFile = --output-file; -ForceOverwrite = --force-overwrite; -TestRunner = --test-runner.
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
        [Parameter(Mandatory = $false)][string] $FromDefinition,
        [Parameter(Mandatory = $false)][string] $OutputFile,
        [Parameter(Mandatory = $false)][switch] $ForceOverwrite,
        [Parameter(Mandatory = $false)][ValidateSet('agentforce-studio', 'testing-center')][string] $TestRunner
    )
    if ($FromDefinition -and -not (Test-Path -LiteralPath $FromDefinition -PathType Leaf)) { throw "Definition file '$FromDefinition' does not exist." }
    if ($OutputFile) {
        $parent = Split-Path -Path $OutputFile -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Output folder '$parent' does not exist." }
    }
    $arguments = @('agent', 'generate', 'test-spec')
    if ($FromDefinition) { $arguments += @('--from-definition', $FromDefinition) }
    if ($OutputFile) { $arguments += @('--output-file', $OutputFile) }
    if ($ForceOverwrite) { $arguments += '--force-overwrite' }
    if ($TestRunner) { $arguments += @('--test-runner', $TestRunner) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    # The command has no --json. From a definition file it asks nothing, otherwise it needs the console.
    if (-not $FromDefinition) { Assert-SalesforceAgentInteractiveSession -Command 'sf agent generate test-spec' }
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments -Interactive @commonParams
}

#endregion

#region Agent tests, more

# Agent test creation, resume and the beta run-eval.

function New-SalesforceAgentTest {
    <#
    .SYNOPSIS
    Creates an agent test in an org from a local test spec file.

    .DESCRIPTION
    Runs sf agent test create. The spec is the YAML file made by New-SalesforceAgentTestSpec. With -Preview the CLI shows what it would create without creating it. Supports -WhatIf and -Confirm; it does not prompt by default.

    .PARAMETER Spec
    Path of the test spec YAML file. It must exist. Passed to sf as --spec.

    .PARAMETER ApiName
    API name of the new test. By default the CLI derives it from the spec. Passed to sf as --api-name.

    .PARAMETER Preview
    Show what would be created, without creating the test. Adds --preview.

    .PARAMETER ForceOverwrite
    Replace the test without asking if one with that API name already exists. Adds --force-overwrite.

    .PARAMETER TestRunner
    The test runner that holds or runs the test. Valid values: agentforce-studio, testing-center. Passed to sf as --test-runner.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceAgentTest -Spec .\specs\orders-testSpec.yaml -ApiName Orders_Test -TargetOrg dev1 -WhatIf
    Preview the create.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent test create (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Spec = --spec; -ApiName = --api-name; -Preview = --preview; -ForceOverwrite = --force-overwrite; -TestRunner = --test-runner; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][string] $Spec,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $ApiName,
        [Parameter(Mandatory = $false)][switch] $Preview,
        [Parameter(Mandatory = $false)][switch] $ForceOverwrite,
        [Parameter(Mandatory = $false)][ValidateSet('agentforce-studio', 'testing-center')][string] $TestRunner,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($Spec -and -not (Test-Path -LiteralPath $Spec -PathType Leaf)) { throw "Spec file '$Spec' does not exist." }
    $arguments = @('agent', 'test', 'create')
    if ($Spec) { $arguments += @('--spec', $Spec) }
    if ($ApiName) { $arguments += @('--api-name', $ApiName) }
    if ($Preview) { $arguments += '--preview' }
    if ($ForceOverwrite) { $arguments += '--force-overwrite' }
    if ($TestRunner) { $arguments += @('--test-runner', $TestRunner) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if ($Preview) { $ConfirmPreference = 'None' }
    if (-not $PSCmdlet.ShouldProcess($(if ($ApiName) { $ApiName } else { $Spec }), 'Create agent test')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Resume-SalesforceAgentTest {
    <#
    .SYNOPSIS
    Waits for an agent test run you started earlier and returns its results.

    .DESCRIPTION
    Runs sf agent test resume for the job ID that Start-SalesforceAgentTest returned, or for the most recent run with -UseMostRecent. With -ResultFormat json (the default) the results come back as an object; the other formats return the CLI text. It does not change anything in the org.

    .PARAMETER JobId
    ID of the test run (the job ID). Required unless you give -UseMostRecent. Passed to sf as --job-id. Required.

    .PARAMETER UseMostRecent
    Resume the most recent test run instead of giving -JobId. Adds --use-most-recent. Required.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the run to finish. Passed to sf as --wait.

    .PARAMETER ExtendedDetails
    Show the generated data, such as the full response of each test, in the results. Adds --verbose.

    .PARAMETER OutputDir
    Folder to write the results files to. Passed to sf as --output-dir.

    .PARAMETER ResultFormat
    Format of the results. Valid values: json, human, junit, tap. With json the result is returned as an object; with the others the CLI text is returned as it is. Passed to sf as --result-format.

    .PARAMETER TestRunner
    The test runner that holds or runs the test. Valid values: agentforce-studio, testing-center. Passed to sf as --test-runner.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Resume-SalesforceAgentTest -UseMostRecent -WaitMinutes 10 -TargetOrg dev1
    Wait for the latest run.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent test resume (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -JobId = --job-id; -UseMostRecent = --use-most-recent; -WaitMinutes = --wait; -ExtendedDetails = --verbose; -OutputDir = --output-dir; -ResultFormat = --result-format; -TestRunner = --test-runner; -TargetOrg = --target-org.
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
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ById')][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $JobId,
        [Parameter(Mandatory = $true, ParameterSetName = 'MostRecent')][switch] $UseMostRecent,
        [Parameter(Mandatory = $false)][ValidateRange(1, 1440)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails,
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][ValidateSet('json', 'human', 'junit', 'tap')][string] $ResultFormat,
        [Parameter(Mandatory = $false)][ValidateSet('agentforce-studio', 'testing-center')][string] $TestRunner,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('agent', 'test', 'resume')
    if ($PSCmdlet.ParameterSetName -eq 'MostRecent') { $arguments += '--use-most-recent' } else { $arguments += @('--job-id', $JobId) }
    if ($PSBoundParameters.ContainsKey('WaitMinutes')) { $arguments += @('--wait', $WaitMinutes) }
    if ($ExtendedDetails) { $arguments += '--verbose' }
    if ($OutputDir) { $arguments += @('--output-dir', $OutputDir) }
    if ($TestRunner) { $arguments += @('--test-runner', $TestRunner) }
    if ($ResultFormat) { $arguments += @('--result-format', $ResultFormat) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if ($ResultFormat -and $ResultFormat -ne 'json') { return Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams }
    $arguments += '--json'
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Start-SalesforceAgentEvaluation {
    <#
    .SYNOPSIS
    Runs rich evaluation tests against an agent. Beta.

    .DESCRIPTION
    Runs sf agent test run-eval, which runs the test cases of a spec file (YAML or JSON) against an agent, without a test being created in the org. This CLI command is in beta, so its flags and output can change in a later release. With -ResultFormat json the results come back as an object; the CLI default, human, and the other formats return text.

    .PARAMETER Spec
    Path of the test spec file (YAML or JSON). It must exist. Passed to sf as --spec. Required.

    .PARAMETER ApiName
    API name of the agent to test. By default the CLI reads it from the spec's subjectName. Passed to sf as --api-name.

    .PARAMETER BatchSize
    Number of tests to send per request. The CLI default is 5 and the maximum is 5. Passed to sf as --batch-size.

    .PARAMETER NoNormalize
    Do not normalize field names and shorthand references in the spec. Adds --no-normalize.

    .PARAMETER ResultFormat
    Format of the results. Valid values: json, human, junit, tap. With json the result is returned as an object; with the others the CLI text is returned as it is. Passed to sf as --result-format.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Start-SalesforceAgentEvaluation -Spec .\specs\orders-eval.yaml -ResultFormat json -TargetOrg dev1
    Run an evaluation and get the results as an object.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent test run-eval (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Spec = --spec; -ApiName = --api-name; -BatchSize = --batch-size; -NoNormalize = --no-normalize; -ResultFormat = --result-format; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][string] $Spec,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $ApiName,
        [Parameter(Mandatory = $false)][ValidateRange(1, 5)][int] $BatchSize,
        [Parameter(Mandatory = $false)][switch] $NoNormalize,
        [Parameter(Mandatory = $false)][ValidateSet('json', 'human', 'junit', 'tap')][string] $ResultFormat,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if (-not (Test-Path -LiteralPath $Spec -PathType Leaf)) { throw "Spec file '$Spec' does not exist." }
    $arguments = @('agent', 'test', 'run-eval', '--spec', $Spec)
    if ($ApiName) { $arguments += @('--api-name', $ApiName) }
    if ($PSBoundParameters.ContainsKey('BatchSize')) { $arguments += @('--batch-size', $BatchSize) }
    if ($NoNormalize) { $arguments += '--no-normalize' }
    if ($ResultFormat) { $arguments += @('--result-format', $ResultFormat) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if ($ResultFormat -ne 'json') { return Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams }
    $arguments += '--json'
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region Agent preview

# Wraps sf agent preview. The programmatic commands (start, send, end, sessions) return JSON; Invoke-SalesforceAgentPreview is the interactive conversation.

function Start-SalesforceAgentPreview {
    <#
    .SYNOPSIS
    Starts a programmatic preview session with an agent.

    .DESCRIPTION
    Runs sf agent preview start and returns the session, with the session ID that Send-SalesforceAgentPreviewMessage, Stop-SalesforceAgentPreview and Get-SalesforceAgentTrace* use. This is a programmatic preview session: each step is its own command, so a script or another tool can drive the conversation. Give -ApiName for a published agent or -AuthoringBundle for a local Agent Script agent. For a conversation you type yourself use Invoke-SalesforceAgentPreview.

    .PARAMETER ApiName
    API name of a published, activated agent. Use it or -AuthoringBundle, not both. Passed to sf as --api-name.

    .PARAMETER AuthoringBundle
    API name of a local authoring bundle (an Agent Script agent in the project). Use it or -ApiName, not both. Passed to sf as --authoring-bundle.

    .PARAMETER ContextVariables
    Context variables for the conversation as name and value pairs. Each pair is passed to sf as its own --context-variables name=value. Names are checked, and a value may not contain a double quote or line break. Cannot be used with -ContextVariablesJson. Passed to sf as --context-variables.

    .PARAMETER ContextVariablesJson
    Context variables as a JSON string, for example '{"order":"1001"}'. It must be valid JSON. Cannot be used with -ContextVariables. Passed to sf as --context-variables-json.

    .PARAMETER SimulateActions
    Simulate the agent's actions instead of running them. Only for an authoring bundle. Adds --simulate-actions.

    .PARAMETER UseLiveActions
    Run the real actions of the agent, which can change data. Only for an authoring bundle. Adds --use-live-actions.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    $session = Start-SalesforceAgentPreview -ApiName Service_Agent -TargetOrg dev1
    Start a session with a published agent.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent preview start (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ApiName = --api-name; -AuthoringBundle = --authoring-bundle; -ContextVariables = --context-variables; -ContextVariablesJson = --context-variables-json; -SimulateActions = --simulate-actions; -UseLiveActions = --use-live-actions; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $ApiName,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $AuthoringBundle,
        [Parameter(Mandatory = $false)][System.Collections.IDictionary] $ContextVariables,
        [Parameter(Mandatory = $false)][string] $ContextVariablesJson,
        [Parameter(Mandatory = $false)][switch] $SimulateActions,
        [Parameter(Mandatory = $false)][switch] $UseLiveActions,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($ContextVariables -and $ContextVariablesJson) { throw 'Use -ContextVariables or -ContextVariablesJson, not both.' }
    if ($ApiName -and $AuthoringBundle) { throw 'Use -ApiName or -AuthoringBundle, not both.' }
    if ($ContextVariablesJson) { try { $null = $ContextVariablesJson | ConvertFrom-Json -ErrorAction Stop } catch { throw "-ContextVariablesJson is not valid JSON: $($_.Exception.Message)" } }
    $contextPairs = @()
    if ($null -ne $ContextVariables) {
        foreach ($key in $ContextVariables.Keys) {
            $field = [string] $key
            if ($field -notmatch '^[A-Za-z_][A-Za-z0-9_.]*\z') { throw "'$field' is not a valid context variable name." }
            if ($ContextVariables[$key] -is [bool]) { $text = if ($ContextVariables[$key]) { 'true' } else { 'false' } } else { $text = [System.Convert]::ToString($ContextVariables[$key], [System.Globalization.CultureInfo]::InvariantCulture) }
            if ($text -match '["\r\n]') { throw "The value of '$field' contains a double quote or a line break, which the CLI cannot take safely." }
            $contextPairs += "$field=$text"
        }
    }
    if ($SimulateActions -and $UseLiveActions) { throw 'Use -SimulateActions or -UseLiveActions, not both.' }
    $arguments = @('agent', 'preview', 'start')
    if ($ApiName) { $arguments += @('--api-name', $ApiName) }
    if ($AuthoringBundle) { $arguments += @('--authoring-bundle', $AuthoringBundle) }
    foreach ($pair in $contextPairs) { $arguments += @('--context-variables', $pair) }
    if ($ContextVariablesJson) { $arguments += @('--context-variables-json', $ContextVariablesJson) }
    if ($SimulateActions) { $arguments += '--simulate-actions' }
    if ($UseLiveActions) { $arguments += '--use-live-actions' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Send-SalesforceAgentPreviewMessage {
    <#
    .SYNOPSIS
    Sends a message to a preview session and returns the agent's answer.

    .DESCRIPTION
    Runs sf agent preview send. This is a programmatic preview session: each step is its own command, so a script or another tool can drive the conversation. Give the session with -SessionId, or the agent with -ApiName or -AuthoringBundle if there is only one open session for it. The message is passed as one argument, so quotes and special characters need no escaping.

    .PARAMETER Utterance
    What to say to the agent. Passed to sf as --utterance. Required.

    .PARAMETER SessionId
    ID of the preview session, from Start-SalesforceAgentPreview. Passed to sf as --session-id.

    .PARAMETER ApiName
    API name of a published, activated agent. Use it or -AuthoringBundle, not both. Passed to sf as --api-name.

    .PARAMETER AuthoringBundle
    API name of a local authoring bundle (an Agent Script agent in the project). Use it or -ApiName, not both. Passed to sf as --authoring-bundle.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Send-SalesforceAgentPreviewMessage -SessionId $session.sessionId -Utterance 'Where is my order?' -TargetOrg dev1
    Ask the agent a question.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent preview send (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Utterance = --utterance; -SessionId = --session-id; -ApiName = --api-name; -AuthoringBundle = --authoring-bundle; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Utterance,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $SessionId,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $ApiName,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $AuthoringBundle,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($ApiName -and $AuthoringBundle) { throw 'Use -ApiName or -AuthoringBundle, not both.' }
    $arguments = @('agent', 'preview', 'send', '--utterance', $Utterance)
    if ($SessionId) { $arguments += @('--session-id', $SessionId) }
    if ($ApiName) { $arguments += @('--api-name', $ApiName) }
    if ($AuthoringBundle) { $arguments += @('--authoring-bundle', $AuthoringBundle) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Stop-SalesforceAgentPreview {
    <#
    .SYNOPSIS
    Ends a preview session and returns where its trace files are.

    .DESCRIPTION
    Runs sf agent preview end. Give the session with -SessionId, the agent with -ApiName or -AuthoringBundle, or -All to end every session. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time.

    .PARAMETER SessionId
    ID of the preview session to end. Passed to sf as --session-id.

    .PARAMETER All
    End every preview session. Adds --all.

    .PARAMETER ApiName
    API name of a published, activated agent. Use it or -AuthoringBundle, not both. Passed to sf as --api-name.

    .PARAMETER AuthoringBundle
    API name of a local authoring bundle (an Agent Script agent in the project). Use it or -ApiName, not both. Passed to sf as --authoring-bundle.

    .PARAMETER NoPrompt
    Do not ask for confirmation. Skips the PowerShell question; psfdx always passes --no-prompt to the CLI after it has confirmed.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Stop-SalesforceAgentPreview -SessionId $session.sessionId -TargetOrg dev1 -Confirm:$false
    End one session without a question.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent preview end (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -SessionId = --session-id; -All = --all; -ApiName = --api-name; -AuthoringBundle = --authoring-bundle; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $SessionId,
        [Parameter(Mandatory = $false)][switch] $All,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $ApiName,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $AuthoringBundle,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($ApiName -and $AuthoringBundle) { throw 'Use -ApiName or -AuthoringBundle, not both.' }
    $arguments = @('agent', 'preview', 'end')
    if ($SessionId) { $arguments += @('--session-id', $SessionId) }
    if ($All) { $arguments += '--all' }
    if ($ApiName) { $arguments += @('--api-name', $ApiName) }
    if ($AuthoringBundle) { $arguments += @('--authoring-bundle', $AuthoringBundle) }
    # psfdx asks first (or the caller said not to), so the CLI must not ask a second time.
    $arguments += '--no-prompt'
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    $what = 'preview session'
    if ($All) { $what = 'every preview session' } elseif ($SessionId) { $what = "preview session $SessionId" }
    if (-not $PSCmdlet.ShouldProcess($what, 'End')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceAgentPreviewSessions {
    <#
    .SYNOPSIS
    Lists the preview sessions that are still open.

    .DESCRIPTION
    Runs sf agent preview sessions and returns one object per known programmatic preview session (its ID and the agent). It reads local session records, so it needs no org.

    .EXAMPLE
    Get-SalesforceAgentPreviewSessions
    Every open session.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent preview sessions (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
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

    )
    $arguments = @('agent', 'preview', 'sessions', '--json')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Invoke-SalesforceAgentPreview {
    <#
    .SYNOPSIS
    Talks to an agent in the terminal to see how it responds.

    .DESCRIPTION
    Runs sf agent preview, the CLI version of the Preview panel in Agentforce Builder: you type utterances and read the answers. It is interactive, so it needs a terminal, and you should run it as a plain command (an assigned or piped result hides the conversation). Without -ApiName or -AuthoringBundle the CLI lets you pick an agent. For a conversation driven by a script use Start-SalesforceAgentPreview.

    .PARAMETER ApiName
    API name of a published, activated agent. Use it or -AuthoringBundle, not both. Passed to sf as --api-name.

    .PARAMETER AuthoringBundle
    API name of a local authoring bundle (an Agent Script agent in the project). Use it or -ApiName, not both. Passed to sf as --authoring-bundle.

    .PARAMETER ContextVariables
    Context variables for the conversation as name and value pairs. Each pair is passed to sf as its own --context-variables name=value. Names are checked, and a value may not contain a double quote or line break. Cannot be used with -ContextVariablesJson. Passed to sf as --context-variables.

    .PARAMETER ContextVariablesJson
    Context variables as a JSON string, for example '{"order":"1001"}'. It must be valid JSON. Cannot be used with -ContextVariables. Passed to sf as --context-variables-json.

    .PARAMETER ApexDebug
    Show Apex debug logs of the agent's actions. Adds --apex-debug.

    .PARAMETER UseLiveActions
    Run the real actions of the agent, which can change data. Only for an authoring bundle. Adds --use-live-actions.

    .PARAMETER OutputDir
    Folder to save the conversation transcript and traces to. Passed to sf as --output-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Invoke-SalesforceAgentPreview -ApiName Service_Agent -TargetOrg dev1
    Chat with a published agent.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent preview (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ApiName = --api-name; -AuthoringBundle = --authoring-bundle; -ContextVariables = --context-variables; -ContextVariablesJson = --context-variables-json; -ApexDebug = --apex-debug; -UseLiveActions = --use-live-actions; -OutputDir = --output-dir; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $ApiName,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $AuthoringBundle,
        [Parameter(Mandatory = $false)][System.Collections.IDictionary] $ContextVariables,
        [Parameter(Mandatory = $false)][string] $ContextVariablesJson,
        [Parameter(Mandatory = $false)][switch] $ApexDebug,
        [Parameter(Mandatory = $false)][switch] $UseLiveActions,
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($ContextVariables -and $ContextVariablesJson) { throw 'Use -ContextVariables or -ContextVariablesJson, not both.' }
    if ($ApiName -and $AuthoringBundle) { throw 'Use -ApiName or -AuthoringBundle, not both.' }
    if ($ContextVariablesJson) { try { $null = $ContextVariablesJson | ConvertFrom-Json -ErrorAction Stop } catch { throw "-ContextVariablesJson is not valid JSON: $($_.Exception.Message)" } }
    $contextPairs = @()
    if ($null -ne $ContextVariables) {
        foreach ($key in $ContextVariables.Keys) {
            $field = [string] $key
            if ($field -notmatch '^[A-Za-z_][A-Za-z0-9_.]*\z') { throw "'$field' is not a valid context variable name." }
            if ($ContextVariables[$key] -is [bool]) { $text = if ($ContextVariables[$key]) { 'true' } else { 'false' } } else { $text = [System.Convert]::ToString($ContextVariables[$key], [System.Globalization.CultureInfo]::InvariantCulture) }
            if ($text -match '["\r\n]') { throw "The value of '$field' contains a double quote or a line break, which the CLI cannot take safely." }
            $contextPairs += "$field=$text"
        }
    }
    $arguments = @('agent', 'preview')
    if ($ApiName) { $arguments += @('--api-name', $ApiName) }
    if ($AuthoringBundle) { $arguments += @('--authoring-bundle', $AuthoringBundle) }
    foreach ($pair in $contextPairs) { $arguments += @('--context-variables', $pair) }
    if ($ContextVariablesJson) { $arguments += @('--context-variables-json', $ContextVariablesJson) }
    if ($ApexDebug) { $arguments += '--apex-debug' }
    if ($UseLiveActions) { $arguments += '--use-live-actions' }
    if ($OutputDir) { $arguments += @('--output-dir', $OutputDir) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    Assert-SalesforceAgentInteractiveSession -Command 'sf agent preview'
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments -Interactive @commonParams
}

#endregion

#region Agent traces

# Wraps sf agent trace. Traces are local files recorded by preview sessions.

function Get-SalesforceAgentTraces {
    <#
    .SYNOPSIS
    Lists the trace files recorded during agent preview sessions.

    .DESCRIPTION
    Runs sf agent trace list. Trace files record how an agent handled each turn of a preview. It reads local files and needs no org.

    .PARAMETER Agent
    Only traces of the agent with this API name (a published agent or an authoring bundle). Passed to sf as --agent.

    .PARAMETER SessionId
    Only traces of this preview session. Passed to sf as --session-id.

    .PARAMETER Since
    Only traces recorded on or after this date. It is sent as a date in the form yyyy-MM-dd. Passed to sf as --since.

    .EXAMPLE
    Get-SalesforceAgentTraces -Agent Service_Agent -Since (Get-Date).AddDays(-7)
    Last week's traces of an agent.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent trace list (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Agent = --agent; -SessionId = --session-id; -Since = --since.
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
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Agent,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $SessionId,
        [Parameter(Mandatory = $false)][datetime] $Since
    )
    $arguments = @('agent', 'trace', 'list')
    if ($Agent) { $arguments += @('--agent', $Agent) }
    if ($SessionId) { $arguments += @('--session-id', $SessionId) }
    if ($PSBoundParameters.ContainsKey('Since')) { $arguments += @('--since', $Since.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Read-SalesforceAgentTrace {
    <#
    .SYNOPSIS
    Reads the trace of a preview session: what the agent did in each turn.

    .DESCRIPTION
    Runs sf agent trace read. -Format picks how much you get: summary (the default), detail, or raw. With -Format detail, -Dimension narrows it to one kind of question. A turn is one utterance and response, counted from 1. It reads local files and needs no org.

    .PARAMETER SessionId
    ID of the preview session to read. Passed to sf as --session-id. Required.

    .PARAMETER Format
    How much to show. Valid values: summary, detail, raw. The CLI default is summary. Passed to sf as --format.

    .PARAMETER Dimension
    What to look at with -Format detail. Valid values: actions, grounding, routing, errors. Passed to sf as --dimension.

    .PARAMETER Turn
    Only this turn, counted from 1. Passed to sf as --turn.

    .EXAMPLE
    Read-SalesforceAgentTrace -SessionId $session.sessionId -Format detail -Dimension routing
    How the agent routed each turn.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent trace read (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -SessionId = --session-id; -Format = --format; -Dimension = --dimension; -Turn = --turn.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $SessionId,
        [Parameter(Mandatory = $false)][ValidateSet('summary', 'detail', 'raw')][string] $Format,
        [Parameter(Mandatory = $false)][ValidateSet('actions', 'grounding', 'routing', 'errors')][string] $Dimension,
        [Parameter(Mandatory = $false)][ValidateRange(1, 100000)][int] $Turn
    )
    if ($Dimension -and $Format -and $Format -ne 'detail') { throw '-Dimension is for -Format detail.' }
    $arguments = @('agent', 'trace', 'read', '--session-id', $SessionId)
    if ($Format) { $arguments += @('--format', $Format) }
    if ($Dimension) { $arguments += @('--dimension', $Dimension) }
    if ($PSBoundParameters.ContainsKey('Turn')) { $arguments += @('--turn', $Turn) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceAgentTrace {
    <#
    .SYNOPSIS
    Deletes trace files of preview sessions.

    .DESCRIPTION
    Runs sf agent trace delete for the traces that match -Agent, -SessionId and -OlderThan. At least one filter is needed, so a call cannot delete every trace by accident. This cannot be undone. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time. It only touches local files.

    .PARAMETER Agent
    Only traces of the agent with this API name. Passed to sf as --agent.

    .PARAMETER SessionId
    Only traces of this preview session. Passed to sf as --session-id.

    .PARAMETER OlderThan
    Only traces older than this: a number and a unit, m (minutes), h (hours), d (days) or w (weeks), for example 7d or 24h. Passed to sf as --older-than.

    .PARAMETER NoPrompt
    Do not ask for confirmation. Skips the PowerShell question; psfdx always passes --no-prompt to the CLI after it has confirmed.

    .EXAMPLE
    Remove-SalesforceAgentTrace -Agent Service_Agent -OlderThan 30d -WhatIf
    Preview deleting a month-old traces.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent trace delete (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Agent = --agent; -SessionId = --session-id; -OlderThan = --older-than.
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
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Agent,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $SessionId,
        [Parameter(Mandatory = $false)][ValidatePattern('^[0-9]+[mhdw]\z')][string] $OlderThan,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    if (-not $Agent -and -not $SessionId -and -not $OlderThan) { throw 'Give -Agent, -SessionId or -OlderThan, so that not every trace is deleted by accident.' }
    $arguments = @('agent', 'trace', 'delete')
    if ($Agent) { $arguments += @('--agent', $Agent) }
    if ($SessionId) { $arguments += @('--session-id', $SessionId) }
    if ($OlderThan) { $arguments += @('--older-than', $OlderThan) }
    # psfdx asks first (or the caller said not to), so the CLI must not ask a second time.
    $arguments += '--no-prompt'
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    $filters = @()
    if ($Agent) { $filters += "agent $Agent" }
    if ($SessionId) { $filters += "session $SessionId" }
    if ($OlderThan) { $filters += "older than $OlderThan" }
    if (-not $PSCmdlet.ShouldProcess('trace files (' + ($filters -join ', ') + ')', 'Delete')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region Agent data libraries

# Wraps sf agent adl, the Agentforce Data Library commands.

function New-SalesforceAgentDataLibrary {
    <#
    .SYNOPSIS
    Creates an Agentforce Data Library, the knowledge an agent is grounded in.

    .DESCRIPTION
    Runs sf agent adl create. The source decides what the library holds: sfdrive (files you upload), knowledge (Salesforce Knowledge articles) or retriever (an existing retriever). Supports -WhatIf and -Confirm; it does not prompt by default. Without -WaitMinutes the CLI returns before indexing is done; check with Get-SalesforceAgentDataLibraryStatus.

    .PARAMETER Name
    Name (label) of the library. Passed to sf as --name. Required.

    .PARAMETER DeveloperName
    API name of the library. Passed to sf as --developer-name. Required.

    .PARAMETER SourceType
    Where the library's content comes from. Valid values: sfdrive, knowledge, retriever. Passed to sf as --source-type. Required.

    .PARAMETER Description
    Description of the library. Passed to sf as --description.

    .PARAMETER IndexMode
    How the content is indexed. Valid values: basic, enhanced. Passed to sf as --index-mode.

    .PARAMETER ContentFields
    Knowledge fields to index. Each is passed to sf as its own --content-fields. For a knowledge library. Passed to sf as --content-fields.

    .PARAMETER DataCategoryIds
    IDs of the data categories to include. Each is passed to sf as its own --data-category-ids. For a knowledge library. Passed to sf as --data-category-ids.

    .PARAMETER DataCategoryNames
    Names of the data categories to include. Each is passed to sf as its own --data-category-names. For a knowledge library. Passed to sf as --data-category-names.

    .PARAMETER PrimaryIndexField1
    First field of the primary index. For a retriever library. Passed to sf as --primary-index-field1.

    .PARAMETER PrimaryIndexField2
    Second field of the primary index. For a retriever library. Passed to sf as --primary-index-field2.

    .PARAMETER RetrieverId
    ID of the retriever. For a retriever library. Passed to sf as --retriever-id.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the library to be created. Passed to sf as --wait.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceAgentDataLibrary -Name 'Product Manuals' -DeveloperName Product_Manuals -SourceType sfdrive -WaitMinutes 5 -TargetOrg dev1
    Create a library for uploaded files.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent adl create (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -DeveloperName = --developer-name; -SourceType = --source-type; -Description = --description; -IndexMode = --index-mode; -ContentFields = --content-fields; -DataCategoryIds = --data-category-ids; -DataCategoryNames = --data-category-names; -PrimaryIndexField1 = --primary-index-field1; -PrimaryIndexField2 = --primary-index-field2; -RetrieverId = --retriever-id; -WaitMinutes = --wait; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $DeveloperName,
        [Parameter(Mandatory = $true)][ValidateSet('sfdrive', 'knowledge', 'retriever')][string] $SourceType,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][ValidateSet('basic', 'enhanced')][string] $IndexMode,
        [Parameter(Mandatory = $false)][string[]] $ContentFields,
        [Parameter(Mandatory = $false)][string[]] $DataCategoryIds,
        [Parameter(Mandatory = $false)][string[]] $DataCategoryNames,
        [Parameter(Mandatory = $false)][string] $PrimaryIndexField1,
        [Parameter(Mandatory = $false)][string] $PrimaryIndexField2,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $RetrieverId,
        [Parameter(Mandatory = $false)][ValidateRange(1, 1440)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('agent', 'adl', 'create', '--name', $Name, '--developer-name', $DeveloperName, '--source-type', $SourceType)
    if ($Description) { $arguments += @('--description', $Description) }
    if ($IndexMode) { $arguments += @('--index-mode', $IndexMode) }
    foreach ($item in @($ContentFields | Where-Object { $_ })) { $arguments += @('--content-fields', $item) }
    foreach ($item in @($DataCategoryIds | Where-Object { $_ })) { $arguments += @('--data-category-ids', $item) }
    foreach ($item in @($DataCategoryNames | Where-Object { $_ })) { $arguments += @('--data-category-names', $item) }
    if ($PrimaryIndexField1) { $arguments += @('--primary-index-field1', $PrimaryIndexField1) }
    if ($PrimaryIndexField2) { $arguments += @('--primary-index-field2', $PrimaryIndexField2) }
    if ($RetrieverId) { $arguments += @('--retriever-id', $RetrieverId) }
    if ($PSBoundParameters.ContainsKey('WaitMinutes')) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if (-not $PSCmdlet.ShouldProcess($DeveloperName, 'Create data library')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceAgentDataLibraries {
    <#
    .SYNOPSIS
    Lists the Agentforce Data Libraries in an org.

    .DESCRIPTION
    Runs sf agent adl list and returns one object per library. It only reads.

    .PARAMETER SourceType
    Only libraries with this source. Valid values: sfdrive, knowledge, retriever. Passed to sf as --source-type.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceAgentDataLibraries -SourceType sfdrive -TargetOrg dev1
    The file-based libraries.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent adl list (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -SourceType = --source-type; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][ValidateSet('sfdrive', 'knowledge', 'retriever')][string] $SourceType,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('agent', 'adl', 'list')
    if ($SourceType) { $arguments += @('--source-type', $SourceType) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceAgentDataLibrary {
    <#
    .SYNOPSIS
    Shows the details of one Agentforce Data Library.

    .DESCRIPTION
    Runs sf agent adl get. It only reads.

    .PARAMETER LibraryId
    ID of the data library. Passed to sf as --library-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceAgentDataLibrary -LibraryId 1JDxx0000000001 -TargetOrg dev1
    The details of one library.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent adl get (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -LibraryId = --library-id; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $LibraryId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('agent', 'adl', 'get', '--library-id', $LibraryId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceAgentDataLibraryStatus {
    <#
    .SYNOPSIS
    Shows the indexing status of a data library.

    .DESCRIPTION
    Runs sf agent adl status, which says whether the library's content is indexed and ready for an agent to use. It only reads.

    .PARAMETER LibraryId
    ID of the data library. Passed to sf as --library-id. Required.

    .PARAMETER IncludeArtifacts
    Also list the artifacts (indexes and related records) the indexing made. Adds --include-artifacts.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceAgentDataLibraryStatus -LibraryId 1JDxx0000000001 -TargetOrg dev1
    Is the library indexed yet?

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent adl status (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -LibraryId = --library-id; -IncludeArtifacts = --include-artifacts; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $LibraryId,
        [Parameter(Mandatory = $false)][switch] $IncludeArtifacts,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('agent', 'adl', 'status', '--library-id', $LibraryId)
    if ($IncludeArtifacts) { $arguments += '--include-artifacts' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Update-SalesforceAgentDataLibrary {
    <#
    .SYNOPSIS
    Changes the settings of a data library.

    .DESCRIPTION
    Runs sf agent adl update. Only the settings you give are changed. Supports -WhatIf and -Confirm; it does not prompt by default.

    .PARAMETER LibraryId
    ID of the data library. Passed to sf as --library-id. Required.

    .PARAMETER Name
    New name (label). Passed to sf as --name.

    .PARAMETER Description
    New description. Passed to sf as --description.

    .PARAMETER ContentFields
    Knowledge fields to index. Each is passed to sf as its own --content-fields. Passed to sf as --content-fields.

    .PARAMETER RetrieverId
    ID of the retriever, for a retriever library. Passed to sf as --retriever-id.

    .PARAMETER DataCategoryRule
    Turn on the data category rule of a knowledge library. Adds --data-category-rule.

    .PARAMETER RestrictToPublicArticles
    Index only public articles of a knowledge library. Adds --restrict-to-public-articles.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Update-SalesforceAgentDataLibrary -LibraryId 1JDxx0000000001 -Description 'Current manuals' -TargetOrg dev1 -WhatIf
    Preview the change.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent adl update (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -LibraryId = --library-id; -Name = --name; -Description = --description; -ContentFields = --content-fields; -RetrieverId = --retriever-id; -DataCategoryRule = --data-category-rule; -RestrictToPublicArticles = --restrict-to-public-articles; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $LibraryId,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string[]] $ContentFields,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $RetrieverId,
        [Parameter(Mandatory = $false)][switch] $DataCategoryRule,
        [Parameter(Mandatory = $false)][switch] $RestrictToPublicArticles,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('agent', 'adl', 'update', '--library-id', $LibraryId)
    if ($Name) { $arguments += @('--name', $Name) }
    if ($Description) { $arguments += @('--description', $Description) }
    foreach ($item in @($ContentFields | Where-Object { $_ })) { $arguments += @('--content-fields', $item) }
    if ($RetrieverId) { $arguments += @('--retriever-id', $RetrieverId) }
    if ($DataCategoryRule) { $arguments += '--data-category-rule' }
    if ($RestrictToPublicArticles) { $arguments += '--restrict-to-public-articles' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if (-not $PSCmdlet.ShouldProcess($LibraryId, 'Update data library')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceAgentDataLibrary {
    <#
    .SYNOPSIS
    Deletes an Agentforce Data Library.

    .DESCRIPTION
    Runs sf agent adl delete. Agents that use the library lose that knowledge, and this cannot be undone. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. The CLI command has no prompt of its own.

    .PARAMETER LibraryId
    ID of the data library. Passed to sf as --library-id. Required.

    .PARAMETER NoPrompt
    Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceAgentDataLibrary -LibraryId 1JDxx0000000001 -TargetOrg dev1 -WhatIf
    Preview the delete.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent adl delete (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -LibraryId = --library-id; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $LibraryId,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('agent', 'adl', 'delete', '--library-id', $LibraryId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    if (-not $PSCmdlet.ShouldProcess($LibraryId, 'Delete data library')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceAgentDataLibraryFiles {
    <#
    .SYNOPSIS
    Lists the files in a data library.

    .DESCRIPTION
    Runs sf agent adl file list and returns one object per file, with its status. It only reads. Use -Offset and -PageSize to page through a big library.

    .PARAMETER LibraryId
    ID of the data library. Passed to sf as --library-id. Required.

    .PARAMETER Status
    Only files with this status. Valid values: uploaded, indexing, indexed, index_failed, deleting, delete_failed. Passed to sf as --status.

    .PARAMETER Offset
    Number of files to skip, for paging. Passed to sf as --offset.

    .PARAMETER PageSize
    Number of files to return. Passed to sf as --page-size.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceAgentDataLibraryFiles -LibraryId 1JDxx0000000001 -Status index_failed -TargetOrg dev1
    The files that did not index.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent adl file list (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -LibraryId = --library-id; -Status = --status; -Offset = --offset; -PageSize = --page-size; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $LibraryId,
        [Parameter(Mandatory = $false)][ValidateSet('uploaded', 'indexing', 'indexed', 'index_failed', 'deleting', 'delete_failed')][string] $Status,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1000000)][int] $Offset,
        [Parameter(Mandatory = $false)][ValidateRange(1, 1000)][int] $PageSize,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('agent', 'adl', 'file', 'list', '--library-id', $LibraryId)
    if ($Status) { $arguments += @('--status', $Status) }
    if ($PSBoundParameters.ContainsKey('Offset')) { $arguments += @('--offset', $Offset) }
    if ($PSBoundParameters.ContainsKey('PageSize')) { $arguments += @('--page-size', $PageSize) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Add-SalesforceAgentDataLibraryFile {
    <#
    .SYNOPSIS
    Adds files to an existing data library.

    .DESCRIPTION
    Runs sf agent adl file add for each path you give. Supports -WhatIf and -Confirm; it does not prompt by default. For an SFDRIVE library that you want to wait on, use Send-SalesforceAgentDataLibraryFile.

    .PARAMETER LibraryId
    ID of the data library. Passed to sf as --library-id. Required.

    .PARAMETER Path
    Files to add. Each is passed to sf as its own --path. Each must exist. Passed to sf as --path. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Add-SalesforceAgentDataLibraryFile -LibraryId 1JDxx0000000001 -Path .\manual.pdf, .\faq.pdf -TargetOrg dev1
    Add two files.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent adl file add (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -LibraryId = --library-id; -Path = --path; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $LibraryId,
        [Parameter(Mandatory = $true)][string[]] $Path,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $paths = @($Path | Where-Object { $_ })
    if ($paths.Count -eq 0) { throw 'Give at least one -Path.' }
    foreach ($item in $paths) { if (-not (Test-Path -LiteralPath $item -PathType Leaf)) { throw "File '$item' does not exist." } }
    $arguments = @('agent', 'adl', 'file', 'add', '--library-id', $LibraryId)
    foreach ($item in $paths) { $arguments += @('--path', $item) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if (-not $PSCmdlet.ShouldProcess("$($paths.Count) file(s) in library $LibraryId", 'Add files')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceAgentDataLibraryFile {
    <#
    .SYNOPSIS
    Deletes one file from a data library.

    .DESCRIPTION
    Runs sf agent adl file delete. This cannot be undone. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. The CLI command has no prompt of its own.

    .PARAMETER LibraryId
    ID of the data library. Passed to sf as --library-id. Required.

    .PARAMETER FileId
    ID of the file to delete, from Get-SalesforceAgentDataLibraryFiles. Passed to sf as --file-id. Required.

    .PARAMETER NoPrompt
    Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceAgentDataLibraryFile -LibraryId 1JDxx0000000001 -FileId 0Pexx0000000001 -TargetOrg dev1 -WhatIf
    Preview the delete.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent adl file delete (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -LibraryId = --library-id; -FileId = --file-id; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $LibraryId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $FileId,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('agent', 'adl', 'file', 'delete', '--library-id', $LibraryId, '--file-id', $FileId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    if (-not $PSCmdlet.ShouldProcess("file $FileId in library $LibraryId", 'Delete file')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Send-SalesforceAgentDataLibraryFile {
    <#
    .SYNOPSIS
    Uploads files to an SFDRIVE data library.

    .DESCRIPTION
    Runs sf agent adl upload, which uploads local files to a library whose source is sfdrive and can wait for them to be indexed. Supports -WhatIf and -Confirm; it does not prompt by default.

    .PARAMETER LibraryId
    ID of the data library. Passed to sf as --library-id. Required.

    .PARAMETER File
    Files to upload. Each is passed to sf as its own --file. Each must exist. Passed to sf as --file. Required.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the upload and indexing. Passed to sf as --wait.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Send-SalesforceAgentDataLibraryFile -LibraryId 1JDxx0000000001 -File .\manual.pdf -WaitMinutes 10 -TargetOrg dev1
    Upload a file and wait.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent adl upload (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -LibraryId = --library-id; -File = --file; -WaitMinutes = --wait; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $LibraryId,
        [Parameter(Mandatory = $true)][string[]] $File,
        [Parameter(Mandatory = $false)][ValidateRange(1, 1440)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $files = @($File | Where-Object { $_ })
    if ($files.Count -eq 0) { throw 'Give at least one -File.' }
    foreach ($item in $files) { if (-not (Test-Path -LiteralPath $item -PathType Leaf)) { throw "File '$item' does not exist." } }
    $arguments = @('agent', 'adl', 'upload', '--library-id', $LibraryId)
    foreach ($item in $files) { $arguments += @('--file', $item) }
    if ($PSBoundParameters.ContainsKey('WaitMinutes')) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if (-not $PSCmdlet.ShouldProcess("$($files.Count) file(s) to library $LibraryId", 'Upload files')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region Agent MCP servers

# Wraps sf agent mcp, preview commands for MCP servers in the API Catalog. Their flags and output can change in a later release.

function New-SalesforceMcpServer {
    <#
    .SYNOPSIS
    Registers an MCP server in the API Catalog. Preview.

    .DESCRIPTION
    Runs sf agent mcp create, which adds a Model Context Protocol server to the org's API Catalog so agents can use its tools. This CLI command is a preview, so its flags and output can change in a later release. The server URL must be an absolute https URL, because credentials are sent to it. Supports -WhatIf and -Confirm; it does not prompt by default.

    .PARAMETER Name
    Unique name of the server. Passed to sf as --name. Required.

    .PARAMETER ServerUrl
    URL of the MCP server. It must be an absolute https:// URL. Passed to sf as --server-url. Required.

    .PARAMETER AuthType
    How the server is authenticated. Valid values: OAUTH, NO_AUTH. Passed to sf as --auth-type.

    .PARAMETER Label
    Label shown for the server. Passed to sf as --label.

    .PARAMETER Description
    Description of the server. Passed to sf as --description.

    .PARAMETER IdentityProvider
    Name of the identity provider, for OAUTH. Passed to sf as --identity-provider.

    .PARAMETER Scope
    OAuth scope, for OAUTH. Passed to sf as --scope.

    .PARAMETER ClientId
    OAuth client ID, for OAUTH. Passed to sf as --client-id.

    .PARAMETER ClientSecret
    OAuth client secret of the server, as a SecureString, for example (Read-Host -AsSecureString). It is turned into text only when the command is built, and the CLI's own verbose line hides it. Passed to sf as --client-secret.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceMcpServer -Name Orders_Mcp -ServerUrl https://mcp.example.com/orders -AuthType OAUTH -ClientId $id -ClientSecret (Read-Host -AsSecureString) -TargetOrg dev1 -WhatIf
    Preview registering a server.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent mcp create (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -ServerUrl = --server-url; -AuthType = --auth-type; -Label = --label; -Description = --description; -IdentityProvider = --identity-provider; -Scope = --scope; -ClientId = --client-id; -ClientSecret = --client-secret; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Name,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $ServerUrl,
        [Parameter(Mandatory = $false)][ValidateSet('OAUTH', 'NO_AUTH')][string] $AuthType,
        [Parameter(Mandatory = $false)][string] $Label,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $IdentityProvider,
        [Parameter(Mandatory = $false)][string] $Scope,
        [Parameter(Mandatory = $false)][string] $ClientId,
        [Parameter(Mandatory = $false)][System.Security.SecureString] $ClientSecret,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if (-not [System.Uri]::TryCreate($ServerUrl, [System.UriKind]::Absolute, [ref]$null) -or -not $ServerUrl.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) { throw "-ServerUrl must be an absolute https:// URL, because credentials are sent to it. Got '$ServerUrl'." }
    $arguments = @('agent', 'mcp', 'create', '--name', $Name, '--server-url', $ServerUrl)
    if ($AuthType) { $arguments += @('--auth-type', $AuthType) }
    if ($Label) { $arguments += @('--label', $Label) }
    if ($Description) { $arguments += @('--description', $Description) }
    if ($IdentityProvider) { $arguments += @('--identity-provider', $IdentityProvider) }
    if ($Scope) { $arguments += @('--scope', $Scope) }
    if ($ClientId) { $arguments += @('--client-id', $ClientId) }
    if ($ClientSecret) { $arguments += @('--client-secret', (ConvertTo-SalesforceAgentPlainText -Value $ClientSecret)) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if (-not $PSCmdlet.ShouldProcess($Name, 'Register MCP server')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Update-SalesforceMcpServer {
    <#
    .SYNOPSIS
    Changes an MCP server in the API Catalog. Preview.

    .DESCRIPTION
    Runs sf agent mcp update. Only the settings you give are changed. This CLI command is a preview, so its flags and output can change in a later release. A new server URL must be an absolute https URL. Supports -WhatIf and -Confirm; it does not prompt by default.

    .PARAMETER McpServerId
    ID of the MCP server in the API Catalog. Passed to sf as --mcp-server-id. Required.

    .PARAMETER ServerUrl
    New URL of the server. It must be an absolute https:// URL. Passed to sf as --server-url.

    .PARAMETER AuthType
    How the server is authenticated. Valid values: OAUTH, NO_AUTH. Passed to sf as --auth-type.

    .PARAMETER Label
    New label. Passed to sf as --label.

    .PARAMETER Description
    New description. Passed to sf as --description.

    .PARAMETER IdentityProvider
    New identity provider name. Passed to sf as --identity-provider.

    .PARAMETER Scope
    New OAuth scope. Passed to sf as --scope.

    .PARAMETER ClientId
    New OAuth client ID. Passed to sf as --client-id.

    .PARAMETER ClientSecret
    OAuth client secret of the server, as a SecureString, for example (Read-Host -AsSecureString). It is turned into text only when the command is built, and the CLI's own verbose line hides it. Passed to sf as --client-secret.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Update-SalesforceMcpServer -McpServerId 0Xxxx0000000001 -Description 'Orders tools' -TargetOrg dev1 -WhatIf
    Preview the change.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent mcp update (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -McpServerId = --mcp-server-id; -ServerUrl = --server-url; -AuthType = --auth-type; -Label = --label; -Description = --description; -IdentityProvider = --identity-provider; -Scope = --scope; -ClientId = --client-id; -ClientSecret = --client-secret; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $McpServerId,
        [Parameter(Mandatory = $false)][string] $ServerUrl,
        [Parameter(Mandatory = $false)][ValidateSet('OAUTH', 'NO_AUTH')][string] $AuthType,
        [Parameter(Mandatory = $false)][string] $Label,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $IdentityProvider,
        [Parameter(Mandatory = $false)][string] $Scope,
        [Parameter(Mandatory = $false)][string] $ClientId,
        [Parameter(Mandatory = $false)][System.Security.SecureString] $ClientSecret,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($ServerUrl -and (-not [System.Uri]::TryCreate($ServerUrl, [System.UriKind]::Absolute, [ref]$null) -or -not $ServerUrl.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase))) { throw "-ServerUrl must be an absolute https:// URL, because credentials are sent to it. Got '$ServerUrl'." }
    $arguments = @('agent', 'mcp', 'update', '--mcp-server-id', $McpServerId)
    if ($ServerUrl) { $arguments += @('--server-url', $ServerUrl) }
    if ($AuthType) { $arguments += @('--auth-type', $AuthType) }
    if ($Label) { $arguments += @('--label', $Label) }
    if ($Description) { $arguments += @('--description', $Description) }
    if ($IdentityProvider) { $arguments += @('--identity-provider', $IdentityProvider) }
    if ($Scope) { $arguments += @('--scope', $Scope) }
    if ($ClientId) { $arguments += @('--client-id', $ClientId) }
    if ($ClientSecret) { $arguments += @('--client-secret', (ConvertTo-SalesforceAgentPlainText -Value $ClientSecret)) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if (-not $PSCmdlet.ShouldProcess($McpServerId, 'Update MCP server')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceMcpServer {
    <#
    .SYNOPSIS
    Deletes an MCP server from the API Catalog. Preview.

    .DESCRIPTION
    Runs sf agent mcp delete. Agents that use the server lose its tools, and this cannot be undone. This CLI command is a preview, so its flags and output can change in a later release. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time.

    .PARAMETER McpServerId
    ID of the MCP server in the API Catalog. Passed to sf as --mcp-server-id. Required.

    .PARAMETER NoPrompt
    Do not ask for confirmation. Skips the PowerShell question; psfdx always passes --no-prompt to the CLI after it has confirmed.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceMcpServer -McpServerId 0Xxxx0000000001 -TargetOrg dev1 -WhatIf
    Preview the delete.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent mcp delete (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -McpServerId = --mcp-server-id; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $McpServerId,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('agent', 'mcp', 'delete', '--mcp-server-id', $McpServerId)
    # psfdx asks first (or the caller said not to), so the CLI must not ask a second time.
    $arguments += '--no-prompt'
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    if (-not $PSCmdlet.ShouldProcess($McpServerId, 'Delete MCP server')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceMcpServer {
    <#
    .SYNOPSIS
    Shows one MCP server of the API Catalog. Preview.

    .DESCRIPTION
    Runs sf agent mcp get. This CLI command is a preview, so its flags and output can change in a later release. It only reads.

    .PARAMETER McpServerId
    ID of the MCP server in the API Catalog. Passed to sf as --mcp-server-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceMcpServer -McpServerId 0Xxxx0000000001 -TargetOrg dev1
    The details of one server.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent mcp get (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -McpServerId = --mcp-server-id; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $McpServerId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('agent', 'mcp', 'get', '--mcp-server-id', $McpServerId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceMcpServers {
    <#
    .SYNOPSIS
    Lists the MCP servers of the API Catalog. Preview.

    .DESCRIPTION
    Runs sf agent mcp list and returns one object per server. This CLI command is a preview, so its flags and output can change in a later release. It only reads.

    .PARAMETER Label
    Only servers with this label. Passed to sf as --label.

    .PARAMETER Status
    Only servers with this status. Valid values: ACTIVE, DISCONNECTED. Passed to sf as --status.

    .PARAMETER Type
    Only servers of this type. Valid value: EXTERNAL. Passed to sf as --type.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceMcpServers -Status ACTIVE -TargetOrg dev1
    The servers that are connected.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent mcp list (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Label = --label; -Status = --status; -Type = --type; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][string] $Label,
        [Parameter(Mandatory = $false)][ValidateSet('ACTIVE', 'DISCONNECTED')][string] $Status,
        [Parameter(Mandatory = $false)][ValidateSet('EXTERNAL')][string] $Type,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('agent', 'mcp', 'list')
    if ($Label) { $arguments += @('--label', $Label) }
    if ($Status) { $arguments += @('--status', $Status) }
    if ($Type) { $arguments += @('--type', $Type) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceMcpAssets {
    <#
    .SYNOPSIS
    Lists the assets (tools, prompts and resources) of an MCP server in the catalog. Preview.

    .DESCRIPTION
    Runs sf agent mcp asset list: the assets that are allowed in the catalog. Use Get-SalesforceMcpServerLiveAssets for what the server offers right now. This CLI command is a preview, so its flags and output can change in a later release. It only reads.

    .PARAMETER McpServerId
    ID of the MCP server in the API Catalog. Passed to sf as --mcp-server-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceMcpAssets -McpServerId 0Xxxx0000000001 -TargetOrg dev1
    The allowed assets of a server.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent mcp asset list (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -McpServerId = --mcp-server-id; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $McpServerId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('agent', 'mcp', 'asset', 'list', '--mcp-server-id', $McpServerId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceMcpServerLiveAssets {
    <#
    .SYNOPSIS
    Asks an MCP server for the assets it offers right now. Preview.

    .DESCRIPTION
    Runs sf agent mcp fetch, which connects to the server and returns the tools, prompts and resources it advertises. Compare it with Get-SalesforceMcpAssets, then change the allowed set with Set-SalesforceMcpAssets. This CLI command is a preview, so its flags and output can change in a later release. It does not change the catalog.

    .PARAMETER McpServerId
    ID of the MCP server in the API Catalog. Passed to sf as --mcp-server-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceMcpServerLiveAssets -McpServerId 0Xxxx0000000001 -TargetOrg dev1
    What the server offers now.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent mcp fetch (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -McpServerId = --mcp-server-id; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $McpServerId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('agent', 'mcp', 'fetch', '--mcp-server-id', $McpServerId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Set-SalesforceMcpAssets {
    <#
    .SYNOPSIS
    Replaces the allowed assets of an MCP server in the catalog. Preview.

    .DESCRIPTION
    Runs sf agent mcp asset replace. The set you give replaces the allowed set, so an asset that is not in it is no longer allowed. Give the set as a JSON string in -Assets, as an object or array in -AssetList (psfdx converts it to JSON), or as a JSON file in -AssetsFile. This CLI command is a preview, so its flags and output can change in a later release. Supports -WhatIf and -Confirm; it does not prompt by default.

    .PARAMETER McpServerId
    ID of the MCP server in the API Catalog. Passed to sf as --mcp-server-id. Required.

    .PARAMETER Assets
    The allowed assets as a JSON string. It must be valid JSON. Use one of -Assets, -AssetList and -AssetsFile. Passed to sf as --assets.

    .PARAMETER AssetList
    The allowed assets as a PowerShell object or array, sent as JSON. Use one of -Assets, -AssetList and -AssetsFile. Sent to sf as --assets.

    .PARAMETER AssetsFile
    Path of a JSON file with the allowed assets. It must exist. Use one of -Assets, -AssetList and -AssetsFile. Passed to sf as --assets-file.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Set-SalesforceMcpAssets -McpServerId 0Xxxx0000000001 -AssetsFile .\assets.json -TargetOrg dev1 -WhatIf
    Preview replacing the set.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf agent mcp asset replace (plugin @salesforce/plugin-agent)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -McpServerId = --mcp-server-id; -Assets = --assets; -AssetsFile = --assets-file; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z')][string] $McpServerId,
        [Parameter(Mandatory = $false)][string] $Assets,
        [Parameter(Mandatory = $false)][object] $AssetList,
        [Parameter(Mandatory = $false)][string] $AssetsFile,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $sourceCount = 0
    if ($Assets) { $sourceCount++ }
    if ($PSBoundParameters.ContainsKey('AssetList')) { $sourceCount++ }
    if ($AssetsFile) { $sourceCount++ }
    if ($sourceCount -ne 1) { throw 'Give exactly one of -Assets, -AssetList and -AssetsFile.' }
    $json = $Assets
    if ($PSBoundParameters.ContainsKey('AssetList')) { $json = ConvertTo-Json -InputObject $AssetList -Depth 10 -Compress }
    if ($json) { try { $null = $json | ConvertFrom-Json -ErrorAction Stop } catch { throw "The assets are not valid JSON: $($_.Exception.Message)" } }
    if ($AssetsFile -and -not (Test-Path -LiteralPath $AssetsFile -PathType Leaf)) { throw "Assets file '$AssetsFile' does not exist." }
    $arguments = @('agent', 'mcp', 'asset', 'replace', '--mcp-server-id', $McpServerId)
    if ($json) { $arguments += @('--assets', $json) }
    if ($AssetsFile) { $arguments += @('--assets-file', $AssetsFile) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    Assert-SalesforceAgentPlugin -CommonParams $commonParams
    if (-not $PSCmdlet.ShouldProcess($McpServerId, 'Replace the allowed assets')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion
