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
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|retrieve|start|--metadata|ApexClass' }
        }
        It 'retrieves a named component with target org' {
            Retrieve-SalesforceComponent -Type 'ApexClass' -Name 'MyClass' -TargetOrg 'me' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|retrieve|start|--metadata|ApexClass:MyClass|--target-org|me' }
        }
        It 'appends child name to named component' {
            Retrieve-SalesforceComponent -Type 'CustomField' -Name 'Account' -ChildName 'MyField__c' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|retrieve|start|--metadata|CustomField:Account.MyField__c' }
        }
        It 'throws when ChildName is used without Name' {
            { Retrieve-SalesforceComponent -Type 'CustomField' -ChildName 'MyField__c' } | Should -Throw -ExpectedMessage 'Specify -Name when using -ChildName.'
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { ($Arguments -join '|') -like 'project|retrieve|start*' }
        }
        It 'adds wait and ignore conflicts flags' {
            Retrieve-SalesforceComponent -Type 'ApexClass' -Wait 5 -IgnoreConflicts | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|retrieve|start|--metadata|ApexClass|--wait|5|--ignore-conflicts' }
        }
        It 'throws when output directory does not exist' {
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            { Retrieve-SalesforceComponent -Type 'ApexClass' -OutputDir $missing } | Should -Throw -ExpectedMessage "Output directory '$missing' does not exist."
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { ($Arguments -join '|') -like 'project|retrieve|start*' }
        }
        It 'passes an output directory with spaces as one argument' {
            $dir = New-Item -Path (Join-Path $TestDrive 'out dir with spaces') -ItemType Directory
            Retrieve-SalesforceComponent -Type 'ApexClass' -OutputDir $dir.FullName | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Arguments.Count -eq 7 -and $Arguments[6] -eq $dir.FullName }
        }
        It 'passes the output directory when the path exists' {
            $existing = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                Retrieve-SalesforceComponent -Type 'ApexClass' -OutputDir $existing.FullName | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "project|retrieve|start|--metadata|ApexClass|--output-dir|$($existing.FullName)" }
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
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|retrieve|start|--metadata|CustomField:Account.MyField__c' }
        }
        It 'retrieves a validation rule as ValidationRule:Object.Rule' {
            Retrieve-SalesforceValidationRule -ObjectName 'Account' -RuleName 'MyRule' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|retrieve|start|--metadata|ValidationRule:Account.MyRule' }
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
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "project|retrieve|start|--manifest|$($manifest.FullName)|--target-metadata-dir|$($outputDir.FullName)|--unzip|--target-org|me" }
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
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "project|retrieve|start|--package-name|MyPkg|--output-dir|$($outputDir.FullName)|--target-org|me" }
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
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|generate|manifest|--from-org|me|--name=allMetadata|--output-dir|.' }
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|retrieve|start|--target-org|me|--manifest|allMetadata.xml' }
        }
        It 'includes unlocked packages when requested' {
            Retrieve-SalesforceOrg -IncludePackages | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|generate|manifest|--name=allMetadata|--output-dir|.|--include-packages=unlocked' }
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
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { ($Arguments -join '|') -like 'project|deploy|start*' }
        }
        It 'throws when Name is provided without Type' {
            # The Type/SourceDir guard runs first, so that is the message thrown when only -Name is given
            { Deploy-SalesforceComponent -Name 'MyClass' } | Should -Throw -ExpectedMessage 'Specify -Type or -SourceDir when deploying metadata.'
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { ($Arguments -join '|') -like 'project|deploy|start*' }
        }
        It 'throws when both ConciseResults and DetailedResults are provided' {
            { Deploy-SalesforceComponent -Type 'ApexClass' -ConciseResults -DetailedResults } | Should -Throw -ExpectedMessage 'Specify only one of -ConciseResults or -DetailedResults.'
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { ($Arguments -join '|') -like 'project|deploy|start*' }
        }
        It 'deploys named component with target org, default test level and json' {
            Deploy-SalesforceComponent -Type 'ApexClass' -Name 'MyClass' -TargetOrg 'me' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|start|--metadata|ApexClass:MyClass|--target-org|me|--test-level|NoTestRun|--json' }
        }
        It 'adds dry run before json' {
            Deploy-SalesforceComponent -Type 'ApexClass' -DryRun | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|start|--metadata|ApexClass|--test-level|NoTestRun|--dry-run|--json' }
        }
        It 'throws when source path does not exist' {
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            { Deploy-SalesforceComponent -SourceDir $missing } | Should -Throw -ExpectedMessage "Source path '$missing' does not exist."
            Assert-MockCalled Invoke-Salesforce -Times 0 -ParameterFilter { ($Arguments -join '|') -like 'project|deploy|start*' }
        }
        It 'deploys from a quoted source directory' {
            $existing = New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -ItemType Directory
            try {
                Deploy-SalesforceComponent -SourceDir $existing.FullName | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "project|deploy|start|--source-dir|$($existing.FullName)|--test-level|NoTestRun|--json" }
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
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "project|deploy|start|--manifest|$($manifest.FullName)|--target-org|me|--json" }
            }
            finally {
                Remove-Item -LiteralPath $manifest.FullName -Force
            }
        }
        It 'deploys a single package artifact' {
            Deploy-SalesforceMetadata -ManifestPackage | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|start|--single-package|--json' }
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
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "project|deploy|validate|--source-dir|$($dir.FullName)|--target-org|prod|--wait|30|--test-level|RunLocalTests|--json" }
                @($result)[0].id | Should -Be '0Af000000000001AAA'
            }
            It 'validates a manifest with specific tests, async and concise' {
                $manifest = New-Item -Path (Join-Path $TestDrive 'package.xml') -ItemType File
                Test-SalesforceDeploy -Manifest $manifest.FullName -TestLevel SpecificTests -Tests 'MyTest' -IgnoreWarnings -Async -ConciseResults | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -like "project|deploy|validate|--manifest|$($manifest.FullName)|--ignore-warnings|--async|--test-level|RunSpecifiedTests*--concise|--json" }
            }
            It 'validates a metadata directory as a single package with detailed results' {
                $dir = New-Item -Path (Join-Path $TestDrive 'mdapi') -ItemType Directory
                Test-SalesforceDeploy -InputDir $dir.FullName -ManifestPackage -DetailedResults | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "project|deploy|validate|--metadata-dir|$($dir.FullName)|--single-package|--test-level|RunLocalTests|--verbose|--json" }
            }
            It 'validates a Metadata API ZIP whose path contains spaces as one --metadata-dir value' {
                $folder = New-Item -Path (Join-Path $TestDrive 'my folder') -ItemType Directory
                $zip = New-Item -Path (Join-Path $folder.FullName 'mdapi package.zip') -ItemType File
                Test-SalesforceDeploy -InputDir $zip.FullName -TargetOrg 'my-org' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "project|deploy|validate|--metadata-dir|$($zip.FullName)|--target-org|my-org|--test-level|RunLocalTests|--json" }
            }
            It 'validates a Metadata API ZIP as a single package' {
                $zip = New-Item -Path (Join-Path $TestDrive 'single.ZIP') -ItemType File
                Test-SalesforceDeploy -InputDir $zip.FullName -ManifestPackage | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "project|deploy|validate|--metadata-dir|$($zip.FullName)|--single-package|--test-level|RunLocalTests|--json" }
            }
            It 'throws for a missing or unsupported -InputDir path' {
                $txt = New-Item -Path (Join-Path $TestDrive 'mdapi.txt') -ItemType File
                { Test-SalesforceDeploy -InputDir (Join-Path $TestDrive 'missing.zip') } | Should -Throw -ExpectedMessage "Input path '*missing.zip' does not exist."
                { Test-SalesforceDeploy -InputDir $txt.FullName } | Should -Throw -ExpectedMessage "Input path '*mdapi.txt' must be a directory or a .zip file."
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'rejects -InputDir combined with another source option' {
                $zip = New-Item -Path (Join-Path $TestDrive 'excl.zip') -ItemType File
                $dir = New-Item -Path (Join-Path $TestDrive 'excl-src') -ItemType Directory
                { Test-SalesforceDeploy -InputDir $zip.FullName -SourceDir $dir.FullName } | Should -Throw -ExpectedMessage 'Specify exactly one of -Manifest, -SourceDir, -InputDir, or -Metadata.'
                { Test-SalesforceDeploy -SourceDir $dir.FullName -ManifestPackage } | Should -Throw -ExpectedMessage '-ManifestPackage can only be used with -InputDir.'
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'rejects NoTests during parameter validation' {
                $dir = New-Item -Path (Join-Path $TestDrive 'notests') -ItemType Directory
                { Test-SalesforceDeploy -SourceDir $dir.FullName -TestLevel NoTests } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'maps each supported test level to a CLI value' {
                $dir = New-Item -Path (Join-Path $TestDrive 'levels') -ItemType Directory
                Test-SalesforceDeploy -SourceDir $dir.FullName -TestLevel TestsInOrgAndPackages | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "project|deploy|validate|--source-dir|$($dir.FullName)|--test-level|RunAllTestsInOrg|--json" }
                Test-SalesforceDeploy -SourceDir $dir.FullName -TestLevel TestsInOrg | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "project|deploy|validate|--source-dir|$($dir.FullName)|--test-level|RunLocalTests|--json" }
                Test-SalesforceDeploy -SourceDir $dir.FullName -TestLevel SpecificTests -Tests 'MyTest' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "project|deploy|validate|--source-dir|$($dir.FullName)|--test-level|RunSpecifiedTests|--tests|MyTest|--json" }
                Test-SalesforceDeploy -SourceDir $dir.FullName -TestLevel RelevantTests | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "project|deploy|validate|--source-dir|$($dir.FullName)|--test-level|RunRelevantTests|--json" }
            }
            It 'requires test names for SpecificTests' {
                $dir = New-Item -Path (Join-Path $TestDrive 'specific') -ItemType Directory
                { Test-SalesforceDeploy -SourceDir $dir.FullName -TestLevel SpecificTests } | Should -Throw -ExpectedMessage 'Provide one or more -Tests when using -TestLevel SpecificTests.'
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'throws unless exactly one source option is given' {
                { Test-SalesforceDeploy } | Should -Throw -ExpectedMessage 'Specify exactly one of -Manifest, -SourceDir, -InputDir, or -Metadata.'
                { Test-SalesforceDeploy -Manifest 'a.xml' -SourceDir 'b' } | Should -Throw -ExpectedMessage 'Specify exactly one of -Manifest, -SourceDir, -InputDir, or -Metadata.'
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
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|quick|--job-id|0Af000000000001AAA|--target-org|prod|--wait|10|--json' }
            }
            It 'quick deploys the most recent validation asynchronously with concise output' {
                Start-SalesforceQuickDeploy -UseMostRecent -Async -ConciseResults -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|quick|--use-most-recent|--async|--concise|--json' }
            }
            It 'supports detailed results' {
                Start-SalesforceQuickDeploy -JobId '0Af000000000001' -DetailedResults -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|quick|--job-id|0Af000000000001|--verbose|--json' }
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
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|report|--job-id|0Af000000000001AAA|--target-org|me|--wait|5|--json' }
                @($result)[0].status | Should -Be 'Succeeded'
            }
            It 'reports the most recent deployment' {
                Get-SalesforceDeployStatus -UseMostRecent | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|report|--use-most-recent|--json' }
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
                Resume-SalesforceDeploy -JobId '0Af000000000001AAA' -Wait 20 -ConciseResults | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|resume|--job-id|0Af000000000001AAA|--wait|20|--concise|--json' }
            }
            It 'has no TargetOrg parameter and never emits --target-org' {
                (Get-Command Resume-SalesforceDeploy).Parameters.ContainsKey('TargetOrg') | Should -BeFalse
                { Resume-SalesforceDeploy -UseMostRecent -TargetOrg 'me' } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0
                Resume-SalesforceDeploy -UseMostRecent | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|resume|--use-most-recent|--json' }
            }
            It 'resumes the most recent deployment with detailed results' {
                Resume-SalesforceDeploy -UseMostRecent -DetailedResults | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|resume|--use-most-recent|--verbose|--json' }
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
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|cancel|--job-id|0Af000000000001AAA|--target-org|me|--wait|5|--json' }
            }
            It 'cancels the most recent deployment asynchronously' {
                Stop-SalesforceDeploy -UseMostRecent -Async -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|cancel|--use-most-recent|--async|--json' }
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
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'sobject|list|--target-org|me|--json' }
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
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'sobject|describe|--target-org|me|--sobject|Account|--use-tooling-api|--json' }
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
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'org|list|metadata-types|--target-org|me|--json' }
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
        It 'refuses an object name that is not an API name' {
            { Build-SalesforceQuery -ObjectName 'Account WHERE 1=1' } | Should -Throw -ExpectedMessage '*not a valid Salesforce object or field API name*'
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
                Should -Throw -ExpectedMessage 'Specify -Type or -SourceDir when retrieving a component.'
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
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'project|retrieve|start|--metadata|apexclass' }
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

