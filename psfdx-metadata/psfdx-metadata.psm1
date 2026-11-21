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
    <#
    .SYNOPSIS
    Forgets the metadata types psfdx cached for -Type completion.

    .DESCRIPTION
    Does not use the Salesforce CLI. psfdx caches the list of metadata types for the session so -Type can be completed and checked; this removes the cache so the next use asks the org again.

    .EXAMPLE
    Clear-SalesforceMetadataTypeCache
    Force a fresh list of metadata types.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It works locally in PowerShell and .NET.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Retrieves one metadata component from an org.

    .DESCRIPTION
    Runs sf project retrieve start with --metadata Type, Type:Name or Type:Name.ChildName. The type is checked against the org's metadata types.

    .PARAMETER Type
    Metadata type, for example ApexClass or CustomField. Required; completes from the org's metadata types and is checked.

    .PARAMETER Name
    Name of the component, for example an object name for a field. Together with -Type it forms --metadata Type:Name.

    .PARAMETER ChildName
    Metadata component names to retrieve. Wildcards (`*`) supported as long as you use quotes, such as `ApexClass:MyClass*`. Passed to sf as --metadata.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .PARAMETER Wait
    Number of minutes to wait for the command to complete and display results to the terminal window. Passed to sf as --wait.

    .PARAMETER OutputDir
    Directory root for the retrieved source files. Passed to sf as --output-dir.

    .PARAMETER IgnoreConflicts
    Ignore conflicts and retrieve and save files to your local filesystem, even if they overwrite your local changes. Adds --ignore-conflicts.

    .EXAMPLE
    Retrieve-SalesforceComponent -Type ApexClass -Name AccountService -TargetOrg dev1
    Retrieve one class into the project.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project retrieve start (plugin @salesforce/plugin-deploy-retrieve)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --root-type-with-dependencies, --single-package, --source-dir, --zip-file-name
    Parameter to flag: -ChildName = --metadata; -TargetOrg = --target-org; -Wait = --wait; -OutputDir = --output-dir; -IgnoreConflicts = --ignore-conflicts.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-deploy-retrieve

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Retrieves the metadata a manifest lists, as a package, into a folder.

    .DESCRIPTION
    Runs sf project retrieve start with --manifest and --target-metadata-dir, optionally unzipped. Both the manifest file and the output folder must exist.

    .PARAMETER Manifest
    File path for the manifest (package.xml) that specifies the components to retrieve. Passed to sf as --manifest. Required.

    .PARAMETER OutputDir
    Folder that receives the retrieved package. Passed as --target-metadata-dir. Required.

    .PARAMETER Wait
    Number of minutes to wait for the command to complete and display results to the terminal window. Passed to sf as --wait.

    .PARAMETER Unzip
    Extract the retrieved zip. Passed as --unzip.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Retrieve-SalesforceMetadata -Manifest manifest/package.xml -OutputDir .\retrieved -Unzip -TargetOrg dev1
    Retrieve and unzip.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project retrieve start (plugin @salesforce/plugin-deploy-retrieve)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --root-type-with-dependencies, --single-package, --source-dir, --zip-file-name
    Parameter to flag: -Manifest = --manifest; -OutputDir = --target-metadata-dir; -Wait = --wait; -Unzip = --unzip; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-deploy-retrieve

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Retrieves a package's metadata into a folder.

    .DESCRIPTION
    Runs sf project retrieve start with --package-name and --output-dir. The output folder must exist.

    .PARAMETER Name
    Name of the package to retrieve. Passed as --package-name. Required.

    .PARAMETER OutputDir
    Directory root for the retrieved source files. Passed to sf as --output-dir. Required.

    .PARAMETER Wait
    Number of minutes to wait for the command to complete and display results to the terminal window. Passed to sf as --wait.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Retrieve-SalesforcePackage -Name MyPackage -OutputDir .\pkg -TargetOrg dev1
    Retrieve one package.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project retrieve start (plugin @salesforce/plugin-deploy-retrieve)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --root-type-with-dependencies, --single-package, --source-dir, --zip-file-name
    Parameter to flag: -Name = --package-name; -OutputDir = --output-dir; -Wait = --wait; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-deploy-retrieve

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Retrieves one custom field into the project.

    .DESCRIPTION
    A shortcut for Retrieve-SalesforceComponent -Type CustomField with the object as the name and the field as the child name.

    .PARAMETER ObjectName
    API name of the object that holds the field. Required.

    .PARAMETER FieldName
    API name of the field, for example Rating__c. Required.

    .PARAMETER TargetOrg
    Username or alias of the org. If omitted, the Salesforce CLI uses the default target org.

    .EXAMPLE
    Retrieve-SalesforceField -ObjectName Account -FieldName Rating__c -TargetOrg dev1
    Retrieve Account.Rating__c.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Retrieve-SalesforceComponent. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,
        [Parameter(Mandatory = $true)][string] $FieldName,
        [Parameter(Mandatory = $false)][string] $TargetOrg)
    Retrieve-SalesforceComponent -Type 'CustomField' -Name $ObjectName -ChildName $FieldName -TargetOrg $TargetOrg
}

