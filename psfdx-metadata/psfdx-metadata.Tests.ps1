<#
Pester unit tests for psfdx-metadata module

Run with:

pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path . -CI"
#>

# Ensure clean slate and load module locally
Get-Module -Name 'psfdx-metadata' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-metadata.psd1'
Import-Module $moduleManifest -Force | Out-Null

Describe 'Retrieve-SalesforceComponent' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            # -Type is validated against the org's metadata types; fall back to the built-in list instead
            Clear-SalesforceMetadataTypeCache
            Mock Describe-SalesforceMetadataTypes { @() }
            Mock Invoke-Salesforce {}
        }
        It 'retrieves a metadata type' {
            Retrieve-SalesforceComponent -Type 'ApexClass' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project retrieve start --metadata ApexClass' }
        }
        It 'retrieves a named component with target org' {
            Retrieve-SalesforceComponent -Type 'ApexClass' -Name 'MyClass' -TargetOrg 'me' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project retrieve start --metadata ApexClass:MyClass --target-org me' }
        }
        It 'appends child name to named component' {
            Retrieve-SalesforceComponent -Type 'CustomField' -Name 'Account' -ChildName 'MyField__c' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project retrieve start --metadata CustomField:Account.MyField__c' }
        }
        It 'throws when ChildName is used without Name' {
            { Retrieve-SalesforceComponent -Type 'CustomField' -ChildName 'MyField__c' } | Should -Throw -ExpectedMessage 'Specify -Name when using -ChildName.'
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { $Command -like 'sf project retrieve start*' }
        }
        It 'adds wait and ignore conflicts flags' {
            Retrieve-SalesforceComponent -Type 'ApexClass' -Wait 5 -IgnoreConflicts | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project retrieve start --metadata ApexClass --wait 5 --ignore-conflicts' }
        }
        It 'throws when output directory does not exist' {
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            { Retrieve-SalesforceComponent -Type 'ApexClass' -OutputDir $missing } | Should -Throw -ExpectedMessage "Output directory '$missing' does not exist."
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { $Command -like 'sf project retrieve start*' }
        }
        It 'quotes output directory when path exists' {
            $existing = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                Retrieve-SalesforceComponent -Type 'ApexClass' -OutputDir $existing.FullName | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq "sf project retrieve start --metadata ApexClass --output-dir `"$($existing.FullName)`"" }
            }
            finally {
                Remove-Item -LiteralPath $existing.FullName -Force -Recurse
            }
        }
    }
}

Describe 'Retrieve-SalesforceField and Retrieve-SalesforceValidationRule' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            # -Type is validated against the org's metadata types; fall back to the built-in list instead
            Clear-SalesforceMetadataTypeCache
            Mock Describe-SalesforceMetadataTypes { @() }
            Mock Invoke-Salesforce {}
        }
        It 'retrieves a custom field as CustomField:Object.Field' {
            Retrieve-SalesforceField -ObjectName 'Account' -FieldName 'MyField__c' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project retrieve start --metadata CustomField:Account.MyField__c' }
        }
        It 'retrieves a validation rule as ValidationRule:Object.Rule' {
            Retrieve-SalesforceValidationRule -ObjectName 'Account' -RuleName 'MyRule' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project retrieve start --metadata ValidationRule:Account.MyRule' }
        }
    }
}

Describe 'Retrieve-SalesforceMetadata' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Invoke-Salesforce {}
        }
        It 'throws when manifest file does not exist' {
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ("$([guid]::NewGuid()).xml")
            $existing = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                { Retrieve-SalesforceMetadata -Manifest $missing -OutputDir $existing.FullName } | Should -Throw -ExpectedMessage "Manifest file '$missing' does not exist."
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            finally {
                Remove-Item -LiteralPath $existing.FullName -Force -Recurse
            }
        }
        It 'throws when output directory does not exist' {
            $manifest = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("$([guid]::NewGuid()).xml")) -ItemType File
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            try {
                { Retrieve-SalesforceMetadata -Manifest $manifest.FullName -OutputDir $missing } | Should -Throw -ExpectedMessage "Output directory '$missing' does not exist."
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            finally {
                Remove-Item -LiteralPath $manifest.FullName -Force
            }
        }
        It 'builds retrieve command with quoted manifest and output directory' {
            $manifest = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("$([guid]::NewGuid()).xml")) -ItemType File
            $outputDir = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                Retrieve-SalesforceMetadata -Manifest $manifest.FullName -OutputDir $outputDir.FullName -Unzip -TargetOrg 'me' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq "sf project retrieve start --manifest `"$($manifest.FullName)`" --target-metadata-dir `"$($outputDir.FullName)`" --unzip --target-org me" }
            }
            finally {
                Remove-Item -LiteralPath $manifest.FullName -Force
                Remove-Item -LiteralPath $outputDir.FullName -Force -Recurse
            }
        }
    }
}

