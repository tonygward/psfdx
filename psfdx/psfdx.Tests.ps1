<#
Pester unit tests for psfdx module

Run with:

pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path . -CI"
#>

$here = $PSScriptRoot
$moduleManifest = Join-Path $here 'psfdx.psd1'

# Ensure no duplicate 'psfdx' modules are loaded before importing this test instance
Get-Module -Name 'psfdx' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

$module = Import-Module $moduleManifest -Force -PassThru

Describe 'psfdx module' {
    Context 'Get-SalesforceDateTime' {
        It 'formats in sortable UTC with Z suffix' {
            $dt = Get-Date '2020-01-02T03:04:05Z'
            $out = Get-SalesforceDateTime -Datetime $dt
            $out | Should -Be '2020-01-02T03:04:05Z'
        }
    }

    InModuleScope $module {
        Context 'Alias commands' {
            It 'sets alias using equals syntax' {
                Mock Invoke-Salesforce {} -ModuleName $module.Name
                Add-SalesforceAlias -Alias 'my' -TargetOrg 'user@example.com'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter { $Command -eq 'sf alias set my=user@example.com' }
            }

            It 'unsets alias without stray leading space' {
                Mock Invoke-Salesforce {} -ModuleName $module.Name
                Remove-SalesforceAlias -Alias 'my'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter { $Command -eq 'sf alias unset my' }
            }
        }

        Context 'Connect-Salesforce' {
            It 'includes --set-default-dev-hub when requested' {
                Mock Invoke-Salesforce { '{"status":0,"result":{}}' } -ModuleName $module.Name
                Connect-Salesforce -SetDefaultDevHub
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter { $Command -like 'sf * --set-default-dev-hub*' }
            }
        }

        Context 'Connect-SalesforceAuthUrl' {
            It 'throws when the SFDX URL file does not exist' {
                Mock Test-Path { $false }
                { Connect-SalesforceAuthUrl -SfdxUrlFile 'missing.txt' } | Should -Throw -ExpectedMessage 'File does not exist: missing.txt'
            }

            It 'stores authentication using the provided URL file and options' {
                Mock Test-Path { $true }
                Mock Invoke-Salesforce { '{"status":0,"result":{}}' } -ModuleName $module.Name
                Mock Show-SalesforceResult { [pscustomobject]@{ alias = 'my'; username = 'user'; accessToken = 'tok'; refreshToken = 'ref' } } -ModuleName $module.Name
                $result = Connect-SalesforceAuthUrl -SfdxUrlFile './auth.txt' -Alias 'my' -SetDefault -SetDefaultDevHub
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter {
                    $Command -eq 'sf org login sfdx-url --sfdx-url-file "./auth.txt" --alias my --set-default --set-default-dev-hub --json'
                }
                $result.PSObject.Properties.Match('accessToken').Count | Should -Be 0
                $result.PSObject.Properties.Match('refreshToken').Count | Should -Be 0
                $result.alias | Should -Be 'my'
            }

            It 'returns tokens when IncludeToken is specified' {
                Mock Test-Path { $true }
                Mock Invoke-Salesforce { '{"status":0,"result":{}}' } -ModuleName $module.Name
                Mock Show-SalesforceResult { [pscustomobject]@{ alias = 'my'; accessToken = 'tok'; refreshToken = 'ref' } } -ModuleName $module.Name
                $result = Connect-SalesforceAuthUrl -SfdxUrlFile './auth.txt' -IncludeToken
                $result.PSObject.Properties.Match('accessToken').Count | Should -Be 1
                $result.PSObject.Properties.Match('refreshToken').Count | Should -Be 1
            }
        }

        Context 'Auth response shapes' {
            BeforeAll {
                Mock Test-Path { $true }
            }

            It 'handles a CLI response with no token or auth URL fields (new shape)' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"username":"u@example.com","orgId":"00D000000000001","instanceUrl":"https://x.my.salesforce.com"}}' } -ModuleName $module.Name
                $result = Connect-SalesforceAuthUrl -SfdxUrlFile './auth.txt'
                $result.username | Should -Be 'u@example.com'
                $result.PSObject.Properties.Match('accessToken').Count | Should -Be 0
            }

            It 'strips tokens and auth URLs from the real result handling by default (old shape)' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"username":"u@example.com","accessToken":"00Dtok","refreshToken":"5Aref","sfdxAuthUrl":"force://PlatformCLI::x@y.com"}}' } -ModuleName $module.Name
                $result = Connect-SalesforceAuthUrl -SfdxUrlFile './auth.txt'
                $result.username | Should -Be 'u@example.com'
                $result.PSObject.Properties.Match('accessToken').Count | Should -Be 0
                $result.PSObject.Properties.Match('refreshToken').Count | Should -Be 0
                $result.PSObject.Properties.Match('sfdxAuthUrl').Count | Should -Be 0
            }

            It 'IncludeToken passes through only what the CLI returned' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"username":"u@example.com"}}' } -ModuleName $module.Name
                $result = Connect-SalesforceAuthUrl -SfdxUrlFile './auth.txt' -IncludeToken
                $result.PSObject.Properties.Match('accessToken').Count | Should -Be 0
            }

            It 'does not leak secrets in the exception text on failure' {
                Mock Invoke-Salesforce { '{"status":1,"message":"Invalid auth URL","result":{"accessToken":"00Dleak"}}' } -ModuleName $module.Name
                $caught = $null
                try { Connect-SalesforceAuthUrl -SfdxUrlFile './auth.txt' } catch { $caught = $_.Exception.Message }
                $caught | Should -Be 'Invalid auth URL'
                $caught | Should -Not -Match '00Dleak'
            }

            It 'strips tokens from Connect-SalesforceJwt output' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"username":"u","accessToken":"00Dtok"}}' } -ModuleName $module.Name
                $result = Connect-SalesforceJwt -ConsumerKey 'ck' -TargetOrg 'u' -JwtKeyfile 'key.pem'
                $result.username | Should -Be 'u'
                $result.PSObject.Properties.Match('accessToken').Count | Should -Be 0
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter {
                    $Command -eq 'sf org login jwt --client-id ck --username u --jwt-key-file "key.pem" --instance-url https://login.salesforce.com --json'
                }
            }

            It 'Get-SalesforceConnections returns only safe fields from nonScratchOrgs' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"nonScratchOrgs":[{"orgId":"00D1","instanceUrl":"https://a","username":"a@x.com","alias":"a","accessToken":"00Dtok","connectedStatus":"Connected"}],"scratchOrgs":[]}}' } -ModuleName $module.Name
                $rows = @(Get-SalesforceConnections)
                $rows.Count | Should -Be 1
                $rows[0].username | Should -Be 'a@x.com'
                $rows[0].PSObject.Properties.Match('accessToken').Count | Should -Be 0
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter { $Command -eq 'sf org list --json' }
            }

            It 'Get-SalesforceConnections falls back to grouped orgs when nonScratchOrgs is absent' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"devHubs":[{"orgId":"00D1","username":"hub@x.com"}],"sandboxes":[{"orgId":"00D2","username":"sb@x.com"}],"other":[],"scratchOrgs":[{"orgId":"00D3","username":"s@x.com"}]}}' } -ModuleName $module.Name
                $rows = @(Get-SalesforceConnections)
                $rows.Count | Should -Be 2
                $rows[1].username | Should -Be 'sb@x.com'
            }

            It 'Get-SalesforceConnections returns nothing when no org groups are present' {
                Mock Invoke-Salesforce { '{"status":0,"result":{}}' } -ModuleName $module.Name
                @(Get-SalesforceConnections).Count | Should -Be 0
            }

            It 'Get-SalesforceConnections throws the CLI message on failure' {
                Mock Invoke-Salesforce { '{"status":1,"message":"boom"}' } -ModuleName $module.Name
                { Get-SalesforceConnections } | Should -Throw -ExpectedMessage 'boom'
            }
        }

        Context 'Install-SalesforceCli' {
            It 'uses npm on macOS' {
                Mock Invoke-Salesforce {} -ModuleName $module.Name
                Mock Test-SalesforceIsMacOS { $true } -ModuleName $module.Name
                Install-SalesforceCli
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter { $Command -eq 'npm install --global @salesforce/cli' }
            }

            It 'updates with npm on macOS' {
                Mock Invoke-Salesforce {} -ModuleName $module.Name
                Mock Test-SalesforceIsMacOS { $true } -ModuleName $module.Name
                Update-SalesforceCli
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter { $Command -eq 'npm update --global @salesforce/cli' }
            }

            It 'uses npm elsewhere' {
                Mock Invoke-Salesforce {} -ModuleName $module.Name
                Mock Test-SalesforceIsMacOS { $false } -ModuleName $module.Name
                Install-SalesforceCli
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter { $Command -eq 'npm install --global @salesforce/cli' }
            }
        }

        Context 'Connect-SalesforceJwt' {
            BeforeAll {
                Mock Test-Path { $true }
            }

            It 'uses login URL for production' {
                Mock Invoke-Salesforce { '{"status":0,"result":{}}' }
                Connect-SalesforceJwt -ConsumerKey 'ck' -TargetOrg 'u' -JwtKeyfile 'key.pem'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -like 'sf * --instance-url https://login.salesforce.com*' }
            }

            It 'uses test URL for sandbox' {
                Mock Invoke-Salesforce { '{"status":0,"result":{}}' }
                Connect-SalesforceJwt -ConsumerKey 'ck' -TargetOrg 'u' -JwtKeyfile 'key.pem' -Sandbox
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -like 'sf * --instance-url https://test.salesforce.com*' }
            }
        }

        Context 'Select-SalesforceRecords' {
            It 'returns records from successful JSON result' {
                $json = @'
{"status":0,"result":{"records":[{"Id":"001xx0000000001"}]}}
'@
                Mock Invoke-Salesforce { $json } -ModuleName $module.Name
                $rows = Select-SalesforceRecords -Query 'SELECT Id FROM Account LIMIT 1' -TargetOrg 'me'
                @($rows).Count | Should -Be 1
                $rows[0].Id | Should -Be '001xx0000000001'
            }
        }

        Context 'Get-SalesforceUsers' {
            It 'builds SOQL with filters and returns users' {
                $json = @'
{"status":0,"result":{"records":[{"Id":"005xx0000000001","Username":"user@example.com","IsActive":true}]}}
'@
                Mock Invoke-Salesforce { $json } -ModuleName $module.Name
                $rows = Get-SalesforceUsers -Username 'user@example.com' -ActiveOnly -Limit 5 -TargetOrg 'me'
                @($rows).Count | Should -Be 1
                $rows[0].Id | Should -Be '005xx0000000001'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter {
                    ($Command -like 'sf data query --query *FROM User*') -and
                    ($Command -like "*Username = 'user@example.com'*") -and
                    ($Command -like '*IsActive = true*') -and
                    ($Command -like '* ORDER BY LastLoginDate DESC*') -and
                    ($Command -like '* LIMIT 5*') -and
                    ($Command -like '* --target-org me*') -and
                    ($Command -like '* --result-format json*')
                }
            }
        }

        Context 'Object CRUD helpers' {
            It 'returns parsed result for New-SalesforceRecord' {
                $json = @'
{"status":0,"result":{"id":"001xx0000000001"}}
'@
                Mock Invoke-Salesforce { $json } -ModuleName $module.Name
                $res = New-SalesforceRecord -Type Account -FieldUpdates 'Name=Acme' -TargetOrg me
                $res.id | Should -Be '001xx0000000001'
            }

            It 'returns parsed result for Set-SalesforceRecord' {
                $json = @'
{"status":0,"result":{"success":true}}
'@
                Mock Invoke-Salesforce { $json } -ModuleName $module.Name
                $res = Set-SalesforceRecord -Id '001xx0000000001' -Type Account -FieldUpdates 'Name=Updated' -TargetOrg me
                $res.success | Should -BeTrue
            }
        }

        Context 'Invoke-SalesforceApi' {
            It 'uses Bearer token auth header' {
                Mock Invoke-RestMethod { @{ ok = $true } } -ParameterFilter { $Headers.Authorization -like 'Bearer *' }
                $out = Invoke-SalesforceApi -Url 'https://example.com' -AccessToken 'abc'
                $out.ok | Should -BeTrue
            }
        }

        Context 'Select-SalesforceRecords non-JSON result formats' {
            It 'returns csv output untouched instead of parsing it as JSON' {
                Mock Invoke-Salesforce { "Id,Name`n001,Acme" } -ModuleName $module.Name
                $out = Select-SalesforceRecords -Query 'SELECT Id FROM Account' -ResultFormat csv
                $out | Should -Match 'Acme'
            }

            It 'returns human output untouched instead of parsing it as JSON' {
                Mock Invoke-Salesforce { "ID   NAME`n001  Acme" } -ModuleName $module.Name
                $out = Select-SalesforceRecords -Query 'SELECT Id FROM Account' -ResultFormat human
                $out | Should -Match 'Acme'
            }

            It 'throws on a failed json result without first emitting the raw payload' {
                Mock Invoke-Salesforce { '{"status":1,"message":"MALFORMED_QUERY"}' } -ModuleName $module.Name
                $emitted = @()
                try { $emitted = @(Select-SalesforceRecords -Query 'bad' -ErrorAction Stop) } catch { }
                $emitted.Count | Should -Be 0
            }
        }

        Context 'Get-SalesforceLatestApiVersion' {
            It 'compares versions numerically, not as strings' {
                Mock Get-SalesforceApiVersions {
                    @(
                        [pscustomobject]@{ version = '99.0' },
                        [pscustomobject]@{ version = '100.0' },
                        [pscustomobject]@{ version = '64.0' }
                    )
                } -ModuleName $module.Name
                Get-SalesforceLatestApiVersion | Should -Be 'v100.0'
            }

            It 'returns null when no versions are reported' {
                Mock Get-SalesforceApiVersions { @() } -ModuleName $module.Name
                Get-SalesforceLatestApiVersion | Should -BeNullOrEmpty
            }
        }

        Context 'Limit helpers with unusable data' {
            It 'returns null when the DataStorageMB row is absent' {
                Mock Get-SalesforceLimits { @([pscustomobject]@{ Name = 'Other'; max = 10; remaining = 5 }) } -ModuleName $module.Name
                Get-SalesforceDataStorage | Should -BeNullOrEmpty
            }

            It 'does not divide by zero when max is 0' {
                Mock Get-SalesforceLimits { @([pscustomobject]@{ Name = 'DailyApiRequests'; max = 0; remaining = 0 }) } -ModuleName $module.Name
                { Get-SalesforceApiUsage -ErrorAction Stop } | Should -Not -Throw
            }
        }
    }
}