# SOQL builder regression coverage (#172): identifiers cannot be quoted, so anything that is not an API name must be refused.
Describe 'Build-SalesforceQuery identifier regression' {
    InModuleScope 'psfdx-metadata' {
        It 'refuses object name <Name> and returns no query' -ForEach @(
            @{ Name = 'injection';  Value = 'Account WHERE 1=1' }
            @{ Name = 'semicolon';  Value = 'Account;DELETE' }
            @{ Name = 'comma';      Value = 'Account,Contact' }
            @{ Name = 'quote';      Value = "Account'" }
            @{ Name = 'backslash';  Value = 'Account\' }
            @{ Name = 'percent';    Value = 'Acc%' }
            @{ Name = 'space';      Value = 'My Object__c' }
            @{ Name = 'unicode';    Value = 'Konto日本' }
            @{ Name = 'dot only';   Value = '.' }
        ) {
            Mock Describe-SalesforceFields { @([pscustomobject]@{ name = 'Id' }) }
            { Build-SalesforceQuery -ObjectName $Value } | Should -Throw -ExpectedMessage '*not a valid Salesforce object or field API name*'
        }

        It 'refuses a field name that is not an API name' {
            Mock Describe-SalesforceFields { @([pscustomobject]@{ name = 'Id' }, [pscustomobject]@{ name = 'Name FROM Secret' }) }
            { Build-SalesforceQuery -ObjectName 'Account' } | Should -Throw -ExpectedMessage '*not a valid Salesforce object or field API name*'
        }

        It 'accepts custom, namespaced and relationship-style API names' {
            Mock Describe-SalesforceFields { @([pscustomobject]@{ name = 'Id' }, [pscustomobject]@{ name = 'My_Field__c' }, [pscustomobject]@{ name = 'ns__Thing__c' }) }
            Build-SalesforceQuery -ObjectName 'ns__Obj__c' | Should -Be 'SELECT Id,My_Field__c,ns__Thing__c FROM ns__Obj__c'
        }

        It 'returns an empty string when the object has no fields' {
            Mock Describe-SalesforceFields { $null }
            Build-SalesforceQuery -ObjectName 'Account' | Should -Be ''
        }
    }
}

Describe 'Deploy and retrieve preview' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            $script:Reply = '{"status":0,"result":{"toDeploy":[{"type":"ApexClass","fullName":"Foo","projectRelativePath":"force-app/Foo.cls"}],"toRetrieve":[],"toDelete":[{"type":"ApexClass","fullName":"Old"}],"conflicts":[{"type":"ApexClass","fullName":"Bar","conflict":true}],"ignored":[{"fullName":"x.txt"}]}}'
            Mock Invoke-Salesforce { $script:Reply }
        }
        It 'builds the exact deploy preview command and returns the lists' {
            $dir = Join-Path $TestDrive 'my classes'; New-Item -ItemType Directory -Path $dir | Out-Null
            $p = Get-SalesforceDeployPreview -SourceDir $dir -Metadata 'ApexClass:Foo' -IgnoreConflicts -TargetOrg me
            $expected = "project|deploy|preview|--source-dir|$dir|--metadata|ApexClass:Foo|--ignore-conflicts|--target-org|me|--json"
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
            $p.Operation | Should -Be 'Deploy'
            $p.ToDeploy.Count | Should -Be 1
            $p.ToDelete.Count | Should -Be 1
            $p.Conflicts[0].fullName | Should -Be 'Bar'
            $p.Ignored.Count | Should -Be 1
            $p.HasChanges | Should -BeTrue
            $p.HasConflicts | Should -BeTrue
            $p.Summary | Should -Be '1 to deploy, 0 to retrieve, 1 to delete, 1 conflict(s)'
        }
        It 'accepts a manifest and builds the plain command with no options' {
            $m = Join-Path $TestDrive 'package.xml'; Set-Content -Path $m -Value '<Package/>'
            Get-SalesforceDeployPreview -Manifest $m | Out-Null
            $expected = "project|deploy|preview|--manifest|$m|--json"
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
            Get-SalesforceDeployPreview | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|preview|--json' }
        }
        It 'rejects missing paths without calling the CLI' {
            { Get-SalesforceDeployPreview -Manifest (Join-Path $TestDrive 'nope.xml') } | Should -Throw -ExpectedMessage '*does not exist*'
            { Get-SalesforceDeployPreview -SourceDir (Join-Path $TestDrive 'nope') } | Should -Throw -ExpectedMessage '*does not exist*'
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
        }
        It 'builds the exact retrieve preview command' {
            $script:Reply = '{"status":0,"result":{"toRetrieve":[{"type":"CustomObject","fullName":"Acme__c"}],"toDeploy":[],"toDelete":[],"conflicts":[],"ignored":[]}}'
            $p = Get-SalesforceRetrievePreview -IgnoreConflicts -TargetOrg me
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|retrieve|preview|--ignore-conflicts|--target-org|me|--json' }
            $p.Operation | Should -Be 'Retrieve'
            $p.ToRetrieve.Count | Should -Be 1
            $p.HasConflicts | Should -BeFalse
        }
        It 'returns empty lists and a clear summary when there are no changes, including a missing property' {
            $script:Reply = '{"status":0,"result":{"toDeploy":[],"toRetrieve":[],"toDelete":[],"conflicts":[],"ignored":[]}}'
            $p = Get-SalesforceDeployPreview
            $p.HasChanges | Should -BeFalse
            $p.Summary | Should -Be 'No changes'
            @($p.ToDeploy).Count | Should -Be 0
            $script:Reply = '{"status":0,"result":{}}'
            (Get-SalesforceRetrievePreview).Summary | Should -Be 'No changes'
        }
        It 'surfaces CLI errors, adding guidance for orgs without source tracking' {
            $script:Reply = '{"status":1,"name":"NoSourceTracking","message":"This org does not have source tracking enabled."}'
            { Get-SalesforceDeployPreview } | Should -Throw -ExpectedMessage '*source tracking*Deploy-SalesforceMetadata*'
            $script:Reply = '{"status":1,"name":"Other","message":"Something else failed."}'
            { Get-SalesforceRetrievePreview } | Should -Throw -ExpectedMessage 'Something else failed.'
        }
        It 'is exported, has examples, and keeps helpers private' {
            $exports = (Import-PowerShellDataFile -Path (Join-Path (Get-Module -Name psfdx-metadata).ModuleBase 'psfdx-metadata.psd1')).FunctionsToExport
            $exports | Should -Contain 'Get-SalesforceDeployPreview'
            $exports | Should -Contain 'Get-SalesforceRetrievePreview'
            $exports | Should -Not -Contain 'ConvertTo-SalesforcePreviewObject'
            foreach ($n in 'Get-SalesforceDeployPreview', 'Get-SalesforceRetrievePreview') { @((Get-Help $n -Examples).examples.example).Count | Should -BeGreaterThan 0 }
        }
    }
}

