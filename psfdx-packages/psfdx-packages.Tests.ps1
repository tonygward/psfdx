# Ensure no other instances of psfdx-packages are loaded (e.g., from PSModulePath)
Get-Module -Name 'psfdx-packages' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

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
            $id = New-SalesforcePackage -Name 'MyPkg' -TargetDevHub 'devhub' -PackageType Managed
            $id | Should -Be '0Ho000000000001'
            Assert-MockCalled Invoke-Salesforce -Times 1 -Scope It -ParameterFilter {
                ($Command -like 'sf package create * --target-dev-hub devhub*') -and
                ($Command -notlike '* --description *') -and
                ($Command -notlike '* --error-notification-username *')
            }
        }

        It 'omits target-dev-hub when not provided' {
            New-SalesforcePackage -Name 'MyPkg' -PackageType Managed | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Scope It -ParameterFilter {
                ($Command -like 'sf package create *') -and
                ($Command -notlike '* --target-dev-hub *') -and
                ($Command -notlike '* --description *') -and
                ($Command -notlike '* --error-notification-username *')
            }
        }

        It 'passes description when provided' {
            New-SalesforcePackage -Name 'MyPkg' -Description 'My description' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Command -like 'sf package create *') -and
                ($Command -like '* --description My description*')
            }
        }

        It 'passes error notification username when provided' {
            New-SalesforcePackage -Name 'MyPkg' -ErrorNotificationUsername 'alert@example.com' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Command -like 'sf package create *') -and
                ($Command -like '* --error-notification-username alert@example.com*')
            }
        }
    }
}

Describe 'Get-SalesforcePackages' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0}' }
            Mock Show-SalesforceResult { @([pscustomobject]@{ Name = 'Pkg1' }) }
        }

        It 'omits verbose by default' {
            Get-SalesforcePackages -TargetDevHub 'devhub' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Command -like 'sf package list *') -and
                ($Command -like '* --target-dev-hub devhub*') -and
                ($Command -notlike '* --verbose*')
            }
        }

        It 'adds verbose when extended details requested' {
            Get-SalesforcePackages -ExtendedPackageDetails | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Command -like 'sf package list *') -and
                ($Command -like '* --verbose*')
            }
        }
    }
}

Describe 'Get-SalesforcePackage' {
    InModuleScope 'psfdx-packages' {
        It 'forwards extended details to package list' {
            Mock Get-SalesforcePackages { @([pscustomobject]@{ Name = 'Pkg1' }) }
            Get-SalesforcePackage -Name 'Pkg1' -ExtendedPackageDetails | Out-Null
            Assert-MockCalled Get-SalesforcePackages -Times 1 -ParameterFilter { $ExtendedPackageDetails }
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
            $out = New-SalesforcePackageVersion -PackageId '0Ho000000000001' -TargetDevHub 'devhub' -WaitMinutes 10
            $out.id | Should -Be '04t000000000001'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -like 'sf package version create *') -and ($Command -like '* --target-dev-hub devhub*') -and ($Command -like '* --json') }
        }

        It 'omits target-dev-hub when not provided' {
            New-SalesforcePackageVersion -PackageId '0Ho000000000001' -WaitMinutes 10 | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -like 'sf package version create *') -and ($Command -notlike '* --target-dev-hub *') }
        }
    }
}

Describe 'Get-SalesforcePackageVersions' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0}' }
            Mock Show-SalesforceResult { @([pscustomobject]@{ Id = '04t000000000001' }) }
            Mock Get-SalesforcePackage { @([pscustomobject]@{ Id = '0Ho000000000001' }) }
        }

        It 'builds package version list command' {
            Get-SalesforcePackageVersions -PackageId '0Ho000000000001' -Released -Concise -ExtendedDetails -TargetDevHub 'devhub' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Command -like 'sf package version list*') -and
                ($Command -like '* --packages 0Ho000000000001*') -and
                ($Command -like '* --released*') -and
                ($Command -like '* --concise*') -and
                ($Command -like '* --verbose*') -and
                ($Command -like '* --target-dev-hub devhub*') -and
                ($Command -notlike '* --branch *')
            }
        }

        It 'adds conversions-only flag when requested' {
            Get-SalesforcePackageVersions -PackageId '0Ho000000000001' -ConversionsOnly | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Command -like 'sf package version list*') -and
                ($Command -like '* --show-conversions-only*')
            }
        }

        It 'adds branch when provided' {
            Get-SalesforcePackageVersions -PackageId '0Ho000000000001' -Branch 'feature/foo' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Command -like 'sf package version list*') -and
                ($Command -like '* --branch feature/foo*')
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
                ($Command -like 'sf package install *') -and
                ($Command -like '* --target-org me*') -and
                ($Command -like '* --wait 5*') -and
                ($Command -like '* --publish-wait 5*') -and
                ($Command -like '* --no-prompt*') -and
                ($Command -like '* --security-type AdminsOnly*')
            }
        }

        It 'allows security type override' {
            Install-SalesforcePackageVersion -PackageVersionId '04t...' -SecurityType AllUsers | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Command -like 'sf package install *') -and
                ($Command -like '* --security-type AllUsers*')
            }
        }
    }
}
