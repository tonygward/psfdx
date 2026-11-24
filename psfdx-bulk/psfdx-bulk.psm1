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

#region Bulk API 2.0

# Wraps `sf data export|import|update|upsert bulk`, their `resume` commands and `sf data bulk results`. Without -WaitMinutes the CLI
# creates the job and returns at once with a job ID; with it, the CLI polls and returns the counts. Each cmdlet returns a plain object.
#
# A job that finishes with failed rows, or fails or aborts, makes the CLI exit with an error. That error is rethrown as
# PsfdxBulkJobFailed, and its TargetObject holds JobId, State and Message, so a script can fetch the row-level results with
# Get-SalesforceBulkResult. Any other CLI error (no authorisation, a bad file, a bad flag) is thrown with the CLI's message.

function Export-SalesforceBulkData {
    <#
    .SYNOPSIS
    Exports the records of a SOQL query to a file with Bulk API 2.0 (sf data export bulk).

    .DESCRIPTION
    Give the query as -Query or -QueryFile (a file avoids line breaks, which the Windows CLI shim rejects as an argument). The query is
    passed to the CLI unchanged. Without -WaitMinutes the job is created and its JobId returned; finish it later with
    Resume-SalesforceBulkJob -Operation Export. With -WaitMinutes the cmdlet waits and returns TotalSize.

    .PARAMETER OutputFile
    File where records are written. Passed to sf as --output-file. Required.

    .PARAMETER Query
    SOQL query to execute. Passed to sf as --query.

    .PARAMETER QueryFile
    File that contains the SOQL query. Passed to sf as --query-file.

    .PARAMETER ResultFormat
    Format to write the results. Passed to sf as --result-format. Default: csv. Valid values: csv, json.

    .PARAMETER AllRows
    Include records that have been soft-deleted due to a merge or delete. By default, deleted records are not returned. Adds --all-rows.

    .PARAMETER ColumnDelimiter
    Column delimiter to be used when writing CSV output. Default is COMMA. Passed to sf as --column-delimiter. Valid values: BACKQUOTE, CARET, COMMA, PIPE, SEMICOLON, TAB.

    .PARAMETER LineEnding
    Line ending to be used when writing CSV output. Default value on Windows is is `CRLF`; on macOS and Linux it's `LR`. Passed to sf as --line-ending. Valid values: LF, CRLF.

    .PARAMETER WaitMinutes
    Time to wait for the command to finish, in minutes. Passed to sf as --wait. Default: 0. Range: 0 to 1440.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Export-SalesforceBulkData -Query 'SELECT Id, Name FROM Account' -OutputFile .\accounts.csv -WaitMinutes 10 -TargetOrg myorg

    .EXAMPLE
    $job = Export-SalesforceBulkData -QueryFile .\big.soql -OutputFile .\big.csv -TargetOrg myorg; Resume-SalesforceBulkJob -Operation Export -JobId $job.JobId

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data export bulk (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -OutputFile = --output-file; -Query = --query; -QueryFile = --query-file; -ResultFormat = --result-format; -AllRows = --all-rows; -ColumnDelimiter = --column-delimiter; -LineEnding = --line-ending; -WaitMinutes = --wait; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][string] $OutputFile,
        [Parameter(Mandatory = $false)][string] $Query,
        [Parameter(Mandatory = $false)][string] $QueryFile,
        [Parameter(Mandatory = $false)][ValidateSet('csv', 'json')][string] $ResultFormat = 'csv',
        [Parameter(Mandatory = $false)][switch] $AllRows,
        [Parameter(Mandatory = $false)][ValidateSet('BACKQUOTE', 'CARET', 'COMMA', 'PIPE', 'SEMICOLON', 'TAB')][string] $ColumnDelimiter,
        [Parameter(Mandatory = $false)][ValidateSet('LF', 'CRLF')][string] $LineEnding,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $hasQuery = -not [string]::IsNullOrWhiteSpace($Query)
    $hasQueryFile = -not [string]::IsNullOrWhiteSpace($QueryFile)
    if ($hasQuery -eq $hasQueryFile) { throw 'Give exactly one of -Query and -QueryFile.' }
    if ($hasQueryFile -and -not (Test-Path -LiteralPath $QueryFile -PathType Leaf)) { throw "Query file '$QueryFile' does not exist." }
    $outputParent = Split-Path -Path $OutputFile -Parent
    if ($outputParent -and -not (Test-Path -LiteralPath $outputParent -PathType Container)) { throw "Output directory '$outputParent' does not exist." }

    $arguments = @('data', 'export', 'bulk')
    if ($hasQuery) { $arguments += @('--query', $Query) } else { $arguments += @('--query-file', $QueryFile) }
    $arguments += @('--output-file', $OutputFile, '--result-format', $ResultFormat)
    if ($AllRows) { $arguments += '--all-rows' }
    if ($ColumnDelimiter) { $arguments += @('--column-delimiter', $ColumnDelimiter) }
    if ($LineEnding) { $arguments += @('--line-ending', $LineEnding) }
    if ($WaitMinutes -gt 0) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data export bulk'
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation 'Export'
}

