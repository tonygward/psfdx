# Import module at discovery time so InModuleScope can find it
$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-logs.psd1'
Import-Module $moduleManifest -Force | Out-Null

Describe 'Watch-SalesforceDebugLogs' {
    InModuleScope 'psfdx-logs' {
        BeforeEach { Mock Invoke-Salesforce {} }
        It 'builds base command with color' {
            Watch-SalesforceDebugLogs | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log tail --color' }
        }
        It 'adds username when provided' {
            Watch-SalesforceDebugLogs -TargetOrg 'user@example' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log tail --target-org user@example --color' }
        }
        It 'adds skip trace flag' {
            Watch-SalesforceDebugLogs -SkipTraceFlag | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log tail --skip-trace-flag --color' }
        }
        It 'adds debug level when provided' {
            Watch-SalesforceDebugLogs -DebugLevel 'SFDC_DevConsole' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log tail --debug-level SFDC_DevConsole --color' }
        }
    }
}

Describe 'Get-SalesforceDebugLogs' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":[{"Id":"1"}]}' }
            Mock Show-SalesforceResult { return @(@{ Id = '1' }) }
        }
        It 'lists logs with json' {
            $out = Get-SalesforceDebugLogs
            $out | Should -Not -BeNullOrEmpty
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log list --json' }
            Assert-MockCalled Show-SalesforceResult -Times 1
        }
        It 'adds username when provided' {
            Get-SalesforceDebugLogs -TargetOrg 'user@example' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log list --target-org user@example --json' }
        }
    }
}

Describe 'Get-SalesforceDebugLog' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            # Default successful response from sf
            $jsonOk = '{"status":0,"result":{"log":"LOGDATA"}}'
            Mock Invoke-Salesforce { $jsonOk }
        }
        It 'requires either LogId or Last' {
            { Get-SalesforceDebugLog -TargetOrg 'user' } | Should -Throw
        }
        It 'fetches by LogId and returns log text' {
            $log = Get-SalesforceDebugLog -LogId '07Lxx0000000001' -TargetOrg 'user'
            $log | Should -Be 'LOGDATA'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log get --log-id 07Lxx0000000001 --target-org user --json' }
        }
        It 'uses -Last to get latest log id' {
            $logs = @(
                [pscustomobject]@{ Id = '2'; StartTime = [datetime]'2020-01-02' },
                [pscustomobject]@{ Id = '1'; StartTime = [datetime]'2020-01-01' }
            )
            Mock Get-SalesforceDebugLogs { $logs }
            $null = Get-SalesforceDebugLog -Last -TargetOrg 'user'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -join ' ') -match '--log-id 2 ' }
        }
        It 'throws when sf returns error' {
            Mock Invoke-Salesforce { '{"status":1,"message":"failure"}' }
            { Get-SalesforceDebugLog -LogId 'X' -TargetOrg 'user' } | Should -Throw
        }
    }
}

Describe 'Convert-SalesforceDebugLog' {
    It 'parses pipe-delimited log lines into objects' {
        $log = @(
            'Timestamp|LogType|SubType|Detail',
            '2024-01-01T00:00:00.000Z|USER_DEBUG|NULL|Hello',
            '2024-01-01T00:00:01.000Z|SYSTEM_METHOD_ENTRY|method|Class.Method'
        ) -join [Environment]::NewLine

        $results = Convert-SalesforceDebugLog -Log $log
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

Describe 'Get-SalesforceEventFiles' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            # Mock SF query pipeline
            Mock Invoke-Salesforce { '{"status":0}' }
            # With -ReturnRecords, the helper returns an array of records
            Mock Show-SalesforceResult { @([pscustomobject]@{ Id = '1'; EventType = 'Login'; LogDate = '2024-01-01T00:00:00.000Z' }) }
        }
        It 'builds SOQL with filters and returns objects' {
            $out = Get-SalesforceEventFiles -EventType 'Login' -Limit 10 -TargetOrg 'me'
            $out | Should -Not -BeNullOrEmpty
            $out[0].EventType | Should -Be 'Login'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Command -like 'sf data query --query *FROM EventLogFile*') -and
                ($Command -like "*EventType = 'Login'*") -and
                ($Command -like '* ORDER BY LogDate DESC*') -and
                ($Command -like '* LIMIT 10*') -and
                ($Command -like '* --target-org me*') -and
                ($Command -like '* --result-format json*')
            }
        }
    }
}

Describe 'Export-SalesforceEventFiles' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0}' }
            Mock Show-SalesforceResult { @([pscustomobject]@{ Id = '1'; EventType = 'Login'; LogDate = '2024-01-01T00:00:00.000Z' }) }
            Mock Export-SalesforceEventFile {}
        }
        It 'writes CSV to disk and uses filters' {
            Export-SalesforceEventFiles -EventType 'Login' -Limit 2 -TargetOrg 'me' -Verbose | Out-Null
            Assert-MockCalled Export-SalesforceEventFile -Times 1
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Command -like 'sf data query --query *FROM EventLogFile*') -and
                ($Command -like "*EventType = 'Login'*") -and
                ($Command -like '* LIMIT 2*') -and
                ($Command -like '* --target-org me*')
            }
        }
    }
}

Describe 'Get-SalesforceLoginHistory' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0}' }
            Mock Show-SalesforceResult { @([pscustomobject]@{ Id = '1'; Username = 'user'; Status = 'Failure'; LoginTime = '2024-01-01T00:00:00.000Z' }) }
            Mock Get-SalesforceUsers { @([pscustomobject]@{ Username = 'user'; Name = 'User Name'; Email = 'user@example.com'; IsActive = $true; LastLoginDate = '2024-01-01T00:00:00.000Z' }) }
        }
        It 'builds SOQL with filters and returns objects' {
            $after = [datetime]'2024-01-01T00:00:00Z'
            $before = [datetime]'2024-01-02T00:00:00Z'
            $out = Get-SalesforceLoginHistory -Username 'user' -After $after -Before $before -Limit 5 -TargetOrg 'me'
            $out | Should -Not -BeNullOrEmpty
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Command -like 'sf data query --query *FROM LoginHistory*') -and
                ($Command -like "*Username = 'user'*") -and
                ($Command -like '* ORDER BY LoginTime DESC*') -and
                ($Command -like '* LIMIT 5*') -and
                ($Command -like '* --target-org me*') -and
                ($Command -like '* --result-format json*')
            }
            Assert-MockCalled Get-SalesforceUsers -Times 1 -ParameterFilter { $Username -eq 'user' -and $Limit -eq 1 -and $TargetOrg -eq 'me' }
            $out[0].Email | Should -Be 'user@example.com'
        }
    }
}