Describe 'Security regressions: deployments can be previewed (issue 112)' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
            $script:manifest = Join-Path $TestDrive 'package.xml'
            Set-Content -Path $script:manifest -Value '<Package/>'
        }
        It 'deploys nothing under -WhatIf from a manifest, a directory or a component' {
            Deploy-SalesforceMetadata -Manifest $script:manifest -WhatIf | Out-Null
            Deploy-SalesforceComponent -SourceDir $TestDrive -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
        }
        It 'still deploys when not previewing, without a prompt' {
            Deploy-SalesforceMetadata -Manifest $script:manifest | Out-Null
            Deploy-SalesforceComponent -SourceDir $TestDrive | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 2 -Exactly
        }
        It 'runs a validation-only deployment (-DryRun) even under -WhatIf, because it changes nothing' {
            Deploy-SalesforceComponent -SourceDir $TestDrive -DryRun -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { $Arguments -contains '--dry-run' }
        }
    }
}

Describe 'sf project parity: new flags on existing cmdlets (issue 244)' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Clear-SalesforceMetadataTypeCache
            Mock Describe-SalesforceMetadataTypes { @() }
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
            $script:manifest = Join-Path $TestDrive 'package.xml'
            Set-Content -Path $script:manifest -Value '<Package/>'
            $script:pre = Join-Path $TestDrive 'destructiveChangesPre.xml'
            Set-Content -Path $script:pre -Value '<Package/>'
        }
        It 'Deploy-SalesforceMetadata passes destructive changes, async and result flags' {
            Deploy-SalesforceMetadata -Manifest $script:manifest -PreDestructiveChanges $script:pre -PurgeOnDelete -Async -CoverageFormatters json, lcovonly -Junit -ResultsDir 'out dir' | Out-Null
            $expected = "project|deploy|start|--manifest|$($script:manifest)|--pre-destructive-changes|$($script:pre)|--purge-on-delete|--async|--coverage-formatters|json|--coverage-formatters|lcovonly|--junit|--results-dir|out dir|--json"
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
        }
        It 'Deploy-SalesforceMetadata refuses -PurgeOnDelete without a destructive changes file, and a missing file' {
            { Deploy-SalesforceMetadata -Manifest $script:manifest -PurgeOnDelete } | Should -Throw -ExpectedMessage '-PurgeOnDelete needs*'
            { Deploy-SalesforceMetadata -Manifest $script:manifest -PostDestructiveChanges (Join-Path $TestDrive 'nope.xml') } | Should -Throw -ExpectedMessage '*does not exist.'
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
        }
        It 'Deploy-SalesforceMetadata rejects an unknown coverage formatter' {
            { Deploy-SalesforceMetadata -Manifest $script:manifest -CoverageFormatters bogus } | Should -Throw
        }
        It 'Deploy-SalesforceComponent passes RunRelevantTests, async and result flags' {
            Deploy-SalesforceComponent -Type ApexClass -Name Foo -TestLevel RelevantTests -Async -Junit -ResultsDir res | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|start|--metadata|ApexClass:Foo|--test-level|RunRelevantTests|--async|--junit|--results-dir|res|--json' }
        }
        It 'Deploy-SalesforceComponent refuses -Async with -Wait' {
            { Deploy-SalesforceComponent -Type ApexClass -Name Foo -Async -Wait 5 } | Should -Throw -ExpectedMessage 'Specify only one of -Wait or -Async.'
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
        }
        It 'Test-SalesforceDeploy accepts -Metadata with destructive changes and result flags' {
            Test-SalesforceDeploy -Metadata ApexClass:A, ApexClass:B -PostDestructiveChanges $script:pre -CoverageFormatters clover -Junit -ResultsDir r | Out-Null
            $expected = "project|deploy|validate|--metadata|ApexClass:A|--metadata|ApexClass:B|--post-destructive-changes|$($script:pre)|--coverage-formatters|clover|--junit|--results-dir|r|--test-level|RunLocalTests|--json"
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
        }
        It 'Get-SalesforceDeployStatus and Resume-SalesforceDeploy pass the result flags' {
            Get-SalesforceDeployStatus -UseMostRecent -CoverageFormatters text -Junit -ResultsDir r | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|report|--use-most-recent|--coverage-formatters|text|--junit|--results-dir|r|--json' }
            Resume-SalesforceDeploy -JobId 0Af000000000001AAA -CoverageFormatters none -ResultsDir r | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|resume|--job-id|0Af000000000001AAA|--coverage-formatters|none|--results-dir|r|--json' }
        }
        It 'the previews pass --concise' {
            Mock Get-SalesforcePreviewResult { 'ok' }
            Get-SalesforceDeployPreview -ConciseResults -TargetOrg me | Out-Null
            Get-SalesforceRetrievePreview -ConciseResults | Out-Null
            Assert-MockCalled Get-SalesforcePreviewResult -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|preview|--concise|--target-org|me|--json' }
            Assert-MockCalled Get-SalesforcePreviewResult -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|retrieve|preview|--concise|--json' }
        }
        It 'Retrieve-SalesforceComponent retrieves from -SourceDir with root types, without -Type' {
            Retrieve-SalesforceComponent -SourceDir $TestDrive -RootTypeWithDependencies Bot, AiAgentDefinitionVersion | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "project|retrieve|start|--source-dir|$TestDrive|--root-type-with-dependencies|Bot|--root-type-with-dependencies|AiAgentDefinitionVersion" }
            { Retrieve-SalesforceComponent } | Should -Throw -ExpectedMessage 'Specify -Type or -SourceDir when retrieving a component.'
            { Retrieve-SalesforceComponent -SourceDir (Join-Path $TestDrive 'nope') } | Should -Throw -ExpectedMessage '*does not exist.'
        }
        It 'Retrieve-SalesforceMetadata passes --single-package and --zip-file-name' {
            Retrieve-SalesforceMetadata -Manifest $script:manifest -OutputDir $TestDrive -SinglePackage -ZipFileName pkg.zip | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "project|retrieve|start|--manifest|$($script:manifest)|--target-metadata-dir|$TestDrive|--single-package|--zip-file-name|pkg.zip" }
        }
    }
}

