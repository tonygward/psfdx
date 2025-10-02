# Ensure clean slate and load local dependency module first
Get-Module -Name 'psfdx-development','psfdx-metadata','psfdx' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

# Import local psfdx-metadata so RequiredModules resolves from repo
$metadataManifest = Join-Path -Path $PSScriptRoot -ChildPath '..\psfdx-metadata\psfdx-metadata.psd1'
Import-Module $metadataManifest -Force | Out-Null

# Import base psfdx module used by shared helpers
$psfdxManifest = Join-Path -Path $PSScriptRoot -ChildPath '..\psfdx\psfdx.psd1'
Import-Module $psfdxManifest -Force | Out-Null

# Import module under test so InModuleScope can find it
$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-development.psd1'
Import-Module $moduleManifest -Force | Out-Null

Describe 'psfdx-development basics' {
    InModuleScope 'psfdx-development' {
        BeforeEach {
            Mock Invoke-Salesforce {
                param($Command)
                switch -Regex ($Command) {
                    'sf config get target-dev-hub' {
                        return '{"status":0,"result":{"target-dev-hub":[{"name":"target-dev-hub","value":"DevHub"}]}}'
                    }
                    Default {
                        return '{"status":0,"result":{"successes":[{"name":"target-config"}]}}'
                    }
                }
            }
        }
        It 'starts LWC dev server with sf command' {
            Start-SalesforceLwcDevServer | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf lightning dev app' }
        }
        It 'sets project target org with equals syntax' {
            Set-SalesforceTargetOrg -Value 'user@example' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config set target-org=user@example --json' }
        }
        It 'removes project target org' {
            Remove-SalesforceTargetOrg | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config unset target-org --json' }
        }
        It 'removes project target org globally' {
            Remove-SalesforceTargetOrg -Global | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config unset target-org --global --json' }
        }
        It 'sets default dev hub with equals syntax' {
            Set-SalesforceTargetDevHub -Value 'DevHubAlias' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config set target-dev-hub=DevHubAlias --json' }
        }
        It 'sets default dev hub globally' {
            Set-SalesforceTargetDevHub -Value 'DevHubAlias' -Global | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config set target-dev-hub=DevHubAlias --global --json' }
        }
        It 'gets default dev hub' {
            Get-SalesforceTargetDevHub | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config get target-dev-hub --json' }
        }
        It 'gets default dev hub globally' {
            Get-SalesforceTargetDevHub -Global | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config get target-dev-hub --global --json' }
        }
        It 'removes default dev hub' {
            Remove-SalesforceTargetDevHub | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config unset target-dev-hub --json' }
        }
        It 'removes default dev hub globally' {
            Remove-SalesforceTargetDevHub -Global | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf config unset target-dev-hub --global --json' }
        }
    }
}

Describe 'Test-SalesforceApex command building' {
    InModuleScope 'psfdx-development' {
        BeforeEach {
            Mock Invoke-Salesforce {
                param($Command)
                '{"status":0,"result":{"tests":[],"summary":{"outcome":"Passed","testRunCoverage":"100%"}}}'
            }
        }
        It 'runs specified class synchronously with target org and json' {
            Test-SalesforceApex -ClassName 'MyClass' -TargetOrg 'me' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -like 'sf apex run test *') -and ($Command -like '* --tests MyClass*') -and ($Command -like '* --target-org me*') -and ($Command -like '* --result-format json*') }
        }
        It 'throws if output directory does not exist' {
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            $threw = $false
            try {
                Test-SalesforceApex -OutputDirectory $missing | Out-Null
            }
            catch {
                $threw = $true
                $_.Exception.Message | Should -Be "Output directory '$missing' does not exist."
            }
            $threw | Should -BeTrue "Expected Test-SalesforceApex to throw when output directory is missing."
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
        It 'passes output directory when path exists' {
            $existing = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                Test-SalesforceApex -OutputDirectory $existing.FullName | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -like "sf apex run test* --output-dir $($existing.FullName)*" }
            }
            finally {
                Remove-Item -LiteralPath $existing.FullName -Force -Recurse
            }
        }
        It 'throws if TestsInProject has no apex tests' {
            $tempRoot = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            Push-Location $tempRoot.FullName
            try {
                $clsPath = Join-Path (Get-Location).Path 'NotATest.cls'
                Set-Content -Path $clsPath -Value 'public class NotATest {}' -Encoding UTF8
                $threw = $false
                try {
                    Test-SalesforceApex -TestsInProject | Out-Null
                }
                catch {
                    $threw = $true
                    $_.Exception.Message | Should -BeLike "Cannot validate argument on parameter 'TestClassNames'.*"
                }
                $threw | Should -BeTrue "Expected Test-SalesforceApex to throw when no Apex tests found."
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            finally {
                Pop-Location
                Remove-Item -LiteralPath $tempRoot.FullName -Force -Recurse
            }
        }
        It 'adds tests from project folder as repeated --tests parameters' {
            $tempRoot = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            Push-Location $tempRoot.FullName
            try {
                $first = Join-Path (Get-Location).Path 'first.cls'
                $secondFolder = Join-Path (Get-Location).Path 'sub'
                $second = Join-Path $secondFolder 'second.cls'
                New-Item -Path $secondFolder -ItemType Directory -Force | Out-Null
                Set-Content -Path $first -Value '@isTest public class first {}' -Encoding UTF8
                Set-Content -Path $second -Value '@isTest private class second {}' -Encoding UTF8

                Test-SalesforceApex -TestsInProject | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                    ($Command -like 'sf apex run test *') -and
                    ($Command -like '* --tests first*') -and
                    ($Command -like '* --tests second*')
                }
            }
            finally {
                Pop-Location
                Remove-Item -LiteralPath $tempRoot.FullName -Force -Recurse
            }
        }
    }
}

