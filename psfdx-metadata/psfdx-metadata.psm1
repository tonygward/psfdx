function Invoke-Salesforce {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Command)
    Write-Verbose $Command
    return Invoke-Expression -Command $Command
}

function Show-SalesforceResult {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][psobject] $Result)
    $result = $Result | ConvertFrom-Json
    if ($result.status -ne 0) {
        Write-Debug $result
        throw ($result.message)
    }
    return $result.result
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

function Retrieve-SalesforceComponent {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string][ValidateSet(
            'AIApplication',
            'AIApplicationConfig',
            'ActionLauncherItemDef',
            'ActionLinkGroupTemplate',
            'AnalyticSnapshot',
            'AnimationRule',
            'ApexClass',
            'ApexComponent',
            'ApexEmailNotifications',
            'ApexPage',
            'ApexTestSuite',
            'ApexTrigger',
            'AppFrameworkTemplateBundle',
            'AppMenu',
            'AppointmentAssignmentPolicy',
            'AppointmentSchedulingPolicy',
            'ApprovalProcess',
            'AssignmentRules',
            'AuraDefinitionBundle',
            'AuthProvider',
            'AutoResponseRules',
            'BlacklistedConsumer',
            'BrandingSet',
            'BriefcaseDefinition',
            'CallCenter',
            'CallCoachingMediaProvider',
            'CanvasMetadata',
            'Certificate',
            'ChannelLayout',
            'ChatterExtension',
            'ChoiceList',
            'CleanDataService',
            'Community',
            'ConnectedApp',
            'ContentAsset',
            'ContentTypeBundle',
            'ConvIntelligenceSignalRule',
            'ConversationMessageDefinition',
            'CorsWhitelistOrigin',
            'CspTrustedSite',
            'CustomApplication',
            'CustomApplicationComponent',
            'CustomFeedFilter',
            'CustomHelpMenuSection',
            'CustomIndex',
            'CustomLabels',
            'CustomMetadata',
            'CustomNotificationType',
            'CustomObject',
            'CustomObjectTranslation',
            'CustomPageWebLink',
            'CustomPermission',
            'CustomSite',
            'CustomTab',
            'Dashboard',
            'DataCategoryGroup',
            'DataWeaveResource',
            'DelegateGroup',
            'DigitalExperienceBundle',
            'Document',
            'DuplicateRule',
            'EclairGeoData',
            'EmailServicesFunction',
            'EmailTemplate',
            'EmbeddedServiceBranding',
            'EmbeddedServiceConfig',
            'EmbeddedServiceFlowConfig',
            'EmbeddedServiceMenuSettings',
            'EscalationRules',
            'EventRelayConfig',
            'ExperienceContainer',
            'ExperiencePropertyTypeBundle',
            'ExternalAuthIdentityProvider',
            'ExternalClientApplication',
            'ExternalCredential',
            'ExternalDataSource',
            'ExternalServiceRegistration',
            'ExtlClntAppConfigurablePolicies',
            'ExtlClntAppGlobalOauthSettings',
            'ExtlClntAppMobileConfigurablePolicies',
            'ExtlClntAppMobileSettings',
            'ExtlClntAppNotificationSettings',
            'ExtlClntAppOauthConfigurablePolicies',
            'ExtlClntAppOauthSettings',
            'ExtlClntAppPushConfigurablePolicies',
            'ExtlClntAppPushSettings',
            'ExtlClntAppSamlConfigurablePolicies',
            'FieldRestrictionRule',
            'FlexiPage',
            'Flow',
            'FlowCategory',
            'FlowDefinition',
            'FlowTest',
            'ForecastingFilter',
            'ForecastingFilterCondition',
            'ForecastingGroup',
            'ForecastingSourceDefinition',
            'ForecastingType',
            'ForecastingTypeSource',
            'GatewayProviderPaymentMethodType',
            'GlobalValueSet',
            'GlobalValueSetTranslation',
            'Group',
            'HomePageComponent',
            'HomePageLayout',
            'IPAddressRange',
            'IframeWhiteListUrlSettings',
            'InboundNetworkConnection',
            'InstalledPackage',
            'Layout',
            'LeadConvertSettings',
            'Letterhead',
            'LightningBolt',
            'LightningComponentBundle',
            'LightningExperienceTheme',
            'LightningMessageChannel',
            'LightningOnboardingConfig',
            'LightningTypeBundle',
            'LiveChatSensitiveDataRule',
            'MLDataDefinition',
            'MLPredictionDefinition',
            'MLRecommendationDefinition',
            'ManagedContentType',
            'ManagedEventSubscription',
            'MatchingRules',
            'MessagingChannel',
            'MobileApplicationDetail',
            'MutingPermissionSet',
            'MyDomainDiscoverableLogin',
            'NamedCredential',
            'NetworkBranding',
            'NotificationTypeConfig',
            'OauthCustomScope',
            'OauthTokenExchangeHandler',
            'OutboundNetworkConnection',
            'PathAssistant',
            'PaymentGatewayProvider',
            'PermissionSet',
            'PermissionSetGroup',
            'PlatformCachePartition',
            'PlatformEventChannel',
            'PlatformEventChannelMember',
            'PlatformEventSubscriberConfig',
            'PostTemplate',
            'ProcessFlowMigration',
            'ProductAttributeSet',
            'Profile',
            'ProfilePasswordPolicy',
            'ProfileSessionSetting',
            'Prompt',
            'PublicKeyCertificate',
            'PublicKeyCertificateSet',
            'Queue',
            'QuickAction',
            'RecommendationStrategy',
            'RecordActionDeployment',
            'RedirectWhitelistUrl',
            'RemoteSiteSetting',
            'Report',
            'ReportType',
            'RestrictionRule',
            'Role',
            'SamlSsoConfig',
            'Scontrol',
            'SearchCustomization',
            'SearchOrgWideObjectConfig',
            'Settings',
            'SharingRules',
            'SharingSet',
            'SiteDotCom',
            'Skill',
            'SkillType',
            'StandardValueSet',
            'StandardValueSetTranslation',
            'StaticResource',
            'SynonymDictionary',
            'TopicsForObjects',
            'TransactionSecurityPolicy',
            'UiFormatSpecificationSet',
            'UserProvisioningConfig',
            'WaveAnalyticAssetCollection',
            'Workflow'
        )] $Type,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $command = "sf project retrieve start --metadata $Type"
    if ($Name) { $command += ":$Name" }
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    Invoke-Salesforce -Command $command
}