Describe 'sf project parity: manifest, conversion and ignored files (issue 244)' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":["a.cls","b.cls"]}' }
            $script:src = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'src dir') -Force
            $script:manifest = Join-Path $TestDrive 'package.xml'
            Set-Content -Path $script:manifest -Value '<Package/>'
        }
        It 'New-SalesforceManifest passes every flag' {
            New-SalesforceManifest -Metadata ApexClass:A -ExcludedMetadata Report -SourceDir $script:src.FullName -FromOrg dev -IncludePackages managed, unlocked -Name pkg -OutputDir $TestDrive -Type destroy | Out-Null
            $expected = "project|generate|manifest|--metadata|ApexClass:A|--excluded-metadata|Report|--source-dir|$($script:src.FullName)|--from-org|dev|--include-packages|managed|--include-packages|unlocked|--name|pkg|--output-dir|$TestDrive|--type|destroy|--json"
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
        }
        It 'New-SalesforceManifest rejects a bad type and a missing folder' {
            { New-SalesforceManifest -Type bogus } | Should -Throw
            { New-SalesforceManifest -OutputDir (Join-Path $TestDrive 'nope') } | Should -Throw -ExpectedMessage '*does not exist.'
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
        }
        It 'ConvertTo-SalesforceSourceFormat runs sf project convert mdapi' {
            ConvertTo-SalesforceSourceFormat -RootDir $script:src.FullName -OutputDir out -Manifest $script:manifest -Metadata ApexClass:A -MetadataDir d1, d2 | Out-Null
            $expected = "project|convert|mdapi|--root-dir|$($script:src.FullName)|--output-dir|out|--manifest|$($script:manifest)|--metadata|ApexClass:A|--metadata-dir|d1|--metadata-dir|d2|--json"
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
            { ConvertTo-SalesforceSourceFormat -RootDir (Join-Path $TestDrive 'nope') } | Should -Throw -ExpectedMessage '*does not exist.'
        }
        It 'ConvertTo-SalesforceMdapiFormat runs sf project convert source' {
            ConvertTo-SalesforceMdapiFormat -RootDir $script:src.FullName -SourceDir $script:src.FullName -OutputDir out -Manifest $script:manifest -Metadata ApexClass:A -PackageName pkg | Out-Null
            $expected = "project|convert|source|--root-dir|$($script:src.FullName)|--source-dir|$($script:src.FullName)|--output-dir|out|--manifest|$($script:manifest)|--metadata|ApexClass:A|--package-name|pkg|--json"
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
        }
        It 'Enable-SalesforceSourceBehavior previews with -WhatIf but still runs -DryRun' {
            Enable-SalesforceSourceBehavior -Behavior decomposeWorkflowBeta -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            Enable-SalesforceSourceBehavior -Behavior decomposeWorkflowBeta -DryRun -PreserveTempDir -TargetOrg me -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|convert|source-behavior|--behavior|decomposeWorkflowBeta|--dry-run|--preserve-temp-dir|--target-org|me|--json' }
            Enable-SalesforceSourceBehavior -Behavior decomposePermissionSetBeta2 -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|convert|source-behavior|--behavior|decomposePermissionSetBeta2|--json' }
            { Enable-SalesforceSourceBehavior -Behavior nope } | Should -Throw
        }
        It 'Get-SalesforceIgnoredFiles returns the ignored paths' {
            $files = @(Get-SalesforceIgnoredFiles -SourceDir $script:src.FullName)
            $files.Count | Should -Be 2
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "project|list|ignored|--source-dir|$($script:src.FullName)|--json" }
            Get-SalesforceIgnoredFiles | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|list|ignored|--json' }
        }
    }
}

