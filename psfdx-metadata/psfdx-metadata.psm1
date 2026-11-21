function Import-PsfdxSharedModule {
    # Loads psfdx-shared for the module this copy sits in. Keep every copy identical.
    #
    # Contract: the modules release in lockstep, so psfdx-shared must have the same Major.Minor as the importing module and
    # a version no lower than it. A newer patch is fine; an older one, or a different minor, is not.
    #
    # Resolution is deterministic. Versions are compared as [version], never as text.
    #   1. A loaded copy that is compatible (the highest one) is used as it is.
    #   2. Otherwise the first tier that has a compatible copy wins, and the highest version within the tier:
    #      the sibling folder (source checkout, zip install, flat install, Gallery bundle), then sibling version
    #      folders (<Modules>/psfdx-shared/<version>), then PSModulePath.
    #   3. A loaded copy that is not compatible is removed and replaced. If nothing compatible exists the
    #      function throws and says what it found; it never carries on with the wrong version.
    [CmdletBinding()]
    param(
        [string] $ModuleName = 'psfdx-shared',
        [string] $ModuleRoot = $PSScriptRoot,
        [version] $OwnVersion
    )

    $readVersion = {
        param([string] $Manifest)
        try { return [version](Import-PowerShellDataFile -LiteralPath $Manifest).ModuleVersion } catch { return $null }
    }

    # The module's own version comes from its manifest next to this file: the module's version is not set yet while its .psm1 loads.
    if ((-not $PSBoundParameters.ContainsKey('OwnVersion')) -and $PSCommandPath) {
        $ownManifest = [System.IO.Path]::ChangeExtension($PSCommandPath, '.psd1')
        if (Test-Path -LiteralPath $ownManifest) { $OwnVersion = & $readVersion $ownManifest }
    }
    $versionKnown = ($null -ne $OwnVersion) -and ($OwnVersion -gt [version]'0.0')
    $isCompatible = {
        param([version] $Version)
        if (-not $versionKnown) { return $true }
        return (($Version.Major -eq $OwnVersion.Major) -and ($Version.Minor -eq $OwnVersion.Minor) -and ($Version -ge $OwnVersion))
    }

    $loaded = @(Get-Module -Name $ModuleName -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending)
    $loadedCompatible = @($loaded | Where-Object { & $isCompatible $_.Version }) | Select-Object -First 1
    if ($loadedCompatible) {
        Import-Module -ModuleInfo $loadedCompatible -ErrorAction Stop
        return
    }

    $found = @()

    # Tier 1: the sibling folder.
    $tier = @()
    $parent = Split-Path -Path $ModuleRoot -Parent
    if ($parent) {
        $manifest = Join-Path -Path $parent -ChildPath (Join-Path $ModuleName "$ModuleName.psd1")
        if (Test-Path -LiteralPath $manifest) {
            $version = & $readVersion $manifest
            if ($version) { $tier += [pscustomobject]@{ Path = $manifest; Version = $version } }
        }
    }
    $found += , $tier

    # Tier 2: sibling version folders. Only when this module itself sits in a version folder (<Modules>/<name>/<version>).
    $tier = @()
    $ownLeaf = [version] '0.0'
    if ($parent -and [version]::TryParse((Split-Path -Path $ModuleRoot -Leaf), [ref] $ownLeaf)) {
        $modulesRoot = Split-Path -Path $parent -Parent
        if ($modulesRoot) {
            $sharedBase = Join-Path -Path $modulesRoot -ChildPath $ModuleName
            if (Test-Path -LiteralPath $sharedBase) {
                foreach ($dir in @(Get-ChildItem -LiteralPath $sharedBase -Directory -ErrorAction SilentlyContinue)) {
                    $dirVersion = [version] '0.0'
                    if (-not [version]::TryParse($dir.Name, [ref] $dirVersion)) { continue }
                    $manifest = Join-Path -Path $dir.FullName -ChildPath "$ModuleName.psd1"
                    if (Test-Path -LiteralPath $manifest) {
                        $version = & $readVersion $manifest
                        if ($version) { $tier += [pscustomobject]@{ Path = $manifest; Version = $version } }
                    }
                }
            }
        }
    }
    $found += , $tier

    # Tier 3: PSModulePath.
    $tier = @()
    foreach ($item in @(Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue)) {
        if ($item.Path) { $tier += [pscustomobject]@{ Path = $item.Path; Version = $item.Version } }
    }
    $found += , $tier

    foreach ($tier in $found) {
        $match = @($tier | Where-Object { & $isCompatible $_.Version } | Sort-Object -Property Version -Descending) | Select-Object -First 1
        if ($match) {
            # Remove the stale copies first: -Force alone would leave two modules of the same name loaded.
            foreach ($stale in $loaded) { Remove-Module -ModuleInfo $stale -Force -ErrorAction SilentlyContinue }
            Import-Module -Name $match.Path -ErrorAction Stop
            return
        }
    }

    $needs = "$ModuleName $($OwnVersion.Major).$($OwnVersion.Minor).x, version $OwnVersion or newer"
    $message = "Cannot load $ModuleName for module version ${OwnVersion}: it needs $needs."
    $seen = @($loaded | ForEach-Object { "$($_.Version) (loaded)" }) + @($found | ForEach-Object { $_ } | ForEach-Object { "$($_.Version) ($($_.Path))" })
    if ($seen.Count -gt 0) {
        $message += " Found only: $($seen -join '; ')."
    } else {
        $message += " It was not found."
    }
    $message += " Install matching versions of every psfdx module (Install-Module psfdx, or reinstall from the same release)"
    if ($loaded.Count -gt 0) { $message += ", then start a new session or run Remove-Module $ModuleName -Force" }
    throw ($message + '.')
}

