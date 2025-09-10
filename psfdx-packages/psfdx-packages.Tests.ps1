# Import module at discovery time so InModuleScope can find it
$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-packages.psd1'
Import-Module $moduleManifest -Force | Out-Null

Describe 'New-SalesforcePackage' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"Id":"0Ho000000000001"}}' }
            Mock Show-SalesforceResult { param($Result) return @{ Id = '0Ho000000000001' } }
        }
        It 'uses target-dev-hub and returns package id' {
            $id = New-SalesforcePackage -Name 'MyPkg' -DevHubUsername 'devhub' -PackageType Managed
            $id | Should -Be '0Ho000000000001'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                $cmd = if ($Command) { $Command } else { "sf $Arguments" }
                $cmd -like 'sf package create * --target-dev-hub devhub*'
            }
        }
    }
}

Describe 'New-SalesforcePackageVersion' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"id":"04t000000000001"}}' }
            Mock Show-SalesforceResult { @{ id = '04t000000000001' } }
        }
        It 'includes target-dev-hub and json' {
            $out = New-SalesforcePackageVersion -PackageId '0Ho000000000001' -DevHubUsername 'devhub' -WaitMinutes 10
            $out.id | Should -Be '04t000000000001'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                $cmd = if ($Command) { $Command } else { "sf $Arguments" }
                ($cmd -like 'sf package version create *') -and ($cmd -like '* --target-dev-hub devhub*') -and ($cmd -like '* --json')
            }
        }
    }
}

Describe 'Install-SalesforcePackageVersion' {
    InModuleScope 'psfdx-packages' {
        BeforeEach { Mock Invoke-Salesforce {} }
        It 'targets org and sets waits' {
            Install-SalesforcePackageVersion -PackageVersionId '04t...' -TargetOrg 'me' -WaitMinutes 5 -NoPrompt | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                $cmd = if ($Command) { $Command } else { "sf $Arguments" }
                ($cmd -like 'sf package install *') -and ($cmd -like '* --target-org me*') -and ($cmd -like '* --wait 5*') -and ($cmd -like '* --publish-wait 5*') -and ($cmd -like '* --no-prompt*')
            }
        }
    }
}