Describe 'New-SalesforceApexClass' {
    InModuleScope 'psfdx-development' {
        It 'throws if output directory does not exist' {
            Mock Invoke-Salesforce {}
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            $threw = $false
            try {
                New-SalesforceApexClass -Name 'MyClass' -OutputDirectory $missing
            }
            catch {
                $threw = $true
                $_.Exception.Message | Should -Be "Output directory '$missing' does not exist."
            }
            $threw | Should -BeTrue "Expected New-SalesforceApexClass to throw when output directory is missing."
            Assert-MockCalled Invoke-Salesforce -Times 0
        }

        It 'passes output directory when path exists' {
            $existing = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                Mock Invoke-Salesforce {}
                New-SalesforceApexClass -Name 'MyClass' -OutputDirectory $existing.FullName
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq "sf apex generate class --name MyClass --template DefaultApexClass --output-dir $($existing.FullName)" }
            }
            finally {
                Remove-Item -LiteralPath $existing.FullName -Force -Recurse
            }
        }

        It 'omits output directory validation when not provided' {
            Mock Invoke-Salesforce {}
            Mock Test-Path { throw "Test-Path should not be called" }
            New-SalesforceApexClass -Name 'DefaultClass'
            $expected = 'sf apex generate class --name DefaultClass --template DefaultApexClass'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq $expected }
        }
    }
}

Describe 'New-SalesforceApexTrigger' {
    InModuleScope 'psfdx-development' {
        It 'throws if output directory does not exist' {
            Mock Invoke-Salesforce {}
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            $threw = $false
            try {
                New-SalesforceApexTrigger -Name 'MyTrigger' -OutputDirectory $missing
            }
            catch {
                $threw = $true
                $_.Exception.Message | Should -Be "Output directory '$missing' does not exist."
            }
            $threw | Should -BeTrue "Expected New-SalesforceApexTrigger to throw when output directory is missing."
            Assert-MockCalled Invoke-Salesforce -Times 0
        }

        It 'passes options when path exists' {
            $existing = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                Mock Invoke-Salesforce {}
                New-SalesforceApexTrigger -Name 'MyTrigger' -SObject 'Account' -OutputDirectory $existing.FullName
                $expected = "sf apex generate trigger --name MyTrigger --event before insert --sobject Account --output-dir $($existing.FullName)"
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq $expected }
            }
            finally {
                Remove-Item -LiteralPath $existing.FullName -Force -Recurse
            }
        }

        It 'omits output directory validation when not provided' {
            Mock Invoke-Salesforce {}
            Mock Test-Path { throw "Test-Path should not be called" }
            New-SalesforceApexTrigger -Name 'DefaultTrigger'
            $expected = 'sf apex generate trigger --name DefaultTrigger --event before insert'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq $expected }
        }
    }
}

Describe 'Watch-SalesforceApexAction' {
    InModuleScope 'psfdx-development' {
        BeforeEach {
            Mock Describe-SalesforceMetadataTypes { @('ApexClass', 'ApexTrigger') } -ModuleName 'psfdx-metadata'
        }

        It 'deploys component and runs tests when apex class changes' {
            $tempRoot = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                $file = Join-Path $tempRoot.FullName 'Sample.cls'
                Set-Content -Path $file -Value 'public class Sample {}' -Encoding UTF8

                Mock Invoke-Salesforce {
                    param($Command)
                    return '{"status":0,"result":{"command":"deploy","details":{"tests":{"successes":[{"name":"SampleTest"}]}}}}'
                }
                Mock Get-SalesforceApexTestClassNames { param($FilePath,$ProjectFolder) return @('SampleTest') }

                $result = Watch-SalesforceApexAction -FilePath $file -ProjectFolder $tempRoot.FullName

                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -like 'sf project deploy start --metadata ApexClass:Sample*') -and ($Command -like '*--tests SampleTest*') -and ($Command -like '*--test-level RunSpecifiedTests*') }
                $result.command | Should -Be 'deploy'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot.FullName -Force -Recurse
            }
        }

        It 'skips non-apex files' {
            $tempRoot = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                $file = Join-Path $tempRoot.FullName 'README.txt'
                Set-Content -Path $file -Value 'not apex' -Encoding UTF8

                Mock Invoke-Salesforce { throw 'Should not deploy' }

                $result = Watch-SalesforceApexAction -FilePath $file -ProjectFolder $tempRoot.FullName
                $result | Should -BeNullOrEmpty
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            finally {
                Remove-Item -LiteralPath $tempRoot.FullName -Force -Recurse
            }
        }

        It 'deploys but skips tests when no apex tests exist' {
            $tempRoot = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                $file = Join-Path $tempRoot.FullName 'Sample.trigger'
                Set-Content -Path $file -Value 'trigger Sample on Account (before insert) {}' -Encoding UTF8

                Mock Invoke-Salesforce {
                    param($Command)
                    return '{"status":0,"result":{"command":"deploy"}}'
                }
                Mock Get-SalesforceApexTestClassNames { param($FilePath,$ProjectFolder) return @() }

                $result = Watch-SalesforceApexAction -FilePath $file -ProjectFolder $tempRoot.FullName
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -like 'sf project deploy start --metadata ApexTrigger:Sample*') -and ($Command -notlike '*--tests*') }
                $result.command | Should -Be 'deploy'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot.FullName -Force -Recurse
            }
        }
    }
}