Describe 'Retrieve-SalesforcePackage' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Invoke-Salesforce {}
        }
        It 'throws when output directory does not exist' {
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            { Retrieve-SalesforcePackage -Name 'MyPkg' -OutputDir $missing } | Should -Throw -ExpectedMessage "Output directory '$missing' does not exist."
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
        It 'builds retrieve command with quoted package name and output directory' {
            $outputDir = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                Retrieve-SalesforcePackage -Name 'MyPkg' -OutputDir $outputDir.FullName -TargetOrg 'me' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq "sf project retrieve start --package-name `"MyPkg`" --output-dir `"$($outputDir.FullName)`" --target-org me" }
            }
            finally {
                Remove-Item -LiteralPath $outputDir.FullName -Force -Recurse
            }
        }
    }
}

Describe 'Retrieve-SalesforceOrg' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Invoke-Salesforce {}
        }
        It 'creates a manifest then retrieves using it' {
            Retrieve-SalesforceOrg -TargetOrg 'me' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf force source manifest create --from-org me --name=allMetadata --output-dir .' }
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project retrieve start --target-org me --manifest allMetadata.xml' }
        }
        It 'includes unlocked packages when requested' {
            Retrieve-SalesforceOrg -IncludePackages | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf force source manifest create --name=allMetadata --output-dir . --include-packages=unlocked' }
        }
    }
}