Import-PsfdxSharedModule

# The valid -Type values feed tab-completion and Assert-SalesforceMetadataType, and the org
# round-trip behind them costs seconds, so they are resolved once per session. Call
# Clear-SalesforceMetadataTypeCache after connecting to an org (or re-import the module)
# to pick up types that were not visible when the cache was first populated.
# -Type uses an ArgumentCompleter rather than [ValidateSet([Generator])] because
# IValidateSetValuesGenerator needs PowerShell 6+ and this module supports 5.1. The completer
# scriptblock runs in the caller's scope, so it calls back into the module to reach the private helper.
$script:SalesforceMetadataTypeCache = $null

function Complete-SalesforceMetadataType {
    Param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    Get-SalesforceMetadataTypeValidValues |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

function Assert-SalesforceMetadataType {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Type)
    $validTypes = Get-SalesforceMetadataTypeValidValues
    if ($validTypes -notcontains $Type) {
        throw "Unknown metadata type '$Type'. Run Describe-SalesforceMetadataTypes to list valid types, or Clear-SalesforceMetadataTypeCache after connecting to a different org."
    }
}

function Get-SalesforceMetadataTypeValidValues {
    [CmdletBinding()]
    Param()

    if ($script:SalesforceMetadataTypeCache) {
        return $script:SalesforceMetadataTypeCache
    }

    $types = $null
    try {
        $types = Describe-SalesforceMetadataTypes
    } catch {
        Write-Verbose ("Could not list metadata types from the org: " + $_.Exception.Message)
    }

    if (-not $types -or (@($types).Count -eq 0)) {
        Write-Verbose "Falling back to the built-in metadata type list"
        $types = Get-SalesforceMetadataTypesDefault
    }

    $script:SalesforceMetadataTypeCache = (@($types) + 'CustomField', 'ValidationRule') |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique

    return $script:SalesforceMetadataTypeCache
}

