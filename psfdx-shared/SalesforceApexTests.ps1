function Get-SalesforceApexCliTestParams {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $SourceDir,
        [Parameter(Mandatory = $false)][ValidateSet('NoTests', 'SpecificTests', 'TestsInFolder', 'TestsInOrg', 'TestsInOrgAndPackages')][string] $TestLevel = 'NoTests',
        [Parameter(Mandatory = $false)][string[]] $Tests
    )

    $testLevelMap = @{
        'NoTests'               = 'NoTestRun'
        'SpecificTests'         = 'RunSpecifiedTests'
        'TestsInFolder'         = 'RunSpecifiedTests'
        'TestsInOrg'            = 'RunLocalTests'
        'TestsInOrgAndPackages' = 'RunAllTestsInOrg'
    }
    $value += " --test-level " + $testLevelMap[$TestLevel]

    if ($TestLevel -eq 'TestsInFolder') {
        $TestsPath = $SourceDir
        if (-not $TestsPath) {
            $TestsPath = Get-Location
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