function Import-SalesforceBulkData {
    <#
    .SYNOPSIS
    Inserts the rows of a CSV file with Bulk API 2.0 (sf data import bulk).

    .DESCRIPTION
    Creates records. Asks for confirmation only when $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. Without
    -WaitMinutes the job is created and its JobId returned; with it the cmdlet waits and returns the counts. A job with failed rows
    throws PsfdxBulkJobFailed (see Get-SalesforceBulkResult for the row results).

    .PARAMETER File
    CSV file that contains the Salesforce object records you want to import. Passed to sf as --file. Required.

    .PARAMETER Object
    API name of the Salesforce object, either standard or custom, into which you're importing records. Passed to sf as --sobject. Required.

    .PARAMETER ColumnDelimiter
    Column delimiter used in the CSV file. Passed to sf as --column-delimiter. Valid values: BACKQUOTE, CARET, COMMA, PIPE, SEMICOLON, TAB.

    .PARAMETER LineEnding
    Line ending used in the CSV file. Default value on Windows is `CRLF`; on macOS and Linux it's `LF`. Passed to sf as --line-ending. Valid values: LF, CRLF.

    .PARAMETER WaitMinutes
    Time to wait for the command to finish, in minutes. Passed to sf as --wait. Default: 0. Range: 0 to 1440.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Import-SalesforceBulkData -File '.\new accounts.csv' -Object Account -WaitMinutes 10 -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data import bulk (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -File = --file; -Object = --sobject; -ColumnDelimiter = --column-delimiter; -LineEnding = --line-ending; -WaitMinutes = --wait; -TargetOrg = --target-org.
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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $File,
        [Parameter(Mandatory = $true)][string] $Object,
        [Parameter(Mandatory = $false)][ValidateSet('BACKQUOTE', 'CARET', 'COMMA', 'PIPE', 'SEMICOLON', 'TAB')][string] $ColumnDelimiter,
        [Parameter(Mandatory = $false)][ValidateSet('LF', 'CRLF')][string] $LineEnding,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $objectName = ConvertTo-SalesforceSoqlIdentifier -Value $Object
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "CSV file '$File' does not exist." }

    $arguments = @('data', 'import', 'bulk', '--file', $File, '--sobject', $objectName)
    if ($ColumnDelimiter) { $arguments += @('--column-delimiter', $ColumnDelimiter) }
    if ($LineEnding) { $arguments += @('--line-ending', $LineEnding) }
    if ($WaitMinutes -gt 0) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess((Get-SalesforceBulkTargetLabel -Object $objectName -File $File -TargetOrg $TargetOrg), 'Bulk insert')) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data import bulk'
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation 'Import' -Object $objectName
}