function Retrieve-SalesforceValidationRule {
    <#
    .SYNOPSIS
    Retrieves one validation rule into the project.

    .DESCRIPTION
    A shortcut for Retrieve-SalesforceComponent -Type ValidationRule with the object and rule name combined.

    .PARAMETER ObjectName
    API name of the object that holds the rule. Required.

    .PARAMETER RuleName
    Name of the validation rule. Required.

    .PARAMETER TargetOrg
    Username or alias of the org. If omitted, the Salesforce CLI uses the default target org.

    .EXAMPLE
    Retrieve-SalesforceValidationRule -ObjectName Account -RuleName Require_Name -TargetOrg dev1
    Retrieve one rule.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Retrieve-SalesforceComponent. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,
        [Parameter(Mandatory = $true)][string] $RuleName,
        [Parameter(Mandatory = $false)][string] $TargetOrg)
    Retrieve-SalesforceComponent -Type 'ValidationRule' -Name $ObjectName -ChildName $RuleName -TargetOrg $TargetOrg
}

function Retrieve-SalesforceOrg {
    <#
    .SYNOPSIS
    Retrieves all the metadata of an org into the project.

    .DESCRIPTION
    Runs two commands. First sf project generate manifest --from-org --name=allMetadata --output-dir . writes allMetadata.xml in the current folder; then sf project retrieve start --manifest allMetadata.xml retrieves everything it lists. This can take a long time on a large org.

    .PARAMETER TargetOrg
    Username or alias of the org to retrieve from. Passed as --from-org to sf project generate manifest and as --target-org to sf project retrieve start. If omitted, the CLI uses the default target org.

    .PARAMETER IncludePackages
    Also include the org's unlocked package contents. psfdx passes --include-packages=unlocked; the value managed is not available.

    .EXAMPLE
    Retrieve-SalesforceOrg -TargetOrg dev1
    Write allMetadata.xml and retrieve all metadata.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project generate manifest (plugin @salesforce/plugin-deploy-retrieve)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --excluded-metadata, --metadata, --source-dir, --type
      Values psfdx cannot pass: --include-packages managed
    Command run: sf project retrieve start (plugin @salesforce/plugin-deploy-retrieve)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --root-type-with-dependencies, --single-package, --source-dir, --zip-file-name
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-deploy-retrieve

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Deploys one metadata component, or a source path, to an org.

    .DESCRIPTION
    Runs sf project deploy start with --metadata Type:Name or --source-dir, with optional test level and tests. -DryRun adds --dry-run, which validates without deploying, so only a real deployment is confirmed. Supports -WhatIf and -Confirm (no prompt by default).

    .PARAMETER Type
    Metadata type, for example ApexClass. Completes from the org's metadata types. Needed unless -SourceDir is given. Passed to sf as --metadata.

    .PARAMETER Name
    Name of the component. Needs -Type. Passed as --metadata Type:Name.

    .PARAMETER SourceDir
    Path to the local source files to deploy. Passed to sf as --source-dir.

    .PARAMETER IgnoreConflicts
    Ignore conflicts and deploy local files, even if they overwrite changes in the org. Adds --ignore-conflicts.

    .PARAMETER IgnoreWarnings
    Ignore warnings and allow a deployment to complete successfully. Adds --ignore-warnings.

    .PARAMETER IgnoreErrors
    Ignore any errors and don't roll back deployment. Adds --ignore-errors.

    .PARAMETER Wait
    Number of minutes to wait for command to complete and display results. Passed to sf as --wait.

    .PARAMETER TestLevel
    How tests run. psfdx level names are translated to the CLI's (see the value mapping). Passed to sf as --test-level. Default: NoTests. Valid values: NoTests, SpecificTests, ReferencedTests, TestsInFolder, TestsInOrg, TestsInOrgAndPackages. Value mapping to the CLI: NoTests = NoTestRun, SpecificTests = RunSpecifiedTests, ReferencedTests = RunSpecifiedTests, TestsInFolder = RunSpecifiedTests, TestsInOrg = RunLocalTests, TestsInOrgAndPackages = RunAllTestsInOrg, RelevantTests = RunRelevantTests.

    .PARAMETER Tests
    Test classes to run for -TestLevel SpecificTests. Passed as one --tests per name.

    .PARAMETER DryRun
    Validate only. Passed as --dry-run; nothing is deployed.

    .PARAMETER ConciseResults
    Show concise output of the deploy result. Adds --concise.

    .PARAMETER DetailedResults
    Show verbose output of the deploy result. Adds --verbose.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Deploy-SalesforceComponent -Type ApexClass -Name AccountService -TargetOrg dev1 -WhatIf
    Preview deploying one class.

    .EXAMPLE
    Deploy-SalesforceComponent -SourceDir force-app -TestLevel TestsInOrg -DryRun -TargetOrg uat
    Validate a deployment with all local tests, deploying nothing.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy start (plugin @salesforce/plugin-deploy-retrieve)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --async, --coverage-formatters, --junit, --post-destructive-changes, --pre-destructive-changes, --purge-on-delete, --results-dir
      Values psfdx cannot pass: --test-level RunRelevantTests
    Parameter to flag: -Type = --metadata; -Name = --metadata; -SourceDir = --source-dir; -IgnoreConflicts = --ignore-conflicts; -IgnoreWarnings = --ignore-warnings; -IgnoreErrors = --ignore-errors; -Wait = --wait; -TestLevel = --test-level; -Tests = --tests; -DryRun = --dry-run; -ConciseResults = --concise; -DetailedResults = --verbose; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-deploy-retrieve

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')

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
    # A dry run (--dry-run) deploys nothing, so only a real deployment needs confirming.
    $what = @($Type, $Name, $SourceDir | Where-Object { $_ }) -join ' '
    if (-not $DryRun -and -not $PSCmdlet.ShouldProcess("$what to the org", 'Deploy metadata')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Deploy-SalesforceMetadata {
    <#
    .SYNOPSIS
    Deploys metadata described by a manifest or a metadata folder.

    .DESCRIPTION
    Runs sf project deploy start with --manifest, --metadata-dir or --single-package. Give exactly one of -Manifest, -InputDir and -ManifestPackage. Supports -WhatIf and -Confirm (no prompt by default).

    .PARAMETER Manifest
    Path of package.xml. Passed as --manifest.

    .PARAMETER InputDir
    Folder of metadata in metadata (mdapi) format. Passed as --metadata-dir.

    .PARAMETER ManifestPackage
    Treat the metadata directory as a single package. Passed as --single-package.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .PARAMETER IgnoreConflicts
    Ignore conflicts and deploy local files, even if they overwrite changes in the org. Adds --ignore-conflicts.

    .PARAMETER IgnoreWarnings
    Ignore warnings and allow a deployment to complete successfully. Adds --ignore-warnings.

    .PARAMETER IgnoreErrors
    Ignore any errors and don't roll back deployment. Adds --ignore-errors.

    .EXAMPLE
    Deploy-SalesforceMetadata -Manifest manifest/package.xml -TargetOrg dev1 -WhatIf
    Preview deploying a manifest.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy start (plugin @salesforce/plugin-deploy-retrieve)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --async, --coverage-formatters, --junit, --post-destructive-changes, --pre-destructive-changes, --purge-on-delete, --results-dir
      Values psfdx cannot pass: --test-level RunRelevantTests
    Parameter to flag: -Manifest = --manifest; -InputDir = --metadata-dir; -ManifestPackage = --single-package; -TargetOrg = --target-org; -IgnoreConflicts = --ignore-conflicts; -IgnoreWarnings = --ignore-warnings; -IgnoreErrors = --ignore-errors.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-deploy-retrieve

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $what = @($Manifest, $InputDir | Where-Object { $_ }) -join ' '
    if ($ManifestPackage) { $what = 'the manifest package' }
    if (-not $PSCmdlet.ShouldProcess("$what to the org", 'Deploy metadata')) { return }
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
        if ($JobId -notmatch '^0Af[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?\z') {
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
    <#
    .SYNOPSIS
    Validates a deployment, running tests, without deploying it.

    .DESCRIPTION
    Runs sf project deploy validate. Nothing is deployed; a passing validation can be released later with Start-SalesforceQuickDeploy. The test level must run tests (NoTests is not offered).

    .PARAMETER Manifest
    Full file path for manifest (package.xml) of components to validate for deployment. Passed to sf as --manifest.

    .PARAMETER SourceDir
    Path to the local source files to validate for deployment. Passed to sf as --source-dir.

    .PARAMETER InputDir
    Root of directory or zip file of metadata formatted files to deploy. Passed to sf as --metadata-dir.

    .PARAMETER ManifestPackage
    Indicates that the metadata zip file points to a directory structure for a single package. Adds --single-package.

    .PARAMETER TestLevel
    Deployment Apex testing level. Passed to sf as --test-level. Default: TestsInOrg. Valid values: SpecificTests, ReferencedTests, TestsInFolder, TestsInOrg, TestsInOrgAndPackages, RelevantTests. Value mapping to the CLI: NoTests = NoTestRun, SpecificTests = RunSpecifiedTests, ReferencedTests = RunSpecifiedTests, TestsInFolder = RunSpecifiedTests, TestsInOrg = RunLocalTests, TestsInOrgAndPackages = RunAllTestsInOrg, RelevantTests = RunRelevantTests.

    .PARAMETER Tests
    Apex tests to run when --test-level is RunSpecifiedTests.

    .PARAMETER IgnoreWarnings
    Ignore warnings and allow a deployment to complete successfully. Adds --ignore-warnings.

    .PARAMETER Wait
    Number of minutes to wait for the command to complete and display results. Passed to sf as --wait.

    .PARAMETER Async
    Run the command asynchronously. Adds --async.

    .PARAMETER ConciseResults
    Show concise output of the validation result. Adds --concise.

    .PARAMETER DetailedResults
    Show verbose output of the validation result. Adds --verbose.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Test-SalesforceDeploy -SourceDir force-app -TestLevel TestsInOrg -TargetOrg prod
    Validate against production with all local tests.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy validate (plugin @salesforce/plugin-deploy-retrieve)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --coverage-formatters, --junit, --metadata, --post-destructive-changes, --pre-destructive-changes, --purge-on-delete, --results-dir
    Parameter to flag: -Manifest = --manifest; -SourceDir = --source-dir; -InputDir = --metadata-dir; -ManifestPackage = --single-package; -TestLevel = --test-level; -Tests = --tests; -IgnoreWarnings = --ignore-warnings; -Wait = --wait; -Async = --async; -ConciseResults = --concise; -DetailedResults = --verbose; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-deploy-retrieve

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Deploys a validated deployment without running the tests again.

    .DESCRIPTION
    Runs sf project deploy quick for the validation job ID (or the most recent with -UseMostRecent). The validation must have passed recently. Asks for confirmation and supports -WhatIf.

    .PARAMETER JobId
    Job ID of the deployment you want to quick deploy. Passed to sf as --job-id.

    .PARAMETER UseMostRecent
    Use the validation the CLI ran most recently. Use instead of -JobId.

    .PARAMETER Wait
    Number of minutes to wait for the command to complete and display results. Passed to sf as --wait.

    .PARAMETER Async
    Run the command asynchronously. Adds --async.

    .PARAMETER ConciseResults
    Show concise output of the deploy result. Adds --concise.

    .PARAMETER DetailedResults
    Show verbose output of the deploy result. Adds --verbose.

    .PARAMETER TargetOrg
    Username or alias of the target org. Passed to sf as --target-org.

    .EXAMPLE
    Start-SalesforceQuickDeploy -JobId 0Af000000000001AAA -TargetOrg prod -WhatIf
    Preview the quick deploy.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy quick (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -JobId = --job-id; -Wait = --wait; -Async = --async; -ConciseResults = --concise; -DetailedResults = --verbose; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-deploy-retrieve

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Reports the status of a deployment.

    .DESCRIPTION
    Runs sf project deploy report for a job ID, or for the most recent deployment with -UseMostRecent. Give one of the two. With -Wait the CLI keeps polling.

    .PARAMETER JobId
    Job ID of the deploy operation you want to check the status of. Passed to sf as --job-id.

    .PARAMETER UseMostRecent
    Report on the deployment the CLI started most recently. Use instead of -JobId.

    .PARAMETER Wait
    Number of minutes to wait for command to complete and display results. Passed to sf as --wait.

    .PARAMETER TargetOrg
    Username or alias of the target org. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDeployStatus -UseMostRecent -TargetOrg dev1
    Status of the last deployment.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy report (plugin @salesforce/plugin-deploy-retrieve)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --coverage-formatters, --junit, --results-dir
    Parameter to flag: -JobId = --job-id; -Wait = --wait; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-deploy-retrieve

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Resumes watching a deployment that is still running.

    .DESCRIPTION
    Runs sf project deploy resume for a job ID, or the most recent one with -UseMostRecent. The CLI finds the org from its record of the job, so there is no -TargetOrg.

    .PARAMETER JobId
    Job ID of the deploy operation you want to resume. Passed to sf as --job-id.

    .PARAMETER UseMostRecent
    Resume the deployment the CLI started most recently. Use instead of -JobId.

    .PARAMETER Wait
    Number of minutes to wait for the command to complete and display results. Passed to sf as --wait.

    .PARAMETER ConciseResults
    Show concise output of the deploy operation result. Adds --concise.

    .PARAMETER DetailedResults
    Show verbose output of the deploy operation result. Adds --verbose.

    .EXAMPLE
    Resume-SalesforceDeploy -UseMostRecent -Wait 10
    Wait up to ten more minutes for the last deployment.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy resume (plugin @salesforce/plugin-deploy-retrieve)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --coverage-formatters, --junit, --results-dir
    Parameter to flag: -JobId = --job-id; -Wait = --wait; -ConciseResults = --concise; -DetailedResults = --verbose.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-deploy-retrieve

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Cancels a deployment that is running.

    .DESCRIPTION
    Runs sf project deploy cancel for a job ID or the most recent one. Asks for confirmation and supports -WhatIf.

    .PARAMETER JobId
    Job ID of the deploy operation you want to cancel. Passed to sf as --job-id.

    .PARAMETER UseMostRecent
    Cancel the deployment the CLI started most recently. Use instead of -JobId.

    .PARAMETER Wait
    Number of minutes to wait for the command to complete and display results. Passed to sf as --wait.

    .PARAMETER Async
    Run the command asynchronously. Adds --async.

    .PARAMETER TargetOrg
    Username or alias of the target org. Passed to sf as --target-org.

    .EXAMPLE
    Stop-SalesforceDeploy -UseMostRecent -TargetOrg dev1 -WhatIf
    Preview the cancel.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy cancel (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -JobId = --job-id; -Wait = --wait; -Async = --async; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-deploy-retrieve

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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

    .PARAMETER SourceDir
    Path to the local source files to preview. Passed to sf as --source-dir.

    .PARAMETER Manifest
    Full file path for manifest (package.xml) of components to preview. Passed to sf as --manifest.

    .PARAMETER Metadata
    Metadata component names to preview. Passed to sf as --metadata.

    .PARAMETER IgnoreConflicts
    Don't display conflicts in preview of the deployment. Adds --ignore-conflicts.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDeployPreview -TargetOrg my-sandbox

    .EXAMPLE
    $p = Get-SalesforceDeployPreview -SourceDir force-app/main/default/classes; if ($p.HasConflicts) { $p.Conflicts }

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy preview (plugin @salesforce/plugin-deploy-retrieve)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --concise
    Parameter to flag: -SourceDir = --source-dir; -Manifest = --manifest; -Metadata = --metadata; -IgnoreConflicts = --ignore-conflicts; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-deploy-retrieve

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
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

    .PARAMETER IgnoreConflicts
    Don't display conflicts in the preview of the retrieval. Adds --ignore-conflicts.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceRetrievePreview -TargetOrg my-scratch

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project retrieve preview (plugin @salesforce/plugin-deploy-retrieve)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --concise
    Parameter to flag: -IgnoreConflicts = --ignore-conflicts; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-deploy-retrieve

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
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
    <#
    .SYNOPSIS
    Lists the objects in an org.

    .DESCRIPTION
    Runs sf sobject list and returns the object names. With no category the CLI lists all objects.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Describe-SalesforceObjects -TargetOrg dev1
    Every object name.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf sobject list (plugin @salesforce/plugin-schema)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --sobject
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-schema

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Describes one object: fields, relationships and settings.

    .DESCRIPTION
    Runs sf sobject describe and returns the full description as an object. Use Describe-SalesforceFields for just the field list.

    .PARAMETER Name
    API name of the object. Passed as --sobject. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .PARAMETER UseToolingApi
    Use Tooling API to display metadata for Tooling API objects. Adds --use-tooling-api.

    .EXAMPLE
    Describe-SalesforceObject -Name Account -TargetOrg dev1
    The full description of Account.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf sobject describe (plugin @salesforce/plugin-schema)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --sobject; -TargetOrg = --target-org; -UseToolingApi = --use-tooling-api.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-schema

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Lists the fields of an object.

    .DESCRIPTION
    Describes the object with Describe-SalesforceObject and returns name, label, type and byteLength for each field, sorted by name.

    .PARAMETER ObjectName
    API name of the object. Required.

    .PARAMETER TargetOrg
    Username or alias of the org. If omitted, the Salesforce CLI uses the default target org.

    .PARAMETER UseToolingApi
    Describe a Tooling API object instead of a standard or custom one.

    .EXAMPLE
    Describe-SalesforceFields -ObjectName Account -TargetOrg dev1
    The fields of Account.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Describe-SalesforceObject. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Lists the metadata types enabled in an org.

    .DESCRIPTION
    Runs sf org list metadata-types and returns just the type names (the xmlName of each type), for example ApexClass. Returns an empty array when the org reports none.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Describe-SalesforceMetadataTypes -TargetOrg dev1
    Every metadata type the org supports.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org list metadata-types (plugin @salesforce/plugin-org)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --output-file
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-org

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Builds a SELECT statement that lists every field of an object.

    .DESCRIPTION
    Reads the object's fields with Describe-SalesforceFields and returns the query text, for example SELECT Id,Name FROM Account. Use the switches to leave out groups of fields. Returns an empty string when the object has no fields. Field and object names are checked so only valid API names end up in the query.

    .PARAMETER ObjectName
    API name of the object. Required.

    .PARAMETER TargetOrg
    Username or alias of the org to describe. If omitted, the Salesforce CLI uses the default target org.

    .PARAMETER UseToolingApi
    Describe a Tooling API object instead of a standard or custom one.

    .PARAMETER ExcludeAuditFields
    Leave out CreatedById, CreatedDate, LastModifiedById, LastModifiedDate, SystemModstamp and IsDeleted.

    .PARAMETER ExcludeNameFields
    Leave out Name, FirstName, LastName and Subject.

    .PARAMETER ExcludeContextFields
    Leave out OwnerId, RecordTypeId, CurrencyIsoCode and Division.

    .EXAMPLE
    Build-SalesforceQuery -ObjectName Account -ExcludeAuditFields -TargetOrg dev1
    A query for the fields of Account without the audit fields.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Describe-SalesforceFields. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
