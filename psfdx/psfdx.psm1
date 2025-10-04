function Resolve-PsfdxSharedScriptPath {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $FileName
    )

    $moduleBase = $ExecutionContext.SessionState.Module.ModuleBase
    $candidates = @()

    if ($moduleBase) {
        $candidates += Join-Path -Path $moduleBase -ChildPath (Join-Path '..' (Join-Path 'psfdx-shared' $FileName))
        $moduleRoot = Split-Path -Path $moduleBase -Parent
        if ($moduleRoot) {
            $candidates += Join-Path -Path $moduleRoot -ChildPath (Join-Path 'psfdx-shared' $FileName)
        }
    }

    $psModuleRoots = $env:PSModulePath -split [System.IO.Path]::PathSeparator
    foreach ($root in $psModuleRoots) {
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $candidates += Join-Path -Path $root -ChildPath (Join-Path 'psfdx-shared' $FileName)
        }
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        try {
            $resolved = Resolve-Path -LiteralPath $candidate -ErrorAction Stop
            return $resolved.ProviderPath
        } catch {
            continue
        }
    }

    return $null
}

function Import-PsfdxSharedScript {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $FileName,
        [switch] $Optional
    )

    $path = Resolve-PsfdxSharedScriptPath -FileName $FileName
    if ($path) {
        . $path
        return
    }

    switch ($FileName) {
        'Invoke-Salesforce.ps1' {
            if (-not (Get-Command -Name Invoke-Salesforce -ErrorAction SilentlyContinue)) {
                function Invoke-Salesforce {
                    [CmdletBinding()]
                    Param(
                        [Parameter(Mandatory = $true)][string] $Command
                    )

                    Write-Verbose $Command
                    Invoke-Expression -Command $Command
                }
            }
            return
        }
        'Show-SalesforceResult.ps1' {
            if (-not (Get-Command -Name Show-SalesforceResult -ErrorAction SilentlyContinue)) {
                function Show-SalesforceResult {
                    [CmdletBinding()]
                    Param(
                        [Parameter(Mandatory = $true)][psobject] $Result,
                        [Parameter(Mandatory = $false)][switch] $ReturnRecords,
                        [Parameter(Mandatory = $false)][switch] $IncludeAttributes
                    )

                    $converted = $Result | ConvertFrom-Json
                    if ($converted.status -ne 0) {
                        Write-Debug ($Result | ConvertTo-Json)
                        $message = Get-SalesforceErrorMessage -Result $converted
                        throw $message
                    }

                    $out = $converted.result
                    if ($ReturnRecords) {
                        $records = $out.records
                        if ($null -eq $records) { return @() }
                        if ($IncludeAttributes) { return $records }
                        return ($records | Select-Object -ExcludeProperty attributes)
                    }
                    return $out
                }

                function Get-SalesforceErrorMessage {
                    [CmdletBinding()]
                    Param(
                        [Parameter(Mandatory = $true)][psobject] $Result
                    )

                    if ($Result -is [string]) {
                        Write-Debug $Result
                    } else {
                        Write-Debug ($Result | ConvertTo-Json -Depth 10)
                    }

                    $messages = @()

                    if ($Result.message) {
                        $messages += $Result.message
                    }

                    $deployFailures = Get-SalesforceDeployFailures -Result $Result
                    if ($deployFailures) {
                        $messages += $deployFailures
                    }

                    $testFailures = Get-SalesforceTestFailure -Result $Result
                    if ($testFailures) {
                        $messages += $testFailures
                    }

                    if (-not $messages) {
                        $messages += "Salesforce command failed with status $($Result.status)."
                    }

                    return ($messages -join [Environment]::NewLine)
                }

                function Get-SalesforceDeployFailures {
                    [CmdletBinding()]
                    Param(
                        [Parameter(Mandatory = $true)][psobject] $Result
                    )

                    $resultRoot = $Result.result
                    if ($null -eq $resultRoot) { return $null }

                    $details = $resultRoot.details
                    if ($null -eq $details) { return $null }

                    $componentFailures = $details.componentFailures
                    if (-not $componentFailures) {
                        return $null
                    }

                    return ($componentFailures | ForEach-Object {
                        $problem = $_.problem
                        $line = $_.lineNumber
                        $column = $_.columnNumber

                        if ([string]::IsNullOrWhiteSpace($problem)) {
                            return $null
                        }

                        if (($null -ne $line) -or ($null -ne $column)) {
                            $lineValue = if ($null -ne $line) { $line } else { '?' }
                            $columnValue = if ($null -ne $column) { $column } else { '?' }
                            "$problem ($($lineValue):$($columnValue))"
                        } else {
                            $problem
                        }
                    }) | Where-Object { $_ }
                }

                function Get-SalesforceTestFailure {
                    [CmdletBinding()]
                    Param(
                        [Parameter(Mandatory = $true)][psobject] $Result
                    )

                    $resultRoot = $Result.result
                    if ($null -eq $resultRoot) { return $null }

                    $details = $resultRoot.details
                    if ($null -eq $details) { return $null }

                    $runTestResult = $details.runTestResult
                    if ($null -eq $runTestResult) { return $null }

                    $failures = $runTestResult.failures
                    if (-not $failures) {
                        return $null
                    }

                    return ($failures | ForEach-Object {
                        $message = $_.message
                        $stack = $_.stackTrace
                        if ($stack) {
                            "$message $stack"
                        } else {
                            $message
                        }
                    })
                }
            }
            return
        }
        'SalesforceApexTests.ps1' {
            if (-not (Get-Command -Name Get-SalesforceApexCliTestParams -ErrorAction SilentlyContinue)) {
                function Get-SalesforceApexCliTestParams {
                    [CmdletBinding()]
                    Param(
                        [Parameter(Mandatory = $false)][string] $SourceDir,
                        [Parameter(Mandatory = $false)][ValidateSet(
                            'NoTests',
                            'SpecificTests',
                            'TestsClass',
                            'TestsInFolder',
                            'TestsInOrg',
                            'TestsInOrgAndPackages')][string] $TestLevel = 'NoTests',
                        [Parameter(Mandatory = $false)][string[]] $Tests
                    )

                    $value = ""
                    $testLevelMap = @{
                        'NoTests'               = 'NoTestRun'
                        'SpecificTests'         = 'RunSpecifiedTests'
                        'TestsClass'            = 'RunSpecifiedTests'
                        'TestsInFolder'         = 'RunSpecifiedTests'
                        'TestsInOrg'            = 'RunLocalTests'
                        'TestsInOrgAndPackages' = 'RunAllTestsInOrg'
                    }
                    $value += " --test-level " + $testLevelMap[$TestLevel]

                    if ($TestLevel -eq 'TestsClass') {
                        if (-not $SourceDir) {
                            throw "Specify -SourceDir when using -TestLevel TestsClass."
                        }
                        if (-not (Test-Path -LiteralPath $SourceDir)) {
                            throw "Source path '$SourceDir' does not exist."
                        }

                        $item = Get-Item -LiteralPath $SourceDir
                        if ($item.PSIsContainer) {
                            throw "Provide a file path for -SourceDir when using -TestLevel TestsClass."
                        }

                        $className = [System.IO.Path]::GetFileNameWithoutExtension($item.Name)
                        if (-not $className) {
                            throw "Unable to determine class name from '$SourceDir'."
                        }

                        $searchRoot = $item.Directory
                        if (-not $searchRoot) {
                            throw "Unable to determine directory for '$SourceDir'."
                        }

                        $escapedClassName = [regex]::Escape($className)
                        $classPattern = "\b$escapedClassName\b"

                        $Tests = Get-ChildItem -LiteralPath $searchRoot.FullName -Filter '*.cls' -File -ErrorAction SilentlyContinue |
                            Where-Object {
                                $_.FullName -ne $item.FullName -and
                                (Select-String -Path $_.FullName -Pattern '@isTest' -SimpleMatch -Quiet) -and
                                (Select-String -Path $_.FullName -Pattern $classPattern -Quiet)
                            } |
                            ForEach-Object { $_.BaseName } |
                            Sort-Object -Unique

                        if (-not $Tests -or $Tests.Count -eq 0) {
                            throw "No Apex test classes in '$($searchRoot.FullName)' reference '$className'."
                        }
                    } elseif ($TestLevel -eq 'TestsInFolder') {
                        $TestsPath = $SourceDir
                        if (-not $TestsPath) {
                            $TestsPath = Get-Location
                        }
                        if (Test-Path -LiteralPath $TestsPath) {
                            $item = Get-Item -LiteralPath $TestsPath
                            if (-not $item.PSIsContainer -and $item.Directory) {
                                $TestsPath = $item.Directory.FullName
                            }
                        }
                        $Tests = Get-SalesforceApexTestClassNamesFromPath -Path $TestsPath
                        if (-not $Tests -or $Tests.Count -eq 0) {
                            throw "No Apex test classes found in '$TestsPath'."
                        }
                    } elseif ($TestLevel -eq 'SpecificTests') {
                        if (-not $Tests -or $Tests.Count -eq 0) {
                            throw "Provide one or more -Tests when using -TestLevel SpecificTests."
                        }
                        $Tests = $Tests |
                            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                            Sort-Object -Unique
                        if (-not $Tests -or $Tests.Count -eq 0) {
                            throw "Provided -Tests values are empty."
                        }
                    }

                    $value += ConvertTo-SalesforceCliApexTestParams -TestClassNames $Tests
                    return $value
                }
            }

            if (-not (Get-Command -Name Get-SalesforceApexTestClassNamesFromPath -ErrorAction SilentlyContinue)) {
                function Get-SalesforceApexTestClassNamesFromPath {
                    [CmdletBinding()]
                    Param(
                        [Parameter(Mandatory = $true)][string] $Path
                    )

                    if (-not (Test-Path -LiteralPath $Path)) {
                        throw "Path '$Path' does not exist."
                    }

                    $item = Get-Item -LiteralPath $Path
                    if ($item.PSIsContainer) {
                        $searchRoot = $item.FullName
                    } else {
                        $directory = $item.Directory
                        $searchRoot = if ($directory) { $directory.FullName } else { $item.FullName }
                    }

                    $testFiles = Get-ChildItem -LiteralPath $searchRoot -Recurse -Filter '*.cls' -File -ErrorAction SilentlyContinue
                    if (-not $testFiles) {
                        return @()
                    }

                    $testFiles = $testFiles | Where-Object {
                        Select-String -Path $_.FullName -Pattern '@isTest' -SimpleMatch -Quiet
                    }

                    return @($testFiles | ForEach-Object { $_.BaseName } | Sort-Object -Unique)
                }
            }

            if (-not (Get-Command -Name ConvertTo-SalesforceCliApexTestParams -ErrorAction SilentlyContinue)) {
                function ConvertTo-SalesforceCliApexTestParams {
                    [CmdletBinding()]
                    Param(
                        [Parameter(Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
                        [AllowNull()]
                        [AllowEmptyCollection()]
                        [string[]] $TestClassNames = @()
                    )

                    begin { $all = @() }

                    process {
                        if ($null -ne $TestClassNames) {
                            $all += $TestClassNames | ForEach-Object { $_ } | Where-Object { $_ -and $_.Trim() }
                        }
                    }

                    end {
                        if ($all.Count -eq 0) { return "" }
                        $parts = $all | ForEach-Object { "--tests $($_.Trim())" }
                        ' ' + ($parts -join ' ')
                    }
                }
            }

            return
        }
        default {
            if (-not $Optional) {
                throw "Unable to locate psfdx-shared script '$FileName'. Reinstall psfdx to ensure shared scripts are installed."
            }
        }
    }
}

Import-PsfdxSharedScript -FileName 'Invoke-Salesforce.ps1'
Import-PsfdxSharedScript -FileName 'Show-SalesforceResult.ps1'
Import-PsfdxSharedScript -FileName 'SalesforceApexTests.ps1' -Optional

#region Authentication & Orgs

function Connect-Salesforce {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Sandbox,
        [Parameter(Mandatory = $false)][string] $CustomUrl,

        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][switch] $SetDefaultDevHub,

        [Parameter(Mandatory = $false)][string][ValidateSet('chrome', 'edge', 'firefox')] $Browser,
        [Parameter(Mandatory = $false)][string] $OAuthClientId
    )

    $command = "sf org login web"
    if ($Sandbox) { $command += " --instance-url https://test.salesforce.com" }
    if ($CustomUrl) { $command += " --instance-url $CustomUrl" }

    if ($Alias) { $command += " --alias $Alias" }
    if ($SetDefault) { $command += " --set-default" }
    if ($SetDefaultDevHub) { $command += " --set-default-dev-hub" }

    if ($Browser) { $command += " --browser $Browser" }
    if ($OAuthClientId) { $command += " --client-id $OAuthClientId" }

    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    Show-SalesforceResult -Result $result
}

