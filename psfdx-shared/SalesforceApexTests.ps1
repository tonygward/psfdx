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
        [ValidateNotNullOrEmpty()]
        [string[]] $TestClassNames
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
