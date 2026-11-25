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

#region Private helpers

# Copies of four small private helpers of psfdx-metadata, which the DevOps Center cmdlets also call. psfdx-metadata keeps its own copies for the deploy
# and schema generator cmdlets; tests/Repository.Tests.ps1 fails if a copy differs from the one in psfdx-metadata.

function Test-SalesforceDeployWaitParams {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][bool] $HasWait,
        [Parameter(Mandatory = $false)][bool] $Async
    )
    if ($HasWait -and $Async) {
        throw "Specify only one of -Wait or -Async."
    }
}

function Test-SalesforceDeployResultOptions {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][bool] $ConciseResults,
        [Parameter(Mandatory = $false)][bool] $DetailedResults
    )
    if ($ConciseResults -and $DetailedResults) {
        throw "Specify only one of -ConciseResults or -DetailedResults."
    }
}

function Test-SalesforceValidDeployWait {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][int] $Wait
    )
    if ($Wait -lt 0) {
        throw "-Wait must be zero or greater (minutes)."
    }
}

function Assert-SalesforceInteractiveSession {
    # Private: stops with a clear message when the session cannot ask questions, so an interactive generator does not wait for input that never comes.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Command
    )
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw "$Command asks questions, so it needs a terminal. Run it in an interactive PowerShell session, not in a script, job or pipeline whose input or output is redirected."
    }
}

#endregion

#region DevOps Center pipeline deploys (beta)

function Get-SalesforcePipelineJobArguments {
    # Private: the --job-id / --use-most-recent choice of the sf project deploy pipeline commands.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $JobId,
        [Parameter(Mandatory = $false)][switch] $UseMostRecent
    )
    if ($JobId -and $UseMostRecent) { throw "Specify only one of -JobId or -UseMostRecent." }
    if (-not $JobId -and -not $UseMostRecent) { throw "Specify -JobId or -UseMostRecent." }
    if ($JobId) {
        if ($JobId -notmatch '^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?\z') {
            throw "Job ID '$JobId' is not a valid pipeline deploy job ID. Expected a 15 or 18 character ID."
        }
        return @('--job-id', $JobId)
    }
    return @('--use-most-recent')
}

function Get-SalesforcePipelineStartArguments {
    # Private: the arguments that sf project deploy pipeline start and validate share. Returns the arguments after the command words.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $DevOpsCenterUsername,
        [Parameter(Mandatory = $true)][string] $DevOpsCenterProjectName,
        [Parameter(Mandatory = $true)][string] $BranchName,
        [Parameter(Mandatory = $false)][string] $BundleVersionName,
        [Parameter(Mandatory = $false)][switch] $DeployAll,
        [Parameter(Mandatory = $false)][string] $TestLevel,
        [Parameter(Mandatory = $false)][string[]] $Tests,
        [Parameter(Mandatory = $false)][bool] $HasWait,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults,
        [Parameter(Mandatory = $false)][hashtable] $CommonParams = @{}
    )
    Test-SalesforceDeployResultOptions -ConciseResults ([bool]$ConciseResults) -DetailedResults ([bool]$DetailedResults)
    Test-SalesforceDeployWaitParams -HasWait $HasWait -Async ([bool]$Async)
    if ($HasWait) { Test-SalesforceValidDeployWait -Wait $Wait }
    $arguments = @('--devops-center-username', $DevOpsCenterUsername, '--devops-center-project-name', $DevOpsCenterProjectName, '--branch-name', $BranchName)
    if ($BundleVersionName) { $arguments += @('--bundle-version-name', $BundleVersionName) }
    if ($DeployAll) { $arguments += '--deploy-all' }
    if ($TestLevel) {
        $arguments += Get-SalesforceApexCliTestArguments @CommonParams -TestLevel $TestLevel -Tests $Tests
    } elseif (@($Tests | Where-Object { $_ }).Count -gt 0) {
        throw "-Tests needs -TestLevel SpecificTests."
    }
    if ($HasWait) { $arguments += @('--wait', $Wait) }
    if ($Async) { $arguments += '--async' }
    if ($ConciseResults) { $arguments += '--concise' }
    if ($DetailedResults) { $arguments += '--verbose' }
    return $arguments
}

