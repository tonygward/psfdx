BeforeAll {
    $moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-development.psd1'
    Import-Module $moduleManifest -Force
}

Describe 'psfdx-development basics' {
    BeforeEach {
        Mock -ModuleName 'psfdx-development' Invoke-Sf {}
    }

    It 'starts LWC dev server with sf command' {
        Start-SalesforceLwcDevServer | Out-Null
        Assert-MockCalled -ModuleName 'psfdx-development' Invoke-Sf -Times 1 -ParameterFilter { $Command -eq 'sf lightning lwc start' }
    }

    It 'sets project user with equals syntax' {
        Set-SalesforceProjectUser -TargetOrg 'user@example' | Out-Null
        Assert-MockCalled -ModuleName 'psfdx-development' Invoke-Sf -Times 1 -ParameterFilter { $Command -eq 'sf config set target-org=user@example' }
    }
}

Describe 'Test-Salesforce command building' {
    BeforeEach {
        Mock -ModuleName 'psfdx-development' Invoke-Sf { '{"status":0,"result":{"tests":[],"summary":{"outcome":"Passed","testRunCoverage":"100%"}}}' }
    }

    It 'runs specified class synchronously with target org and json' {
        Test-Salesforce -ClassName 'MyClass' -TargetOrg 'me' | Out-Null
        Assert-MockCalled -ModuleName 'psfdx-development' Invoke-Sf -Times 1 -ParameterFilter { ($Command -like 'sf apex run test *') -and ($Command -like '* --class-names MyClass*') -and ($Command -like '* --target-org me*') -and ($Command -like '* --result-format json*') }
    }
}

