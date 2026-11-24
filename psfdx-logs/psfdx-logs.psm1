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

#region Debug Logs

function Watch-SalesforceDebugLogs {
    <#
    .SYNOPSIS
    Streams debug logs from an org to the terminal.

    .DESCRIPTION
    Runs sf apex tail log with --color, which keeps running until you press Ctrl+C. Unless you pass -SkipTraceFlag the CLI first creates a trace flag for you, which stays after you stop.

    .PARAMETER DebugLevel
    Debug level to set on the DEVELOPER_LOG trace flag for your user. Passed to sf as --debug-level.

    .PARAMETER SkipTraceFlag
    Skip trace flag setup. Assumes that a trace flag and debug level are fully set up. Adds --skip-trace-flag.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Watch-SalesforceDebugLogs -DebugLevel SFDC_DevConsole -TargetOrg dev1
    Follow the logs of the org.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf apex tail log (plugin @salesforce/plugin-apex)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -DebugLevel = --debug-level; -SkipTraceFlag = --skip-trace-flag; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][string] $DebugLevel,
        [Parameter(Mandatory = $false)][switch] $SkipTraceFlag,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('apex', 'tail', 'log')
    if ($DebugLevel) { $arguments += @('--debug-level', $DebugLevel) }
    if ($SkipTraceFlag) { $arguments += '--skip-trace-flag' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--color'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    return Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

function Select-SalesforceDebugLogs {
    <#
    .SYNOPSIS
    Lists the debug logs in an org.

    .DESCRIPTION
    Runs sf apex list log and returns one object per log (Id, Application, Operation, StartTime, LogLength, and so on), in the order the CLI returns them.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Select-SalesforceDebugLogs -TargetOrg dev1 | Select-Object -First 5
    The five newest logs.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf apex list log (plugin @salesforce/plugin-apex)
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
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $arguments = @('apex', 'list', 'log')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDebugLogs {
    <#
    .SYNOPSIS
    Fetches one debug log, or the newest few, from an org.

    .DESCRIPTION
    Runs sf apex get log with --log-id or --number. Give exactly one of -LogId and -Last. With -OutputDir the CLI saves the logs as files; with -Raw the text is returned as it is.

    .PARAMETER OutputDir
    Directory for saving the log files. Passed to sf as --output-dir.

    .PARAMETER LogId
    ID of the specific log to display. Passed to sf as --log-id.

    .PARAMETER Last
    Fetch this many of the newest logs. Passed as --number. Use instead of -LogId.

    .PARAMETER Raw
    Return the log text as the CLI prints it.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDebugLogs -Last 1 -Raw -TargetOrg dev1
    The newest log, as text.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf apex get log (plugin @salesforce/plugin-apex)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -OutputDir = --output-dir; -LogId = --log-id; -Last = --number; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][string] $LogId,
        [Parameter(Mandatory = $false)][int] $Last,
        [Parameter(Mandatory = $false)][switch] $Raw,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if (-not $LogId -and -not $Last) {
        throw "Specify -LogId or -Last to fetch a debug log."
    }
    if ($LogId -and $Last) {
        throw "Provide only one of -LogId or -Last, not both."
    }

    $arguments = @('apex', 'get', 'log')
    if ($OutputDir) {
        if ((Test-Path -Path $OutputDir) -eq $false) {
            throw "Folder $OutputDir does not exist"
        }
        $arguments += @('--output-dir', $OutputDir)
    }
    if ($LogId) { $arguments += @('--log-id', $LogId) }
    if ($Last) { $arguments += @('--number', $Last) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters

    if (-not $Raw) {
        return Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    }

    $arguments += '--json'
    $response = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $response = $response | ConvertFrom-Json
    if ($response.status -ne 0) {
        throw "Error retrieving log: $($response.message)"
    }
    $logs = ""
    foreach ($log in $response.result.log) {
        $logs += $log + "`n"
    }
    return $logs.TrimEnd("`n")
}

function Export-SalesforceDebugLogs {
    <#
    .SYNOPSIS
    Saves the most recent debug logs to files.

    .DESCRIPTION
    Lists the logs with Select-SalesforceDebugLogs, keeps the first -Limit of them and writes each one with Get-SalesforceDebugLogs to <log id>.log in the output folder, with a progress bar. Existing files with the same name are overwritten.

    .PARAMETER Limit
    How many logs to save, taken from the start of the list the CLI returns. Default 50. Default: 50.

    .PARAMETER OutputFolder
    Folder to write the .log files to. It must exist. Defaults to the current folder.

    .PARAMETER TargetOrg
    Username or alias of the org to read the logs from. If omitted, the Salesforce CLI uses the default target org.

    .EXAMPLE
    Export-SalesforceDebugLogs -Limit 5 -OutputFolder .\logs -TargetOrg dev1
    Save the five newest logs.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Get-SalesforceDebugLogs, Select-SalesforceDebugLogs. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][int] $Limit = 50,
        [Parameter(Mandatory = $false)][string] $OutputFolder = $null,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if (($OutputFolder -eq $null) -or ($OutputFolder -eq "") ) {
        $currentFolder = (Get-Location).Path
        $OutputFolder = $currentFolder
    }
    if ((Test-Path -Path $OutputFolder) -eq $false) {
        throw "Folder $OutputFolder does not exist"
    }
    Write-Verbose "Output Folder: $OutputFolder"

    $logs = Select-SalesforceDebugLogs -TargetOrg $TargetOrg | Select-Object -First $Limit
    if (-not $logs -or (($logs | Measure-Object).Count -eq 0)) {
        Write-Verbose "No Logs"
        return
    }

    $logsCount = ($logs | Measure-Object).Count
    $i = 0
    foreach ($log in $logs) {
        $fileName = $log.Id + ".log"
        $filePath = Join-Path -Path $OutputFolder -ChildPath $fileName
        Write-Verbose "Exporting file: $filePath"
        Get-SalesforceDebugLogs -LogId $log.Id -Raw -TargetOrg $TargetOrg | Out-File -FilePath $filePath
        $i = $i + 1
        $percentCompleted = ($i / $logsCount) * 100
        Write-Progress -Activity "Export Salesforce Debug Logs" -Status "Completed $fileName" -PercentComplete $percentCompleted
    }
}

function Convert-SalesforceDebugLog {
    <#
    .SYNOPSIS
    Converts the text of a debug log into one object per line (in development).

    .DESCRIPTION
    Does not use the Salesforce CLI. Pipe in the text of a log, for example from Get-SalesforceDebugLogs -Raw; the first (header) line is skipped and each remaining line is split on | into DateTime, LogType and, when present, SubType and Detail. It writes a warning that it is still in development, so the properties may change.

    .PARAMETER Log
    The log text to convert. Accepts pipeline input. Required.

    .EXAMPLE
    Get-SalesforceDebugLogs -Last 1 -Raw -TargetOrg dev1 | Convert-SalesforceDebugLog | Select-Object -First 20
    The first twenty log lines as objects.

    .NOTES
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
        [Parameter(ValueFromPipeline, Mandatory = $true)][string] $Log
    )

    begin {
        Write-Warning "Function still in Development"
    }

    process {
        $results = @()
        $lines = ($Log -split "`r?`n") | Select-Object -Skip 1 # Skip Header
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $statements = $line.Split('|')

            $result = New-Object -TypeName PSObject
            $dt = if ($statements.Count -ge 1) { ($statements[0]).Trim() } else { $null }
            $lt = if ($statements.Count -ge 2) { ($statements[1]).Trim() } else { $null }
            $st = if ($statements.Count -ge 3) { ($statements[2]).Trim() } else { $null }
            $de = if ($statements.Count -ge 4) { ($statements[3]).Trim() } else { $null }
            if ($dt -eq 'NULL') { $dt = $null }
            if ($lt -eq 'NULL') { $lt = $null }
            if ($st -eq 'NULL') { $st = $null }
            if ($de -eq 'NULL') { $de = $null }
            $result | Add-Member -MemberType NoteProperty -Name 'DateTime' -Value $dt
            $result | Add-Member -MemberType NoteProperty -Name 'LogType' -Value $lt
            if (($null -ne $st) -and ($st -ne '')) { $result | Add-Member -MemberType NoteProperty -Name 'SubType' -Value $st }
            if (($null -ne $de) -and ($de -ne '')) { $result | Add-Member -MemberType NoteProperty -Name 'Detail' -Value $de }
            $results += $result
        }
        return $results
    }
}

