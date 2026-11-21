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
                ($Arguments -join '|') -eq 'data|query|--query|SELECT Id, Name, Body FROM ApexClass WHERE Name = ''My\''Class\\'' LIMIT 1|--target-org|me|--use-tooling-api|--result-format|json'
            }
        }
        It 'refuses a control character in the name and runs nothing' {
            { Get-SalesforceApexClass -Name ('a' + [char]1) } | Should -Throw -ExpectedMessage '*control character*'
            Assert-MockCalled Invoke-Salesforce -Times 0 -ModuleName 'psfdx'
        }
    }
}

Describe 'Scratch org deletion safety' {
    InModuleScope 'psfdx-development' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{}}' }
        }

        It 'Remove-SalesforceScratchOrg runs nothing under -WhatIf' {
            Remove-SalesforceScratchOrg -TargetOrg 'so1' -WhatIf
            Assert-MockCalled Invoke-Salesforce -Times 0
        }

        It 'Remove-SalesforceScratchOrg deletes with -Confirm:$false and keeps --no-prompt' {
            Remove-SalesforceScratchOrg -TargetOrg 'so1' -NoPrompt -Confirm:$false
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'org|delete|scratch|--target-org|so1|--no-prompt'
            }
        }

        Context 'Remove-SalesforceScratchOrgs' {
            BeforeEach {
                Mock Get-SalesforceScratchOrgs { @([pscustomobject]@{ username = 'a@x.com' }, [pscustomobject]@{ username = 'b@x.com' }) }
            }

            It 'runs nothing under -WhatIf' {
                Remove-SalesforceScratchOrgs -WhatIf
                Assert-MockCalled Invoke-Salesforce -Times 0
            }

            It 'deletes each org once with -Confirm:$false' {
                Remove-SalesforceScratchOrgs -Confirm:$false
                Assert-MockCalled Invoke-Salesforce -Times 2
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'org|delete|scratch|--target-org|a@x.com|--no-prompt' }
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'org|delete|scratch|--target-org|b@x.com|--no-prompt' }
            }

            It 'does nothing when there are no scratch orgs' {
                Mock Get-SalesforceScratchOrgs { @() }
                Remove-SalesforceScratchOrgs -Confirm:$false
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
        }
    }
}