function Update-SalesforceBulkData {
    <#
    .SYNOPSIS
    Updates records from the rows of a CSV file with Bulk API 2.0 (sf data update bulk).

    .DESCRIPTION
    The CSV needs an Id column. Asks for confirmation only when $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call.
    Results are as for Import-SalesforceBulkData.

    .PARAMETER File
    CSV file that contains the Salesforce object records you want to update. Passed to sf as --file. Required.

    .PARAMETER Object
    API name of the Salesforce object, either standard or custom, which you are updating. Passed to sf as --sobject. Required.

    .PARAMETER ColumnDelimiter
    Column delimiter used in the CSV file. Passed to sf as --column-delimiter. Valid values: BACKQUOTE, CARET, COMMA, PIPE, SEMICOLON, TAB.

    .PARAMETER LineEnding
    Line ending used in the CSV file. Default value on Windows is `CRLF`; on macOS and Linux it's `LF`. Passed to sf as --line-ending. Valid values: LF, CRLF.

    .PARAMETER WaitMinutes
    Time to wait for the command to finish, in minutes. Passed to sf as --wait. Default: 0. Range: 0 to 1440.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Update-SalesforceBulkData -File .\changes.csv -Object Contact -WaitMinutes 10 -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data update bulk (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -File = --file; -Object = --sobject; -ColumnDelimiter = --column-delimiter; -LineEnding = --line-ending; -WaitMinutes = --wait; -TargetOrg = --target-org.
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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $File,
        [Parameter(Mandatory = $true)][string] $Object,
        [Parameter(Mandatory = $false)][ValidateSet('BACKQUOTE', 'CARET', 'COMMA', 'PIPE', 'SEMICOLON', 'TAB')][string] $ColumnDelimiter,
        [Parameter(Mandatory = $false)][ValidateSet('LF', 'CRLF')][string] $LineEnding,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $objectName = ConvertTo-SalesforceSoqlIdentifier -Value $Object
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "CSV file '$File' does not exist." }

    $arguments = @('data', 'update', 'bulk', '--file', $File, '--sobject', $objectName)
    if ($ColumnDelimiter) { $arguments += @('--column-delimiter', $ColumnDelimiter) }
    if ($LineEnding) { $arguments += @('--line-ending', $LineEnding) }
    if ($WaitMinutes -gt 0) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess((Get-SalesforceBulkTargetLabel -Object $objectName -File $File -TargetOrg $TargetOrg), 'Bulk update')) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data update bulk'
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation 'Update' -Object $objectName
}

function Upsert-SalesforceBulkData {
    <#
    .SYNOPSIS
    Inserts or updates records from the rows of a CSV file by external ID with Bulk API 2.0 (sf data upsert bulk).

    .DESCRIPTION
    -ExternalIdField names the external ID field the CSV matches on, and its column must be in the file. Asks for confirmation only when
    $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. For one record use Upsert-SalesforceRecord.

    .PARAMETER File
    CSV file that contains the IDs of the records to update or delete. Passed to sf as --file. Required.

    .PARAMETER Object
    API name of the Salesforce object, either standard or custom, that you want to update or delete records from. Passed to sf as --sobject. Required.

    .PARAMETER ExternalIdField
    Name of the external ID field, or the Id field. Passed to sf as --external-id. Required.

    .PARAMETER ColumnDelimiter
    Column delimiter used in the CSV file. Passed to sf as --column-delimiter. Valid values: BACKQUOTE, CARET, COMMA, PIPE, SEMICOLON, TAB.

    .PARAMETER LineEnding
    Line ending used in the CSV file. Default value on Windows is `CRLF`; on macOS and Linux it's `LF`. Passed to sf as --line-ending. Valid values: LF, CRLF.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the command to complete before displaying the results. Passed to sf as --wait. Default: 0. Range: 0 to 1440.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Upsert-SalesforceBulkData -File .\accounts.csv -Object Account -ExternalIdField Ext_Id__c -WaitMinutes 10 -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data upsert bulk (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -File = --file; -Object = --sobject; -ExternalIdField = --external-id; -ColumnDelimiter = --column-delimiter; -LineEnding = --line-ending; -WaitMinutes = --wait; -TargetOrg = --target-org.
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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $File,
        [Parameter(Mandatory = $true)][string] $Object,
        [Parameter(Mandatory = $true)][string] $ExternalIdField,
        [Parameter(Mandatory = $false)][ValidateSet('BACKQUOTE', 'CARET', 'COMMA', 'PIPE', 'SEMICOLON', 'TAB')][string] $ColumnDelimiter,
        [Parameter(Mandatory = $false)][ValidateSet('LF', 'CRLF')][string] $LineEnding,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $objectName = ConvertTo-SalesforceSoqlIdentifier -Value $Object
    $externalIdFieldName = ConvertTo-SalesforceSoqlIdentifier -Value $ExternalIdField
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "CSV file '$File' does not exist." }

    $arguments = @('data', 'upsert', 'bulk', '--file', $File, '--sobject', $objectName, '--external-id', $externalIdFieldName)
    if ($ColumnDelimiter) { $arguments += @('--column-delimiter', $ColumnDelimiter) }
    if ($LineEnding) { $arguments += @('--line-ending', $LineEnding) }
    if ($WaitMinutes -gt 0) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess((Get-SalesforceBulkTargetLabel -Object $objectName -File $File -TargetOrg $TargetOrg), "Bulk upsert on $externalIdFieldName")) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data upsert bulk'
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation 'Upsert' -Object $objectName
}