#endregion

#region Debug Logging

function Enable-SalesforceDebugLogging {
    <#
    .SYNOPSIS
    Turns on debug logging for a user, Apex class or Apex trigger by creating a trace flag.

    .DESCRIPTION
    Runs sf apex trace create. Identify what to trace with one of -TracedEntityId, -Username, -ApexClass or -ApexTrigger; the last three are looked up with a SOQL query first and the cmdlet stops if no record, or more than one, matches. -DebugLevel names an existing debug level. The trace flag stays until it expires or you remove it with Disable-SalesforceDebugLogging.

    .PARAMETER TracedEntityId
    ID of the user, Apex class, or Apex trigger to trace. Passed to sf as --traced-entity-id. Required in the Id parameter set.

    .PARAMETER Username
    User name of the user to trace. psfdx looks up the user's ID and passes it as --traced-entity-id. Required in the Username parameter set.

    .PARAMETER ApexClass
    Name of the Apex class to trace. psfdx looks up its ID and passes it as --traced-entity-id. Required in the ApexClass parameter set.

    .PARAMETER ApexTrigger
    Name of the Apex trigger to trace. psfdx looks up its ID and passes it as --traced-entity-id. Required in the ApexTrigger parameter set.

    .PARAMETER DebugLevel
    Developer name of an existing debug level to apply. Passed to sf as --debug-level. Required.

    .PARAMETER LogType
    Type of trace flag to create. Passed to sf as --log-type. Valid values: DEVELOPER_LOG, USER_DEBUG.

    .PARAMETER Duration
    Duration, in minutes, before the trace flag expires. Maximum is 1440 (24 hours). Passed to sf as --duration. Range: 1 to 1440.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Enable-SalesforceDebugLogging -Username me@example.com -DebugLevel SFDC_DevConsole -Duration 60 -TargetOrg dev1
    Trace one user for an hour.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf apex trace create (plugin @salesforce/plugin-apex)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TracedEntityId = --traced-entity-id; -DebugLevel = --debug-level; -LogType = --log-type; -Duration = --duration; -TargetOrg = --target-org.
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
    [CmdletBinding(DefaultParameterSetName = 'Id')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Id')][string] $TracedEntityId,
        [Parameter(Mandatory = $true, ParameterSetName = 'Username')][string] $Username,
        [Parameter(Mandatory = $true, ParameterSetName = 'ApexClass')][string] $ApexClass,
        [Parameter(Mandatory = $true, ParameterSetName = 'ApexTrigger')][string] $ApexTrigger,
        [Parameter(Mandatory = $true)][string] $DebugLevel,
        [Parameter(Mandatory = $false)][ValidateSet('DEVELOPER_LOG', 'USER_DEBUG')][string] $LogType,
        [Parameter(Mandatory = $false)][ValidateRange(1, 1440)][int] $Duration,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters

    if ($PSCmdlet.ParameterSetName -ne 'Id') {
        switch ($PSCmdlet.ParameterSetName) {
            'Username'    { $object = 'User';        $field = 'Username'; $name = $Username }
            'ApexClass'   { $object = 'ApexClass';   $field = 'Name';     $name = $ApexClass }
            'ApexTrigger' { $object = 'ApexTrigger'; $field = 'Name';     $name = $ApexTrigger }
        }
        $query = "SELECT Id FROM $object WHERE $field = " + (ConvertTo-SalesforceSoqlLiteral -Value $name) + " LIMIT 2"
        $records = @(Select-SalesforceRecords -Query $query -TargetOrg $TargetOrg @commonParams)
        if ($records.Count -eq 0) {
            throw "No $object found with $field '$name'."
        }
        if ($records.Count -gt 1) {
            # e.g. a managed package class with the same name as a local one
            throw "More than one $object found with $field '$name'. Use -TracedEntityId instead."
        }
        $TracedEntityId = $records[0].Id
        Write-Verbose "Resolved $object '$name' to $TracedEntityId"
    }

    $arguments = @('apex', 'trace', 'create', '--traced-entity-id', $TracedEntityId)
    $arguments += @('--debug-level', $DebugLevel)
    if ($LogType) { $arguments += @('--log-type', $LogType) }
    if ($Duration) { $arguments += @('--duration', $Duration) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDebugLogging {
    <#
    .SYNOPSIS
    Lists the trace flags that turn on debug logging.

    .DESCRIPTION
    Runs sf apex trace list and returns one object per trace flag. Pipe them to Disable-SalesforceDebugLogging to remove them.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDebugLogging -TargetOrg dev1
    Active trace flags.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf apex trace list (plugin @salesforce/plugin-apex)
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
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $arguments = @('apex', 'trace', 'list')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Disable-SalesforceDebugLogging {
    <#
    .SYNOPSIS
    Deletes a trace flag to stop debug logging (sf apex trace delete).

    .DESCRIPTION
    -TraceId can come from the pipeline: a trace flag from Get-SalesforceDebugLogging is used through its Id. Each flag is confirmed on its own,
    so -WhatIf previews every delete, and an org with no trace flags deletes nothing.

    .PARAMETER TraceId
    ID of the trace flag to delete. Passed to sf as --trace-flag-id. Required. Alias: Id, TraceFlagId. Accepts input from the pipeline by property name.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDebugLogging -TargetOrg myorg | Disable-SalesforceDebugLogging -TargetOrg myorg -WhatIf

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf apex trace delete (plugin @salesforce/plugin-apex)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TraceId = --trace-flag-id; -TargetOrg = --target-org.
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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)][Alias('Id', 'TraceFlagId')][string] $TraceId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    process {
        $arguments = @('apex', 'trace', 'delete', '--trace-flag-id', $TraceId)
        if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
        $arguments += '--json'
        $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
        $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
        if ($PSCmdlet.ShouldProcess($TraceId, 'Disable debug logging (delete trace flag)')) {
            $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
            Show-SalesforceResult -Result $result
        }
    }
}

#endregion

#region Flows

function Get-SalesforceFlowInterviews {
    <#
    .SYNOPSIS
    Lists flow interviews, for example the ones that failed.

    .DESCRIPTION
    Runs sf data query on FlowInterview (Id, CreatedDate, InterviewLabel, InterviewStatus, Error) filtered by status and optional date, newest first. Values are escaped as SOQL literals.

    .PARAMETER Type
    Interview status to list: Error, Paused, Running, Completed, VersionPaused, Autosaved, Expired, or All (the default). Default: All. Valid values: Error, Paused, Running, Completed, VersionPaused, Autosaved, Expired, All.

    .PARAMETER After
    Only interviews created at or after this time.

    .PARAMETER Limit
    SOQL query to execute. Passed to sf as --query. Default: 200.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceFlowInterviews -Type Error -After (Get-Date).AddDays(-1) -TargetOrg prod
    Flow errors in the last day.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data query (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Limit = --query; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][ValidateSet('Error','Paused','Running', 'Completed', 'VersionPaused', 'Autosaved', 'Expired', 'All')] [string] $Type = 'All',
        [Parameter(Mandatory = $false)][datetime] $After,
        [Parameter(Mandatory = $false)][int] $Limit = 200,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    # Build SOQL
    $query = ""
    $query += "SELECT Id, CreatedDate, InterviewLabel, InterviewStatus, Error "
    $query += "FROM FlowInterview "
    if ($Type -eq 'All') {
        $InterviewStatus = "'Error','Paused','Running','Completed','VersionPaused','Autosaved','Expired'"
    } else {
        $InterviewStatus = ConvertTo-SalesforceSoqlLiteral -Value $Type
    }
    $query += "WHERE InterviewStatus IN ($InterviewStatus) "
    if ($After) {
        $afterIso = ConvertTo-SalesforceSoqlDateTime -Value $After
        $query += "AND CreatedDate >= $afterIso "
    }
    $query += "ORDER BY CreatedDate DESC "
    $query += "LIMIT $Limit"

    # Execute via sf data query
    $arguments = @('data', 'query', '--query', $query, '--result-format', 'json')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $raw = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $raw -ReturnRecords
}

#endregion

#region Logins

function Get-SalesforceLoginHistory {
    <#
    .SYNOPSIS
    Lists login history records, newest first.

    .DESCRIPTION
    Runs sf data query on LoginHistory (Id, LoginTime, UserId, SourceIp, Application, Status). The user filter is applied through a subquery on User. Values are escaped as SOQL literals.

    .PARAMETER After
    Only logins at or after this time.

    .PARAMETER Before
    Only logins at or before this time.

    .PARAMETER Username
    Only this user name.

    .PARAMETER Limit
    SOQL query to execute. Passed to sf as --query.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceLoginHistory -Username me@example.com -Limit 20 -TargetOrg prod
    The last twenty logins of one user.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data query (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Limit = --query; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.
    Also calls these psfdx cmdlets: Get-SalesforceUsers.

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
        [Parameter(Mandatory = $false)][datetime] $After,
        [Parameter(Mandatory = $false)][datetime] $Before,
        [Parameter(Mandatory = $false)][string] $Username,
        [Parameter(Mandatory = $false)][int] $Limit,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    # Build SOQL for LoginHistory
    $query = "SELECT Id, LoginTime, UserId, SourceIp, Application, Status FROM LoginHistory"
    $conditions = @()
    if ($After)    { $conditions += ("LoginTime >= " + (ConvertTo-SalesforceSoqlDateTime -Value $After)) }
    if ($Before)   { $conditions += ("LoginTime <= " + (ConvertTo-SalesforceSoqlDateTime -Value $Before)) }
    # LoginHistory has no Username column, so filter through a User subquery on UserId
    if ($Username) { $conditions += ("UserId IN (SELECT Id FROM User WHERE Username = " + (ConvertTo-SalesforceSoqlLiteral -Value $Username) + ")") }
    if ($conditions.Count -gt 0) { $query += (" WHERE " + ($conditions -join " AND ")) }
    $query += " ORDER BY LoginTime DESC"
    if ($Limit -gt 0) { $query += " LIMIT $Limit" }

    # Query LoginHistory
    $arguments = @('data', 'query', '--query', $query, '--result-format', 'json')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $raw = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $records = Show-SalesforceResult -Result $raw -ReturnRecords

    # No LoginHistory records found
    if ((-not $records) -or (($records | Measure-Object).Count -eq 0)) {
        Write-Verbose "No LoginHistory records found"
        return @()
    }

    $userParams = @{ TargetOrg = $TargetOrg }
    if ($Username) {
        $userParams.Username = $Username
        $userParams.Limit = 1
    }
    $users = Get-SalesforceUsers @userParams
    foreach ($record in $records) {
        $user = $null
        if ($users) {
            $user = $users | Where-Object { ($_.Id -eq $record.UserId) -or ($_.Username -eq $record.Username) } | Select-Object -First 1
        }
        if ($user) {
            foreach ($prop in 'Username','Name','Email','IsActive','LastLoginDate') {
                $userProperty = $user.PSObject.Properties[$prop]
                if ($userProperty) {
                    $record | Add-Member -NotePropertyName $prop -NotePropertyValue $userProperty.Value -Force
                }
            }
        } elseif (-not $record.PSObject.Properties['Username']) {
            $record | Add-Member -NotePropertyName Username -NotePropertyValue $null -Force
        }
    }

    # Already filtered in SOQL when -Username is provided
    return $records
}

function Get-SalesforceLoginFailures {
    <#
    .SYNOPSIS
    Lists login attempts that did not succeed.

    .DESCRIPTION
    Calls Get-SalesforceLoginHistory with the same filters and keeps the rows whose Status is not Success. Returns an empty array when there are none.

    .PARAMETER After
    Only logins at or after this time.

    .PARAMETER Before
    Only logins at or before this time.

    .PARAMETER Limit
    Maximum number of login history rows to read before filtering.

    .PARAMETER Username
    Only this user name.

    .PARAMETER TargetOrg
    Username or alias of the org. If omitted, the Salesforce CLI uses the default target org.

    .EXAMPLE
    Get-SalesforceLoginFailures -After (Get-Date).AddDays(-1) -TargetOrg prod
    Failed logins in the last day.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Get-SalesforceLoginHistory. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][datetime] $After,
        [Parameter(Mandatory = $false)][datetime] $Before,
        [Parameter(Mandatory = $false)][int] $Limit,
        [Parameter(Mandatory = $false)][string] $Username,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $records = Get-SalesforceLoginHistory @PSBoundParameters
    if ((-not $records) -or (($records | Measure-Object).Count -eq 0)) {
        return @()
    }
    $records | Where-Object { $_.Status -ne 'Success' }
}

#endregion

#region Event Monitoring

function New-SalesforceEventFileQuery {
    # One place that builds the EventLogFile query for Select-SalesforceEventFiles and Export-SalesforceEventFiles.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $EventType,
        [Parameter(Mandatory = $false)][Nullable[datetime]] $After,
        [Parameter(Mandatory = $false)][Nullable[datetime]] $Before,
        [Parameter(Mandatory = $false)][int] $Limit
    )
    $query = "SELECT Id, EventType, LogDate, LogFileLength, Sequence, Interval, CreatedDate"
    $query += " FROM EventLogFile"
    $where = @()
    if ($EventType) { $where += ("EventType = " + (ConvertTo-SalesforceSoqlLiteral -Value $EventType)) }
    if ($After)     { $where += ("LogDate >= " + (ConvertTo-SalesforceSoqlDateTime -Value $After)) }
    if ($Before)    { $where += ("LogDate <= " + (ConvertTo-SalesforceSoqlDateTime -Value $Before)) }
    if ($where.Count -gt 0) { $query += (" WHERE " + ($where -join " AND ")) }
    $query += " ORDER BY LogDate DESC"
    if ($Limit -gt 0) { $query += " LIMIT $Limit" }
    return $query
}

function Select-SalesforceEventFiles {
    <#
    .SYNOPSIS
    Lists Event Monitoring log files.

    .DESCRIPTION
    Runs sf data query on EventLogFile (Id, EventType, LogDate, LogFileLength, Sequence, Interval, CreatedDate), newest log date first, with optional filters. Values are escaped as SOQL literals.

    .PARAMETER EventType
    Only this event type, for example Login or ApexExecution. Passed to sf as --query.

    .PARAMETER After
    Only files with a LogDate at or after this time. Passed to sf as --query.

    .PARAMETER Before
    Only files with a LogDate at or before this time. Passed to sf as --query.

    .PARAMETER Limit
    Maximum number of files to return. Passed to sf as --query.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Select-SalesforceEventFiles -EventType Login -Limit 10 -TargetOrg prod
    The ten newest login files.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data query (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -EventType = --query; -After = --query; -Before = --query; -Limit = --query; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][string] $EventType,
        [Parameter(Mandatory = $false)][datetime] $After,
        [Parameter(Mandatory = $false)][datetime] $Before,
        [Parameter(Mandatory = $false)][int] $Limit,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    # Build SOQL for Event Monitoring (EventLogFile)
    $query = New-SalesforceEventFileQuery -EventType $EventType -After $After -Before $Before -Limit $Limit

    $arguments = @('data', 'query', '--query', $query, '--result-format', 'json')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $raw = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $raw -ReturnRecords
}

function Assert-SalesforceEventFileId {
    # Private: an EventLogFile ID is 15 or 18 letters and digits.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Id
    )

    if ($Id -notmatch '^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z') {
        throw "Event log file ID '$Id' is not a valid 15 or 18 character Salesforce ID."
    }
}

