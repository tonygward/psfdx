# Ensure a clean module state before importing
Get-Module -Name 'psfdx-metadata' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-metadata.psd1'
$module = Import-Module $moduleManifest -Force -PassThru
$moduleName = $module.Name

Describe 'psfdx-metadata module' {
    InModuleScope $module {
        Context 'Retrieve-SalesforceComponent' {
            It 'throws when ChildName is provided without Name' {
                Mock Describe-SalesforceMetadataTypes { 'CustomField' } -ModuleName $moduleName
                $action = { Retrieve-SalesforceComponent -Type 'CustomField' -ChildName 'Field__c' }
                $action | Should -Throw
                try { & $action } catch { $_.Exception.Message | Should -Be "Specify -Name when using -ChildName." }
            }

            It 'builds retrieve command with child metadata and options' {
                Mock Describe-SalesforceMetadataTypes { 'CustomField' } -ModuleName $moduleName
                Mock Test-Path { $true }
                Mock Invoke-Salesforce { 'ok' } -ModuleName $moduleName

                Retrieve-SalesforceComponent -Type 'CustomField' -Name 'Account' -ChildName 'Field__c' -TargetOrg 'me' -Wait 7 -OutputDir 'outdir' -IgnoreConflicts

                Assert-MockCalled Invoke-Salesforce -ModuleName $moduleName -Times 1 -ParameterFilter {
                    ($Command -like 'sf project retrieve start --metadata CustomField:Account.Field__c*') -and
                    ($Command -like '* --target-org me*') -and
                    ($Command -like '* --wait 7*') -and
                    ($Command -like '* --output-dir "outdir"*') -and
                    ($Command -like '* --ignore-conflicts*')
                }
            }

            It 'validates output directory existence' {
                Mock Describe-SalesforceMetadataTypes { 'CustomField' } -ModuleName $moduleName
                Mock Test-Path { param($Path, $PathType) if ($Path -eq 'missing' -and $PathType -eq 'Container') { return $false } else { return $true } }

                $action = { Retrieve-SalesforceComponent -Type 'CustomField' -Name 'Account' -OutputDir 'missing' }
                $action | Should -Throw
                try { & $action } catch { $_.Exception.Message | Should -Be "Output directory 'missing' does not exist." }
            }
        }

        Context 'Retrieve-SalesforceMetadata' {
            It 'requires manifest file to exist' {
                Mock Test-Path {
                    param($Path, $PathType)
                    if ($PathType -eq 'Leaf') { return $false }
                    return $true
                }

                $action = { Retrieve-SalesforceMetadata -Manifest 'missing.xml' -OutputDir '.' }
                $action | Should -Throw
                try { & $action } catch { $_.Exception.Message | Should -Be "Manifest file 'missing.xml' does not exist." }
            }

            It 'builds manifest retrieve command' {
                Mock Test-Path { $true }
                Mock Invoke-Salesforce { 'ok' } -ModuleName $moduleName

                Retrieve-SalesforceMetadata -Manifest 'package.xml' -OutputDir 'mdapi' -Wait 5 -Unzip -TargetOrg 'me'

                Assert-MockCalled Invoke-Salesforce -ModuleName $moduleName -Times 1 -ParameterFilter {
                    ($Command -like 'sf project retrieve start --manifest "package.xml"*') -and
                    ($Command -like '* --target-metadata-dir "mdapi"*') -and
                    ($Command -like '* --wait 5*') -and
                    ($Command -like '* --unzip*') -and
                    ($Command -like '* --target-org me*')
                }
            }
        }

        Context 'Deploy-SalesforceComponent' {
            It 'requires a metadata type' {
                Mock Describe-SalesforceMetadataTypes { 'CustomField' } -ModuleName $moduleName

                $action = { Deploy-SalesforceComponent }
                $action | Should -Throw
                try { & $action } catch { $_.Exception.Message | Should -Be 'Specify -Type when deploying metadata.' }
            }

            It 'rejects conflicting result verbosity switches' {
                Mock Describe-SalesforceMetadataTypes { 'CustomField' } -ModuleName $moduleName

                $action = { Deploy-SalesforceComponent -Type 'CustomField' -ConciseResults -DetailedResults }
                $action | Should -Throw
                try { & $action } catch { $_.Exception.Message | Should -Be 'Specify only one of -ConciseResults or -DetailedResults.' }
            }

            It 'builds deploy command and returns processed result' {
                Mock Describe-SalesforceMetadataTypes { 'CustomField' } -ModuleName $moduleName
                Mock Invoke-Salesforce { '{"status":0}' } -ModuleName $moduleName
                Mock Show-SalesforceResult { param($Result) @{ fromShow = $Result } } -ModuleName $moduleName

                $out = Deploy-SalesforceComponent -Type 'CustomField' -Name 'Account.Field__c' -TargetOrg 'me' -IgnoreConflicts -IgnoreWarnings -IgnoreErrors -Wait 10 -DryRun -ConciseResults

                $out.fromShow | Should -Be '{"status":0}'
                Assert-MockCalled Invoke-Salesforce -ModuleName $moduleName -Times 1 -ParameterFilter {
                    ($Command -like 'sf project deploy start*') -and
                    ($Command -like '* --metadata CustomField:Account.Field__c*') -and
                    ($Command -like '* --target-org me*') -and
                    ($Command -like '* --ignore-conflicts*') -and
                    ($Command -like '* --ignore-warnings*') -and
                    ($Command -like '* --ignore-errors*') -and
                    ($Command -like '* --wait 10*') -and
                    ($Command -like '* --dry-run*') -and
                    ($Command -like '* --concise*') -and
                    ($Command -like '* --json*')
                }
            }
        }

        Context 'Deploy-SalesforceMetadata' {
            It 'enforces mutually exclusive input options' {
                $action = { Deploy-SalesforceMetadata -Manifest 'one' -InputDir 'two' }
                $action | Should -Throw
                try { & $action } catch { $_.Exception.Message | Should -Be 'Specify exactly one of -Manifest, -InputDir, or -ManifestPackage.' }
            }

            It 'verifies manifest path before deploy' {
                Mock Test-Path {
                    param($Path, $PathType)
                    if ($Path -eq 'missing.xml' -and $PathType -eq 'Leaf') { return $false }
                    return $true
                }

                $action = { Deploy-SalesforceMetadata -Manifest 'missing.xml' }
                $action | Should -Throw
                try { & $action } catch { $_.Exception.Message | Should -Be "Manifest file 'missing.xml' does not exist." }
            }

            It 'verifies input directory path before deploy' {
                Mock Test-Path {
                    param($Path, $PathType)
                    if ($Path -eq 'missingDir' -and $PathType -eq 'Container') { return $false }
                    return $true
                }

                $action = { Deploy-SalesforceMetadata -InputDir 'missingDir' }
                $action | Should -Throw
                try { & $action } catch { $_.Exception.Message | Should -Be "Input directory 'missingDir' does not exist." }
            }

            It 'builds deploy command from manifest' {
                Mock Test-Path { $true }
                Mock Invoke-Salesforce { '{"status":0}' } -ModuleName $moduleName
                Mock Show-SalesforceResult { param($Result) @{ fromShow = $Result } } -ModuleName $moduleName

                $out = Deploy-SalesforceMetadata -Manifest 'package.xml' -TargetOrg 'me' -IgnoreConflicts -IgnoreWarnings -IgnoreErrors

                $out.fromShow | Should -Be '{"status":0}'
                Assert-MockCalled Invoke-Salesforce -ModuleName $moduleName -Times 1 -ParameterFilter {
                    ($Command -like 'sf project deploy start*') -and
                    ($Command -like '* --manifest "package.xml"*') -and
                    ($Command -like '* --target-org me*') -and
                    ($Command -like '* --ignore-conflicts*') -and
                    ($Command -like '* --ignore-warnings*') -and
                    ($Command -like '* --ignore-errors*') -and
                    ($Command -like '* --json*')
                }
            }
        }

        Context 'Describe-SalesforceMetadataTypes' {
            BeforeEach {
                Mock Invoke-Salesforce { '{"status":0,"result":{"metadataObjects":[{"xmlName":"ApexClass"},{"xmlName":"CustomObject"}]}}' } -ModuleName $moduleName
            }

            It 'requests metadata types and parses json result' {
                $types = Describe-SalesforceMetadataTypes -TargetOrg 'me'
                $types | Should -HaveCount 2
                $types[0].xmlName | Should -Be 'ApexClass'

                Assert-MockCalled Invoke-Salesforce -ModuleName $moduleName -Times 1 -ParameterFilter {
                    ($Command -like 'sf org list metadata-types*') -and
                    ($Command -like '* --target-org me*') -and
                    ($Command -like '* --json*')
                }
            }
        }

        Context 'Describe-SalesforceFields' {
            BeforeEach {
                Mock Describe-SalesforceObject {
                    param($Name, $TargetOrg, $UseToolingApi)
                    [pscustomobject]@{
                        fields = @(
                            [pscustomobject]@{ name = 'B__c'; label = 'B'; type = 'Text'; byteLength = 40 },
                            [pscustomobject]@{ name = 'A__c'; label = 'A'; type = 'Number'; byteLength = 18 }
                        )
                    }
                } -ModuleName $moduleName
            }

            It 'returns sorted field metadata and forwards tooling switch' {
                $fields = Describe-SalesforceFields -ObjectName 'Sample__c' -TargetOrg 'me' -UseToolingApi
                $fields | Should -Not -BeNullOrEmpty
                $fields[0].name | Should -Be 'A__c'
                $fields[1].name | Should -Be 'B__c'

                Assert-MockCalled Describe-SalesforceObject -ModuleName $moduleName -Times 1 -ParameterFilter {
                    ($Name -eq 'Sample__c') -and
                    ($TargetOrg -eq 'me') -and
                    $UseToolingApi
                }
            }
        }

        Context 'Build-SalesforceQuery' {
            BeforeEach {
                Mock Describe-SalesforceFields {
                    @(
                        [pscustomobject]@{ name = 'Id' },
                        [pscustomobject]@{ name = 'CreatedDate' },
                        [pscustomobject]@{ name = 'Name' },
                        [pscustomobject]@{ name = 'OwnerId' },
                        [pscustomobject]@{ name = 'Custom__c' }
                    )
                } -ModuleName $moduleName
            }

            It 'builds field list and removes excluded categories' {
                $query = Build-SalesforceQuery -ObjectName 'Account' -ExcludeAuditFields -ExcludeNameFields -ExcludeContextFields
                $query | Should -Be 'SELECT Id,Custom__c FROM Account'
            }

            It 'returns empty string when no fields are returned' {
                Mock Describe-SalesforceFields { $null } -ModuleName $moduleName
                $query = Build-SalesforceQuery -ObjectName 'Contact'
                $query | Should -Be ''
            }
        }
    }
}
