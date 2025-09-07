<#
Pester unit tests for psfdx module

Run with:

pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path . -CI"
#>

$here = Split-Path -Parent $PSCommandPath
$moduleManifest = Join-Path $here '..' 'psfdx.psd1'
$module = Import-Module $moduleManifest -Force -PassThru

Describe 'psfdx module' {
    Context 'Get-SalesforceDateTime' {
        It 'formats in sortable UTC with Z suffix' {
            $dt = Get-Date '2020-01-02T03:04:05Z'
            $out = Get-SalesforceDateTime -Datetime $dt
            $out | Should -Be '2020-01-02T03:04:05Z'
        }
    }

    InModuleScope $module.Name {
        Context 'Alias commands' {
            It 'sets alias using equals syntax' {
                Mock Invoke-Sf {} -ModuleName $module.Name
                Add-SalesforceAlias -Alias 'my' -TargetOrg 'user@example.com'
                Assert-MockCalled Invoke-Sf -Times 1 -ModuleName $module.Name -ParameterFilter { $Arguments -eq 'alias set my=user@example.com' }
            }

            It 'unsets alias without stray leading space' {
                Mock Invoke-Sf {} -ModuleName $module.Name
                Remove-SalesforceAlias -Alias 'my'
                Assert-MockCalled Invoke-Sf -Times 1 -ModuleName $module.Name -ParameterFilter { $Arguments -eq 'alias unset my' }
            }
        }

        Context 'Connect-Salesforce' {
            It 'includes --set-default-dev-hub when requested' {
                Mock Invoke-Sf { '{"status":0,"result":{}}' } -ModuleName $module.Name
                Connect-Salesforce -SetDefaultDevHub
                Assert-MockCalled Invoke-Sf -Times 1 -ModuleName $module.Name -ParameterFilter { $Arguments -like '* --set-default-dev-hub*' }
            }
        }

        Context 'Connect-SalesforceJwt' {
            BeforeAll {
                Mock Test-Path { $true }
            }

            It 'uses login URL for production' {
                Mock Invoke-Sf { '{"status":0,"result":{}}' }
                Connect-SalesforceJwt -ConsumerKey 'ck' -TargetOrg 'u' -JwtKeyfile 'key.pem'
                Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { $Arguments -like '* --instance-url https://login.salesforce.com*' }
            }

            It 'uses test URL for sandbox' {
                Mock Invoke-Sf { '{"status":0,"result":{}}' }
                Connect-SalesforceJwt -ConsumerKey 'ck' -TargetOrg 'u' -JwtKeyfile 'key.pem' -Sandbox
                Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { $Arguments -like '* --instance-url https://test.salesforce.com*' }
            }
        }

        Context 'Select-SalesforceObjects' {
            It 'returns records from successful JSON result' {
                $json = @'
{"status":0,"result":{"records":[{"Id":"001xx0000000001"}]}}
'@
                Mock Invoke-Sf { $json } -ModuleName $module.Name
                $rows = Select-SalesforceObjects -Query 'SELECT Id FROM Account LIMIT 1' -TargetOrg 'me'
                $rows.Count | Should -Be 1
                $rows[0].Id | Should -Be '001xx0000000001'
            }
        }

        Context 'Object CRUD helpers' {
            It 'returns parsed result for New-SalesforceObject' {
                $json = @'
{"status":0,"result":{"id":"001xx0000000001"}}
'@
                Mock Invoke-Sf { $json } -ModuleName $module.Name
                $res = New-SalesforceObject -Type Account -FieldUpdates 'Name=Acme' -TargetOrg me
                $res.id | Should -Be '001xx0000000001'
            }

            It 'returns parsed result for Set-SalesforceObject' {
                $json = @'
{"status":0,"result":{"success":true}}
'@
                Mock Invoke-Sf { $json } -ModuleName $module.Name
                $res = Set-SalesforceObject -Id '001xx0000000001' -Type Account -FieldUpdates 'Name=Updated' -TargetOrg me
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
