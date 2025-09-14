. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Invoke-Salesforce.ps1')
. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Show-SalesforceResult.ps1')

function Watch-SalesforceDebugLogs {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $SkipTraceFlag,
        [Parameter(Mandatory = $false)][string] $DebugLevel
    )
    $command = @('sf','apex','log','tail')
    if ($TargetOrg) { $command += @('--target-org', $TargetOrg) }
    if ($SkipTraceFlag) { $command += @('--skip-trace-flag') }
    if ($DebugLevel) { $command += @('--debug-level', $DebugLevel) }
    $command += @('--color')
    return Invoke-Salesforce -Command $command
}

function Get-SalesforceDebugLogs {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $command = @('sf','apex','log','list')
    if ($TargetOrg) { $command += @('--target-org', $TargetOrg) }
    $command += @('--json')
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDebugLog {
    [CmdletBinding(DefaultParameterSetName='ById')]
    Param(
        [Parameter(ParameterSetName='ById', Mandatory = $true)][string] $LogId,
        [Parameter(ParameterSetName='ByLast', Mandatory = $true)][switch] $Last,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if ($PSCmdlet.ParameterSetName -eq 'ByLast') {
        $LogId = (Get-SalesforceDebugLogs -TargetOrg $TargetOrg | Sort-Object StartTime -Descending | Select-Object -First 1).Id
    }

    $command = @('sf','apex','log','get','--log-id', $LogId)
    if ($TargetOrg) { $command += @('--target-org', $TargetOrg) }
    $command += @('--json')
    $raw = Invoke-Salesforce -Command $command
    $parsed = Show-SalesforceResult -Result $raw
    return $parsed.log
}

function Export-SalesforceDebugLogs {
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
    if ((Test-Path -Path $OutputFolder) -eq $false) { throw "Folder $OutputFolder does not exist" }
    Write-Verbose "Output Folder: $OutputFolder"

    $logs = Get-SalesforceDebugLogs -TargetOrg $TargetOrg | Sort-Object -Property StartTime -Descending | Select-Object -First $Limit
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
        Get-SalesforceDebugLog -LogId $log.Id -TargetOrg $TargetOrg | Out-File -FilePath $filePath -Encoding utf8
        $i = $i + 1
        $percentCompleted = ($i / $logsCount) * 100
        Write-Progress -Activity "Export Salesforce Debug Logs" -Status "Completed $fileName" -PercentComplete $percentCompleted
    }
}

function Convert-SalesforceDebugLog {
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline, Mandatory = $true)][string] $Log
    )

    Write-Warning "Function still in Development"

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
        foreach ($v in @('dt','lt','st','de')) { if ((Get-Variable $v -ValueOnly) -eq 'NULL') { Set-Variable -Name $v -Value $null } }
        $result | Add-Member -MemberType NoteProperty -Name 'DateTime' -Value $dt
        $result | Add-Member -MemberType NoteProperty -Name 'LogType' -Value $lt
        if ($st -ne $null -and $st -ne '') { $result | Add-Member -MemberType NoteProperty -Name 'SubType' -Value $st }
        if ($de -ne $null -and $de -ne '') { $result | Add-Member -MemberType NoteProperty -Name 'Detail' -Value $de }
        $results += $result
    }
    return $results
}

function Get-SalesforceFlowInterviews {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidateSet('Error','Paused','Running', 'Completed', 'VersionPaused', 'Autosaved', 'Expired', 'All')] [string] $Type = 'All',
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
        $InterviewStatus = "'$Type'"
    }
    $query += "WHERE InterviewStatus IN ($InterviewStatus) "
    if ($After) {
        $afterIso = $After.ToString('s') + 'Z'
        $query += "AND CreatedDate >= $afterIso "
    }
    $query += "ORDER BY CreatedDate DESC "
    $query += "LIMIT $Limit"

    # Execute via sf data query
    $command = "sf data query --query `"$query`" --result-format json"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }

    $raw = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $raw -ReturnRecords
}

function Export-SalesforceEventFiles {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $EventType,
        [Parameter(Mandatory = $false)][datetime] $After,
        [Parameter(Mandatory = $false)][datetime] $Before,
        [Parameter(Mandatory = $false)][int] $Limit,
        [Parameter(Mandatory = $false)][string] $OutputFolder = $null,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if (($OutputFolder -eq $null) -or ($OutputFolder -eq "")) {
        $OutputFolder = (Get-Location).Path
    }
    if ((Test-Path -Path $OutputFolder) -eq $false) { throw "Folder $OutputFolder does not exist" }

    # Build SOQL for Event Monitoring (EventLogFile)
    $query = "SELECT Id, EventType, LogDate, LogFileLength, Sequence, Interval, CreatedDate FROM EventLogFile"
    $where = @()
    if ($EventType) { $where += "EventType = '$EventType'" }
    if ($After)     { $where += ("LogDate >= " + ($After.ToString('s') + 'Z')) }
    if ($Before)    { $where += ("LogDate <= " + ($Before.ToString('s') + 'Z')) }
    if ($where.Count -gt 0) { $query += (" WHERE " + ($where -join " AND ")) }
    $query += " ORDER BY LogDate DESC"
    if ($Limit -gt 0) { $query += " LIMIT $Limit" }

    $command = "sf data query --query `"$query`" --result-format json"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }

    $raw = Invoke-Salesforce -Command $command
    $records = Show-SalesforceResult -Result $raw -ReturnRecords
    if (-not $records -or (($records | Measure-Object).Count -eq 0)) {
        Write-Verbose "No EventLogFile records found"
        return
    }

    $fileName = "EventLogFile-" + (Get-Date -AsUTC).ToString('yyyyMMddTHHmmssZ') + ".csv"
    $filePath = Join-Path -Path $OutputFolder -ChildPath $fileName
    ($records | Select-Object -ExcludeProperty attributes | ConvertTo-Csv -NoTypeInformation) | Set-Content -Path $filePath -Encoding utf8
    Write-Verbose ("Exported EventLogFile records to: " + $filePath)
}

function Get-SalesforceEventLogFiles {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $EventType,
        [Parameter(Mandatory = $false)][datetime] $After,
        [Parameter(Mandatory = $false)][datetime] $Before,
        [Parameter(Mandatory = $false)][int] $Limit,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    # Build SOQL for Event Monitoring (EventLogFile)
    $query = "SELECT Id, EventType, LogDate, LogFileLength, Sequence, Interval, CreatedDate FROM EventLogFile"
    $where = @()
    if ($EventType) { $where += "EventType = '$EventType'" }
    if ($After)     { $where += ("LogDate >= " + ($After.ToString('s') + 'Z')) }
    if ($Before)    { $where += ("LogDate <= " + ($Before.ToString('s') + 'Z')) }
    if ($where.Count -gt 0) { $query += (" WHERE " + ($where -join " AND ")) }
    $query += " ORDER BY LogDate DESC"
    if ($Limit -gt 0) { $query += " LIMIT $Limit" }

    $command = "sf data query --query `"$query`" --result-format json"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }

    $raw = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $raw -ReturnRecords
}

function Out-Notepad {
    [CmdletBinding()]
    Param([Parameter(ValueFromPipeline, Mandatory = $true)][string] $Content)
    $filename = New-TemporaryFile
    $Content | Out-File -FilePath $filename -Encoding utf8
    if ($IsWindows) {
        Start-Process -FilePath 'notepad' -ArgumentList $filename | Out-Null
    }
}