function Get-SalesforceEventFile {
    <#
    .SYNOPSIS
    Downloads the content of one Event Monitoring log file.

    .DESCRIPTION
    Finds the newest REST API version of the org, then runs sf api request rest on /services/data/<version>/sobjects/EventLogFile/<Id>/Logfile and returns the CSV text. The ID must be a 15 or 18 character Salesforce ID.

    .PARAMETER Id
    ID of the EventLogFile record. Required.

    .PARAMETER TargetOrg
    Username or alias of the org. If omitted, the Salesforce CLI uses the default target org. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceEventFile -Id 0AT000000000001AAA -TargetOrg prod
    The CSV of that file.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf api request rest (plugin @salesforce/plugin-api)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --file, --header, --include, --stream-to-file
      Values psfdx cannot pass: --method POST, PUT, HEAD, DELETE, OPTIONS, TRACE
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.
    Also calls these psfdx cmdlets: Get-SalesforceLatestApiVersion.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-api

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Id,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    Assert-SalesforceEventFileId -Id $Id
    $apiVersion = (Get-SalesforceLatestApiVersion -TargetOrg $TargetOrg)
    $arguments = @('api', 'request', 'rest', "/services/data/$apiVersion/sobjects/EventLogFile/$Id/Logfile")
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

function Export-SalesforceEventFile {
    <#
    .SYNOPSIS
    Downloads one Event Monitoring log file and saves it as a CSV.

    .DESCRIPTION
    Gets the file with Get-SalesforceEventFile and writes it to <Id>.csv in the output folder. The ID must be a 15 or 18 character Salesforce ID, so it cannot point outside the folder.

    .PARAMETER Id
    ID of the EventLogFile record. Required.

    .PARAMETER OutputFolder
    Folder to write the CSV to. It must exist. Defaults to the current folder.

    .PARAMETER TargetOrg
    Username or alias of the org. If omitted, the Salesforce CLI uses the default target org.

    .EXAMPLE
    Export-SalesforceEventFile -Id 0AT000000000001AAA -OutputFolder .\events -TargetOrg prod
    Save one event log file.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Get-SalesforceEventFile. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Id,
        [Parameter(Mandatory = $false)][string] $OutputFolder = $null,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    # The ID becomes part of the file name and of the REST path, so it must be an ID, not a path (..\x, a/b).
    Assert-SalesforceEventFileId -Id $Id
    if (($OutputFolder -eq $null) -or ($OutputFolder -eq "")) {
        $OutputFolder = (Get-Location).Path
    }
    if ((Test-Path -Path $OutputFolder) -eq $false) {
        throw "Folder $OutputFolder does not exist"
    }

    $record = Get-SalesforceEventFile -Id $Id -TargetOrg $TargetOrg
    if (-not $record) {
        Write-Verbose "No EventLogFile record found for Id $Id"
        return
    }

    $fileName = "$Id.csv"
    $filePath = Join-Path -Path $OutputFolder -ChildPath $fileName
    $record | Out-File -FilePath $filePath -Encoding utf8
    Write-Verbose ("Exported EventLogFile record to: " + $filePath)
}

function Export-SalesforceEventFiles {
    <#
    .SYNOPSIS
    Downloads several Event Monitoring log files as CSVs.

    .DESCRIPTION
    Finds files with Select-SalesforceEventFiles using the filters you give, then saves each one with Export-SalesforceEventFile, with a progress bar. See Select-SalesforceEventFiles for how the filters work.

    .PARAMETER EventType
    SOQL query to execute. Passed to sf as --query.

    .PARAMETER After
    SOQL query to execute. Passed to sf as --query.

    .PARAMETER Before
    SOQL query to execute. Passed to sf as --query.

    .PARAMETER Limit
    SOQL query to execute. Passed to sf as --query. Default: 200.

    .PARAMETER OutputFolder
    Folder to write the CSV files to. It must exist. Defaults to the current folder.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Export-SalesforceEventFiles -EventType Login -After (Get-Date).AddDays(-7) -OutputFolder .\events -TargetOrg prod
    Last week's login event files.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data query (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -EventType = --query; -After = --query; -Before = --query; -Limit = --query; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.
    Also calls these psfdx cmdlets: Export-SalesforceEventFile.

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
        [Parameter(Mandatory = $false)][string] $EventType,
        [Parameter(Mandatory = $false)][datetime] $After,
        [Parameter(Mandatory = $false)][datetime] $Before,
        [Parameter(Mandatory = $false)][int] $Limit = 200,
        [Parameter(Mandatory = $false)][string] $OutputFolder = $null,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if (($OutputFolder -eq $null) -or ($OutputFolder -eq "")) {
        $OutputFolder = (Get-Location).Path
    }
    if ((Test-Path -Path $OutputFolder) -eq $false) {
        throw "Folder $OutputFolder does not exist"
    }

    # Build SOQL for Event Monitoring (EventLogFile)
    $query = New-SalesforceEventFileQuery -EventType $EventType -After $After -Before $Before -Limit $Limit

    $arguments = @('data', 'query', '--query', $query, '--result-format', 'json')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $raw = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $records = Show-SalesforceResult -Result $raw -ReturnRecords
    if (-not $records -or (($records | Measure-Object).Count -eq 0)) {
        Write-Verbose "No EventLogFile records found"
        return
    }

    $total = ($records | Measure-Object).Count
    $i = 0
    foreach ($record in $records) {
        $i++
        Export-SalesforceEventFile -Id $record.Id -OutputFolder $OutputFolder -TargetOrg $TargetOrg
        $percent = [int](($i / $total) * 100)
        Write-Progress -Activity "Export Salesforce Event Files" -Status "Exported $i of $total" -PercentComplete $percent
    }
    Write-Progress -Activity "Export Salesforce Event Files" -Completed
    Write-Verbose ("Exported $i EventLogFile record(s) to: " + $OutputFolder)
}

#endregion

#region Utilities

function Out-Notepad {
    <#
    .SYNOPSIS
    Shows text in Notepad (Windows only).

    .DESCRIPTION
    Does not use the Salesforce CLI. Pipe text in; it is written to a new temporary file that Notepad opens. The file is not deleted afterwards, so remove it if the text is sensitive. On other systems it does nothing.

    .PARAMETER Content
    The text to show. Accepts pipeline input. Required.

    .EXAMPLE
    Get-SalesforceDebugLogs -Last 1 -Raw -TargetOrg dev1 | Out-Notepad
    Read the newest log in Notepad.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It works locally in PowerShell and .NET.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param([Parameter(ValueFromPipeline, Mandatory = $true)][string] $Content)

    process {
        # $IsWindows does not exist on Windows PowerShell 5.1, where it would silently
        # evaluate to $null and skip the launch entirely.
        if (-not (Test-SalesforceIsWindows)) {
            Write-Verbose "Out-Notepad is only supported on Windows"
            return
        }
        $filename = New-TemporaryFile
        $Content | Out-File -FilePath $filename -Encoding utf8
        Start-Process -FilePath 'notepad' -ArgumentList $filename | Out-Null
    }
}

function Test-SalesforceIsWindows {
    [CmdletBinding()]
    Param()
    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
}

#endregion