function Remove-SalesforceBulkData {
    <#
    .SYNOPSIS
    Deletes the records whose IDs are in a CSV file with Bulk API 2.0 (sf data delete bulk).

    .DESCRIPTION
    The CSV needs an Id column. By default the records go to the Recycle Bin; -HardDelete deletes them permanently, which cannot be undone, and needs the Bulk API Hard Delete permission. Asks for confirmation by default, naming the object, the file, the org and whether the delete is permanent; -WhatIf makes no CLI call. Scripts that run unattended need -Confirm:$false. Without -WaitMinutes the job is created and its JobId returned; finish it with Resume-SalesforceBulkJob -Operation Delete. With -WaitMinutes the cmdlet waits and returns the counts. A job with failed rows throws PsfdxBulkJobFailed (see Get-SalesforceBulkResult for the row results).

    .PARAMETER File
    CSV file that contains the IDs of the records to delete. Passed to sf as --file. Required.

    .PARAMETER Object
    API name of the Salesforce object, either standard or custom, that you want to delete records from. Passed to sf as --sobject. Required.

    .PARAMETER HardDelete
    Delete the records permanently, without moving them to the Recycle Bin. Adds --hard-delete. The user needs the Bulk API Hard Delete permission.

    .PARAMETER LineEnding
    Line ending used in the CSV file. Default value on Windows is `CRLF`; on macOS and Linux it's `LF`. Passed to sf as --line-ending. Valid values: LF, CRLF.

    .PARAMETER WaitMinutes
    Time to wait for the command to finish, in minutes. Passed to sf as --wait. Default: 0. Range: 0 to 1440.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceBulkData -File .\old-accounts.csv -Object Account -WaitMinutes 10 -TargetOrg myorg -WhatIf
    Preview the delete without sending anything.

    .EXAMPLE
    Remove-SalesforceBulkData -File .\old-accounts.csv -Object Account -HardDelete -WaitMinutes 10 -TargetOrg myorg -Confirm:$false
    Delete the accounts permanently, without any question.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data delete bulk (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -File = --file; -Object = --sobject; -HardDelete = --hard-delete; -LineEnding = --line-ending; -WaitMinutes = --wait; -TargetOrg = --target-org.
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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string] $File,
        [Parameter(Mandatory = $true)][string] $Object,
        [Parameter(Mandatory = $false)][switch] $HardDelete,
        [Parameter(Mandatory = $false)][ValidateSet('LF', 'CRLF')][string] $LineEnding,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $objectName = ConvertTo-SalesforceSoqlIdentifier -Value $Object
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "CSV file '$File' does not exist." }
    $arguments = @('data', 'delete', 'bulk', '--file', $File, '--sobject', $objectName)
    if ($HardDelete) { $arguments += '--hard-delete' }
    if ($LineEnding) { $arguments += @('--line-ending', $LineEnding) }
    if ($WaitMinutes -gt 0) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $action = 'Bulk delete (to the Recycle Bin)'
    if ($HardDelete) { $action = 'Bulk HARD delete (permanent, cannot be undone)' }
    if (-not $PSCmdlet.ShouldProcess((Get-SalesforceBulkTargetLabel -Object $objectName -File $File -TargetOrg $TargetOrg), $action)) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data delete bulk'
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation 'Delete' -Object $objectName
}

