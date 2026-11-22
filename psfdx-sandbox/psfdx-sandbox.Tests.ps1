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

            It 'passes a definition file path with spaces as one argument' {
                Mock Invoke-Salesforce { '{"status":0}' }
                New-SalesforceSandbox -SandboxName 'MySandbox' -DefinitionFile 'my dir/sandbox def.json' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'org|create|sandbox|--name|MySandbox|--definition-file|my dir/sandbox def.json|--license-type|Developer|--json' }
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

                $out = Remove-SalesforceSandbox -Confirm:$false -NoPrompt -TargetOrg 'prod'

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

Describe 'Remove-SalesforceSandbox safety' {
    InModuleScope 'psfdx-sandbox' {
        It 'runs nothing under -WhatIf' {
            Mock Invoke-Salesforce { '{"status":0,"result":{}}' }
            Remove-SalesforceSandbox -TargetOrg 'prod' -WhatIf
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
    }
}

# SOQL builder and `sf data query --json` regression coverage (#172).
# Fixtures are sanitised copies of real `sf data query --json` output shapes: no tokens, no real org data.
Describe 'Get-SalesforceSandboxRefreshStatus SOQL regression' {
    InModuleScope 'psfdx-sandbox' {
        BeforeAll {
            $script:Empty = '{"status":0,"result":{"records":[],"totalSize":0,"done":true},"warnings":[]}'
            $script:Info = '{"status":0,"result":{"records":[{"attributes":{"type":"SandboxInfo"},"SandboxName":"dev1","LicenseType":"Developer"}],"totalSize":1,"done":true},"warnings":[]}'
            $script:Process = '{"status":0,"result":{"records":[{"attributes":{"type":"SandboxProcess"},"SandboxName":"dev1","StartDate":"2026-11-01T09:00:00.000+0000","EndDate":"2026-11-01T09:30:00.000+0000"}],"totalSize":1,"done":true},"warnings":[]}'
            $script:NoAuth = '{"name":"NoAuthFoundError","message":"No authorization information found for nobody@example.com.","exitCode":1,"status":1,"warnings":[]}'
        }

        It 'escapes the sandbox name <Name> in both queries' -ForEach @(
            @{ Name = 'apostrophe'; Value = "dev'1";        Literal = "'dev\'1'" }
            @{ Name = 'backslash';  Value = 'dev\1';        Literal = "'dev\\1'" }
            @{ Name = 'injection';  Value = "x' OR Id != '"; Literal = "'x\' OR Id != \''" }
            @{ Name = 'unicode';    Value = 'dév日本';        Literal = "'dév日本'" }
        ) {
            Mock Invoke-Salesforce { $script:Info } -ParameterFilter { ($Arguments -join '|') -like '*FROM SandboxInfo*' }
            Mock Invoke-Salesforce { $script:Process } -ParameterFilter { ($Arguments -join '|') -like '*FROM SandboxProcess*' }
            Get-SalesforceSandboxRefreshStatus -Name $Value -TargetOrg 'prod' | Out-Null
            $info = "data|query|--use-tooling-api|--result-format|json|--query|SELECT SandboxName, LicenseType FROM SandboxInfo WHERE SandboxName = $Literal|--target-org|prod"
            $proc = "data|query|--use-tooling-api|--result-format|json|--query|SELECT SandboxName, StartDate, EndDate FROM SandboxProcess WHERE SandboxName = $Literal ORDER BY StartDate DESC LIMIT 1|--target-org|prod"
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq $info }
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq $proc }
        }

        It 'refuses a control character and runs nothing' {
            Mock Invoke-Salesforce { $script:Info }
            { Get-SalesforceSandboxRefreshStatus -Name "a$([char]1)b" } | Should -Throw -ExpectedMessage '*control character*'
            Assert-MockCalled Invoke-Salesforce -Times 0
        }

        It 'returns nothing and skips the process query when the sandbox is unknown' {
            Mock Invoke-Salesforce { $script:Empty }
            @(Get-SalesforceSandboxRefreshStatus -Name 'ghost').Count | Should -Be 0
            Assert-MockCalled Invoke-Salesforce -Times 1
        }

        It 'throws the CLI message on an authentication error' {
            Mock Invoke-Salesforce { $script:NoAuth }
            { Get-SalesforceSandboxRefreshStatus -Name 'dev1' -TargetOrg 'nobody@example.com' } | Should -Throw -ExpectedMessage '*No authorization information found for nobody@example.com*'
        }

        It 'parses the ISO 8601 refresh date with the invariant culture' {
            Mock Invoke-Salesforce { $script:Info } -ParameterFilter { ($Arguments -join '|') -like '*FROM SandboxInfo*' }
            Mock Invoke-Salesforce { $script:Process } -ParameterFilter { ($Arguments -join '|') -like '*FROM SandboxProcess*' }
            $old = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
                $r = @(Get-SalesforceSandboxRefreshStatus -Name 'dev1')
            } finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $old
            }
            $r[0].LastRefreshed.Year | Should -Be 2026
            $r[0].LastRefreshed.Month | Should -Be 11
            $r[0].NextRefreshDate.Day | Should -Be ($r[0].LastRefreshed.AddDays(1).Day)
        }
    }
}

