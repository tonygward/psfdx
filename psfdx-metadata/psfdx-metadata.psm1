if (-not (Get-Variable -Scope Global -Name PsfdxSharedScriptLoader -ErrorAction SilentlyContinue)) {
    Set-Variable -Scope Global -Name PsfdxSharedScriptLoader -Value {
        param(
            [Parameter(Mandatory = $true)][string] $FileName,
            [switch] $Optional
        )

        $moduleBase = $ExecutionContext.SessionState.Module.ModuleBase
        $candidates = @()
        if ($moduleBase) {
            $candidates += Join-Path -Path $moduleBase -ChildPath (Join-Path '..' (Join-Path 'psfdx-shared' $FileName))
            $moduleRoot = Split-Path -Path $moduleBase -Parent
            if ($moduleRoot) {
                $candidates += Join-Path -Path $moduleRoot -ChildPath (Join-Path 'psfdx-shared' $FileName)
            }
        }

        $psModuleRoots = $env:PSModulePath -split [System.IO.Path]::PathSeparator
        foreach ($root in $psModuleRoots) {
            if (-not [string]::IsNullOrWhiteSpace($root)) {
                $candidates += Join-Path -Path $root -ChildPath (Join-Path 'psfdx-shared' $FileName)
            }
        }

        foreach ($candidate in $candidates | Select-Object -Unique) {
            try {
                $resolved = Resolve-Path -LiteralPath $candidate -ErrorAction Stop
                . $resolved.ProviderPath
                return
            } catch {
                continue
            }
        }

        switch ($FileName) {
            'Invoke-Salesforce.ps1' {
                if (-not (Get-Command -Name Invoke-Salesforce -ErrorAction SilentlyContinue)) {
                    function Invoke-Salesforce {
                        [CmdletBinding()]
                        Param(
                            [Parameter(Mandatory = $true)][string] $Command
                        )

                        Write-Verbose $Command
                        Invoke-Expression -Command $Command
                    }
                }
                return
            }
            'Show-SalesforceResult.ps1' {
                if (-not (Get-Command -Name Show-SalesforceResult -ErrorAction SilentlyContinue)) {
                    function Show-SalesforceResult {
                        [CmdletBinding()]
                        Param(
                            [Parameter(Mandatory = $true)][psobject] $Result,
                            [Parameter(Mandatory = $false)][switch] $ReturnRecords,
                            [Parameter(Mandatory = $false)][switch] $IncludeAttributes
                        )

                        $converted = $Result | ConvertFrom-Json
                        if ($converted.status -ne 0) {
                            Write-Debug ($Result | ConvertTo-Json)
                            $message = Get-SalesforceErrorMessage -Result $converted
                            throw $message
                        }

                        $out = $converted.result
                        if ($ReturnRecords) {
                            $records = $out.records
                            if ($null -eq $records) { return @() }
                            if ($IncludeAttributes) { return $records }
                            return ($records | Select-Object -ExcludeProperty attributes)
                        }
                        return $out
                    }

                    function Get-SalesforceErrorMessage {
                        [CmdletBinding()]
                        Param(
                            [Parameter(Mandatory = $true)][psobject] $Result
                        )

                        if ($Result -is [string]) {
                            Write-Debug $Result
                        } else {
                            Write-Debug ($Result | ConvertTo-Json -Depth 10)
                        }

                        $messages = @()

                        if ($Result.message) {
                            $messages += $Result.message
                        }

                        $deployFailures = Get-SalesforceDeployFailures -Result $Result
                        if ($deployFailures) {
                            $messages += $deployFailures
                        }

                        $testFailures = Get-SalesforceTestFailure -Result $Result
                        if ($testFailures) {
                            $messages += $testFailures
                        }

                        if (-not $messages) {
                            $messages += "Salesforce command failed with status $($Result.status)."
                        }

                        return ($messages -join [Environment]::NewLine)
                    }

                    function Get-SalesforceDeployFailures {
                        [CmdletBinding()]
                        Param(
                            [Parameter(Mandatory = $true)][psobject] $Result
                        )

                        $resultRoot = $Result.result
                        if ($null -eq $resultRoot) { return $null }

                        $details = $resultRoot.details
                        if ($null -eq $details) { return $null }

                        $componentFailures = $details.componentFailures
                        if (-not $componentFailures) {
                            return $null
                        }

                        return ($componentFailures | ForEach-Object {
                            $problem = $_.problem
                            $line = $_.lineNumber
                            $column = $_.columnNumber

                            if ([string]::IsNullOrWhiteSpace($problem)) {
                                return $null
                            }

                            if (($null -ne $line) -or ($null -ne $column)) {
                                $lineValue = if ($null -ne $line) { $line } else { '?' }
                                $columnValue = if ($null -ne $column) { $column } else { '?' }
                                "$problem ($($lineValue):$($columnValue))"
                            } else {
                                $problem
                            }
                        }) | Where-Object { $_ }
                    }

                    function Get-SalesforceTestFailure {
                        [CmdletBinding()]
                        Param(
                            [Parameter(Mandatory = $true)][psobject] $Result
                        )

                        $resultRoot = $Result.result
                        if ($null -eq $resultRoot) { return $null }

                        $details = $resultRoot.details
                        if ($null -eq $details) { return $null }

                        $runTestResult = $details.runTestResult
                        if ($null -eq $runTestResult) { return $null }

                        $failures = $runTestResult.failures
                        if (-not $failures) {
                            return $null
                        }

                        return ($failures | ForEach-Object {
                            $message = $_.message
                            $stack = $_.stackTrace
                            if ($stack) {
                                "$message $stack"
                            } else {
                                $message
                            }
                        })
                    }
                }
                return
            }
            'SalesforceApexTests.ps1' {
                if (-not (Get-Command -Name Get-SalesforceApexCliTestParams -ErrorAction SilentlyContinue)) {
                    function Get-SalesforceApexCliTestParams {
                        [CmdletBinding()]
                        Param(
                            [Parameter(Mandatory = $false)][string] $SourceDir,
                            [Parameter(Mandatory = $false)][ValidateSet(
                                'NoTests',
                                'SpecificTests',
                                'TestsClass',
                                'TestsInFolder',
                                'TestsInOrg',
                                'TestsInOrgAndPackages')][string] $TestLevel = 'NoTests',
                            [Parameter(Mandatory = $false)][string[]] $Tests
                        )

                        $value = ""
                        $testLevelMap = @{
                            'NoTests'               = 'NoTestRun'
                            'SpecificTests'         = 'RunSpecifiedTests'
                            'TestsClass'            = 'RunSpecifiedTests'
                            'TestsInFolder'         = 'RunSpecifiedTests'
                            'TestsInOrg'            = 'RunLocalTests'
                            'TestsInOrgAndPackages' = 'RunAllTestsInOrg'
                        }
                        $value += " --test-level " + $testLevelMap[$TestLevel]

                        if ($TestLevel -eq 'TestsClass') {
                            if (-not $SourceDir) {
                                throw "Specify -SourceDir when using -TestLevel TestsClass."
                            }
                            if (-not (Test-Path -LiteralPath $SourceDir)) {
                                throw "Source path '$SourceDir' does not exist."
                            }

                            $item = Get-Item -LiteralPath $SourceDir
                            if ($item.PSIsContainer) {
                                throw "Provide a file path for -SourceDir when using -TestLevel TestsClass."
                            }

                            $className = [System.IO.Path]::GetFileNameWithoutExtension($item.Name)
                            if (-not $className) {
                                throw "Unable to determine class name from '$SourceDir'."
                            }

                            $searchRoot = $item.Directory
                            if (-not $searchRoot) {
                                throw "Unable to determine directory for '$SourceDir'."
                            }

                            $escapedClassName = [regex]::Escape($className)
                            $classPattern = "\b$escapedClassName\b"

                            $Tests = Get-ChildItem -LiteralPath $searchRoot.FullName -Filter '*.cls' -File -ErrorAction SilentlyContinue |
                                Where-Object {
                                    $_.FullName -ne $item.FullName -and
                                    (Select-String -Path $_.FullName -Pattern '@isTest' -SimpleMatch -Quiet) -and
                                    (Select-String -Path $_.FullName -Pattern $classPattern -Quiet)
                                } |
                                ForEach-Object { $_.BaseName } |
                                Sort-Object -Unique

                            if (-not $Tests -or $Tests.Count -eq 0) {
                                throw "No Apex test classes in '$($searchRoot.FullName)' reference '$className'."
                            }
                        } elseif ($TestLevel -eq 'TestsInFolder') {
                            $TestsPath = $SourceDir
                            if (-not $TestsPath) {
                                $TestsPath = Get-Location
                            }
                            if (Test-Path -LiteralPath $TestsPath) {
                                $item = Get-Item -LiteralPath $TestsPath
                                if (-not $item.PSIsContainer -and $item.Directory) {
                                    $TestsPath = $item.Directory.FullName
                                }
                            }
                            $Tests = Get-SalesforceApexTestClassNamesFromPath -Path $TestsPath
                            if (-not $Tests -or $Tests.Count -eq 0) {
                                throw "No Apex test classes found in '$TestsPath'."
                            }
                        } elseif ($TestLevel -eq 'SpecificTests') {
                            if (-not $Tests -or $Tests.Count -eq 0) {
                                throw "Provide one or more -Tests when using -TestLevel SpecificTests."
                            }
                            $Tests = $Tests |
                                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                                Sort-Object -Unique
                            if (-not $Tests -or $Tests.Count -eq 0) {
                                throw "Provided -Tests values are empty."
                            }
                        }

                        $value += ConvertTo-SalesforceCliApexTestParams -TestClassNames $Tests
                        return $value
                    }
                }

                if (-not (Get-Command -Name Get-SalesforceApexTestClassNamesFromPath -ErrorAction SilentlyContinue)) {
                    function Get-SalesforceApexTestClassNamesFromPath {
                        [CmdletBinding()]
                        Param(
                            [Parameter(Mandatory = $true)][string] $Path
                        )

                        if (-not (Test-Path -LiteralPath $Path)) {
                            throw "Path '$Path' does not exist."
                        }

                        $item = Get-Item -LiteralPath $Path
                        if ($item.PSIsContainer) {
                            $searchRoot = $item.FullName
                        } else {
                            $directory = $item.Directory
                            $searchRoot = if ($directory) { $directory.FullName } else { $item.FullName }
                        }

                        $testFiles = Get-ChildItem -LiteralPath $searchRoot -Recurse -Filter '*.cls' -File -ErrorAction SilentlyContinue
                        if (-not $testFiles) {
                            return @()
                        }

                        $testFiles = $testFiles | Where-Object {
                            Select-String -Path $_.FullName -Pattern '@isTest' -SimpleMatch -Quiet
                        }

                        return @($testFiles | ForEach-Object { $_.BaseName } | Sort-Object -Unique)
                    }
                }

                if (-not (Get-Command -Name ConvertTo-SalesforceCliApexTestParams -ErrorAction SilentlyContinue)) {
                    function ConvertTo-SalesforceCliApexTestParams {
                        [CmdletBinding()]
                        Param(
                            [Parameter(Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
                            [AllowNull()]
                            [AllowEmptyCollection()]
                            [string[]] $TestClassNames = @()
                        )

                        begin { $all = @() }

                        process {
                            if ($null -ne $TestClassNames) {
                                $all += $TestClassNames | ForEach-Object { $_ } | Where-Object { $_ -and $_.Trim() }
                            }
                        }

                        end {
                            if ($all.Count -eq 0) { return "" }
                            $parts = $all | ForEach-Object { "--tests $($_.Trim())" }
                            ' ' + ($parts -join ' ')
                        }
                    }
                }

                return
            }
            default {
                if (-not $Optional) {
                    throw "Unable to locate psfdx-shared script '$FileName'. Reinstall psfdx to ensure shared scripts are installed."
                }
            }
        }
    }
}

$importPsfdxSharedScript = (Get-Variable -Scope Global -Name PsfdxSharedScriptLoader -ValueOnly).GetNewClosure()

& $importPsfdxSharedScript -FileName 'Invoke-Salesforce.ps1'
& $importPsfdxSharedScript -FileName 'Show-SalesforceResult.ps1'
& $importPsfdxSharedScript -FileName 'SalesforceApexTests.ps1' -Optional

class SalesforceMetadataTypeGenerator : System.Management.Automation.IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        $types = Describe-SalesforceMetadataTypes
        if (-not $types -or $types.Count -eq 0) {
            $types = Get-SalesforceMetadataTypesDefault
        }
        return (@($types) + 'CustomField', 'ValidationRule') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    }
}