function Connect-SalesforceAuthUrl {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $SfdxUrlFile,

        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][switch] $SetDefaultDevHub,
        [Parameter(Mandatory = $false)][switch] $IncludeToken
    )

    if (-not (Test-Path -LiteralPath $SfdxUrlFile)) {
        throw "File does not exist: $SfdxUrlFile"
    }

    $segments = [System.Collections.Generic.List[string]]::new()
    $segments.Add('sf auth sfdxurl store') | Out-Null
    $segments.Add("--sfdx-url-file `"$SfdxUrlFile`"") | Out-Null
    if ($Alias) { $segments.Add("--alias $Alias") | Out-Null }
    if ($SetDefault) { $segments.Add('--set-default') | Out-Null }
    if ($SetDefaultDevHub) { $segments.Add('--set-default-dev-hub') | Out-Null }
    $segments.Add('--json') | Out-Null

    $command = $segments -join ' '
    $result = Invoke-Salesforce -Command $command
    $details = Show-SalesforceResult -Result $result

    if ($IncludeToken) {
        return $details
    }

    if ($null -eq $details) {
        return $details
    }

    $sensitiveKeys = @('accessToken', 'refreshToken')
    if ($details -is [System.Collections.IEnumerable] -and -not ($details -is [string])) {
        return $details | ForEach-Object {
            if ($_ -is [psobject]) {
                $_ | Select-Object -Property * -ExcludeProperty $sensitiveKeys
            } else {
                $_
            }
        }
    }

    if ($details -is [psobject]) {
        return $details | Select-Object -Property * -ExcludeProperty $sensitiveKeys
    }

    return $details
}

function Disconnect-Salesforce {
    [CmdletBinding(DefaultParameterSetName = 'TargetOrg')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'All')][switch] $All,
        [Parameter(Mandatory = $true, ParameterSetName = 'TargetOrg')][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $command = "sf org logout"
    if ($PSCmdlet.ParameterSetName -eq 'All') {
        $command += " --all"
    } else {
        $command += " --target-org $TargetOrg"
    }
    if ($NoPrompt) { $command += " --no-prompt" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    Show-SalesforceResult -Result $result
}

function Connect-SalesforceJwt {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ConsumerKey,
        [Parameter(Mandatory = $true)][string] $TargetOrg,
        [Parameter(Mandatory = $true)][string] $JwtKeyfile,
        [Parameter(Mandatory = $false)][switch] $Sandbox,

        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][switch] $SetDefaultDevHub
    )
    if (-not(Test-Path $JwtKeyfile)) {
        throw "File does not exist: $JwtKeyfile"
    }

    $url = "https://login.salesforce.com"
    if ($Sandbox) { $url = "https://test.salesforce.com" }

    $command = "sf org login jwt --client-id $ConsumerKey --username $TargetOrg --jwt-key-file `"$JwtKeyfile`" --instance-url $url"
    if ($Alias) { $command += " --alias $Alias" }
    if ($SetDefault) { $command += " --set-default" }
    if ($SetDefaultDevHub) { $command += " --set-default-dev-hub" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Open-Salesforce {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UrlOnly,
        [Parameter(Mandatory = $false)][string][ValidateSet('chrome', 'edge', 'firefox')] $Browser,
        [Parameter(Mandatory = $false)][string] $BrowserPrivateMode
    )
    $command = "sf org open"
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    if ($Browser) { $command += " --browser $Browser" }
    if ($BrowserPrivateMode) { $command += " --private $BrowserPrivateMode" }
    if ($UrlOnly) { $command += " --url-only" }
    Invoke-Salesforce -Command $command
}

function Get-SalesforceConnections {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $ShowVerboseDetails
    )
    $command = "sf org list"
    if ($ShowVerboseDetails) { $command += " --verbose" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command

    $result = $result | ConvertFrom-Json
    $result = $result.result.nonScratchOrgs # Exclude Scratch Orgs
    $result = $result | Select-Object orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias
    return $result
}

function Repair-SalesforceConnections {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][switch] $NoPrompt)
    $command = "sf org list --clean"
    if ($NoPrompt) { $command += " --no-prompt" }
    Invoke-Salesforce -Command $command
}

