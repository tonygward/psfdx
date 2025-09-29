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

        Context 'Install-SalesforceCli' {
            It 'runs npm global install for the CLI' {
                Mock Invoke-Salesforce {} -ModuleName $module.Name
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
                $rows.Count | Should -Be 1
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
                $rows.Count | Should -Be 1
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
    }
}
