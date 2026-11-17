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
                if ($Command -eq 'sf plugins --core --json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                return '{"status":0,"result":{"ok":true}}'
            }
        }

        Context 'manifest' {
            It 'exports only the public cmdlets' {
                $exported = @((Get-Module psfdx-agentforce).ExportedFunctions.Keys | Sort-Object)
                $exported | Should -Be @(
                    'Disable-SalesforceAgent', 'Enable-SalesforceAgent', 'Get-SalesforceAgentTestResult',
                    'Get-SalesforceAgentTests', 'Start-SalesforceAgentTest', 'Test-SalesforceAgentPlugin'
                )
            }
        }

        Context 'Test-SalesforceAgentPlugin' {
            It 'returns true when the plugin is listed' {
                Test-SalesforceAgentPlugin | Should -BeTrue
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf plugins --core --json' }
            }

            It 'returns false when the plugin is absent' {
                Mock Invoke-Salesforce { '{"status":0,"result":[{"name":"@salesforce/plugin-auth"}]}' }
                Test-SalesforceAgentPlugin | Should -BeFalse
            }
        }

        Context 'Get-SalesforceAgentTests' {
            It 'lists agent tests and maps the JSON result' {
                Mock Invoke-Salesforce {
                    if ($Command -eq 'sf plugins --core --json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    return '{"status":0,"result":[{"name":"Suite_A","type":"AiEvaluationDefinition"},{"name":"Suite_B","type":"AiEvaluationDefinition"}]}'
                }
                $tests = @(Get-SalesforceAgentTests -TargetOrg 'me')
                $tests.Count | Should -Be 2
                $tests[0].name | Should -Be 'Suite_A'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf agent test list --target-org me --json' }
            }

            It 'omits --target-org when not given' {
                Get-SalesforceAgentTests | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf agent test list --json' }
            }

            It 'returns an empty array when the CLI returns nothing' {
                Mock Invoke-Salesforce {
                    if ($Command -eq 'sf plugins --core --json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    return '{"status":0}'
                }
                @(Get-SalesforceAgentTests).Count | Should -Be 0
            }

            It 'throws the CLI message on failure' {
                Mock Invoke-Salesforce {
                    if ($Command -eq 'sf plugins --core --json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    return '{"status":1,"message":"No default org found"}'
                }
                { Get-SalesforceAgentTests } | Should -Throw -ExpectedMessage 'No default org found'
            }
        }

        Context 'Start-SalesforceAgentTest' {
            It 'builds the run command with wait and target org' {
                $out = Start-SalesforceAgentTest -ApiName 'My_Suite' -WaitMinutes 10 -TargetOrg 'me'
                $out.ok | Should -BeTrue
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf agent test run --api-name My_Suite --wait 10 --target-org me --json' }
            }

            It 'builds the minimal command' {
                Start-SalesforceAgentTest -ApiName 'My_Suite' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf agent test run --api-name My_Suite --json' }
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
                Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { $Command -like 'sf agent*' }
            }

            It 'throws the CLI message on failure' {
                Mock Invoke-Salesforce {
                    if ($Command -eq 'sf plugins --core --json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    return '{"status":1,"message":"Test definition not found"}'
                }
                { Start-SalesforceAgentTest -ApiName 'Nope' } | Should -Throw -ExpectedMessage 'Test definition not found'
            }
        }

        Context 'Get-SalesforceAgentTestResult' {
            It 'builds the results command' {
                $out = Get-SalesforceAgentTestResult -JobId '4KBxx0000000001AAA' -TargetOrg 'me'
                $out.ok | Should -BeTrue
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf agent test results --job-id 4KBxx0000000001AAA --target-org me --json' }
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
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf agent activate --api-name Service_Agent --version 3 --target-org me --json' }
            }

            It 'does not run the activation with -WhatIf' {
                Enable-SalesforceAgent -ApiName 'Service_Agent' -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { $Command -like 'sf agent activate*' }
            }

            It 'rejects an invalid API name' {
                { Enable-SalesforceAgent -ApiName 'bad name' -Confirm:$false } | Should -Throw -ExpectedMessage "*is not a valid API name*"
                Assert-MockCalled Invoke-Salesforce -Times 0
            }

            It 'stops when the plugin is absent' {
                Mock Invoke-Salesforce { '{"status":0,"result":[]}' }
                { Enable-SalesforceAgent -ApiName 'Service_Agent' -Confirm:$false } | Should -Throw -ExpectedMessage "*not installed*"
                Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { $Command -like 'sf agent*' }
            }

            It 'throws the CLI message on failure' {
                Mock Invoke-Salesforce {
                    if ($Command -eq 'sf plugins --core --json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    return '{"status":1,"message":"Agent not found"}'
                }
                { Enable-SalesforceAgent -ApiName 'Service_Agent' -Confirm:$false } | Should -Throw -ExpectedMessage 'Agent not found'
            }
        }

        Context 'Disable-SalesforceAgent' {
            It 'builds the deactivate command' {
                $out = Disable-SalesforceAgent -ApiName 'Service_Agent' -TargetOrg 'me' -Confirm:$false
                $out.ok | Should -BeTrue
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf agent deactivate --api-name Service_Agent --target-org me --json' }
            }

            It 'does not run the deactivation with -WhatIf' {
                Disable-SalesforceAgent -ApiName 'Service_Agent' -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { $Command -like 'sf agent deactivate*' }
            }

            It 'rejects an invalid API name' {
                { Disable-SalesforceAgent -ApiName 'a;b' -Confirm:$false } | Should -Throw -ExpectedMessage "*is not a valid API name*"
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
        }
    }
}