function Start-SalesforcePipelineDeploy {
    <#
    .SYNOPSIS
    Deploys the changes of a branch to the org of a DevOps Center pipeline stage (beta).

    .DESCRIPTION
    Runs sf project deploy pipeline start, a beta command of the DevOps Center plugin. It needs a DevOps Center org that you are logged in to (-DevOpsCenterUsername) and the name of the DevOps Center project. Because the command is beta, its name, flags and result can change in a later CLI release. Asks for confirmation and supports -WhatIf. Returns the CLI result, which holds the job ID that Get-SalesforcePipelineDeployStatus, Resume-SalesforcePipelineDeploy and Start-SalesforcePipelineQuickDeploy take.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf project deploy pipeline start (plugin @salesforce/plugin-devops-center, beta)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -DevOpsCenterUsername = --devops-center-username; -DevOpsCenterProjectName = --devops-center-project-name; -BranchName = --branch-name; -BundleVersionName = --bundle-version-name; -DeployAll = --deploy-all; -TestLevel = --test-level; -Tests = --tests; -Wait = --wait; -Async = --async; -ConciseResults = --concise; -DetailedResults = --verbose.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER DevOpsCenterUsername
    Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.

    .PARAMETER DevOpsCenterProjectName
    Name of the DevOps Center project. Passed as --devops-center-project-name. Required.

    .PARAMETER BranchName
    Branch whose changes are deployed to the pipeline stage. Passed as --branch-name. Required.

    .PARAMETER BundleVersionName
    Version name of the bundle to deploy. Passed as --bundle-version-name.

    .PARAMETER DeployAll
    Deploy all the metadata in the branch, not only the changes. Adds --deploy-all.

    .PARAMETER TestLevel
    Apex testing level. Passed to sf as --test-level. Valid values: NoTests, SpecificTests, TestsInOrg, TestsInOrgAndPackages. Value mapping to the CLI: NoTests = NoTestRun, SpecificTests = RunSpecifiedTests, TestsInOrg = RunLocalTests, TestsInOrgAndPackages = RunAllTestsInOrg. The CLI default applies when omitted.

    .PARAMETER Tests
    Apex test classes to run with -TestLevel SpecificTests. Passed as one --tests per name.

    .PARAMETER Wait
    Number of minutes to wait for the deployment to finish. Passed as --wait. Cannot be used with -Async.

    .PARAMETER Async
    Start the deployment and return without waiting. Adds --async.

    .PARAMETER ConciseResults
    Show concise output of the result. Adds --concise.

    .PARAMETER DetailedResults
    Show verbose output of the result. Adds --verbose.

    .EXAMPLE
    Start-SalesforcePipelineDeploy -DevOpsCenterUsername doc-org -DevOpsCenterProjectName "Sales App" -BranchName feature/new-flow -TestLevel TestsInOrg -WhatIf
    Preview deploying a branch with all local tests.

    .NOTES
    This runs a beta Salesforce CLI command that needs a DevOps Center org. Beta commands can change or be removed without notice; psfdx does not promise they stay stable.
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string] $DevOpsCenterUsername,
        [Parameter(Mandatory = $true)][string] $DevOpsCenterProjectName,
        [Parameter(Mandatory = $true)][string] $BranchName,
        [Parameter(Mandatory = $false)][string] $BundleVersionName,
        [Parameter(Mandatory = $false)][switch] $DeployAll,
        [Parameter(Mandatory = $false)][ValidateSet('NoTests', 'SpecificTests', 'TestsInOrg', 'TestsInOrgAndPackages')][string] $TestLevel,
        [Parameter(Mandatory = $false)][string[]] $Tests,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults
    )

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $arguments = @('project', 'deploy', 'pipeline', 'start')
    $arguments += Get-SalesforcePipelineStartArguments -DevOpsCenterUsername $DevOpsCenterUsername -DevOpsCenterProjectName $DevOpsCenterProjectName -BranchName $BranchName -BundleVersionName $BundleVersionName -DeployAll:$DeployAll -TestLevel $TestLevel -Tests $Tests -HasWait ($PSBoundParameters.ContainsKey('Wait')) -Wait $Wait -Async:$Async -ConciseResults:$ConciseResults -DetailedResults:$DetailedResults -CommonParams $commonParams
    $arguments += '--json'
    if ($PSCmdlet.ShouldProcess("branch $BranchName of $DevOpsCenterProjectName", 'Deploy to the pipeline stage')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Test-SalesforcePipelineDeploy {
    <#
    .SYNOPSIS
    Validates a deployment of a branch to the org of a DevOps Center pipeline stage, without deploying it (beta).

    .DESCRIPTION
    Runs sf project deploy pipeline validate, a beta command of the DevOps Center plugin. Nothing is deployed; a passing validation can be released with Start-SalesforcePipelineQuickDeploy. It needs a DevOps Center org that you are logged in to. Because the command is beta, its name, flags and result can change in a later CLI release.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf project deploy pipeline validate (plugin @salesforce/plugin-devops-center, beta)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -DevOpsCenterUsername = --devops-center-username; -DevOpsCenterProjectName = --devops-center-project-name; -BranchName = --branch-name; -BundleVersionName = --bundle-version-name; -DeployAll = --deploy-all; -TestLevel = --test-level; -Tests = --tests; -Wait = --wait; -Async = --async; -ConciseResults = --concise; -DetailedResults = --verbose.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER DevOpsCenterUsername
    Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.

    .PARAMETER DevOpsCenterProjectName
    Name of the DevOps Center project. Passed as --devops-center-project-name. Required.

    .PARAMETER BranchName
    Branch whose changes are validated. Passed as --branch-name. Required.

    .PARAMETER BundleVersionName
    Version name of the bundle to validate. Passed as --bundle-version-name.

    .PARAMETER DeployAll
    Validate all the metadata in the branch, not only the changes. Adds --deploy-all.

    .PARAMETER TestLevel
    Apex testing level. Passed to sf as --test-level. Valid values: NoTests, SpecificTests, TestsInOrg, TestsInOrgAndPackages. Value mapping to the CLI: NoTests = NoTestRun, SpecificTests = RunSpecifiedTests, TestsInOrg = RunLocalTests, TestsInOrgAndPackages = RunAllTestsInOrg. The CLI default applies when omitted.

    .PARAMETER Tests
    Apex test classes to run with -TestLevel SpecificTests. Passed as one --tests per name.

    .PARAMETER Wait
    Number of minutes to wait for the validation to finish. Passed as --wait. Cannot be used with -Async.

    .PARAMETER Async
    Start the validation and return without waiting. Adds --async.

    .PARAMETER ConciseResults
    Show concise output of the result. Adds --concise.

    .PARAMETER DetailedResults
    Show verbose output of the result. Adds --verbose.

    .EXAMPLE
    Test-SalesforcePipelineDeploy -DevOpsCenterUsername doc-org -DevOpsCenterProjectName "Sales App" -BranchName main -TestLevel TestsInOrg -Wait 30
    Validate a branch with all local tests.

    .NOTES
    This runs a beta Salesforce CLI command that needs a DevOps Center org. Beta commands can change or be removed without notice; psfdx does not promise they stay stable.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $DevOpsCenterUsername,
        [Parameter(Mandatory = $true)][string] $DevOpsCenterProjectName,
        [Parameter(Mandatory = $true)][string] $BranchName,
        [Parameter(Mandatory = $false)][string] $BundleVersionName,
        [Parameter(Mandatory = $false)][switch] $DeployAll,
        [Parameter(Mandatory = $false)][ValidateSet('NoTests', 'SpecificTests', 'TestsInOrg', 'TestsInOrgAndPackages')][string] $TestLevel,
        [Parameter(Mandatory = $false)][string[]] $Tests,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults
    )

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $arguments = @('project', 'deploy', 'pipeline', 'validate')
    $arguments += Get-SalesforcePipelineStartArguments -DevOpsCenterUsername $DevOpsCenterUsername -DevOpsCenterProjectName $DevOpsCenterProjectName -BranchName $BranchName -BundleVersionName $BundleVersionName -DeployAll:$DeployAll -TestLevel $TestLevel -Tests $Tests -HasWait ($PSBoundParameters.ContainsKey('Wait')) -Wait $Wait -Async:$Async -ConciseResults:$ConciseResults -DetailedResults:$DetailedResults -CommonParams $commonParams
    $arguments += '--json'
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Start-SalesforcePipelineQuickDeploy {
    <#
    .SYNOPSIS
    Deploys a validated pipeline deployment without running the tests again (beta).

    .DESCRIPTION
    Runs sf project deploy pipeline quick, a beta command of the DevOps Center plugin, for the job ID of a validation made with Test-SalesforcePipelineDeploy (or the most recent one with -UseMostRecent). Because the command is beta, its name, flags and result can change in a later CLI release. Asks for confirmation and supports -WhatIf.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf project deploy pipeline quick (plugin @salesforce/plugin-devops-center, beta)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -DevOpsCenterUsername = --devops-center-username; -JobId = --job-id; -UseMostRecent = --use-most-recent; -Wait = --wait; -Async = --async; -ConciseResults = --concise; -DetailedResults = --verbose.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER DevOpsCenterUsername
    Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.

    .PARAMETER JobId
    Job ID of the validated deployment. A 15 or 18 character ID. Passed as --job-id.

    .PARAMETER UseMostRecent
    Use the validation the CLI ran most recently. Use instead of -JobId. Adds --use-most-recent.

    .PARAMETER Wait
    Number of minutes to wait for the deployment to finish. Passed as --wait. Cannot be used with -Async.

    .PARAMETER Async
    Start the deployment and return without waiting. Adds --async.

    .PARAMETER ConciseResults
    Show concise output of the result. Adds --concise.

    .PARAMETER DetailedResults
    Show verbose output of the result. Adds --verbose.

    .EXAMPLE
    Start-SalesforcePipelineQuickDeploy -DevOpsCenterUsername doc-org -UseMostRecent -WhatIf
    Preview the quick deploy of the last validation.

    .NOTES
    This runs a beta Salesforce CLI command that needs a DevOps Center org. Beta commands can change or be removed without notice; psfdx does not promise they stay stable.
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string] $DevOpsCenterUsername,
        [Parameter(Mandatory = $false)][string] $JobId,
        [Parameter(Mandatory = $false)][switch] $UseMostRecent,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults
    )

    $jobParams = Get-SalesforcePipelineJobArguments -JobId $JobId -UseMostRecent:$UseMostRecent
    Test-SalesforceDeployResultOptions -ConciseResults ([bool]$ConciseResults) -DetailedResults ([bool]$DetailedResults)
    Test-SalesforceDeployWaitParams -HasWait ($PSBoundParameters.ContainsKey('Wait')) -Async ([bool]$Async)
    if ($PSBoundParameters.ContainsKey('Wait')) { Test-SalesforceValidDeployWait -Wait $Wait }

    $arguments = @('project', 'deploy', 'pipeline', 'quick', '--devops-center-username', $DevOpsCenterUsername) + $jobParams
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    if ($Async) { $arguments += '--async' }
    if ($ConciseResults) { $arguments += '--concise' }
    if ($DetailedResults) { $arguments += '--verbose' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $target = if ($JobId) { $JobId } else { 'most recent validated pipeline deployment' }
    if ($PSCmdlet.ShouldProcess($target, 'Quick deploy validated pipeline deployment')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Get-SalesforcePipelineDeployStatus {
    <#
    .SYNOPSIS
    Reports the status of a DevOps Center pipeline deployment (beta).

    .DESCRIPTION
    Runs sf project deploy pipeline report, a beta command of the DevOps Center plugin, for a job ID or for the most recent deployment with -UseMostRecent. Read-only. Because the command is beta, its name, flags and result can change in a later CLI release.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf project deploy pipeline report (plugin @salesforce/plugin-devops-center, beta)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -DevOpsCenterUsername = --devops-center-username; -JobId = --job-id; -UseMostRecent = --use-most-recent.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER DevOpsCenterUsername
    Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.

    .PARAMETER JobId
    Job ID of the pipeline deployment. A 15 or 18 character ID. Passed as --job-id.

    .PARAMETER UseMostRecent
    Report on the deployment the CLI started most recently. Use instead of -JobId. Adds --use-most-recent.

    .EXAMPLE
    Get-SalesforcePipelineDeployStatus -DevOpsCenterUsername doc-org -UseMostRecent
    Status of the last pipeline deployment.

    .NOTES
    This runs a beta Salesforce CLI command that needs a DevOps Center org. Beta commands can change or be removed without notice; psfdx does not promise they stay stable.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $DevOpsCenterUsername,
        [Parameter(Mandatory = $false)][string] $JobId,
        [Parameter(Mandatory = $false)][switch] $UseMostRecent
    )

    $jobParams = Get-SalesforcePipelineJobArguments -JobId $JobId -UseMostRecent:$UseMostRecent
    $arguments = @('project', 'deploy', 'pipeline', 'report', '--devops-center-username', $DevOpsCenterUsername) + $jobParams
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Resume-SalesforcePipelineDeploy {
    <#
    .SYNOPSIS
    Resumes watching a DevOps Center pipeline deployment that is still running (beta).

    .DESCRIPTION
    Runs sf project deploy pipeline resume, a beta command of the DevOps Center plugin, for a job ID or for the most recent deployment with -UseMostRecent. Because the command is beta, its name, flags and result can change in a later CLI release.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf project deploy pipeline resume (plugin @salesforce/plugin-devops-center, beta)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -DevOpsCenterUsername = --devops-center-username; -JobId = --job-id; -UseMostRecent = --use-most-recent; -Wait = --wait; -ConciseResults = --concise; -DetailedResults = --verbose.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER DevOpsCenterUsername
    Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.

    .PARAMETER JobId
    Job ID of the pipeline deployment. A 15 or 18 character ID. Passed as --job-id.

    .PARAMETER UseMostRecent
    Resume the deployment the CLI started most recently. Use instead of -JobId. Adds --use-most-recent.

    .PARAMETER Wait
    Number of minutes to wait for the deployment to finish. Passed as --wait.

    .PARAMETER ConciseResults
    Show concise output of the result. Adds --concise.

    .PARAMETER DetailedResults
    Show verbose output of the result. Adds --verbose.

    .EXAMPLE
    Resume-SalesforcePipelineDeploy -DevOpsCenterUsername doc-org -UseMostRecent -Wait 10
    Wait up to ten more minutes for the last pipeline deployment.

    .NOTES
    This runs a beta Salesforce CLI command that needs a DevOps Center org. Beta commands can change or be removed without notice; psfdx does not promise they stay stable.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $DevOpsCenterUsername,
        [Parameter(Mandatory = $false)][string] $JobId,
        [Parameter(Mandatory = $false)][switch] $UseMostRecent,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults
    )

    $jobParams = Get-SalesforcePipelineJobArguments -JobId $JobId -UseMostRecent:$UseMostRecent
    Test-SalesforceDeployResultOptions -ConciseResults ([bool]$ConciseResults) -DetailedResults ([bool]$DetailedResults)
    if ($PSBoundParameters.ContainsKey('Wait')) { Test-SalesforceValidDeployWait -Wait $Wait }

    $arguments = @('project', 'deploy', 'pipeline', 'resume', '--devops-center-username', $DevOpsCenterUsername) + $jobParams
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    if ($ConciseResults) { $arguments += '--concise' }
    if ($DetailedResults) { $arguments += '--verbose' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region DevOps Center

# Wraps sf devops, the DevOps Center commands: projects, work items, pipelines and their stages, branches and environments, and promotion. They need a DevOps Center org.
# The beta deploy commands of sf project deploy pipeline are in the region above.

function Get-SalesforceDevOpsProject {
    <#
    .SYNOPSIS
    Lists the DevOps Center projects of an org.

    .DESCRIPTION
    Runs sf devops project list. Returns the DevOps Center projects with their IDs, which the work item, pipeline and promotion cmdlets take. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops project list (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDevOpsProject -TargetOrg devops-org
    List the projects.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'project', 'list')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceDevOpsProject {
    <#
    .SYNOPSIS
    Creates a DevOps Center project.

    .DESCRIPTION
    Runs sf devops project create. Creates a project with a name and an optional description in the DevOps Center org. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops project create (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Name = --name; -Description = --description; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Name
    Name of the project. Passed to sf as --name. Required.

    .PARAMETER Description
    Description of the project. Passed to sf as --description.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceDevOpsProject -Name 'Sales App' -Description 'Quarterly releases' -TargetOrg devops-org -WhatIf
    Preview creating a project.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'project', 'create', '--name', $Name)
    if ($Description) { $arguments += @('--description', $Description) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($Name, 'Create DevOps Center project')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Update-SalesforceDevOpsProject {
    <#
    .SYNOPSIS
    Renames, describes or activates or deactivates a DevOps Center project.

    .DESCRIPTION
    Runs sf devops project update. Give at least one of -Name, -Description and -IsActive. Use -IsActive to activate the project and -IsActive:$false to deactivate it. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops project update (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -ProjectId = --project-id; -Name = --name; -Description = --description; -IsActive = --is-active; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER ProjectId
    ID of the project to update. Passed to sf as --project-id. Required.

    .PARAMETER Name
    New name of the project. Passed to sf as --name.

    .PARAMETER Description
    New description of the project. Passed to sf as --description.

    .PARAMETER IsActive
    Set whether the project is active. Adds --is-active, or --no-is-active when you write -IsActive:$false. Passed to sf as --is-active.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Update-SalesforceDevOpsProject -ProjectId 0Hn000000000001 -IsActive:$false -TargetOrg devops-org -WhatIf
    Preview deactivating a project.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $ProjectId,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][switch] $IsActive,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if (-not $Name -and -not $Description -and -not $PSBoundParameters.ContainsKey('IsActive')) { throw 'Give at least one of -Name, -Description and -IsActive.' }
    $arguments = @('devops', 'project', 'update', '--project-id', $ProjectId)
    if ($Name) { $arguments += @('--name', $Name) }
    if ($Description) { $arguments += @('--description', $Description) }
    if ($PSBoundParameters.ContainsKey('IsActive')) { if ($IsActive) { $arguments += '--is-active' } else { $arguments += '--no-is-active' } }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($ProjectId, 'Update DevOps Center project')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDevOpsWorkItem {
    <#
    .SYNOPSIS
    Lists the work items of a DevOps Center project.

    .DESCRIPTION
    Runs sf devops work-item list. Each work item shows the branch, environment and repository details needed to check it out and promote it, and its ID, which the promotion cmdlets take. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops work-item list (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -ProjectId = --project-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER ProjectId
    ID of the project, from Get-SalesforceDevOpsProject. Passed to sf as --project-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDevOpsWorkItem -ProjectId 1Qg000000000001 -TargetOrg devops-org
    The work items of a project.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $ProjectId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'work-item', 'list', '--project-id', $ProjectId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceDevOpsWorkItem {
    <#
    .SYNOPSIS
    Creates a work item in a DevOps Center project.

    .DESCRIPTION
    Runs sf devops work-item create. Creates a work item with a subject and an optional description. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops work-item create (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -ProjectId = --project-id; -Subject = --subject; -Description = --description; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER ProjectId
    ID of the project to create the work item in. Passed to sf as --project-id. Required.

    .PARAMETER Subject
    Subject (title) of the work item. Passed to sf as --subject. Required.

    .PARAMETER Description
    Description of the work item. Passed to sf as --description.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceDevOpsWorkItem -ProjectId 1Qg000000000001 -Subject 'Add invoice flow' -TargetOrg devops-org
    Create a work item.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $ProjectId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Subject,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'work-item', 'create', '--project-id', $ProjectId, '--subject', $Subject)
    if ($Description) { $arguments += @('--description', $Description) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($Subject, 'Create DevOps Center work item')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Update-SalesforceDevOpsWorkItem {
    <#
    .SYNOPSIS
    Changes the subject, description or status of a work item.

    .DESCRIPTION
    Runs sf devops work-item update. Identify the work item by -WorkItemId or by -WorkItemName, and give at least one of -Subject, -Description and -Status. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops work-item update (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -WorkItemId = --work-item-id; -WorkItemName = --work-item-name; -Subject = --subject; -Description = --description; -Status = --status; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER WorkItemId
    ID of the work item. Use it or -WorkItemName. Passed to sf as --work-item-id.

    .PARAMETER WorkItemName
    Name of the work item, such as WI-000001. Use it or -WorkItemId. Passed to sf as --work-item-name.

    .PARAMETER Subject
    New subject. Passed to sf as --subject.

    .PARAMETER Description
    New description. Passed to sf as --description.

    .PARAMETER Status
    New status. Valid values: In Progress, Ready to Promote. Passed to sf as --status.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Update-SalesforceDevOpsWorkItem -WorkItemName WI-000001 -Status 'Ready to Promote' -TargetOrg devops-org -WhatIf
    Preview marking a work item ready.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $WorkItemId,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,79}\z')][string] $WorkItemName,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string] $Subject,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][ValidateSet('In Progress', 'Ready to Promote')][string] $Status,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($WorkItemId -and $WorkItemName) { throw 'Use -WorkItemId or -WorkItemName, not both.' }
    if (-not $WorkItemId -and -not $WorkItemName) { throw 'Give the work item with -WorkItemId or -WorkItemName.' }
    if (-not $Subject -and -not $Description -and -not $Status) { throw 'Give at least one of -Subject, -Description and -Status.' }
    if ($Status) { $Status = @('In Progress', 'Ready to Promote') | Where-Object { $_ -eq $Status } | Select-Object -First 1 }
    $arguments = @('devops', 'work-item', 'update')
    if ($WorkItemId) { $arguments += @('--work-item-id', $WorkItemId) }
    if ($WorkItemName) { $arguments += @('--work-item-name', $WorkItemName) }
    if ($Subject) { $arguments += @('--subject', $Subject) }
    if ($Description) { $arguments += @('--description', $Description) }
    if ($Status) { $arguments += @('--status', $Status) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($(if ($WorkItemId) { $WorkItemId } else { $WorkItemName }), 'Update DevOps Center work item')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Initialize-SalesforceDevOpsWorkItem {
    <#
    .SYNOPSIS
    Prepares a work item for a one-off promotion to a stage.

    .DESCRIPTION
    Runs sf devops work-item prepare. Creates the branches and pull requests in the source control repository that a one-off promotion needs. Run it before Start-SalesforceDevOpsPromotion for a one-off promotion. Get the IDs from Get-SalesforceDevOpsWorkItem. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops work-item prepare (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -WorkItemId = --work-item-id; -TargetStageId = --target-stage-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER WorkItemId
    ID of the work item to prepare. Passed to sf as --work-item-id. Required.

    .PARAMETER TargetStageId
    ID of the pipeline stage to promote the work item to. Passed to sf as --target-stage-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Initialize-SalesforceDevOpsWorkItem -WorkItemId 1fk000000000001 -TargetStageId 1QV000000000001 -TargetOrg devops-org -WhatIf
    Preview preparing a work item.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $WorkItemId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $TargetStageId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'work-item', 'prepare', '--work-item-id', $WorkItemId, '--target-stage-id', $TargetStageId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($WorkItemId, 'Prepare work item for promotion (creates branches and pull requests)')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Join-SalesforceDevOpsWorkItem {
    <#
    .SYNOPSIS
    Prepares work items to be combined and promoted together.

    .DESCRIPTION
    Runs sf devops work-item combine. Use it when work items in the same stage share metadata or depend on each other: DevOps Center combines the child work items into the parent so they are promoted as one unit. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops work-item combine (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -ParentWorkItemId = --parent-work-item-id; -ChildWorkItemId = --child-work-item-id; -TargetStageId = --target-stage-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER ParentWorkItemId
    ID of the parent work item. Passed to sf as --parent-work-item-id. Required.

    .PARAMETER ChildWorkItemId
    IDs of the work items to combine into the parent. Each is passed to sf as its own --child-work-item-id. Passed to sf as --child-work-item-id. Required.

    .PARAMETER TargetStageId
    ID of the pipeline stage to promote the combined work item to. Passed to sf as --target-stage-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Join-SalesforceDevOpsWorkItem -ParentWorkItemId 1fk000000000001 -ChildWorkItemId 1fk000000000002, 1fk000000000003 -TargetStageId 1QV000000000001 -TargetOrg devops-org -WhatIf
    Preview combining two work items into one.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $ParentWorkItemId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string[]] $ChildWorkItemId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $TargetStageId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if (@($ChildWorkItemId | Where-Object { $_ }).Count -eq 0) { throw 'Give at least one -ChildWorkItemId.' }
    $arguments = @('devops', 'work-item', 'combine', '--parent-work-item-id', $ParentWorkItemId, '--target-stage-id', $TargetStageId)
    foreach ($item in @($ChildWorkItemId | Where-Object { $_ })) { $arguments += @('--child-work-item-id', $item) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($ParentWorkItemId, 'Combine work items')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceDevOpsReview {
    <#
    .SYNOPSIS
    Creates a pull request for a work item branch.

    .DESCRIPTION
    Runs sf devops review create. Creates the pull request through the DevOps Center API with the version control credentials stored in the org, for GitHub and Bitbucket, so no local login to the repository is needed. Identify the work item by -WorkItemId or -WorkItemName. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops review create (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -WorkItemId = --work-item-id; -WorkItemName = --work-item-name; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER WorkItemId
    ID of the work item. Use it or -WorkItemName. Passed to sf as --work-item-id.

    .PARAMETER WorkItemName
    Name of the work item, such as WI-000001. Use it or -WorkItemId. Passed to sf as --work-item-name.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceDevOpsReview -WorkItemName WI-000001 -TargetOrg devops-org -WhatIf
    Preview opening a pull request.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $WorkItemId,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,79}\z')][string] $WorkItemName,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($WorkItemId -and $WorkItemName) { throw 'Use -WorkItemId or -WorkItemName, not both.' }
    if (-not $WorkItemId -and -not $WorkItemName) { throw 'Give the work item with -WorkItemId or -WorkItemName.' }
    $arguments = @('devops', 'review', 'create')
    if ($WorkItemId) { $arguments += @('--work-item-id', $WorkItemId) }
    if ($WorkItemName) { $arguments += @('--work-item-name', $WorkItemName) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($(if ($WorkItemId) { $WorkItemId } else { $WorkItemName }), 'Create a pull request for the work item branch')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDevOpsPipeline {
    <#
    .SYNOPSIS
    Lists the DevOps Center pipelines.

    .DESCRIPTION
    Runs sf devops pipeline list. Returns every pipeline with its stages, repositories and connected projects. For one pipeline in detail use Get-SalesforceDevOpsPipelineDetails. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops pipeline list (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDevOpsPipeline -TargetOrg devops-org
    All pipelines.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'pipeline', 'list')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDevOpsPipelineDetails {
    <#
    .SYNOPSIS
    Shows one DevOps Center pipeline in detail.

    .DESCRIPTION
    Runs sf devops pipeline get. Returns one pipeline: its stages in order, the repository and branch of each stage, and its connected projects. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops pipeline get (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PipelineId = --pipeline-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PipelineId
    ID of the pipeline, from Get-SalesforceDevOpsPipeline. Passed to sf as --pipeline-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDevOpsPipelineDetails -PipelineId 0XB000000000001 -TargetOrg devops-org
    One pipeline in detail.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'pipeline', 'get', '--pipeline-id', $PipelineId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceDevOpsPipeline {
    <#
    .SYNOPSIS
    Creates a DevOps Center pipeline attached to a repository.

    .DESCRIPTION
    Runs sf devops pipeline create. Give the URL of an existing repository as -Repo, or use -CreateRepo with a repository name to create one on GitHub or Bitbucket. After you create the pipeline, add stages (unless you gave -Stage) and activate it with Update-SalesforceDevOpsPipeline -Activate. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops pipeline create (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Name = --name; -Repo = --repo; -Stage = --stage; -ProjectId = --project-id; -CreateRepo = --create-repo; -RepoType = --repo-type; -RepoOwner = --repo-owner; -BitbucketWorkspace = --bitbucket-workspace; -BitbucketProjectKey = --bitbucket-project-key; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Name
    Name of the pipeline. Passed to sf as --name. Required.

    .PARAMETER Repo
    URL of an existing repository, or the name of a repository to create with -CreateRepo. Passed to sf as --repo. Required.

    .PARAMETER Stage
    Names of the pipeline stages in promotion order. Each is passed to sf as its own --stage. The CLI default is Integration, UAT, Staging and Production. Passed to sf as --stage.

    .PARAMETER ProjectId
    IDs of projects to associate with the pipeline. Each is passed to sf as its own --project-id. Passed to sf as --project-id.

    .PARAMETER CreateRepo
    Create the repository if it does not exist. Needs -RepoType, and -RepoOwner for GitHub or -BitbucketWorkspace for Bitbucket. Adds --create-repo.

    .PARAMETER RepoType
    Type of the repository. Valid values: github, bitbucket. Needed with -CreateRepo. Passed to sf as --repo-type.

    .PARAMETER RepoOwner
    Owner (organization or user) of the GitHub repository. Needed to create a GitHub repository. Passed to sf as --repo-owner.

    .PARAMETER BitbucketWorkspace
    Bitbucket workspace that will own the repository. Needed to create a Bitbucket repository. Passed to sf as --bitbucket-workspace.

    .PARAMETER BitbucketProjectKey
    Bitbucket project key to associate with the repository. Optional when creating a Bitbucket repository. Passed to sf as --bitbucket-project-key.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceDevOpsPipeline -Name 'Release Pipeline' -Repo https://github.com/myorg/myrepo -TargetOrg devops-org -WhatIf
    Preview creating a pipeline on an existing repository.

    .EXAMPLE
    New-SalesforceDevOpsPipeline -Name 'Release Pipeline' -Repo my-new-repo -CreateRepo -RepoType github -RepoOwner myorg -Stage Dev, QA, Prod -TargetOrg devops-org
    Create a pipeline, a new GitHub repository and three stages.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $true)][ValidatePattern('^[^\s-][^\s]*\z')][string] $Repo,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string[]] $Stage,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string[]] $ProjectId,
        [Parameter(Mandatory = $false)][switch] $CreateRepo,
        [Parameter(Mandatory = $false)][ValidateSet('github', 'bitbucket')][string] $RepoType,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string] $RepoOwner,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string] $BitbucketWorkspace,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string] $BitbucketProjectKey,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($CreateRepo -and -not $RepoType) { throw '-RepoType is needed with -CreateRepo.' }
    if ($CreateRepo -and $RepoType -eq 'github' -and -not $RepoOwner) { throw '-RepoOwner is needed to create a GitHub repository.' }
    if ($CreateRepo -and $RepoType -eq 'bitbucket' -and -not $BitbucketWorkspace) { throw '-BitbucketWorkspace is needed to create a Bitbucket repository.' }
    if ($RepoType) { $RepoType = @('github', 'bitbucket') | Where-Object { $_ -eq $RepoType } | Select-Object -First 1 }
    $arguments = @('devops', 'pipeline', 'create', '--name', $Name, '--repo', $Repo)
    foreach ($item in @($Stage | Where-Object { $_ })) { $arguments += @('--stage', $item) }
    foreach ($item in @($ProjectId | Where-Object { $_ })) { $arguments += @('--project-id', $item) }
    if ($CreateRepo) { $arguments += '--create-repo' }
    if ($RepoType) { $arguments += @('--repo-type', $RepoType) }
    if ($RepoOwner) { $arguments += @('--repo-owner', $RepoOwner) }
    if ($BitbucketWorkspace) { $arguments += @('--bitbucket-workspace', $BitbucketWorkspace) }
    if ($BitbucketProjectKey) { $arguments += @('--bitbucket-project-key', $BitbucketProjectKey) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($Name, 'Create DevOps Center pipeline')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Update-SalesforceDevOpsPipeline {
    <#
    .SYNOPSIS
    Renames, activates or deactivates a DevOps Center pipeline.

    .DESCRIPTION
    Runs sf devops pipeline update. Give at least one of -Name, -Activate and -Deactivate. A pipeline needs at least one stage before you can activate it, and you cannot change its stages after you activate it and promote changes through it, so -Activate asks for confirmation. You can combine -Deactivate and -Name. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops pipeline update (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PipelineId = --pipeline-id; -Name = --name; -Activate = --activate; -Deactivate = --deactivate; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PipelineId
    ID of the pipeline. Passed to sf as --pipeline-id. Required.

    .PARAMETER Name
    New name of the pipeline. Passed to sf as --name.

    .PARAMETER Activate
    Activate the pipeline. Cannot be used with -Deactivate. Asks for confirmation by default. Adds --activate.

    .PARAMETER Deactivate
    Deactivate the pipeline. Cannot be used with -Activate. Adds --deactivate.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Update-SalesforceDevOpsPipeline -PipelineId 0XB000000000001 -Activate -TargetOrg devops-org -WhatIf
    Preview activating a pipeline.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $false)][switch] $Activate,
        [Parameter(Mandatory = $false)][switch] $Deactivate,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($Activate -and $Deactivate) { throw 'Use -Activate or -Deactivate, not both.' }
    if (-not $Name -and -not $Activate -and -not $Deactivate) { throw 'Give at least one of -Name, -Activate and -Deactivate.' }
    if ($Activate -and -not $PSBoundParameters.ContainsKey('Confirm')) { $ConfirmPreference = 'Medium' }
    $arguments = @('devops', 'pipeline', 'update', '--pipeline-id', $PipelineId)
    if ($Name) { $arguments += @('--name', $Name) }
    if ($Activate) { $arguments += '--activate' }
    if ($Deactivate) { $arguments += '--deactivate' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($PipelineId, 'Update DevOps Center pipeline')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Add-SalesforceDevOpsPipelineProject {
    <#
    .SYNOPSIS
    Attaches a project to a DevOps Center pipeline.

    .DESCRIPTION
    Runs sf devops pipeline project add. Connects the project to the pipeline. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops pipeline project add (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PipelineId = --pipeline-id; -ProjectId = --project-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PipelineId
    ID of the pipeline. Passed to sf as --pipeline-id. Required.

    .PARAMETER ProjectId
    ID of the project to attach. Passed to sf as --project-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Add-SalesforceDevOpsPipelineProject -PipelineId 0XB000000000001 -ProjectId 0Hn000000000001 -TargetOrg devops-org -WhatIf
    Preview attaching a project.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $ProjectId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'pipeline', 'project', 'add', '--pipeline-id', $PipelineId, '--project-id', $ProjectId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($ProjectId, 'Attach project to DevOps Center pipeline')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceDevOpsPipelineProject {
    <#
    .SYNOPSIS
    Disconnects a project from a DevOps Center pipeline.

    .DESCRIPTION
    Runs sf devops pipeline project delete. Removes the connection between the project and the pipeline. The project itself is not deleted. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops pipeline project delete (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PipelineId = --pipeline-id; -ProjectId = --project-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PipelineId
    ID of the pipeline. Passed to sf as --pipeline-id. Required.

    .PARAMETER ProjectId
    ID of the project to disconnect. Passed to sf as --project-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceDevOpsPipelineProject -PipelineId 0XB000000000001 -ProjectId 0Hn000000000001 -TargetOrg devops-org -WhatIf
    Preview disconnecting a project.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $ProjectId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'pipeline', 'project', 'delete', '--pipeline-id', $PipelineId, '--project-id', $ProjectId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($ProjectId, 'Disconnect project from DevOps Center pipeline')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Add-SalesforceDevOpsPipelineStage {
    <#
    .SYNOPSIS
    Adds a stage to a DevOps Center pipeline.

    .DESCRIPTION
    Runs sf devops pipeline stage add. Inserts an empty stage before the stage given as -NextStageId. The new stage has no branch or environment: add them with Add-SalesforceDevOpsStageBranch and Add-SalesforceDevOpsStageEnvironment. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops pipeline stage add (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PipelineId = --pipeline-id; -Name = --name; -NextStageId = --next-stage-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PipelineId
    ID of the pipeline. Passed to sf as --pipeline-id. Required.

    .PARAMETER Name
    Name of the stage, such as Integration, UAT or Staging. Passed to sf as --name. Required.

    .PARAMETER NextStageId
    ID of the stage that follows the new stage. Passed to sf as --next-stage-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Add-SalesforceDevOpsPipelineStage -PipelineId 0XB000000000001 -Name QA -NextStageId 1QV000000000002 -TargetOrg devops-org -WhatIf
    Preview adding a QA stage.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $NextStageId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'pipeline', 'stage', 'add', '--pipeline-id', $PipelineId, '--name', $Name, '--next-stage-id', $NextStageId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($Name, 'Add stage to DevOps Center pipeline')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Update-SalesforceDevOpsPipelineStage {
    <#
    .SYNOPSIS
    Renames a stage of a DevOps Center pipeline.

    .DESCRIPTION
    Runs sf devops pipeline stage update. Changes the name of the stage. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops pipeline stage update (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -StageId = --stage-id; -Name = --name; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER StageId
    ID of the stage. Passed to sf as --stage-id. Required.

    .PARAMETER Name
    New name of the stage. Passed to sf as --name. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Update-SalesforceDevOpsPipelineStage -StageId 1QV000000000002 -Name Staging -TargetOrg devops-org -WhatIf
    Preview renaming a stage.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $StageId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'pipeline', 'stage', 'update', '--stage-id', $StageId, '--name', $Name)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($StageId, 'Rename DevOps Center pipeline stage')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceDevOpsPipelineStage {
    <#
    .SYNOPSIS
    Deletes a stage from a DevOps Center pipeline.

    .DESCRIPTION
    Runs sf devops pipeline stage delete. If the stage sits between two others, the stage before it is linked to the stage after it, so the chain stays whole. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops pipeline stage delete (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PipelineId = --pipeline-id; -StageId = --stage-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PipelineId
    ID of the pipeline that holds the stage. Passed to sf as --pipeline-id. Required.

    .PARAMETER StageId
    ID of the stage to delete. Passed to sf as --stage-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceDevOpsPipelineStage -PipelineId 0XB000000000001 -StageId 1QV000000000002 -TargetOrg devops-org -WhatIf
    Preview deleting a stage.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $StageId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'pipeline', 'stage', 'delete', '--pipeline-id', $PipelineId, '--stage-id', $StageId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($StageId, 'Delete DevOps Center pipeline stage')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Add-SalesforceDevOpsStageBranch {
    <#
    .SYNOPSIS
    Assigns a repository branch to a pipeline stage.

    .DESCRIPTION
    Runs sf devops stage branch add. By default the branch must already exist in the repository; -CreateVcsBranch creates it. A stage has one branch. If it already has one the command stops so the old branch is not orphaned, unless you give -Force, which replaces it. Branches are set from right to left: a stage can have a branch only after the stage to its right has one. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops stage branch add (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PipelineId = --pipeline-id; -StageId = --stage-id; -BranchName = --branch-name; -CreateVcsBranch = --create-vcs-branch; -Force = --force; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PipelineId
    ID of the pipeline that holds the stage. Passed to sf as --pipeline-id. Required.

    .PARAMETER StageId
    ID of the stage. Passed to sf as --stage-id. Required.

    .PARAMETER BranchName
    Name of the repository branch. Passed to sf as --branch-name. Required.

    .PARAMETER CreateVcsBranch
    Create the branch in the remote repository if it does not exist. Adds --create-vcs-branch.

    .PARAMETER Force
    Replace the stage's existing branch. Adds --force.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Add-SalesforceDevOpsStageBranch -PipelineId 0XB000000000001 -StageId 1QV000000000002 -BranchName uat -CreateVcsBranch -TargetOrg devops-org -WhatIf
    Preview assigning a branch, creating it if needed.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $StageId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $BranchName,
        [Parameter(Mandatory = $false)][switch] $CreateVcsBranch,
        [Parameter(Mandatory = $false)][switch] $Force,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'stage', 'branch', 'add', '--pipeline-id', $PipelineId, '--stage-id', $StageId, '--branch-name', $BranchName)
    if ($CreateVcsBranch) { $arguments += '--create-vcs-branch' }
    if ($Force) { $arguments += '--force' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($BranchName, 'Assign branch to DevOps Center pipeline stage')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceDevOpsStageBranch {
    <#
    .SYNOPSIS
    Removes the branch of a pipeline stage from the stage.

    .DESCRIPTION
    Runs sf devops stage branch delete. Only the link between the stage and its branch is removed; the branch in the repository stays. Branches are set from right to left, so this also removes the branches of every stage before it (to its left). The pipeline must be inactive. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops stage branch delete (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PipelineId = --pipeline-id; -StageId = --stage-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PipelineId
    ID of the pipeline that holds the stage. The CLI uses it to check that the pipeline is inactive. Passed to sf as --pipeline-id. Required.

    .PARAMETER StageId
    ID of the stage whose branch to remove. Passed to sf as --stage-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceDevOpsStageBranch -PipelineId 0XB000000000001 -StageId 1QV000000000002 -TargetOrg devops-org -WhatIf
    Preview removing a stage's branch.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $StageId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'stage', 'branch', 'delete', '--pipeline-id', $PipelineId, '--stage-id', $StageId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($StageId, 'Remove branch from DevOps Center pipeline stage (and from the stages before it)')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Add-SalesforceDevOpsStageEnvironment {
    <#
    .SYNOPSIS
    Adds a Salesforce environment to a pipeline stage.

    .DESCRIPTION
    Runs sf devops stage environment add. Starts an OAuth login to connect the environment, which opens a browser window (-NoBrowser prints the URL instead) and waits until you finish. A stage has one environment. If it already has one the command stops unless you give -Force, which adds the new one first and removes the old one after the new one is connected. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops stage environment add (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PipelineId = --pipeline-id; -StageId = --stage-id; -EnvironmentName = --environment-name; -OrgType = --org-type; -NoBrowser = --no-browser; -Force = --force; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PipelineId
    ID of the pipeline that holds the stage. Passed to sf as --pipeline-id. Required.

    .PARAMETER StageId
    ID of the stage. Passed to sf as --stage-id. Required.

    .PARAMETER EnvironmentName
    Name of the environment. Passed to sf as --environment-name. Required.

    .PARAMETER OrgType
    Type of the Salesforce org. Valid values: Production, Sandbox. Passed to sf as --org-type. Required.

    .PARAMETER NoBrowser
    Do not open the browser for the login; the CLI prints the URL for you to open yourself. The CLI only prints it outside JSON mode, so with this switch the command runs live in your terminal without --json (it needs a terminal, and returns nothing). Adds --no-browser.

    .PARAMETER Force
    Replace the stage's existing environment. Adds --force.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Add-SalesforceDevOpsStageEnvironment -PipelineId 0XB000000000001 -StageId 1QV000000000002 -EnvironmentName uat-sandbox -OrgType Sandbox -TargetOrg devops-org -WhatIf
    Preview connecting a sandbox to a stage.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $StageId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $EnvironmentName,
        [Parameter(Mandatory = $true)][ValidateSet('Production', 'Sandbox')][string] $OrgType,
        [Parameter(Mandatory = $false)][switch] $NoBrowser,
        [Parameter(Mandatory = $false)][switch] $Force,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($OrgType) { $OrgType = @('Production', 'Sandbox') | Where-Object { $_ -eq $OrgType } | Select-Object -First 1 }
    $arguments = @('devops', 'stage', 'environment', 'add', '--pipeline-id', $PipelineId, '--stage-id', $StageId, '--environment-name', $EnvironmentName, '--org-type', $OrgType)
    if ($NoBrowser) { $arguments += '--no-browser' }
    if ($Force) { $arguments += '--force' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    # With -NoBrowser the CLI prints the login URL, and it does not print it in JSON mode. So that run is shown live instead of captured.
    if (-not $NoBrowser) { $arguments += '--json' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($EnvironmentName, 'Add environment to DevOps Center pipeline stage (starts an OAuth login)')) { return }
    if ($NoBrowser) {
        Assert-SalesforceInteractiveSession -Command 'sf devops stage environment add --no-browser'
        Invoke-Salesforce -FilePath 'sf' -Arguments $arguments -Interactive @commonParams
        return
    }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceDevOpsStageEnvironment {
    <#
    .SYNOPSIS
    Removes an environment from a pipeline stage.

    .DESCRIPTION
    Runs sf devops stage environment delete. The pipeline must be inactive. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops stage environment delete (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -PipelineId = --pipeline-id; -EnvironmentId = --environment-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER PipelineId
    ID of the pipeline. The CLI uses it to check that the pipeline is inactive. Passed to sf as --pipeline-id. Required.

    .PARAMETER EnvironmentId
    ID of the environment to remove. Passed to sf as --environment-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceDevOpsStageEnvironment -PipelineId 0XB000000000001 -EnvironmentId 0Xx000000000001 -TargetOrg devops-org -WhatIf
    Preview removing an environment.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $EnvironmentId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'stage', 'environment', 'delete', '--pipeline-id', $PipelineId, '--environment-id', $EnvironmentId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($EnvironmentId, 'Remove environment from DevOps Center pipeline stage')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Start-SalesforceDevOpsPromotion {
    <#
    .SYNOPSIS
    Promotes work items, or a whole stage, to a pipeline stage.

    .DESCRIPTION
    Runs sf devops promote. Give -WorkItemId to promote specific work items, or -StageId to promote all the approved work items of a source stage; exactly one of the two. It deploys to the org of the target stage. By default it stops if another promotion to the same stage is running (-Force overrides) and it checks first that each work item has a pull request (-SkipValidation skips that). It returns a request token that Get-SalesforceDevOpsRequestStatus takes. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops promote (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetStageId = --target-stage-id; -WorkItemId = --work-item-id; -StageId = --stage-id; -DeployAll = --deploy-all; -Force = --force; -SkipValidation = --skip-validation; -TestLevel = --test-level; -Tests = --tests; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetStageId
    ID of the pipeline stage to promote to. Passed to sf as --target-stage-id. Required.

    .PARAMETER WorkItemId
    IDs of the work items to promote. Each is passed to sf as its own --work-item-id. Use it or -StageId. Passed to sf as --work-item-id.

    .PARAMETER StageId
    ID of the source stage whose approved work items are promoted. Use it or -WorkItemId. Passed to sf as --stage-id.

    .PARAMETER DeployAll
    Deploy all the metadata in the branch, not only the changes that are not yet in the target stage. Adds --deploy-all.

    .PARAMETER Force
    Submit the promotion even if another promotion to the same target stage is in progress. Adds --force.

    .PARAMETER SkipValidation
    Skip the check before the promotion that each work item has a pull request. Adds --skip-validation.

    .PARAMETER TestLevel
    Apex test level of the deployment. Valid values: NoTestRun, RunSpecifiedTests, RunLocalTests, RunAllTestsInOrg. NoTestRun is only for development orgs. Passed to sf as --test-level.

    .PARAMETER Tests
    Apex tests to run with -TestLevel RunSpecifiedTests. Each is passed to sf as its own --tests. Passed to sf as --tests.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Start-SalesforceDevOpsPromotion -StageId 1QV000000000001 -TargetStageId 1QV000000000002 -TargetOrg devops-org -WhatIf
    Preview promoting a whole stage.

    .EXAMPLE
    Start-SalesforceDevOpsPromotion -WorkItemId 1fk000000000001, 1fk000000000002 -TargetStageId 1QV000000000001 -TestLevel RunLocalTests -TargetOrg devops-org
    Promote two work items and run the local tests.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $TargetStageId,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string[]] $WorkItemId,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $StageId,
        [Parameter(Mandatory = $false)][switch] $DeployAll,
        [Parameter(Mandatory = $false)][switch] $Force,
        [Parameter(Mandatory = $false)][switch] $SkipValidation,
        [Parameter(Mandatory = $false)][ValidateSet('NoTestRun', 'RunSpecifiedTests', 'RunLocalTests', 'RunAllTestsInOrg')][string] $TestLevel,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string[]] $Tests,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $workItems = @($WorkItemId | Where-Object { $_ })
    if ($workItems.Count -gt 0 -and $StageId) { throw 'Use -WorkItemId or -StageId, not both.' }
    if ($workItems.Count -eq 0 -and -not $StageId) { throw 'Give the work items to promote with -WorkItemId, or a source stage with -StageId.' }
    if ($Tests -and $TestLevel -ne 'RunSpecifiedTests') { throw '-Tests is only used with -TestLevel RunSpecifiedTests.' }
    if ($TestLevel -eq 'RunSpecifiedTests' -and -not $Tests) { throw '-TestLevel RunSpecifiedTests needs the tests to run in -Tests.' }

    if ($TestLevel) { $TestLevel = @('NoTestRun', 'RunSpecifiedTests', 'RunLocalTests', 'RunAllTestsInOrg') | Where-Object { $_ -eq $TestLevel } | Select-Object -First 1 }
    $arguments = @('devops', 'promote', '--target-stage-id', $TargetStageId)
    foreach ($item in @($WorkItemId | Where-Object { $_ })) { $arguments += @('--work-item-id', $item) }
    if ($StageId) { $arguments += @('--stage-id', $StageId) }
    if ($DeployAll) { $arguments += '--deploy-all' }
    if ($Force) { $arguments += '--force' }
    if ($SkipValidation) { $arguments += '--skip-validation' }
    if ($TestLevel) { $arguments += @('--test-level', $TestLevel) }
    foreach ($item in @($Tests | Where-Object { $_ })) { $arguments += @('--tests', $item) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($TargetStageId, 'Promote to the pipeline stage (deploys to its org)')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Complete-SalesforceDevOpsPromotion {
    <#
    .SYNOPSIS
    Deploys work items that were merged outside DevOps Center to a stage.

    .DESCRIPTION
    Runs sf devops promotion complete. Deploys work items that were merged into the pipeline branch outside DevOps Center (externally merged) into the target stage's org and updates the DevOps Center records. It is the "Complete Promotion" action of the DevOps Center page for a stage that is out of sync. Without -WorkItemId it deploys every undeployed work item of the stage; if there are none it does nothing and succeeds. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops promotion complete (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetStageId = --target-stage-id; -WorkItemId = --work-item-id; -DeployAll = --deploy-all; -TestLevel = --test-level; -Tests = --tests; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetStageId
    ID of the out-of-sync stage to deploy to. Passed to sf as --target-stage-id. Required.

    .PARAMETER WorkItemId
    IDs of specific work items to deploy. Each is passed to sf as its own --work-item-id. Leave it out to deploy all the undeployed work items of the stage; use it for the first stage of a pipeline, which has no source stage. Passed to sf as --work-item-id.

    .PARAMETER DeployAll
    Deploy all the metadata in the branch, not only the changes that are not yet in the stage. Adds --deploy-all.

    .PARAMETER TestLevel
    Apex test level of the deployment. Valid values: NoTestRun, RunSpecifiedTests, RunLocalTests, RunAllTestsInOrg. NoTestRun is only for development orgs. Passed to sf as --test-level.

    .PARAMETER Tests
    Apex tests to run with -TestLevel RunSpecifiedTests. Each is passed to sf as its own --tests. Passed to sf as --tests.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Complete-SalesforceDevOpsPromotion -TargetStageId 1QV000000000002 -TargetOrg devops-org -WhatIf
    Preview completing the promotion of a stage.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $TargetStageId,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string[]] $WorkItemId,
        [Parameter(Mandatory = $false)][switch] $DeployAll,
        [Parameter(Mandatory = $false)][ValidateSet('NoTestRun', 'RunSpecifiedTests', 'RunLocalTests', 'RunAllTestsInOrg')][string] $TestLevel,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string[]] $Tests,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($Tests -and $TestLevel -ne 'RunSpecifiedTests') { throw '-Tests is only used with -TestLevel RunSpecifiedTests.' }
    if ($TestLevel -eq 'RunSpecifiedTests' -and -not $Tests) { throw '-TestLevel RunSpecifiedTests needs the tests to run in -Tests.' }

    if ($TestLevel) { $TestLevel = @('NoTestRun', 'RunSpecifiedTests', 'RunLocalTests', 'RunAllTestsInOrg') | Where-Object { $_ -eq $TestLevel } | Select-Object -First 1 }
    $arguments = @('devops', 'promotion', 'complete', '--target-stage-id', $TargetStageId)
    foreach ($item in @($WorkItemId | Where-Object { $_ })) { $arguments += @('--work-item-id', $item) }
    if ($DeployAll) { $arguments += '--deploy-all' }
    if ($TestLevel) { $arguments += @('--test-level', $TestLevel) }
    foreach ($item in @($Tests | Where-Object { $_ })) { $arguments += @('--tests', $item) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($TargetStageId, 'Deploy undeployed work items to the stage org')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Test-SalesforceDevOpsPromotion {
    <#
    .SYNOPSIS
    Checks whether work items can be promoted to a stage.

    .DESCRIPTION
    Runs sf devops promotion validate. Validates the work items for the target stage: it looks for version control and object permission errors before a promotion is tried. It does not deploy anything. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops promotion validate (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetStageId = --target-stage-id; -WorkItemId = --work-item-id; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetStageId
    ID of the stage to validate the promotion to. Passed to sf as --target-stage-id. Required.

    .PARAMETER WorkItemId
    IDs of the work items to validate. Each is passed to sf as its own --work-item-id. Passed to sf as --work-item-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Test-SalesforceDevOpsPromotion -WorkItemId 1fk000000000001 -TargetStageId 1QV000000000002 -TargetOrg devops-org
    Can this work item be promoted?

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $TargetStageId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string[]] $WorkItemId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if (@($WorkItemId | Where-Object { $_ }).Count -eq 0) { throw 'Give at least one -WorkItemId.' }
    $arguments = @('devops', 'promotion', 'validate', '--target-stage-id', $TargetStageId)
    foreach ($item in @($WorkItemId | Where-Object { $_ })) { $arguments += @('--work-item-id', $item) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDevOpsRequestStatus {
    <#
    .SYNOPSIS
    Gets the status of a DevOps Center request.

    .DESCRIPTION
    Runs sf devops request status. Returns the current status of the request with the given token, such as the one Start-SalesforceDevOpsPromotion returns. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    SALESFORCE CLI
        Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
        Command run: sf devops request status (plugin @salesforce/plugin-devops-center)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -RequestToken = --request-token; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER RequestToken
    The request token from the promotion result. Passed to sf as --request-token. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDevOpsRequestStatus -RequestToken $promotion.requestToken -TargetOrg devops-org
    Check on a promotion.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,299}\z')][string] $RequestToken,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'request', 'status', '--request-token', $RequestToken)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion
