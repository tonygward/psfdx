# Offline checks for the opt-in integration lane. They need no org: they prove the report tells setup failures from psfdx regressions,
# that the real tests are skipped without opt-in, that they only call commands psfdx exports, and that the workflow keeps its safety rules.

BeforeAll {
    $script:Here = $PSScriptRoot
    $script:Root = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:Report = Join-Path $script:Here 'Write-IntegrationReport.ps1'
    $script:Out = Join-Path $TestDrive 'report'
    function Invoke-Report([string] $Setup, [string] $Tests, [string] $Teardown, [string] $Xml) {
        $params = @{ OutputDirectory = $script:Out; SetupOutcome = $Setup; TestOutcome = $Tests; TeardownOutcome = $Teardown; SfVersion = '2.99.1'; PwshVersion = '7.5.0'; ModuleVersion = '0.8.30'; CommitSha = 'abc1234'; RunUrl = 'https://example.test/run/1' }
        if ($Xml) { $params['TestResultsXml'] = $Xml }
        & $script:Report @params
        return (Get-Content -LiteralPath (Join-Path $script:Out 'integration-report.json') -Raw | ConvertFrom-Json)
    }
}

Describe 'Integration report' {
    It 'passes when every phase succeeded, and records the exact versions' {
        $r = Invoke-Report 'success' 'success' 'success' $null
        $r.verdict | Should -Be 'passed'
        $r.failureKind | Should -Be 'none'
        $r.versions.salesforceCli | Should -Be '2.99.1'
        $r.versions.psfdx | Should -Be '0.8.30'
        $r.versions.commit | Should -Be 'abc1234'
    }
    It 'reports a failed setup as a setup failure, never as a psfdx regression' {
        $r = Invoke-Report 'failure' 'skipped' 'success' $null
        $r.verdict | Should -Be 'setup-failed'
        $r.failureKind | Should -Be 'setup'
        (Get-Content -LiteralPath (Join-Path $script:Out 'integration-report.md') -Raw) | Should -BeLike '*not evidence of a psfdx regression*'
    }
    It 'reports failing tests as a psfdx regression' {
        $r = Invoke-Report 'success' 'failure' 'success' $null
        $r.verdict | Should -Be 'tests-failed'
        $r.failureKind | Should -Be 'psfdx-regression'
    }
    It 'reports a failed teardown separately, so a leaked org is not missed' {
        $r = Invoke-Report 'success' 'success' 'failure' $null
        $r.verdict | Should -Be 'teardown-failed'
        $r.failureKind | Should -Be 'teardown'
    }
    It 'puts a setup failure ahead of a teardown failure' {
        (Invoke-Report 'failure' 'skipped' 'failure' $null).failureKind | Should -Be 'setup'
    }
    It 'lists each test with its result and duration from the Pester NUnit file' {
        $xml = Join-Path $TestDrive 'testResults.xml'
        Set-Content -LiteralPath $xml -Value '<test-results><test-suite><results><test-case name="queries a record" result="Success" time="1.25"/><test-case name="deploys" result="Failure" time="3.5"/></results></test-suite></test-results>'
        $r = Invoke-Report 'success' 'failure' 'success' $xml
        @($r.tests).Count | Should -Be 2
        $r.tests[0].name | Should -Be 'queries a record'
        $r.tests[1].result | Should -Be 'Failure'
        $r.tests[0].seconds | Should -Be 1.25
        (Get-Content -LiteralPath (Join-Path $script:Out 'integration-report.md') -Raw) | Should -BeLike '*| deploys | Failure |*'
    }
    It 'survives a missing or malformed results file' {
        @((Invoke-Report 'success' 'success' 'success' (Join-Path $TestDrive 'none.xml')).tests).Count | Should -Be 0
        $bad = Join-Path $TestDrive 'bad.xml'
        Set-Content -LiteralPath $bad -Value 'not xml'
        @((Invoke-Report 'success' 'success' 'success' $bad).tests).Count | Should -Be 0
    }
    It 'contains nothing that looks like a credential' {
        Invoke-Report 'success' 'success' 'success' $null | Out-Null
        $text = (Get-Content -LiteralPath (Join-Path $script:Out 'integration-report.json') -Raw) + (Get-Content -LiteralPath (Join-Path $script:Out 'integration-report.md') -Raw)
        $text | Should -Not -Match '(?i)force://|accessToken|sfdxAuthUrl|refresh_token|password'
    }
}

