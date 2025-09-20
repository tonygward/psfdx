# Ensure no other instances of psfdx-metadata are loaded (e.g., from PSModulePath)
Get-Module -Name 'psfdx-metadata' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

# Import module at discovery time so InModuleScope can find it
$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-metadata.psd1'
Import-Module $moduleManifest -Force | Out-Null

Describe 'Retrieve-SalesforceOrg' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach { Mock Invoke-Salesforce {} }
        It 'creates manifest from org and retrieves via manifest' {
            Retrieve-SalesforceOrg -TargetOrg 'user' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -like 'sf force source manifest create --from-org user*' }
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -like 'sf project retrieve start --target-org user*' }
        }
    }
}

Describe 'Retrieve-SalesforceComponent' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach { Mock Invoke-Salesforce {} }
        It 'retrieves a named ApexClass for target org' {
            Retrieve-SalesforceComponent -Type ApexClass -Name 'MyClass' -TargetOrg 'me' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project retrieve start --metadata ApexClass:MyClass --target-org me' }
        }
        It 'requires Name when child name specified' {
            { Retrieve-SalesforceComponent -Type Flow -ChildName 'Version1' -TargetOrg 'me' } | Should -Throw
        }
        It 'retrieves a child component when provided' {
            Retrieve-SalesforceComponent -Type Flow -Name 'MyFlow' -ChildName 'Version1' -TargetOrg 'me' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project retrieve start --metadata Flow:MyFlow.Version1 --target-org me' }
        }
        It 'adds ignore conflicts when requested' {
            Retrieve-SalesforceComponent -Type ApexClass -Name 'MyClass' -TargetOrg 'me' -IgnoreConflicts | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project retrieve start --metadata ApexClass:MyClass --target-org me --ignore-conflicts' }
        }
    }
}

Describe 'Retrieve-SalesforceField' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach { Mock Invoke-Salesforce {} }
        It 'builds custom field retrieve command' {
            Retrieve-SalesforceField -ObjectName 'Account' -FieldName 'MyField__c' -TargetOrg 'me'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Command -eq 'sf project retrieve start --metadata CustomField:Account.MyField__c --target-org me')
            }
        }
    }
}

Describe 'Retrieve-SalesforceValidationRule' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach { Mock Invoke-Salesforce {} }
        It 'builds validation rule retrieve command' {
            Retrieve-SalesforceValidationRule -ObjectName 'Account' -RuleName 'MyRule' -TargetOrg 'me'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Command -eq 'sf project retrieve start --metadata ValidationRule:Account.MyRule --target-org me')
            }
        }
    }
}
