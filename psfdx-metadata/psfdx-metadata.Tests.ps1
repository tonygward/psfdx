# Import module at discovery time so InModuleScope can find it
$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-metadata.psd1'
Import-Module $moduleManifest -Force | Out-Null

Describe 'Retrieve-SalesforceOrg' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach { Mock Invoke-Salesforce {} }
        It 'creates manifest from org and retrieves via manifest' {
            Retrieve-SalesforceOrg -TargetOrg 'user' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Arguments -like 'force source manifest create --from-org user*' }
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Arguments -like 'project retrieve start --target-org user*' }
        }
    }
}

Describe 'Retrieve-SalesforceComponent' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach { Mock Invoke-Salesforce {} }
        It 'retrieves a named ApexClass for target org' {
            Retrieve-SalesforceComponent -Type ApexClass -Name 'MyClass' -TargetOrg 'me' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Arguments -eq 'project retrieve start --metadata ApexClass:MyClass --target-org me' }
        }
    }
}

Describe 'Get-SalesforceApexClass' {
    InModuleScope 'psfdx-metadata' {
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
