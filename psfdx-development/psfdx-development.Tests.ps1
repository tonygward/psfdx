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
                $text = $FilePath + ' ' + ($Arguments -join ' ')
                switch -Regex ($text) {
                    'sf plugins --core --json' {
                        return '[{"name":"@salesforce/plugin-lightning-dev","version":"1.0.0"}]'
                    }
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
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'lightning|dev|app' }
        }
        It 'starts LWC dev server in component mode with name and target org' {
            Start-SalesforceLwcDevServer -Mode Component -Name 'my comp' -TargetOrg me | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'lightning|dev|component|--name|my comp|--target-org|me' }
        }
        It 'starts LWC dev server in site mode' {
            Start-SalesforceLwcDevServer -Mode Site -Name 'My Site' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'lightning|dev|site|--name|My Site' }
        }
        It 'starts LWC dev server app with device type' {
            Start-SalesforceLwcDevServer -Mode App -Name MyApp -DeviceType ios | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'lightning|dev|app|--name|MyApp|--device-type|ios' }
        }
        It 'rejects device type outside app mode' {
            { Start-SalesforceLwcDevServer -Mode Site -DeviceType ios } | Should -Throw -ExpectedMessage '-DeviceType is only supported with -Mode App.'
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { ($Arguments -join '|') -like 'lightning|dev*' }
        }
        It 'throws an actionable error when the lightning dev plugin is missing' {
            Mock Invoke-Salesforce { return '[{"name":"@salesforce/plugin-apex"}]' }
            { Start-SalesforceLwcDevServer } | Should -Throw -ExpectedMessage "*Install-SalesforceLwcDevServer*"
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { ($Arguments -join '|') -like 'lightning|dev*' }
        }
        It 'installs the lightning dev plugin' {
            Install-SalesforceLwcDevServer | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|install|@salesforce/plugin-lightning-dev' }
        }
        It 'scaffolds a Jest test without calling sf' {
            $project = Join-Path $TestDrive 'my project'
            $lwc = Join-Path $project 'force-app/main/default/lwc/myComp'
            New-Item -ItemType Directory -Path $lwc -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $lwc 'myComp.js') -Value '// component'
            $file = New-SalesforceJestTest -LwcName myComp -ProjectPath $project
            $file.Name | Should -Be 'myComp.test.js'
            $text = Get-Content -LiteralPath $file.FullName -Raw
            $text | Should -Match "import myComp from 'c/myComp';"
            $text | Should -Match "createElement\('c-my-comp'"
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
        It 'refuses to overwrite an existing Jest test without -Force' {
            $project = Join-Path $TestDrive 'proj2'
            $lwc = Join-Path $project 'force-app/main/default/lwc/abc'
            New-Item -ItemType Directory -Path (Join-Path $lwc '__tests__') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $lwc 'abc.js') -Value '// component'
            Set-Content -LiteralPath (Join-Path $lwc '__tests__/abc.test.js') -Value 'old'
            { New-SalesforceJestTest -LwcName abc -ProjectPath $project } | Should -Throw -ExpectedMessage '*already exists*'
            New-SalesforceJestTest -LwcName abc -ProjectPath $project -Force | Out-Null
            (Get-Content -LiteralPath (Join-Path $lwc '__tests__/abc.test.js') -Raw) | Should -Match 'createElement'
        }
        It 'throws when the LWC component file is absent' {
            $project = Join-Path $TestDrive 'proj3'
            New-Item -ItemType Directory -Path $project -Force | Out-Null
            { New-SalesforceJestTest -LwcName missing -ProjectPath $project } | Should -Throw -ExpectedMessage '*does not exist*'
        }
        It 'sets project target org with equals syntax' {
            Set-SalesforceTargetOrg -Value 'user@example' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'config|set|target-org=user@example|--json' }
        }
        It 'removes project target org' {
            Remove-SalesforceTargetOrg | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'config|unset|target-org|--json' }
        }
        It 'removes project target org globally' {
            Remove-SalesforceTargetOrg -Global | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'config|unset|target-org|--global|--json' }
        }
        It 'sets default dev hub with equals syntax' {
            Set-SalesforceTargetDevHub -Value 'DevHubAlias' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'config|set|target-dev-hub=DevHubAlias|--json' }
        }
        It 'sets default dev hub globally' {
            Set-SalesforceTargetDevHub -Value 'DevHubAlias' -Global | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'config|set|target-dev-hub=DevHubAlias|--global|--json' }
        }
        It 'gets default dev hub' {
            Get-SalesforceTargetDevHub | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'config|get|target-dev-hub|--json' }
        }
        It 'gets default dev hub globally without passing --global, which sf config get does not accept' {
            Get-SalesforceTargetDevHub -Global | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'config|get|target-dev-hub|--json' }
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { ($Arguments -join '|') -like '*--global*' }
        }
        Context 'Get-SalesforceTargetOrg and Get-SalesforceTargetDevHub with -Global' {
            It 'returns the entry only when it is set globally' {
                Mock Invoke-Salesforce { '{"status":0,"result":[{"name":"target-org","value":"me@example.com","location":"Global","success":true}]}' }
                $r = @(Get-SalesforceTargetOrg -Global)
                $r.Count | Should -Be 1
                $r[0].value | Should -Be 'me@example.com'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'config|get|target-org|--json' }
            }
            It 'returns nothing when the value is only set locally' {
                Mock Invoke-Salesforce { '{"status":0,"result":[{"name":"target-dev-hub","value":"hub","location":"Local","success":true}]}' }
                @(Get-SalesforceTargetDevHub -Global).Count | Should -Be 0
            }
            It 'returns the entry whatever its location when -Global is not given' {
                Mock Invoke-Salesforce { '{"status":0,"result":[{"name":"target-org","value":"me@example.com","location":"Local","success":true}]}' }
                $r = @(Get-SalesforceTargetOrg)
                $r.Count | Should -Be 1
                $r[0].location | Should -Be 'Local'
            }
        }
        It 'removes default dev hub' {
            Remove-SalesforceTargetDevHub | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'config|unset|target-dev-hub|--json' }
        }
        It 'removes default dev hub globally' {
            Remove-SalesforceTargetDevHub -Global | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'config|unset|target-dev-hub|--global|--json' }
        }
    }
}