function Get-SalesforceMetadataTypesDefault {
    [CmdletBinding()]
    Param()

    return @(
        'AIApplication'
        'AIApplicationConfig'
        'ActionLauncherItemDef'
        'ActionLinkGroupTemplate'
        'AnalyticSnapshot'
        'AnimationRule'
        'ApexClass'
        'ApexComponent'
        'ApexEmailNotifications'
        'ApexPage'
        'ApexTestSuite'
        'ApexTrigger'
        'AppFrameworkTemplateBundle'
        'AppMenu'
        'AppointmentAssignmentPolicy'
        'AppointmentSchedulingPolicy'
        'ApprovalProcess'
        'AssignmentRules'
        'AuraDefinitionBundle'
        'AuthProvider'
        'AutoResponseRules'
        'BlacklistedConsumer'
        'BrandingSet'
        'BriefcaseDefinition'
        'CallCenter'
        'CallCoachingMediaProvider'
        'CanvasMetadata'
        'Certificate'
        'ChannelLayout'
        'ChatterExtension'
        'ChoiceList'
        'CleanDataService'
        'Community'
        'ConnectedApp'
        'ContentAsset'
        'ContentTypeBundle'
        'ConvIntelligenceSignalRule'
        'ConversationMessageDefinition'
        'CorsWhitelistOrigin'
        'CspTrustedSite'
        'CustomApplication'
        'CustomApplicationComponent'
        'CustomFeedFilter'
        'CustomHelpMenuSection'
        'CustomIndex'
        'CustomLabels'
        'CustomMetadata'
        'CustomNotificationType'
        'CustomObject'
        'CustomObjectTranslation'
        'CustomPageWebLink'
        'CustomPermission'
        'CustomSite'
        'CustomTab'
        'Dashboard'
        'DataCategoryGroup'
        'DataWeaveResource'
        'DelegateGroup'
        'DigitalExperienceBundle'
        'Document'
        'DuplicateRule'
        'EclairGeoData'
        'EmailServicesFunction'
        'EmailTemplate'
        'EmbeddedServiceBranding'
        'EmbeddedServiceConfig'
        'EmbeddedServiceFlowConfig'
        'EmbeddedServiceMenuSettings'
        'EscalationRules'
        'EventRelayConfig'
        'ExperienceContainer'
        'ExperiencePropertyTypeBundle'
        'ExternalAuthIdentityProvider'
        'ExternalClientApplication'
        'ExternalCredential'
        'ExternalDataSource'
        'ExternalServiceRegistration'
        'ExtlClntAppConfigurablePolicies'
        'ExtlClntAppGlobalOauthSettings'
        'ExtlClntAppMobileConfigurablePolicies'
        'ExtlClntAppMobileSettings'
        'ExtlClntAppNotificationSettings'
        'ExtlClntAppOauthConfigurablePolicies'
        'ExtlClntAppOauthSettings'
        'ExtlClntAppPushConfigurablePolicies'
        'ExtlClntAppPushSettings'
        'ExtlClntAppSamlConfigurablePolicies'
        'FieldRestrictionRule'
        'FlexiPage'
        'Flow'
        'FlowCategory'
        'FlowDefinition'
        'FlowTest'
        'ForecastingFilter'
        'ForecastingFilterCondition'
        'ForecastingGroup'
        'ForecastingSourceDefinition'
        'ForecastingType'
        'ForecastingTypeSource'
        'GatewayProviderPaymentMethodType'
        'GlobalValueSet'
        'GlobalValueSetTranslation'
        'Group'
        'HomePageComponent'
        'HomePageLayout'
        'IPAddressRange'
        'IframeWhiteListUrlSettings'
        'InboundNetworkConnection'
        'InstalledPackage'
        'Layout'
        'LeadConvertSettings'
        'Letterhead'
        'LightningBolt'
        'LightningComponentBundle'
        'LightningExperienceTheme'
        'LightningMessageChannel'
        'LightningOnboardingConfig'
        'LightningTypeBundle'
        'LiveChatSensitiveDataRule'
        'MLDataDefinition'
        'MLPredictionDefinition'
        'MLRecommendationDefinition'
        'ManagedContentType'
        'ManagedEventSubscription'
        'MatchingRules'
        'MessagingChannel'
        'MobileApplicationDetail'
        'MutingPermissionSet'
        'MyDomainDiscoverableLogin'
        'NamedCredential'
        'NetworkBranding'
        'NotificationTypeConfig'
        'OauthCustomScope'
        'OauthTokenExchangeHandler'
        'OutboundNetworkConnection'
        'PathAssistant'
        'PaymentGatewayProvider'
        'PermissionSet'
        'PermissionSetGroup'
        'PlatformCachePartition'
        'PlatformEventChannel'
        'PlatformEventChannelMember'
        'PlatformEventSubscriberConfig'
        'PostTemplate'
        'ProcessFlowMigration'
        'ProductAttributeSet'
        'Profile'
        'ProfilePasswordPolicy'
        'ProfileSessionSetting'
        'Prompt'
        'PublicKeyCertificate'
        'PublicKeyCertificateSet'
        'Queue'
        'QuickAction'
        'RecommendationStrategy'
        'RecordActionDeployment'
        'RedirectWhitelistUrl'
        'RemoteSiteSetting'
        'Report'
        'ReportType'
        'RestrictionRule'
        'Role'
        'SamlSsoConfig'
        'Scontrol'
        'SearchCustomization'
        'SearchOrgWideObjectConfig'
        'Settings'
        'SharingRules'
        'SharingSet'
        'SiteDotCom'
        'Skill'
        'SkillType'
        'StandardValueSet'
        'StandardValueSetTranslation'
        'StaticResource'
        'SynonymDictionary'
        'TopicsForObjects'
        'TransactionSecurityPolicy'
        'UiFormatSpecificationSet'
        'UserProvisioningConfig'
        'WaveAnalyticAssetCollection'
        'Workflow'
    )
}

