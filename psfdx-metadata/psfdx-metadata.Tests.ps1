BeforeAll {
    $moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-metadata.psd1'
    $script:module = Import-Module $moduleManifest -Force -PassThru
    $script:moduleName = $script:module.Name
}

Describe 'Retrieve-SalesforceOrg' {
    InModuleScope $script:moduleName {
        BeforeEach { Mock Invoke-Sf {} }
        It 'creates manifest from org and retrieves via manifest' {
            Retrieve-SalesforceOrg -TargetOrg 'user' | Out-Null
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { $Command -like 'sf force source manifest create --from-org user*' }
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { $Command -like 'sf project retrieve start --target-org user*' }
        }
    }
}

Describe 'Retrieve-SalesforceComponent' {
    InModuleScope $script:moduleName {
        BeforeEach { Mock Invoke-Sf {} }
        It 'retrieves a named ApexClass for target org' {
            Retrieve-SalesforceComponent -Type ApexClass -Name 'MyClass' -TargetOrg 'me' | Out-Null
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { $Command -eq 'sf project retrieve start --metadata ApexClass:MyClass --target-org me' }
        }
    }
}

Describe 'Describe-SalesforceObjects' {
    InModuleScope $script:moduleName {
        BeforeEach {
            Mock Invoke-Sf { '{"status":0,"result":[{"xmlName":"ApexClass"}]}' }
            Mock Show-SfResult { return @('Account','Contact') }
        }
        It 'passes category and returns Show-SfResult output' {
            $out = Describe-SalesforceObjects -TargetOrg 'me' -ObjectTypeCategory all
            $out | Should -Contain 'Account'
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { $Command -like 'sf sobject list * --category all*' }
        }
    }
}

Describe 'Get-SalesforceApexClass' {
    InModuleScope $script:moduleName {
        BeforeEach {
            $json = '{"status":0,"result":{"records":[{"Id":"01pxx0000000001AAA","Name":"MyClass"}]}}'
            Mock Invoke-Sf { $json }
        }
        It 'returns first record by name' {
            $rec = Get-SalesforceApexClass -Name 'MyClass' -TargetOrg 'me'
            $rec.Id   | Should -Be '01pxx0000000001AAA'
            $rec.Name | Should -Be 'MyClass'
        }
    }
}