function Retrieve-SalesforceField {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,
        [Parameter(Mandatory = $true)][string] $FieldName,
        [Parameter(Mandatory = $false)][string] $TargetOrg)
    $command = "sf project retrieve start --metadata CustomField:$ObjectName.$FieldName"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    Invoke-Salesforce -Command $command
}

function Retrieve-SalesforceValidationRule {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,
        [Parameter(Mandatory = $true)][string] $RuleName,
        [Parameter(Mandatory = $false)][string] $TargetOrg)
    $command = "sf project retrieve start --metadata ValidationRule:$ObjectName.$RuleName"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    Invoke-Salesforce -Command $command
}

function Deploy-SalesforceComponent {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string][ValidateSet(
            'AIApplication',
            'AIApplicationConfig',
            'ActionLauncherItemDef',
            'ActionLinkGroupTemplate',
            'AnalyticSnapshot',
            'AnimationRule',
            'ApexClass',
            'ApexComponent',
            'ApexEmailNotifications',
            'ApexPage',
            'ApexTestSuite',
            'ApexTrigger',
            'AppFrameworkTemplateBundle',
            'AppMenu',
            'AppointmentAssignmentPolicy',
            'AppointmentSchedulingPolicy',
            'ApprovalProcess',
            'AssignmentRules',
            'AuraDefinitionBundle',
            'AuthProvider',
            'AutoResponseRules',
            'BlacklistedConsumer',
            'BrandingSet',
            'BriefcaseDefinition',
            'CallCenter',
            'CallCoachingMediaProvider',
            'CanvasMetadata',
            'Certificate',
            'ChannelLayout',
            'ChatterExtension',
            'ChoiceList',
            'CleanDataService',
            'Community',
            'ConnectedApp',
            'ContentAsset',
            'ContentTypeBundle',
            'ConvIntelligenceSignalRule',
            'ConversationMessageDefinition',
            'CorsWhitelistOrigin',
            'CspTrustedSite',
            'CustomApplication',
            'CustomApplicationComponent',
            'CustomFeedFilter',
            'CustomHelpMenuSection',
            'CustomIndex',
            'CustomLabels',
            'CustomMetadata',
            'CustomNotificationType',
            'CustomObject',
            'CustomObjectTranslation',
            'CustomPageWebLink',
            'CustomPermission',
            'CustomSite',
            'CustomTab',
            'Dashboard',
            'DataCategoryGroup',
            'DataWeaveResource',
            'DelegateGroup',
            'DigitalExperienceBundle',
            'Document',
            'DuplicateRule',
            'EclairGeoData',
            'EmailServicesFunction',
            'EmailTemplate',
            'EmbeddedServiceBranding',
            'EmbeddedServiceConfig',
            'EmbeddedServiceFlowConfig',
            'EmbeddedServiceMenuSettings',
            'EscalationRules',
            'EventRelayConfig',
            'ExperienceContainer',
            'ExperiencePropertyTypeBundle',
            'ExternalAuthIdentityProvider',
            'ExternalClientApplication',
            'ExternalCredential',
            'ExternalDataSource',
            'ExternalServiceRegistration',
            'ExtlClntAppConfigurablePolicies',
            'ExtlClntAppGlobalOauthSettings',
            'ExtlClntAppMobileConfigurablePolicies',
            'ExtlClntAppMobileSettings',
            'ExtlClntAppNotificationSettings',
            'ExtlClntAppOauthConfigurablePolicies',
            'ExtlClntAppOauthSettings',
            'ExtlClntAppPushConfigurablePolicies',
            'ExtlClntAppPushSettings',
            'ExtlClntAppSamlConfigurablePolicies',
            'FieldRestrictionRule',
            'FlexiPage',
            'Flow',
            'FlowCategory',
            'FlowDefinition',
            'FlowTest',
            'ForecastingFilter',
            'ForecastingFilterCondition',
            'ForecastingGroup',
            'ForecastingSourceDefinition',
            'ForecastingType',
            'ForecastingTypeSource',
            'GatewayProviderPaymentMethodType',
            'GlobalValueSet',
            'GlobalValueSetTranslation',
            'Group',
            'HomePageComponent',
            'HomePageLayout',
            'IPAddressRange',
            'IframeWhiteListUrlSettings',
            'InboundNetworkConnection',
            'InstalledPackage',
            'Layout',
            'LeadConvertSettings',
            'Letterhead',
            'LightningBolt',
            'LightningComponentBundle',
            'LightningExperienceTheme',
            'LightningMessageChannel',
            'LightningOnboardingConfig',
            'LightningTypeBundle',
            'LiveChatSensitiveDataRule',
            'MLDataDefinition',
            'MLPredictionDefinition',
            'MLRecommendationDefinition',
            'ManagedContentType',
            'ManagedEventSubscription',
            'MatchingRules',
            'MessagingChannel',
            'MobileApplicationDetail',
            'MutingPermissionSet',
            'MyDomainDiscoverableLogin',
            'NamedCredential',
            'NetworkBranding',
            'NotificationTypeConfig',
            'OauthCustomScope',
            'OauthTokenExchangeHandler',
            'OutboundNetworkConnection',
            'PathAssistant',
            'PaymentGatewayProvider',
            'PermissionSet',
            'PermissionSetGroup',
            'PlatformCachePartition',
            'PlatformEventChannel',
            'PlatformEventChannelMember',
            'PlatformEventSubscriberConfig',
            'PostTemplate',
            'ProcessFlowMigration',
            'ProductAttributeSet',
            'Profile',
            'ProfilePasswordPolicy',
            'ProfileSessionSetting',
            'Prompt',
            'PublicKeyCertificate',
            'PublicKeyCertificateSet',
            'Queue',
            'QuickAction',
            'RecommendationStrategy',
            'RecordActionDeployment',
            'RedirectWhitelistUrl',
            'RemoteSiteSetting',
            'Report',
            'ReportType',
            'RestrictionRule',
            'Role',
            'SamlSsoConfig',
            'Scontrol',
            'SearchCustomization',
            'SearchOrgWideObjectConfig',
            'Settings',
            'SharingRules',
            'SharingSet',
            'SiteDotCom',
            'Skill',
            'SkillType',
            'StandardValueSet',
            'StandardValueSetTranslation',
            'StaticResource',
            'SynonymDictionary',
            'TopicsForObjects',
            'TransactionSecurityPolicy',
            'UiFormatSpecificationSet',
            'UserProvisioningConfig',
            'WaveAnalyticAssetCollection',
            'Workflow'
        )] $Type = 'ApexClass',
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $true)][string] $TargetOrg
    )
    $command = "sf project deploy start"
    $command += " --metadata $Type"
    if ($Name) {
        $command += ":$Name"
    }
    $command += " --target-org $TargetOrg"
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Describe-SalesforceObjects {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][string][ValidateSet('all', 'custom', 'standard')] $ObjectTypeCategory = 'all'
    )
    $command = "sf sobject list"
    $command += " --category $ObjectTypeCategory"
    $command += " --target-org $TargetOrg"
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
    if ($TargetOrg) {
        $command += " --target-org $TargetOrg"
    }
    $command += " --sobject $Name"
    if ($UseToolingApi) {
        $command += " --use-tooling-api"
    }
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
    $result = $result | Select-Object name, label, type, byteLength
    return $result
}

