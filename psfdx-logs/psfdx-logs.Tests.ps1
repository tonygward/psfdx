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
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|log|tail|--color' }
        }
        It 'adds username when provided' {
            Watch-SalesforceDebugLogs -TargetOrg 'user@example' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|log|tail|--target-org|user@example|--color' }
        }
        It 'adds skip trace flag' {
            Watch-SalesforceDebugLogs -SkipTraceFlag | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|log|tail|--skip-trace-flag|--color' }
        }
        It 'adds debug level when provided' {
            Watch-SalesforceDebugLogs -DebugLevel 'SFDC_DevConsole' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|log|tail|--debug-level|SFDC_DevConsole|--color' }
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
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|log|list|--json' }
            Assert-MockCalled Show-SalesforceResult -Times 1
        }
        It 'adds username when provided' {
            Select-SalesforceDebugLogs -TargetOrg 'user@example' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|log|list|--target-org|user@example|--json' }
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
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|log|get|--log-id|07Lxx0000000001|--target-org|user' }
        }
        It 'builds command using last number when requested' {
            $null = Get-SalesforceDebugLogs -Last 1 -TargetOrg 'user'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|log|get|--number|1|--target-org|user' }
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
                (($Arguments -join '|') -like 'data|query|--query|*FROM EventLogFile*') -and
                (($Arguments -join '|') -like "*EventType = 'Login'*") -and
                (($Arguments -join '|') -like '* ORDER BY LogDate DESC*') -and
                (($Arguments -join '|') -like '* LIMIT 10*') -and
                (($Arguments -join '|') -like '*|--target-org|me*') -and
                (($Arguments -join '|') -like '*|--result-format|json*')
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
        It 'escapes the event type and builds the same query for select and export' {
            $expected = 'SELECT Id, EventType, LogDate, LogFileLength, Sequence, Interval, CreatedDate FROM EventLogFile WHERE EventType = ''Lo\''gin\\'' ORDER BY LogDate DESC LIMIT 3'
            Export-SalesforceEventFiles -EventType "Lo'gin\" -Limit 3 | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments[0..1] -join '|') -eq 'data|query' -and $Arguments[3] -ceq $expected }
            Select-SalesforceEventFiles -EventType "Lo'gin\" -Limit 3 | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 2 -ParameterFilter { ($Arguments[0..1] -join '|') -eq 'data|query' -and $Arguments[3] -ceq $expected }
        }
        It 'sends -After and -Before as the UTC instant, never local time labelled as UTC' {
            $after = [datetime]::SpecifyKind([datetime]'2026-10-21T08:00:00', [System.DateTimeKind]::Local)
            $before = [datetime]::SpecifyKind([datetime]'2026-10-22T08:00:00', [System.DateTimeKind]::Utc)
            $afterUtc = $after.ToUniversalTime().ToString('s', [System.Globalization.CultureInfo]::InvariantCulture) + 'Z'
            Select-SalesforceEventFiles -EventType 'Login' -After $after -Before $before -Limit 1 | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                $Arguments[3] -ceq "SELECT Id, EventType, LogDate, LogFileLength, Sequence, Interval, CreatedDate FROM EventLogFile WHERE EventType = 'Login' AND LogDate >= $afterUtc AND LogDate <= 2026-10-22T08:00:00Z ORDER BY LogDate DESC LIMIT 1"
            }
        }
        It 'writes CSV to disk and uses filters' {
            Export-SalesforceEventFiles -EventType 'Login' -Limit 2 -TargetOrg 'me' -Verbose | Out-Null
            Assert-MockCalled Export-SalesforceEventFile -Times 1
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'data|query|--query|SELECT Id, EventType, LogDate, LogFileLength, Sequence, Interval, CreatedDate FROM EventLogFile WHERE EventType = ''Login'' ORDER BY LogDate DESC LIMIT 2|--result-format|json|--target-org|me'
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
                (($Arguments -join '|') -like '*LoginTime >= 2024-01-01T00:00:00Z AND LoginTime <= 2024-01-02T00:00:00Z*')
            }
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                (($Arguments -join '|') -like 'data|query|--query|*FROM LoginHistory*') -and
                (($Arguments -join '|') -like "*Username = 'user'*") -and
                (($Arguments -join '|') -like '* ORDER BY LoginTime DESC*') -and
                (($Arguments -join '|') -like '* LIMIT 5*') -and
                (($Arguments -join '|') -like '*|--target-org|me*') -and
                (($Arguments -join '|') -like '*|--result-format|json*')
            }
            Assert-MockCalled Get-SalesforceUsers -Times 1 -ParameterFilter { $Username -eq 'user' -and $Limit -eq 1 -and $TargetOrg -eq 'me' }
            $out[0].Email | Should -Be 'user@example.com'
        }
    }
}