# SOQL builder and `sf data query --json` regression coverage (#172).
# Fixtures are sanitised copies of real `sf data query --json` output shapes: no tokens, no real org data.
Describe 'psfdx-development SOQL regression' {
    InModuleScope 'psfdx-development' {
        BeforeAll {
            $script:Empty = '{"status":0,"result":{"records":[],"totalSize":0,"done":true},"warnings":[]}'
            $script:NoAuth = '{"name":"NoAuthFoundError","message":"No authorization information found for nobody@example.com.","exitCode":1,"status":1,"warnings":[]}'
            $script:Malformed = '{"name":"MALFORMED_QUERY","message":"\nSELECT Id FROM\n          ^\nERROR at Row:1:Column:11\nunexpected token: FROM","exitCode":1,"status":1,"warnings":[]}'
        }

        Context 'Get-SalesforceApexClass' {
            It 'escapes the name <Name>' -ForEach @(
                @{ Name = 'apostrophe'; Value = "My'Class";         Literal = "'My\'Class'" }
                @{ Name = 'backslash';  Value = 'My\Class';         Literal = "'My\\Class'" }
                @{ Name = 'injection';  Value = "x' OR Name != '";  Literal = "'x\' OR Name != \''" }
                @{ Name = 'unicode';    Value = 'Klasse日本';         Literal = "'Klasse日本'" }
                @{ Name = 'percent';    Value = '100%_Class';       Literal = "'100%_Class'" }
            ) {
                Mock Invoke-Salesforce { $script:Empty } -ModuleName 'psfdx'
                Get-SalesforceApexClass -Name $Value | Out-Null
                $expected = "data|query|--query|SELECT Id, Name, Body FROM ApexClass WHERE Name = $Literal LIMIT 1|--use-tooling-api|--result-format|json"
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName 'psfdx' -ParameterFilter { ($Arguments -join '|') -eq $expected }
            }

            It 'returns nothing for zero records' {
                Mock Invoke-Salesforce { $script:Empty } -ModuleName 'psfdx'
                @(Get-SalesforceApexClass -Name 'Nope').Count | Should -Be 0
            }

            It 'throws the CLI message on an authentication error' {
                Mock Invoke-Salesforce { $script:NoAuth } -ModuleName 'psfdx'
                { Get-SalesforceApexClass -Name 'A' -TargetOrg 'nobody@example.com' } | Should -Throw -ExpectedMessage '*No authorization information found*'
            }
        }

        Context 'Get-SalesforceCodeCoverage' {
            It 'queries ApexCodeCoverage through the tooling API' {
                Mock Invoke-Salesforce { $script:Empty } -ModuleName 'psfdx'
                Get-SalesforceCodeCoverage -TargetOrg 'me' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName 'psfdx' -ParameterFilter {
                    ($Arguments -join '|') -eq 'data|query|--query|SELECT ApexTestClass.Name, TestMethodName, ApexClassOrTrigger.Name, NumLinesUncovered, NumLinesCovered, Coverage FROM ApexCodeCoverage |--target-org|me|--use-tooling-api|--result-format|json'
                }
            }

            It 'returns nothing for zero records' {
                Mock Invoke-Salesforce { $script:Empty } -ModuleName 'psfdx'
                @(Get-SalesforceCodeCoverage).Count | Should -Be 0
            }

            It 'throws the CLI message for a malformed query' {
                Mock Invoke-Salesforce { $script:Malformed } -ModuleName 'psfdx'
                { Get-SalesforceCodeCoverage } | Should -Throw -ExpectedMessage '*unexpected token: FROM*'
            }

            It 'throws the CLI message on an authentication error' {
                Mock Invoke-Salesforce { $script:NoAuth } -ModuleName 'psfdx'
                { Get-SalesforceCodeCoverage -TargetOrg 'nobody@example.com' } | Should -Throw -ExpectedMessage '*No authorization information found*'
            }
        }
    }
}

