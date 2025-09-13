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
    }
}