function Clear-SalesforceMetadataTypeCache {
    [CmdletBinding()]
    Param()
    $script:SalesforceMetadataTypeCache = $null
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
        [Parameter(Mandatory = $false)][ArgumentCompleter({ & (Get-Module psfdx-metadata -All | Select-Object -First 1) { Complete-SalesforceMetadataType @args } @args })][string] $Type,
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

    if ([string]::IsNullOrWhiteSpace($Type)) {
        throw "Specify -Type when retrieving a component."
    }
    Assert-SalesforceMetadataType -Type $Type

    $metadata = $Type
    if ($Name) {
        $metadata += ":$Name"
        if ($ChildName) { $metadata += ".$ChildName" }
    }
    $arguments = @('project', 'retrieve', 'start', '--metadata', $metadata)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    if ($OutputDir) {
        if (-not (Test-Path -Path $OutputDir -PathType Container)) {
            throw "Output directory '$OutputDir' does not exist."
        }
        $arguments += @('--output-dir', $OutputDir)
    }
    if ($IgnoreConflicts) { $arguments += '--ignore-conflicts' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
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

    $arguments = @('project', 'retrieve', 'start', '--manifest', $Manifest)
    $arguments += @('--target-metadata-dir', $OutputDir)
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    if ($Unzip) { $arguments += '--unzip' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
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

    $arguments = @('project', 'retrieve', 'start', '--package-name', $Name)
    $arguments += @('--output-dir', $OutputDir)
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
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

    $arguments = @('project', 'generate', 'manifest')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) {
        $arguments += @('--from-org', $TargetOrg)
    }
    $arguments += '--name=allMetadata'
    $arguments += @('--output-dir', '.')
    if ($IncludePackages) { $arguments += '--include-packages=unlocked' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams

    $arguments = @('project', 'retrieve', 'start')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) {
        $arguments += @('--target-org', $TargetOrg)
    }
    $arguments += @('--manifest', 'allMetadata.xml')
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

#endregion

#region Deploy

function Deploy-SalesforceComponent {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][ArgumentCompleter({ & (Get-Module psfdx-metadata -All | Select-Object -First 1) { Complete-SalesforceMetadataType @args } @args })][string] $Type,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string] $SourceDir,
        [Parameter(Mandatory = $false)][switch] $IgnoreConflicts,
        [Parameter(Mandatory = $false)][switch] $IgnoreWarnings,
        [Parameter(Mandatory = $false)][switch] $IgnoreErrors,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][ValidateSet(
            'NoTests',
            'SpecificTests',
            'ReferencedTests',
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

    if ($Type) { Assert-SalesforceMetadataType -Type $Type }

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters

    $arguments = @('project', 'deploy', 'start')
    if ($Type) {
        $metadata = $Type
        if ($Name) { $metadata += ":$Name" }
        $arguments += @('--metadata', $metadata)
    }
    if ($SourceDir) {
        if (-not (Test-Path -LiteralPath $SourceDir)) {
            throw "Source path '$SourceDir' does not exist."
        }
        $arguments += @('--source-dir', $SourceDir)
    }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($IgnoreConflicts) { $arguments += '--ignore-conflicts' }
    if ($IgnoreWarnings) { $arguments += '--ignore-warnings' }
    if ($IgnoreErrors) { $arguments += '--ignore-errors' }
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }

    $arguments += Get-SalesforceApexCliTestArguments @commonParams -SourceDir $SourceDir -TestLevel $TestLevel -Tests $Tests

    if ($DryRun) { $arguments += '--dry-run' }
    if ($ConciseResults) { $arguments += '--concise' }
    if ($DetailedResults) { $arguments += '--verbose' }
    $arguments += '--json'
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
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

    $arguments = @('project', 'deploy', 'start')
    if ($Manifest) { $arguments += @('--manifest', $Manifest) }
    if ($InputDir) { $arguments += @('--metadata-dir', $InputDir) }
    if ($ManifestPackage) { $arguments += '--single-package' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($IgnoreConflicts) { $arguments += '--ignore-conflicts' }
    if ($IgnoreWarnings) { $arguments += '--ignore-warnings' }
    if ($IgnoreErrors) { $arguments += '--ignore-errors' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region Deploy lifecycle

function Get-SalesforceDeployJobParams {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $JobId,
        [Parameter(Mandatory = $false)][switch] $UseMostRecent
    )

    if ($JobId -and $UseMostRecent) {
        throw "Specify only one of -JobId or -UseMostRecent."
    }
    if (-not $JobId -and -not $UseMostRecent) {
        throw "Specify -JobId or -UseMostRecent."
    }
    if ($JobId) {
        if ($JobId -notmatch '^0Af[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$') {
            throw "Job ID '$JobId' is not a valid deploy job ID. Expected a 15 or 18 character ID starting with 0Af."
        }
        return @('--job-id', $JobId)
    }
    return @('--use-most-recent')
}

function Test-SalesforceDeployWaitParams {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][bool] $HasWait,
        [Parameter(Mandatory = $false)][bool] $Async
    )
    if ($HasWait -and $Async) {
        throw "Specify only one of -Wait or -Async."
    }
}