Describe 'Get-SalesforceAlias' {
    It 'declares a Param block so common parameters are honoured' {
        # Without Param(), [CmdletBinding()] is inert and -Verbose is silently swallowed
        (Get-Command Get-SalesforceAlias).Parameters.Keys | Should -Contain 'Verbose'
    }
}

Describe 'Invoke-Salesforce' {
    # Resolved inside the module scope: psfdx-shared is imported there, not into the session
    InModuleScope 'psfdx' {
        It 'does not declare SupportsShouldProcess' {
            # Suppressing the call would return $null into Show-SalesforceResult -Result,
            # which is Mandatory, breaking every cmdlet under -WhatIf.
            $command = Get-Command Invoke-Salesforce -ErrorAction Stop
            $binding = @($command.ScriptBlock.Attributes | Where-Object { $_ -is [CmdletBinding] })
            $binding.Count | Should -Be 1 -Because 'the CmdletBinding attribute must be present to assert against'
            $binding[0].SupportsShouldProcess | Should -BeFalse
        }

        It 'still runs every cmdlet when $WhatIfPreference is set' {
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
            $WhatIfPreference = $true
            try {
                { Connect-Salesforce -Alias 'foo' -ErrorAction Stop } | Should -Not -Throw
            } finally {
                $WhatIfPreference = $false
            }
        }
    }
}
