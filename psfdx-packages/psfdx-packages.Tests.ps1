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
            Remove-SalesforcePackage -Name 'My Pkg' -Confirm:$false -NoPrompt -TargetDevHub 'devhub'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'package|delete|--package|My Pkg|--no-prompt|--target-dev-hub|devhub'
            }
        }
    }
}

Describe 'Get-SalesforcePackagesInstalled' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":[]}' }
        }

        It 'returns nothing for zero installed packages' {
            @(Get-SalesforcePackagesInstalled).Count | Should -Be 0
        }

        It 'returns one installed package from a result array' {
            Mock Invoke-Salesforce { '{"status":0,"result":[{"SubscriberPackageName":"A","SubscriberPackageVersionId":"04t000000000001"}]}' }
            $out = @(Get-SalesforcePackagesInstalled)
            $out.Count | Should -Be 1
            $out[0].SubscriberPackageName | Should -Be 'A'
        }

        It 'returns multiple installed packages' {
            Mock Invoke-Salesforce { '{"status":0,"result":[{"SubscriberPackageName":"A"},{"SubscriberPackageName":"B"}]}' }
            $out = @(Get-SalesforcePackagesInstalled)
            $out.Count | Should -Be 2
            $out[1].SubscriberPackageName | Should -Be 'B'
        }

        It 'still accepts a records wrapper' {
            Mock Invoke-Salesforce { '{"status":0,"result":{"records":[{"SubscriberPackageName":"A"}]}}' }
            @(Get-SalesforcePackagesInstalled).Count | Should -Be 1
        }

        It 'throws the CLI message on non-zero status' {
            Mock Invoke-Salesforce { '{"status":1,"message":"No authorization information found for x"}' }
            { Get-SalesforcePackagesInstalled } | Should -Throw '*No authorization information*'
        }

        It 'throws on malformed JSON' {
            Mock Invoke-Salesforce { 'not json' }
            { Get-SalesforcePackagesInstalled } | Should -Throw '*not valid JSON*'
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
            Remove-SalesforcePackageVersion -PackageVersionId '04t000000000001' -Confirm:$false -NoPrompt | Out-Null
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

Describe 'Package deletion safety' {
    InModuleScope 'psfdx-packages' {
        BeforeEach { Mock Invoke-Salesforce { '{"status":0,"result":{}}' } }

        It 'Remove-SalesforcePackage runs nothing under -WhatIf' {
            Remove-SalesforcePackage -Name 'P' -WhatIf
            Assert-MockCalled Invoke-Salesforce -Times 0
        }

        It 'Remove-SalesforcePackageVersion runs nothing under -WhatIf and returns nothing' {
            $out = Remove-SalesforcePackageVersion -PackageVersionId '04t000000000001' -WhatIf
            $out | Should -BeNullOrEmpty
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
    }
}

Describe 'Package job reports' {
    InModuleScope 'psfdx-packages' {
        BeforeAll {
            $script:CreateId = '08c000000000001'
            $script:InstallId = '0Hf000000000001'
            $script:Queued = '{"status":0,"result":[{"Id":"08c000000000001AAA","Status":"Queued","Package2Id":"0Ho000000000001AAA","Package2VersionId":null,"SubscriberPackageVersionId":null,"Tag":"ci","Branch":"main","CreatedDate":"2026-11-21T10:00:00.000+0000","Error":[]}]}'
            $script:Success = '{"status":0,"result":[{"Id":"08c000000000001AAA","Status":"Success","Package2Id":"0Ho000000000001AAA","Package2VersionId":"05i000000000001AAA","SubscriberPackageVersionId":"04t000000000001AAA","Tag":"ci","Branch":"main","CreatedDate":"2026-11-21T10:00:00.000+0000","Error":[]}]}'
            $script:Failed = '{"status":0,"result":[{"Id":"08c000000000001AAA","Status":"Error","Package2Id":"0Ho000000000001AAA","Package2VersionId":null,"SubscriberPackageVersionId":null,"Error":["Apex test failed: MyTest.a","Code coverage 60% is below 75%"]}]}'
        }
        BeforeEach {
            $script:Reply = $script:Success
            Mock Invoke-Salesforce { $script:Reply }
        }

        Context 'Get-SalesforcePackageVersionCreateStatus' {
            It 'builds the exact command with the Dev Hub and maps the IDs of a successful job' {
                $s = Get-SalesforcePackageVersionCreateStatus -RequestId $script:CreateId -TargetDevHub devhub
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|version|create|report|--package-create-request-id|08c000000000001|--target-dev-hub|devhub|--json' }
                $s.Status | Should -Be 'Success'
                $s.Completed | Should -BeTrue
                $s.Succeeded | Should -BeTrue
                $s.RequestId | Should -Be '08c000000000001AAA'
                $s.PackageId | Should -Be '0Ho000000000001AAA'
                $s.PackageVersionId | Should -Be '05i000000000001AAA'
                $s.SubscriberPackageVersionId | Should -Be '04t000000000001AAA'
                $s.Tag | Should -Be 'ci'
                @($s.Errors).Count | Should -Be 0
            }
            It 'does not add --target-dev-hub when none is given' {
                Get-SalesforcePackageVersionCreateStatus -RequestId $script:CreateId | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|version|create|report|--package-create-request-id|08c000000000001|--json' }
            }
            It 'reports a queued job as not completed' {
                $script:Reply = $script:Queued
                $s = Get-SalesforcePackageVersionCreateStatus -RequestId $script:CreateId
                $s.Status | Should -Be 'Queued'
                $s.Completed | Should -BeFalse
                $s.Succeeded | Should -BeFalse
                $s.SubscriberPackageVersionId | Should -BeNullOrEmpty
            }
            It 'treats an in-between status as still running' {
                $script:Reply = $script:Queued.Replace('"Queued"', '"VerifyingFeaturesAndSettings"')
                (Get-SalesforcePackageVersionCreateStatus -RequestId $script:CreateId).Completed | Should -BeFalse
            }
            It 'returns a failed job with its error messages, without throwing' {
                $script:Reply = $script:Failed
                $s = Get-SalesforcePackageVersionCreateStatus -RequestId $script:CreateId
                $s.Status | Should -Be 'Error'
                $s.Completed | Should -BeTrue
                $s.Succeeded | Should -BeFalse
                $s.Errors | Should -Be @('Apex test failed: MyTest.a', 'Code coverage 60% is below 75%')
            }
            It 'writes the status and then throws PsfdxPackageJobFailed with -ThrowOnFailure' {
                $script:Reply = $script:Failed
                $err = $null
                try { Get-SalesforcePackageVersionCreateStatus -RequestId $script:CreateId -ThrowOnFailure | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxPackageJobFailed'
                $err.Exception.Message | Should -BeLike '*failed*Apex test failed*'
                $err.TargetObject.Status | Should -Be 'Error'
                $script:Reply = $script:Success
                { Get-SalesforcePackageVersionCreateStatus -RequestId $script:CreateId -ThrowOnFailure | Out-Null } | Should -Not -Throw
            }
            It 'rejects a bad request ID without calling the CLI, including an install request ID' {
                { Get-SalesforcePackageVersionCreateStatus -RequestId '0Hf000000000001' } | Should -Throw
                { Get-SalesforcePackageVersionCreateStatus -RequestId 'abc' } | Should -Throw
                { Get-SalesforcePackageVersionCreateStatus -RequestId '08c000000000001; calc' } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'throws the CLI message for CLI errors, and for empty results' {
                $script:Reply = '{"status":1,"name":"NamedOrgNotFoundError","message":"No authorization information found for nodevhub."}'
                { Get-SalesforcePackageVersionCreateStatus -RequestId $script:CreateId -TargetDevHub nodevhub } | Should -Throw -ExpectedMessage '*No authorization information found*'
                $script:Reply = '{"status":0,"result":[]}'
                { Get-SalesforcePackageVersionCreateStatus -RequestId $script:CreateId } | Should -Throw -ExpectedMessage '*returned no status*'
            }
        }

        Context 'Get-SalesforcePackageInstallStatus' {
            It 'builds the exact command with the target org and maps a successful install' {
                $script:Reply = '{"status":0,"result":{"Id":"0Hf000000000001AAA","Status":"SUCCESS","SubscriberPackageVersionKey":"04t000000000001AAA","Errors":null}}'
                $s = Get-SalesforcePackageInstallStatus -RequestId $script:InstallId -TargetOrg me
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|install|report|--request-id|0Hf000000000001|--target-org|me|--json' }
                $s.Status | Should -Be 'SUCCESS'
                $s.Succeeded | Should -BeTrue
                $s.Completed | Should -BeTrue
                $s.SubscriberPackageVersionKey | Should -Be '04t000000000001AAA'
                $s.RequestId | Should -Be '0Hf000000000001AAA'
            }
            It 'reports an install still in progress as not completed' {
                $script:Reply = '{"status":0,"result":{"Id":"0Hf000000000001AAA","Status":"IN_PROGRESS","SubscriberPackageVersionKey":"04t000000000001AAA"}}'
                $s = Get-SalesforcePackageInstallStatus -RequestId $script:InstallId
                $s.Completed | Should -BeFalse
                $s.Succeeded | Should -BeFalse
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|install|report|--request-id|0Hf000000000001|--json' }
            }
            It 'returns errors listed in the result of a failed install' {
                $script:Reply = '{"status":0,"result":{"Id":"0Hf000000000001AAA","Status":"ERROR","SubscriberPackageVersionKey":"04t000000000001AAA","Errors":{"errors":[{"message":"Missing dependency"},{"message":"Apex failed"}]}}}'
                $s = Get-SalesforcePackageInstallStatus -RequestId $script:InstallId
                $s.Status | Should -Be 'ERROR'
                $s.Completed | Should -BeTrue
                $s.Errors | Should -Be @('Missing dependency', 'Apex failed')
            }
            It 'turns the CLI''s failed-install error into an ERROR status with its numbered errors' {
                $script:Reply = '{"status":1,"name":"packageInstallError","message":"Package installation failed. Installation errors: \n1) Missing dependency\n2) Apex failed"}'
                $s = Get-SalesforcePackageInstallStatus -RequestId $script:InstallId -TargetOrg me
                $s.Status | Should -Be 'ERROR'
                $s.Completed | Should -BeTrue
                $s.RequestId | Should -Be $script:InstallId
                $s.Errors | Should -Be @('Missing dependency', 'Apex failed')
            }
            It 'recognises the CLI''s real failed-install message and error name, with or without error details' {
                $script:Reply = '{"status":1,"name":"packageInstallError","message":"Encountered errors installing the package! Installation errors: 
1) Missing dependency"}'
                $s = Get-SalesforcePackageInstallStatus -RequestId $script:InstallId
                $s.Status | Should -Be 'ERROR'
                $s.Errors | Should -Be @('Missing dependency')
                $script:Reply = '{"status":1,"name":"packageInstallError","message":"Encountered errors installing the package! <empty>"}'
                $s = Get-SalesforcePackageInstallStatus -RequestId $script:InstallId
                $s.Status | Should -Be 'ERROR'
                $s.Completed | Should -BeTrue
                @($s.Errors).Count | Should -Be 0
                $script:Reply = '{"status":1,"name":"packageInstallError","message":"Something else entirely"}'
                (Get-SalesforcePackageInstallStatus -RequestId $script:InstallId).Status | Should -Be 'ERROR'
            }
            It 'writes the status and then throws PsfdxPackageJobFailed with -ThrowOnFailure' {
                $script:Reply = '{"status":0,"result":{"Id":"0Hf000000000001AAA","Status":"ERROR","Errors":{"errors":[{"message":"Missing dependency"}]}}}'
                $err = $null
                try { Get-SalesforcePackageInstallStatus -RequestId $script:InstallId -ThrowOnFailure | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxPackageJobFailed'
                $err.Exception.Message | Should -BeLike '*Missing dependency*'
            }
            It 'throws the CLI message for errors that are not an install failure' {
                $script:Reply = '{"status":1,"name":"NamedOrgNotFoundError","message":"No authorization information found for nobody."}'
                { Get-SalesforcePackageInstallStatus -RequestId $script:InstallId -TargetOrg nobody } | Should -Throw -ExpectedMessage '*No authorization information found*'
                $script:Reply = ''
                { Get-SalesforcePackageInstallStatus -RequestId $script:InstallId } | Should -Throw -ExpectedMessage '*no output*'
                $script:Reply = 'not json'
                { Get-SalesforcePackageInstallStatus -RequestId $script:InstallId } | Should -Throw -ExpectedMessage '*not valid JSON*'
            }
            It 'rejects a bad request ID without calling the CLI, including a create request ID' {
                { Get-SalesforcePackageInstallStatus -RequestId '08c000000000001' } | Should -Throw
                { Get-SalesforcePackageInstallStatus -RequestId 'x' } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Install-SalesforcePackageVersion -AsObject' {
            It 'returns the install request when asked, so its Id can be reported later' {
                $script:Reply = '{"status":0,"result":{"Id":"0Hf000000000001AAA","Status":"IN_PROGRESS","SubscriberPackageVersionKey":"04t000000000001AAA"}}'
                $req = Install-SalesforcePackageVersion -PackageVersionId '04t000000000001' -TargetOrg me -NoPrompt -WaitMinutes 0 -AsObject
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|install|--package|04t000000000001|--target-org|me|--no-prompt|--security-type|AdminsOnly|--json' }
                $req.Id | Should -Be '0Hf000000000001AAA'
            }
            It 'still returns the CLI output unchanged, with no --json, without -AsObject' {
                $script:Reply = 'Successfully installed package'
                Install-SalesforcePackageVersion -PackageVersionId '04t000000000001' -TargetOrg me -WaitMinutes 5 | Should -Be 'Successfully installed package'
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|install|--package|04t000000000001|--target-org|me|--security-type|AdminsOnly|--wait|5|--publish-wait|5' }
            }
        }

        Context 'module surface' {
            It 'exports the two new commands and has help that says which ID to capture' {
                $exports = (Import-PowerShellDataFile -Path (Join-Path (Get-Module -Name psfdx-packages).ModuleBase 'psfdx-packages.psd1')).FunctionsToExport
                $exports | Should -Contain 'Get-SalesforcePackageVersionCreateStatus'
                $exports | Should -Contain 'Get-SalesforcePackageInstallStatus'
                (Get-Help Get-SalesforcePackageVersionCreateStatus -Full | Out-String) | Should -BeLike '*08c*New-SalesforcePackageVersion*'
                (Get-Help Get-SalesforcePackageInstallStatus -Full | Out-String) | Should -BeLike '*0Hf*Install-SalesforcePackageVersion*-AsObject*'
                foreach ($name in 'Get-SalesforcePackageVersionCreateStatus', 'Get-SalesforcePackageInstallStatus') { @((Get-Help $name -Examples).examples.example).Count | Should -BeGreaterThan 0 }
            }
        }
    }
}

Describe 'Package version pipelines' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            $script:Versions = '{"status":0,"result":[{"Id":"05i000000000001AAA","SubscriberPackageVersionId":"04t000000000001AAA","Version":"1.0.0.1"},{"Id":"05i000000000002AAA","SubscriberPackageVersionId":"04t000000000002AAA","Version":"1.0.0.2"}]}'
            Mock Invoke-Salesforce {
                if (($Arguments -join '|') -like 'package|version|list*') { return $script:Versions }
                return '{"status":0,"result":{"success":true}}'
            }
        }

        It 'pipes listed versions into Remove-SalesforcePackageVersion using the subscriber version ID' {
            Get-SalesforcePackageVersions -PackageId 0Ho000000000001AAA | Remove-SalesforcePackageVersion -NoPrompt -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|version|delete|--package|04t000000000001AAA|--no-prompt|--json' }
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|version|delete|--package|04t000000000002AAA|--no-prompt|--json' }
        }
        It 'deletes nothing under -WhatIf for piped versions' {
            Get-SalesforcePackageVersions -PackageId 0Ho000000000001AAA | Remove-SalesforcePackageVersion -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly -ParameterFilter { ($Arguments -join '|') -like 'package|version|delete*' }
        }
        It 'pipes a listed version into Promote-SalesforcePackageVersion' {
            Get-SalesforcePackageVersions -PackageId 0Ho000000000001AAA | Select-Object -First 1 | Promote-SalesforcePackageVersion -NoPrompt | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|version|promote|--package|04t000000000001AAA|--no-prompt|--json' }
        }
        It 'returns an empty collection for no versions, and piping it does nothing' {
            $script:Versions = '{"status":0,"result":[]}'
            @(Get-SalesforcePackageVersions -PackageId 0Ho000000000001AAA).Count | Should -Be 0
            Get-SalesforcePackageVersions -PackageId 0Ho000000000001AAA | Remove-SalesforcePackageVersion -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly -ParameterFilter { ($Arguments -join '|') -like 'package|version|delete*' }
        }
        It 'still takes an explicit -PackageVersionId' {
            Remove-SalesforcePackageVersion -PackageVersionId 04t000000000009AAA -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|version|delete|--package|04t000000000009AAA|--json' }
        }
    }
}

Describe 'Security regressions: package confirmation (issue 112)' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
        }
        It 'promotes nothing under -WhatIf, even with -NoPrompt' {
            Promote-SalesforcePackageVersion -PackageVersionId 04t000000000001AAA -WhatIf | Out-Null
            Promote-SalesforcePackageVersion -PackageVersionId 04t000000000001AAA -NoPrompt -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
        }
        It 'declares a High confirmation impact, so an interactive caller is asked' {
            (Get-Command Promote-SalesforcePackageVersion).ScriptBlock.Attributes.ConfirmImpact | Should -Contain 'High'
        }
        It 'promotes with -Confirm:$false, and with -NoPrompt without asking (existing scripts keep working)' {
            Promote-SalesforcePackageVersion -PackageVersionId 04t000000000001AAA -Confirm:$false | Out-Null
            Promote-SalesforcePackageVersion -PackageVersionId 04t000000000002AAA -NoPrompt | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|version|promote|--package|04t000000000001AAA|--json' }
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|version|promote|--package|04t000000000002AAA|--no-prompt|--json' }
        }
        It 'installs nothing under -WhatIf and still installs normally' {
            Install-SalesforcePackageVersion -PackageVersionId 04t000000000001AAA -TargetOrg me -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            Install-SalesforcePackageVersion -PackageVersionId 04t000000000001AAA -TargetOrg me | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly
        }
    }
}