function Resume-SalesforceBulkJob {
    <#
    .SYNOPSIS
    Resumes a Bulk API 2.0 job started without -WaitMinutes (sf data export|import|update|upsert|delete resume).

    .DESCRIPTION
    Pass the JobId from the earlier step and the -Operation that created it, or -UseMostRecent for the job the CLI started last. The CLI remembers jobs it created on this computer, so import,
    update and export resumes find the org from that record; they do not take -TargetOrg (it is ignored with a warning), and a job created
    elsewhere cannot be resumed here: use Get-SalesforceBulkResult with -TargetOrg instead. Upsert and Delete resumes do take -TargetOrg. Export resumes do not take -WaitMinutes.
    Resuming only continues the existing job, so it does not ask for confirmation. Errors are as for the cmdlet that created the job.

    .PARAMETER Operation
    The kind of bulk job to resume: Export, Import, Update, Upsert or Delete. It selects which command runs: sf data export, import, update, upsert or delete resume. Required. Valid values: Export, Import, Update, Upsert, Delete.

    .PARAMETER JobId
    Job ID of the bulk job. Passed to sf as --job-id. Required unless you give -UseMostRecent.

    .PARAMETER UseMostRecent
    Resume the job that was started most recently, instead of giving -JobId. Adds --use-most-recent.

    .PARAMETER WaitMinutes
    Time to wait for the command to finish, in minutes. Passed to sf as --wait. Default: 0. Range: 0 to 1440.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the "target-org" configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Resume-SalesforceBulkJob -Operation Upsert -JobId 750xx0000000001 -WaitMinutes 10 -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data export resume (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Command run: sf data import resume (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Command run: sf data update resume (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Command run: sf data upsert resume (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Command run: sf data delete resume (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -JobId = --job-id; -UseMostRecent = --use-most-recent; -WaitMinutes = --wait; -TargetOrg = --target-org.
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
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    Param(
        [Parameter(Mandatory = $true)][ValidateSet('Export', 'Import', 'Update', 'Upsert', 'Delete')][string] $Operation,
        [Parameter(Mandatory = $true, ParameterSetName = 'ById')][ValidatePattern('^750[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $JobId,
        [Parameter(Mandatory = $true, ParameterSetName = 'MostRecent')][switch] $UseMostRecent,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $hasTargetOrg = $PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)
    $takesTargetOrg = $Operation -in 'Upsert', 'Delete'
    if ($hasTargetOrg -and -not $takesTargetOrg) { Write-Warning "-TargetOrg is ignored for a $Operation resume: the CLI finds the org from its record of the job." }
    if ($WaitMinutes -gt 0 -and $Operation -eq 'Export') { Write-Warning '-WaitMinutes is ignored for an Export resume.' }

    switch ($Operation) {
        'Export' { $arguments = @('data', 'export', 'resume'); $command = 'data export resume' }
        'Import' { $arguments = @('data', 'import', 'resume'); $command = 'data import resume' }
        'Update' { $arguments = @('data', 'update', 'resume'); $command = 'data update resume' }
        'Upsert' { $arguments = @('data', 'upsert', 'resume'); $command = 'data upsert resume' }
        'Delete' { $arguments = @('data', 'delete', 'resume'); $command = 'data delete resume' }
    }
    if ($PSCmdlet.ParameterSetName -eq 'MostRecent') { $arguments += '--use-most-recent' } else { $arguments += @('--job-id', $JobId) }
    if ($WaitMinutes -gt 0 -and $Operation -ne 'Export') { $arguments += @('--wait', $WaitMinutes) }
    if ($hasTargetOrg -and $takesTargetOrg) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command $command
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation $Operation -JobId $JobId
}

function Get-SalesforceBulkResult {
    <#
    .SYNOPSIS
    Gets the outcome of a Bulk API 2.0 ingest job and saves its row results as CSV files (sf data bulk results).

    .DESCRIPTION
    The CLI writes <JobId>-success-records.csv, <JobId>-failed-records.csv and <JobId>-unprocessed-records.csv into its working directory, so
    the cmdlet runs it in -OutputDirectory (the current directory by default) and returns the full paths of the files it wrote. Records that
    failed do not make this cmdlet throw: check HasFailures or FailedRecords. A job that has not finished is an error. Works for any job in
    the org, including ones this computer did not create.

    .PARAMETER JobId
    Job ID of the bulk job. Passed to sf as --job-id. Required.

    .PARAMETER OutputDirectory
    Folder the result files are written to. It is created if it does not exist. Defaults to the current folder. The cmdlet runs the CLI there and returns the full paths of the files it wrote.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    $r = Get-SalesforceBulkResult -JobId 750xx0000000001 -OutputDirectory .\bulk -TargetOrg myorg; if ($r.HasFailures) { Import-Csv $r.FailedFilePath }

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data bulk results (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -JobId = --job-id; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^750[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $JobId,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $directory = (Get-Location).ProviderPath
    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw "Output directory '$OutputDirectory' does not exist." }
        $directory = (Resolve-Path -LiteralPath $OutputDirectory).ProviderPath
    }

    $arguments = @('data', 'bulk', 'results', '--job-id', $JobId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Push-Location -LiteralPath $directory
    try {
        $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    } finally {
        Pop-Location
    }
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data bulk results' -AllowFailedRecords

    $pathOf = {
        param([string] $Name)
        if ($null -ne $result.PSObject.Properties[$Name] -and -not [string]::IsNullOrWhiteSpace([string] $result.$Name)) { return (Join-Path -Path $directory -ChildPath ([string] $result.$Name)) }
        return $null
    }
    $failed = 0
    if ($null -ne $result.PSObject.Properties['failedRecords'] -and $null -ne $result.failedRecords) { $failed = [int] $result.failedRecords }
    if ($failed -gt 0) { Write-Warning "$failed record(s) failed in job $JobId. See the failed records file in $directory." }
    return [pscustomobject]@{
        JobId               = $JobId
        Status              = $result.status
        Operation           = $result.operation
        Object              = $result.object
        ProcessedRecords    = $result.processedRecords
        SuccessfulRecords   = $result.successfulRecords
        FailedRecords       = $failed
        HasFailures         = ($failed -gt 0)
        SuccessFilePath     = & $pathOf 'successFilePath'
        FailedFilePath      = & $pathOf 'failedFilePath'
        UnprocessedFilePath = & $pathOf 'unprocessedFilePath'
    }
}

function Get-SalesforceBulkJobStatus {
    <#
    .SYNOPSIS
    Shows the status of a bulk data load job, or of one batch in it (sf data resume).

    .DESCRIPTION
    Runs sf data resume, which reads the state of a bulk job from the org and returns it as an object. It only reads: it does not continue or change the job. For a Bulk API 2.0 job started with -WaitMinutes 0, use Resume-SalesforceBulkJob to continue it and Get-SalesforceBulkResult for its row results.

    .PARAMETER JobId
    ID of the bulk job. Passed to sf as --job-id. Required.

    .PARAMETER BatchId
    ID of one batch in the job. Passed to sf as --batch-id.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceBulkJobStatus -JobId 750xx0000000001AAA -TargetOrg myorg
    The state of the job.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data resume (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -JobId = --job-id; -BatchId = --batch-id; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $JobId,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $BatchId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('data', 'resume', '--job-id', $JobId)
    if ($BatchId) { $arguments += @('--batch-id', $BatchId) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceBulkTargetLabel {
    # Names what a bulk write will touch, for the ShouldProcess prompt and -WhatIf: the object, the file and the org.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Object,
        [Parameter(Mandatory = $true)][string] $File,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $org = 'the default org'
    if (-not [string]::IsNullOrWhiteSpace($TargetOrg)) { $org = "org $TargetOrg" }
    return "$Object records from '$File' in $org"
}

function ConvertFrom-SalesforceBulkOutput {
    # Returns the result of a bulk command, or throws. A failed job (failed rows, Failed or Aborted) becomes PsfdxBulkJobFailed with the
    # job ID, so a script can fetch the row results; any other failure is thrown as the CLI described it.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][AllowEmptyCollection()] $Output,
        [Parameter(Mandatory = $true)][string] $Command,
        [Parameter(Mandatory = $false)][switch] $AllowFailedRecords
    )
    $text = [string]::Join([Environment]::NewLine, @($Output | ForEach-Object { [string] $_ })).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { throw "sf $Command returned no output where JSON was expected." }
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop } catch {
        $preview = $text; if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
        throw "sf $Command returned output that is not valid JSON: $preview"
    }
    if ($null -eq $parsed -or $parsed -is [array] -or $null -eq $parsed.PSObject.Properties['status']) {
        throw "sf $Command returned JSON in an unexpected shape (no status)."
    }
    # Upsert and its resume return { jobInfo, records } instead of the flat counts, and the CLI can send that with a failing status when rows failed.
    $hasResult = ($null -ne $parsed.PSObject.Properties['result']) -and ($null -ne $parsed.result)
    if ($hasResult -and $null -ne $parsed.result.PSObject.Properties['jobInfo'] -and $null -ne $parsed.result.jobInfo) {
        $info = $parsed.result.jobInfo
        $state = $null; if ($null -ne $info.PSObject.Properties['state']) { $state = [string] $info.state }
        $flat = [ordered]@{ jobId = [string] $info.id; state = $state }
        if ($state -eq 'JobComplete') {
            $processed = 0; if ($null -ne $info.PSObject.Properties['numberRecordsProcessed'] -and $null -ne $info.numberRecordsProcessed) { $processed = [int] $info.numberRecordsProcessed }
            $failedRows = 0; if ($null -ne $info.PSObject.Properties['numberRecordsFailed'] -and $null -ne $info.numberRecordsFailed) { $failedRows = [int] $info.numberRecordsFailed }
            $flat['processedRecords'] = $processed
            $flat['failedRecords'] = $failedRows
            $flat['successfulRecords'] = $processed - $failedRows
        }
        if (-not $AllowFailedRecords) {
            $message = ''
            if ($state -eq 'Failed' -or $state -eq 'Aborted') {
                if ($null -ne $info.PSObject.Properties['errorMessage'] -and $info.errorMessage) { $message = [string] $info.errorMessage }
                $message = "The job is $state. $message".Trim()
            } elseif ($flat.Contains('failedRecords') -and $flat['failedRecords'] -gt 0) {
                $message = "Job finished being processed but $($flat['failedRecords']) records failed to process."
            }
            if ($message) {
                $full = "sf $Command reported a problem with bulk job $($flat['jobId']): $message Get-SalesforceBulkResult -JobId $($flat['jobId']) lists the rows that failed."
                $target = [pscustomobject]@{ JobId = $flat['jobId']; State = $state; Message = $message }
                $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException $full), 'PsfdxBulkJobFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $target)
                throw $record
            }
        }
        return [pscustomobject] $flat
    }

    if ($parsed.status -eq 0) {
        if (-not $hasResult) { throw "sf $Command succeeded but returned no result." }
        return $parsed.result
    }

    $jobId = $null; $state = $null
    if ($null -ne $parsed.PSObject.Properties['data'] -and $null -ne $parsed.data) {
        if ($null -ne $parsed.data.PSObject.Properties['jobId']) { $jobId = [string] $parsed.data.jobId }
        if ($null -ne $parsed.data.PSObject.Properties['state']) { $state = [string] $parsed.data.state }
    }
    $message = ''
    if ($null -ne $parsed.PSObject.Properties['message'] -and $parsed.message) { $message = [string] $parsed.message }
    if (-not $jobId -and $message -match '\b(750[A-Za-z0-9]{12}(?:[A-Za-z0-9]{3})?)\b') { $jobId = $Matches[1] }
    if ($jobId) {
        $full = "sf $Command reported a problem with bulk job ${jobId}: $message Get-SalesforceBulkResult -JobId $jobId lists the rows that failed.".Replace('  ', ' ')
        $target = [pscustomobject]@{ JobId = $jobId; State = $state; Message = $message }
        $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException $full), 'PsfdxBulkJobFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $target)
        throw $record
    }
    # No job ID: an ordinary CLI failure, with the same message handling as every other cmdlet.
    Show-SalesforceResult -Result $text | Out-Null
    throw "sf $Command failed with status $($parsed.status). $message".Trim()
}

function ConvertTo-SalesforceBulkJobObject {
    # One shape for every bulk command. Properties the CLI did not report (an asynchronous job has no counts yet) are $null.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)] $Result,
        [Parameter(Mandatory = $true)][string] $Operation,
        [Parameter(Mandatory = $false)][string] $Object,
        [Parameter(Mandatory = $false)][string] $JobId
    )
    $get = {
        param([string] $Name)
        if ($null -ne $Result.PSObject.Properties[$Name]) { return $Result.$Name }
        return $null
    }
    $id = & $get 'jobId'
    if (-not $id) { $id = $JobId }
    $processed = & $get 'processedRecords'
    $total = & $get 'totalSize'
    $state = & $get 'state'
    return [pscustomobject]@{
        JobId             = $id
        Operation         = $Operation
        Object            = $(if ($Object) { $Object } else { $null })
        Completed         = (($null -ne $processed) -or ($null -ne $total))
        State             = $state
        ProcessedRecords  = $processed
        SuccessfulRecords = & $get 'successfulRecords'
        FailedRecords     = & $get 'failedRecords'
        TotalSize         = $total
        FilePath          = & $get 'filePath'
    }
}

#endregion
