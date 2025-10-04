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

#region Sandbox Management

function Get-SalesforceSandboxes {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Name
    )

    $command = "sf org list --json"
    $result = Invoke-Salesforce -Command $command
    $parsed = Show-SalesforceResult -Result $result
    if (-not $parsed) { return @() }

    $nonScratch = $parsed.nonScratchOrgs
    if ($null -eq $nonScratch) { return @() }

    $sandboxes = @($nonScratch | Where-Object { $_.isSandbox })
    if ($Name) {
        $sandboxes = $sandboxes | Where-Object {
            ($_.sandboxName -eq $Name) -or
            ($_.username -eq $Name) -or
            ($_.alias -eq $Name)
        }
    }
    return $sandboxes
}

function New-SalesforceSandbox {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $SandboxName,
        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][string] $DefinitionFile,
        [Parameter(Mandatory = $false)][ValidateSet('Developer', 'Developer_Pro', 'Partial', 'Full')][string] $LicenseType = 'Developer',
        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][switch] $NoTrackSource,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $command = "sf org create sandbox --name $SandboxName"
    if ($Alias) { $command += " --alias $Alias" }

    if ($DefinitionFile) { $command += " --definition-file `"$DefinitionFile`"" }
    if ($LicenseType) { $command += " --license-type $LicenseType" }
    if ($WaitMinutes) { $command += " --wait $WaitMinutes" }
    if ($NoPrompt) { $command += " --no-prompt" }
    if ($NoTrackSource) { $command += " --no-track-source" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Resume-SalesforceSandbox {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $SandboxName,
        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $command = "sf org resume sandbox --name $SandboxName"
    if ($WaitMinutes) { $command += " --wait $WaitMinutes" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Copy-SalesforceSandbox {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $SourceSandboxName,
        [Parameter(Mandatory = $true)][string] $CloneSandboxName,
        [Parameter(Mandatory = $false)][string] $LicenseType,
        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $command = "sf org clone sandbox --name $SourceSandboxName --clone-name $CloneSandboxName"
    if ($LicenseType) { $command += " --license-type $LicenseType" }
    if ($Alias) { $command += " --alias $Alias" }
    if ($WaitMinutes) { $command += " --wait $WaitMinutes" }
    if ($NoPrompt) { $command += " --no-prompt" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceSandbox {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $command = "sf org delete sandbox"
    if ($NoPrompt) { $command += " --no-prompt" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceSandboxRefreshStatus {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $escapedName = $Name -replace "'", "''"

    $infoQuery = "SELECT SandboxName, LicenseType FROM SandboxInfo WHERE SandboxName = '$escapedName'"
    $infoCommand = "sf data query --use-tooling-api --result-format json --query `"$infoQuery`""
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $infoCommand += " --target-org $TargetOrg" }

    $infoResult = Invoke-Salesforce -Command $infoCommand | ConvertFrom-Json
    if ($infoResult.status -ne 0) {
        Write-Debug ($infoResult | ConvertTo-Json -Depth 5)
        throw $infoResult.message
    }

    $infoRecords = @($infoResult.result.records | Select-Object -ExcludeProperty attributes)
    if ($infoRecords.Count -eq 0) {
        return @()
    }

    $licenseType = $infoRecords[0].LicenseType

    $processQuery = "SELECT SandboxName, StartDate, EndDate FROM SandboxProcess WHERE SandboxName = '$escapedName' ORDER BY StartDate DESC LIMIT 1"
    $processCommand = "sf data query --use-tooling-api --result-format json --query `"$processQuery`""
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $processCommand += " --target-org $TargetOrg" }

    $processResult = Invoke-Salesforce -Command $processCommand | ConvertFrom-Json
    if ($processResult.status -ne 0) {
        Write-Debug ($processResult | ConvertTo-Json -Depth 5)
        throw $processResult.message
    }

    $processRecords = @($processResult.result.records | Select-Object -ExcludeProperty attributes)

    $lastRefreshed = $null
    if ($processRecords.Count -gt 0 -and $processRecords[0].EndDate) {
        try {
            $lastRefreshed = [datetime]::Parse($processRecords[0].EndDate)
        } catch {
            Write-Warning "Unable to parse sandbox EndDate '$($processRecords[0].EndDate)' as datetime."
        }
    }

    $nextRefresh = $null
    if ($lastRefreshed) {
        switch ($licenseType) {
            'Developer' { $nextRefresh = $lastRefreshed.AddDays(1) }
            'Developer_Pro' { $nextRefresh = $lastRefreshed.AddDays(1) }
            'Partial' { $nextRefresh = $lastRefreshed.AddDays(5) }
            'Full' { $nextRefresh = $lastRefreshed.AddDays(29) }
        }
    }

    return @([pscustomobject]@{
        Name = $Name
        LicenseType = $licenseType
        LastRefreshed = $lastRefreshed
        NextRefreshDate = $nextRefresh
    })
}

#endregion