Describe 'sf project parity: delete source and source tracking (issue 244)' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
            $script:cls = Join-Path $TestDrive 'Old Helper.cls'
            Set-Content -Path $script:cls -Value 'public class OldHelper {}'
        }
        It 'Remove-SalesforceSource deletes nothing under -WhatIf' {
            Remove-SalesforceSource -Metadata ApexClass:Old -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
        }
        It 'Remove-SalesforceSource passes every flag and never lets the CLI prompt' {
            Remove-SalesforceSource -SourceDir $script:cls -Metadata ApexClass:Old -ForceOverwrite -TrackSource -TestLevel SpecificTests -Tests T1, T2 -Wait 5 -DetailedResults -NoPrompt -TargetOrg me | Out-Null
            $expected = "project|delete|source|--source-dir|$($script:cls)|--metadata|ApexClass:Old|--force-overwrite|--track-source|--test-level|RunSpecifiedTests|--tests|T1|--tests|T2|--wait|5|--verbose|--no-prompt|--target-org|me|--json"
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
        }
        It 'Remove-SalesforceSource -CheckOnly runs without confirmation even under -WhatIf' {
            Remove-SalesforceSource -Metadata ApexClass:Old -CheckOnly -TestLevel RelevantTests -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|delete|source|--metadata|ApexClass:Old|--check-only|--test-level|RunRelevantTests|--no-prompt|--json' }
        }
        It 'Remove-SalesforceSource validates its input' {
            { Remove-SalesforceSource } | Should -Throw -ExpectedMessage 'Specify -SourceDir or -Metadata.'
            { Remove-SalesforceSource -SourceDir (Join-Path $TestDrive 'nope') -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist.'
            { Remove-SalesforceSource -Metadata ApexClass:Old -Tests T1 -Confirm:$false } | Should -Throw -ExpectedMessage '-Tests needs -TestLevel SpecificTests.'
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
        }
        It 'Remove-SalesforceSourceTracking and Reset-SalesforceSourceTracking preview with -WhatIf and run with --no-prompt' {
            Remove-SalesforceSourceTracking -TargetOrg me -WhatIf | Out-Null
            Reset-SalesforceSourceTracking -Revision 0 -TargetOrg me -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            Remove-SalesforceSourceTracking -TargetOrg me -NoPrompt | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|delete|tracking|--no-prompt|--target-org|me|--json' }
            Reset-SalesforceSourceTracking -Revision 12 -TargetOrg me -NoPrompt | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|reset|tracking|--revision|12|--no-prompt|--target-org|me|--json' }
            Reset-SalesforceSourceTracking -NoPrompt | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|reset|tracking|--no-prompt|--json' }
        }
        It 'Reset-SalesforceSourceTracking rejects a negative revision' {
            { Reset-SalesforceSourceTracking -Revision -1 -NoPrompt } | Should -Throw
        }
        It 'surfaces a CLI error as an exception' {
            Mock Invoke-Salesforce { '{"status":1,"name":"NoSourceTracking","message":"This org does not use source tracking."}' }
            { Remove-SalesforceSourceTracking -NoPrompt } | Should -Throw -ExpectedMessage '*source tracking*'
        }
    }
}