#endregion

#region Aliases & Limits

function Get-SalesforceAlias {
    [CmdletBinding()]
    $command = "sf alias list --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Add-SalesforceAlias {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Alias,
        [Parameter(Mandatory = $true)][string] $TargetOrg
    )
    $command = "sf alias set $Alias=$TargetOrg"
    Invoke-Salesforce -Command $command
}

function Remove-SalesforceAlias {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Alias)
    $command = "sf alias unset $Alias"
    Invoke-Salesforce -Command $command
}

#endregion

#region Limits & Usage

function Get-SalesforceLimits {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $command = "sf limits api display"
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDataStorage {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $values = Get-SalesforceLimits -TargetOrg $TargetOrg | Where-Object Name -eq "DataStorageMB"
    $values | Add-Member -NotePropertyName InUse -NotePropertyValue ($values.max + ($values.remaining * -1))
    $values | Add-Member -NotePropertyName Usage -NotePropertyValue (($values.max + ($values.remaining * -1)) / $values.max).ToString('P')
    return $values
}

function Get-SalesforceApiUsage {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $values = Get-SalesforceLimits -TargetOrg $TargetOrg | Where-Object Name -eq "DailyApiRequests"
    $values | Add-Member -NotePropertyName Usage -NotePropertyValue (($values.max + ($values.remaining * -1)) / $values.max).ToString('P')
    return $values
}

#endregion

#region Data Management

function Select-SalesforceRecords {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Query,
        [Parameter(Mandatory = $false)][string] $File,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi,
        [Parameter(Mandatory = $false)][switch] $IncludeDeletedRows,
        [Parameter(Mandatory = $false)][string][ValidateSet('human', 'json', 'csv')] $ResultFormat = 'json',
        [Parameter(Mandatory = $false)][string] $OutputFile
    )
    $command = "sf data query"
    if ($Query) { $command += " --query `"$Query`"" }
    if ($File) { $command += " --file `"$File`"" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) {
        $trimmedTargetOrg = $TargetOrg.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmedTargetOrg)) {
            $command += " --target-org $trimmedTargetOrg"
        }
    }
    if ($UseToolingApi) { $command += " --use-tooling-api" }
    if ($IncludeDeletedRows) { $command += " --all-rows" }

    $command += " --result-format $ResultFormat"
    if ($OutputFile) { $command += " --output-file $OutputFile" }

    $result = Invoke-Salesforce -Command $command | ConvertFrom-Json
    if ($result.status -ne 0) {
        $result
        throw $result.message
    }
    # Exclude Salesforce's built-in 'attributes' metadata from each row
    return ($result.result.records | Select-Object -ExcludeProperty attributes)
}