Describe 'Test-SalesforceApex command building' {
    InModuleScope 'psfdx-development' {
        BeforeEach {
            Mock Invoke-Salesforce {
                '{"status":0,"result":{"tests":[],"summary":{"outcome":"Passed","testRunCoverage":"100%"}}}'
            }
        }
        It 'runs specified class synchronously with target org and json' {
            Test-SalesforceApex -ClassName 'MyClass' -TargetOrg 'me' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { (($Arguments -join '|') -like 'apex|run|test|*') -and (($Arguments -join '|') -like '*|--tests|MyClass*') -and (($Arguments -join '|') -like '*|--target-org|me*') -and (($Arguments -join '|') -like '*|--result-format|json*') }
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
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -like "apex|run|test*|--output-dir|$($existing.FullName)*" }
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
                    $_.Exception.Message | Should -Be "No Apex test classes found in the project."
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
                    (($Arguments -join '|') -like 'apex|run|test|*') -and
                    (($Arguments -join '|') -like '*|--tests|first*') -and
                    (($Arguments -join '|') -like '*|--tests|second*')
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
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "apex|generate|class|--name|MyClass|--template|DefaultApexClass|--output-dir|$($existing.FullName)" }
            }
            finally {
                Remove-Item -LiteralPath $existing.FullName -Force -Recurse
            }
        }

        It 'passes an output directory with spaces as one argument' {
            Mock Invoke-Salesforce {}
            $dir = New-Item -Path (Join-Path $TestDrive 'my classes dir') -ItemType Directory
            New-SalesforceApexClass -Name 'MyClass' -OutputDirectory $dir.FullName
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Arguments.Count -eq 9 -and $Arguments[8] -eq $dir.FullName }
        }

        It 'omits output directory validation when not provided' {
            Mock Invoke-Salesforce {}
            Mock Test-Path { throw "Test-Path should not be called" }
            New-SalesforceApexClass -Name 'DefaultClass'
            $expected = 'apex|generate|class|--name|DefaultClass|--template|DefaultApexClass'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq $expected }
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
                $expected = "apex|generate|trigger|--name|MyTrigger|--event|before insert|--sobject|Account|--output-dir|$($existing.FullName)"
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq $expected }
            }
            finally {
                Remove-Item -LiteralPath $existing.FullName -Force -Recurse
            }
        }

        It 'passes an output directory with spaces as one argument' {
            Mock Invoke-Salesforce {}
            $dir = New-Item -Path (Join-Path $TestDrive 'my classes dir') -ItemType Directory
            New-SalesforceApexClass -Name 'MyClass' -OutputDirectory $dir.FullName
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Arguments.Count -eq 9 -and $Arguments[8] -eq $dir.FullName }
        }

        It 'omits output directory validation when not provided' {
            Mock Invoke-Salesforce {}
            Mock Test-Path { throw "Test-Path should not be called" }
            New-SalesforceApexTrigger -Name 'DefaultTrigger'
            $expected = 'apex|generate|trigger|--name|DefaultTrigger|--event|before insert'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq $expected }
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
                    return '{"status":0,"result":{"command":"deploy","details":{"tests":{"successes":[{"name":"SampleTest"}]}}}}'
                }
                Mock Get-SalesforceApexTestClassNames { param($FilePath,$ProjectFolder) return @('SampleTest') }

                $result = Watch-SalesforceApexAction -FilePath $file -ProjectFolder $tempRoot.FullName -IgnoreErrors

                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { (($Arguments -join '|') -like 'project|deploy|start|--metadata|ApexClass:Sample*') -and (($Arguments -join '|') -like '*--tests|SampleTest*') -and (($Arguments -join '|') -like '*--test-level|RunSpecifiedTests*') -and (($Arguments -join '|') -like '*--ignore-errors*') }
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
                    return '{"status":0,"result":{"command":"deploy"}}'
                }
                Mock Get-SalesforceApexTestClassNames { param($FilePath,$ProjectFolder) return @() }

                $result = Watch-SalesforceApexAction -FilePath $file -ProjectFolder $tempRoot.FullName
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { (($Arguments -join '|') -like 'project|deploy|start|--metadata|ApexTrigger:Sample*') -and (($Arguments -join '|') -notlike '*--tests*') -and (($Arguments -join '|') -notlike '*--ignore-errors*') }
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

