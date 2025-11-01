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
    $command = "sf project generate --name $Name"
    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) {
            throw "Output directory '$OutputDirectory' does not exist."
        }
        $command += " --output-dir $OutputDirectory"
    }
    if ($DefaultPackageDirectory) { $command += " --default-package-dir $DefaultPackageDirectory" }
    if ($Namespace) { $command += " --namespace $Namespace" }
    if ($GenerateManifest) { $command += " --manifest" }
    $command += " --template $Template"
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    $result = Show-SalesforceResult -Result $result

    if (($null -ne $DefaultUserName) -and ($DefaultUserName -ne '')) {
        $projectFolder = Join-Path -Path $result.outputDir -ChildPath $Name
        New-Item -Path $projectFolder -Name ".sfdx" -ItemType Directory | Out-Null
        Set-SalesforceTargetOrg -DefaultUserName $DefaultUserName -ProjectFolder $projectFolder
    }
    return $result
}

function Set-SalesforceTargetOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Value,
        [Parameter(Mandatory = $false)][switch] $Global
    )
    $command = "sf config set target-org=$Value"
    if ($Global) { $command += " --global" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return (Show-SalesforceResult -Result $result).successes
}

function Get-SalesforceTargetOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Global
    )
    $command = "sf config get target-org"
    if ($Global) { $command += " --global" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceTargetOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Global
    )
    $command = "sf config unset target-org"
    if ($Global) { $command += " --global" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return (Show-SalesforceResult -Result $result).successes
}

function Get-SalesforceConfig {
    [CmdletBinding()]
    Param()
    $command = "sf config list --json"
    $result = Invoke-Salesforce -Command $command
    Show-SalesforceResult -Result $result
}

function Set-SalesforceTargetDevHub {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Value,
        [Parameter(Mandatory = $false)][switch] $Global
    )

    $command = "sf config set target-dev-hub=$Value"
    if ($Global) { $command += " --global" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return (Show-SalesforceResult -Result $result).successes
}

function Get-SalesforceTargetDevHub {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Global
    )

    $command = "sf config get target-dev-hub"
    if ($Global) { $command += " --global" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceTargetDevHub {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Global
    )
    $command = "sf config unset target-dev-hub"
    if ($Global) { $command += " --global" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
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

    $command = "sf org list --all"
    if ($SkipConnectionStatus) {
        $command += " --skip-connection-status"
    }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command

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
    $command = "sf org create scratch"
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }
    if ($SetDefault) { $command += " --set-default" }
    if ($DurationDays) { $command += " --duration-days $DurationDays" }
    $command += " --definition-file $DefinitionFile"
    if ($WaitMinutes) { $command += " --wait $WaitMinutes" }
    if ($Edition) { $command += " --edition $Edition" }
    if ($Snapshot) { $command += " --snapshot $Snapshot" }
    if ($AdminEmail) { $command += " --admin-email $AdminEmail" }
    if ($Description) { $command += " --description `"$Description`"" }
    if ($Name) { $command += " --name `"$Name`"" }
    if ($Release) { $command += " --release $Release" }
    if ($SourceOrgId) { $command += " --source-org $SourceOrgId" }
    if ($AdminUsername) { $command += " --username $AdminUsername" }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    Show-SalesforceResult -Result $result
}

function Remove-SalesforceScratchOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $TargetOrg,
        [Parameter()][switch] $NoPrompt
    )
    $command = "sf org delete scratch --target-org $TargetOrg"
    if ($NoPrompt) {
        $command += " --no-prompt"
    }
    Invoke-Salesforce -Command $command
}

function Remove-SalesforceScratchOrgs {
    [CmdletBinding()]
    Param()

    $scratchOrgs = Get-SalesforceScratchOrgs
    foreach ($scratchOrg in $scratchOrgs) {
        Remove-SalesforceScratchOrg -TargetOrg ($scratchOrg.username) -NoPrompt
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

    $command = "sf apex run test"

    $command += Get-SalesforceCliApexTestParams -TestsInProject:$TestsInProject -ClassName $ClassName -TestName $TestName

    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) {
            throw "Output directory '$OutputDirectory' does not exist."
        }
        $command += " --output-dir $OutputDirectory"
    }
    if ($WaitMinutes) { $command += " --wait $WaitMinutes" }

    if ($Concise) { $command += " --concise" }
    if ($CodeCoverage) { $command += " --code-coverage" }
    if ($CodeCoverageDetailed) { $command += " --detailed-coverage" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --result-format $ResultFormat"

    if ($ResultFormat -ne 'json') {
        Invoke-Salesforce -Command $command
        return
    }

    $result = Invoke-Salesforce -Command $command
    $result = $result | ConvertFrom-Json

    $result.result.tests
    if ($result.result.summary.outcome -ne 'Passed') {
        throw ($result.result.summary.failing.tostring() + " Tests Failed")
    }

    if ((-not $CodeCoverage) -and (-not $CodeCoverageDetailed)) {
        return
    }

    [int]$codeCoverage = ($result.result.summary.testRunCoverage -replace '%')
    if ($codeCoverage -lt 75) {
        $result.result.coverage.coverage
        throw "Insufficient code coverage ${codeCoverage}%"
    }
}