function Get-SalesforceUsers {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $ActiveOnly,
        [Parameter(Mandatory = $false)][int] $Limit = 200,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $fields = 'Id, Name, Username, Email, IsActive, LastLoginDate'
    $query = "SELECT $fields FROM User"
    $filters = @()
    if ($ActiveOnly) { $filters += 'IsActive = true' }
    if ($Username)   { $filters += "Username = '$Username'" }
    if ($filters.Count -gt 0) { $query += ' WHERE ' + ($filters -join ' AND ') }
    $query += ' ORDER BY LastLoginDate DESC'
    $query += " LIMIT $Limit"

    return Select-SalesforceRecords -Query $query -TargetOrg $TargetOrg -ResultFormat json
}

function New-SalesforceRecord {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true)][string] $FieldUpdates,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    Write-Verbose $FieldUpdates
    $command = "sf data create record"
    $command += " --sobject $Type"
    $command += " --values `"$FieldUpdates`""
    if ($UseToolingApi) { $command += " --use-tooling-api" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Set-SalesforceRecord {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Id,
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true)][string] $FieldUpdates,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    Write-Verbose $FieldUpdates
    $command = "sf data update record"
    $command += " --sobject $Type"
    $command += " --record-id $Id"
    $command += " --values `"$FieldUpdates`""
    if ($UseToolingApi) { $command += " --use-tooling-api" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceRecordType {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectType,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $query = "SELECT Id, SobjectType, Name, DeveloperName, IsActive"
    $query += " FROM RecordType"
    if ($ObjectType) { $query += " WHERE SobjectType = '$ObjectType'" }
    return Select-SalesforceRecords -Query $query -TargetOrg $TargetOrg
}

#endregion

#region Salesforce REST API

function Connect-SalesforceApi {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $TargetOrg,
        [Parameter(Mandatory = $true)][string] $Password,
        [Parameter(Mandatory = $true)][string] $Token,
        [Parameter(Mandatory = $true)][string] $ClientId,
        [Parameter(Mandatory = $true)][string] $ClientSecret,
        [Parameter(Mandatory = $false)][switch] $Sandbox,
        [Parameter(Mandatory = $false)][string] $CustomUrl
    )

    $loginUrl = "https://login.salesforce.com/services/oauth2/token"
    if ($Sandbox) { $loginUrl = "https://test.salesforce.com/services/oauth2/token" }
    if ($CustomUrl) { $loginUrl = "$CustomUrl/services/oauth2/token" }

    return Invoke-RestMethod -Uri $loginUrl `
        -Method Post `
        -Body @{
        grant_type    = "password"
        client_id     = "$ClientId"
        client_secret = "$ClientSecret"
        username      = "$TargetOrg"
        password      = ($Password + $Token)
    }
}