Describe 'sf project deploy pipeline commands (beta, issue 244)' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"id":"3A0000000000001AAA"}}' }
        }
        It 'Start-SalesforcePipelineDeploy passes every flag and honours -WhatIf' {
            Start-SalesforcePipelineDeploy -DevOpsCenterUsername doc -DevOpsCenterProjectName 'Sales App' -BranchName feature/x -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            Start-SalesforcePipelineDeploy -DevOpsCenterUsername doc -DevOpsCenterProjectName 'Sales App' -BranchName feature/x -BundleVersionName v1 -DeployAll -TestLevel SpecificTests -Tests A, B -Wait 20 -ConciseResults -Confirm:$false | Out-Null
            $expected = 'project|deploy|pipeline|start|--devops-center-username|doc|--devops-center-project-name|Sales App|--branch-name|feature/x|--bundle-version-name|v1|--deploy-all|--test-level|RunSpecifiedTests|--tests|A|--tests|B|--wait|20|--concise|--json'
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
        }
        It 'Start-SalesforcePipelineDeploy rejects -Async with -Wait, -Tests without a level, and an unsupported level' {
            { Start-SalesforcePipelineDeploy -DevOpsCenterUsername d -DevOpsCenterProjectName p -BranchName b -Async -Wait 1 -Confirm:$false } | Should -Throw -ExpectedMessage 'Specify only one of -Wait or -Async.'
            { Start-SalesforcePipelineDeploy -DevOpsCenterUsername d -DevOpsCenterProjectName p -BranchName b -Tests T -Confirm:$false } | Should -Throw -ExpectedMessage '-Tests needs -TestLevel SpecificTests.'
            { Start-SalesforcePipelineDeploy -DevOpsCenterUsername d -DevOpsCenterProjectName p -BranchName b -TestLevel RelevantTests -Confirm:$false } | Should -Throw
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
        }
        It 'Test-SalesforcePipelineDeploy runs the validate command and needs no confirmation' {
            Test-SalesforcePipelineDeploy -DevOpsCenterUsername doc -DevOpsCenterProjectName p -BranchName main -TestLevel TestsInOrg -Async -DetailedResults | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|pipeline|validate|--devops-center-username|doc|--devops-center-project-name|p|--branch-name|main|--test-level|RunLocalTests|--async|--verbose|--json' }
        }
        It 'Start-SalesforcePipelineQuickDeploy needs a job and asks first' {
            { Start-SalesforcePipelineQuickDeploy -DevOpsCenterUsername doc -Confirm:$false } | Should -Throw -ExpectedMessage 'Specify -JobId or -UseMostRecent.'
            { Start-SalesforcePipelineQuickDeploy -DevOpsCenterUsername doc -JobId '3A00000000000' -Confirm:$false } | Should -Throw -ExpectedMessage '*not a valid pipeline deploy job ID*'
            Start-SalesforcePipelineQuickDeploy -DevOpsCenterUsername doc -UseMostRecent -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            Start-SalesforcePipelineQuickDeploy -DevOpsCenterUsername doc -JobId 3A0000000000001AAA -Wait 5 -ConciseResults -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|pipeline|quick|--devops-center-username|doc|--job-id|3A0000000000001AAA|--wait|5|--concise|--json' }
        }
        It 'Get-SalesforcePipelineDeployStatus and Resume-SalesforcePipelineDeploy build their commands' {
            Get-SalesforcePipelineDeployStatus -DevOpsCenterUsername doc -UseMostRecent | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|pipeline|report|--devops-center-username|doc|--use-most-recent|--json' }
            Resume-SalesforcePipelineDeploy -DevOpsCenterUsername doc -JobId 3A0000000000001AAA -Wait 3 -DetailedResults | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|pipeline|resume|--devops-center-username|doc|--job-id|3A0000000000001AAA|--wait|3|--verbose|--json' }
            { Resume-SalesforcePipelineDeploy -DevOpsCenterUsername doc -JobId 3A0000000000001AAA -UseMostRecent } | Should -Throw -ExpectedMessage 'Specify only one of -JobId or -UseMostRecent.'
        }
    }
}

Describe 'psfdx-metadata exports the sf project parity cmdlets (issue 244)' {
    It 'exports the new cmdlets and keeps the helpers private' {
        $exports = (Get-Module psfdx-metadata).ExportedFunctions.Keys
        foreach ($n in 'New-SalesforceManifest', 'ConvertTo-SalesforceSourceFormat', 'ConvertTo-SalesforceMdapiFormat', 'Enable-SalesforceSourceBehavior', 'Get-SalesforceIgnoredFiles', 'Remove-SalesforceSource', 'Remove-SalesforceSourceTracking', 'Reset-SalesforceSourceTracking', 'Start-SalesforcePipelineDeploy', 'Test-SalesforcePipelineDeploy', 'Start-SalesforcePipelineQuickDeploy', 'Get-SalesforcePipelineDeployStatus', 'Resume-SalesforcePipelineDeploy') {
            $exports | Should -Contain $n
        }
        foreach ($n in 'Get-SalesforceDeployReportArguments', 'Get-SalesforceDestructiveChangeArguments', 'Get-SalesforcePipelineJobArguments', 'Get-SalesforcePipelineStartArguments') {
            $exports | Should -Not -Contain $n
        }
    }
}