function Get-SalesforceCliApexTestParams {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $ClassName,
        [Parameter(Mandatory = $false)][string] $TestName,
        [Parameter(Mandatory = $false)][switch] $TestsInProject
    )

    $value = ""
    if ($TestsInProject.IsPresent) {
        $testClassNames = Get-SalesforceApexTestClassNames
        $value += ConvertTo-SalesforceCliApexTestParams -TestClassNames $testClassNames
    } elseif ($ClassName -and $TestName) {
        $value += " --tests $ClassName.$TestName" # Run specific Test in a Class
    } elseif ((-not $TestName) -and ($ClassName)) {
        $value += " --tests $ClassName"     # Run Test Class
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
        [Parameter(Mandatory = $false)][int] $DebounceMilliseconds = 300
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
    $watcherInfo = New-SalesforceApexWatcher -ProjectFolder $ProjectFolder
    $sourceIdentifiers = Register-SalesforceApexWatcherEvents -Watcher $watcherInfo.Watcher
    $recentEvents = [System.Collections.Hashtable]::Synchronized(@{})

    try {
        Write-Host "Watching $($watcherInfo.Project) for Apex changes. Press Ctrl+C to stop." -ForegroundColor Cyan
        while ($true) {
            $changeEvent = Wait-Event -Timeout 1
            if (-not $changeEvent) {
                continue
            }
            if ($changeEvent.SourceIdentifier -notin $sourceIdentifiers) {
                Remove-Event -EventIdentifier $changeEvent.EventIdentifier -ErrorAction SilentlyContinue
                continue
            }

            try {
                $paths = Get-SalesforceApexEventPaths -EventArgs $changeEvent.SourceEventArgs

                foreach ($path in $paths) {
                    # If Not Salesfore Apex or Trigger
                    if (-not (Test-SalesforceApexPath -Path $path -Extensions @('.cls', '.trigger'))) {
                        continue
                    }

                    # Wait for File Save
                    $now = Get-Date
                    $nextAllowed = $recentEvents[$path]
                    if ($nextAllowed -and ($now -lt $nextAllowed)) {
                        continue
                    }
                    Start-Sleep -Milliseconds $DebounceMilliseconds

                    # Deploy and Test
                    Watch-SalesforceApexAction -FilePath $path -ProjectFolder $watcherInfo.Project | Out-Null
                    $recentEvents[$path] = (Get-Date).AddMilliseconds($DebounceMilliseconds)
                }
            }
            finally {
                Remove-Event -EventIdentifier $changeEvent.EventIdentifier -ErrorAction SilentlyContinue
            }
        }
    }
    finally {
        foreach ($identifier in $sourceIdentifiers) {
            Unregister-Event -SourceIdentifier $identifier -ErrorAction SilentlyContinue
        }
        $watcherInfo.Watcher.EnableRaisingEvents = $false
        $watcherInfo.Watcher.Dispose()
    }
}

#region "Salesforce Apex Watcher Helpers"

function Invoke-SalesforceApex {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ApexFile,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $command = "sf apex run --file $ApexFile"
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
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

    $paths = @()
    if ($EventArgs -is [System.IO.RenamedEventArgs]) {
        $paths += $EventArgs.FullPath
    }
    else {
        $paths += $EventArgs.FullPath
    }

    return $paths
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
        [Parameter(Mandatory = $false)][string] $ProjectFolder
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

        $command = "sf project deploy start"
        $command += " --metadata ${type}:${name}"

        $testClassNames = Get-SalesforceApexTestClassNames -FilePath $FilePath -ProjectFolder $ProjectFolder
        if ($testClassNames -and $testClassNames.Count -gt 0) {
            $command += " --test-level RunSpecifiedTests"
            $command += $testClassNames | ConvertTo-SalesforceCliApexTestParams
        } else {
            Write-Warning 'No Apex test classes found in project; deploying without running tests.'
        }
        $command += " --ignore-warnings"
        $command += " --json"

        $deployJson = Invoke-Salesforce -Command $command
        Show-SalesforceResult -Result $deployJson

        $successMessage = "Deployed $type ${name}"
        if ($testClassNames -and $testClassNames.Count -gt 0) {
            $successMessage += " and successfully ran tests (" + ($testClassNames -join ', ') + ")"
        }
        $successMessage += "."
        Write-Host $successMessage -ForegroundColor Cyan
    }
    catch {
        Write-Error $_
    }
}

