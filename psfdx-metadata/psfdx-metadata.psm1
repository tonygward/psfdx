. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Invoke-Salesforce.ps1')
. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Show-SalesforceResult.ps1')

class SalesforceMetadataTypeGenerator : System.Management.Automation.IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        $types = Describe-SalesforceMetadataTypes
        if (-not $types -or $types.Count -eq 0) {
            $types = @(
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
        return (@($types) + 'CustomField', 'ValidationRule') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    }
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
