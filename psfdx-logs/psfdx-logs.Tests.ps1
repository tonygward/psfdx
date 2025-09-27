# Ensure clean slate and load dependency modules locally
Get-Module -Name 'psfdx','psfdx-logs' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$psfdxManifest = Join-Path -Path $repoRoot -ChildPath 'psfdx/psfdx.psd1'
Import-Module $psfdxManifest -Force | Out-Null

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

Describe 'Select-SalesforceDebugLogs' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":[{"Id":"1"}]}' }
            Mock Show-SalesforceResult { return @(@{ Id = '1' }) }
        }
        It 'lists logs with json' {
            $out = Select-SalesforceDebugLogs
            $out | Should -Not -BeNullOrEmpty
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log list --json' }
            Assert-MockCalled Show-SalesforceResult -Times 1
        }
        It 'adds username when provided' {
            Select-SalesforceDebugLogs -TargetOrg 'user@example' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log list --target-org user@example --json' }
        }
    }
}

Describe 'Get-SalesforceDebugLogs' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            # Default successful response from sf
            $script:JsonOk = '{"status":0,"result":{"log":"LOGDATA"}}'
            Mock Invoke-Salesforce { $script:JsonOk }
        }
        It 'requires either LogId or Last' {
            { Get-SalesforceDebugLogs -TargetOrg 'user' } | Should -Throw
        }
        It 'errors when both LogId and Last provided' {
            { Get-SalesforceDebugLogs -LogId '07L' -Last 1 -TargetOrg 'user' } | Should -Throw
        }
        It 'builds command with log id and returns raw response' {
            $raw = Get-SalesforceDebugLogs -LogId '07Lxx0000000001' -TargetOrg 'user'
            $raw | Should -Be $script:JsonOk
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log get --log-id 07Lxx0000000001 --target-org user' }
        }
        It 'builds command using last number when requested' {
            $null = Get-SalesforceDebugLogs -Last 1 -TargetOrg 'user'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -join ' ') -eq 'sf apex log get --number 1 --target-org user' }
        }
        It 'surfaces sf error payload for callers to handle' {
            Mock Invoke-Salesforce { '{"status":1,"message":"failure"}' }
            $response = Get-SalesforceDebugLogs -LogId 'X' -TargetOrg 'user'
            ($response | ConvertFrom-Json).status | Should -Be 1
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

Describe 'Select-SalesforceEventFiles' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            # Mock SF query pipeline
            Mock Invoke-Salesforce { '{"status":0}' }
            # With -ReturnRecords, the helper returns an array of records
            Mock Show-SalesforceResult { @([pscustomobject]@{ Id = '1'; EventType = 'Login'; LogDate = '2024-01-01T00:00:00.000Z' }) }
        }
        It 'builds SOQL with filters and returns objects' {
            $out = Select-SalesforceEventFiles -EventType 'Login' -Limit 10 -TargetOrg 'me'
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

Describe 'Get-SalesforceLoginFailures' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            # Bypass direct SF call; just validate filtering behavior
            Mock Get-SalesforceLoginHistory {
                @(
                    [pscustomobject]@{ Id='1'; Username='user'; Status='Success'; LoginTime='2024-01-01T00:00:00.000Z' },
                    [pscustomobject]@{ Id='2'; Username='user'; Status='Failure'; LoginTime='2024-01-01T01:00:00.000Z' }
                )
            }
        }
        It 'returns only failed login history' {
            $rows = Get-SalesforceLoginFailures -Username 'user'
            $rows.Count | Should -Be 1
            $rows[0].Id   | Should -Be '2'
            Assert-MockCalled Get-SalesforceLoginHistory -Times 1
        }
    }
}