#region Retrieve

function Retrieve-SalesforceComponent {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string][ValidateSet([SalesforceMetadataTypeGenerator])] $Type,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string] $ChildName,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][switch] $IgnoreConflicts
    )

    if ($ChildName -and -not $Name) {
        throw "Specify -Name when using -ChildName."
    }

    $command = "sf project retrieve start --metadata $Type"
    if ($Name) {
        $command += ":$Name"
        if ($ChildName) { $command += ".$ChildName" }
    }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    if ($PSBoundParameters.ContainsKey('Wait')) { $command += " --wait $Wait" }
    if ($OutputDir) {
        if (-not (Test-Path -Path $OutputDir -PathType Container)) {
            throw "Output directory '$OutputDir' does not exist."
        }
        $command += " --output-dir `"$OutputDir`""
    }
    if ($IgnoreConflicts) { $command += " --ignore-conflicts" }
    Invoke-Salesforce -Command $command
}

function Retrieve-SalesforceMetadata {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Manifest,
        [Parameter(Mandatory = $true)][string] $OutputDir,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $Unzip,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if (-not (Test-Path -Path $Manifest -PathType Leaf)) {
        throw "Manifest file '$Manifest' does not exist."
    }
    if (-not (Test-Path -Path $OutputDir -PathType Container)) {
        throw "Output directory '$OutputDir' does not exist."
    }

    $command = "sf project retrieve start --manifest `"$Manifest`""
    $command += " --target-metadata-dir `"$OutputDir`""
    if ($PSBoundParameters.ContainsKey('Wait')) { $command += " --wait $Wait" }
    if ($Unzip) { $command += " --unzip" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }

    Invoke-Salesforce -Command $command
}

function Retrieve-SalesforcePackage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $OutputDir,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if (-not (Test-Path -Path $OutputDir -PathType Container)) {
        throw "Output directory '$OutputDir' does not exist."
    }

    $command = "sf project retrieve start --package-name `"$Name`""
    $command += " --output-dir `"$OutputDir`""
    if ($PSBoundParameters.ContainsKey('Wait')) { $command += " --wait $Wait" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }

    Invoke-Salesforce -Command $command
}

function Retrieve-SalesforceField {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,
        [Parameter(Mandatory = $true)][string] $FieldName,
        [Parameter(Mandatory = $false)][string] $TargetOrg)
    Retrieve-SalesforceComponent -Type 'CustomField' -Name $ObjectName -ChildName $FieldName -TargetOrg $TargetOrg
}

function Retrieve-SalesforceValidationRule {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,
        [Parameter(Mandatory = $true)][string] $RuleName,
        [Parameter(Mandatory = $false)][string] $TargetOrg)
    Retrieve-SalesforceComponent -Type 'ValidationRule' -Name $ObjectName -ChildName $RuleName -TargetOrg $TargetOrg
}

function Retrieve-SalesforceOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $IncludePackages
    )

    $command = "sf force source manifest create --from-org $TargetOrg"
    $command += " --name=allMetadata"
    $command += " --output-dir ."
    if ($IncludePackages) { $command += " --include-packages=unlocked" }
    Invoke-Salesforce -Command $command

    $command = "sf project retrieve start --target-org $TargetOrg"
    $command += " --manifest allMetadata.xml"
    Invoke-Salesforce -Command $command
}

#endregion

#region Deploy

function Deploy-SalesforceComponent {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string][ValidateSet([SalesforceMetadataTypeGenerator])] $Type,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string] $SourceDir,
        [Parameter(Mandatory = $false)][switch] $IgnoreConflicts,
        [Parameter(Mandatory = $false)][switch] $IgnoreWarnings,
        [Parameter(Mandatory = $false)][switch] $IgnoreErrors,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][ValidateSet(
            'NoTests',
            'SpecificTests',
            'TestsClass',
            'TestsInFolder',
            'TestsInOrg',
            'TestsInOrgAndPackages')][string] $TestLevel = 'NoTests',
        [Parameter(Mandatory = $false)][string[]] $Tests,
        [Parameter(Mandatory = $false)][switch] $DryRun,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if ($ConciseResults -and $DetailedResults) {
        throw "Specify only one of -ConciseResults or -DetailedResults."
    }

    if (-not $Type -and -not $SourceDir) {
        throw "Specify -Type or -SourceDir when deploying metadata."
    }

    if (-not $Type -and $Name) {
        throw "Specify -Type when using -Name."
    }

    $command = "sf project deploy start"
    if ($Type) {
        $command += " --metadata $Type"
        if ($Name) { $command += ":$Name" }
    }
    if ($SourceDir) {
        if (-not (Test-Path -LiteralPath $SourceDir)) {
            throw "Source path '$SourceDir' does not exist."
        }
        $command += " --source-dir `"$SourceDir`""
    }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    if ($IgnoreConflicts) { $command += " --ignore-conflicts" }
    if ($IgnoreWarnings) { $command += " --ignore-warnings" }
    if ($IgnoreErrors) { $command += " --ignore-errors" }
    if ($PSBoundParameters.ContainsKey('Wait')) { $command += " --wait $Wait" }

    $command += Get-SalesforceApexCliTestParams -SourceDir $SourceDir -TestLevel $TestLevel -Tests $Tests

    if ($DryRun) { $command += " --dry-run" }
    if ($ConciseResults) { $command += " --concise" }
    if ($DetailedResults) { $command += " --verbose" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Deploy-SalesforceMetadata {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Manifest,
        [Parameter(Mandatory = $false)][string] $InputDir,
        [Parameter(Mandatory = $false)][switch] $ManifestPackage,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $IgnoreConflicts,
        [Parameter(Mandatory = $false)][switch] $IgnoreWarnings,
        [Parameter(Mandatory = $false)][switch] $IgnoreErrors
    )

    $optionsProvided = 0
    if ($Manifest) { $optionsProvided++ }
    if ($InputDir) { $optionsProvided++ }
    if ($ManifestPackage) { $optionsProvided++ }
    if ($optionsProvided -ne 1) {
        throw "Specify exactly one of -Manifest, -InputDir, or -ManifestPackage."
    }

    if ($Manifest -and -not (Test-Path -Path $Manifest -PathType Leaf)) {
        throw "Manifest file '$Manifest' does not exist."
    }
    if ($InputDir -and -not (Test-Path -Path $InputDir -PathType Container)) {
        throw "Input directory '$InputDir' does not exist."
    }

    $command = "sf project deploy start"
    if ($Manifest) { $command += " --manifest `"$Manifest`"" }
    if ($InputDir) { $command += " --metadata-dir `"$InputDir`"" }
    if ($ManifestPackage) { $command += " --single-package" }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    if ($IgnoreConflicts) { $command += " --ignore-conflicts" }
    if ($IgnoreWarnings) { $command += " --ignore-warnings" }
    if ($IgnoreErrors) { $command += " --ignore-errors" }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

#endregion

#region Describe

function Describe-SalesforceObjects {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $command = "sf sobject list"
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Describe-SalesforceObject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    $command = "sf sobject describe"
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $command += " --target-org $TargetOrg" }
    $command += " --sobject $Name"
    if ($UseToolingApi) { $command += " --use-tooling-api" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Describe-SalesforceFields {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    $result = Describe-SalesforceObject -Name $ObjectName -TargetOrg $TargetOrg -UseToolingApi:$UseToolingApi
    $result = $result.fields
    $result = $result | Select-Object name, label, type, byteLength | Sort-Object name
    return $result
}

#endregion

#region Types and Utilities

function Describe-SalesforceMetadataTypes {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $command = "sf org list metadata-types"
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) {
        $command += " --target-org $TargetOrg"
    }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    $result = $result | ConvertFrom-Json
    $metadataObjects = $result.result.metadataObjects
    if (-not $metadataObjects) {
        return @()
    }
    return $metadataObjects |
        ForEach-Object { $_.xmlName } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function Build-SalesforceQuery {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi,

        [Parameter(Mandatory = $false)][switch] $ExcludeAuditFields,
        [Parameter(Mandatory = $false)][switch] $ExcludeNameFields,
        [Parameter(Mandatory = $false)][switch] $ExcludeContextFields
    )
    $fields = Describe-SalesforceFields -ObjectName $ObjectName -TargetOrg $TargetOrg -UseToolingApi:$UseToolingApi
    if ($null -eq $fields) {
        return ""
    }

    $fieldNames = @()
    foreach ($field in $fields) {
        $fieldNames += $field.name
    }
    if ($ExcludeAuditFields) {
        $auditFields = @(
            'CreatedById',
            'CreatedDate',
            'LastModifiedById',
            'LastModifiedDate',
            'SystemModstamp',
            'IsDeleted'
        )
        $fieldNames = $fieldNames | Where-Object { $auditFields -notcontains $_ }
    }
    if ($ExcludeNameFields) {
        $nameFields = @(
            'Name',
            'FirstName',
            'LastName',
            'Subject'
        )
        $fieldNames = $fieldNames | Where-Object { $nameFields -notcontains $_ }
    }
    if ($ExcludeContextFields) {
        $contextFields = @(
            'OwnerId',
            'RecordTypeId',
            'CurrencyIsoCode',
            'Division'
        )
        $fieldNames = $fieldNames | Where-Object { $contextFields -notcontains $_ }
    }
    $value = "SELECT "
    foreach ($fieldName in $fieldNames) {
        $value += $fieldName + ","
    }
    $value = $value.TrimEnd(",")
    $value += " FROM $ObjectName"
    return $value
}

#endregion
