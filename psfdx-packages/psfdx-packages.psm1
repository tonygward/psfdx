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

#region Packages

function Get-SalesforcePackages {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $ExtendedPackageDetails
    )
    $command = "sf package list"
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }
    if ($ExtendedPackageDetails) { $command += " --verbose" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Get-SalesforcePackage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $ExtendedPackageDetails
    )
    if ($TargetDevHub) {
        $packages = Get-SalesforcePackages -TargetDevHub $TargetDevHub -ExtendedPackageDetails:$ExtendedPackageDetails
    } else {
        $packages = Get-SalesforcePackages -ExtendedPackageDetails:$ExtendedPackageDetails
    }
    return $packages | Where-Object Name -eq $Name
}

function New-SalesforcePackage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string][ValidateSet("Managed", "Unlocked")] $PackageType = "Unlocked",
        [Parameter(Mandatory = $false)][switch] $IsOrgDependent,
        [Parameter(Mandatory = $false)][string] $Path = "force-app/main/default",
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $ErrorNotificationUsername,
        [Parameter(Mandatory = $false)][switch] $NoNamespace,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    $command = "sf package create --name $Name"
    $command += " --package-type $PackageType"
    $command += " --path $Path"
    if ($IsOrgDependent) { $command += " --org-dependent" }
    if ($Description) { $command += " --description $Description" }
    if ($ErrorNotificationUsername) { $command += " --error-notification-username $ErrorNotificationUsername" }
    if ($NoNamespace) { $command += " --no-namespace" }
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    $resultSfdx = Show-SalesforceResult -Result $result
    return $resultSfdx.Id
}

function Remove-SalesforcePackage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $command = "sf package delete --package $Name"
    if ($NoPrompt) { $command += " --no-prompt" }
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }
    Invoke-Salesforce -Command $command
}

#endregion

#region Package Versions

function Get-SalesforcePackageVersions {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $PackageId,
        [Parameter(Mandatory = $false)][string] $PackageName,
        [Parameter(Mandatory = $false)][switch] $Released,
        [Parameter(Mandatory = $false)][switch] $Concise,
        [Parameter(Mandatory = $false)][switch] $ExtendedDetails,
        [Parameter(Mandatory = $false)][switch] $ConversionsOnly,
        [Parameter(Mandatory = $false)][string] $Branch,
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )
    if ((! $PackageId ) -and ($PackageName) ) {
        if ($TargetDevHub) {
            $package = Get-SalesforcePackage -Name $PackageName -TargetDevHub $TargetDevHub
        } else {
            $package = Get-SalesforcePackage -Name $PackageName
        }
        $PackageId = $package.Id
    }

    $command = "sf package version list"
    if ($PackageId) { $command += " --packages $PackageId" }
    if ($Released) { $command += " --released" }
    if ($Concise) { $command += " --concise" }
    if ($ExtendedDetails) { $command += " --verbose" }
    if ($ConversionsOnly) { $command += " --show-conversions-only" }
    if ($Branch) { $command += " --branch $Branch" }
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function New-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $PackageId,
        [Parameter(Mandatory = $false)][string] $PackageName,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $Tag,

        [Parameter(Mandatory = $false)][string] $InstallationKey,
        [Parameter(Mandatory = $false)][switch] $InstallationKeyBypass,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][switch] $SkipValidation,

        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string] $ScratchOrgDefinitionFile = "config/project-scratch-def.json",
        [Parameter(Mandatory = $false)][string] $TargetDevHub
    )

    if ((! $PackageId ) -and (! $PackageName) ) {
        throw "Please provide a PackageId or Package Name"
    }
    if ((! $PackageId ) -and ($PackageName) ) {
        if ($TargetDevHub) {
            $package = Get-SalesforcePackage -Name $PackageName -TargetDevHub $TargetDevHub
        } else {
            $package = Get-SalesforcePackage -Name $PackageName
        }
        $PackageId = $package.Id
    }

    $command = "sf package version create --package $PackageId"
    if ($Name) { $command += " --version-name $Name" }
    if ($Description) { $command += " --version-description $Description" }
    if ($Tag) { $command += " --tag $Tag" }
    if ($CodeCoverage) { $command += " --code-coverage" }
    $command += " --definition-file $ScratchOrgDefinitionFile"

    if (($InstallationKeyBypass) -or (! $InstallationKey)) {
        $command += " --installation-key-bypass"
    } else {
        $command += " --installation-key $InstallationKey"
    }

    if ($SkipValidation) { $command += " --skip-validation" }
    if ($WaitMinutes) { $command += " --wait $WaitMinutes" }
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }

    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Promote-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )

    $command = "sf package version promote"
    $command += " --package $PackageVersionId"
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }
    if ($NoPrompt) { $command += " --no-prompt" }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )

    $command = "sf package version delete"
    $command += " --package $PackageVersionId"
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }
    if ($NoPrompt) { $command += " --no-prompt" }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Install-SalesforcePackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $PackageVersionId,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][int] $WaitMinutes = 10,
        [Parameter(Mandatory = $false)][ValidateSet('AllUsers','AdminsOnly')][string] $SecurityType = 'AdminsOnly'
    )

    $command = "sf package install"
    $command += " --package $PackageVersionId"
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    if ($NoPrompt) { $command += " --no-prompt" }
    if ($SecurityType) { $command += " --security-type $SecurityType" }
    if ($WaitMinutes) {
        $command += " --wait $WaitMinutes"
        $command += " --publish-wait $WaitMinutes"
    }
    Invoke-Salesforce -Command $command
}

#endregion