Describe 'Flow and logic test commands' {
    InModuleScope 'psfdx-development' {
        BeforeAll {
            $script:Passed = '{"status":0,"result":{"summary":{"outcome":"Passed","testsRan":2,"passing":2,"failing":0,"skipped":0},"tests":[{"FullName":"Flow1.Test1","Outcome":"Pass"},{"FullName":"Flow1.Test2","Outcome":"Pass"}]}}'
            $script:Failed = '{"status":100,"result":{"summary":{"outcome":"Failed","testsRan":2,"passing":1,"failing":1,"skipped":0},"tests":[{"FullName":"Flow1.Test1","Outcome":"Pass"},{"FullName":"Flow1.Test2","Outcome":"Fail"}]}}'
            $script:Queued = '{"status":0,"result":{"testRunId":"707xx0000000001AAA"}}'
            $script:RunId = '707xx0000000001'
        }
        BeforeEach {
            $script:Reply = $script:Passed
            Mock Invoke-Salesforce { $script:Reply }
        }

        Context 'Test-SalesforceFlow arguments' {
            It 'builds the exact command for named flows, level and org' {
                Test-SalesforceFlow -FlowName 'Flow1', 'Flow2' -TestLevel RunSpecifiedTests -TargetOrg me | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'flow|run|test|--class-names|Flow1|--class-names|Flow2|--test-level|RunSpecifiedTests|--target-org|me|--result-format|json|--json' }
            }
            It 'builds the exact command for specific tests, synchronously with coverage and concise output' {
                Test-SalesforceFlow -TestName 'Flow1.Test1' -Synchronous -CodeCoverage -Concise | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'flow|run|test|--tests|Flow1.Test1|--synchronous|--concise|--code-coverage|--result-format|json' }
            }
            It 'runs the local tests with no selection and does not add --target-org' {
                Test-SalesforceFlow | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'flow|run|test|--result-format|json|--json' }
            }
            It 'passes names with spaces and quotes as single arguments' {
                Test-SalesforceFlow -SuiteName "My Suite's `"x`"" | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { $Arguments -contains "My Suite's `"x`"" }
            }
            It 'writes text formats through unchanged and does not ask for --json' {
                $script:Reply = '<testsuites/>'
                $out = Test-SalesforceFlow -ResultFormat junit
                $out | Should -Be '<testsuites/>'
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'flow|run|test|--result-format|junit' }
            }
            It 'checks the output directory exists' {
                $missing = Join-Path $TestDrive 'nope'
                { Test-SalesforceFlow -OutputDirectory $missing } | Should -Throw -ExpectedMessage '*does not exist*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'passes an existing output directory' {
                $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'out') -Force
                Test-SalesforceFlow -OutputDirectory $dir.FullName | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { $Arguments -contains '--output-dir' -and $Arguments -contains $dir.FullName }
            }
            It 'rejects <Case> without calling the CLI' -ForEach @(
                @{ Case = 'flows with suites';          Splat = @{ FlowName = 'F'; SuiteName = 'S' };                       Message = '*only one of*' }
                @{ Case = 'tests with flows';           Splat = @{ FlowName = 'F'; TestName = 'F.T' };                      Message = '*only one of*' }
                @{ Case = 'a named flow at another level'; Splat = @{ FlowName = 'F'; TestLevel = 'RunLocalTests' };        Message = '*needs -TestLevel RunSpecifiedTests*' }
                @{ Case = 'a synchronous suite';        Splat = @{ SuiteName = 'S'; Synchronous = $true };                  Message = '*only one flow*' }
                @{ Case = 'a synchronous run of two flows'; Splat = @{ FlowName = 'A', 'B'; Synchronous = $true };          Message = '*only one flow*' }
                @{ Case = 'an unknown test level';      Splat = @{ TestLevel = 'RunEverything' };                           Message = '*RunEverything*' }
            ) {
                $params = $Splat
                { Test-SalesforceFlow @params } | Should -Throw -ExpectedMessage $Message
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'results: finished, asynchronous, failed and not run' {
            It 'returns the tests of a passing run' {
                $res = Test-SalesforceFlow -FlowName Flow1 -Synchronous
                $res.Summary.outcome | Should -Be 'Passed'
                $res.Tests.Count | Should -Be 2
                $res.Tests[0].FullName | Should -Be 'Flow1.Test1'
            }
            It 'returns the coverage when the CLI reports it' {
                $script:Reply = '{"status":0,"result":{"summary":{"outcome":"Passed","testsRan":1,"failing":0,"testRunId":"707xx0000000009","testRunCoverage":"82%"},"tests":[],"coverage":{"coverage":[{"name":"Flow1","coveredPercent":82}]}}}'
                $res = Test-SalesforceFlow -FlowName Flow1 -Synchronous -CodeCoverage
                $res.Coverage.coverage[0].name | Should -Be 'Flow1'
                $res.Summary.testRunCoverage | Should -Be '82%'
                $res.TestRunId | Should -Be '707xx0000000009'
                $script:Reply = $script:Passed
                (Test-SalesforceFlow -FlowName Flow1 -Synchronous).Coverage | Should -BeNullOrEmpty
            }
            It 'does not ask for --json on a synchronous run, because the CLI then returns a run ID at once' {
                Test-SalesforceFlow -Synchronous -TestLevel RunLocalTests | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'flow|run|test|--test-level|RunLocalTests|--synchronous|--result-format|json' }
                Test-SalesforceFlow -TestLevel RunLocalTests | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'flow|run|test|--test-level|RunLocalTests|--result-format|json|--json' }
            }
            It 'returns the test run ID of an asynchronous run' {
                $script:Reply = $script:Queued
                $res = Test-SalesforceFlow
                $res.TestRunId | Should -Be '707xx0000000001AAA'
            }
            It 'writes the tests, then throws PsfdxTestsFailed with the summary, for failing tests' {
                $script:Reply = $script:Failed
                $emitted = @()
                $err = $null
                try { $emitted = @(Test-SalesforceFlow -FlowName Flow1 -Synchronous) } catch { $err = $_ }
                $err | Should -Not -BeNullOrEmpty
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxTestsFailed'
                $err.Exception.Message | Should -BeLike '*1 failing of 2 run*'
                $err.TargetObject.failing | Should -Be 1
            }
            It 'throws PsfdxTestRunInvocationFailed, not a test failure, when the command could not run' {
                $script:Reply = '{"status":1,"name":"NamedOrgNotFoundError","message":"No authorization information found for nobody."}'
                $err = $null
                try { Test-SalesforceFlow -TargetOrg nobody | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxTestRunInvocationFailed'
                $err.Exception.Message | Should -BeLike '*No authorization information found*'
            }
            It 'explains how to install a missing plugin' {
                $script:Reply = '{"status":1,"name":"CommandNotFound","message":"flow run test is not a sf command."}'
                { Test-SalesforceFlow } | Should -Throw -ExpectedMessage "*sf plugins install @salesforce/plugin-flow*"
            }
            It 'rejects empty output' {
                $script:Reply = ''
                { Test-SalesforceFlow } | Should -Throw -ExpectedMessage '*returned no output*'
            }
            It 'rejects output that is not JSON' {
                $script:Reply = 'Warning: something odd'
                { Test-SalesforceFlow } | Should -Throw -ExpectedMessage '*not valid JSON*'
            }
        }

        Context 'Get-SalesforceFlowTestResult' {
            It 'builds the exact command' {
                Get-SalesforceFlowTestResult -TestRunId $script:RunId -CodeCoverage -CodeCoverageDetailed -Concise -TargetOrg me | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'flow|get|test|--test-run-id|707xx0000000001|--concise|--code-coverage|--detailed-coverage|--target-org|me|--result-format|json|--json' }
            }
            It 'returns the tests, and throws PsfdxTestsFailed when they failed' {
                (Get-SalesforceFlowTestResult -TestRunId $script:RunId).Tests.Count | Should -Be 2
                $script:Reply = $script:Failed
                $err = $null
                try { Get-SalesforceFlowTestResult -TestRunId $script:RunId | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxTestsFailed'
            }
            It 'rejects a malformed run ID and a detailed coverage request without coverage' {
                { Get-SalesforceFlowTestResult -TestRunId '001xx0000000001' } | Should -Throw
                { Get-SalesforceFlowTestResult -TestRunId "707xx0000000001; calc" } | Should -Throw
                { Get-SalesforceFlowTestResult -TestRunId $script:RunId -CodeCoverageDetailed } | Should -Throw -ExpectedMessage '*needs -CodeCoverage*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Test-SalesforceLogic' {
            It 'builds the exact command for both categories, waiting' {
                Test-SalesforceLogic -TestCategory Apex, Flow -TestLevel RunLocalTests -WaitMinutes 10 -TargetOrg me | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'logic|run|test|--test-category|Apex|--test-category|Flow|--test-level|RunLocalTests|--wait|10|--target-org|me|--result-format|json|--json' }
            }
            It 'builds the exact command for a mixed list of Apex and Flow tests, synchronously' {
                Test-SalesforceLogic -TestName 'OrderFlow.Test1', 'OrderTest.testSave' -Synchronous -CodeCoverage -CodeCoverageDetailed | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'logic|run|test|--tests|OrderFlow.Test1|--tests|OrderTest.testSave|--synchronous|--code-coverage|--detailed-coverage|--result-format|json' }
            }
            It 'sends --wait 0 when asked' {
                Test-SalesforceLogic -WaitMinutes 0 | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'logic|run|test|--wait|0|--result-format|json|--json' }
            }
            It 'returns an asynchronous run ID, mixed results, and a failed-test error' {
                $script:Reply = $script:Queued
                (Test-SalesforceLogic).TestRunId | Should -Be '707xx0000000001AAA'
                $script:Reply = $script:Passed
                (Test-SalesforceLogic -Synchronous).Tests.Count | Should -Be 2
                $script:Reply = $script:Failed
                $err = $null
                try { Test-SalesforceLogic -Synchronous | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxTestsFailed'
            }
            It 'reports a missing plugin with the apex plugin name' {
                $script:Reply = '{"status":1,"message":"logic run test is not a sf command."}'
                { Test-SalesforceLogic } | Should -Throw -ExpectedMessage '*sf plugins install @salesforce/plugin-apex*'
            }
            It 'rejects <Case> without calling the CLI' -ForEach @(
                @{ Case = 'a category without a test level'; Splat = @{ TestCategory = 'Flow' };                    Message = '*-TestCategory needs -TestLevel*' }
                @{ Case = 'a synchronous run of two classes'; Splat = @{ ClassName = 'A', 'B'; Synchronous = $true }; Message = '*only one class or flow*' }
                @{ Case = 'two selectors';                 Splat = @{ ClassName = 'C'; TestCategory = 'Flow'; TestLevel = 'RunSpecifiedTests' };         Message = '*only one of*' }
                @{ Case = 'a class at another level';      Splat = @{ ClassName = 'C'; TestLevel = 'RunAllTestsInOrg' }; Message = '*needs -TestLevel RunSpecifiedTests*' }
                @{ Case = 'detailed coverage alone';       Splat = @{ CodeCoverageDetailed = $true };                   Message = '*needs -CodeCoverage*' }
                @{ Case = 'an unknown category';           Splat = @{ TestCategory = 'Lightning' };                     Message = '*Lightning*' }
                @{ Case = 'a negative wait';               Splat = @{ WaitMinutes = -1 };                               Message = '*-1*' }
            ) {
                $params = $Splat
                { Test-SalesforceLogic @params } | Should -Throw -ExpectedMessage $Message
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Get-SalesforceLogicTestResult' {
            It 'builds the exact command' {
                Get-SalesforceLogicTestResult -TestRunId $script:RunId -TargetOrg me | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'logic|get|test|--test-run-id|707xx0000000001|--target-org|me|--result-format|json|--json' }
            }
            It 'throws PsfdxTestRunInvocationFailed for an invalid run' {
                $script:Reply = '{"status":1,"message":"The requested resource does not exist"}'
                $err = $null
                try { Get-SalesforceLogicTestResult -TestRunId $script:RunId | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxTestRunInvocationFailed'
            }
        }

        Context 'module surface' {
            It 'exports the four commands from the manifest, and keeps the helper private' {
                $exports = (Import-PowerShellDataFile -Path (Join-Path (Get-Module -Name psfdx-development).ModuleBase 'psfdx-development.psd1')).FunctionsToExport
                $exports | Should -Contain 'Test-SalesforceFlow'
                $exports | Should -Contain 'Get-SalesforceFlowTestResult'
                $exports | Should -Contain 'Test-SalesforceLogic'
                $exports | Should -Contain 'Get-SalesforceLogicTestResult'
                $exports | Should -Not -Contain 'ConvertFrom-SalesforceTestRunOutput'
            }
            It 'has help examples' {
                foreach ($name in 'Test-SalesforceFlow', 'Get-SalesforceFlowTestResult', 'Test-SalesforceLogic', 'Get-SalesforceLogicTestResult') {
                    @((Get-Help $name -Examples).examples.example).Count | Should -BeGreaterThan 0
                }
            }
            It 'does not change Test-SalesforceApex' {
                Test-SalesforceApex -ClassName C -TargetOrg me | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -like 'apex|run|test|*' }
            }
        }
    }
}

