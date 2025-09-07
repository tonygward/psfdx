# Import module at discovery time so InModuleScope can find it
$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-packages.psd1'
Import-Module $moduleManifest -Force | Out-Null

Describe 'New-SalesforcePackage' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Sf { '{"status":0,"result":{"Id":"0Ho000000000001"}}' }
            Mock Show-SfResult { param($Result) return @{ Id = '0Ho000000000001' } }
        }
        It 'uses target-dev-hub and returns package id' {
            $id = New-SalesforcePackage -Name 'MyPkg' -DevHubUsername 'devhub' -PackageType Managed
            $id | Should -Be '0Ho000000000001'
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { $Command -like 'sf package create * --target-dev-hub devhub*' }
        }
    }
}

Describe 'New-SalesforcePackageVersion' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Sf { '{"status":0,"result":{"id":"04t000000000001"}}' }
            Mock Show-SfResult { @{ id = '04t000000000001' } }
        }
        It 'includes target-dev-hub and json' {
            $out = New-SalesforcePackageVersion -PackageId '0Ho000000000001' -DevHubUsername 'devhub' -WaitMinutes 10
            $out.id | Should -Be '04t000000000001'
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { ($Command -like 'sf package version create *') -and ($Command -like '* --target-dev-hub devhub*') -and ($Command -like '* --json') }
        }
    }
}

Describe 'Install-SalesforcePackageVersion' {
    InModuleScope 'psfdx-packages' {
        BeforeEach { Mock Invoke-Sf {} }
        It 'targets org and sets waits' {
            Install-SalesforcePackageVersion -PackageVersionId '04t...' -TargetOrg 'me' -WaitMinutes 5 -NoPrompt | Out-Null
            Assert-MockCalled Invoke-Sf -Times 1 -ParameterFilter { ($Command -like 'sf package install *') -and ($Command -like '* --target-org me*') -and ($Command -like '* --wait 5*') -and ($Command -like '* --publish-wait 5*') -and ($Command -like '* --no-prompt*') }
        }
    }
}
