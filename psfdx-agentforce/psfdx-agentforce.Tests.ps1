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
                $expected = @(
                    'Disable-SalesforceAgent', 'Enable-SalesforceAgent', 'Get-SalesforceAgentTestResult',
                    'Get-SalesforceAgentTests', 'New-SalesforceAgentAuthoringBundle', 'Publish-SalesforceAgentAuthoringBundle',
                    'Start-SalesforceAgentTest', 'Test-SalesforceAgentAuthoringBundle', 'Test-SalesforceAgentPlugin',
                    # Issue 255
                    'New-SalesforceAgentUser', 'Open-SalesforceAgent', 'New-SalesforceAgent', 'New-SalesforceAgentSpec',
                    'New-SalesforceAgentTemplate', 'New-SalesforceAgentTestSpec', 'New-SalesforceAgentTest', 'Resume-SalesforceAgentTest',
                    'Start-SalesforceAgentEvaluation', 'Start-SalesforceAgentPreview', 'Send-SalesforceAgentPreviewMessage',
                    'Stop-SalesforceAgentPreview', 'Get-SalesforceAgentPreviewSessions', 'Invoke-SalesforceAgentPreview',
                    'Get-SalesforceAgentTraces', 'Read-SalesforceAgentTrace', 'Remove-SalesforceAgentTrace',
                    'New-SalesforceAgentDataLibrary', 'Get-SalesforceAgentDataLibraries', 'Get-SalesforceAgentDataLibrary',
                    'Get-SalesforceAgentDataLibraryStatus', 'Update-SalesforceAgentDataLibrary', 'Remove-SalesforceAgentDataLibrary',
                    'Get-SalesforceAgentDataLibraryFiles', 'Add-SalesforceAgentDataLibraryFile', 'Remove-SalesforceAgentDataLibraryFile',
                    'Send-SalesforceAgentDataLibraryFile', 'New-SalesforceMcpServer', 'Update-SalesforceMcpServer',
                    'Remove-SalesforceMcpServer', 'Get-SalesforceMcpServer', 'Get-SalesforceMcpServers', 'Get-SalesforceMcpAssets',
                    'Get-SalesforceMcpServerLiveAssets', 'Set-SalesforceMcpAssets'
                )
                $exported | Should -Be @($expected | Sort-Object)
                $exported | Should -Not -Contain 'Assert-SalesforceAgentInteractiveSession'
                $exported | Should -Not -Contain 'ConvertTo-SalesforceAgentPlainText'
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

