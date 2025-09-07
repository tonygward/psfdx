function Invoke-Sf {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string[]] $Command)
    Write-Verbose ($Command -join ' ')
    if ($Command.Length -eq 0) { throw 'No command specified' }
    $exe = $Command[0]
    $args = @()
    if ($Command.Length -gt 1) { $args = $Command[1..($Command.Length-1)] }
    return & $exe @args
}

function Show-SfResult {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][psobject] $Result)
    $result = $Result | ConvertFrom-Json
    if ($result.status -ne 0) {
        Write-Debug $result
        throw ($result.message)
    }
    return $result.result
}

function Watch-SalesforceLogs {
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
    return Invoke-Sf -Command $command
}

function Get-SalesforceLogs {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $command = @('sf','apex','log','list')
    if ($TargetOrg) { $command += @('--target-org', $TargetOrg) }
    $command += @('--json')
    $result = Invoke-Sf -Command $command
    return Show-SfResult -Result $result
}

function Get-SalesforceLog {
    [CmdletBinding(DefaultParameterSetName='ById')]
    Param(
        [Parameter(ParameterSetName='ById', Mandatory = $true)][string] $LogId,
        [Parameter(ParameterSetName='ByLast', Mandatory = $true)][switch] $Last,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if ($PSCmdlet.ParameterSetName -eq 'ByLast') {
        $LogId = (Get-SalesforceLogs -TargetOrg $TargetOrg | Sort-Object StartTime -Descending | Select-Object -First 1).Id
    }

    $command = @('sf','apex','log','get','--log-id', $LogId)
    if ($TargetOrg) { $command += @('--target-org', $TargetOrg) }
    $command += @('--json')
    $raw = Invoke-Sf -Command $command
    $parsed = Show-SfResult -Result $raw
    return $parsed.log
}

function Export-SalesforceLogs {
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

    $logs = Get-SalesforceLogs -TargetOrg $TargetOrg | Sort-Object -Property StartTime -Descending | Select-Object -First $Limit
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
        Get-SalesforceLog -LogId $log.Id -TargetOrg $TargetOrg | Out-File -FilePath $filePath -Encoding utf8
        $i = $i + 1
        $percentCompleted = ($i / $logsCount) * 100
        Write-Progress -Activity "Export Salesforce Logs" -Status "Completed $fileName" -PercentComplete $percentCompleted
    }
}

function Convert-SalesforceLog {
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

function Out-Notepad {
    [CmdletBinding()]
    Param([Parameter(ValueFromPipeline, Mandatory = $true)][string] $Content)
    $filename = New-TemporaryFile
    $Content | Out-File -FilePath $filename -Encoding utf8
    if ($IsWindows) {
        Start-Process -FilePath 'notepad' -ArgumentList $filename | Out-Null
    }
}