Describe 'Get-SalesforceLoginHistory -Username filter' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0}' }
            Mock Show-SalesforceResult { @() }
            Mock Get-SalesforceUsers { @() }
        }
        It 'filters through a User subquery because LoginHistory has no Username column' {
            Get-SalesforceLoginHistory -Username "o'brien@example.com" | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                (($Arguments -join '|') -like "*UserId IN (SELECT Id FROM User WHERE Username = 'o\'brien@example.com')*") -and
                (($Arguments -join '|') -notlike '*LoginHistory WHERE Username*')
            }
        }
    }
}

Describe 'Convert-SalesforceDebugLog pipeline input' {
    It 'processes every piped log, not just the last one' {
        $logs = @(
            "header`n2024-01-01T00:00:00.000Z|USER_DEBUG|NULL|First",
            "header`n2024-01-01T00:00:01.000Z|USER_DEBUG|NULL|Second",
            "header`n2024-01-01T00:00:02.000Z|USER_DEBUG|NULL|Third"
        )
        $rows = $logs | Convert-SalesforceDebugLog -WarningAction SilentlyContinue
        @($rows).Count | Should -Be 3
        $rows.Detail | Should -Be @('First', 'Second', 'Third')
    }

    It 'maps the literal NULL placeholder to $null' {
        $rows = Convert-SalesforceDebugLog -Log "header`n2024-01-01T00:00:00.000Z|USER_DEBUG|NULL|Only" -WarningAction SilentlyContinue
        $rows.PSObject.Properties.Match('SubType').Count | Should -Be 0
    }
}

Describe 'Get-SalesforceFlowInterviews' {
    It 'does not make -Type mandatory, so its default can apply' {
        $mandatory = (Get-Command Get-SalesforceFlowInterviews).Parameters['Type'].Attributes |
            Where-Object { $_ -is [Parameter] } |
            ForEach-Object { $_.Mandatory }
        $mandatory | Should -Not -Contain $true
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
            @($rows).Count | Should -Be 1
            $rows[0].Id   | Should -Be '2'
            Assert-MockCalled Get-SalesforceLoginHistory -Times 1
        }
    }
}

Describe 'Enable-SalesforceDebugLogging' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"id":"7tf000000000001AAA","success":true}}' }
            Mock Show-SalesforceResult { [pscustomobject]@{ id = '7tf000000000001AAA'; success = $true } }
        }
        It 'builds create command with required flags' {
            $out = Enable-SalesforceDebugLogging -TracedEntityId '005000000000001' -DebugLevel 'SFDC_DevConsole'
            $out.id | Should -Be '7tf000000000001AAA'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|trace|create|--traced-entity-id|005000000000001|--debug-level|SFDC_DevConsole|--json' }
            Assert-MockCalled Show-SalesforceResult -Times 1
        }
        It 'adds log type, duration and target org' {
            Enable-SalesforceDebugLogging -TracedEntityId '01p000000000001' -DebugLevel 'MyLevel' -LogType USER_DEBUG -Duration 120 -TargetOrg 'user@example' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|trace|create|--traced-entity-id|01p000000000001|--debug-level|MyLevel|--log-type|USER_DEBUG|--duration|120|--target-org|user@example|--json' }
        }
        It 'rejects an invalid log type' {
            { Enable-SalesforceDebugLogging -TracedEntityId '005' -DebugLevel 'X' -LogType 'PROFILING' } | Should -Throw
        }
        It 'rejects a duration over 24 hours' {
            { Enable-SalesforceDebugLogging -TracedEntityId '005' -DebugLevel 'X' -Duration 1441 } | Should -Throw
        }
    }
}