Describe 'psfdx-metadata sf org parity (issue 248)' {
    InModuleScope 'psfdx-metadata' {
        Context 'Describe-SalesforceMetadataTypes -OutputFile' {
            It 'passes --output-file and still returns the type names' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"metadataObjects":[{"xmlName":"ApexClass"},{"xmlName":"CustomObject"}]}}' }
                $file = Join-Path $TestDrive 'types.json'
                $types = @(Describe-SalesforceMetadataTypes -OutputFile $file -TargetOrg dev1)
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "org|list|metadata-types|--target-org|dev1|--output-file|$file|--json" }
                $types | Should -Be @('ApexClass', 'CustomObject')
            }
            It 'stops before running sf when the output folder does not exist' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"metadataObjects":[]}}' }
                { Describe-SalesforceMetadataTypes -OutputFile (Join-Path $TestDrive 'nope/types.json') } | Should -Throw -ExpectedMessage '*does not exist*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Get-SalesforceMetadataComponents' {
            BeforeEach {
                Clear-SalesforceMetadataTypeCache
                Mock Describe-SalesforceMetadataTypes { @() }
                Mock Invoke-Salesforce { '{"status":0,"result":[{"fullName":"AccountService","type":"ApexClass","fileName":"classes/AccountService.cls","lastModifiedDate":"2026-11-01T10:00:00.000Z"},{"fullName":"OrderService","type":"ApexClass","fileName":"classes/OrderService.cls","lastModifiedDate":"2026-11-02T10:00:00.000Z"}]}' }
            }
            It 'builds the command and returns one object per component' {
                $components = @(Get-SalesforceMetadataComponents -MetadataType ApexClass -TargetOrg dev1)
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|list|metadata|--metadata-type|ApexClass|--target-org|dev1|--json' }
                $components.Count | Should -Be 2
                $components[1].fullName | Should -Be 'OrderService'
            }
            It 'passes -Folder and -OutputFile' {
                $file = Join-Path $TestDrive 'components.json'
                Get-SalesforceMetadataComponents -MetadataType Report -Folder 'Sales Reports' -OutputFile $file | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "org|list|metadata|--metadata-type|Report|--folder|Sales Reports|--output-file|$file|--json" }
            }
            It 'rejects an unknown metadata type and a missing output folder before running sf' {
                { Get-SalesforceMetadataComponents -MetadataType NotAType } | Should -Throw -ExpectedMessage '*Unknown metadata type*'
                { Get-SalesforceMetadataComponents -MetadataType ApexClass -OutputFile (Join-Path $TestDrive 'nope/out.json') } | Should -Throw -ExpectedMessage '*does not exist*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'returns nothing when the org has no components of the type' {
                Mock Invoke-Salesforce { '{"status":0,"result":[]}' }
                @(Get-SalesforceMetadataComponents -MetadataType ApexClass).Count | Should -Be 0
            }
            It 'reports a CLI failure' {
                Mock Invoke-Salesforce { '{"status":1,"message":"Folder is required for Report."}' }
                { Get-SalesforceMetadataComponents -MetadataType Report } | Should -Throw -ExpectedMessage '*Folder is required*'
            }
            It 'is exported' {
                (Get-Module psfdx-metadata).ExportedFunctions.Keys | Should -Contain 'Get-SalesforceMetadataComponents'
            }
        }
    }
}

