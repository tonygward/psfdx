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
        BeforeAll {
            # The -Type validate set generator runs inside a PowerShell class at parameter-binding
            # time, which bypasses Pester mocks and invokes the real sf CLI. Stub a global sf
            # function so binding works without the CLI; empty metadataObjects makes the
            # generator fall back to its built-in default type list.
            function global:sf { '{"status":0,"result":{"metadataObjects":[]}}' }
        }
        AfterAll {
            Remove-Item -Path Function:\sf -Force -ErrorAction SilentlyContinue
        }
        BeforeEach {
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
        BeforeAll {
            # Stub sf CLI for the class-based -Type validate set generator (see Retrieve-SalesforceComponent)
            function global:sf { '{"status":0,"result":{"metadataObjects":[]}}' }
        }
        AfterAll {
            Remove-Item -Path Function:\sf -Force -ErrorAction SilentlyContinue
        }
        BeforeEach {
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
        BeforeAll {
            # Stub sf CLI for the class-based -Type validate set generator (see Retrieve-SalesforceComponent)
            function global:sf { '{"status":0,"result":{"metadataObjects":[]}}' }
        }
        AfterAll {
            Remove-Item -Path Function:\sf -Force -ErrorAction SilentlyContinue
        }
        BeforeEach {
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
    }
}
