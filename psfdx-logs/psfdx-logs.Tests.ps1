# Import module at discovery time so InModuleScope can find it
$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-logs.psd1'
Import-Module $moduleManifest -Force | Out-Null

Describe 'Watch-SalesforceLogs' {
    InModuleScope 'psfdx-logs' {
        BeforeEach { Mock Invoke-Sf {} }
        It 'builds base command with color' {
            Watch-SalesforceLogs | Out-Null
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log tail --color' }
        }
        It 'adds username when provided' {
            Watch-SalesforceLogs -TargetOrg 'user@example' | Out-Null
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log tail --target-org user@example --color' }
        }
        It 'adds skip trace flag' {
            Watch-SalesforceLogs -SkipTraceFlag | Out-Null
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log tail --skip-trace-flag --color' }
        }
        It 'adds debug level when provided' {
            Watch-SalesforceLogs -DebugLevel 'SFDC_DevConsole' | Out-Null
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log tail --debug-level SFDC_DevConsole --color' }
        }
    }
}

Describe 'Get-SalesforceLogs' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            Mock Invoke-Sf { '{"status":0,"result":[{"Id":"1"}]}' }
            Mock Show-SfResult { return @(@{ Id = '1' }) }
        }
        It 'lists logs with json' {
            $out = Get-SalesforceLogs
            $out | Should -Not -BeNullOrEmpty
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log list --json' }
            Assert-MockCalled Show-SfResult -Times 1
        }
        It 'adds username when provided' {
            Get-SalesforceLogs -TargetOrg 'user@example' | Out-Null
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log list --target-org user@example --json' }
        }
    }
}

Describe 'Get-SalesforceLog' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            # Default successful response from sf
            $jsonOk = '{"status":0,"result":{"log":"LOGDATA"}}'
            Mock Invoke-Sf { $jsonOk }
        }
        It 'requires either LogId or Last' {
            { Get-SalesforceLog -TargetOrg 'user' } | Should -Throw
        }
        It 'fetches by LogId and returns log text' {
            $log = Get-SalesforceLog -LogId '07Lxx0000000001' -TargetOrg 'user'
            $log | Should -Be 'LOGDATA'
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log get --log-id 07Lxx0000000001 --target-org user --json' }
        }
        It 'uses -Last to get latest log id' {
            $logs = @(
                [pscustomobject]@{ Id = '2'; StartTime = [datetime]'2020-01-02' },
                [pscustomobject]@{ Id = '1'; StartTime = [datetime]'2020-01-01' }
            )
            Mock Get-SalesforceLogs { $logs }
            $null = Get-SalesforceLog -Last -TargetOrg 'user'
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { ($Command -join ' ') -match '--log-id 2 ' }
        }
        It 'throws when sf returns error' {
            Mock Invoke-Sf { '{"status":1,"message":"failure"}' }
            { Get-SalesforceLog -LogId 'X' -TargetOrg 'user' } | Should -Throw
        }
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
        InModuleScope 'psfdx-logs' {
            Mock Get-SalesforceLogs { $logs }
            Mock Get-SalesforceLog { 'content' }
        }
        # Avoid noisy progress in CI
        Mock Write-Progress {}
    }

    AfterEach {
        if (Test-Path $script:tempDir) { Remove-Item -Recurse -Force $script:tempDir }
    }

    It 'writes one file per log to the output folder' {
        Export-SalesforceLogs -OutputFolder $script:tempDir -TargetOrg 'user' -Verbose | Out-Null
        Test-Path (Join-Path $script:tempDir 'A.log') | Should -BeTrue
        Test-Path (Join-Path $script:tempDir 'B.log') | Should -BeTrue
    }

    It 'throws when output folder does not exist' {
        $missing = Join-Path $script:tempDir 'missing'
        { Export-SalesforceLogs -OutputFolder $missing -TargetOrg 'user' } | Should -Throw
    }

    It 'handles no logs gracefully' {
        InModuleScope 'psfdx-logs' { Mock Get-SalesforceLogs { @() } }
        Export-SalesforceLogs -OutputFolder $script:tempDir -TargetOrg 'user' -Verbose | Out-Null
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
        InModuleScope 'psfdx-logs' { Mock Start-Process {} }
        Out-Notepad -Content 'test'
        InModuleScope 'psfdx-logs' { Assert-MockCalled Start-Process -Times 1 }
    }
}