function Invoke-SalesforceApi {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Url,
        [Parameter(Mandatory = $true)][string] $AccessToken,
        [Parameter(Mandatory = $false)][string][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')] $Method = "GET"
    )
    return Invoke-RestMethod -Uri $Url -Method $Method -Headers @{Authorization = "Bearer " + $AccessToken }
}

function Get-SalesforceApiVersions {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $command = "sf api request rest /services/data"
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $result = Invoke-Salesforce -Command $command
    return $result | ConvertFrom-Json
}

function Get-SalesforceLatestApiVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $versions = Get-SalesforceApiVersions -TargetOrg $TargetOrg
    if ($versions.Count -eq 0) { return $null }
    $latest = $versions | Sort-Object -Property version -Descending | Select-Object
    $version = $latest[0].version
    return "v$version"
}

#endregion

#region Plugins

function Test-SalesforceIsMacOS {
    [CmdletBinding()]
    Param()
    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
}

function Install-SalesforceCli {
    [CmdletBinding()]
    Param()
    if (Test-SalesforceIsMacOS) {
        Invoke-Salesforce -Command "brew install sfdx-cli/tap/sf"
    } else {
        Invoke-Salesforce -Command "npm install --global @salesforce/cli"
    }
}

function Install-SalesforcePlugin {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name
    )
    $command = "sf plugins install $Name"
    Invoke-Salesforce -Command $command
}

function Get-SalesforcePlugins {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $IncludeCore
    )
    $command = "sf plugins"
    if ($IncludeCore) { $command += " --core" }
    Invoke-Salesforce -Command $command
}

function Update-SalesforcePlugins {
    [CmdletBinding()]
    Param()
    $command = "sf plugins update"
    Invoke-Salesforce -Command $command
}

#endregion

#region Utilities

function Get-SalesforceDateTime {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][datetime] $Datetime)
    if ($null -eq $Datetime) { $Datetime = Get-Date }
    return $Datetime.ToString('s') + 'Z'
}

#endregion