Describe 'psfdx-packages sf package parity (issue 250)' {
    InModuleScope 'psfdx-packages' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
            $script:VerId = '04txx0000000001AAA'
        }

        Context 'missing flags on existing cmdlets' {
            It 'Install-SalesforcePackageVersion passes -ApexCompile, -InstallationKey and -UpgradeType' {
                Install-SalesforcePackageVersion -PackageVersionId $script:VerId -TargetOrg me -ApexCompile package -InstallationKey 'k 1' -UpgradeType DeprecateOnly -WaitMinutes 0 -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "package|install|--package|$($script:VerId)|--apex-compile|package|--installation-key|k 1|--upgrade-type|DeprecateOnly|--target-org|me|--security-type|AdminsOnly" }
            }
            It 'Install-SalesforcePackageVersion rejects values the CLI does not know' {
                { Install-SalesforcePackageVersion -PackageVersionId $script:VerId -ApexCompile some -Confirm:$false } | Should -Throw
                { Install-SalesforcePackageVersion -PackageVersionId $script:VerId -UpgradeType Purge -Confirm:$false } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'New-SalesforcePackageVersion passes every new option' {
                $dir = Join-Path $TestDrive 'pkg dir'
                New-Item -ItemType Directory -Path $dir | Out-Null
                New-SalesforcePackageVersion -PackageId 0Hoxx0000000001AAA -Path $dir -Branch main -VersionNumber '1.4.0.NEXT' -Language en_US -PostInstallScript Post -UninstallScript Un -PostInstallUrl https://a.example/post -ReleaseNotesUrl https://a.example/notes -SkipAncestorCheck -AsyncValidation -GeneratePackageZip -ExtendedDetails -InstallationKeyBypass -TargetDevHub hub | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "package|version|create|--package|0Hoxx0000000001AAA|--path|$dir|--branch|main|--version-number|1.4.0.NEXT|--language|en_US|--post-install-script|Post|--uninstall-script|Un|--post-install-url|https://a.example/post|--releasenotes-url|https://a.example/notes|--skip-ancestor-check|--async-validation|--generate-pkg-zip|--verbose|--definition-file|config/project-scratch-def.json|--installation-key-bypass|--target-dev-hub|hub|--json" }
            }
            It 'New-SalesforcePackageVersion accepts -Path without a package, and checks it exists' {
                $dir = Join-Path $TestDrive 'src'
                New-Item -ItemType Directory -Path $dir | Out-Null
                New-SalesforcePackageVersion -Path $dir | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -like "package|version|create|--path|$dir|*" -and ($Arguments -notcontains '--package') }
                { New-SalesforcePackageVersion -Path (Join-Path $TestDrive 'missing') } | Should -Throw -ExpectedMessage '*does not exist*'
                { New-SalesforcePackageVersion } | Should -Throw -ExpectedMessage '*PackageId*'
            }
            It 'Get-SalesforcePackageVersions passes the date and order options' {
                Get-SalesforcePackageVersions -PackageId 0Hoxx0000000001AAA -CreatedLastDays 0 -ModifiedLastDays 7 -OrderBy 'CreatedDate,PatchVersion' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|version|list|--created-last-days|0|--modified-last-days|7|--order-by|CreatedDate,PatchVersion|--packages|0Hoxx0000000001AAA|--json' }
            }
            It 'Get-SalesforcePackageVersions leaves the new options out by default' {
                Get-SalesforcePackageVersions -PackageId 0Hoxx0000000001AAA | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|version|list|--packages|0Hoxx0000000001AAA|--json' }
            }
        }

        Context 'Convert-SalesforcePackage' {
            It 'builds the command and asks first' {
                $seed = Join-Path $TestDrive 'seed'; New-Item -ItemType Directory -Path $seed | Out-Null
                $def = Join-Path $TestDrive 'def.json'; Set-Content -LiteralPath $def -Value '{}'
                Convert-SalesforcePackage -Package 033xx0000000001AAA -DefinitionFile $def -InstallationKey 'k' -CodeCoverage -PatchVersion 3 -SeedMetadata $seed -ExtendedDetails -WaitMinutes 30 -TargetDevHub hub -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "package|convert|--package|033xx0000000001AAA|--definition-file|$def|--installation-key|k|--code-coverage|--patch-version|3|--seed-metadata|$seed|--verbose|--wait|30|--target-dev-hub|hub|--json" }
                Convert-SalesforcePackage -Package 033xx0000000001AAA -InstallationKeyBypass -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly
            }
            It 'validates its input before running sf' {
                { Convert-SalesforcePackage -Package 033xx0000000001AAA -InstallationKey k -InstallationKeyBypass -Confirm:$false } | Should -Throw -ExpectedMessage '*not both*'
                { Convert-SalesforcePackage -Package 0Hoxx0000000001AAA -Confirm:$false } | Should -Throw
                { Convert-SalesforcePackage -Package 033xx0000000001AAA -SeedMetadata (Join-Path $TestDrive 'nope') -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist*'
                { Convert-SalesforcePackage -Package 033xx0000000001AAA -DefinitionFile (Join-Path $TestDrive 'nope.json') -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Update-SalesforcePackage' {
            It 'passes only what is given, and honours -WhatIf' {
                Update-SalesforcePackage -Package MyPkg -Name 'New name' -Description 'A "quoted" one' -ErrorNotificationUsername a@b.com -EnableAppAnalytics -RecommendedVersionId $script:VerId -SkipAncestorCheck -TargetDevHub hub -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "package|update|--package|MyPkg|--name|New name|--description|A `"quoted`" one|--error-notification-username|a@b.com|--enable-app-analytics|--recommended-version-id|$($script:VerId)|--skip-ancestor-check|--target-dev-hub|hub|--json" }
                Update-SalesforcePackage -Package MyPkg -Description 'x' -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly
            }
            It 'rejects a recommended version that is not a 04t ID' {
                { Update-SalesforcePackage -Package MyPkg -RecommendedVersionId 0Hoxx0000000001AAA -Confirm:$false } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Uninstall-SalesforcePackage and its report' {
            It 'is high impact: -WhatIf makes no call, and -NoPrompt does not turn -WhatIf off' {
                Uninstall-SalesforcePackage -Package $script:VerId -WhatIf | Out-Null
                Uninstall-SalesforcePackage -Package $script:VerId -NoPrompt -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
                (Get-Command Uninstall-SalesforcePackage).ScriptBlock.Attributes.Where({ $_ -is [System.Management.Automation.CmdletBindingAttribute] })[0].ConfirmImpact | Should -Be 'High'
            }
            It 'builds the command' {
                Uninstall-SalesforcePackage -Package $script:VerId -WaitMinutes 10 -NoPrompt -TargetOrg me | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "package|uninstall|--package|$($script:VerId)|--wait|10|--target-org|me|--json" }
            }
            It 'reports the status of an uninstall request, and rejects a bad ID' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"Id":"06yxx0000000001AAA","Status":"Success"}}' }
                (Get-SalesforcePackageUninstallStatus -RequestId 06yxx0000000001AAA -TargetOrg me).Status | Should -Be 'Success'
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|uninstall|report|--request-id|06yxx0000000001AAA|--target-org|me|--json' }
                { Get-SalesforcePackageUninstallStatus -RequestId "06yxx0000000001AAA`n" } | Should -Throw
                { Get-SalesforcePackageUninstallStatus -RequestId 'x; calc' } | Should -Throw
            }
            It 'throws the CLI message when the uninstall fails' {
                Mock Invoke-Salesforce { '{"status":1,"message":"The package is in use."}' }
                { Uninstall-SalesforcePackage -Package $script:VerId -Confirm:$false } | Should -Throw -ExpectedMessage '*in use*'
            }
        }

        Context 'package version read and update cmdlets' {
            It 'Get-SalesforcePackageVersion reads one version' {
                Mock Invoke-Salesforce { '{"status":0,"result":[{"Id":"05i000000000001","Version":"1.2.0.3"}]}' }
                (Get-SalesforcePackageVersion -PackageVersionId $script:VerId -ExtendedDetails -TargetDevHub hub) | Should -Not -BeNullOrEmpty
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "package|version|report|--package|$($script:VerId)|--verbose|--target-dev-hub|hub|--json" }
            }
            It 'Update-SalesforcePackageVersion passes the changes and honours -WhatIf' {
                Update-SalesforcePackageVersion -PackageVersionId $script:VerId -Branch main -InstallationKey k -Tag t1 -Description 'new desc' -Name 'New name' -TargetDevHub hub -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "package|version|update|--package|$($script:VerId)|--branch|main|--installation-key|k|--tag|t1|--version-description|new desc|--version-name|New name|--target-dev-hub|hub|--json" }
                Update-SalesforcePackageVersion -PackageVersionId $script:VerId -Tag t2 -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly
            }
            It 'Retrieve-SalesforcePackageVersion passes the output folder' {
                Retrieve-SalesforcePackageVersion -PackageVersionId $script:VerId -OutputDir 'out dir' -TargetDevHub hub | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "package|version|retrieve|--package|$($script:VerId)|--output-dir|out dir|--target-dev-hub|hub|--json" }
            }
            It 'ancestry and dependencies pass their options' {
                Get-SalesforcePackageVersionAncestry -Package MyPkg -DotCode -ExtendedDetails -TargetDevHub hub | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|version|displayancestry|--package|MyPkg|--dot-code|--verbose|--target-dev-hub|hub|--json' }
                Get-SalesforcePackageVersionDependencies -PackageVersionId $script:VerId -EdgeDirection root-last -InstallationKey k -ExtendedDetails -TargetDevHub hub | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "package|version|displaydependencies|--package|$($script:VerId)|--edge-direction|root-last|--installation-key|k|--verbose|--target-dev-hub|hub|--json" }
                { Get-SalesforcePackageVersionDependencies -PackageVersionId $script:VerId -EdgeDirection sideways } | Should -Throw
            }
            It 'Get-SalesforcePackageVersionCreateRequests passes the filters' {
                Get-SalesforcePackageVersionCreateRequests -CreatedLastDays 0 -ConversionsOnly -Status Error -ExtendedDetails -TargetDevHub hub | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|version|create|list|--created-last-days|0|--show-conversions-only|--status|Error|--verbose|--target-dev-hub|hub|--json' }
                { Get-SalesforcePackageVersionCreateRequests -Status Done } | Should -Throw
            }
            It 'reports a CLI failure' {
                Mock Invoke-Salesforce { '{"status":1,"message":"No package version found."}' }
                { Get-SalesforcePackageVersion -PackageVersionId $script:VerId } | Should -Throw -ExpectedMessage '*No package version*'
            }
        }

        Context 'push upgrades' {
            It 'schedules a push upgrade for a list of orgs, in UTC' {
                $start = [datetime]::SpecifyKind([datetime]'2026-12-01 02:30:00', [System.DateTimeKind]::Utc)
                New-SalesforcePushUpgrade -Package $script:VerId -OrgList 00Dxx0000000001AAA, 00Dxx0000000002AAA -StartTime $start -MigrateTo2gp -TargetDevHub hub -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "package|push-upgrade|schedule|--package|$($script:VerId)|--org-list|00Dxx0000000001AAA,00Dxx0000000002AAA|--start-time|2026-12-01T02:30:00|--migrate-to-2gp|--target-dev-hub|hub|--json" }
            }
            It 'writes the start time with the invariant culture whatever the machine culture' {
                $old = [System.Threading.Thread]::CurrentThread.CurrentCulture
                try {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('ar-SA')
                    $start = [datetime]::SpecifyKind([datetime]::new(2026, 12, 1, 2, 30, 0), [System.DateTimeKind]::Utc)
                    New-SalesforcePushUpgrade -Package $script:VerId -OrgList 00Dxx0000000001AAA -StartTime $start -Confirm:$false | Out-Null
                } finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $old }
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -like '*|--start-time|2026-12-01T02:30:00|*' }
            }
            It 'reads the orgs from a file, and needs exactly one source' {
                $file = Join-Path $TestDrive 'orgs.csv'; Set-Content -LiteralPath $file -Value "00Dxx0000000001AAA"
                New-SalesforcePushUpgrade -Package $script:VerId -OrgFile $file -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "package|push-upgrade|schedule|--package|$($script:VerId)|--org-file|$file|--json" }
                { New-SalesforcePushUpgrade -Package $script:VerId -Confirm:$false } | Should -Throw -ExpectedMessage '*-OrgList or -OrgFile*'
                { New-SalesforcePushUpgrade -Package $script:VerId -OrgList 00Dxx0000000001AAA -OrgFile $file -Confirm:$false } | Should -Throw -ExpectedMessage '*not both*'
                { New-SalesforcePushUpgrade -Package $script:VerId -OrgFile (Join-Path $TestDrive 'nope.csv') -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist*'
                { New-SalesforcePushUpgrade -Package $script:VerId -OrgList 'not-an-org' -Confirm:$false } | Should -Throw
            }
            It 'asks first, and -WhatIf names the time and makes no call' {
                New-SalesforcePushUpgrade -Package $script:VerId -OrgList 00Dxx0000000001AAA -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
                (Get-Command New-SalesforcePushUpgrade).ScriptBlock.Attributes.Where({ $_ -is [System.Management.Automation.CmdletBindingAttribute] })[0].ConfirmImpact | Should -Be 'High'
            }
            It 'lists and reports requests' {
                Get-SalesforcePushUpgrades -Package MyPkg -ScheduledLastDays 7 -ShowMigrationsOnly -Status 'In Progress' -TargetDevHub hub | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|push-upgrade|list|--package|MyPkg|--scheduled-last-days|7|--show-push-migrations-only|--status|In Progress|--target-dev-hub|hub|--json' }
                Get-SalesforcePushUpgrade -PushRequestId 0DVxx0000000001AAA -TargetDevHub hub | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|push-upgrade|report|--push-request-id|0DVxx0000000001AAA|--target-dev-hub|hub|--json' }
                { Get-SalesforcePushUpgrades -Package MyPkg -Status Done } | Should -Throw
                { Get-SalesforcePushUpgrade -PushRequestId "0DVxx0000000001AAA`n" } | Should -Throw
            }
            It 'Stop-SalesforcePushUpgrade confirms first and does not let -NoPrompt override -WhatIf' {
                Stop-SalesforcePushUpgrade -PushRequestId 0DVxx0000000001AAA -WhatIf | Out-Null
                Stop-SalesforcePushUpgrade -PushRequestId 0DVxx0000000001AAA -NoPrompt -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
                Stop-SalesforcePushUpgrade -PushRequestId 0DVxx0000000001AAA -NoPrompt -TargetDevHub hub | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package|push-upgrade|abort|--push-request-id|0DVxx0000000001AAA|--target-dev-hub|hub|--json' }
            }
            It 'throws the CLI message when the request cannot be aborted' {
                Mock Invoke-Salesforce { '{"status":1,"message":"Only Created or Pending requests can be aborted."}' }
                { Stop-SalesforcePushUpgrade -PushRequestId 0DVxx0000000001AAA -Confirm:$false } | Should -Throw -ExpectedMessage '*can be aborted*'
            }
        }

        Context 'first-generation (package1) cmdlets' {
            It 'uploads a version' {
                New-SalesforceFirstGenPackageVersion -PackageId 033xx0000000001AAA -Name 'Spring release' -Description 'D' -Version 2.1 -InstallationKey k -ManagedReleased -PostInstallUrl https://a.example/p -ReleaseNotesUrl https://a.example/r -WaitMinutes 20 -TargetOrg pack -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package1|version|create|--package-id|033xx0000000001AAA|--name|Spring release|--description|D|--version|2.1|--installation-key|k|--managed-released|--post-install-url|https://a.example/p|--release-notes-url|https://a.example/r|--wait|20|--target-org|pack|--json' }
                New-SalesforceFirstGenPackageVersion -PackageId 033xx0000000001AAA -Name x -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly
            }
            It 'reads the upload status, one version and the list' {
                Get-SalesforceFirstGenPackageVersionCreateStatus -RequestId 0HD000000000001 -TargetOrg pack | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package1|version|create|get|--request-id|0HD000000000001|--target-org|pack|--json' }
                Get-SalesforceFirstGenPackageVersion -PackageVersionId $script:VerId -TargetOrg pack | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "package1|version|display|--package-version-id|$($script:VerId)|--target-org|pack|--json" }
                Get-SalesforceFirstGenPackageVersions -PackageId 033xx0000000001AAA -TargetOrg pack | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package1|version|list|--package-id|033xx0000000001AAA|--target-org|pack|--json' }
                Get-SalesforceFirstGenPackageVersions | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'package1|version|list|--json' }
            }
            It 'rejects IDs of the wrong kind before running sf' {
                { New-SalesforceFirstGenPackageVersion -PackageId 0Hoxx0000000001AAA -Name x -Confirm:$false } | Should -Throw
                { Get-SalesforceFirstGenPackageVersion -PackageVersionId 033xx0000000001AAA } | Should -Throw
                { Get-SalesforceFirstGenPackageVersions -PackageId "033xx0000000001AAA`n" } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        It 'exports the new cmdlets' {
            $exports = (Get-Module psfdx-packages).ExportedFunctions.Keys
            foreach ($n in 'Convert-SalesforcePackage', 'Update-SalesforcePackage', 'Uninstall-SalesforcePackage', 'Get-SalesforcePackageVersion', 'Update-SalesforcePackageVersion', 'Retrieve-SalesforcePackageVersion', 'Get-SalesforcePackageVersionAncestry', 'Get-SalesforcePackageVersionDependencies', 'Get-SalesforcePackageVersionCreateRequests', 'Get-SalesforcePackageUninstallStatus', 'New-SalesforcePushUpgrade', 'Get-SalesforcePushUpgrades', 'Get-SalesforcePushUpgrade', 'Stop-SalesforcePushUpgrade', 'New-SalesforceFirstGenPackageVersion', 'Get-SalesforceFirstGenPackageVersionCreateStatus', 'Get-SalesforceFirstGenPackageVersion', 'Get-SalesforceFirstGenPackageVersions') { $exports | Should -Contain $n }
        }
    }
}
