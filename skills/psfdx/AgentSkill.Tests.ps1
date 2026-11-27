BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $root 'psfdx-data/psfdx-data.psd1') -Force -DisableNameChecking
    $skill = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'SKILL.md') -Raw
    $examples = [regex]::Matches($skill, '(?ms)^```powershell\r?\n(.*?)^```')
    $read = [scriptblock]::Create($examples[0].Groups[1].Value)
    $group = [scriptblock]::Create($examples[1].Groups[1].Value)

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
