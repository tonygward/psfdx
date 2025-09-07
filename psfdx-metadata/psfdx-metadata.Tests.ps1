BeforeAll {
    $moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-metadata.psd1'
    $script:module = Import-Module $moduleManifest -Force -PassThru
    $script:moduleName = $script:module.Name
}

Describe 'Retrieve-SalesforceOrg' {
    BeforeEach {
        Mock -ModuleName $script:moduleName Invoke-Sf {}
    }

    It 'creates manifest from org and retrieves via manifest' {
        Retrieve-SalesforceOrg -TargetOrg 'user' | Out-Null
        Assert-MockCalled -ModuleName $script:moduleName Invoke-Sf -Times 1 -ParameterFilter { $Command -like 'sf force source manifest create --from-org user*' }
        Assert-MockCalled -ModuleName $script:moduleName Invoke-Sf -Times 1 -ParameterFilter { $Command -like 'sf project retrieve start --target-org user*' }
    }
}

Describe 'Retrieve-SalesforceComponent' {
    BeforeEach { Mock -ModuleName $script:moduleName Invoke-Sf {} }

    It 'retrieves a named ApexClass for target org' {
        Retrieve-SalesforceComponent -Type ApexClass -Name 'MyClass' -TargetOrg 'me' | Out-Null
        Assert-MockCalled -ModuleName $script:moduleName Invoke-Sf -Times 1 -ParameterFilter { $Command -eq 'sf project retrieve start --metadata ApexClass:MyClass --target-org me' }
    }
}

Describe 'Describe-SalesforceObjects' {
    BeforeEach {
        Mock -ModuleName $script:moduleName Invoke-Sf { '{"status":0,"result":[{"xmlName":"ApexClass"}]}' }
        Mock -ModuleName $script:moduleName Show-SfResult { return @('Account','Contact') }
    }

    It 'passes category and returns Show-SfResult output' {
        $out = Describe-SalesforceObjects -TargetOrg 'me' -ObjectTypeCategory all
        $out | Should -Contain 'Account'
        Assert-MockCalled -ModuleName $script:moduleName Invoke-Sf -Times 1 -ParameterFilter { $Command -like 'sf sobject list * --category all*' }
    }
}

Describe 'Get-SalesforceApexClass' {
    BeforeEach {
        $json = '{"status":0,"result":{"records":[{"Id":"01pxx0000000001AAA","Name":"MyClass"}]}}'
        Mock -ModuleName $script:moduleName Invoke-Sf { $json }
    }

    It 'returns first record by name' {
        $rec = Get-SalesforceApexClass -Name 'MyClass' -TargetOrg 'me'
        $rec.Id   | Should -Be '01pxx0000000001AAA'
        $rec.Name | Should -Be 'MyClass'
    }
}
