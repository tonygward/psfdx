# Ensure no other instances of psfdx-packages are loaded (e.g., from PSModulePath)
Get-Module -Name 'psfdx-packages' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

# Import module at discovery time so InModuleScope can find it
$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-packages.psd1'
Import-Module $moduleManifest -Force | Out-Null

# These cmdlets use the structured form of Invoke-Salesforce (-FilePath and -Arguments), so the
# tests assert the exact argument array, joined with '|' to keep each value distinct.

Describe 'New-SalesforcePackage' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"Id":"0Ho000000000001"}}' }
        }

        It 'uses target-dev-hub and returns package id' {
            $id = New-SalesforcePackage -Name 'MyPkg' -TargetDevHub 'devhub' -PackageType Managed
            $id | Should -Be '0Ho000000000001'
            Assert-MockCalled Invoke-Salesforce -Times 1 -Scope It -ParameterFilter {
                ($FilePath -eq 'sf') -and
                (($Arguments -join '|') -eq 'package|create|--name|MyPkg|--package-type|Managed|--path|force-app/main/default|--target-dev-hub|devhub|--json')
            }
        }

        It 'omits target-dev-hub, description and notification user when not provided' {
            New-SalesforcePackage -Name 'MyPkg' -PackageType Managed | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Scope It -ParameterFilter {
                (($Arguments -join '|') -eq 'package|create|--name|MyPkg|--package-type|Managed|--path|force-app/main/default|--json')
            }
        }

        It 'passes a description with spaces as one argument' {
            New-SalesforcePackage -Name 'My Pkg' -Description 'My description' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                $Arguments.Count -eq 11 -and
                $Arguments[3] -eq 'My Pkg' -and
                ($Arguments -join '|') -like '*|--description|My description|--json'
            }
        }

        It 'passes error notification username when provided' {
            New-SalesforcePackage -Name 'MyPkg' -ErrorNotificationUsername 'alert@example.com' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -like '*|--error-notification-username|alert@example.com|--json'
            }
        }

        It 'keeps hostile and awkward values as single arguments' {
            $path = "my dir/it's `"quoted`" 100% C:\temp\ ; & | `$(x) Zoë"
            $description = "O'Brien's `"pkg`" --json --target-dev-hub evil; rm -rf /"
            New-SalesforcePackage -Name 'My-Pkg' -Path $path -Description $description | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                $Arguments.Count -eq 11 -and
                $Arguments[7] -ceq "my dir/it's `"quoted`" 100% C:\temp\ ; & | `$(x) Zoë" -and
                $Arguments[9] -ceq "O'Brien's `"pkg`" --json --target-dev-hub evil; rm -rf /"
            }
        }
    }
}

Describe 'Get-SalesforcePackages' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":[{"Name":"Pkg1"}]}' }
        }

        It 'omits verbose by default' {
            Get-SalesforcePackages -TargetDevHub 'devhub' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'package|list|--target-dev-hub|devhub|--json'
            }
        }

        It 'adds verbose when extended details requested' {
            Get-SalesforcePackages -ExtendedPackageDetails | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'package|list|--verbose|--json'
            }
        }

        It 'forwards -Verbose' {
            Get-SalesforcePackages -Verbose 4>&1 | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Verbose }
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

Describe 'Remove-SalesforcePackage' {
    InModuleScope 'psfdx-packages' {
        It 'passes a name with spaces as one argument' {
            Mock Invoke-Salesforce {}
            Remove-SalesforcePackage -Name 'My Pkg' -NoPrompt -TargetDevHub 'devhub'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'package|delete|--package|My Pkg|--no-prompt|--target-dev-hub|devhub'
            }
        }
    }
}

Describe 'Get-SalesforcePackagesInstalled' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"records":[]}}' }
        }

        It 'builds command with target org and json' {
            Get-SalesforcePackagesInstalled -TargetOrg 'me@example.com' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($FilePath -eq 'sf') -and (($Arguments -join '|') -eq 'package|installed|list|--target-org|me@example.com|--json')
            }
        }

        It 'adds api version when provided' {
            Get-SalesforcePackagesInstalled -ApiVersion '60.0' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'package|installed|list|--api-version|60.0|--json'
            }
        }
    }
}

Describe 'New-SalesforcePackageVersion' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"id":"04t000000000001"}}' }
        }

        It 'includes target-dev-hub and json' {
            $out = New-SalesforcePackageVersion -PackageId '0Ho000000000001' -TargetDevHub 'devhub' -WaitMinutes 10
            $out.id | Should -Be '04t000000000001'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'package|version|create|--package|0Ho000000000001|--definition-file|config/project-scratch-def.json|--installation-key-bypass|--wait|10|--target-dev-hub|devhub|--json'
            }
        }

        It 'omits target-dev-hub when not provided' {
            New-SalesforcePackageVersion -PackageId '0Ho000000000001' -WaitMinutes 10 | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                (($Arguments -join '|') -like 'package|version|create|*') -and ($Arguments -notcontains '--target-dev-hub')
            }
        }

        It 'keeps names, descriptions, tags, keys and definition file paths with spaces intact' {
            New-SalesforcePackageVersion -PackageId '0Ho000000000001' -Name 'Version 1' -Description "It's `"new`"" -Tag 'tag one' -InstallationKey 'key 100%' -ScratchOrgDefinitionFile 'my config/def file.json' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -ceq "package|version|create|--package|0Ho000000000001|--version-name|Version 1|--version-description|It's `"new`"|--tag|tag one|--definition-file|my config/def file.json|--installation-key|key 100%|--json"
            }
        }
    }
}

Describe 'Promote and Remove package versions' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{}}' }
        }

        It 'builds the promote command' {
            Promote-SalesforcePackageVersion -PackageVersionId '04t000000000001' -TargetDevHub 'devhub' -NoPrompt | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'package|version|promote|--package|04t000000000001|--target-dev-hub|devhub|--no-prompt|--json'
            }
        }

        It 'builds the delete command' {
            Remove-SalesforcePackageVersion -PackageVersionId '04t000000000001' -NoPrompt | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'package|version|delete|--package|04t000000000001|--no-prompt|--json'
            }
        }
    }
}

Describe 'Get-SalesforcePackageVersions' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":[]}' }
            Mock Get-SalesforcePackage { @([pscustomobject]@{ Id = '0Ho000000000001' }) }
        }

        It 'builds package version list command' {
            Get-SalesforcePackageVersions -PackageId '0Ho000000000001' -Released -Concise -ExtendedDetails -TargetDevHub 'devhub' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'package|version|list|--packages|0Ho000000000001|--released|--concise|--verbose|--target-dev-hub|devhub|--json'
            }
        }

        It 'adds conversions-only flag when requested' {
            Get-SalesforcePackageVersions -PackageId '0Ho000000000001' -ConversionsOnly | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'package|version|list|--packages|0Ho000000000001|--show-conversions-only|--json'
            }
        }

        It 'adds branch when provided' {
            Get-SalesforcePackageVersions -PackageId '0Ho000000000001' -Branch 'feature/foo bar' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'package|version|list|--packages|0Ho000000000001|--branch|feature/foo bar|--json'
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
                ($Arguments -join '|') -eq 'package|install|--package|04t...|--target-org|me|--no-prompt|--security-type|AdminsOnly|--wait|5|--publish-wait|5'
            }
        }

        It 'allows security type override' {
            Install-SalesforcePackageVersion -PackageVersionId '04t...' -SecurityType AllUsers | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -like '*|--security-type|AllUsers|*'
            }
        }
    }
}
