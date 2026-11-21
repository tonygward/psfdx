function Test-SalesforceApexTestReference {
    <#
    .SYNOPSIS
    Checks whether an Apex test file references a particular Apex class.
    .DESCRIPTION
    Returns True if the test file's base name follows Test<ClassName>, <ClassName>Test,
    or <ClassName>Tests (case-insensitive), or if the contents contain ClassName as
    a whole word. Does not count partial name matches such as Account within
    AccountHelperTest. This performs a local file/text check, not an Apex test run.
    .PARAMETER Path
    Path of the Apex test file (.cls) to examine. The file is read only when its
    name does not already match a supported test naming convention.
    .PARAMETER ClassName
    Apex class name to match, either in the test file name or as a whole word
    in the file contents.
    .EXAMPLE
    Test-SalesforceApexTestReference -Path './classes/AccountServiceTest.cls' -ClassName 'AccountService'
    Returns True based on the test class name.
    .EXAMPLE
    Test-SalesforceApexTestReference -Path './classes/CustomTests.cls' -ClassName 'AccountService'
    Checks the contents for an AccountService reference.
    .NOTES
    Underlying Salesforce CLI command: None. Uses local PowerShell Select-String
    and .NET regex/path matching; does not invoke sf or contact an org.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $ClassName
    )

    $escaped = [regex]::Escape($ClassName)

    $testClassName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ($testClassName -imatch "^(Test$escaped|$escaped(Test|Tests))$") {
        return $true
    }

    return [bool](Select-String -Path $Path -Pattern "\b$escaped\b" -Quiet)
}

function Get-SalesforceApexCliTestArguments {
    <#
    .SYNOPSIS
    Builds Salesforce CLI deployment test-selection arguments.
    .DESCRIPTION
    Returns a string array containing --test-level and, where applicable, repeated
    --tests flags for Apex classes. Resolves specified, referenced, or folder-based
    Apex tests locally. This helper builds arguments; it does not run a deployment.
    Test-level mapping: NoTests=NoTestRun, SpecificTests/ReferencedTests/TestsInFolder=
    RunSpecifiedTests, TestsInOrg=RunLocalTests, TestsInOrgAndPackages=
    RunAllTestsInOrg, RelevantTests=RunRelevantTests.
    .PARAMETER SourceDir
    Apex source file for ReferencedTests; folder or file whose directory is
    searched for TestsInFolder. If omitted with TestsInFolder, uses current directory.
    .PARAMETER TestLevel
    Test selection mode. Default: NoTests. Valid values: NoTests, SpecificTests,
    ReferencedTests, TestsInFolder, TestsInOrg, TestsInOrgAndPackages, RelevantTests.
    ReferencedTests requires SourceDir; SpecificTests requires non-empty Tests.
    .PARAMETER Tests
    Apex test class names when TestLevel is SpecificTests. Blank values are removed
    and duplicates deduplicated for that mode. Emits one --tests flag per name.
    .EXAMPLE
    Get-SalesforceApexCliTestArguments -TestLevel SpecificTests -Tests AccountServiceTest,ContactServiceTest
    Produces --test-level RunSpecifiedTests with two --tests arguments.
    .EXAMPLE
    Get-SalesforceApexCliTestArguments -TestLevel TestsInFolder -SourceDir './force-app/main/default/classes'
    Searches the directory recursively for .cls files containing @isTest and
    emits RunSpecifiedTests with the discovered test class names.
    .NOTES
    Underlying Salesforce CLI command: None. Produces flags for supported
    sf project deploy commands; the caller selects and invokes the command.
    Validation requirements differ by command (for example, deploy validate
    does not support NoTestRun). This helper does not check command compatibility.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $SourceDir,
        [Parameter(Mandatory = $false)][ValidateSet(
            'NoTests',
            'SpecificTests',
            'ReferencedTests',
            'TestsInFolder',
            'TestsInOrg',
            'TestsInOrgAndPackages',
            'RelevantTests')][string] $TestLevel = 'NoTests',
        [Parameter(Mandatory = $false)][string[]] $Tests
    )

    $value = @()
    $testLevelMap = @{
        'NoTests'               = 'NoTestRun'
        'SpecificTests'         = 'RunSpecifiedTests'
        'ReferencedTests'       = 'RunSpecifiedTests'
        'TestsInFolder'         = 'RunSpecifiedTests'
        'TestsInOrg'            = 'RunLocalTests'
        'TestsInOrgAndPackages' = 'RunAllTestsInOrg'
        'RelevantTests'         = 'RunRelevantTests'
    }
    $value += @('--test-level', $testLevelMap[$TestLevel])

    if ($TestLevel -eq 'ReferencedTests') {
        if (-not $SourceDir) {
            throw "Specify -SourceDir when using -TestLevel ReferencedTests."
        }
        if (-not (Test-Path -LiteralPath $SourceDir)) {
            throw "Source path '$SourceDir' does not exist."
        }

        $item = Get-Item -LiteralPath $SourceDir
        if ($item.PSIsContainer) {
            throw "Provide a file path for -SourceDir when using -TestLevel ReferencedTests."
        }

        $className = [System.IO.Path]::GetFileNameWithoutExtension($item.Name)
        if (-not $className) {
            throw "Unable to determine class name from '$SourceDir'."
        }

        $searchRoot = $item.Directory
        if (-not $searchRoot) {
            throw "Unable to determine directory for '$SourceDir'."
        }

        $Tests = Get-ChildItem -LiteralPath $searchRoot.FullName -Filter '*.cls' -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -ne $item.FullName -and
                (Select-String -Path $_.FullName -Pattern '@isTest' -SimpleMatch -Quiet) -and
                (Test-SalesforceApexTestReference -Path $_.FullName -ClassName $className)
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

    Write-Verbose "Test Level: $TestLevel found Tests: $Tests"

    foreach ($test in @($Tests | Where-Object { $_ -and $_.Trim() })) {
        $value += @('--tests', $test.Trim())
    }
    return [string[]]$value
}

function Get-SalesforceApexTestClassNamesFromPath {
    <#
    .SYNOPSIS
    Finds Apex test class names in a local folder tree.
    .DESCRIPTION
    Searches recursively for .cls files containing the literal @isTest marker,
    returning unique file base names sorted alphabetically. If Path is a file,
    searches from its parent directory instead. Throws if the path does not exist.
    An empty search returns an empty array.
    .PARAMETER Path
    Existing folder or file whose parent folder is searched recursively.
    .EXAMPLE
    Get-SalesforceApexTestClassNamesFromPath -Path './force-app/main/default/classes'
    Lists the Apex test classes discovered under the classes directory.
    .NOTES
    Underlying Salesforce CLI command: None. Uses local PowerShell filesystem
    and text search commands; does not invoke sf or connect to Salesforce.
    #>
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
