. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Invoke-Salesforce.ps1')
. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Show-SalesforceResult.ps1')

#region Debug Logs

function Watch-SalesforceDebugLogs {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $DebugLevel,
        [Parameter(Mandatory = $false)][switch] $SkipTraceFlag,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $command = "sf apex log tail"
    if ($DebugLevel) { $command += " --debug-level $DebugLevel" }
    if ($SkipTraceFlag) { $command += " --skip-trace-flag" }
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    $command += " --color"
    return Invoke-Salesforce -Command $command
}

function Select-SalesforceDebugLogs {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $command = "sf apex log list"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDebugLogs {
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

    $command = "sf apex log get"
    if ($OutputDir) {
        if ((Test-Path -Path $OutputDir) -eq $false) {
            throw "Folder $OutputDir does not exist"
        }
        $command += " --output-dir `"$OutputDir`""
    }
    if ($LogId) { $command += " --log-id $LogId" }
    if ($Last) { $command += " --number $Last" }
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }

    if (-not $Raw) {
        return Invoke-Salesforce -Command $command
    }

    $command += " --json"
    $response = Invoke-Salesforce -Command $command
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
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Mandatory = $true)][Alias('FullName','Path')][string[]] $Log
    )

    begin {
        $parseContent = {
        param([string] $Content)

        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @()
        }

        $lines = @($Content -split "`r?`n")
        $headerIndex = -1
        for ($i = 0; $i -lt $lines.Length; $i++) {
            $candidate = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if ($candidate -notlike '*|*') { continue }
            if ($candidate.TrimStart() -notmatch '^[0-9]') {
                $headerIndex = $i
                break
            }
        }

        $columnNames = @()
        $startIndex = 0
        $headerSignature = $null
        if ($headerIndex -ge 0) {
            $headerParts = $lines[$headerIndex].Split('|')
            for ($i = 0; $i -lt $headerParts.Count; $i++) {
                $name = $headerParts[$i].Trim()
                if ([string]::IsNullOrEmpty($name)) {
                    $name = "Column$($i + 1)"
                }
                $columnNames += $name
            }
            $headerSignature = ($columnNames -join '|')
            $startIndex = $headerIndex + 1
        } else {
            $columnNames = @('DateTime', 'LogType', 'SubType', 'Detail')
            for ($i = 0; $i -lt $lines.Length; $i++) {
                if ($lines[$i] -like '*|*') {
                    $startIndex = $i
                    break
                }
            }
        }

        if ($columnNames.Count -eq 0) {
            return @()
        }

        $results = @()
        $detailColumn = $columnNames[$columnNames.Count - 1]
        $current = $null

        for ($i = $startIndex; $i -lt $lines.Length; $i++) {
            $line = $lines[$i]
            if ($headerIndex -ge 0 -and $i -eq $headerIndex) { continue }
            if ($line -eq $null) { continue }

            if ([string]::IsNullOrWhiteSpace($line)) {
                if ($current -ne $null) {
                    $existing = $current.PSObject.Properties[$detailColumn].Value
                    if (-not [string]::IsNullOrEmpty($existing)) {
                        $current | Add-Member -MemberType NoteProperty -Name $detailColumn -Value ($existing + "`n") -Force
                    }
                }
                continue
            }

            if ($line -notlike '*|*') {
                if ($current -ne $null) {
                    $existing = $current.PSObject.Properties[$detailColumn].Value
                    if ([string]::IsNullOrEmpty($existing)) {
                        $newValue = $line
                    } else {
                        $newValue = "$existing`n$line"
                    }
                    $current | Add-Member -MemberType NoteProperty -Name $detailColumn -Value $newValue -Force
                }
                continue
            }

            $rawParts = $line.Split('|')
            if ($headerSignature -ne $null) {
                $normalizedHeader = ($rawParts | ForEach-Object { $_.Trim() }) -join '|'
                if ($normalizedHeader -eq $headerSignature) {
                    $current = $null
                    continue
                }
            }
            $normalized = @()
            if ($columnNames.Count -eq 1) {
                $normalized = @($line.Trim())
            } elseif ($rawParts.Count -ge $columnNames.Count) {
                for ($partIndex = 0; $partIndex -lt ($columnNames.Count - 1); $partIndex++) {
                    $normalized += $rawParts[$partIndex]
                }
                $normalized += ($rawParts[($columnNames.Count - 1)..($rawParts.Count - 1)] -join '|')
            } else {
                $normalized = @($rawParts)
                while ($normalized.Count -lt $columnNames.Count) {
                    $normalized += ''
                }
            }

            $record = [ordered]@{}
            for ($partIndex = 0; $partIndex -lt $columnNames.Count; $partIndex++) {
                $value = if ($partIndex -lt $normalized.Count) { $normalized[$partIndex] } else { $null }
                if ($null -ne $value) {
                    $value = $value.Trim()
                    if ($value -match '^(?i)null$') {
                        $value = $null
                    } elseif ($value -eq '') {
                        $value = $null
                    }
                }
                $record[$columnNames[$partIndex]] = $value
            }

            $current = [pscustomobject]$record
            $results += $current
        }

        foreach ($entry in $results) {
            if ($entry.PSObject.Properties[$detailColumn]) {
                $value = $entry.PSObject.Properties[$detailColumn].Value
                if ($value -is [string]) {
                    $trimmed = $value.TrimEnd("`r","`n")
                    if ($trimmed -ne $value) {
                        $entry | Add-Member -MemberType NoteProperty -Name $detailColumn -Value $trimmed -Force
                    }
                }
            }
        }

        return $results
    }
    }

    process {
        foreach ($item in @($Log)) {
            if ([string]::IsNullOrWhiteSpace($item)) { continue }

            $content = $item
            if ((Test-Path -LiteralPath $item) -and -not (Test-Path -LiteralPath $item -PathType Container)) {
                $content = Get-Content -LiteralPath $item -Raw
            }

            foreach ($parsed in & $parseContent $content) {
                $parsed
            }
        }
    }
}