function Test-SalesforceDeployResultOptions {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][bool] $ConciseResults,
        [Parameter(Mandatory = $false)][bool] $DetailedResults
    )
    if ($ConciseResults -and $DetailedResults) {
        throw "Specify only one of -ConciseResults or -DetailedResults."
    }
}

function Test-SalesforceValidDeployWait {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][int] $Wait
    )
    if ($Wait -lt 0) {
        throw "-Wait must be zero or greater (minutes)."
    }
}

function Test-SalesforceDeploy {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Manifest,
        [Parameter(Mandatory = $false)][string] $SourceDir,
        [Parameter(Mandatory = $false)][string] $InputDir,
        [Parameter(Mandatory = $false)][switch] $ManifestPackage,
        [Parameter(Mandatory = $false)][ValidateSet(
            'SpecificTests',
            'ReferencedTests',
            'TestsInFolder',
            'TestsInOrg',
            'TestsInOrgAndPackages',
            'RelevantTests')][string] $TestLevel = 'TestsInOrg',
        [Parameter(Mandatory = $false)][string[]] $Tests,
        [Parameter(Mandatory = $false)][switch] $IgnoreWarnings,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $optionsProvided = 0
    if ($Manifest) { $optionsProvided++ }
    if ($SourceDir) { $optionsProvided++ }
    if ($InputDir) { $optionsProvided++ }
    if ($optionsProvided -ne 1) {
        throw "Specify exactly one of -Manifest, -SourceDir, or -InputDir."
    }
    if ($ManifestPackage -and -not $InputDir) {
        throw "-ManifestPackage can only be used with -InputDir."
    }
    Test-SalesforceDeployResultOptions -ConciseResults ([bool]$ConciseResults) -DetailedResults ([bool]$DetailedResults)
    Test-SalesforceDeployWaitParams -HasWait ($PSBoundParameters.ContainsKey('Wait')) -Async ([bool]$Async)
    if ($PSBoundParameters.ContainsKey('Wait')) { Test-SalesforceValidDeployWait -Wait $Wait }

    if ($Manifest -and -not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
        throw "Manifest file '$Manifest' does not exist."
    }
    if ($SourceDir -and -not (Test-Path -LiteralPath $SourceDir)) {
        throw "Source path '$SourceDir' does not exist."
    }
    if ($InputDir) {
        if (-not (Test-Path -LiteralPath $InputDir)) {
            throw "Input path '$InputDir' does not exist."
        }
        if (-not (Test-Path -LiteralPath $InputDir -PathType Container)) {
            $inputExtension = [System.IO.Path]::GetExtension($InputDir)
            if (-not [string]::Equals($inputExtension, '.zip', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Input path '$InputDir' must be a directory or a .zip file."
            }
        }
    }

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters

    $arguments = @('project', 'deploy', 'validate')
    if ($Manifest) { $arguments += @('--manifest', $Manifest) }
    if ($SourceDir) { $arguments += @('--source-dir', $SourceDir) }
    if ($InputDir) { $arguments += @('--metadata-dir', $InputDir) }
    if ($ManifestPackage) { $arguments += '--single-package' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($IgnoreWarnings) { $arguments += '--ignore-warnings' }
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    if ($Async) { $arguments += '--async' }
    $arguments += Get-SalesforceApexCliTestArguments @commonParams -SourceDir $SourceDir -TestLevel $TestLevel -Tests $Tests
    if ($ConciseResults) { $arguments += '--concise' }
    if ($DetailedResults) { $arguments += '--verbose' }
    $arguments += '--json'
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Start-SalesforceQuickDeploy {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $false)][string] $JobId,
        [Parameter(Mandatory = $false)][switch] $UseMostRecent,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $jobParams = Get-SalesforceDeployJobParams -JobId $JobId -UseMostRecent:$UseMostRecent
    Test-SalesforceDeployResultOptions -ConciseResults ([bool]$ConciseResults) -DetailedResults ([bool]$DetailedResults)
    Test-SalesforceDeployWaitParams -HasWait ($PSBoundParameters.ContainsKey('Wait')) -Async ([bool]$Async)
    if ($PSBoundParameters.ContainsKey('Wait')) { Test-SalesforceValidDeployWait -Wait $Wait }

    $arguments = @('project', 'deploy', 'quick') + $jobParams
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    if ($Async) { $arguments += '--async' }
    if ($ConciseResults) { $arguments += '--concise' }
    if ($DetailedResults) { $arguments += '--verbose' }
    $arguments += '--json'

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $target = if ($JobId) { $JobId } else { 'most recent validated deployment' }
    if ($PSCmdlet.ShouldProcess($target, 'Quick deploy validated deployment')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Get-SalesforceDeployStatus {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $JobId,
        [Parameter(Mandatory = $false)][switch] $UseMostRecent,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $jobParams = Get-SalesforceDeployJobParams -JobId $JobId -UseMostRecent:$UseMostRecent
    if ($PSBoundParameters.ContainsKey('Wait')) { Test-SalesforceValidDeployWait -Wait $Wait }

    $arguments = @('project', 'deploy', 'report') + $jobParams
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Resume-SalesforceDeploy {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $JobId,
        [Parameter(Mandatory = $false)][switch] $UseMostRecent,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults
    )

    $jobParams = Get-SalesforceDeployJobParams -JobId $JobId -UseMostRecent:$UseMostRecent
    Test-SalesforceDeployResultOptions -ConciseResults ([bool]$ConciseResults) -DetailedResults ([bool]$DetailedResults)
    if ($PSBoundParameters.ContainsKey('Wait')) { Test-SalesforceValidDeployWait -Wait $Wait }

    # sf project deploy resume has no --target-org; the org comes from the cached deployment.
    $arguments = @('project', 'deploy', 'resume') + $jobParams
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    if ($ConciseResults) { $arguments += '--concise' }
    if ($DetailedResults) { $arguments += '--verbose' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Stop-SalesforceDeploy {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $false)][string] $JobId,
        [Parameter(Mandatory = $false)][switch] $UseMostRecent,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $jobParams = Get-SalesforceDeployJobParams -JobId $JobId -UseMostRecent:$UseMostRecent
    Test-SalesforceDeployWaitParams -HasWait ($PSBoundParameters.ContainsKey('Wait')) -Async ([bool]$Async)
    if ($PSBoundParameters.ContainsKey('Wait')) { Test-SalesforceValidDeployWait -Wait $Wait }

    $arguments = @('project', 'deploy', 'cancel') + $jobParams
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    if ($Async) { $arguments += '--async' }
    $arguments += '--json'

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $target = if ($JobId) { $JobId } else { 'most recent deployment' }
    if ($PSCmdlet.ShouldProcess($target, 'Cancel deployment')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

#endregion

#region Deploy and retrieve preview

function ConvertTo-SalesforcePreviewObject {
    # Private: turns the result of `sf project deploy|retrieve preview` into one object with the lists the CLI reports.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowNull()] $Result,
        [Parameter(Mandatory = $true)][ValidateSet('Deploy', 'Retrieve')][string] $Operation
    )

    $names = @()
    if ($null -ne $Result) { $names = @($Result.PSObject.Properties.Name) }
    $get = {
        param($Name)
        if ($names -contains $Name -and $null -ne $Result.$Name) { return @($Result.$Name) }
        return @()
    }
    $toDeploy = @(& $get 'toDeploy')
    $toRetrieve = @(& $get 'toRetrieve')
    $toDelete = @(& $get 'toDelete')
    $conflicts = @(& $get 'conflicts')
    $ignored = @(& $get 'ignored')
    $changeCount = $toDeploy.Count + $toRetrieve.Count + $toDelete.Count
    $summary = 'No changes'
    if ($changeCount -gt 0 -or $conflicts.Count -gt 0) {
        $summary = "$($toDeploy.Count) to deploy, $($toRetrieve.Count) to retrieve, $($toDelete.Count) to delete, $($conflicts.Count) conflict(s)"
    }
    return [pscustomobject]@{
        Operation    = $Operation
        HasChanges   = ($changeCount -gt 0)
        HasConflicts = ($conflicts.Count -gt 0)
        Summary      = $summary
        ToDeploy     = $toDeploy
        ToRetrieve   = $toRetrieve
        ToDelete     = $toDelete
        Conflicts    = $conflicts
        Ignored      = $ignored
    }
}

function Get-SalesforcePreviewResult {
    # Private: runs a preview command and adds guidance when the org has no source tracking.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [Parameter(Mandatory = $true)][ValidateSet('Deploy', 'Retrieve')][string] $Operation,
        [Parameter(Mandatory = $false)][hashtable] $CommonParams = @{}
    )

    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $Arguments @CommonParams
    try {
        $parsed = Show-SalesforceResult -Result $result
    } catch {
        if ($_.Exception.Message -match 'track') {
            throw "$($_.Exception.Message) The preview commands need an org with source tracking (a scratch org or a tracked sandbox). Use Deploy-SalesforceMetadata or Retrieve-SalesforceMetadata directly for other orgs."
        }
        throw
    }
    return ConvertTo-SalesforcePreviewObject -Result $parsed -Operation $Operation
}

function Get-SalesforceDeployPreview {
    <#
    .SYNOPSIS
    Shows what a deploy would send, and what conflicts with the org, without deploying (sf project deploy preview).
    .DESCRIPTION
    Read-only: nothing is deployed, retrieved or deleted. Returns one object with ToDeploy, ToRetrieve, ToDelete, Conflicts and Ignored,
    plus HasChanges, HasConflicts and Summary. With no changes the lists are empty and Summary is 'No changes'.
    Source tracking is required: scratch orgs and tracked sandboxes work; other orgs return the CLI error with guidance.
    Narrow the preview with -SourceDir, -Manifest (one package.xml; the CLI accepts only one) or -Metadata (any combination the CLI accepts).
    .EXAMPLE
    Get-SalesforceDeployPreview -TargetOrg my-sandbox
    .EXAMPLE
    $p = Get-SalesforceDeployPreview -SourceDir force-app/main/default/classes; if ($p.HasConflicts) { $p.Conflicts }
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string[]] $SourceDir,
        [Parameter(Mandatory = $false)][string] $Manifest,
        [Parameter(Mandatory = $false)][string[]] $Metadata,
        [Parameter(Mandatory = $false)][switch] $IgnoreConflicts,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if ($Manifest -and -not (Test-Path -LiteralPath $Manifest -PathType Leaf)) { throw "Manifest file '$Manifest' does not exist." }
    foreach ($dir in @($SourceDir)) {
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { throw "Source path '$dir' does not exist." }
    }
    $arguments = @('project', 'deploy', 'preview')
    foreach ($d in @($SourceDir)) { if ($d) { $arguments += @('--source-dir', $d) } }
    if ($Manifest) { $arguments += @('--manifest', $Manifest) }
    foreach ($m in @($Metadata)) { if ($m) { $arguments += @('--metadata', $m) } }
    if ($IgnoreConflicts) { $arguments += '--ignore-conflicts' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    return Get-SalesforcePreviewResult -Arguments $arguments -Operation 'Deploy' -CommonParams $commonParams
}

function Get-SalesforceRetrievePreview {
    <#
    .SYNOPSIS
    Shows what a retrieve would bring down, and what conflicts with local files, without retrieving (sf project retrieve preview).
    .DESCRIPTION
    Read-only: nothing is retrieved or changed. Returns the same object as Get-SalesforceDeployPreview. The CLI command takes no selection
    flags, so it previews the org's tracked changes. Source tracking is required (see Get-SalesforceDeployPreview).
    .EXAMPLE
    Get-SalesforceRetrievePreview -TargetOrg my-scratch
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $IgnoreConflicts,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $arguments = @('project', 'retrieve', 'preview')
    if ($IgnoreConflicts) { $arguments += '--ignore-conflicts' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    return Get-SalesforcePreviewResult -Arguments $arguments -Operation 'Retrieve' -CommonParams $commonParams
}

#endregion

#region Describe

function Describe-SalesforceObjects {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('sobject', 'list')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Describe-SalesforceObject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    $arguments = @('sobject', 'describe')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += @('--sobject', $Name)
    if ($UseToolingApi) { $arguments += '--use-tooling-api' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
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
    $arguments = @('org', 'list', 'metadata-types')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) {
        $arguments += @('--target-org', $TargetOrg)
    }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
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
    $fieldNames = @($fieldNames)
    if ($fieldNames.Count -eq 0) {
        # Every field was excluded; 'SELECT FROM X' is not valid SOQL
        return ""
    }

    return "SELECT " + (@($fieldNames | ForEach-Object { ConvertTo-SalesforceSoqlIdentifier -Value $_ }) -join ",") + " FROM " + (ConvertTo-SalesforceSoqlIdentifier -Value $ObjectName)
}

#endregion
