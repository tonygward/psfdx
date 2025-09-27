# Ensure clean slate and load local dependency module first
Get-Module -Name 'psfdx-development','psfdx-metadata' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

# Import local psfdx-metadata so RequiredModules resolves from repo
$metadataManifest = Join-Path -Path $PSScriptRoot -ChildPath '..\psfdx-metadata\psfdx-metadata.psd1'
Import-Module $metadataManifest -Force | Out-Null

# Import module under test so InModuleScope can find it
$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-development.psd1'
Import-Module $moduleManifest -Force | Out-Null

Describe 'psfdx-development basics' {
    InModuleScope 'psfdx-development' {
        BeforeEach {
            Mock Invoke-Salesforce {
                param($Command)
                switch -Regex ($Command) {
                    'sf config get target-dev-hub' {
                        return '{"status":0,"result":{"target-dev-hub":[{"name":"target-dev-hub","value":"DevHub"}]}}'
                    }
                    Default {
                        return '{"status":0,"result":{"successes":[{"name":"target-config"}]}}'
                    }
                }
            }
        }
        It 'starts LWC dev server with sf command' {
            Start-SalesforceLwcDevServer | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf lightning lwc start' }
        }
        It 'sets project target org with equals syntax' {
            Set-SalesforceTargetOrg -Value 'user@example' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config set target-org=user@example --json' }
        }
        It 'removes project target org' {
            Remove-SalesforceTargetOrg | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config unset target-org --json' }
        }
        It 'removes project target org globally' {
            Remove-SalesforceTargetOrg -Global | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config unset target-org --global --json' }
        }
        It 'sets default dev hub with equals syntax' {
            Set-SalesforceTargetDevHub -Value 'DevHubAlias' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config set target-dev-hub=DevHubAlias --json' }
        }
        It 'sets default dev hub globally' {
            Set-SalesforceTargetDevHub -Value 'DevHubAlias' -Global | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config set target-dev-hub=DevHubAlias --global --json' }
        }
        It 'gets default dev hub' {
            Get-SalesforceTargetDevHub | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config get target-dev-hub --json' }
        }
        It 'gets default dev hub globally' {
            Get-SalesforceTargetDevHub -Global | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config get target-dev-hub --global --json' }
        }
        It 'removes default dev hub' {
            Remove-SalesforceTargetDevHub | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config unset target-dev-hub --json' }
        }
        It 'removes default dev hub globally' {
            Remove-SalesforceTargetDevHub -Global | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config unset target-dev-hub --global --json' }
        }
    }
}

Describe 'Test-SalesforceApex command building' {
    InModuleScope 'psfdx-development' {
        BeforeEach { Mock Invoke-Salesforce { '{"status":0,"result":{"tests":[],"summary":{"outcome":"Passed","testRunCoverage":"100%"}}}' } }
        It 'runs specified class synchronously with target org and json' {
            Test-SalesforceApex -ClassName 'MyClass' -TargetOrg 'me' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -like 'sf apex run test *') -and ($Command -like '* --class-names MyClass*') -and ($Command -like '* --target-org me*') -and ($Command -like '* --result-format json*') }
        }
    }
}

Describe 'Get-SalesforceApexClass' {
    InModuleScope 'psfdx-development' {
        BeforeEach {
            $json = '{"status":0,"result":{"records":[{"Id":"01pxx0000000001AAA","Name":"MyClass"}]}}'
            Mock Invoke-Salesforce { $json }
        }
        It 'returns first record by name' {
            $rec = Get-SalesforceApexClass -Name 'MyClass' -TargetOrg 'me'
            $rec.Id   | Should -Be '01pxx0000000001AAA'
            $rec.Name | Should -Be 'MyClass'
        }
    }
}