Describe 'Get-SalesforceApexTestClassNames' {
    InModuleScope 'psfdx-development' {
        It 'returns all test classes within a project folder' {
            $tempRoot = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                $testOne = Join-Path $tempRoot.FullName 'SampleTest.cls'
                $nested = Join-Path $tempRoot.FullName 'nested'
                New-Item -Path $nested -ItemType Directory | Out-Null
                $testTwo = Join-Path $nested 'AnotherTest.cls'
                Set-Content -Path $testOne -Value '@isTest public class SampleTest { @isTest static void exerciseSample() { Sample.handle(); } }' -Encoding UTF8
                Set-Content -Path $testTwo -Value '@isTest private class AnotherTest { @isTest static void exerciseSampleDependency() { Sample.handle(); } }' -Encoding UTF8

                $result = Get-SalesforceApexTestClassNames -ProjectFolder $tempRoot.FullName
                $result | Should -Contain 'SampleTest'
                $result | Should -Contain 'AnotherTest'
                $result.Count | Should -Be 2
            }
            finally {
                Remove-Item -LiteralPath $tempRoot.FullName -Force -Recurse
            }
        }
    }
}

Describe 'Get-SalesforceApexTestClassNamesFromFile' {
    InModuleScope 'psfdx-development' {
        It 'returns only the class when file is a test class' {
            $tempRoot = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                $grand = Join-Path $tempRoot.FullName 'grand'
                $parent = Join-Path $grand 'parent'
                New-Item -Path $parent -ItemType Directory -Force | Out-Null

                $file = Join-Path $parent 'SampleTest.cls'
                Set-Content -Path $file -Value '@isTest public class SampleTest {}' -Encoding UTF8

                $result = Get-SalesforceApexTestClassNamesFromFile -FilePath $file
                $result | Should -Be @('SampleTest')
            }
            finally {
                Remove-Item -LiteralPath $tempRoot.FullName -Force -Recurse
            }
        }

        It 'returns all discovered test classes when file is not a test class' {
            $tempRoot = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                $grand = Join-Path $tempRoot.FullName 'grand'
                $parent = Join-Path $grand 'parent'
                New-Item -Path $parent -ItemType Directory -Force | Out-Null

                $classFile = Join-Path $parent 'Sample.cls'
                Set-Content -Path $classFile -Value 'public class Sample {}' -Encoding UTF8

                $testOne = Join-Path $grand 'SampleTest.cls'
                $nested = Join-Path $grand 'nested'
                New-Item -Path $nested -ItemType Directory -Force | Out-Null
                $testTwo = Join-Path $nested 'AnotherTest.cls'
                Set-Content -Path $testOne -Value '@isTest public class SampleTest {}' -Encoding UTF8
                Set-Content -Path $testTwo -Value '@isTest private class AnotherTest {}' -Encoding UTF8

                $result = Get-SalesforceApexTestClassNamesFromFile -FilePath $classFile
                $result | Should -Contain 'SampleTest'
                $result.Count | Should -Be 1
            }
            finally {
                Remove-Item -LiteralPath $tempRoot.FullName -Force -Recurse
            }
        }
    }
}

Describe 'Get-SalesforceApexClass' {
    InModuleScope 'psfdx-development' {
        BeforeEach {
            $json = '{"status":0,"result":{"records":[{"Id":"01pxx0000000001AAA","Name":"MyClass"}]}}'
            Mock Invoke-Salesforce { $json } -ModuleName 'psfdx'
        }
        It 'returns first record by name' {
            $rec = Get-SalesforceApexClass -Name 'MyClass' -TargetOrg 'me'
            $rec.Id   | Should -Be '01pxx0000000001AAA'
            $rec.Name | Should -Be 'MyClass'
        }
    }
}