Describe 'Apex test run lifecycle' {
    InModuleScope 'psfdx-development' {
        BeforeAll {
            $script:RunId = '707xx0000000001'
            $script:Queued = '{"status":0,"result":{"testRunId":"707xx0000000001AAA"}}'
            $script:Passed = '{"status":0,"result":{"summary":{"outcome":"Passed","testsRan":2,"passing":2,"failing":0,"skipped":0,"testRunId":"707xx0000000001AAA","testTotalTime":"120 ms"},"tests":[{"FullName":"MyTest.a","Outcome":"Pass","RunTime":40},{"FullName":"MyTest.b","Outcome":"Pass","RunTime":80}]}}'
            $script:Failed = '{"status":100,"result":{"summary":{"outcome":"Failed","testsRan":2,"passing":1,"failing":1,"skipped":0,"testRunId":"707xx0000000001AAA"},"tests":[{"FullName":"MyTest.a","Outcome":"Pass","RunTime":40},{"FullName":"MyTest.b","Outcome":"Fail","RunTime":80,"Message":"System.AssertException: expected 1","StackTrace":"Class.MyTest.b: line 9"}]}}'
            $script:Running = '{"status":0,"result":{"summary":{"outcome":"Processing","testsRan":1,"passing":1,"failing":0,"skipped":0,"testRunId":"707xx0000000001AAA"},"tests":[{"FullName":"MyTest.a","Outcome":"Pass","RunTime":40}]}}'
        }
        BeforeEach {
            $script:Replies = @($script:Passed)
            $script:Calls = 0
            Mock Invoke-Salesforce {
                $i = [math]::Min($script:Calls, $script:Replies.Count - 1)
                $script:Calls++
                $script:Replies[$i]
            }
            Mock Start-Sleep { }
        }

        Context 'Start-SalesforceApexTest' {
            It 'builds the exact command for classes and returns the run ID without waiting' {
                $script:Replies = @($script:Queued)
                $res = Start-SalesforceApexTest -ClassName MyTest, OtherTest -TestLevel RunSpecifiedTests -TargetOrg me
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'apex|run|test|--class-names|MyTest|--class-names|OtherTest|--test-level|RunSpecifiedTests|--target-org|me|--result-format|json|--json' }
                $res.TestRunId | Should -Be '707xx0000000001AAA'
                $res.Completed | Should -BeFalse
            }
            It 'builds the command for specific tests, a suite, and the local tests' {
                $script:Replies = @($script:Queued)
                Start-SalesforceApexTest -TestName 'MyTest.a' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'apex|run|test|--tests|MyTest.a|--result-format|json|--json' }
                Start-SalesforceApexTest -SuiteName Smoke | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'apex|run|test|--suite-names|Smoke|--result-format|json|--json' }
                Start-SalesforceApexTest | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'apex|run|test|--result-format|json|--json' }
            }
            It 'rejects <Case> without calling the CLI' -ForEach @(
                @{ Case = 'two kinds of selection';  Run = { Start-SalesforceApexTest -ClassName A -SuiteName B };                       Message = '*only one of*' }
                @{ Case = 'a class at another level'; Run = { Start-SalesforceApexTest -ClassName A -TestLevel RunLocalTests };          Message = '*needs -TestLevel RunSpecifiedTests*' }
                @{ Case = 'an unknown level';         Run = { Start-SalesforceApexTest -TestLevel RunEverything };                       Message = '*RunEverything*' }
            ) {
                { & $Run } | Should -Throw -ExpectedMessage $Message
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'fails when the CLI returns no run ID, or an error' {
                $script:Replies = @('{"status":0,"result":{}}')
                { Start-SalesforceApexTest } | Should -Throw
                $script:Calls = 0
                $script:Replies = @('{"status":1,"name":"NamedOrgNotFoundError","message":"No authorization information found for nobody."}')
                $err = $null
                try { Start-SalesforceApexTest -TargetOrg nobody } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxTestRunInvocationFailed'
            }
        }

        Context 'Get-SalesforceApexTestResult' {
            It 'builds the exact command and returns per-test outcome and run time' {
                $res = Get-SalesforceApexTestResult -TestRunId $script:RunId -CodeCoverage -CodeCoverageDetailed -Concise -TargetOrg me
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'apex|get|test|--test-run-id|707xx0000000001|--concise|--code-coverage|--detailed-coverage|--target-org|me|--result-format|json|--json' }
                $res.Completed | Should -BeTrue
                $res.Summary.outcome | Should -Be 'Passed'
                $res.Tests.Count | Should -Be 2
                $res.Tests[1].RunTime | Should -Be 80
                $res.Tests[0].Outcome | Should -Be 'Pass'
            }
            It 'returns coverage when the CLI reports it' {
                $script:Replies = @('{"status":0,"result":{"summary":{"outcome":"Passed","testsRan":1,"failing":0,"testRunId":"707xx0000000001AAA","testRunCoverage":"85%"},"tests":[],"coverage":{"coverage":[{"name":"MyClass","coveredPercent":85}]}}}')
                $res = Get-SalesforceApexTestResult -TestRunId $script:RunId -CodeCoverage
                $res.Coverage.coverage[0].name | Should -Be 'MyClass'
                $res.Summary.testRunCoverage | Should -Be '85%'
            }
            It 'writes the results and then throws PsfdxTestsFailed for failing tests, with message and stack trace available' {
                $script:Replies = @($script:Failed)
                $err = $null
                try { Get-SalesforceApexTestResult -TestRunId $script:RunId | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxTestsFailed'
                $err.TargetObject.failing | Should -Be 1
                $err.Exception.Message | Should -BeLike '*1 failing of 2*'
            }
            It 'returns Completed = false, without throwing, for a run still processing' {
                $script:Replies = @($script:Running)
                $res = Get-SalesforceApexTestResult -TestRunId $script:RunId
                $res.Completed | Should -BeFalse
                $res.Summary.outcome | Should -Be 'Processing'
            }
            It 'throws PsfdxTestRunInvocationFailed for an unknown run and for malformed output' {
                $script:Replies = @('{"status":1,"message":"The requested resource does not exist"}')
                $err = $null
                try { Get-SalesforceApexTestResult -TestRunId $script:RunId | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxTestRunInvocationFailed'
                $script:Calls = 0
                $script:Replies = @('not json')
                { Get-SalesforceApexTestResult -TestRunId $script:RunId } | Should -Throw -ExpectedMessage '*not valid JSON*'
                $script:Calls = 0
                $script:Replies = @('{"status":0,"result":{"unexpected":true}}')
                { Get-SalesforceApexTestResult -TestRunId $script:RunId } | Should -Throw
            }
            It 'rejects a malformed run ID, missing output directory and detailed coverage alone without calling the CLI' {
                { Get-SalesforceApexTestResult -TestRunId '001xx0000000001' } | Should -Throw
                { Get-SalesforceApexTestResult -TestRunId '707xx0000000001; calc' } | Should -Throw
                { Get-SalesforceApexTestResult -TestRunId $script:RunId -OutputDirectory (Join-Path $TestDrive 'nope') } | Should -Throw -ExpectedMessage '*does not exist*'
                { Get-SalesforceApexTestResult -TestRunId $script:RunId -CodeCoverageDetailed } | Should -Throw -ExpectedMessage '*needs -CodeCoverage*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Wait-SalesforceApexTest' {
            It 'polls until the run finishes and returns the results' {
                $script:Replies = @($script:Running, $script:Running, $script:Passed)
                $res = Wait-SalesforceApexTest -TestRunId $script:RunId -TimeoutMinutes 5 -PollSeconds 10 -TargetOrg me
                $res.Completed | Should -BeTrue
                $res.Tests.Count | Should -Be 2
                Assert-MockCalled Invoke-Salesforce -Times 3 -Exactly
                Assert-MockCalled Start-Sleep -Times 2 -Exactly -ParameterFilter { $Seconds -eq 10 }
            }
            It 'passes coverage options and the org to every poll' {
                $script:Replies = @($script:Running, $script:Passed)
                Wait-SalesforceApexTest -TestRunId $script:RunId -CodeCoverage -TargetOrg me | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 2 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'apex|get|test|--test-run-id|707xx0000000001|--code-coverage|--target-org|me|--result-format|json|--json' }
            }
            It 'throws PsfdxTestRunTimeout, with the run ID, when the run does not finish in time' {
                $script:Replies = @($script:Running)
                $err = $null
                try { Wait-SalesforceApexTest -TestRunId $script:RunId -TimeoutMinutes 1 -PollSeconds 30 | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxTestRunTimeout'
                $err.TargetObject | Should -Be $script:RunId
                Assert-MockCalled Invoke-Salesforce -Times 2 -Exactly
                Assert-MockCalled Start-Sleep -Times 1 -Exactly
            }
            It 'throws PsfdxTestsFailed straight away when the finished run has failures' {
                $script:Replies = @($script:Running, $script:Failed)
                $err = $null
                try { Wait-SalesforceApexTest -TestRunId $script:RunId | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxTestsFailed'
            }
            It 'rejects out-of-range waits and a malformed run ID without calling the CLI' {
                { Wait-SalesforceApexTest -TestRunId $script:RunId -TimeoutMinutes 0 } | Should -Throw
                { Wait-SalesforceApexTest -TestRunId $script:RunId -PollSeconds 0 } | Should -Throw
                { Wait-SalesforceApexTest -TestRunId 'abc' } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'compatibility and surface' {
            It 'leaves Test-SalesforceApex as it was' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"summary":{"outcome":"Passed","testsRan":1,"failing":0},"tests":[{"FullName":"A.b","Outcome":"Pass"}]}}' }
                $res = @(Test-SalesforceApex -ClassName MyTest -TargetOrg me)
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'apex|run|test|--tests|MyTest|--wait|10|--target-org|me|--result-format|json' }
                $res[0].FullName | Should -Be 'A.b'
                Mock Invoke-Salesforce { '{"status":100,"result":{"summary":{"outcome":"Failed","failing":2,"testsRan":3},"tests":[]}}' }
                { Test-SalesforceApex -ClassName MyTest } | Should -Throw -ExpectedMessage '2 Tests Failed'
            }
            It 'exports the three commands and has help examples, including the start-now-read-later one' {
                $exports = (Import-PowerShellDataFile -Path (Join-Path (Get-Module -Name psfdx-development).ModuleBase 'psfdx-development.psd1')).FunctionsToExport
                foreach ($name in 'Start-SalesforceApexTest', 'Get-SalesforceApexTestResult', 'Wait-SalesforceApexTest') {
                    $exports | Should -Contain $name
                    @((Get-Help $name -Examples).examples.example).Count | Should -BeGreaterThan 0
                }
                ((Get-Help Start-SalesforceApexTest -Examples | Out-String)) | Should -BeLike '*Later, in another shell*'
            }
            It 'tells Flow users where the Flow commands are' {
                (Get-Help Get-SalesforceApexTestResult).description.Text -join ' ' | Should -Not -BeNullOrEmpty
                (Get-Content -LiteralPath (Join-Path (Get-Module -Name psfdx-development).ModuleBase 'psfdx-development.psm1') -Raw) | Should -BeLike '*Test-SalesforceFlow and Test-SalesforceLogic (#191)*'
            }
        }
    }
}