Describe 'psfdx-metadata custom metadata type generators (issue 251)' {
    InModuleScope 'psfdx-metadata' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"typename":"Cfg","label":"Cfg"},"warnings":[]}' }
        }

        Context 'New-SalesforceCustomMetadataType' {
            It 'passes every option and returns the result object' {
                $t = New-SalesforceCustomMetadataType -TypeName Feature_Flag -Label 'Feature Flag' -PluralLabel 'Feature Flags' -Visibility Protected -OutputDirectory 'force-app/main/default/objects'
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'cmdt|generate|object|--type-name|Feature_Flag|--label|Feature Flag|--plural-label|Feature Flags|--visibility|Protected|--output-directory|force-app/main/default/objects|--json' }
                $t.typename | Should -Be 'Cfg'
            }
            It 'needs only the type name' {
                New-SalesforceCustomMetadataType -TypeName Cfg | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'cmdt|generate|object|--type-name|Cfg|--json' }
            }
            It 'rejects a name that is not an API name, a bad visibility, and a trailing line break' {
                foreach ($bad in 'My Type', 'Type;calc', '1Type', "Type`n", '') { { New-SalesforceCustomMetadataType -TypeName $bad } | Should -Throw }
                { New-SalesforceCustomMetadataType -TypeName Cfg -Visibility Hidden } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'throws the CLI message, for example outside a project' {
                Mock Invoke-Salesforce { '{"status":1,"name":"RequiresProjectError","message":"This command is required to run from within a Salesforce project directory."}' }
                { New-SalesforceCustomMetadataType -TypeName Cfg } | Should -Throw -ExpectedMessage '*Salesforce project directory*'
            }
        }

        Context 'New-SalesforceCustomMetadataField' {
            It 'passes each picklist value as its own flag' {
                New-SalesforceCustomMetadataField -Name Mode -Type Picklist -PicklistValues 'On', 'Off', 'Auto mode' -Label 'Mode' -OutputDirectory 'objects/Cfg__mdt' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'cmdt|generate|field|--name|Mode|--type|Picklist|--label|Mode|--picklist-values|On|--picklist-values|Off|--picklist-values|Auto mode|--output-directory|objects/Cfg__mdt|--json' }
            }
            It 'passes decimal places for a number field, including zero' {
                New-SalesforceCustomMetadataField -Name Threshold -Type Number -DecimalPlaces 0 | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'cmdt|generate|field|--name|Threshold|--type|Number|--decimal-places|0|--json' }
            }
            It 'accepts every documented field type and rejects others' {
                foreach ($type in 'Checkbox', 'Date', 'DateTime', 'Email', 'Number', 'Percent', 'Phone', 'Text', 'TextArea', 'LongTextArea', 'Url') {
                    { New-SalesforceCustomMetadataField -Name F -Type $type } | Should -Not -Throw
                }
                { New-SalesforceCustomMetadataField -Name F -Type Currency } | Should -Throw
            }
            It 'sends the type and visibility spelled as the CLI lists them, whatever case was typed' {
                New-SalesforceCustomMetadataField -Name Mode -Type picklist -PicklistValues A | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'cmdt|generate|field|--name|Mode|--type|Picklist|--picklist-values|A|--json' }
                New-SalesforceCustomMetadataField -Name Body -Type longtextarea | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'cmdt|generate|field|--name|Body|--type|LongTextArea|--json' }
                New-SalesforceCustomMetadataType -TypeName Cfg -Visibility packageprotected | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'cmdt|generate|object|--type-name|Cfg|--visibility|PackageProtected|--json' }
                New-SalesforceCustomMetadataTypeFromOrg -DevName X -Sobject Y__c -Visibility PROTECTED | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'cmdt|generate|fromorg|--dev-name|X|--sobject|Y__c|--visibility|Protected|--json' }
            }
            It 'checks the combinations before running sf' {
                Mock Invoke-Salesforce { throw 'must not run' }
                { New-SalesforceCustomMetadataField -Name F -Type Picklist } | Should -Throw -ExpectedMessage '*needs -PicklistValues*'
                { New-SalesforceCustomMetadataField -Name F -Type Text -PicklistValues A } | Should -Throw -ExpectedMessage '*only for a Picklist*'
                { New-SalesforceCustomMetadataField -Name F -Type Text -DecimalPlaces 2 } | Should -Throw -ExpectedMessage '*Number or Percent*'
                { New-SalesforceCustomMetadataField -Name 'bad name' -Type Text } | Should -Throw
            }
        }

        Context 'New-SalesforceCustomMetadataRecord' {
            It 'passes the field values as Field=Value after the flags, with the invariant culture' {
                $old = [System.Threading.Thread]::CurrentThread.CurrentCulture
                try {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
                    New-SalesforceCustomMetadataRecord -TypeName Cfg__mdt -RecordName Checkout -Label 'Check out' -Protected -Values ([ordered]@{ Mode__c = 'On mode'; Threshold__c = 2.5 }) | Out-Null
                } finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $old }
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'cmdt|generate|record|--type-name|Cfg__mdt|--record-name|Checkout|--label|Check out|--protected|true|Mode__c=On mode|Threshold__c=2.5|--json' }
            }
            It 'leaves --protected out by default and works without values' {
                New-SalesforceCustomMetadataRecord -TypeName Cfg__mdt -RecordName R1 | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'cmdt|generate|record|--type-name|Cfg__mdt|--record-name|R1|--json' }
            }
            It 'passes the input and output folders, and checks the input folder exists' {
                $in = Join-Path $TestDrive 'objects'; New-Item -ItemType Directory -Path $in | Out-Null
                New-SalesforceCustomMetadataRecord -TypeName Cfg__mdt -RecordName R1 -InputDirectory $in -OutputDirectory 'out dir' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "cmdt|generate|record|--type-name|Cfg__mdt|--record-name|R1|--input-directory|$in|--output-directory|out dir|--json" }
                { New-SalesforceCustomMetadataRecord -TypeName Cfg__mdt -RecordName R1 -InputDirectory (Join-Path $TestDrive 'nope') } | Should -Throw -ExpectedMessage '*does not exist*'
            }
            It 'refuses an unsafe field name or value before running sf' {
                Mock Invoke-Salesforce { throw 'must not run' }
                { New-SalesforceCustomMetadataRecord -TypeName Cfg__mdt -RecordName R -Values @{ 'Bad Field' = 'x' } } | Should -Throw -ExpectedMessage '*not a valid field name*'
                { New-SalesforceCustomMetadataRecord -TypeName Cfg__mdt -RecordName R -Values @{ '--json' = 'x' } } | Should -Throw -ExpectedMessage '*not a valid field name*'
                { New-SalesforceCustomMetadataRecord -TypeName Cfg__mdt -RecordName R -Values @{ A__c = 'say "hi"' } } | Should -Throw -ExpectedMessage '*double quote*'
                { New-SalesforceCustomMetadataRecord -TypeName Cfg__mdt -RecordName R -Values @{ A__c = "a`nb" } } | Should -Throw -ExpectedMessage '*line break*'
            }
            It 'writes a boolean value as true or false, which is what a Checkbox field needs' {
                New-SalesforceCustomMetadataRecord -TypeName Cfg__mdt -RecordName R -Values ([ordered]@{ On__c = $true; Off__c = $false }) | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'cmdt|generate|record|--type-name|Cfg__mdt|--record-name|R|On__c=true|Off__c=false|--json' }
            }
            It 'does not treat a value that looks like a flag as one' {
                New-SalesforceCustomMetadataRecord -TypeName Cfg__mdt -RecordName R -Values @{ A__c = '--json' } | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'cmdt|generate|record|--type-name|Cfg__mdt|--record-name|R|A__c=--json|--json' }
            }
        }

        Context 'New-SalesforceCustomMetadataRecordsFromCsv' {
            BeforeEach {
                $script:csv = Join-Path $TestDrive 'my flags.csv'
                Set-Content -LiteralPath $script:csv -Value "Name,Mode__c`nA,On`nB,Off"
                Mock Invoke-Salesforce { '{"status":0,"result":[{"typename":"Cfg","recordname":"A","label":"A"},{"typename":"Cfg","recordname":"B","label":"B"}]}' }
            }
            It 'returns one object per record' {
                $records = @(New-SalesforceCustomMetadataRecordsFromCsv -Csv $script:csv -TypeName Cfg -NameColumn Key -OutputDirectory 'out')
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "cmdt|generate|records|--csv|$($script:csv)|--type-name|Cfg|--name-column|Key|--output-directory|out|--json" }
                $records.Count | Should -Be 2
                $records[1].recordname | Should -Be 'B'
            }
            It 'checks the CSV and the input folder before running sf' {
                { New-SalesforceCustomMetadataRecordsFromCsv -Csv (Join-Path $TestDrive 'missing.csv') -TypeName Cfg } | Should -Throw -ExpectedMessage '*does not exist*'
                { New-SalesforceCustomMetadataRecordsFromCsv -Csv $script:csv -TypeName Cfg -InputDirectory (Join-Path $TestDrive 'nope') } | Should -Throw -ExpectedMessage '*does not exist*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'New-SalesforceCustomMetadataTypeFromOrg' {
            It 'passes every option and reads the org' {
                New-SalesforceCustomMetadataTypeFromOrg -DevName App_Config -Sobject App_Config__c -Label 'App Config' -PluralLabel 'App Configs' -Visibility PackageProtected -IgnoreUnsupported -TypeOutputDirectory 'types' -RecordsOutputDir 'records' -TargetOrg dev1 | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'cmdt|generate|fromorg|--dev-name|App_Config|--sobject|App_Config__c|--label|App Config|--plural-label|App Configs|--visibility|PackageProtected|--ignore-unsupported|--type-output-directory|types|--records-output-dir|records|--target-org|dev1|--json' }
            }
            It 'needs only the names, and rejects a bad object name' {
                New-SalesforceCustomMetadataTypeFromOrg -DevName X -Sobject Y__c | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'cmdt|generate|fromorg|--dev-name|X|--sobject|Y__c|--json' }
                { New-SalesforceCustomMetadataTypeFromOrg -DevName X -Sobject 'Y; drop' } | Should -Throw
            }
            It 'throws the CLI message when the object does not exist' {
                Mock Invoke-Salesforce { '{"status":1,"message":"sObject type ''Nope__c'' is not supported."}' }
                { New-SalesforceCustomMetadataTypeFromOrg -DevName X -Sobject Nope__c } | Should -Throw -ExpectedMessage '*not supported*'
            }
        }

        It 'exports the five generators' {
            $exports = (Get-Module psfdx-metadata).ExportedFunctions.Keys
            foreach ($n in 'New-SalesforceCustomMetadataType', 'New-SalesforceCustomMetadataField', 'New-SalesforceCustomMetadataRecord', 'New-SalesforceCustomMetadataRecordsFromCsv', 'New-SalesforceCustomMetadataTypeFromOrg') { $exports | Should -Contain $n }
        }
    }
}