Describe 'Deploy-SalesforceComponent' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            # -Type is validated against the org's metadata types; fall back to the built-in list instead
            Clear-SalesforceMetadataTypeCache
            Mock Describe-SalesforceMetadataTypes { @() }
            Mock Invoke-Salesforce { '{"status":0,"result":{}}' }
        }
        It 'throws when neither Type nor SourceDir is provided' {
            { Deploy-SalesforceComponent } | Should -Throw -ExpectedMessage 'Specify -Type or -SourceDir when deploying metadata.'
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { $Command -like 'sf project deploy start*' }
        }
        It 'throws when Name is provided without Type' {
            # The Type/SourceDir guard runs first, so that is the message thrown when only -Name is given
            { Deploy-SalesforceComponent -Name 'MyClass' } | Should -Throw -ExpectedMessage 'Specify -Type or -SourceDir when deploying metadata.'
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { $Command -like 'sf project deploy start*' }
        }
        It 'throws when both ConciseResults and DetailedResults are provided' {
            { Deploy-SalesforceComponent -Type 'ApexClass' -ConciseResults -DetailedResults } | Should -Throw -ExpectedMessage 'Specify only one of -ConciseResults or -DetailedResults.'
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { $Command -like 'sf project deploy start*' }
        }
        It 'deploys named component with target org, default test level and json' {
            Deploy-SalesforceComponent -Type 'ApexClass' -Name 'MyClass' -TargetOrg 'me' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project deploy start --metadata ApexClass:MyClass --target-org me --test-level NoTestRun --json' }
        }
        It 'adds dry run before json' {
            Deploy-SalesforceComponent -Type 'ApexClass' -DryRun | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project deploy start --metadata ApexClass --test-level NoTestRun --dry-run --json' }
        }
        It 'throws when source path does not exist' {
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            { Deploy-SalesforceComponent -SourceDir $missing } | Should -Throw -ExpectedMessage "Source path '$missing' does not exist."
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { $Command -like 'sf project deploy start*' }
        }
        It 'deploys from a quoted source directory' {
            $existing = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                Deploy-SalesforceComponent -SourceDir $existing.FullName | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq "sf project deploy start --source-dir `"$($existing.FullName)`" --test-level NoTestRun --json" }
            }
            finally {
                Remove-Item -LiteralPath $existing.FullName -Force -Recurse
            }
        }
    }
}

Describe 'Deploy-SalesforceMetadata' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{}}' }
        }
        It 'throws when no input option is provided' {
            { Deploy-SalesforceMetadata } | Should -Throw -ExpectedMessage 'Specify exactly one of -Manifest, -InputDir, or -ManifestPackage.'
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
        It 'throws when more than one input option is provided' {
            $manifest = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("$([guid]::NewGuid()).xml")) -ItemType File
            try {
                { Deploy-SalesforceMetadata -Manifest $manifest.FullName -ManifestPackage } | Should -Throw -ExpectedMessage 'Specify exactly one of -Manifest, -InputDir, or -ManifestPackage.'
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            finally {
                Remove-Item -LiteralPath $manifest.FullName -Force
            }
        }
        It 'deploys using a quoted manifest' {
            $manifest = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("$([guid]::NewGuid()).xml")) -ItemType File
            try {
                Deploy-SalesforceMetadata -Manifest $manifest.FullName -TargetOrg 'me' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq "sf project deploy start --manifest `"$($manifest.FullName)`" --target-org me --json" }
            }
            finally {
                Remove-Item -LiteralPath $manifest.FullName -Force
            }
        }
        It 'deploys a single package artifact' {
            Deploy-SalesforceMetadata -ManifestPackage | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project deploy start --single-package --json' }
        }
    }
}

