BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    # Remove any installed copies first, so the examples run against the repository modules and their mocks, never a real org.
    Get-Module -Name 'psfdx', 'psfdx-data' -All | ForEach-Object {
        try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
    }
    Import-Module (Join-Path (Join-Path $root 'psfdx') 'psfdx.psd1') -Force -DisableNameChecking
    Import-Module (Join-Path (Join-Path $root 'psfdx-data') 'psfdx-data.psd1') -Force -DisableNameChecking
    $skill = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'SKILL.md') -Raw
    $examples = @([regex]::Matches($skill, '(?ms)^```powershell\r?\n(.*?)^```') | ForEach-Object { $_.Groups[1].Value })

    # Finds each example by what it does, not by its position, so adding an example does not break the others.
    function Get-SkillExample([string] $Pattern) {
        $found = @($examples | Where-Object { $_ -match $Pattern })
        if ($found.Count -ne 1) { throw "Expected one SKILL.md example matching '$Pattern', found $($found.Count)." }
        [scriptblock]::Create($found[0])
    }
    $orgCheck = Get-SkillExample '^Get-SalesforceOrgDetails '
    $read = Get-SkillExample '^Select-SalesforceRecords .*SELECT Id, Name FROM Account'
    $group = Get-SkillExample 'Group-Object'

    # A fixture for stdout from sf. This test never starts the CLI or connects to an org.
    function sf { $script:reply }
    $rawRead = {
        $response = sf data query --query 'SELECT Id, Name FROM Account LIMIT 10' --target-org my-sandbox --json | ConvertFrom-Json
        if ($response.status -ne 0) { throw $response.message }
        $response.result.records | Select-Object Id, Name
    }
    $rawGroup = {
        $response = sf data query --query 'SELECT Industry FROM Account WHERE Industry != null LIMIT 100' --target-org my-sandbox --json | ConvertFrom-Json
        if ($response.status -ne 0) { throw $response.message }
        $response.result.records |
            Group-Object -Property Industry |
            Select-Object Name, Count |
            Sort-Object Count -Descending
    }
}

Describe 'PSFDX agent skill examples' {
    BeforeEach {
        Mock Invoke-Salesforce -ModuleName psfdx-data { $script:reply }
        Mock Invoke-Salesforce -ModuleName psfdx { $script:reply }
    }

    It 'checks the target org without putting a token or authorization URL in the output' {
        $script:reply = '{"status":0,"result":{"id":"00Dfixture","username":"agent@example.com","instanceUrl":"https://fixture.my.salesforce.com","accessToken":"00Dfixture!SECRET","sfdxAuthUrl":"force://SECRET@fixture","clientId":"PlatformCLI","connectedStatus":"Connected"}}'
        $actual = & $orgCheck | ConvertTo-Json -Compress
        $actual | Should -BeExactly '{"id":"00Dfixture","username":"agent@example.com","instanceUrl":"https://fixture.my.salesforce.com"}'
        $actual | Should -Not -Match 'SECRET'
        Should -Invoke Invoke-Salesforce -ModuleName psfdx -Exactly -Times 1 -ParameterFilter {
            $FilePath -eq 'sf' -and ($Arguments -join '|') -eq 'org|display|--target-org|my-sandbox|--json'
        }
    }

    It 'returns the same bounded account projection as the raw CLI baseline' {
        $script:reply = '{"status":0,"result":{"records":[{"attributes":{"type":"Account"},"Id":"001fixture","Name":"Acme"}],"totalSize":1,"done":true}}'
        $actual = & $read | ConvertTo-Json -Compress
        $expected = & $rawRead | ConvertTo-Json -Compress
        $actual | Should -BeExactly $expected
        $actual | Should -BeExactly '{"Id":"001fixture","Name":"Acme"}'
        (Get-Help Select-SalesforceRecords -Examples).examples.example | Should -Not -BeNullOrEmpty
        (Get-Command Select-SalesforceRecords).Parameters.Keys | Should -Contain 'TargetOrg'
        Should -Invoke Invoke-Salesforce -ModuleName psfdx-data -Exactly -Times 1 -ParameterFilter {
            $FilePath -eq 'sf' -and ($Arguments -join '|') -eq 'data|query|--query|SELECT Id, Name FROM Account LIMIT 10|--target-org|my-sandbox|--result-format|json'
        }
    }

    It 'produces the same grouped summary and output size as the raw CLI baseline' {
        $script:reply = '{"status":0,"result":{"records":[{"attributes":{"type":"Account"},"Industry":"Energy"},{"attributes":{"type":"Account"},"Industry":"Media"},{"attributes":{"type":"Account"},"Industry":"Energy"}],"totalSize":3,"done":true}}'
        $actual = & $group | ConvertTo-Json -Compress
        $expected = & $rawGroup | ConvertTo-Json -Compress
        $actual | Should -BeExactly $expected
        $actual | Should -BeExactly '[{"Name":"Energy","Count":2},{"Name":"Media","Count":1}]'
        [Text.Encoding]::UTF8.GetByteCount($actual) | Should -BeLessThan ([Text.Encoding]::UTF8.GetByteCount($script:reply))
        @((($group.ToString()) -split '\r?\n') | Where-Object { $_.Trim() }).Count |
            Should -BeLessThan @((($rawGroup.ToString()) -split '\r?\n') | Where-Object { $_.Trim() }).Count
    }

    It 'surfaces a CLI failure in both workflows rather than returning empty data' {
        $script:reply = '{"status":1,"message":"Fixture org is unavailable."}'
        { & $read } | Should -Throw '*Fixture org is unavailable*'
        { & $group } | Should -Throw '*Fixture org is unavailable*'
        { & $rawRead } | Should -Throw '*Fixture org is unavailable*'
        { & $rawGroup } | Should -Throw '*Fixture org is unavailable*'
    }
}

Describe 'PSFDX agent skill content' {
    It 'never tells the agent to run a command whose output contains the access token' {
        foreach ($example in $examples) {
            $example | Should -Not -Match '(?m)^\s*sf\s+org\s+display' -Because 'raw sf org display prints the access token'
            $example | Should -Not -Match '-IncludeToken'
        }
    }

    It 'links only to files inside the skill folder, so an installed copy of the folder has no broken links' {
        $links = @([regex]::Matches($skill, '\]\(([^)#\s]+)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notmatch '^[a-z]+:' })
        $links.Count | Should -BeGreaterThan 0
        foreach ($link in $links) {
            $link | Should -Not -Match '\.\.' -Because "$link points outside the skill folder"
            Test-Path -LiteralPath (Join-Path $PSScriptRoot $link) -PathType Leaf | Should -BeTrue -Because "SKILL.md links to $link"
        }
    }

    It 'ships the same command reference as docs/reference' {
        $docs = Join-Path (Join-Path $root 'docs') 'reference'
        $copy = Join-Path $PSScriptRoot 'references'
        $expected = @(Get-ChildItem -LiteralPath $docs -Filter *.md | ForEach-Object Name | Sort-Object)
        $expected.Count | Should -BeGreaterThan 0
        @(Get-ChildItem -LiteralPath $copy -Filter *.md | ForEach-Object Name | Sort-Object) | Should -Be $expected
        foreach ($name in $expected) {
            [System.IO.File]::ReadAllText((Join-Path $copy $name)).Replace("`r`n", "`n") |
                Should -BeExactly ([System.IO.File]::ReadAllText((Join-Path $docs $name)).Replace("`r`n", "`n")) -Because "skills/psfdx/references/$name is generated with docs/reference/$name; run pwsh ./site/Update-ModuleReference.ps1"
        }
    }
}
