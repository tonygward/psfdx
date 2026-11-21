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
