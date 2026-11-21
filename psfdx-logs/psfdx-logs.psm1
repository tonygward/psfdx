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

#region Debug Logs

function Watch-SalesforceDebugLogs {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $DebugLevel,
        [Parameter(Mandatory = $false)][switch] $SkipTraceFlag,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('apex', 'log', 'tail')
    if ($DebugLevel) { $arguments += @('--debug-level', $DebugLevel) }
    if ($SkipTraceFlag) { $arguments += '--skip-trace-flag' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--color'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    return Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

function Select-SalesforceDebugLogs {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $arguments = @('apex', 'log', 'list')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
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

    $arguments = @('apex', 'log', 'get')
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
    .EXAMPLE
    Get-SalesforceDebugLogging -TargetOrg myorg | Disable-SalesforceDebugLogging -TargetOrg myorg -WhatIf
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