Describe 'Enable-SalesforceDebugLogging by name' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"id":"7tf000000000001AAA","success":true}}' }
            $script:LookupJson = '{"status":0,"result":{"records":[{"attributes":{"type":"X"},"Id":"0XX000000000001AAA"}]}}'
            Mock Invoke-Salesforce { $script:LookupJson } -ModuleName 'psfdx'
        }
        It 'does not look up an Id when -TracedEntityId is given' {
            Enable-SalesforceDebugLogging -TracedEntityId '005000000000001' -DebugLevel 'X' | Out-Null
            Assert-MockCalled Invoke-Salesforce -ModuleName 'psfdx' -Times 0
        }
        It 'resolves -Username to a user Id' {
            Enable-SalesforceDebugLogging -Username 'me@example.com' -DebugLevel 'SFDC_DevConsole' -TargetOrg 'myorg' | Out-Null
            Assert-MockCalled Invoke-Salesforce -ModuleName 'psfdx' -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'data|query|--query|SELECT Id FROM User WHERE Username = ''me@example.com'' LIMIT 2|--target-org|myorg|--result-format|json' }
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|trace|create|--traced-entity-id|0XX000000000001AAA|--debug-level|SFDC_DevConsole|--target-org|myorg|--json' }
        }
        It 'resolves -ApexClass to a class Id' {
            Enable-SalesforceDebugLogging -ApexClass 'AccountService' -DebugLevel 'X' | Out-Null
            Assert-MockCalled Invoke-Salesforce -ModuleName 'psfdx' -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'data|query|--query|SELECT Id FROM ApexClass WHERE Name = ''AccountService'' LIMIT 2|--result-format|json' }
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|trace|create|--traced-entity-id|0XX000000000001AAA|--debug-level|X|--json' }
        }
        It 'resolves -ApexTrigger to a trigger Id' {
            Enable-SalesforceDebugLogging -ApexTrigger 'AccountTrigger' -DebugLevel 'X' | Out-Null
            Assert-MockCalled Invoke-Salesforce -ModuleName 'psfdx' -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'data|query|--query|SELECT Id FROM ApexTrigger WHERE Name = ''AccountTrigger'' LIMIT 2|--result-format|json' }
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|trace|create|--traced-entity-id|0XX000000000001AAA|--debug-level|X|--json' }
        }
        It 'escapes single quotes in the name' {
            Enable-SalesforceDebugLogging -Username "o'brien@example.com" -DebugLevel 'X' | Out-Null
            Assert-MockCalled Invoke-Salesforce -ModuleName 'psfdx' -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'data|query|--query|SELECT Id FROM User WHERE Username = ''o\''brien@example.com'' LIMIT 2|--result-format|json' }
        }
        It 'throws and does not create a trace flag when the name is not found' {
            $script:LookupJson = '{"status":0,"result":{"records":[]}}'
            { Enable-SalesforceDebugLogging -ApexClass 'Missing' -DebugLevel 'X' } | Should -Throw -ExpectedMessage "No ApexClass found with Name 'Missing'."
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
        It 'throws when the name matches more than one record' {
            $script:LookupJson = '{"status":0,"result":{"records":[{"Id":"01p000000000001AAA"},{"Id":"01p000000000002AAA"}]}}'
            { Enable-SalesforceDebugLogging -ApexClass 'Dup' -DebugLevel 'X' } | Should -Throw -ExpectedMessage "More than one ApexClass found with Name 'Dup'. Use -TracedEntityId instead."
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
        It 'rejects more than one way of naming the entity' {
            { Enable-SalesforceDebugLogging -Username 'a' -ApexClass 'B' -DebugLevel 'X' } | Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
            Assert-MockCalled Invoke-Salesforce -ModuleName 'psfdx' -Times 0
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
    }
}

Describe 'Get-SalesforceDebugLogging' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":[{"Id":"7tf000000000001AAA","Status":"Active"}]}' }
        }
        It 'lists trace flags with json' {
            $out = Get-SalesforceDebugLogging
            $out.Id | Should -Be '7tf000000000001AAA'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|trace|list|--json' }
        }
        It 'adds target org when provided' {
            Get-SalesforceDebugLogging -TargetOrg 'user@example' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|trace|list|--target-org|user@example|--json' }
        }
    }
}