#endregion

#region Flows

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

#endregion

#region Logins

function Get-SalesforceLoginHistory {
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
    if ($After)    { $conditions += ("LoginTime >= " + ($After.ToString('s') + 'Z')) }
    if ($Before)   { $conditions += ("LoginTime <= " + ($Before.ToString('s') + 'Z')) }
    if ($Username) { $conditions += ("Username = '" + ($Username -replace "'", "''") + "'") }
    if ($conditions.Count -gt 0) { $query += (" WHERE " + ($conditions -join " AND ")) }
    $query += " ORDER BY LoginTime DESC"
    if ($Limit -gt 0) { $query += " LIMIT $Limit" }

    # Query LoginHistory
    $command = "sf data query --query `"$query`" --result-format json"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    $raw = Invoke-Salesforce -Command $command
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

function Select-SalesforceEventFiles {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $EventType,
        [Parameter(Mandatory = $false)][datetime] $After,
        [Parameter(Mandatory = $false)][datetime] $Before,
        [Parameter(Mandatory = $false)][int] $Limit,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    # Build SOQL for Event Monitoring (EventLogFile)
    $query = "SELECT Id, EventType, LogDate, LogFileLength, Sequence, Interval, CreatedDate"
    $query += " FROM EventLogFile"
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

function Get-SalesforceEventFile {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Id,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $apiVersion = (Get-SalesforceLatestApiVersion -TargetOrg $TargetOrg)
    $command = "sf api request rest /services/data/$apiVersion/sobjects/EventLogFile/$Id/Logfile"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    Invoke-Salesforce -Command $command
}

function Export-SalesforceEventFile {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Id,
        [Parameter(Mandatory = $false)][string] $OutputFolder = $null,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

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
    $query = "SELECT Id, EventType, LogDate, LogFileLength, Sequence, Interval, CreatedDate"
    $query = " FROM EventLogFile"
    $where = @()
    if ($EventType) { $where += "EventType = '$EventType'" }
    if ($After)     { $where += ("LogDate >= " + ($After.ToString('s') + 'Z')) }
    if ($Before)    { $where += ("LogDate <= " + ($Before.ToString('s') + 'Z')) }
    if ($where.Count -gt 0) { $query += (" WHERE " + ($where -join " AND ")) }
    $query += " ORDER BY LogDate DESC"
    $query += " LIMIT $Limit"

    $command = "sf data query --query `"$query`" --result-format json"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }

    $raw = Invoke-Salesforce -Command $command
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
    [CmdletBinding()]
    Param([Parameter(ValueFromPipeline, Mandatory = $true)][string] $Content)
    $filename = New-TemporaryFile
    $Content | Out-File -FilePath $filename -Encoding utf8
    if ($IsWindows) {
        Start-Process -FilePath 'notepad' -ArgumentList $filename | Out-Null
    }
}

#endregion
