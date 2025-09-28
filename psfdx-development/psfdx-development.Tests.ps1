# Ensure clean slate and load local dependency module first
Get-Module -Name 'psfdx-development','psfdx-metadata' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

# Import local psfdx-metadata so RequiredModules resolves from repo
$metadataManifest = Join-Path -Path $PSScriptRoot -ChildPath '..\psfdx-metadata\psfdx-metadata.psd1'
Import-Module $metadataManifest -Force | Out-Null

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
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf lightning lwc start' }
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
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Command -like 'sf apex run test *') -and ($Command -like '* --class-names MyClass*') -and ($Command -like '* --target-org me*') -and ($Command -like '* --result-format json*') }
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
                $currentPath = (Get-Location).Path
                $threw = $false
                try {
                    Test-SalesforceApex -TestsInProject | Out-Null
                }
                catch {
                    $threw = $true
                    $_.Exception.Message | Should -Be "No Apex test classes found in '$currentPath'."
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