#endregion

function Get-SalesforceType {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $FileName)

    if ($FileName.EndsWith(".cls")) {
        return "ApexClass"
    }
    if ($FileName.EndsWith(".trigger")) {
        return "ApexTrigger"
    }
    return ""
}

function Get-SalesforceName {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $FileName)

    $name = (Get-Item $FileName).Basename
    Write-Verbose ("Apex Name: " + $name)
    return $name
}

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
        (Select-String -Path $_.FullName -Pattern $className -SimpleMatch -Quiet)
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
    $query = "SELECT Id, Name, Body FROM ApexClass WHERE Name = '$Name' LIMIT 1"
    return Select-SalesforceRecords -Query $query -UseToolingApi -TargetOrg $TargetOrg
}

#endregion

#region Apex Scaffolding

function New-SalesforceApexClass {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string]
            [ValidateSet('DefaultApexClass', 'ApexUnitTest', 'ApexUnitTest', 'InboundEmailService')]
            $Template = 'DefaultApexClass',
        [Parameter(Mandatory = $false)][string] $OutputDirectory = 'force-app/main/default/classes'
    )
    $command = "sf apex generate class"
    $command += " --name $Name"
    $command += " --template $Template"
    if ($PSBoundParameters.ContainsKey('OutputDirectory') -and -not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) {
            throw "Output directory '$OutputDirectory' does not exist."
        }
        $command += " --output-dir $OutputDirectory"
    }
    Invoke-Salesforce -Command $command
}

function New-SalesforceApexTrigger {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string]
            [ValidateSet('before insert', 'before update', 'before delete', 'after insert', 'after update', 'after delete', 'after undelete')]
            $Event = 'before insert',
        [Parameter(Mandatory = $false)][string] $SObject,
        [Parameter(Mandatory = $false)][string] $OutputDirectory = 'force-app/main/default/triggers'
    )
    $command = "sf apex generate trigger"
    $command += " --name $Name"
    $command += " --event $Event"
    if ($SObject) { $command += " --sobject $SObject" }
        if ($PSBoundParameters.ContainsKey('OutputDirectory') -and -not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) {
            throw "Output directory '$OutputDirectory' does not exist."
        }
        $command += " --output-dir $OutputDirectory"
    }
    Invoke-Salesforce -Command $command
}

#endregion

#region LWC Dev Server

function Install-SalesforceLwcDevServer {
    [CmdletBinding()]
    Param()
    Invoke-Salesforce -Command "sf plugins install @salesforce/plugin-lightning-dev"
}

function Start-SalesforceLwcDevServer {
    [CmdletBinding()]
    Param()
    Invoke-Salesforce -Command "sf lightning dev app"
}

#endregion

#region LWC / Jest Testing

function Install-SalesforceJest {
    [CmdletBinding()]
    Param()
    if (Get-Command yarn -ErrorAction SilentlyContinue) {
        Invoke-Salesforce -Command "yarn add -D @salesforce/sfdx-lwc-jest"
    } else {
        Invoke-Salesforce -Command "npm install -D @salesforce/sfdx-lwc-jest"
    }
}

function New-SalesforceJestTest {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $LwcName)
    $filePath = "force-app/main/default/lwc/$LwcName/$LwcName.js"
    $command = "sf force lightning lwc test create --filepath $filePath --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Test-SalesforceJest {
    [CmdletBinding()]
    Param()
    Invoke-Salesforce -Command "npm run test:unit"
}

function Debug-SalesforceJest {
    [CmdletBinding()]
    Param()
    Invoke-Salesforce -Command "npm run test:unit:debug"
}

function Watch-SalesforceJest {
    [CmdletBinding()]
    Param()
    Invoke-Salesforce -Command "npm run test:unit:watch"
}

#endregion
