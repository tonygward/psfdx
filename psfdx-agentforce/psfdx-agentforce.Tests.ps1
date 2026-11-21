# Ensure a clean module state before importing
Get-Module -Name 'psfdx-agentforce' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-agentforce.psd1'
Import-Module $moduleManifest -Force | Out-Null

Describe 'psfdx-agentforce module' {
    InModuleScope 'psfdx-agentforce' {
        BeforeEach {
            # Default: the agent plugin is installed. Individual tests override the plugin listing.
            Mock Invoke-Salesforce {
                if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                return '{"status":0,"result":{"ok":true}}'
            }
        }

        Context 'manifest' {
            It 'exports only the public cmdlets' {
                $exported = @((Get-Module psfdx-agentforce).ExportedFunctions.Keys | Sort-Object)
                $exported | Should -Be @(
                    'Disable-SalesforceAgent', 'Enable-SalesforceAgent', 'Get-SalesforceAgentTestResult',
                    'Get-SalesforceAgentTests', 'New-SalesforceAgentAuthoringBundle', 'Publish-SalesforceAgentAuthoringBundle',
                    'Start-SalesforceAgentTest', 'Test-SalesforceAgentAuthoringBundle', 'Test-SalesforceAgentPlugin'
                )
            }
        }

        Context 'Test-SalesforceAgentPlugin' {
            It 'returns true when the plugin is listed' {
                Test-SalesforceAgentPlugin | Should -BeTrue
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|--core|--json' }
            }

            It 'returns false when the plugin is absent' {
                Mock Invoke-Salesforce { '{"status":0,"result":[{"name":"@salesforce/plugin-auth"}]}' }
                Test-SalesforceAgentPlugin | Should -BeFalse
            }
        }

        Context 'Get-SalesforceAgentTests' {
            It 'lists agent tests and maps the JSON result' {
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    return '{"status":0,"result":[{"name":"Suite_A","type":"AiEvaluationDefinition"},{"name":"Suite_B","type":"AiEvaluationDefinition"}]}'
                }
                $tests = @(Get-SalesforceAgentTests -TargetOrg 'me')
                $tests.Count | Should -Be 2
                $tests[0].name | Should -Be 'Suite_A'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'agent|test|list|--target-org|me|--json' }
            }

            It 'omits --target-org when not given' {
                Get-SalesforceAgentTests | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'agent|test|list|--json' }
            }

            It 'returns an empty array when the CLI returns nothing' {
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    return '{"status":0}'
                }
                @(Get-SalesforceAgentTests).Count | Should -Be 0
            }

            It 'throws the CLI message on failure' {
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    return '{"status":1,"message":"No default org found"}'
                }
                { Get-SalesforceAgentTests } | Should -Throw -ExpectedMessage 'No default org found'
            }
        }

        Context 'Start-SalesforceAgentTest' {
            It 'builds the run command with wait and target org' {
                $out = Start-SalesforceAgentTest -ApiName 'My_Suite' -WaitMinutes 10 -TargetOrg 'me'
                $out.ok | Should -BeTrue
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'agent|test|run|--api-name|My_Suite|--wait|10|--target-org|me|--json' }
            }

            It 'passes a target org alias with a space as one argument' {
                Start-SalesforceAgentTest -ApiName 'My_Suite' -TargetOrg 'my org' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Arguments.Count -eq 8 -and $Arguments[6] -eq 'my org' }
            }

            It 'builds the minimal command' {
                Start-SalesforceAgentTest -ApiName 'My_Suite' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'agent|test|run|--api-name|My_Suite|--json' }
            }

            It 'rejects an API name that could add options' {
                { Start-SalesforceAgentTest -ApiName 'x --target-org evil' } | Should -Throw -ExpectedMessage "*is not a valid API name*"
                Assert-MockCalled Invoke-Salesforce -Times 0
            }

            It 'rejects a zero wait' {
                { Start-SalesforceAgentTest -ApiName 'My_Suite' -WaitMinutes 0 } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0
            }

            It 'stops with install guidance when the plugin is absent' {
                Mock Invoke-Salesforce { '{"status":0,"result":[]}' }
                { Start-SalesforceAgentTest -ApiName 'My_Suite' } | Should -Throw -ExpectedMessage "*@salesforce/plugin-agent*not installed*"
                Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { ($Arguments -join '|') -like 'agent*' }
            }

            It 'throws the CLI message on failure' {
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    return '{"status":1,"message":"Test definition not found"}'
                }
                { Start-SalesforceAgentTest -ApiName 'Nope' } | Should -Throw -ExpectedMessage 'Test definition not found'
            }
        }

        Context 'Get-SalesforceAgentTestResult' {
            It 'builds the results command' {
                $out = Get-SalesforceAgentTestResult -JobId '4KBxx0000000001AAA' -TargetOrg 'me'
                $out.ok | Should -BeTrue
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'agent|test|results|--job-id|4KBxx0000000001AAA|--target-org|me|--json' }
            }

            It 'rejects a malformed job id' {
                { Get-SalesforceAgentTestResult -JobId 'abc;rm' } | Should -Throw -ExpectedMessage "*not a valid 15 or 18 character Salesforce ID*"
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
        }

        Context 'Enable-SalesforceAgent' {
            It 'builds the activate command with version and target org' {
                $out = Enable-SalesforceAgent -ApiName 'Service_Agent' -Version 3 -TargetOrg 'me' -Confirm:$false
                $out.ok | Should -BeTrue
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'agent|activate|--api-name|Service_Agent|--version|3|--target-org|me|--json' }
            }

            It 'does not run the activation with -WhatIf' {
                Enable-SalesforceAgent -ApiName 'Service_Agent' -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { ($Arguments -join '|') -like 'agent|activate*' }
            }

            It 'rejects an invalid API name' {
                { Enable-SalesforceAgent -ApiName 'bad name' -Confirm:$false } | Should -Throw -ExpectedMessage "*is not a valid API name*"
                Assert-MockCalled Invoke-Salesforce -Times 0
            }

            It 'stops when the plugin is absent' {
                Mock Invoke-Salesforce { '{"status":0,"result":[]}' }
                { Enable-SalesforceAgent -ApiName 'Service_Agent' -Confirm:$false } | Should -Throw -ExpectedMessage "*not installed*"
                Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { ($Arguments -join '|') -like 'agent*' }
            }

            It 'throws the CLI message on failure' {
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    return '{"status":1,"message":"Agent not found"}'
                }
                { Enable-SalesforceAgent -ApiName 'Service_Agent' -Confirm:$false } | Should -Throw -ExpectedMessage 'Agent not found'
            }
        }

        Context 'Disable-SalesforceAgent' {
            It 'builds the deactivate command' {
                $out = Disable-SalesforceAgent -ApiName 'Service_Agent' -TargetOrg 'me' -Confirm:$false
                $out.ok | Should -BeTrue
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'agent|deactivate|--api-name|Service_Agent|--target-org|me|--json' }
            }

            It 'does not run the deactivation with -WhatIf' {
                Disable-SalesforceAgent -ApiName 'Service_Agent' -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { ($Arguments -join '|') -like 'agent|deactivate*' }
            }

            It 'rejects an invalid API name' {
                { Disable-SalesforceAgent -ApiName 'a;b' -Confirm:$false } | Should -Throw -ExpectedMessage "*is not a valid API name*"
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
        }
    }
}

