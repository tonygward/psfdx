BeforeAll {
    $moduleManifest = Join-Path $PSScriptRoot 'psfdx-logs.psd1'
    Import-Module $moduleManifest -Force
}

Describe 'Watch-SalesforceLogs' {
    BeforeEach {
        # Default mock to capture commands
        Mock -ModuleName 'psfdx-logs' Invoke-Sf {}
    }

    It 'builds base command with color' {
        Watch-SalesforceLogs | Out-Null
        Assert-MockCalled -ModuleName 'psfdx-logs' Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log tail --color' }
    }

    It 'adds username when provided' {
        Watch-SalesforceLogs -Username 'user@example' | Out-Null
        Assert-MockCalled -ModuleName 'psfdx-logs' Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log tail --target-org user@example --color' }
    }

    It 'adds skip trace flag' {
        Watch-SalesforceLogs -SkipTraceFlag | Out-Null
        Assert-MockCalled -ModuleName 'psfdx-logs' Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log tail --skip-trace-flag --color' }
    }

    It 'adds debug level when provided' {
        Watch-SalesforceLogs -DebugLevel 'SFDC_DevConsole' | Out-Null
        Assert-MockCalled -ModuleName 'psfdx-logs' Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log tail --debug-level SFDC_DevConsole --color' }
    }
}

Describe 'Get-SalesforceLogs' {
    BeforeEach {
        Mock -ModuleName 'psfdx-logs' Invoke-Sf { '{"status":0,"result":[{"Id":"1"}]}' }
        Mock -ModuleName 'psfdx-logs' Show-SfResult { return @(@{ Id = '1' }) }
    }

    It 'lists logs with json' {
        $out = Get-SalesforceLogs
        $out | Should -Not -BeNullOrEmpty
        Assert-MockCalled -ModuleName 'psfdx-logs' Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log list --json' }
        Assert-MockCalled -ModuleName 'psfdx-logs' Show-SfResult -Times 1
    }

    It 'adds username when provided' {
        Get-SalesforceLogs -Username 'user@example' | Out-Null
        Assert-MockCalled -ModuleName 'psfdx-logs' Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log list --target-org user@example --json' }
    }
}

Describe 'Get-SalesforceLog' {
    BeforeEach {
        # Default successful response from sf
        $jsonOk = '{"status":0,"result":{"log":"LOGDATA"}}'
        Mock -ModuleName 'psfdx-logs' Invoke-Sf { $jsonOk }
    }

    It 'requires either LogId or Last' {
        { Get-SalesforceLog -Username 'user' } | Should -Throw
    }

    It 'fetches by LogId and returns log text' {
        $log = Get-SalesforceLog -LogId '07Lxx0000000001' -Username 'user'
        $log | Should -Be 'LOGDATA'
        Assert-MockCalled -ModuleName 'psfdx-logs' Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log get --log-id 07Lxx0000000001 --target-org user --json' }
    }

    It 'uses -Last to get latest log id' {
        $logs = @(
            [pscustomobject]@{ Id = '2'; StartTime = [datetime]'2020-01-02' },
            [pscustomobject]@{ Id = '1'; StartTime = [datetime]'2020-01-01' }
        )
        Mock -ModuleName 'psfdx-logs' Get-SalesforceLogs { $logs }

        $null = Get-SalesforceLog -Last -Username 'user'
        # Should pick Id '2' (latest)
        Assert-MockCalled -ModuleName 'psfdx-logs' Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -match '--log-id 2 ' }
    }

    It 'throws when sf returns error' {
        Mock -ModuleName 'psfdx-logs' Invoke-Sf { '{"status":1,"message":"failure"}' }
        { Get-SalesforceLog -LogId 'X' -Username 'user' } | Should -Throw
    }
}

Describe 'Export-SalesforceLogs' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("psfdx-logs-tests-" + [System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null

        $logs = @(
            [pscustomobject]@{ Id = 'A'; StartTime = [datetime]'2020-01-01' },
            [pscustomobject]@{ Id = 'B'; StartTime = [datetime]'2020-01-02' }
        )
        Mock -ModuleName 'psfdx-logs' Get-SalesforceLogs { $logs }
        Mock -ModuleName 'psfdx-logs' Get-SalesforceLog { 'content' }
        # Avoid noisy progress in CI
        Mock Write-Progress {}
    }

    AfterEach {
        if (Test-Path $script:tempDir) { Remove-Item -Recurse -Force $script:tempDir }
    }

    It 'writes one file per log to the output folder' {
        Export-SalesforceLogs -OutputFolder $script:tempDir -Username 'user' -Verbose | Out-Null
        Test-Path (Join-Path $script:tempDir 'A.log') | Should -BeTrue
        Test-Path (Join-Path $script:tempDir 'B.log') | Should -BeTrue
    }

    It 'throws when output folder does not exist' {
        $missing = Join-Path $script:tempDir 'missing'
        { Export-SalesforceLogs -OutputFolder $missing -Username 'user' } | Should -Throw
    }

    It 'handles no logs gracefully' {
        Mock -ModuleName 'psfdx-logs' Get-SalesforceLogs { @() }
        Export-SalesforceLogs -OutputFolder $script:tempDir -Username 'user' -Verbose | Out-Null
        (Get-ChildItem -Path $script:tempDir | Measure-Object).Count | Should -Be 0
    }
}

Describe 'Convert-SalesforceLog' {
    It 'parses pipe-delimited log lines into objects' {
        $log = @(
            'Timestamp|LogType|SubType|Detail',
            '2024-01-01T00:00:00.000Z|USER_DEBUG|NULL|Hello',
            '2024-01-01T00:00:01.000Z|SYSTEM_METHOD_ENTRY|method|Class.Method'
        ) -join [Environment]::NewLine

        $results = Convert-SalesforceLog -Log $log
        $results.Count | Should -Be 2
        $results[0].DateTime | Should -Be '2024-01-01T00:00:00.000Z'
        $results[0].LogType  | Should -Be 'USER_DEBUG'
        $results[0].Detail   | Should -Be 'Hello'
        $results[1].SubType  | Should -Be 'method'
    }
}

Describe 'Out-Notepad' {
    It 'creates a temp file and opens it (Windows only)' -Skip:(!$IsWindows) {
        # Mock Start-Process to prevent UI
        Mock -ModuleName 'psfdx-logs' Start-Process {}
        Out-Notepad -Content 'test'
        Assert-MockCalled -ModuleName 'psfdx-logs' Start-Process -Times 1
    }
}