function Get-SalesforceMetaTypes {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $TargetOrg)
    $command = "sf org list metadata-types"
    $command += " --target-org $TargetOrg"
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    $result = $result | ConvertFrom-Json
    $result = $result.result.metadataObjects
    $result = $result | Select-Object xmlName
    return $result
}

function Get-SalesforceApexClass {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $TargetOrg
    )
    $query = "SELECT Id, Name FROM ApexClass WHERE Name = '$Name' LIMIT 1"
    $result = Invoke-Salesforce -Command "sf data query --query `"$query`" --use-tooling-api --target-org $TargetOrg --json"
    $parsed = $result | ConvertFrom-Json
    if ($parsed.status -ne 0) {
        throw ($parsed.message)
    }
    return $parsed.result.records | Select-Object -First 1 -Property Id, Name
}

function Build-SalesforceQuery {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,
        [Parameter(Mandatory = $true)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    $fields = Describe-SalesforceFields -ObjectName $ObjectName -TargetOrg $TargetOrg -UseToolingApi:$UseToolingApi
    if ($null -eq $fields) {
        return ""
    }

    $fieldNames = @()
    foreach ($field in $fields) {
        $fieldNames += $field.name
    }
    $value = "SELECT "
    foreach ($fieldName in $fieldNames) {
        $value += $fieldName + ","
    }
    $value = $value.TrimEnd(",")
    $value += " FROM $ObjectName"
    return $value
}