Describe 'Agent authoring bundles' {
    InModuleScope 'psfdx-agentforce' {
        BeforeEach {
            $script:Reply = '{"status":0,"result":{"ok":true}}'
            Mock Invoke-Salesforce {
                if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                return $script:Reply
            }
        }

        Context 'New-SalesforceAgentAuthoringBundle' {
            It 'builds the exact command, including a spec and output folder with spaces' {
                $spec = Join-Path $TestDrive 'my spec.yaml'; Set-Content -Path $spec -Value 'x'
                $out = New-SalesforceAgentAuthoringBundle -Name 'Service Agent' -ApiName Service_Agent -Spec $spec -OutputDir 'my bundles' -TargetOrg me -Confirm:$false
                $expected = "agent|generate|authoring-bundle|--name|Service Agent|--api-name|Service_Agent|--spec|$spec|--output-dir|my bundles|--target-org|me|--json"
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
                $out.ok | Should -BeTrue
            }
            It 'adds --no-spec for a blank bundle' {
                New-SalesforceAgentAuthoringBundle -Name 'Service Agent' -NoSpec -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'agent|generate|authoring-bundle|--name|Service Agent|--no-spec|--json' }
            }
            It 'requires a spec or -NoSpec, and not both, before calling the CLI' {
                { New-SalesforceAgentAuthoringBundle -Name 'Service Agent' -Confirm:$false } | Should -Throw -ExpectedMessage '*-Spec*-NoSpec*'
                $spec = Join-Path $TestDrive 's.yaml'; Set-Content -Path $spec -Value 'x'
                { New-SalesforceAgentAuthoringBundle -Name 'Service Agent' -Spec $spec -NoSpec -Confirm:$false } | Should -Throw -ExpectedMessage '*only one of*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'writes nothing under -WhatIf' {
                New-SalesforceAgentAuthoringBundle -Name 'Service Agent' -NoSpec -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly -ParameterFilter { ($Arguments -join '|') -like 'agent|generate*' }
            }
            It 'rejects a bad API name and a missing spec without calling the CLI' {
                { New-SalesforceAgentAuthoringBundle -Name 'X' -NoSpec -ApiName 'bad name' -Confirm:$false } | Should -Throw -ExpectedMessage '*not a valid API name*'
                { New-SalesforceAgentAuthoringBundle -Name 'X' -Spec (Join-Path $TestDrive 'nope.yaml') -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'stops with install guidance when the plugin is missing' {
                Mock Invoke-Salesforce { '{"status":0,"result":[]}' }
                { New-SalesforceAgentAuthoringBundle -Name 'X' -NoSpec -Confirm:$false } | Should -Throw -ExpectedMessage '*plugin-agent*not installed*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly -ParameterFilter { ($Arguments -join '|') -like 'agent*' }
            }
        }

        Context 'Test-SalesforceAgentAuthoringBundle' {
            It 'builds the exact command and reports a valid bundle' {
                $r = Test-SalesforceAgentAuthoringBundle -ApiName Service_Agent -TargetOrg me
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'agent|validate|authoring-bundle|--api-name|Service_Agent|--target-org|me|--json' }
                $r.Valid | Should -BeTrue
                @($r.Diagnostics).Count | Should -Be 0
            }
            It 'returns validation diagnostics as objects instead of throwing' {
                $script:Reply = '{"status":1,"name":"AgentValidationError","message":"Validation failed","data":{"errors":[{"message":"Unknown topic","line":12,"column":3},{"message":"Missing instructions","severity":"Warning"}]}}'
                $r = Test-SalesforceAgentAuthoringBundle -ApiName Service_Agent
                $r.Valid | Should -BeFalse
                @($r.Diagnostics).Count | Should -Be 2
                $r.Diagnostics[0].Message | Should -Be 'Unknown topic'
                $r.Diagnostics[0].Line | Should -Be 12
                $r.Diagnostics[1].Severity | Should -Be 'Warning'
            }
            It 'falls back to the CLI message as the one diagnostic' {
                $script:Reply = '{"status":1,"name":"CompileError","message":"Syntax error on line 4"}'
                $r = Test-SalesforceAgentAuthoringBundle -ApiName Service_Agent
                $r.Valid | Should -BeFalse
                $r.Diagnostics[0].Message | Should -Be 'Syntax error on line 4'
            }
            It 'throws a distinct error carrying the result when -ThrowOnInvalid is set' {
                $script:Reply = '{"status":1,"name":"AgentValidationError","message":"bad","data":[{"message":"Unknown topic"}]}'
                $err = $null
                try { Test-SalesforceAgentAuthoringBundle -ApiName Service_Agent -ThrowOnInvalid } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxAgentValidationFailed'
                $err.TargetObject.Diagnostics.Count | Should -Be 1
            }
            It 'throws for failures that are not validation problems' {
                $script:Reply = '{"status":1,"name":"NamedOrgNotFound","message":"No authorization information found for nope."}'
                { Test-SalesforceAgentAuthoringBundle -ApiName Service_Agent -TargetOrg nope } | Should -Throw -ExpectedMessage '*No authorization information*'
            }
            It 'rejects a bad API name without calling the CLI' {
                { Test-SalesforceAgentAuthoringBundle -ApiName 'a;b' } | Should -Throw -ExpectedMessage '*not a valid API name*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Publish-SalesforceAgentAuthoringBundle' {
            It 'builds the exact command and returns the published result' {
                $script:Reply = '{"status":0,"result":{"developerName":"Service_Agent","agentId":"0XxAAA"}}'
                $r = Publish-SalesforceAgentAuthoringBundle -ApiName Service_Agent -SkipRetrieve -TargetOrg me -Confirm:$false
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'agent|publish|authoring-bundle|--api-name|Service_Agent|--skip-retrieve|--target-org|me|--json' }
                $r.developerName | Should -Be 'Service_Agent'
            }
            It 'does not publish under -WhatIf, and names the agent and org' {
                Publish-SalesforceAgentAuthoringBundle -ApiName Service_Agent -TargetOrg me -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly -ParameterFilter { ($Arguments -join '|') -like 'agent|publish*' }
                (Get-Command Publish-SalesforceAgentAuthoringBundle).ScriptBlock.Attributes.ConfirmImpact | Should -Contain 'High'
            }
            It 'throws the CLI message on failure and rejects a bad name' {
                $script:Reply = '{"status":1,"name":"PublishFailed","message":"Publish failed: topic missing"}'
                { Publish-SalesforceAgentAuthoringBundle -ApiName Service_Agent -Confirm:$false } | Should -Throw -ExpectedMessage '*topic missing*'
                { Publish-SalesforceAgentAuthoringBundle -ApiName '1bad' -Confirm:$false } | Should -Throw -ExpectedMessage '*not a valid API name*'
            }
        }

        Context 'module surface' {
            It 'exports the three cmdlets with examples and keeps the diagnostic helper private' {
                $exported = @((Get-Module psfdx-agentforce).ExportedFunctions.Keys)
                $exported | Should -Contain 'New-SalesforceAgentAuthoringBundle'
                $exported | Should -Contain 'Test-SalesforceAgentAuthoringBundle'
                $exported | Should -Contain 'Publish-SalesforceAgentAuthoringBundle'
                $exported | Should -Not -Contain 'Get-SalesforceAgentDiagnostic'
                foreach ($n in 'New-SalesforceAgentAuthoringBundle', 'Test-SalesforceAgentAuthoringBundle', 'Publish-SalesforceAgentAuthoringBundle') { @((Get-Help $n -Examples).examples.example).Count | Should -BeGreaterThan 0 }
            }
        }
    }
}