Describe 'Test-SalesforceApexTestReference' {
    # Lives in psfdx-shared, which is imported into the psfdx-development module scope
    InModuleScope 'psfdx-development' {
        It 'does not treat a substring match as a reference' {
            # 'AccountHelperTest' contains 'Account' but tests AccountHelper, not Account
            $dir = Join-Path $TestDrive 'classes'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $file = Join-Path $dir 'AccountHelperTest.cls'
            Set-Content -Path $file -Value '@isTest public class AccountHelperTest { AccountHelper h; }' -Encoding UTF8

            Test-SalesforceApexTestReference -Path $file -ClassName 'Account'       | Should -BeFalse
            Test-SalesforceApexTestReference -Path $file -ClassName 'AccountHelper' | Should -BeTrue
        }

        It 'matches the <Class>Test / <Class>Tests / Test<Class> naming conventions' {
            $dir = Join-Path $TestDrive 'conv'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            foreach ($name in 'SampleTest', 'SampleTests', 'TestSample') {
                $file = Join-Path $dir "$name.cls"
                Set-Content -Path $file -Value "@isTest public class $name {}" -Encoding UTF8
                Test-SalesforceApexTestReference -Path $file -ClassName 'Sample' | Should -BeTrue -Because "$name follows the convention"
            }
        }

        It 'matches a whole-word reference in the test body' {
            $dir = Join-Path $TestDrive 'body'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $file = Join-Path $dir 'SomeOtherSuite.cls'
            Set-Content -Path $file -Value '@isTest public class SomeOtherSuite { Order o = Order.build(); }' -Encoding UTF8
            Test-SalesforceApexTestReference -Path $file -ClassName 'Order'    | Should -BeTrue
            Test-SalesforceApexTestReference -Path $file -ClassName 'OrderXyz' | Should -BeFalse
        }
    }
}