Describe 'Disable-SalesforceDebugLogging' {
    InModuleScope 'psfdx-logs' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"id":"7tf000000000001AAA","success":true}}' }
        }
        It 'builds delete command' {
            Disable-SalesforceDebugLogging -TraceId '7tf000000000001AAA' -TargetOrg 'user@example' -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|trace|delete|--trace-flag-id|7tf000000000001AAA|--target-org|user@example|--json' }
        }
        It 'does not call sf with -WhatIf' {
            Disable-SalesforceDebugLogging -TraceId '7tf000000000001AAA' -WhatIf
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
        It 'deletes each trace flag piped from Get-SalesforceDebugLogging' {
            $flags = @(
                [pscustomobject]@{ Id = '7tf000000000001AAA'; Status = 'Expired' },
                [pscustomobject]@{ Id = '7tf000000000002AAA'; Status = 'Expired' }
            )
            $flags | Disable-SalesforceDebugLogging -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|trace|delete|--trace-flag-id|7tf000000000001AAA|--json' }
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'apex|trace|delete|--trace-flag-id|7tf000000000002AAA|--json' }
        }
    }
}

# SOQL builder and `sf data query --json` regression coverage (#172).
# Fixtures are sanitised copies of real `sf data query --json` output shapes: no tokens, no real org data.
Describe 'psfdx-logs SOQL regression' {
    InModuleScope 'psfdx-logs' {
        BeforeAll {
            $script:Empty = '{"status":0,"result":{"records":[],"totalSize":0,"done":true},"warnings":[]}'
            $script:Malformed = '{"name":"MALFORMED_QUERY","message":"\nSELECT Id FROM\n          ^\nERROR at Row:1:Column:11\nunexpected token: FROM","exitCode":1,"status":1,"warnings":[]}'
            $script:NoAuth = '{"name":"NoAuthFoundError","message":"No authorization information found for nobody@example.com.","exitCode":1,"status":1,"warnings":[]}'
            $script:Flows = '{"status":0,"result":{"records":[{"attributes":{"type":"FlowInterview","url":"/services/data/v62.0/sobjects/FlowInterview/300000000000001AAA"},"Id":"300000000000001AAA","InterviewLabel":"My Flow","InterviewStatus":"Error"}],"totalSize":1,"done":true},"warnings":[]}'
            $script:EventHead = 'SELECT Id, EventType, LogDate, LogFileLength, Sequence, Interval, CreatedDate FROM EventLogFile'
        }

        Context 'New-SalesforceEventFileQuery' {
            It 'escapes EventType <Name>' -ForEach @(
                @{ Name = 'plain';      Value = 'Login';         Literal = "'Login'" }
                @{ Name = 'apostrophe'; Value = "Lo'gin";        Literal = "'Lo\'gin'" }
                @{ Name = 'backslash';  Value = 'Lo\gin';        Literal = "'Lo\\gin'" }
                @{ Name = 'injection';  Value = "x' OR Id != '"; Literal = "'x\' OR Id != \''" }
                @{ Name = 'unicode';    Value = 'Anmeldung日本';   Literal = "'Anmeldung日本'" }
                @{ Name = 'percent';    Value = '50%_off';       Literal = "'50%_off'" }
            ) {
                New-SalesforceEventFileQuery -EventType $Value | Should -Be "$script:EventHead WHERE EventType = $Literal ORDER BY LogDate DESC"
            }

            It 'has no WHERE clause and no LIMIT when nothing is given' {
                New-SalesforceEventFileQuery | Should -Be "$script:EventHead ORDER BY LogDate DESC"
            }

            It 'writes the boundaries as UTC instants' {
                $q = New-SalesforceEventFileQuery -After ([datetime]::SpecifyKind([datetime]'2026-01-02T03:04:05', 'Utc')) -Before ([datetime]::SpecifyKind([datetime]'2026-01-03T00:00:00', 'Utc')) -Limit 3
                $q | Should -Be "$script:EventHead WHERE LogDate >= 2026-01-02T03:04:05Z AND LogDate <= 2026-01-03T00:00:00Z ORDER BY LogDate DESC LIMIT 3"
            }

            It 'refuses a control character' {
                { New-SalesforceEventFileQuery -EventType "a$([char]1)b" } | Should -Throw -ExpectedMessage '*control character*'
            }
        }

        Context 'Select-SalesforceEventFiles results' {
            It 'returns nothing for zero records' {
                Mock Invoke-Salesforce { $script:Empty }
                @(Select-SalesforceEventFiles -EventType 'Login').Count | Should -Be 0
            }

            It 'throws the CLI message for a malformed query' {
                Mock Invoke-Salesforce { $script:Malformed }
                { Select-SalesforceEventFiles } | Should -Throw -ExpectedMessage '*unexpected token: FROM*'
            }

            It 'throws the CLI message for an authentication error' {
                Mock Invoke-Salesforce { $script:NoAuth }
                { Select-SalesforceEventFiles -TargetOrg 'nobody@example.com' } | Should -Throw -ExpectedMessage '*No authorization information found*'
            }
        }

        Context 'Get-SalesforceFlowInterviews' {
            It 'asks for every status by default, newest first' {
                Mock Invoke-Salesforce { $script:Empty }
                Get-SalesforceFlowInterviews | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                    ($Arguments -join '|') -eq "data|query|--query|SELECT Id, CreatedDate, InterviewLabel, InterviewStatus, Error FROM FlowInterview WHERE InterviewStatus IN ('Error','Paused','Running','Completed','VersionPaused','Autosaved','Expired') ORDER BY CreatedDate DESC LIMIT 200|--result-format|json"
                }
            }

            It 'filters on one status, a UTC start instant and the target org' {
                Mock Invoke-Salesforce { $script:Empty }
                Get-SalesforceFlowInterviews -Type Error -After ([datetime]::SpecifyKind([datetime]'2026-05-06T07:08:09', 'Utc')) -Limit 7 -TargetOrg 'me' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                    ($Arguments -join '|') -eq "data|query|--query|SELECT Id, CreatedDate, InterviewLabel, InterviewStatus, Error FROM FlowInterview WHERE InterviewStatus IN ('Error') AND CreatedDate >= 2026-05-06T07:08:09Z ORDER BY CreatedDate DESC LIMIT 7|--result-format|json|--target-org|me"
                }
            }

            It 'returns records without attributes' {
                Mock Invoke-Salesforce { $script:Flows }
                $r = @(Get-SalesforceFlowInterviews)
                $r.Count | Should -Be 1
                $r[0].InterviewLabel | Should -Be 'My Flow'
                $r[0].PSObject.Properties.Name | Should -Not -Contain 'attributes'
            }

            It 'returns nothing for zero records' {
                Mock Invoke-Salesforce { $script:Empty }
                @(Get-SalesforceFlowInterviews).Count | Should -Be 0
            }

            It 'throws the CLI message on failure' {
                Mock Invoke-Salesforce { $script:Malformed }
                { Get-SalesforceFlowInterviews } | Should -Throw -ExpectedMessage '*unexpected token: FROM*'
            }

            It 'throws the CLI message on an authentication error' {
                Mock Invoke-Salesforce { $script:NoAuth }
                { Get-SalesforceFlowInterviews -TargetOrg 'nobody@example.com' } | Should -Throw -ExpectedMessage '*No authorization information found*'
            }
        }

        Context 'Get-SalesforceLoginHistory' {
            BeforeEach { Mock Get-SalesforceUsers { @() } }

            It 'escapes Username <Name>' -ForEach @(
                @{ Name = 'apostrophe'; Value = "o'brien@example.com";  Literal = "'o\'brien@example.com'" }
                @{ Name = 'backslash';  Value = 'a\b@example.com';      Literal = "'a\\b@example.com'" }
                @{ Name = 'injection';  Value = "x') OR Status != ('";  Literal = "'x\') OR Status != (\''" }
                @{ Name = 'unicode';    Value = 'Zoë@example.com';      Literal = "'Zoë@example.com'" }
            ) {
                Mock Invoke-Salesforce { $script:Empty }
                Get-SalesforceLoginHistory -Username $Value | Out-Null
                $expected = "data|query|--query|SELECT Id, LoginTime, UserId, SourceIp, Application, Status FROM LoginHistory WHERE UserId IN (SELECT Id FROM User WHERE Username = $Literal) ORDER BY LoginTime DESC|--result-format|json"
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq $expected }
            }

            It 'refuses a control character in Username and runs nothing' {
                Mock Invoke-Salesforce { $script:Empty }
                { Get-SalesforceLoginHistory -Username "a$([char]1)b" } | Should -Throw -ExpectedMessage '*control character*'
                Assert-MockCalled Invoke-Salesforce -Times 0
            }

            It 'returns nothing for zero records' {
                Mock Invoke-Salesforce { $script:Empty }
                @(Get-SalesforceLoginHistory).Count | Should -Be 0
            }

            It 'throws the CLI message on an authentication error' {
                Mock Invoke-Salesforce { $script:NoAuth }
                { Get-SalesforceLoginHistory -TargetOrg 'nobody@example.com' } | Should -Throw -ExpectedMessage '*No authorization information found*'
            }
        }
    }
}