Describe 'Deploy lifecycle cmdlets' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"id":"0Af000000000001AAA","status":"Succeeded"}}' }
        }

        Context 'Test-SalesforceDeploy' {
            It 'validates a source directory with local tests by default' {
                $dir = New-Item -Path (Join-Path $TestDrive 'force-app') -ItemType Directory
                $result = Test-SalesforceDeploy -SourceDir $dir.FullName -TargetOrg 'prod' -Wait 30
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq "sf project deploy validate --source-dir `"$($dir.FullName)`" --target-org prod --wait 30 --test-level RunLocalTests --json" }
                @($result)[0].id | Should -Be '0Af000000000001AAA'
            }
            It 'validates a manifest with specific tests, async and concise' {
                $manifest = New-Item -Path (Join-Path $TestDrive 'package.xml') -ItemType File
                Test-SalesforceDeploy -Manifest $manifest.FullName -TestLevel SpecificTests -Tests 'MyTest' -IgnoreWarnings -Async -ConciseResults | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -like "sf project deploy validate --manifest `"$($manifest.FullName)`" --ignore-warnings --async --test-level RunSpecifiedTests*--concise --json" }
            }
            It 'validates a metadata directory as a single package with detailed results' {
                $dir = New-Item -Path (Join-Path $TestDrive 'mdapi') -ItemType Directory
                Test-SalesforceDeploy -InputDir $dir.FullName -ManifestPackage -TestLevel NoTests -DetailedResults | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq "sf project deploy validate --metadata-dir `"$($dir.FullName)`" --single-package --test-level NoTestRun --verbose --json" }
            }
            It 'throws unless exactly one source option is given' {
                { Test-SalesforceDeploy } | Should -Throw -ExpectedMessage 'Specify exactly one of -Manifest, -SourceDir, or -InputDir.'
                { Test-SalesforceDeploy -Manifest 'a.xml' -SourceDir 'b' } | Should -Throw -ExpectedMessage 'Specify exactly one of -Manifest, -SourceDir, or -InputDir.'
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'throws for conflicting or missing options' {
                $dir = New-Item -Path (Join-Path $TestDrive 'src') -ItemType Directory
                { Test-SalesforceDeploy -SourceDir $dir.FullName -Wait 5 -Async } | Should -Throw -ExpectedMessage 'Specify only one of -Wait or -Async.'
                { Test-SalesforceDeploy -SourceDir $dir.FullName -ConciseResults -DetailedResults } | Should -Throw -ExpectedMessage 'Specify only one of -ConciseResults or -DetailedResults.'
                { Test-SalesforceDeploy -SourceDir (Join-Path $TestDrive 'missing') } | Should -Throw -ExpectedMessage "Source path '*missing' does not exist."
                { Test-SalesforceDeploy -Manifest (Join-Path $TestDrive 'missing.xml') } | Should -Throw -ExpectedMessage "Manifest file '*missing.xml' does not exist."
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'throws when the CLI reports failure' {
                Mock Invoke-Salesforce { '{"status":1,"message":"Deploy failed"}' }
                $dir = New-Item -Path (Join-Path $TestDrive 'failsrc') -ItemType Directory
                { Test-SalesforceDeploy -SourceDir $dir.FullName } | Should -Throw
            }
        }

        Context 'Start-SalesforceQuickDeploy' {
            It 'quick deploys by job id' {
                Start-SalesforceQuickDeploy -JobId '0Af000000000001AAA' -TargetOrg 'prod' -Wait 10 -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project deploy quick --job-id 0Af000000000001AAA --target-org prod --wait 10 --json' }
            }
            It 'quick deploys the most recent validation asynchronously with concise output' {
                Start-SalesforceQuickDeploy -UseMostRecent -Async -ConciseResults -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project deploy quick --use-most-recent --async --concise --json' }
            }
            It 'supports detailed results' {
                Start-SalesforceQuickDeploy -JobId '0Af000000000001' -DetailedResults -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project deploy quick --job-id 0Af000000000001 --verbose --json' }
            }
            It 'does not deploy with -WhatIf' {
                Start-SalesforceQuickDeploy -JobId '0Af000000000001AAA' -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'throws without a valid job id' {
                { Start-SalesforceQuickDeploy -Confirm:$false } | Should -Throw -ExpectedMessage 'Specify -JobId or -UseMostRecent.'
                { Start-SalesforceQuickDeploy -JobId 'abc' -Confirm:$false } | Should -Throw -ExpectedMessage "Job ID 'abc' is not a valid deploy job ID*"
                { Start-SalesforceQuickDeploy -JobId '0Af000000000001AAA' -UseMostRecent -Confirm:$false } | Should -Throw -ExpectedMessage 'Specify only one of -JobId or -UseMostRecent.'
                { Start-SalesforceQuickDeploy -UseMostRecent -Wait 5 -Async -Confirm:$false } | Should -Throw -ExpectedMessage 'Specify only one of -Wait or -Async.'
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'throws when the CLI reports failure' {
                Mock Invoke-Salesforce { '{"status":1,"message":"Quick deploy failed"}' }
                { Start-SalesforceQuickDeploy -UseMostRecent -Confirm:$false } | Should -Throw
            }
        }

        Context 'Get-SalesforceDeployStatus' {
            It 'reports by job id' {
                $result = Get-SalesforceDeployStatus -JobId '0Af000000000001AAA' -TargetOrg 'me' -Wait 5
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project deploy report --job-id 0Af000000000001AAA --target-org me --wait 5 --json' }
                @($result)[0].status | Should -Be 'Succeeded'
            }
            It 'reports the most recent deployment' {
                Get-SalesforceDeployStatus -UseMostRecent | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project deploy report --use-most-recent --json' }
            }
            It 'throws without a valid job id or with a negative wait' {
                { Get-SalesforceDeployStatus } | Should -Throw -ExpectedMessage 'Specify -JobId or -UseMostRecent.'
                { Get-SalesforceDeployStatus -JobId 'bad id' } | Should -Throw -ExpectedMessage "Job ID 'bad id' is not a valid deploy job ID*"
                { Get-SalesforceDeployStatus -UseMostRecent -Wait -1 } | Should -Throw -ExpectedMessage '-Wait must be zero or greater (minutes).'
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'throws when the CLI reports failure' {
                Mock Invoke-Salesforce { '{"status":1,"message":"No deploy found"}' }
                { Get-SalesforceDeployStatus -UseMostRecent } | Should -Throw
            }
        }

        Context 'Resume-SalesforceDeploy' {
            It 'resumes by job id' {
                Resume-SalesforceDeploy -JobId '0Af000000000001AAA' -TargetOrg 'me' -Wait 20 -ConciseResults | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project deploy resume --job-id 0Af000000000001AAA --target-org me --wait 20 --concise --json' }
            }
            It 'resumes the most recent deployment with detailed results' {
                Resume-SalesforceDeploy -UseMostRecent -DetailedResults | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project deploy resume --use-most-recent --verbose --json' }
            }
            It 'throws for missing job id or conflicting result options' {
                { Resume-SalesforceDeploy } | Should -Throw -ExpectedMessage 'Specify -JobId or -UseMostRecent.'
                { Resume-SalesforceDeploy -UseMostRecent -ConciseResults -DetailedResults } | Should -Throw -ExpectedMessage 'Specify only one of -ConciseResults or -DetailedResults.'
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'throws when the deployment failed' {
                Mock Invoke-Salesforce { '{"status":1,"message":"Deploy failed"}' }
                { Resume-SalesforceDeploy -UseMostRecent } | Should -Throw
            }
        }

        Context 'Stop-SalesforceDeploy' {
            It 'cancels by job id' {
                Stop-SalesforceDeploy -JobId '0Af000000000001AAA' -TargetOrg 'me' -Wait 5 -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project deploy cancel --job-id 0Af000000000001AAA --target-org me --wait 5 --json' }
            }
            It 'cancels the most recent deployment asynchronously' {
                Stop-SalesforceDeploy -UseMostRecent -Async -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project deploy cancel --use-most-recent --async --json' }
            }
            It 'does not cancel with -WhatIf' {
                Stop-SalesforceDeploy -JobId '0Af000000000001AAA' -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'throws without a valid job id' {
                { Stop-SalesforceDeploy -Confirm:$false } | Should -Throw -ExpectedMessage 'Specify -JobId or -UseMostRecent.'
                { Stop-SalesforceDeploy -JobId '123' -Confirm:$false } | Should -Throw -ExpectedMessage "Job ID '123' is not a valid deploy job ID*"
                { Stop-SalesforceDeploy -UseMostRecent -Wait 5 -Async -Confirm:$false } | Should -Throw -ExpectedMessage 'Specify only one of -Wait or -Async.'
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'throws when the CLI reports failure' {
                Mock Invoke-Salesforce { '{"status":1,"message":"Cannot cancel"}' }
                { Stop-SalesforceDeploy -UseMostRecent -Confirm:$false } | Should -Throw
            }
        }

        Context 'Manifest exports' {
            It 'exports the lifecycle cmdlets' {
                $exported = (Get-Module 'psfdx-metadata').ExportedFunctions.Keys
                foreach ($name in 'Test-SalesforceDeploy','Start-SalesforceQuickDeploy','Get-SalesforceDeployStatus','Resume-SalesforceDeploy','Stop-SalesforceDeploy') {
                    $exported | Should -Contain $name
                }
            }
        }
    }
}

Describe 'Describe-SalesforceObjects' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":["Account","Contact"]}' }
        }
        It 'lists objects with target org and json' {
            $out = Describe-SalesforceObjects -TargetOrg 'me'
            $out.Count | Should -Be 2
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf sobject list --target-org me --json' }
        }
    }
}

Describe 'Describe-SalesforceObject' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"name":"Account"}}' }
        }
        It 'describes an object with tooling api' {
            $out = Describe-SalesforceObject -Name 'Account' -TargetOrg 'me' -UseToolingApi
            $out.name | Should -Be 'Account'
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf sobject describe --target-org me --sobject Account --use-tooling-api --json' }
        }
    }
}

Describe 'Describe-SalesforceFields' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Describe-SalesforceObject {
                [pscustomobject]@{
                    fields = @(
                        [pscustomobject]@{ name = 'Name'; label = 'Account Name'; type = 'string'; byteLength = 255 },
                        [pscustomobject]@{ name = 'Id'; label = 'Account ID'; type = 'id'; byteLength = 18 }
                    )
                }
            }
        }
        It 'returns fields sorted by name' {
            $out = Describe-SalesforceFields -ObjectName 'Account' -TargetOrg 'me'
            $out.Count | Should -Be 2
            $out[0].name | Should -Be 'Id'
            $out[1].name | Should -Be 'Name'
            Assert-MockCalled Describe-SalesforceObject -Times 1 -ParameterFilter { $Name -eq 'Account' -and $TargetOrg -eq 'me' }
        }
    }
}

Describe 'Describe-SalesforceMetadataTypes' {
    InModuleScope 'psfdx-metadata' {
        It 'returns xml names from metadata objects' {
            Mock Invoke-Salesforce { '{"status":0,"result":{"metadataObjects":[{"xmlName":"ApexClass"},{"xmlName":"CustomObject"}]}}' }
            $out = Describe-SalesforceMetadataTypes -TargetOrg 'me'
            $out | Should -Be @('ApexClass', 'CustomObject')
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf org list metadata-types --target-org me --json' }
        }
        It 'returns empty array when no metadata objects' {
            Mock Invoke-Salesforce { '{"status":0,"result":{}}' }
            $out = Describe-SalesforceMetadataTypes
            @($out).Count | Should -Be 0
        }
    }
}

Describe 'Build-SalesforceQuery' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Describe-SalesforceFields {
                @(
                    [pscustomobject]@{ name = 'Id' },
                    [pscustomobject]@{ name = 'Name' },
                    [pscustomobject]@{ name = 'CreatedDate' },
                    [pscustomobject]@{ name = 'OwnerId' }
                )
            }
        }
        It 'builds a SELECT for all fields' {
            $query = Build-SalesforceQuery -ObjectName 'Account'
            $query | Should -Be 'SELECT Id,Name,CreatedDate,OwnerId FROM Account'
        }
        It 'excludes audit fields when requested' {
            $query = Build-SalesforceQuery -ObjectName 'Account' -ExcludeAuditFields
            $query | Should -Be 'SELECT Id,Name,OwnerId FROM Account'
        }
        It 'excludes name and context fields when requested' {
            $query = Build-SalesforceQuery -ObjectName 'Account' -ExcludeNameFields -ExcludeContextFields
            $query | Should -Be 'SELECT Id,CreatedDate FROM Account'
        }
        It 'returns empty string when no fields are found' {
            Mock Describe-SalesforceFields { $null }
            Build-SalesforceQuery -ObjectName 'Account' | Should -Be ''
        }
        It 'returns empty string rather than invalid SOQL when every field is excluded' {
            Mock Describe-SalesforceFields { @([pscustomobject]@{ name = 'Name' }) }
            Build-SalesforceQuery -ObjectName 'Account' -ExcludeNameFields | Should -Be ''
        }
    }
}

Describe 'Retrieve-SalesforceComponent without -Type' {
    InModuleScope 'psfdx-metadata' {
        It 'throws instead of emitting a dangling --metadata flag' {
            Mock Invoke-Salesforce {}
            { Retrieve-SalesforceComponent -Name 'MyClass' } |
                Should -Throw -ExpectedMessage 'Specify -Type when retrieving a component.'
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
    }
}

Describe 'Metadata type valid-set caching' {
    InModuleScope 'psfdx-metadata' {
        AfterEach { Clear-SalesforceMetadataTypeCache }
        It 'queries the org once and serves later binds from cache' {
            Clear-SalesforceMetadataTypeCache
            Mock Invoke-Salesforce { '{"status":0,"result":{"metadataObjects":[{"xmlName":"ApexClass"}]}}' }

            $first  = Get-SalesforceMetadataTypeValidValues
            $second = Get-SalesforceMetadataTypeValidValues

            $first | Should -Contain 'ApexClass'
            $second | Should -Contain 'ApexClass'
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly
        }
        It 're-queries after the cache is cleared' {
            Clear-SalesforceMetadataTypeCache
            Mock Invoke-Salesforce { '{"status":0,"result":{"metadataObjects":[{"xmlName":"ApexClass"}]}}' }

            Get-SalesforceMetadataTypeValidValues | Out-Null
            Clear-SalesforceMetadataTypeCache
            Get-SalesforceMetadataTypeValidValues | Out-Null

            Assert-MockCalled Invoke-Salesforce -Times 2 -Exactly
        }
        It 'always offers CustomField and ValidationRule' {
            Clear-SalesforceMetadataTypeCache
            Mock Invoke-Salesforce { '{"status":0,"result":{"metadataObjects":[]}}' }
            $values = Get-SalesforceMetadataTypeValidValues
            $values | Should -Contain 'CustomField'
            $values | Should -Contain 'ValidationRule'
            $values | Should -Contain 'ApexClass'
        }
    }
}

Describe 'Metadata -Type validation and completion' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Invoke-Salesforce {}
            Mock Get-SalesforceMetadataTypeValidValues { @('ApexClass', 'ApexTrigger', 'CustomField') }
        }
        It 'declares -Type without a class-based ValidateSet, so the module loads on Windows PowerShell 5.1' {
            foreach ($name in 'Retrieve-SalesforceComponent', 'Deploy-SalesforceComponent') {
                $attributes = (Get-Command $name).Parameters['Type'].Attributes
                @($attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count | Should -Be 0
                @($attributes | Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }).Count | Should -Be 1
            }
        }
        It 'Retrieve-SalesforceComponent rejects an unknown type without calling sf' {
            { Retrieve-SalesforceComponent -Type 'NotAType' } |
                Should -Throw -ExpectedMessage "Unknown metadata type 'NotAType'*"
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
        It 'Deploy-SalesforceComponent rejects an unknown type without calling sf' {
            { Deploy-SalesforceComponent -Type 'NotAType' } |
                Should -Throw -ExpectedMessage "Unknown metadata type 'NotAType'*"
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
        It 'accepts a known type case-insensitively, as ValidateSet did' {
            Retrieve-SalesforceComponent -Type 'apexclass' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Command -eq 'sf project retrieve start --metadata apexclass' }
        }
        It 'completes -Type from the valid values' {
            $completions = @(Complete-SalesforceMetadataType 'Retrieve-SalesforceComponent' 'Type' 'Apex' $null @{})
            $completions.CompletionText | Should -Be @('ApexClass', 'ApexTrigger')
        }
    }
}

Describe 'Metadata -Type argument completer' {
    # Runs outside InModuleScope on purpose: PowerShell invokes the completer from the caller's
    # scope, so it must reach the module's private helpers without help from the test.
    BeforeAll {
        Mock Describe-SalesforceMetadataTypes { @() } -ModuleName 'psfdx-metadata'
        & (Get-Module psfdx-metadata) { Clear-SalesforceMetadataTypeCache }
    }
    It 'completes -Type on <_>' -ForEach 'Retrieve-SalesforceComponent', 'Deploy-SalesforceComponent' {
        $completer = (Get-Command $_).Parameters['Type'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }
        $completions = @(& $completer.ScriptBlock $_ 'Type' 'ApexTr' $null @{})
        $completions.CompletionText | Should -Be @('ApexTrigger')
    }
}
