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
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string][ValidateSet('standard', 'empty', 'analytics')] $Template = 'standard',
        [Parameter(Mandatory = $false)][string] $DefaultUserName = $null,

        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $DefaultPackageDirectory,
        [Parameter(Mandatory = $false)][string] $Namespace,
        [Parameter(Mandatory = $false)][switch] $GenerateManifest
    )
    $arguments = @('project', 'generate', '--name', $Name)
    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) {
            throw "Output directory '$OutputDirectory' does not exist."
        }
        $arguments += @('--output-dir', $OutputDirectory)
    }
    if ($DefaultPackageDirectory) { $arguments += @('--default-package-dir', $DefaultPackageDirectory) }
    if ($Namespace) { $arguments += @('--namespace', $Namespace) }
    if ($GenerateManifest) { $arguments += '--manifest' }
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
    [CmdletBinding()]
    Param()
    $arguments = @('config', 'list', '--json')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    Show-SalesforceResult -Result $result
}

function Set-SalesforceTargetDevHub {
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
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][int] $DurationDays,
        [Parameter(Mandatory = $false)][string] $DefinitionFile = 'config/project-scratch-def.json',
        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string][ValidateSet('developer', 'enterprise', 'group', 'professional', 'partner-developer', 'partner-enterprise', 'partner-group', 'partner-professional')] $Edition,
        [Parameter(Mandatory = $false)][string] $Snapshot,
        [Parameter(Mandatory = $false)][string] $AdminEmail,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string][ValidateSet('preview', 'previous')] $Release,
        [Parameter(Mandatory = $false)][string] $SourceOrgId,
        [Parameter(Mandatory = $false)][string] $AdminUsername
    )
    $arguments = @('org', 'create', 'scratch')
    if ($TargetDevHub) { $arguments += @('--target-dev-hub', $TargetDevHub) }
    if ($SetDefault) { $arguments += '--set-default' }
    if ($DurationDays) { $arguments += @('--duration-days', $DurationDays) }
    $arguments += @('--definition-file', $DefinitionFile)
    if ($WaitMinutes) { $arguments += @('--wait', $WaitMinutes) }
    if ($Edition) { $arguments += @('--edition', $Edition) }
    if ($Snapshot) { $arguments += @('--snapshot', $Snapshot) }
    if ($AdminEmail) { $arguments += @('--admin-email', $AdminEmail) }
    if ($Description) { $arguments += @('--description', $Description) }
    if ($Name) { $arguments += @('--name', $Name) }
    if ($Release) { $arguments += @('--release', $Release) }
    if ($SourceOrgId) { $arguments += @('--source-org', $SourceOrgId) }
    if ($AdminUsername) { $arguments += @('--username', $AdminUsername) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    Show-SalesforceResult -Result $result
}

