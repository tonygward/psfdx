[CmdletBinding()]
Param(
    # Where to write integration-report.json and integration-report.md.
    [Parameter(Mandatory = $true)][string] $OutputDirectory,
    # Outcome of each phase as GitHub Actions reports it: success, failure, cancelled or skipped.
    [Parameter(Mandatory = $true)][string] $SetupOutcome,
    [Parameter(Mandatory = $true)][string] $TestOutcome,
    [Parameter(Mandatory = $true)][string] $TeardownOutcome,
    # The NUnit XML Pester wrote for the test phase, if it got that far.
    [Parameter(Mandatory = $false)][string] $TestResultsXml,
    [Parameter(Mandatory = $false)][string] $SfVersion = 'unknown',
    [Parameter(Mandatory = $false)][string] $PwshVersion = 'unknown',
    [Parameter(Mandatory = $false)][string] $ModuleVersion = 'unknown',
    [Parameter(Mandatory = $false)][string] $CommitSha = 'unknown',
    [Parameter(Mandatory = $false)][string] $RunUrl = ''
)

# Writes the integration result report. It names WHICH PHASE failed so a reader can tell an org or credential problem from a psfdx
# regression: a failed setup (login, scratch org creation) means the tests never ran and says nothing about psfdx; a failed test phase
# is a psfdx regression (or a bad test); a failed teardown is a clean-up problem to fix by hand. The report holds no secrets: only
# versions, outcomes, test names and durations.

$setupOk = $SetupOutcome -eq 'success'
$testsOk = $TestOutcome -eq 'success'
$teardownOk = $TeardownOutcome -eq 'success'
$verdict = 'passed'
$failureKind = 'none'
if (-not $setupOk) {
    $verdict = 'setup-failed'; $failureKind = 'setup'
} elseif (-not $testsOk) {
    $verdict = 'tests-failed'; $failureKind = 'psfdx-regression'
} elseif (-not $teardownOk) {
    $verdict = 'teardown-failed'; $failureKind = 'teardown'
}

$tests = @()
if ($TestResultsXml -and (Test-Path -LiteralPath $TestResultsXml -PathType Leaf)) {
    try {
        [xml] $xml = Get-Content -LiteralPath $TestResultsXml -Raw
        foreach ($case in $xml.SelectNodes('//test-case')) {
            $seconds = 0.0
            [void] [double]::TryParse([string] $case.time, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref] $seconds)
            $tests += [pscustomobject]@{ name = [string] $case.name; result = [string] $case.result; seconds = $seconds }
        }
    } catch {
        $tests = @()
    }
}

$report = [ordered]@{
    verdict     = $verdict
    failureKind = $failureKind
    versions    = [ordered]@{ salesforceCli = $SfVersion; powershell = $PwshVersion; psfdx = $ModuleVersion; commit = $CommitSha }
    runUrl      = $RunUrl
    phases      = [ordered]@{ setup = $SetupOutcome; tests = $TestOutcome; teardown = $TeardownOutcome }
    tests       = $tests
}

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }
$jsonPath = Join-Path -Path $OutputDirectory -ChildPath 'integration-report.json'
$mdPath = Join-Path -Path $OutputDirectory -ChildPath 'integration-report.md'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($jsonPath, ($report | ConvertTo-Json -Depth 5), $utf8)

$meaning = switch ($verdict) {
    'passed'          { 'Setup, tests and teardown all succeeded.' }
    'setup-failed'    { 'Setup failed (login or scratch org creation), so the tests did not run. This is not evidence of a psfdx regression: check the Dev Hub credentials, scratch org allocation and Salesforce status.' }
    'tests-failed'    { 'The org was ready but one or more psfdx tests failed. Treat this as a psfdx regression (or a broken test) until shown otherwise.' }
    'teardown-failed' { 'The tests passed but the scratch org was not deleted. Delete it by hand (it also expires on its own) and check the teardown step.' }
}
$lines = @('## psfdx scratch org integration', '', "**Result: $verdict.** $meaning", '',
    "| Salesforce CLI | PowerShell | psfdx | Commit |", '|---|---|---|---|',
    "| $SfVersion | $PwshVersion | $ModuleVersion | $CommitSha |", '',
    '| Phase | Outcome |', '|---|---|', "| Setup | $SetupOutcome |", "| Tests | $TestOutcome |", "| Teardown | $TeardownOutcome |", '')
if ($tests.Count -gt 0) {
    $lines += @('| Test | Result | Seconds |', '|---|---|---|')
    foreach ($t in $tests) { $lines += "| $($t.name) | $($t.result) | $([math]::Round($t.seconds, 1)) |" }
    $lines += ''
}
if ($RunUrl) { $lines += "Run: $RunUrl"; $lines += '' }
[System.IO.File]::WriteAllText($mdPath, ($lines -join "`n"), $utf8)