Describe 'psfdx-sandbox sf org parity (issue 248)' {
    InModuleScope 'psfdx-sandbox' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
        }

        Context 'New-SalesforceSandbox new flags' {
            It 'passes -Async, -PollIntervalSeconds, -SetDefault and -SourceId' {
                New-SalesforceSandbox -SandboxName dev2 -Async -PollIntervalSeconds 30 -SetDefault -SourceId 0GQ000000000001 -TargetOrg prod | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|create|sandbox|--name|dev2|--license-type|Developer|--async|--poll-interval|30|--set-default|--source-id|0GQ000000000001|--target-org|prod|--json' }
            }
            It 'rejects a poll interval below one second before running sf' {
                { New-SalesforceSandbox -SandboxName dev2 -PollIntervalSeconds 0 } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Copy-SalesforceSandbox new flags' {
            It 'keeps the existing command for -SourceSandboxName' {
                Copy-SalesforceSandbox -SourceSandboxName dev1 -CloneSandboxName dev2 -TargetOrg prod | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|create|sandbox|--source-sandbox-name|dev1|--name|dev2|--target-org|prod|--json' }
            }
            It 'clones by ID and passes the async options' {
                Copy-SalesforceSandbox -SourceId 0GQ000000000001 -CloneSandboxName dev2 -Async -PollIntervalSeconds 15 -SetDefault | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|create|sandbox|--source-id|0GQ000000000001|--name|dev2|--async|--poll-interval|15|--set-default|--json' }
            }
            It 'does not accept both a source name and a source ID' {
                { Copy-SalesforceSandbox -SourceSandboxName dev1 -SourceId 0GQ000000000001 -CloneSandboxName dev2 } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Resume-SalesforceSandbox' {
            It 'keeps resuming by name' {
                Resume-SalesforceSandbox -SandboxName dev2 -WaitMinutes 30 -TargetOrg prod | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|resume|sandbox|--name|dev2|--wait|30|--target-org|prod|--json' }
            }
            It 'resumes by job ID' {
                Resume-SalesforceSandbox -JobId 0GR000000000001 | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|resume|sandbox|--job-id|0GR000000000001|--json' }
            }
            It 'resumes the most recent process' {
                Resume-SalesforceSandbox -UseMostRecent -WaitMinutes 5 | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|resume|sandbox|--use-most-recent|--wait|5|--json' }
            }
            It 'does not accept a name together with a job ID' {
                { Resume-SalesforceSandbox -SandboxName dev2 -JobId 0GR000000000001 } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Update-SalesforceSandbox' {
            It 'builds the refresh command and always passes --no-prompt after confirming' {
                Update-SalesforceSandbox -SandboxName dev1 -SourceSandboxName uat -NoAutoActivate -Async -WaitMinutes 20 -PollIntervalSeconds 10 -TargetOrg prod -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|refresh|sandbox|--name|dev1|--source-sandbox-name|uat|--no-auto-activate|--async|--wait|20|--poll-interval|10|--no-prompt|--target-org|prod|--json' }
            }
            It 'refreshes from a source ID' {
                Update-SalesforceSandbox -SandboxName dev1 -SourceId 0GQ000000000001 -NoPrompt | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|refresh|sandbox|--name|dev1|--source-id|0GQ000000000001|--no-prompt|--json' }
            }
            It 'takes the sandbox from a definition file' {
                $file = Join-Path $TestDrive 'refresh def.json'
                Set-Content -LiteralPath $file -Value '{"sandboxName":"dev1"}'
                Update-SalesforceSandbox -DefinitionFile $file -NoPrompt | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "org|refresh|sandbox|--definition-file|$file|--no-prompt|--json" }
            }
            It 'does nothing with -WhatIf, and -NoPrompt does not turn -WhatIf off' {
                Update-SalesforceSandbox -SandboxName dev1 -WhatIf | Out-Null
                Update-SalesforceSandbox -SandboxName dev1 -NoPrompt -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'needs a sandbox name or a definition file, and rejects both sources' {
                { Update-SalesforceSandbox -Confirm:$false } | Should -Throw -ExpectedMessage '*Specify -SandboxName*'
                { Update-SalesforceSandbox -SandboxName dev1 -SourceSandboxName a -SourceId 0GQ000000000001 -Confirm:$false } | Should -Throw -ExpectedMessage '*not both*'
                { Update-SalesforceSandbox -DefinitionFile (Join-Path $TestDrive 'missing.json') -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'reports a CLI failure' {
                Mock Invoke-Salesforce { '{"status":1,"message":"The sandbox is not refreshable."}' }
                { Update-SalesforceSandbox -SandboxName dev1 -Confirm:$false } | Should -Throw -ExpectedMessage '*not refreshable*'
            }
            It 'is exported and asks for confirmation by default' {
                (Get-Module psfdx-sandbox).ExportedFunctions.Keys | Should -Contain 'Update-SalesforceSandbox'
                (Get-Command Update-SalesforceSandbox).Parameters.ContainsKey('WhatIf') | Should -BeTrue
            }
        }
    }
}