Describe 'Integration tests are opt-in and well-formed' {
    It 'skips every real test unless PSFDX_INTEGRATION=1 and an org are set' {
        $text = Get-Content -LiteralPath (Join-Path $script:Here 'Psfdx.Integration.Tests.ps1') -Raw
        $text | Should -Match "PSFDX_INTEGRATION -eq '1'"
        $text | Should -Match 'PSFDX_INTEGRATION_ORG'
        $text | Should -Match "Describe 'psfdx against a real scratch org' -Skip:\(-not \`$script:Enabled\)"
        $text | Should -Not -Match '(?i)\b(production|login\.salesforce\.com)\b.*-TargetOrg'
    }
    It 'only calls psfdx commands that the manifests export' {
        $file = Join-Path $script:Here 'Psfdx.Integration.Tests.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref] $null, [ref] $null)
        $called = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ -match '^(Get|New|Set|Select|Deploy|Retrieve|Test|Start|Wait|Upsert)-Salesforce' } | Sort-Object -Unique
        $exported = foreach ($name in 'psfdx-core', 'psfdx-metadata', 'psfdx-development') {
            (Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root $name) "$name.psd1")).FunctionsToExport
        }
        @($called).Count | Should -BeGreaterThan 5
        foreach ($c in $called) { $exported | Should -Contain $c -Because "$c is called by the integration tests" }
    }
    It 'has a fixture project whose manifest names classes that exist' {
        $fixtures = Join-Path $script:Here 'fixtures'
        [xml] $manifest = Get-Content -LiteralPath (Join-Path (Join-Path $fixtures 'manifest') 'package.xml') -Raw
        foreach ($m in @($manifest.Package.types.members)) {
            Test-Path -LiteralPath (Join-Path $fixtures "force-app\main\default\classes\$m.cls") | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $fixtures "force-app\main\default\classes\$m.cls-meta.xml") | Should -BeTrue
        }
    }
}

Describe 'Integration workflow keeps its safety rules' {
    BeforeAll {
        $script:Workflow = Get-Content -LiteralPath (Join-Path (Join-Path (Join-Path $script:Root '.github') 'workflows') 'housekeeping-integration.yml') -Raw
    }
    It 'runs only by hand or on a schedule, never on a pull request' {
        $script:Workflow | Should -Match '(?m)^\s*workflow_dispatch:'
        $script:Workflow | Should -Not -Match '(?m)^\s*pull_request'
        $script:Workflow | Should -Not -Match '(?m)^\s*push:'
    }
    It 'uses a protected environment, read-only permissions, one run at a time, and a time limit' {
        $script:Workflow | Should -Match 'environment:\s*scratch-org-integration'
        $script:Workflow | Should -Match '(?m)^permissions:\s*\r?\n\s+contents:\s*read'
        $script:Workflow | Should -Match 'concurrency:'
        $script:Workflow | Should -Match 'timeout-minutes:'
    }
    It 'always deletes the scratch org and always writes the report' {
        $script:Workflow | Should -Match '(?s)name: Teardown.*?if:\s*always\(\)'
        $script:Workflow | Should -Match '(?s)name: Write the report.*?if:\s*always\(\)'
    }
    It 'masks the credential, keeps it out of arguments, and never echoes it' {
        $script:Workflow | Should -Match '::add-mask::'
        $script:Workflow | Should -Not -Match '(?i)echo(?![^\n]*::(add-mask|error)::)[^\n]*SF_DEVHUB_AUTH_URL'
        $script:Workflow | Should -Match '--sfdx-url-file'
    }
    It 'installs the latest stable CLI, never a pinned or release-candidate one' {
        $script:Workflow | Should -Match '@salesforce/cli@latest'
    }
}
