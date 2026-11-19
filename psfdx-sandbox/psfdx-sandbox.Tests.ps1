# Ensure a clean module state before importing
Get-Module -Name 'psfdx-sandbox' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-sandbox.psd1'
Import-Module $moduleManifest -Force | Out-Null

Describe 'psfdx-sandbox module' {
    InModuleScope 'psfdx-sandbox' {
        Context 'Get-SalesforceSandboxes' {
            It 'returns empty array when no sandbox data is available' {
                Mock Invoke-Salesforce { '{"status":0}' }
                Mock Show-SalesforceResult { $null }

                $sandboxes = Get-SalesforceSandboxes
                $sandboxes.Count | Should -Be 0
            }

            It 'filters sandboxes by name, username, or alias' {
                Mock Invoke-Salesforce { '{"status":0}' }
                Mock Show-SalesforceResult {
                    @{
                        nonScratchOrgs = @(
                            [pscustomobject]@{ sandboxName = 'Dev1'; username = 'dev1@example.com'; alias = 'dev1'; isSandbox = $true },
                            [pscustomobject]@{ sandboxName = 'Dev2'; username = 'dev2@example.com'; alias = 'dev2'; isSandbox = $true },
                            [pscustomobject]@{ sandboxName = 'Prod'; username = 'prod@example.com'; alias = 'prod'; isSandbox = $false }
                        )
                    }
                }

                $bySandbox = Get-SalesforceSandboxes -Name 'Dev1'
                @($bySandbox).Count | Should -Be 1
                $bySandbox[0].sandboxName | Should -Be 'Dev1'

                $byUser = Get-SalesforceSandboxes -Name 'dev2@example.com'
                @($byUser).Count | Should -Be 1
                $byUser[0].sandboxName | Should -Be 'Dev2'

                $byAlias = Get-SalesforceSandboxes -Name 'dev1'
                @($byAlias).Count | Should -Be 1
            }
        }

        Context 'New-SalesforceSandbox' {
            BeforeEach {
                Mock Show-SalesforceResult { param($Result) @{ raw = $Result } }
            }

            It 'builds sandbox creation command with options' {
                Mock Invoke-Salesforce { '{"status":0}' }

                $out = New-SalesforceSandbox -SandboxName 'MySandbox' -Alias 'alias' -DefinitionFile 'sandbox-def.json' -LicenseType 'Partial' -WaitMinutes 45 -NoPrompt -NoTrackSource -TargetOrg 'prod'

                $out.raw | Should -Be '{"status":0}'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                    (($Arguments -join '|') -like 'org|create|sandbox|--name|MySandbox*') -and
                    (($Arguments -join '|') -like '*|--alias|alias*') -and
                    (($Arguments -join '|') -like '*|--definition-file|sandbox-def.json*') -and
                    (($Arguments -join '|') -like '*|--license-type|Partial*') -and
                    (($Arguments -join '|') -like '*|--wait|45*') -and
                    (($Arguments -join '|') -like '*|--no-prompt*') -and
                    (($Arguments -join '|') -like '*|--no-track-source*') -and
                    (($Arguments -join '|') -like '*|--target-org|prod*') -and
                    (($Arguments -join '|') -like '*|--json*')
                }
            }
        }

        Context 'Resume-SalesforceSandbox' {
            BeforeEach {
                Mock Show-SalesforceResult { param($Result) @{ ok = $Result } }
            }

            It 'builds resume command and returns parsed result' {
                Mock Invoke-Salesforce { '{"status":0}' }

                $out = Resume-SalesforceSandbox -SandboxName 'MySandbox' -WaitMinutes 30 -TargetOrg 'prod'

                $out.ok | Should -Be '{"status":0}'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                    (($Arguments -join '|') -like 'org|resume|sandbox|--name|MySandbox*') -and
                    (($Arguments -join '|') -like '*|--wait|30*') -and
                    (($Arguments -join '|') -like '*|--target-org|prod*') -and
                    (($Arguments -join '|') -like '*|--json*')
                }
            }
        }

        Context 'Copy-SalesforceSandbox' {
            BeforeEach {
                Mock Show-SalesforceResult { param($Result) @{ ok = $Result } }
            }

            It 'builds clone command with optional parameters' {
                Mock Invoke-Salesforce { '{"status":0}' }

                $out = Copy-SalesforceSandbox -SourceSandboxName 'Dev1' -CloneSandboxName 'Dev1Clone' -LicenseType 'Partial' -Alias 'clone' -WaitMinutes 20 -NoPrompt -TargetOrg 'prod'

                $out.ok | Should -Be '{"status":0}'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                    (($Arguments -join '|') -like 'org|create|sandbox|--source-sandbox-name|Dev1|--name|Dev1Clone*') -and
                    (($Arguments -join '|') -like '*|--license-type|Partial*') -and
                    (($Arguments -join '|') -like '*|--alias|clone*') -and
                    (($Arguments -join '|') -like '*|--wait|20*') -and
                    (($Arguments -join '|') -like '*|--no-prompt*') -and
                    (($Arguments -join '|') -like '*|--target-org|prod*') -and
                    (($Arguments -join '|') -like '*|--json*')
                }
            }

            It 'does not use the removed sf org clone sandbox command or --clone-name flag' {
                Mock Invoke-Salesforce { '{"status":0}' }

                Copy-SalesforceSandbox -SourceSandboxName 'Dev1' -CloneSandboxName 'Dev1Clone' | Out-Null

                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                    ($Arguments -join '|') -eq 'org|create|sandbox|--source-sandbox-name|Dev1|--name|Dev1Clone|--json'
                }
                Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { (($Arguments -join '|') -like '*clone|sandbox*') -or (($Arguments -join '|') -like '*--clone-name*') }
            }
        }

        Context 'Remove-SalesforceSandbox' {
            BeforeEach {
                Mock Show-SalesforceResult { param($Result) @{ ok = $Result } }
            }

            It 'constructs delete command respecting flags' {
                Mock Invoke-Salesforce { '{"status":0}' }

                $out = Remove-SalesforceSandbox -NoPrompt -TargetOrg 'prod'

                $out.ok | Should -Be '{"status":0}'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                    (($Arguments -join '|') -like 'org|delete|sandbox*') -and
                    (($Arguments -join '|') -like '*|--no-prompt*') -and
                    (($Arguments -join '|') -like '*|--target-org|prod*') -and
                    (($Arguments -join '|') -like '*|--json*')
                }
            }
        }

        Context 'Get-SalesforceSandboxRefreshStatus' {
            It 'escapes the sandbox name in the query' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"records":[]}}' }
                Get-SalesforceSandboxRefreshStatus -Name "o'brien\" | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                    ($Arguments[0..5] -join '|') -eq 'data|query|--use-tooling-api|--result-format|json|--query' -and
                    $Arguments[6] -ceq "SELECT SandboxName, LicenseType FROM SandboxInfo WHERE SandboxName = 'o\'brien\\'"
                }
            }
            It 'returns refresh status details with calculated next refresh date' {
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -like '*FROM SandboxInfo*') {
                        return '{"status":0,"result":{"records":[{"SandboxName":"MySandbox","LicenseType":"Partial"}]}}'
                    }
                    if (($Arguments -join '|') -like '*FROM SandboxProcess*') {
                        return '{"status":0,"result":{"records":[{"SandboxName":"MySandbox","StartDate":"2024-01-01T00:00:00.000Z","EndDate":"2024-01-01T12:00:00.000Z"}]}}'
                    }
                    throw "Unexpected command: $($Arguments -join ' ')"
                }

                $status = Get-SalesforceSandboxRefreshStatus -Name 'MySandbox' -TargetOrg 'prod'

                $status | Should -HaveCount 1
                $status[0].LicenseType | Should -Be 'Partial'
                $status[0].LastRefreshed | Should -Be ([datetime]'2024-01-01T12:00:00Z')
                $status[0].NextRefreshDate | Should -Be $status[0].LastRefreshed.AddDays(5)

                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                    (($Arguments -join '|') -like '*FROM SandboxInfo*') -and
                    (($Arguments -join '|') -like '*|--use-tooling-api*') -and
                    (($Arguments -join '|') -like '*|--target-org|prod*')
                }
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                    (($Arguments -join '|') -like '*FROM SandboxProcess*') -and
                    (($Arguments -join '|') -like '*|--use-tooling-api*') -and
                    (($Arguments -join '|') -like '*|--target-org|prod*')
                }
            }

            It 'throws when SandboxInfo query reports an error' {
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -like '*FROM SandboxInfo*') { return '{"status":1,"message":"query failed"}' }
                    throw "Unexpected command: $($Arguments -join ' ')"
                }

                $action = { Get-SalesforceSandboxRefreshStatus -Name 'MySandbox' }
                $action | Should -Throw
                try { & $action } catch { $_.Exception.Message | Should -Be 'query failed' }
            }

            It 'returns empty array when sandbox does not exist' {
                Mock Invoke-Salesforce {
                    if (($Arguments -join '|') -like '*FROM SandboxInfo*') { return '{"status":0,"result":{"records":[]}}' }
                    throw "SandboxProcess query should not run"
                }

                $status = Get-SalesforceSandboxRefreshStatus -Name 'MissingSandbox'
                $status.Count | Should -Be 0
            }
        }
    }
}