function Remove-SalesforceScratchOrg {
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

#region Apex Testing

function Test-SalesforceApex {
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
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $arguments = @('apex', 'run', 'test')

    $arguments += Get-SalesforceCliApexTestArguments -TestsInProject:$TestsInProject -ClassName $ClassName -TestName $TestName

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
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ApexFile,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('apex', 'run', '--file', $ApexFile)
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
    the local tests. The returned TestRunId works from any later session on any computer: pass it to Get-SalesforceApexTestResult or
    Wait-SalesforceApexTest. To run and wait in one call use Test-SalesforceApex.
    .EXAMPLE
    $run = Start-SalesforceApexTest -TestLevel RunLocalTests -TargetOrg myorg; $run.TestRunId
    .EXAMPLE
    # Later, in another shell:
    Wait-SalesforceApexTest -TestRunId 707xx0000000001 -TimeoutMinutes 30 -TargetOrg myorg
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string[]] $ClassName,
        [Parameter(Mandatory = $false)][string[]] $TestName,
        [Parameter(Mandatory = $false)][string[]] $SuiteName,
        [Parameter(Mandatory = $false)][ValidateSet('RunLocalTests', 'RunAllTestsInOrg', 'RunSpecifiedTests')][string] $TestLevel,
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
    Coverage (only with -CodeCoverage) and Completed. A run that is still queued or processing returns Completed = $false and does not throw;
    use Wait-SalesforceApexTest to wait. A finished run with failing tests writes the object and then throws PsfdxTestsFailed (TargetObject is the
    summary). Coverage is returned, never judged: there is no threshold here.
    .EXAMPLE
    $r = Get-SalesforceApexTestResult -TestRunId 707xx0000000001 -CodeCoverage -TargetOrg myorg; $r.Tests | Where-Object Outcome -ne 'Pass'
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^707[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$')][string] $TestRunId,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][switch] $CodeCoverageDetailed,
        [Parameter(Mandatory = $false)][switch] $Concise,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($CodeCoverageDetailed -and -not $CodeCoverage) { throw '-CodeCoverageDetailed needs -CodeCoverage.' }
    $arguments = @('apex', 'get', 'test', '--test-run-id', $TestRunId)
    if ($Concise) { $arguments += '--concise' }
    if ($CodeCoverage) { $arguments += '--code-coverage' }
    if ($CodeCoverageDetailed) { $arguments += '--detailed-coverage' }
    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) { throw "Output directory '$OutputDirectory' does not exist." }
        $arguments += @('--output-dir', $OutputDirectory)
    }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += @('--result-format', 'json', '--json')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
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
    .EXAMPLE
    $run = Start-SalesforceApexTest -TargetOrg myorg; Wait-SalesforceApexTest -TestRunId $run.TestRunId -TimeoutMinutes 30 -CodeCoverage -TargetOrg myorg
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^707[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$')][string] $TestRunId,
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
    .EXAMPLE
    Test-SalesforceFlow -TestLevel RunLocalTests -TargetOrg myorg
    .EXAMPLE
    Test-SalesforceFlow -FlowName Order_Flow -Synchronous -TargetOrg myorg
    .EXAMPLE
    $run = Test-SalesforceFlow -TestLevel RunLocalTests -TargetOrg myorg; Get-SalesforceFlowTestResult -TestRunId $run.TestRunId -TargetOrg myorg
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
    .EXAMPLE
    Get-SalesforceFlowTestResult -TestRunId 707xx0000000001 -TargetOrg myorg
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^707[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$')][string] $TestRunId,
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
    .EXAMPLE
    Test-SalesforceLogic -TestCategory Apex, Flow -TestLevel RunLocalTests -Synchronous -TargetOrg myorg
    .EXAMPLE
    Test-SalesforceLogic -TestName 'OrderFlow.Test1', 'OrderTest.testSave' -WaitMinutes 10 -TargetOrg myorg
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
    .EXAMPLE
    Get-SalesforceLogicTestResult -TestRunId 707xx0000000001 -CodeCoverage -TargetOrg myorg
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^707[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$')][string] $TestRunId,
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
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string]
            [ValidateSet('DefaultApexClass', 'ApexUnitTest', 'InboundEmailService')]
            $Template = 'DefaultApexClass',
        # No default: when omitted, --output-dir is left off so the CLI picks the
        # project's own default package directory.
        [Parameter(Mandatory = $false)][string] $OutputDirectory
    )
    $arguments = @('apex', 'generate', 'class')
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
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string]
            [ValidateSet('before insert', 'before update', 'before delete', 'after insert', 'after update', 'after delete', 'after undelete')]
            $Event = 'before insert',
        [Parameter(Mandatory = $false)][string] $SObject,
        # No default: when omitted, --output-dir is left off so the CLI picks the
        # project's own default package directory.
        [Parameter(Mandatory = $false)][string] $OutputDirectory
    )
    $arguments = @('apex', 'generate', 'trigger')
    $arguments += @('--name', $Name)
    $arguments += @('--event', $Event)
    if ($SObject) { $arguments += @('--sobject', $SObject) }
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
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][ValidateSet('App', 'Component', 'Site')][string] $Mode = 'App',
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][ValidateSet('ios', 'android')][string] $DeviceType,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($PSBoundParameters.ContainsKey('DeviceType') -and $Mode -ne 'App') {
        throw "-DeviceType is only supported with -Mode App."
    }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    if (-not (Test-SalesforceLightningDevPluginInstalled @commonParams)) {
        throw "The Salesforce CLI plugin '@salesforce/plugin-lightning-dev' is not installed. Run Install-SalesforceLwcDevServer, then try again."
    }
    $arguments = @('lightning', 'dev', $($Mode.ToLowerInvariant()))
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $arguments += @('--name', $Name)
    }
    if ($DeviceType) { $arguments += @('--device-type', $DeviceType) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

#endregion

#region LWC / Jest Testing

function Install-SalesforceJest {
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
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $LwcName,
        [Parameter(Mandatory = $false)][string] $ProjectPath = '.',
        [Parameter(Mandatory = $false)][switch] $Force
    )
    # The legacy 'sf force lightning lwc test create' command was removed from the Salesforce CLI,
    # so the Jest test scaffold is written directly.
    if ($LwcName -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
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
    [CmdletBinding()]
    Param()
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'npm' -Arguments @('run', 'test:unit') @commonParams
}

function Debug-SalesforceJest {
    [CmdletBinding()]
    Param()
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'npm' -Arguments @('run', 'test:unit:debug') @commonParams
}

function Watch-SalesforceJest {
    [CmdletBinding()]
    Param()
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'npm' -Arguments @('run', 'test:unit:watch') @commonParams
}

#endregion