Describe 'psfdx-agentforce full sf agent parity (issue 255)' {
    InModuleScope 'psfdx-agentforce' {
        BeforeAll {
            $script:dir = Join-Path $TestDrive ('p-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:dir | Out-Null
            foreach ($f in 'spec.yaml', 'agent.bot-meta.xml', 'def.json', 'assets.json', 'a.pdf', 'b.pdf') { Set-Content -LiteralPath (Join-Path $script:dir $f) -Value 'x' }
            $script:resolve = { param($v) if ($v -is [string]) { $v.Replace('{dir}', $script:dir) } else { $v } }
        }
        BeforeEach {
            $script:Seen = @()
            Mock Invoke-Salesforce {
                if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                $script:Seen += , @{ Args = ($Arguments -join '|'); Interactive = [bool]$Interactive }
                return '{"status":0,"result":{"ok":true,"id":"x1"}}'
            }
            Mock Assert-SalesforceAgentInteractiveSession { }
        }

        Context 'every non-interactive cmdlet builds its exact command and asks for JSON' {
            It '<Cmdlet> runs sf <Expected>' -ForEach @(
                @{ Cmdlet = 'New-SalesforceAgentUser'; Splat = @{ BaseUsername = 'svc@x.com'; FirstName = 'Svc'; LastName = 'Agent'; TargetOrg = 'dev'; Confirm = $false }; Expected = 'org|create|agent-user|--base-username|svc@x.com|--first-name|Svc|--last-name|Agent|--target-org|dev|--json' }
                @{ Cmdlet = 'New-SalesforceAgent'; Splat = @{ Spec = '{dir}\spec.yaml'; Name = 'Svc Agent'; ApiName = 'Svc_Agent'; Preview = $true; TargetOrg = 'dev'; Confirm = $false }; Expected = 'agent|create|--spec|{dir}\spec.yaml|--name|Svc Agent|--api-name|Svc_Agent|--preview|--target-org|dev|--json' }
                @{ Cmdlet = 'New-SalesforceAgentSpec'; Splat = @{ Role = 'Answers orders'; CompanyName = 'Acme'; CompanyDescription = "We sell 'anvils'"; CompanyWebsite = 'https://acme.example.com'; Type = 'customer'; Tone = 'casual'; AgentUser = 'svc@x.com'; MaxTopics = 5; GroundingContext = 'ctx'; PromptTemplate = 'Tpl'; EnrichLogs = 'true'; Spec = '{dir}\spec.yaml'; OutputFile = '{dir}\out.yaml'; ForceOverwrite = $true; TargetOrg = 'dev' }; Expected = "agent|generate|agent-spec|--role|Answers orders|--company-name|Acme|--company-description|We sell 'anvils'|--company-website|https://acme.example.com|--type|customer|--tone|casual|--agent-user|svc@x.com|--max-topics|5|--grounding-context|ctx|--prompt-template|Tpl|--enrich-logs|true|--spec|{dir}\spec.yaml|--output-file|{dir}\out.yaml|--force-overwrite|--target-org|dev|--json" }
                @{ Cmdlet = 'New-SalesforceAgentTemplate'; Splat = @{ AgentFile = '{dir}\agent.bot-meta.xml'; AgentVersion = 2; SourceOrg = 'dev'; OutputDir = 'out' }; Expected = 'agent|generate|template|--agent-file|{dir}\agent.bot-meta.xml|--agent-version|2|--source-org|dev|--output-dir|out|--json' }
                @{ Cmdlet = 'New-SalesforceAgentTest'; Splat = @{ Spec = '{dir}\spec.yaml'; ApiName = 'Orders_Test'; Preview = $true; ForceOverwrite = $true; TestRunner = 'testing-center'; TargetOrg = 'dev'; Confirm = $false }; Expected = 'agent|test|create|--spec|{dir}\spec.yaml|--api-name|Orders_Test|--preview|--force-overwrite|--test-runner|testing-center|--target-org|dev|--json' }
                @{ Cmdlet = 'Resume-SalesforceAgentTest'; Splat = @{ JobId = '4KBxx0000000001AAA'; WaitMinutes = 10; ExtendedDetails = $true; OutputDir = 'out'; TestRunner = 'agentforce-studio'; TargetOrg = 'dev' }; Expected = 'agent|test|resume|--job-id|4KBxx0000000001AAA|--wait|10|--verbose|--output-dir|out|--test-runner|agentforce-studio|--target-org|dev|--json' }
                @{ Cmdlet = 'Resume-SalesforceAgentTest'; Splat = @{ UseMostRecent = $true; ResultFormat = 'json' }; Expected = 'agent|test|resume|--use-most-recent|--result-format|json|--json' }
                @{ Cmdlet = 'Start-SalesforceAgentEvaluation'; Splat = @{ Spec = '{dir}\spec.yaml'; ApiName = 'Svc_Agent'; BatchSize = 3; NoNormalize = $true; ResultFormat = 'json'; TargetOrg = 'dev' }; Expected = 'agent|test|run-eval|--spec|{dir}\spec.yaml|--api-name|Svc_Agent|--batch-size|3|--no-normalize|--result-format|json|--target-org|dev|--json' }
                @{ Cmdlet = 'Start-SalesforceAgentPreview'; Splat = @{ AuthoringBundle = 'My_Bundle'; ContextVariables = [ordered]@{ order = '1001'; vip = $true }; SimulateActions = $true; TargetOrg = 'dev' }; Expected = 'agent|preview|start|--authoring-bundle|My_Bundle|--context-variables|order=1001|--context-variables|vip=true|--simulate-actions|--target-org|dev|--json' }
                @{ Cmdlet = 'Start-SalesforceAgentPreview'; Splat = @{ ApiName = 'Svc_Agent'; ContextVariablesJson = '{"order":"1001"}'; UseLiveActions = $true }; Expected = 'agent|preview|start|--api-name|Svc_Agent|--context-variables-json|{"order":"1001"}|--use-live-actions|--json' }
                @{ Cmdlet = 'Send-SalesforceAgentPreviewMessage'; Splat = @{ Utterance = 'Where''s my "order"? & more; $(x)'; SessionId = 'a1b2-c3d4'; TargetOrg = 'dev' }; Expected = 'agent|preview|send|--utterance|Where''s my "order"? & more; $(x)|--session-id|a1b2-c3d4|--target-org|dev|--json' }
                @{ Cmdlet = 'Stop-SalesforceAgentPreview'; Splat = @{ SessionId = 'a1b2-c3d4'; TargetOrg = 'dev'; Confirm = $false }; Expected = 'agent|preview|end|--session-id|a1b2-c3d4|--no-prompt|--target-org|dev|--json' }
                @{ Cmdlet = 'Stop-SalesforceAgentPreview'; Splat = @{ All = $true; NoPrompt = $true }; Expected = 'agent|preview|end|--all|--no-prompt|--json' }
                @{ Cmdlet = 'Get-SalesforceAgentPreviewSessions'; Splat = @{}; Expected = 'agent|preview|sessions|--json' }
                @{ Cmdlet = 'Get-SalesforceAgentTraces'; Splat = @{ Agent = 'Svc_Agent'; SessionId = 'a1b2'; Since = [datetime]'2026-11-01' }; Expected = 'agent|trace|list|--agent|Svc_Agent|--session-id|a1b2|--since|2026-11-01|--json' }
                @{ Cmdlet = 'Read-SalesforceAgentTrace'; Splat = @{ SessionId = 'a1b2'; Format = 'detail'; Dimension = 'routing'; Turn = 2 }; Expected = 'agent|trace|read|--session-id|a1b2|--format|detail|--dimension|routing|--turn|2|--json' }
                @{ Cmdlet = 'Remove-SalesforceAgentTrace'; Splat = @{ Agent = 'Svc_Agent'; SessionId = 'a1b2'; OlderThan = '7d'; Confirm = $false }; Expected = 'agent|trace|delete|--agent|Svc_Agent|--session-id|a1b2|--older-than|7d|--no-prompt|--json' }
                @{ Cmdlet = 'New-SalesforceAgentDataLibrary'; Splat = @{ Name = 'Product Manuals'; DeveloperName = 'Product_Manuals'; SourceType = 'knowledge'; Description = 'D'; IndexMode = 'enhanced'; ContentFields = 'Title', 'Body'; DataCategoryIds = 'C1', 'C2'; PrimaryIndexField1 = 'F1'; PrimaryIndexField2 = 'F2'; RetrieverId = 'R1'; WaitMinutes = 5; TargetOrg = 'dev'; Confirm = $false }; Expected = 'agent|adl|create|--name|Product Manuals|--developer-name|Product_Manuals|--source-type|knowledge|--description|D|--index-mode|enhanced|--content-fields|Title,Body|--data-category-ids|C1,C2|--primary-index-field1|F1|--primary-index-field2|F2|--retriever-id|R1|--wait|5|--target-org|dev|--json' }
                @{ Cmdlet = 'Get-SalesforceAgentDataLibraries'; Splat = @{ SourceType = 'sfdrive'; TargetOrg = 'dev' }; Expected = 'agent|adl|list|--source-type|sfdrive|--target-org|dev|--json' }
                @{ Cmdlet = 'Get-SalesforceAgentDataLibrary'; Splat = @{ LibraryId = '1JDxx0000000001'; TargetOrg = 'dev' }; Expected = 'agent|adl|get|--library-id|1JDxx0000000001|--target-org|dev|--json' }
                @{ Cmdlet = 'Get-SalesforceAgentDataLibraryStatus'; Splat = @{ LibraryId = '1JDxx0000000001'; IncludeArtifacts = $true }; Expected = 'agent|adl|status|--library-id|1JDxx0000000001|--include-artifacts|--json' }
                @{ Cmdlet = 'Update-SalesforceAgentDataLibrary'; Splat = @{ LibraryId = '1JDxx0000000001'; Name = 'N'; Description = 'D'; ContentFields = 'Body'; RetrieverId = 'R1'; DataCategoryRule = $true; RestrictToPublicArticles = $true; Confirm = $false }; Expected = 'agent|adl|update|--library-id|1JDxx0000000001|--name|N|--description|D|--content-fields|Body|--retriever-id|R1|--data-category-rule|--restrict-to-public-articles|--json' }
                @{ Cmdlet = 'Remove-SalesforceAgentDataLibrary'; Splat = @{ LibraryId = '1JDxx0000000001'; TargetOrg = 'dev'; Confirm = $false }; Expected = 'agent|adl|delete|--library-id|1JDxx0000000001|--target-org|dev|--json' }
                @{ Cmdlet = 'Get-SalesforceAgentDataLibraryFiles'; Splat = @{ LibraryId = '1JDxx0000000001'; Status = 'index_failed'; Offset = 0; PageSize = 50 }; Expected = 'agent|adl|file|list|--library-id|1JDxx0000000001|--status|index_failed|--offset|0|--page-size|50|--json' }
                @{ Cmdlet = 'Add-SalesforceAgentDataLibraryFile'; Splat = @{ LibraryId = '1JDxx0000000001'; Path = '{dir}\a.pdf', '{dir}\b.pdf'; Confirm = $false }; Expected = 'agent|adl|file|add|--library-id|1JDxx0000000001|--path|{dir}\a.pdf|--path|{dir}\b.pdf|--json' }
                @{ Cmdlet = 'Remove-SalesforceAgentDataLibraryFile'; Splat = @{ LibraryId = '1JDxx0000000001'; FileId = '0Pexx0000000001'; Confirm = $false }; Expected = 'agent|adl|file|delete|--library-id|1JDxx0000000001|--file-id|0Pexx0000000001|--json' }
                @{ Cmdlet = 'Send-SalesforceAgentDataLibraryFile'; Splat = @{ LibraryId = '1JDxx0000000001'; File = '{dir}\a.pdf'; WaitMinutes = 10; Confirm = $false }; Expected = 'agent|adl|upload|--library-id|1JDxx0000000001|--file|{dir}\a.pdf|--wait|10|--json' }
                @{ Cmdlet = 'Get-SalesforceMcpServers'; Splat = @{ Label = 'Orders'; Status = 'ACTIVE'; Type = 'EXTERNAL'; TargetOrg = 'dev' }; Expected = 'agent|mcp|list|--label|Orders|--status|ACTIVE|--type|EXTERNAL|--target-org|dev|--json' }
                @{ Cmdlet = 'Get-SalesforceMcpServer'; Splat = @{ McpServerId = '0Xxxx0000000001'; TargetOrg = 'dev' }; Expected = 'agent|mcp|get|--mcp-server-id|0Xxxx0000000001|--target-org|dev|--json' }
                @{ Cmdlet = 'Get-SalesforceMcpAssets'; Splat = @{ McpServerId = '0Xxxx0000000001' }; Expected = 'agent|mcp|asset|list|--mcp-server-id|0Xxxx0000000001|--json' }
                @{ Cmdlet = 'Get-SalesforceMcpServerLiveAssets'; Splat = @{ McpServerId = '0Xxxx0000000001' }; Expected = 'agent|mcp|fetch|--mcp-server-id|0Xxxx0000000001|--json' }
                @{ Cmdlet = 'Remove-SalesforceMcpServer'; Splat = @{ McpServerId = '0Xxxx0000000001'; Confirm = $false }; Expected = 'agent|mcp|delete|--mcp-server-id|0Xxxx0000000001|--no-prompt|--json' }
                @{ Cmdlet = 'Set-SalesforceMcpAssets'; Splat = @{ McpServerId = '0Xxxx0000000001'; AssetsFile = '{dir}\assets.json'; Confirm = $false }; Expected = 'agent|mcp|asset|replace|--mcp-server-id|0Xxxx0000000001|--assets-file|{dir}\assets.json|--json' }
                @{ Cmdlet = 'Set-SalesforceMcpAssets'; Splat = @{ McpServerId = '0Xxxx0000000001'; AssetList = @([ordered]@{ name = 'tool1'; type = 'tool' }); Confirm = $false }; Expected = 'agent|mcp|asset|replace|--mcp-server-id|0Xxxx0000000001|--assets|[{"name":"tool1","type":"tool"}]|--json' }
            ) {
                $invokeArgs = @{}
                foreach ($k in $Splat.Keys) { $v = $Splat[$k]; if ($v -is [array]) { $invokeArgs[$k] = @($v | ForEach-Object { & $script:resolve $_ }) } else { $invokeArgs[$k] = & $script:resolve $v } }
                & $Cmdlet @invokeArgs | Out-Null
                @($script:Seen).Count | Should -Be 1
                $script:Seen[0].Args | Should -Be (& $script:resolve $Expected)
                $script:Seen[0].Interactive | Should -BeFalse
            }
        }

        Context 'what the interactive cmdlets ask the CLI, and that they need a terminal' {
            It 'Invoke-SalesforceAgentPreview runs interactively, without --json' {
                Invoke-SalesforceAgentPreview -ApiName Svc_Agent -ContextVariables @{ order = '1' } -ApexDebug -UseLiveActions -OutputDir out -TargetOrg dev
                @($script:Seen).Count | Should -Be 1
                $script:Seen[0].Args | Should -Be 'agent|preview|--api-name|Svc_Agent|--context-variables|order=1|--apex-debug|--use-live-actions|--output-dir|out|--target-org|dev'
                $script:Seen[0].Interactive | Should -BeTrue
                Assert-MockCalled Assert-SalesforceAgentInteractiveSession -Times 1 -Exactly -ParameterFilter { $Command -eq 'sf agent preview' }
            }
            It 'New-SalesforceAgentTestSpec asks questions unless -FromDefinition is given' {
                New-SalesforceAgentTestSpec -OutputFile (Join-Path $script:dir 'ts.yaml') -ForceOverwrite -TestRunner testing-center
                $script:Seen[0].Interactive | Should -BeTrue
                $script:Seen[0].Args | Should -Be "agent|generate|test-spec|--output-file|$(Join-Path $script:dir 'ts.yaml')|--force-overwrite|--test-runner|testing-center"
                Assert-MockCalled Assert-SalesforceAgentInteractiveSession -Times 1 -Exactly
                New-SalesforceAgentTestSpec -FromDefinition (Join-Path $script:dir 'def.json')
                Assert-MockCalled Assert-SalesforceAgentInteractiveSession -Times 1 -Exactly
                $script:Seen[1].Args | Should -Be "agent|generate|test-spec|--from-definition|$(Join-Path $script:dir 'def.json')"
            }
            It 'New-SalesforceAgentSpec is interactive only with -FullInterview' {
                New-SalesforceAgentSpec -FullInterview -TargetOrg dev
                $script:Seen[0].Interactive | Should -BeTrue
                $script:Seen[0].Args | Should -Be 'agent|generate|agent-spec|--full-interview|--target-org|dev'
                Assert-MockCalled Assert-SalesforceAgentInteractiveSession -Times 1 -Exactly -ParameterFilter { $Command -like '*--full-interview' }
            }
            It 'refuse to run without a terminal, with the helper really called' {
                Mock Assert-SalesforceAgentInteractiveSession { throw 'needs a terminal' }
                { Invoke-SalesforceAgentPreview -ApiName Svc_Agent } | Should -Throw -ExpectedMessage '*needs a terminal*'
                { New-SalesforceAgentTestSpec } | Should -Throw -ExpectedMessage '*needs a terminal*'
                @($script:Seen).Count | Should -Be 0
            }
        }

        Context 'input checks happen before anything runs' {
            It 'rejects IDs and names that are not safe or valid' {
                foreach ($bad in 'a b', 'a;b', "a`nb", '', '$(x)') {
                    { Get-SalesforceAgentDataLibrary -LibraryId $bad } | Should -Throw
                    { Get-SalesforceMcpServer -McpServerId $bad } | Should -Throw
                    { Read-SalesforceAgentTrace -SessionId $bad } | Should -Throw
                }
                { Start-SalesforceAgentPreview -ApiName 'bad name' } | Should -Throw
                { Get-SalesforceAgentTraces -Agent 'bad name' } | Should -Throw
                @($script:Seen).Count | Should -Be 0
            }
            It 'checks files and folders exist' {
                { New-SalesforceAgent -Spec (Join-Path $script:dir 'nope.yaml') -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist*'
                { New-SalesforceAgentTemplate -AgentFile (Join-Path $script:dir 'nope.xml') -AgentVersion 1 -SourceOrg dev } | Should -Throw -ExpectedMessage '*does not exist*'
                { New-SalesforceAgentSpec -OutputFile (Join-Path $script:dir 'nofolder\o.yaml') } | Should -Throw -ExpectedMessage '*does not exist*'
                { New-SalesforceAgentTest -Spec (Join-Path $script:dir 'nope.yaml') -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist*'
                { Add-SalesforceAgentDataLibraryFile -LibraryId 1JDxx0000000001 -Path (Join-Path $script:dir 'nope.pdf') -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist*'
                { Send-SalesforceAgentDataLibraryFile -LibraryId 1JDxx0000000001 -File (Join-Path $script:dir 'nope.pdf') -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist*'
                { Start-SalesforceAgentEvaluation -Spec (Join-Path $script:dir 'nope.yaml') } | Should -Throw -ExpectedMessage '*does not exist*'
                { Set-SalesforceMcpAssets -McpServerId 0Xxxx0000000001 -AssetsFile (Join-Path $script:dir 'nope.json') -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist*'
                @($script:Seen).Count | Should -Be 0
            }
            It 'refuses options that do not go together' {
                { Start-SalesforceAgentPreview -ApiName A -AuthoringBundle B } | Should -Throw -ExpectedMessage '*not both*'
                { Start-SalesforceAgentPreview -ApiName A -ContextVariables @{ a = '1' } -ContextVariablesJson '{}' } | Should -Throw -ExpectedMessage '*not both*'
                { Start-SalesforceAgentPreview -AuthoringBundle B -SimulateActions -UseLiveActions } | Should -Throw -ExpectedMessage '*not both*'
                { Start-SalesforceAgentPreview -ApiName A -ContextVariablesJson 'not json' } | Should -Throw -ExpectedMessage '*not valid JSON*'
                { Open-SalesforceAgent -ApiName A -AuthoringBundle B } | Should -Throw -ExpectedMessage '*not both*'
                { Read-SalesforceAgentTrace -SessionId a1 -Format summary -Dimension routing } | Should -Throw -ExpectedMessage '*-Format detail*'
                { Set-SalesforceMcpAssets -McpServerId 0Xxxx0000000001 -Assets '[]' -AssetsFile (Join-Path $script:dir 'assets.json') -Confirm:$false } | Should -Throw -ExpectedMessage '*exactly one*'
                { Set-SalesforceMcpAssets -McpServerId 0Xxxx0000000001 -Confirm:$false } | Should -Throw -ExpectedMessage '*exactly one*'
                { Set-SalesforceMcpAssets -McpServerId 0Xxxx0000000001 -Assets 'nope' -Confirm:$false } | Should -Throw -ExpectedMessage '*not valid JSON*'
                @($script:Seen).Count | Should -Be 0
            }
            It 'refuses unsafe context variable names and values' {
                foreach ($bad in @{ 'bad name' = '1' }, @{ '--json' = '1' }, @{ a = 'say "hi"' }, @{ a = "x`ny" }) { { Start-SalesforceAgentPreview -ApiName A -ContextVariables $bad } | Should -Throw }
                @($script:Seen).Count | Should -Be 0
            }
            It 'cannot delete every trace by accident, and checks the age filter' {
                { Remove-SalesforceAgentTrace -Confirm:$false } | Should -Throw -ExpectedMessage '*so that not every trace*'
                foreach ($bad in '7', 'd', '7 days', "7d`n", '-1d') { { Remove-SalesforceAgentTrace -OlderThan $bad -Confirm:$false } | Should -Throw }
                @($script:Seen).Count | Should -Be 0
            }
            It 'requires at least one file and one asset source' {
                { Add-SalesforceAgentDataLibraryFile -LibraryId 1JDxx0000000001 -Path @() -Confirm:$false } | Should -Throw
                { New-SalesforceMcpServer -Name Orders -ServerUrl http://mcp.example.com -Confirm:$false } | Should -Throw -ExpectedMessage '*https*'
                { New-SalesforceMcpServer -Name Orders -ServerUrl 'mcp.example.com' -Confirm:$false } | Should -Throw -ExpectedMessage '*https*'
                { Update-SalesforceMcpServer -McpServerId 0Xxxx0000000001 -ServerUrl http://mcp.example.com -Confirm:$false } | Should -Throw -ExpectedMessage '*https*'
                @($script:Seen).Count | Should -Be 0
            }
        }

        Context 'confirmation: -WhatIf makes no CLI call and -NoPrompt never turns it off' {
            It 'high-impact cmdlets do nothing with -WhatIf' {
                Remove-SalesforceAgentDataLibrary -LibraryId 1JDxx0000000001 -WhatIf | Out-Null
                Remove-SalesforceAgentDataLibraryFile -LibraryId 1JDxx0000000001 -FileId 0Pexx0000000001 -WhatIf | Out-Null
                Remove-SalesforceMcpServer -McpServerId 0Xxxx0000000001 -WhatIf | Out-Null
                Remove-SalesforceAgentTrace -Agent Svc_Agent -WhatIf | Out-Null
                Stop-SalesforceAgentPreview -All -WhatIf | Out-Null
                Remove-SalesforceAgentTrace -Agent Svc_Agent -NoPrompt -WhatIf | Out-Null
                Remove-SalesforceMcpServer -McpServerId 0Xxxx0000000001 -NoPrompt -WhatIf | Out-Null
                @($script:Seen).Count | Should -Be 0
            }
            It 'the deletes are high impact and the creates and updates are medium' {
                foreach ($n in 'Remove-SalesforceAgentDataLibrary', 'Remove-SalesforceAgentDataLibraryFile', 'Remove-SalesforceMcpServer', 'Remove-SalesforceAgentTrace') {
                    (Get-Command $n).ScriptBlock.Attributes.Where({ $_ -is [System.Management.Automation.CmdletBindingAttribute] })[0].ConfirmImpact | Should -Be 'High'
                }
                foreach ($n in 'New-SalesforceAgent', 'New-SalesforceAgentTest', 'New-SalesforceAgentDataLibrary', 'Update-SalesforceAgentDataLibrary', 'Add-SalesforceAgentDataLibraryFile', 'Send-SalesforceAgentDataLibraryFile', 'New-SalesforceMcpServer', 'Update-SalesforceMcpServer', 'Set-SalesforceMcpAssets', 'New-SalesforceAgentUser', 'Stop-SalesforceAgentPreview') {
                    (Get-Command $n).ScriptBlock.Attributes.Where({ $_ -is [System.Management.Automation.CmdletBindingAttribute] })[0].ConfirmImpact | Should -Be 'Medium'
                }
            }
            It 'a -Preview run asks for no confirmation because it changes nothing' {
                # With the preference at Low even a medium-impact cmdlet would prompt, and a prompt cannot be answered here.
                $ConfirmPreference = 'Low'
                { New-SalesforceAgent -Spec (Join-Path $script:dir 'spec.yaml') -Preview | Out-Null } | Should -Not -Throw
                @($script:Seen).Count | Should -Be 1
            }
        }

        Context 'data library list flags and switches (review findings)' {
            It 'joins list values with commas into one flag, as the CLI takes them' {
                New-SalesforceAgentDataLibrary -Name N -DeveloperName N_Lib -SourceType knowledge -ContentFields Title, Body -DataCategoryNames 'Grp.A', 'Grp.B' -Confirm:$false | Out-Null
                $script:Seen[0].Args | Should -Be 'agent|adl|create|--name|N|--developer-name|N_Lib|--source-type|knowledge|--content-fields|Title,Body|--data-category-names|Grp.A,Grp.B|--json'
                Update-SalesforceAgentDataLibrary -LibraryId 1JDxx0000000001 -ContentFields Title, Body, Summary -Confirm:$false | Out-Null
                $script:Seen[1].Args | Should -Be 'agent|adl|update|--library-id|1JDxx0000000001|--content-fields|Title,Body,Summary|--json'
            }
            It 'refuses category IDs and category names together, as the CLI does' {
                { New-SalesforceAgentDataLibrary -Name N -DeveloperName N_Lib -SourceType knowledge -DataCategoryIds C1 -DataCategoryNames 'Grp.A' -Confirm:$false } | Should -Throw -ExpectedMessage '*not both*'
                @($script:Seen).Count | Should -Be 0
            }
            It 'sends the --no- form when a switch is explicitly false, and nothing when it is not given' {
                Update-SalesforceAgentDataLibrary -LibraryId 1JDxx0000000001 -DataCategoryRule:$false -RestrictToPublicArticles:$false -Confirm:$false | Out-Null
                $script:Seen[0].Args | Should -Be 'agent|adl|update|--library-id|1JDxx0000000001|--no-data-category-rule|--no-restrict-to-public-articles|--json'
                Update-SalesforceAgentDataLibrary -LibraryId 1JDxx0000000001 -DataCategoryRule:$true -Confirm:$false | Out-Null
                $script:Seen[1].Args | Should -Be 'agent|adl|update|--library-id|1JDxx0000000001|--data-category-rule|--json'
                Update-SalesforceAgentDataLibrary -LibraryId 1JDxx0000000001 -Name N -Confirm:$false | Out-Null
                $script:Seen[2].Args | Should -Be 'agent|adl|update|--library-id|1JDxx0000000001|--name|N|--json'
            }
        }

        Context 'a failing exit code in a text result format is not swallowed (review finding)' {
            BeforeEach {
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    $global:LASTEXITCODE = 1
                    return 'Test run failed: 2 of 5 tests failed.'
                }
            }
            AfterEach { $global:LASTEXITCODE = 0 }
            It '<Name> throws PsfdxAgentCommandFailed with the CLI text, which is also the target object' -ForEach @(
                @{ Name = 'Start-SalesforceAgentTest'; Call = { Start-SalesforceAgentTest -ApiName Orders_Test -ResultFormat junit } }
                @{ Name = 'Get-SalesforceAgentTestResult'; Call = { Get-SalesforceAgentTestResult -JobId 4KBxx0000000001AAA -ResultFormat tap } }
                @{ Name = 'Resume-SalesforceAgentTest'; Call = { Resume-SalesforceAgentTest -JobId 4KBxx0000000001AAA -ResultFormat human } }
                @{ Name = 'Start-SalesforceAgentEvaluation'; Call = { Start-SalesforceAgentEvaluation -Spec (Join-Path $script:dir 'spec.yaml') -ResultFormat junit } }
                @{ Name = 'Open-SalesforceAgent'; Call = { Open-SalesforceAgent -ApiName Svc_Agent -UrlOnly } }
            ) {
                $err = $null
                try { & $Call } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -BeLike 'PsfdxAgentCommandFailed*'
                $err.Exception.Message | Should -BeLike '*exited with code 1*2 of 5 tests failed*'
                $err.TargetObject | Should -Be 'Test run failed: 2 of 5 tests failed.'
            }
            It 'a successful text run still returns the text' {
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    $global:LASTEXITCODE = 0
                    return '<testsuites/>'
                }
                (Start-SalesforceAgentTest -ApiName Orders_Test -ResultFormat junit) | Should -Be '<testsuites/>'
            }
        }

        Context 'arguments the Windows .cmd launcher refuses (review finding)' {
            BeforeEach {
                # What Invoke-Salesforce does on Windows when sf is a .cmd shim and an argument has a double quote.
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    if (@($Arguments | Where-Object { $_ -match '["\r\n]' }).Count -gt 0) { throw "Argument contains a character that cannot be passed safely to 'sf' on Windows (double quote or line break)." }
                    return '{"status":0,"result":{"ok":true}}'
                }
            }
            It 'says to use -ContextVariables when -ContextVariablesJson is refused, for the programmatic and the interactive preview' {
                { Start-SalesforceAgentPreview -ApiName Svc_Agent -ContextVariablesJson '{"order":"1001"}' } | Should -Throw -ExpectedMessage '*Use -ContextVariables (name and value pairs) instead*cannot be passed safely*'
                { Invoke-SalesforceAgentPreview -ApiName Svc_Agent -ContextVariablesJson '{"order":"1001"}' } | Should -Throw -ExpectedMessage '*Use -ContextVariables (name and value pairs) instead*'
            }
            It 'says to use -AssetsFile when the assets JSON is refused' {
                { Set-SalesforceMcpAssets -McpServerId 0Xxxx0000000001 -Assets '[{"name":"t"}]' -Confirm:$false } | Should -Throw -ExpectedMessage '*use -AssetsFile instead*'
                { Set-SalesforceMcpAssets -McpServerId 0Xxxx0000000001 -AssetList @([ordered]@{ name = 't' }) -Confirm:$false } | Should -Throw -ExpectedMessage '*use -AssetsFile instead*'
                { Set-SalesforceMcpAssets -McpServerId 0Xxxx0000000001 -AssetsFile (Join-Path $script:dir 'assets.json') -Confirm:$false } | Should -Not -Throw
            }
            It 'explains a refused utterance, and leaves other failures alone' {
                { Send-SalesforceAgentPreviewMessage -SessionId a1b2 -Utterance 'say "hi"' } | Should -Throw -ExpectedMessage '*utterance has a double quote*'
                { Send-SalesforceAgentPreviewMessage -SessionId a1b2 -Utterance 'plain words' } | Should -Not -Throw
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    throw 'The sf executable was not found.'
                }
                $err = $null
                try { Start-SalesforceAgentPreview -ApiName Svc_Agent -ContextVariablesJson '{"a":"1"}' } catch { $err = $_ }
                $err.Exception.Message | Should -Be 'The sf executable was not found.'
            }
            It 'the help says the JSON parameters do not work on Windows and names the alternative' {
                $help = Get-Help Start-SalesforceAgentPreview -Parameter ContextVariablesJson | Out-String
                $help | Should -BeLike '*Windows*use -ContextVariables*'
                (Get-Help Set-SalesforceMcpAssets -Parameter Assets | Out-String) | Should -BeLike '*Windows*use -AssetsFile*'
            }
        }

        Context 'MCP client secret' {
            It 'takes a SecureString only, sends its text to sf, and never prints it' {
                $secret = ConvertTo-SecureString 'TOPSECRETVALUE' -AsPlainText -Force
                (Get-Command New-SalesforceMcpServer).Parameters['ClientSecret'].ParameterType | Should -Be ([System.Security.SecureString])
                (Get-Command Update-SalesforceMcpServer).Parameters['ClientSecret'].ParameterType | Should -Be ([System.Security.SecureString])
                $out = New-SalesforceMcpServer -Name Orders_Mcp -ServerUrl https://mcp.example.com/orders -AuthType OAUTH -Label 'Orders' -Description 'D' -IdentityProvider Okta -Scope 'read write' -ClientId cid -ClientSecret $secret -TargetOrg dev -Confirm:$false -Verbose 4>&1 3>&1 | Out-String
                $script:Seen[0].Args | Should -Be 'agent|mcp|create|--name|Orders_Mcp|--server-url|https://mcp.example.com/orders|--auth-type|OAUTH|--label|Orders|--description|D|--identity-provider|Okta|--scope|read write|--client-id|cid|--client-secret|TOPSECRETVALUE|--target-org|dev|--json'
                $out | Should -Not -BeLike '*TOPSECRET*'
                Update-SalesforceMcpServer -McpServerId 0Xxxx0000000001 -ClientSecret $secret -Confirm:$false | Out-Null
                $script:Seen[1].Args | Should -Be 'agent|mcp|update|--mcp-server-id|0Xxxx0000000001|--client-secret|TOPSECRETVALUE|--json'
            }
            It 'the secret is masked in the verbose line that Invoke-Salesforce prints' {
                $masked = & (Get-Module psfdx-shared) { Get-PsfdxRedactedCommand -Command 'sf agent mcp create --name x --client-secret TOPSECRETVALUE --json' }
                $masked | Should -Not -BeLike '*TOPSECRET*'
                $masked | Should -BeLike '*--client-secret *********'
            }
        }

        Context 'results and failures' {
            It 'returns the CLI result as an object' {
                $r = Get-SalesforceAgentDataLibrary -LibraryId 1JDxx0000000001
                $r.ok | Should -BeTrue
            }
            It 'throws the CLI message' {
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    return '{"status":1,"message":"Library not found."}'
                }
                { Get-SalesforceAgentDataLibrary -LibraryId 1JDxx0000000001 } | Should -Throw -ExpectedMessage '*Library not found*'
                { Remove-SalesforceMcpServer -McpServerId 0Xxxx0000000001 -Confirm:$false } | Should -Throw -ExpectedMessage '*Library not found*'
            }
            It 'stops with install guidance when the agent plugin is missing' {
                Mock Invoke-Salesforce { '{"status":0,"result":[{"name":"@salesforce/plugin-auth"}]}' }
                { Get-SalesforceMcpServers } | Should -Throw -ExpectedMessage '*@salesforce/plugin-agent*not installed*'
                { Start-SalesforceAgentPreview -ApiName A } | Should -Throw -ExpectedMessage '*not installed*'
            }
        }

        Context 'text result formats' {
            It 'Resume-SalesforceAgentTest and Start-SalesforceAgentEvaluation return the CLI text for junit, tap and human' {
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    $script:Seen += , @{ Args = ($Arguments -join '|') }
                    return '<testsuites/>'
                }
                (Resume-SalesforceAgentTest -JobId 4KBxx0000000001AAA -ResultFormat junit) | Should -Be '<testsuites/>'
                $script:Seen[0].Args | Should -Be 'agent|test|resume|--job-id|4KBxx0000000001AAA|--result-format|junit'
                Start-SalesforceAgentEvaluation -Spec (Join-Path $script:dir 'spec.yaml') -ResultFormat tap | Out-Null
                $script:Seen[1].Args | Should -Be "agent|test|run-eval|--spec|$(Join-Path $script:dir 'spec.yaml')|--result-format|tap"
                Start-SalesforceAgentEvaluation -Spec (Join-Path $script:dir 'spec.yaml') | Out-Null
                $script:Seen[2].Args | Should -Be "agent|test|run-eval|--spec|$(Join-Path $script:dir 'spec.yaml')"
            }
            It 'rejects an unknown format and a bad batch size' {
                { Resume-SalesforceAgentTest -JobId 4KBxx0000000001AAA -ResultFormat xml } | Should -Throw
                { Start-SalesforceAgentEvaluation -Spec (Join-Path $script:dir 'spec.yaml') -BatchSize 6 } | Should -Throw
                { Start-SalesforceAgentEvaluation -Spec (Join-Path $script:dir 'spec.yaml') -BatchSize 0 } | Should -Throw
            }
        }

        Context 'flags added to the existing cmdlets' {
            It 'Start-SalesforceAgentTest and Get-SalesforceAgentTestResult pass the new options' {
                Start-SalesforceAgentTest -ApiName Orders_Test -ExtendedDetails -OutputDir out -TestRunner testing-center -ResultFormat json -TargetOrg dev | Out-Null
                $script:Seen[0].Args | Should -Be 'agent|test|run|--api-name|Orders_Test|--verbose|--output-dir|out|--test-runner|testing-center|--result-format|json|--target-org|dev|--json'
                Get-SalesforceAgentTestResult -JobId 4KBxx0000000001AAA -ExtendedDetails -OutputDir out -TestRunner agentforce-studio -ResultFormat json | Out-Null
                $script:Seen[1].Args | Should -Be 'agent|test|results|--job-id|4KBxx0000000001AAA|--verbose|--output-dir|out|--test-runner|agentforce-studio|--result-format|json|--json'
            }
            It 'they are unchanged without the new options' {
                Start-SalesforceAgentTest -ApiName Orders_Test -WaitMinutes 5 | Out-Null
                $script:Seen[0].Args | Should -Be 'agent|test|run|--api-name|Orders_Test|--wait|5|--json'
                Get-SalesforceAgentTestResult -JobId 4KBxx0000000001AAA | Out-Null
                $script:Seen[1].Args | Should -Be 'agent|test|results|--job-id|4KBxx0000000001AAA|--json'
            }
            It 'junit, tap and human come back as the CLI text, without --json' {
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    $script:Seen += , @{ Args = ($Arguments -join '|') }
                    return 'TAP version 13'
                }
                (Get-SalesforceAgentTestResult -JobId 4KBxx0000000001AAA -ResultFormat tap) | Should -Be 'TAP version 13'
                $script:Seen[0].Args | Should -Be 'agent|test|results|--job-id|4KBxx0000000001AAA|--result-format|tap'
                (Start-SalesforceAgentTest -ApiName Orders_Test -ResultFormat human) | Should -Be 'TAP version 13'
                $script:Seen[1].Args | Should -Be 'agent|test|run|--api-name|Orders_Test|--result-format|human'
            }
            It 'New-SalesforceAgentAuthoringBundle passes -ForceOverwrite' {
                New-SalesforceAgentAuthoringBundle -Name Bundle -NoSpec -ForceOverwrite -Confirm:$false | Out-Null
                $script:Seen[0].Args | Should -BeLike 'agent|generate|authoring-bundle|--name|Bundle|--no-spec|--force-overwrite*'
            }
            It 'Publish-SalesforceAgentAuthoringBundle passes -Concise, -ExtendedDetails and -SourceType' {
                Publish-SalesforceAgentAuthoringBundle -ApiName My_Bundle -Concise -SourceType Bot -Confirm:$false | Out-Null
                $script:Seen[0].Args | Should -Be 'agent|publish|authoring-bundle|--api-name|My_Bundle|--concise|--source-type|Bot|--json'
                Publish-SalesforceAgentAuthoringBundle -ApiName My_Bundle -ExtendedDetails -Confirm:$false | Out-Null
                $script:Seen[1].Args | Should -Be 'agent|publish|authoring-bundle|--api-name|My_Bundle|--verbose|--json'
                { Publish-SalesforceAgentAuthoringBundle -ApiName My_Bundle -Concise -ExtendedDetails -Confirm:$false } | Should -Throw -ExpectedMessage '*not both*'
            }
        }

        Context 'Open-SalesforceAgent' {
            It 'passes every option and returns the CLI text' {
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -eq 'plugins|--core|--json') { return '{"status":0,"result":[{"name":"@salesforce/plugin-agent"}]}' }
                    $script:Seen += , @{ Args = ($Arguments -join '|') }
                    return 'https://x.my.salesforce.com/secur/frontdoor.jsp?sid=abc'
                }
                (Open-SalesforceAgent -ApiName Svc_Agent -Version 2 -Browser edge -BrowserPrivateMode -UrlOnly -TargetOrg dev) | Should -BeLike 'https://*'
                $script:Seen[0].Args | Should -Be 'org|open|agent|--api-name|Svc_Agent|--version|2|--browser|edge|--private|--url-only|--target-org|dev'
                { Open-SalesforceAgent -ApiName A -Browser safari } | Should -Throw
            }
        }
    }
}

Describe 'Assert-SalesforceAgentInteractiveSession (issue 255)' {
    InModuleScope 'psfdx-agentforce' {
        It 'refuses to run where input or output is redirected, as in CI and in scripts, and names the command' -Skip:(-not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)) {
            { Assert-SalesforceAgentInteractiveSession -Command 'sf agent preview' } | Should -Throw -ExpectedMessage 'sf agent preview asks questions, so it needs a terminal*'
        }
        It 'converts a SecureString to text and frees the buffer' {
            ConvertTo-SalesforceAgentPlainText -Value (ConvertTo-SecureString 'abc 123' -AsPlainText -Force) | Should -Be 'abc 123'
        }
    }
}