Describe 'Get-SalesforceApexTestClassNamesFromFile false positives' {
    InModuleScope 'psfdx-development' {
        It 'excludes a test class that merely shares a name prefix' {
            $root = Join-Path $TestDrive 'force-app'
            $classes = Join-Path $root 'classes'
            New-Item -ItemType Directory -Path $classes -Force | Out-Null
            Set-Content -Path (Join-Path $classes 'Account.cls') -Value 'public class Account {}' -Encoding UTF8
            Set-Content -Path (Join-Path $classes 'AccountHelperTest.cls') -Value '@isTest public class AccountHelperTest { AccountHelper h; }' -Encoding UTF8

            $result = Get-SalesforceApexTestClassNamesFromFile -FilePath (Join-Path $classes 'Account.cls')
            @($result) | Should -Not -Contain 'AccountHelperTest'
        }
    }
}

Describe 'Watcher helpers tolerate missing files' {
    InModuleScope 'psfdx-development' {
        It 'Get-SalesforceType returns empty for a null file name' {
            Get-SalesforceType -FileName $null | Should -Be ''
        }
        It 'Get-SalesforceName parses the path without touching the filesystem' {
            # The watcher also fires for files already renamed or deleted
            Get-SalesforceName -FileName (Join-Path $TestDrive 'never-existed\Deleted.cls') | Should -Be 'Deleted'
        }
    }
}

Describe 'Test-SalesforceApex with an unusable CLI response' {
    InModuleScope 'psfdx-development' {
        It 'reports a missing summary instead of a null method call' {
            Mock Invoke-Salesforce { '{"status":0,"result":{}}' }
            { Test-SalesforceApex -ClassName 'Foo' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*no test summary*'
        }
    }
}

Describe 'New-SalesforceProject -DefaultUserName' {
    InModuleScope 'psfdx-development' {
        It 'sets the target org by value from inside the generated project' {
            $work = Join-Path $TestDrive 'work'
            $project = Join-Path $work 'DemoProj'
            New-Item -ItemType Directory -Path $project -Force | Out-Null

            Mock Invoke-Salesforce { '{"status":0,"result":{"outputDir":"' + ($work -replace '\\', '\\') + '"}}' }
            Mock Set-SalesforceTargetOrg { }

            New-SalesforceProject -Name 'DemoProj' -DefaultUserName 'me@example.com' | Out-Null

            # -Value is the only parameter Set-SalesforceTargetOrg accepts; the old code
            # passed -DefaultUserName/-ProjectFolder and always failed to bind.
            Assert-MockCalled Set-SalesforceTargetOrg -Times 1 -ParameterFilter { $Value -eq 'me@example.com' }
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
        It 'escapes the name in the query' {
            Get-SalesforceApexClass -Name "My'Class\" -TargetOrg 'me' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName 'psfdx' -ParameterFilter {
                $Command -eq 'sf data query --query "SELECT Id, Name, Body FROM ApexClass WHERE Name = ''My\''Class\\'' LIMIT 1" --target-org me --use-tooling-api --result-format json'
            }
        }
        It 'refuses a control character in the name and runs nothing' {
            { Get-SalesforceApexClass -Name ('a' + [char]1) } | Should -Throw -ExpectedMessage '*control character*'
            Assert-MockCalled Invoke-Salesforce -Times 0 -ModuleName 'psfdx'
        }
    }
}
