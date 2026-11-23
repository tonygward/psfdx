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
    Metadata type, for example ApexClass or CustomField. Required unless you give -SourceDir; completes from the org's metadata types and is checked.

    .PARAMETER Name
    Name of the component, for example an object name for a field. Together with -Type it forms --metadata Type:Name.

    .PARAMETER ChildName
    Metadata component names to retrieve. Wildcards (`*`) supported as long as you use quotes, such as `ApexClass:MyClass*`. Passed to sf as --metadata.

    .PARAMETER SourceDir
    Local source folders or files whose components are retrieved from the org. Each path must exist. Use instead of -Type. Passed as one --source-dir per value.

    .PARAMETER RootTypeWithDependencies
    Metadata types to retrieve together with the components they depend on. Valid values: Bot, AiAgentDefinitionVersion. Passed as one --root-type-with-dependencies per value.

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
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Type = --metadata; -Name = --metadata; -ChildName = --metadata; -SourceDir = --source-dir; -RootTypeWithDependencies = --root-type-with-dependencies; -TargetOrg = --target-org; -Wait = --wait; -OutputDir = --output-dir; -IgnoreConflicts = --ignore-conflicts.
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
        [Parameter(Mandatory = $false)][string[]] $SourceDir,
        [Parameter(Mandatory = $false)][ValidateSet('Bot', 'AiAgentDefinitionVersion')][string[]] $RootTypeWithDependencies,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][switch] $IgnoreConflicts
    )

    if ($ChildName -and -not $Name) {
        throw "Specify -Name when using -ChildName."
    }

    $sourceDirs = @($SourceDir | Where-Object { $_ })
    if ([string]::IsNullOrWhiteSpace($Type) -and $sourceDirs.Count -eq 0) {
        throw "Specify -Type or -SourceDir when retrieving a component."
    }
    if ([string]::IsNullOrWhiteSpace($Type) -and $Name) {
        throw "Specify -Type when using -Name."
    }
    foreach ($dir in $sourceDirs) {
        if (-not (Test-Path -LiteralPath $dir)) { throw "Source path '$dir' does not exist." }
    }

    $arguments = @('project', 'retrieve', 'start')
    if (-not [string]::IsNullOrWhiteSpace($Type)) {
        Assert-SalesforceMetadataType -Type $Type
        $metadata = $Type
        if ($Name) {
            $metadata += ":$Name"
            if ($ChildName) { $metadata += ".$ChildName" }
        }
        $arguments += @('--metadata', $metadata)
    }
    foreach ($dir in $sourceDirs) { $arguments += @('--source-dir', $dir) }
    foreach ($rootType in @($RootTypeWithDependencies | Where-Object { $_ })) { $arguments += @('--root-type-with-dependencies', $rootType) }
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

    .PARAMETER SinglePackage
    Treat the manifest as a single package (the retrieved zip holds one package folder). Adds --single-package.

    .PARAMETER ZipFileName
    File name of the retrieved zip. Passed as --zip-file-name. The CLI uses unpackaged.zip when omitted.

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
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Manifest = --manifest; -OutputDir = --target-metadata-dir; -Wait = --wait; -Unzip = --unzip; -SinglePackage = --single-package; -ZipFileName = --zip-file-name; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][switch] $SinglePackage,
        [Parameter(Mandatory = $false)][string] $ZipFileName,
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
    if ($SinglePackage) { $arguments += '--single-package' }
    if ($ZipFileName) { $arguments += @('--zip-file-name', $ZipFileName) }
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
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
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
    Also include the org's unlocked package contents. psfdx passes --include-packages=unlocked. Use New-SalesforceManifest for managed packages.

    .EXAMPLE
    Retrieve-SalesforceOrg -TargetOrg dev1
    Write allMetadata.xml and retrieve all metadata.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project generate manifest (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Command run: sf project retrieve start (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
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
    How tests run. psfdx level names are translated to the CLI's (see the value mapping). Passed to sf as --test-level. Default: NoTests. Valid values: NoTests, SpecificTests, ReferencedTests, TestsInFolder, TestsInOrg, TestsInOrgAndPackages, RelevantTests. Value mapping to the CLI: NoTests = NoTestRun, SpecificTests = RunSpecifiedTests, ReferencedTests = RunSpecifiedTests, TestsInFolder = RunSpecifiedTests, TestsInOrg = RunLocalTests, TestsInOrgAndPackages = RunAllTestsInOrg, RelevantTests = RunRelevantTests.

    .PARAMETER Tests
    Test classes to run for -TestLevel SpecificTests. Passed as one --tests per name.

    .PARAMETER Async
    Start the deployment and return without waiting for it (use Get-SalesforceDeployStatus or Resume-SalesforceDeploy later). Adds --async.

    .PARAMETER CoverageFormatters
    Format of the code coverage results written to the results folder. Valid values: clover, cobertura, html-spa, html, json, json-summary, lcovonly, none, teamcity, text, text-summary. Passed as one --coverage-formatters per value.

    .PARAMETER Junit
    Also write JUnit test results. Adds --junit.

    .PARAMETER ResultsDir
    Folder that receives the test and coverage results. Passed as --results-dir.

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
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Type = --metadata; -Name = --metadata; -SourceDir = --source-dir; -IgnoreConflicts = --ignore-conflicts; -IgnoreWarnings = --ignore-warnings; -IgnoreErrors = --ignore-errors; -Wait = --wait; -TestLevel = --test-level; -Tests = --tests; -Async = --async; -CoverageFormatters = --coverage-formatters; -Junit = --junit; -ResultsDir = --results-dir; -DryRun = --dry-run; -ConciseResults = --concise; -DetailedResults = --verbose; -TargetOrg = --target-org.
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
            'TestsInOrgAndPackages',
            'RelevantTests')][string] $TestLevel = 'NoTests',
        [Parameter(Mandatory = $false)][string[]] $Tests,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][ValidateSet('clover', 'cobertura', 'html-spa', 'html', 'json', 'json-summary', 'lcovonly', 'none', 'teamcity', 'text', 'text-summary')][string[]] $CoverageFormatters,
        [Parameter(Mandatory = $false)][switch] $Junit,
        [Parameter(Mandatory = $false)][string] $ResultsDir,
        [Parameter(Mandatory = $false)][switch] $DryRun,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if ($ConciseResults -and $DetailedResults) {
        throw "Specify only one of -ConciseResults or -DetailedResults."
    }
    Test-SalesforceDeployWaitParams -HasWait ($PSBoundParameters.ContainsKey('Wait')) -Async ([bool]$Async)

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

    if ($Async) { $arguments += '--async' }
    $arguments += Get-SalesforceDeployReportArguments -CoverageFormatters $CoverageFormatters -Junit:$Junit -ResultsDir $ResultsDir
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

    .PARAMETER PreDestructiveChanges
    Path of a destructiveChangesPre.xml file; the components it lists are deleted before the deploy. The file must exist. Passed as --pre-destructive-changes.

    .PARAMETER PostDestructiveChanges
    Path of a destructiveChangesPost.xml file; the components it lists are deleted after the deploy. The file must exist. Passed as --post-destructive-changes.

    .PARAMETER PurgeOnDelete
    Delete the destructive-changes components permanently instead of keeping them in the Recycle Bin. Needs -PreDestructiveChanges or -PostDestructiveChanges. Adds --purge-on-delete.

    .PARAMETER Async
    Start the deployment and return without waiting for it (use Get-SalesforceDeployStatus or Resume-SalesforceDeploy later). Adds --async.

    .PARAMETER CoverageFormatters
    Format of the code coverage results written to the results folder. Valid values: clover, cobertura, html-spa, html, json, json-summary, lcovonly, none, teamcity, text, text-summary. Passed as one --coverage-formatters per value.

    .PARAMETER Junit
    Also write JUnit test results. Adds --junit.

    .PARAMETER ResultsDir
    Folder that receives the test and coverage results. Passed as --results-dir.

    .EXAMPLE
    Deploy-SalesforceMetadata -Manifest manifest/package.xml -TargetOrg dev1 -WhatIf
    Preview deploying a manifest.

    .EXAMPLE
    Deploy-SalesforceMetadata -Manifest manifest/package.xml -PostDestructiveChanges manifest/destructiveChangesPost.xml -TargetOrg dev1
    Deploy a manifest, then delete the components listed in the destructive changes file.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy start (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Manifest = --manifest; -InputDir = --metadata-dir; -ManifestPackage = --single-package; -TargetOrg = --target-org; -IgnoreConflicts = --ignore-conflicts; -IgnoreWarnings = --ignore-warnings; -IgnoreErrors = --ignore-errors; -PreDestructiveChanges = --pre-destructive-changes; -PostDestructiveChanges = --post-destructive-changes; -PurgeOnDelete = --purge-on-delete; -Async = --async; -CoverageFormatters = --coverage-formatters; -Junit = --junit; -ResultsDir = --results-dir.
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
        [Parameter(Mandatory = $false)][switch] $IgnoreErrors,
        [Parameter(Mandatory = $false)][string] $PreDestructiveChanges,
        [Parameter(Mandatory = $false)][string] $PostDestructiveChanges,
        [Parameter(Mandatory = $false)][switch] $PurgeOnDelete,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][ValidateSet('clover', 'cobertura', 'html-spa', 'html', 'json', 'json-summary', 'lcovonly', 'none', 'teamcity', 'text', 'text-summary')][string[]] $CoverageFormatters,
        [Parameter(Mandatory = $false)][switch] $Junit,
        [Parameter(Mandatory = $false)][string] $ResultsDir
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
    $arguments += Get-SalesforceDestructiveChangeArguments -PreDestructiveChanges $PreDestructiveChanges -PostDestructiveChanges $PostDestructiveChanges -PurgeOnDelete:$PurgeOnDelete
    if ($Async) { $arguments += '--async' }
    $arguments += Get-SalesforceDeployReportArguments -CoverageFormatters $CoverageFormatters -Junit:$Junit -ResultsDir $ResultsDir
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

function Get-SalesforceDeployReportArguments {
    # Private: the --coverage-formatters, --junit and --results-dir flags that deploy start, validate, report and resume share.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string[]] $CoverageFormatters,
        [Parameter(Mandatory = $false)][switch] $Junit,
        [Parameter(Mandatory = $false)][string] $ResultsDir
    )
    $arguments = @()
    foreach ($formatter in @($CoverageFormatters | Where-Object { $_ })) { $arguments += @('--coverage-formatters', $formatter) }
    if ($Junit) { $arguments += '--junit' }
    if ($ResultsDir) { $arguments += @('--results-dir', $ResultsDir) }
    return $arguments
}

function Get-SalesforceDestructiveChangeArguments {
    # Private: the --pre-destructive-changes, --post-destructive-changes and --purge-on-delete flags of deploy start and validate.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $PreDestructiveChanges,
        [Parameter(Mandatory = $false)][string] $PostDestructiveChanges,
        [Parameter(Mandatory = $false)][switch] $PurgeOnDelete
    )
    $arguments = @()
    if ($PreDestructiveChanges) {
        if (-not (Test-Path -LiteralPath $PreDestructiveChanges -PathType Leaf)) { throw "Pre-destructive changes file '$PreDestructiveChanges' does not exist." }
        $arguments += @('--pre-destructive-changes', $PreDestructiveChanges)
    }
    if ($PostDestructiveChanges) {
        if (-not (Test-Path -LiteralPath $PostDestructiveChanges -PathType Leaf)) { throw "Post-destructive changes file '$PostDestructiveChanges' does not exist." }
        $arguments += @('--post-destructive-changes', $PostDestructiveChanges)
    }
    if ($PurgeOnDelete) {
        if (-not $PreDestructiveChanges -and -not $PostDestructiveChanges) { throw "-PurgeOnDelete needs -PreDestructiveChanges or -PostDestructiveChanges." }
        $arguments += '--purge-on-delete'
    }
    return $arguments
}

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

    .PARAMETER Metadata
    Metadata components to validate, such as ApexClass:MyClass. Use instead of -Manifest, -SourceDir and -InputDir. Passed as one --metadata per value.

    .PARAMETER PreDestructiveChanges
    Path of a destructiveChangesPre.xml file; the components it lists are deleted before the deploy. The file must exist. Passed as --pre-destructive-changes.

    .PARAMETER PostDestructiveChanges
    Path of a destructiveChangesPost.xml file; the components it lists are deleted after the deploy. The file must exist. Passed as --post-destructive-changes.

    .PARAMETER PurgeOnDelete
    Delete the destructive-changes components permanently instead of keeping them in the Recycle Bin. Needs -PreDestructiveChanges or -PostDestructiveChanges. Adds --purge-on-delete.

    .PARAMETER CoverageFormatters
    Format of the code coverage results written to the results folder. Valid values: clover, cobertura, html-spa, html, json, json-summary, lcovonly, none, teamcity, text, text-summary. Passed as one --coverage-formatters per value.

    .PARAMETER Junit
    Also write JUnit test results. Adds --junit.

    .PARAMETER ResultsDir
    Folder that receives the test and coverage results. Passed as --results-dir.
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
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Manifest = --manifest; -SourceDir = --source-dir; -InputDir = --metadata-dir; -Metadata = --metadata; -PreDestructiveChanges = --pre-destructive-changes; -PostDestructiveChanges = --post-destructive-changes; -PurgeOnDelete = --purge-on-delete; -CoverageFormatters = --coverage-formatters; -Junit = --junit; -ResultsDir = --results-dir; -ManifestPackage = --single-package; -TestLevel = --test-level; -Tests = --tests; -IgnoreWarnings = --ignore-warnings; -Wait = --wait; -Async = --async; -ConciseResults = --concise; -DetailedResults = --verbose; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][string[]] $Metadata,
        [Parameter(Mandatory = $false)][string] $PreDestructiveChanges,
        [Parameter(Mandatory = $false)][string] $PostDestructiveChanges,
        [Parameter(Mandatory = $false)][switch] $PurgeOnDelete,
        [Parameter(Mandatory = $false)][ValidateSet('clover', 'cobertura', 'html-spa', 'html', 'json', 'json-summary', 'lcovonly', 'none', 'teamcity', 'text', 'text-summary')][string[]] $CoverageFormatters,
        [Parameter(Mandatory = $false)][switch] $Junit,
        [Parameter(Mandatory = $false)][string] $ResultsDir,
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
    if (@($Metadata | Where-Object { $_ }).Count -gt 0) { $optionsProvided++ }
    if ($optionsProvided -ne 1) {
        throw "Specify exactly one of -Manifest, -SourceDir, -InputDir, or -Metadata."
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
    foreach ($component in @($Metadata | Where-Object { $_ })) { $arguments += @('--metadata', $component) }
    if ($ManifestPackage) { $arguments += '--single-package' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($IgnoreWarnings) { $arguments += '--ignore-warnings' }
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    if ($Async) { $arguments += '--async' }
    $arguments += Get-SalesforceDestructiveChangeArguments -PreDestructiveChanges $PreDestructiveChanges -PostDestructiveChanges $PostDestructiveChanges -PurgeOnDelete:$PurgeOnDelete
    $arguments += Get-SalesforceDeployReportArguments -CoverageFormatters $CoverageFormatters -Junit:$Junit -ResultsDir $ResultsDir
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

    .PARAMETER CoverageFormatters
    Format of the code coverage results written to the results folder. Valid values: clover, cobertura, html-spa, html, json, json-summary, lcovonly, none, teamcity, text, text-summary. Passed as one --coverage-formatters per value.

    .PARAMETER Junit
    Also write JUnit test results. Adds --junit.

    .PARAMETER ResultsDir
    Folder that receives the test and coverage results. Passed as --results-dir.
    .EXAMPLE
    Get-SalesforceDeployStatus -UseMostRecent -TargetOrg dev1
    Status of the last deployment.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy report (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -JobId = --job-id; -Wait = --wait; -TargetOrg = --target-org; -CoverageFormatters = --coverage-formatters; -Junit = --junit; -ResultsDir = --results-dir.
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
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][ValidateSet('clover', 'cobertura', 'html-spa', 'html', 'json', 'json-summary', 'lcovonly', 'none', 'teamcity', 'text', 'text-summary')][string[]] $CoverageFormatters,
        [Parameter(Mandatory = $false)][switch] $Junit,
        [Parameter(Mandatory = $false)][string] $ResultsDir
    )

    $jobParams = Get-SalesforceDeployJobParams -JobId $JobId -UseMostRecent:$UseMostRecent
    if ($PSBoundParameters.ContainsKey('Wait')) { Test-SalesforceValidDeployWait -Wait $Wait }

    $arguments = @('project', 'deploy', 'report') + $jobParams
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    $arguments += Get-SalesforceDeployReportArguments -CoverageFormatters $CoverageFormatters -Junit:$Junit -ResultsDir $ResultsDir
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

    .PARAMETER CoverageFormatters
    Format of the code coverage results written to the results folder. Valid values: clover, cobertura, html-spa, html, json, json-summary, lcovonly, none, teamcity, text, text-summary. Passed as one --coverage-formatters per value.

    .PARAMETER Junit
    Also write JUnit test results. Adds --junit.

    .PARAMETER ResultsDir
    Folder that receives the test and coverage results. Passed as --results-dir.
    .EXAMPLE
    Resume-SalesforceDeploy -UseMostRecent -Wait 10
    Wait up to ten more minutes for the last deployment.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy resume (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -JobId = --job-id; -Wait = --wait; -ConciseResults = --concise; -DetailedResults = --verbose; -CoverageFormatters = --coverage-formatters; -Junit = --junit; -ResultsDir = --results-dir.
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
        [Parameter(Mandatory = $false)][switch] $DetailedResults,
        [Parameter(Mandatory = $false)][ValidateSet('clover', 'cobertura', 'html-spa', 'html', 'json', 'json-summary', 'lcovonly', 'none', 'teamcity', 'text', 'text-summary')][string[]] $CoverageFormatters,
        [Parameter(Mandatory = $false)][switch] $Junit,
        [Parameter(Mandatory = $false)][string] $ResultsDir
    )

    $jobParams = Get-SalesforceDeployJobParams -JobId $JobId -UseMostRecent:$UseMostRecent
    Test-SalesforceDeployResultOptions -ConciseResults ([bool]$ConciseResults) -DetailedResults ([bool]$DetailedResults)
    if ($PSBoundParameters.ContainsKey('Wait')) { Test-SalesforceValidDeployWait -Wait $Wait }

    # sf project deploy resume has no --target-org; the org comes from the cached deployment.
    $arguments = @('project', 'deploy', 'resume') + $jobParams
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    if ($ConciseResults) { $arguments += '--concise' }
    if ($DetailedResults) { $arguments += '--verbose' }
    $arguments += Get-SalesforceDeployReportArguments -CoverageFormatters $CoverageFormatters -Junit:$Junit -ResultsDir $ResultsDir
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
    .PARAMETER ConciseResults
    Show concise output. Adds --concise.

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
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -SourceDir = --source-dir; -Manifest = --manifest; -Metadata = --metadata; -IgnoreConflicts = --ignore-conflicts; -ConciseResults = --concise; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
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
    if ($ConciseResults) { $arguments += '--concise' }
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
    .PARAMETER ConciseResults
    Show concise output. Adds --concise.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceRetrievePreview -TargetOrg my-scratch

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project retrieve preview (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -IgnoreConflicts = --ignore-conflicts; -ConciseResults = --concise; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('project', 'retrieve', 'preview')
    if ($IgnoreConflicts) { $arguments += '--ignore-conflicts' }
    if ($ConciseResults) { $arguments += '--concise' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    return Get-SalesforcePreviewResult -Arguments $arguments -Operation 'Retrieve' -CommonParams $commonParams
}

#endregion

#region Manifest and source conversion

function New-SalesforceManifest {
    <#
    .SYNOPSIS
    Writes a package.xml manifest from metadata names, local source or an org.

    .DESCRIPTION
    Runs sf project generate manifest and returns the CLI result (the path of the manifest written). Build the manifest from -Metadata names, from -SourceDir files, or from the metadata of an org with -FromOrg. Use -Type to write a destructive-changes or package manifest instead of package.xml. The output folder must already exist.

    .PARAMETER Metadata
    Metadata components to put in the manifest, such as ApexClass:MyClass. Passed as one --metadata per value.

    .PARAMETER ExcludedMetadata
    Metadata types to leave out of a manifest built with -FromOrg. Passed as one --excluded-metadata per value.

    .PARAMETER SourceDir
    Local source folders or files to build the manifest from. Passed as one --source-dir per value. Each path must exist.

    .PARAMETER FromOrg
    Username or alias of an org to build the manifest from. Passed as --from-org.

    .PARAMETER IncludePackages
    Also include the contents of managed or unlocked packages when building from an org. Valid values: managed, unlocked. Passed as one --include-packages per value.

    .PARAMETER Name
    File name of the manifest, without the .xml extension. Passed as --name. The CLI chooses a name from -Type when omitted.

    .PARAMETER OutputDir
    Folder that receives the manifest. It must exist. Passed as --output-dir.

    .PARAMETER Type
    Kind of manifest to write. Valid values: pre, post, destroy, package. Passed as --type.

    .EXAMPLE
    New-SalesforceManifest -SourceDir force-app -Name package -OutputDir manifest
    Write manifest/package.xml for everything in force-app.

    .EXAMPLE
    New-SalesforceManifest -FromOrg dev1 -ExcludedMetadata Report,Dashboard -IncludePackages unlocked
    Build a manifest from an org, leaving out reports and dashboards and adding unlocked package contents.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project generate manifest (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Metadata = --metadata; -ExcludedMetadata = --excluded-metadata; -SourceDir = --source-dir; -FromOrg = --from-org; -IncludePackages = --include-packages; -Name = --name; -OutputDir = --output-dir; -Type = --type.
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
        [Parameter(Mandatory = $false)][string[]] $Metadata,
        [Parameter(Mandatory = $false)][string[]] $ExcludedMetadata,
        [Parameter(Mandatory = $false)][string[]] $SourceDir,
        [Parameter(Mandatory = $false)][string] $FromOrg,
        [Parameter(Mandatory = $false)][ValidateSet('managed', 'unlocked')][string[]] $IncludePackages,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][ValidateSet('pre', 'post', 'destroy', 'package')][string] $Type
    )

    foreach ($dir in @($SourceDir | Where-Object { $_ })) {
        if (-not (Test-Path -LiteralPath $dir)) { throw "Source path '$dir' does not exist." }
    }
    if ($OutputDir -and -not (Test-Path -LiteralPath $OutputDir -PathType Container)) {
        throw "Output directory '$OutputDir' does not exist."
    }

    $arguments = @('project', 'generate', 'manifest')
    foreach ($component in @($Metadata | Where-Object { $_ })) { $arguments += @('--metadata', $component) }
    foreach ($component in @($ExcludedMetadata | Where-Object { $_ })) { $arguments += @('--excluded-metadata', $component) }
    foreach ($dir in @($SourceDir | Where-Object { $_ })) { $arguments += @('--source-dir', $dir) }
    if ($FromOrg) { $arguments += @('--from-org', $FromOrg) }
    foreach ($package in @($IncludePackages | Where-Object { $_ })) { $arguments += @('--include-packages', $package) }
    if ($Name) { $arguments += @('--name', $Name) }
    if ($OutputDir) { $arguments += @('--output-dir', $OutputDir) }
    if ($Type) { $arguments += @('--type', $Type) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function ConvertTo-SalesforceSourceFormat {
    <#
    .SYNOPSIS
    Converts Metadata API (mdapi) files into the source format of a Salesforce DX project.

    .DESCRIPTION
    Runs sf project convert mdapi. The files in -RootDir, which you retrieved as a package, are converted into source format and written to -OutputDir, or to the default package folder of the project. Use -Manifest, -Metadata or -MetadataDir to convert only part of them. Works on local files only; it does not touch an org.

    .PARAMETER RootDir
    Folder that holds the Metadata API files. It must exist. Passed as --root-dir. Required.

    .PARAMETER OutputDir
    Folder that receives the source format files. Passed as --output-dir. The CLI uses the default package folder when omitted.

    .PARAMETER Manifest
    Path of a package.xml that selects what to convert. The file must exist. Passed as --manifest.

    .PARAMETER Metadata
    Metadata components to convert, such as ApexClass:MyClass. Passed as one --metadata per value.

    .PARAMETER MetadataDir
    Folders inside -RootDir to convert. Passed as one --metadata-dir per value.

    .EXAMPLE
    ConvertTo-SalesforceSourceFormat -RootDir .\retrieved -OutputDir force-app
    Convert a retrieved package into source format.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project convert mdapi (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -RootDir = --root-dir; -OutputDir = --output-dir; -Manifest = --manifest; -Metadata = --metadata; -MetadataDir = --metadata-dir.
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
        [Parameter(Mandatory = $true)][string] $RootDir,
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][string] $Manifest,
        [Parameter(Mandatory = $false)][string[]] $Metadata,
        [Parameter(Mandatory = $false)][string[]] $MetadataDir
    )

    if (-not (Test-Path -LiteralPath $RootDir -PathType Container)) { throw "Root directory '$RootDir' does not exist." }
    if ($Manifest -and -not (Test-Path -LiteralPath $Manifest -PathType Leaf)) { throw "Manifest file '$Manifest' does not exist." }

    $arguments = @('project', 'convert', 'mdapi', '--root-dir', $RootDir)
    if ($OutputDir) { $arguments += @('--output-dir', $OutputDir) }
    if ($Manifest) { $arguments += @('--manifest', $Manifest) }
    foreach ($component in @($Metadata | Where-Object { $_ })) { $arguments += @('--metadata', $component) }
    foreach ($dir in @($MetadataDir | Where-Object { $_ })) { $arguments += @('--metadata-dir', $dir) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function ConvertTo-SalesforceMdapiFormat {
    <#
    .SYNOPSIS
    Converts Salesforce DX source files into Metadata API (mdapi) format.

    .DESCRIPTION
    Runs sf project convert source. The source in the project (or in -RootDir or -SourceDir) is converted into the format that Metadata API deploys, and written to -OutputDir. Works on local files only; it does not touch an org.

    .PARAMETER RootDir
    Folder that holds the source files. Passed as --root-dir. The CLI uses the project package folders when omitted.

    .PARAMETER SourceDir
    Source folders or files to convert. Each path must exist. Passed as one --source-dir per value.

    .PARAMETER OutputDir
    Folder that receives the converted files. Passed as --output-dir.

    .PARAMETER Manifest
    Path of a package.xml that selects what to convert. The file must exist. Passed as --manifest.

    .PARAMETER Metadata
    Metadata components to convert, such as ApexClass:MyClass. Passed as one --metadata per value.

    .PARAMETER PackageName
    Name of the package the converted files belong to. Passed as --package-name.

    .EXAMPLE
    ConvertTo-SalesforceMdapiFormat -SourceDir force-app -OutputDir .\mdapi
    Convert force-app to Metadata API format.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project convert source (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -RootDir = --root-dir; -SourceDir = --source-dir; -OutputDir = --output-dir; -Manifest = --manifest; -Metadata = --metadata; -PackageName = --package-name.
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
        [Parameter(Mandatory = $false)][string] $RootDir,
        [Parameter(Mandatory = $false)][string[]] $SourceDir,
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][string] $Manifest,
        [Parameter(Mandatory = $false)][string[]] $Metadata,
        [Parameter(Mandatory = $false)][string] $PackageName
    )

    if ($RootDir -and -not (Test-Path -LiteralPath $RootDir -PathType Container)) { throw "Root directory '$RootDir' does not exist." }
    foreach ($dir in @($SourceDir | Where-Object { $_ })) {
        if (-not (Test-Path -LiteralPath $dir)) { throw "Source path '$dir' does not exist." }
    }
    if ($Manifest -and -not (Test-Path -LiteralPath $Manifest -PathType Leaf)) { throw "Manifest file '$Manifest' does not exist." }

    $arguments = @('project', 'convert', 'source')
    if ($RootDir) { $arguments += @('--root-dir', $RootDir) }
    foreach ($dir in @($SourceDir | Where-Object { $_ })) { $arguments += @('--source-dir', $dir) }
    if ($OutputDir) { $arguments += @('--output-dir', $OutputDir) }
    if ($Manifest) { $arguments += @('--manifest', $Manifest) }
    foreach ($component in @($Metadata | Where-Object { $_ })) { $arguments += @('--metadata', $component) }
    if ($PackageName) { $arguments += @('--package-name', $PackageName) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Enable-SalesforceSourceBehavior {
    <#
    .SYNOPSIS
    Turns on a beta source behavior, such as decomposed permission sets, and updates the project to use it (beta).

    .DESCRIPTION
    Runs sf project convert source-behavior, a beta command, so its name, flags and result can change in a later CLI release. It rewrites the source files of the project and adds the behavior to sfdx-project.json. Supports -WhatIf and -Confirm (no prompt by default). -DryRun asks the CLI to show what it would change and changes nothing, so it runs without confirmation.

    .PARAMETER Behavior
    The behavior to turn on. Valid values: decomposeCustomLabelsBeta2, decomposeCustomLabelsBeta, decomposePermissionSetBeta, decomposePermissionSetBeta2, decomposeSharingRulesBeta, decomposeWorkflowBeta, decomposeExternalServiceRegistrationBeta. Passed as --behavior. Required.

    .PARAMETER DryRun
    Show what would change without changing it. Adds --dry-run.

    .PARAMETER PreserveTempDir
    Keep the temporary folder the CLI uses during the conversion. Adds --preserve-temp-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Passed to sf as --target-org.

    .EXAMPLE
    Enable-SalesforceSourceBehavior -Behavior decomposePermissionSetBeta2 -DryRun
    See what the behavior would change.

    .NOTES
    This runs a beta Salesforce CLI command. Beta commands can change or be removed without notice; psfdx does not promise they stay stable.
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project convert source-behavior (plugin @salesforce/plugin-deploy-retrieve, beta)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Behavior = --behavior; -DryRun = --dry-run; -PreserveTempDir = --preserve-temp-dir; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $true)][ValidateSet(
            'decomposeCustomLabelsBeta2',
            'decomposeCustomLabelsBeta',
            'decomposePermissionSetBeta',
            'decomposePermissionSetBeta2',
            'decomposeSharingRulesBeta',
            'decomposeWorkflowBeta',
            'decomposeExternalServiceRegistrationBeta')][string] $Behavior,
        [Parameter(Mandatory = $false)][switch] $DryRun,
        [Parameter(Mandatory = $false)][switch] $PreserveTempDir,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $arguments = @('project', 'convert', 'source-behavior', '--behavior', $Behavior)
    if ($DryRun) { $arguments += '--dry-run' }
    if ($PreserveTempDir) { $arguments += '--preserve-temp-dir' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    # A dry run changes nothing, so only a real conversion needs confirming.
    if (-not $DryRun -and -not $PSCmdlet.ShouldProcess('the project source files', "Enable source behavior $Behavior")) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceIgnoredFiles {
    <#
    .SYNOPSIS
    Lists the files in the project package folders that .forceignore leaves out.

    .DESCRIPTION
    Runs sf project list ignored and returns one path per ignored file. Read-only. Use -SourceDir to check one folder instead of every package directory.

    .PARAMETER SourceDir
    Folder or file to check. It must exist. Passed as --source-dir. The CLI checks every package directory when omitted.

    .EXAMPLE
    Get-SalesforceIgnoredFiles -SourceDir force-app/main/default/classes
    Which class files does .forceignore skip.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project list ignored (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -SourceDir = --source-dir.
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
        [Parameter(Mandatory = $false)][string] $SourceDir
    )

    if ($SourceDir -and -not (Test-Path -LiteralPath $SourceDir)) { throw "Source path '$SourceDir' does not exist." }

    $arguments = @('project', 'list', 'ignored')
    if ($SourceDir) { $arguments += @('--source-dir', $SourceDir) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region Delete source and source tracking

function Remove-SalesforceSource {
    <#
    .SYNOPSIS
    Deletes components from the org and from the local project.

    .DESCRIPTION
    Runs sf project delete source. The named source files or metadata components are deleted from a org that does not use source tracking, and their files are deleted from the project. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. -CheckOnly validates the delete without making it, so it needs no confirmation. Give -SourceDir or -Metadata. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time.

    .PARAMETER SourceDir
    Source folders or files to delete. Each path must exist. Passed as one --source-dir per value.

    .PARAMETER Metadata
    Metadata components to delete, such as ApexClass:MyClass. Passed as one --metadata per value.

    .PARAMETER CheckOnly
    Validate the delete, run any tests, and change nothing. Adds --check-only.

    .PARAMETER ForceOverwrite
    Delete even if it overwrites changes in a source-tracked org. Adds --force-overwrite.

    .PARAMETER TrackSource
    Update source tracking after the delete. Adds --track-source.

    .PARAMETER TestLevel
    Apex testing level. Passed to sf as --test-level. Valid values: NoTests, SpecificTests, TestsInOrg, TestsInOrgAndPackages, RelevantTests. Value mapping to the CLI: NoTests = NoTestRun, SpecificTests = RunSpecifiedTests, TestsInOrg = RunLocalTests, TestsInOrgAndPackages = RunAllTestsInOrg, RelevantTests = RunRelevantTests. The CLI default applies when omitted.

    .PARAMETER Tests
    Apex test classes to run with -TestLevel SpecificTests. Passed as one --tests per name.

    .PARAMETER Wait
    Number of minutes to wait for the command to finish. Passed as --wait.

    .PARAMETER DetailedResults
    Show verbose output of the delete result. Adds --verbose.

    .PARAMETER NoPrompt
    Do not ask for confirmation. Use it in unattended scripts. -WhatIf still shows what would happen without deleting.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceSource -Metadata ApexClass:OldHelper -TargetOrg dev1 -WhatIf
    Preview deleting one class from the org and the project.

    .EXAMPLE
    Remove-SalesforceSource -SourceDir force-app/main/default/classes/OldHelper.cls -CheckOnly -TargetOrg dev1
    Validate the delete without making it.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project delete source (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -SourceDir = --source-dir; -Metadata = --metadata; -CheckOnly = --check-only; -ForceOverwrite = --force-overwrite; -TrackSource = --track-source; -TestLevel = --test-level; -Tests = --tests; -Wait = --wait; -DetailedResults = --verbose; -NoPrompt = --no-prompt; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][string[]] $SourceDir,
        [Parameter(Mandatory = $false)][string[]] $Metadata,
        [Parameter(Mandatory = $false)][switch] $CheckOnly,
        [Parameter(Mandatory = $false)][switch] $ForceOverwrite,
        [Parameter(Mandatory = $false)][switch] $TrackSource,
        [Parameter(Mandatory = $false)][ValidateSet(
            'NoTests',
            'SpecificTests',
            'TestsInOrg',
            'TestsInOrgAndPackages',
            'RelevantTests')][string] $TestLevel,
        [Parameter(Mandatory = $false)][string[]] $Tests,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $DetailedResults,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $sourceDirs = @($SourceDir | Where-Object { $_ })
    $components = @($Metadata | Where-Object { $_ })
    if ($sourceDirs.Count -eq 0 -and $components.Count -eq 0) { throw "Specify -SourceDir or -Metadata." }
    foreach ($dir in $sourceDirs) {
        if (-not (Test-Path -LiteralPath $dir)) { throw "Source path '$dir' does not exist." }
    }
    if ($PSBoundParameters.ContainsKey('Wait')) { Test-SalesforceValidDeployWait -Wait $Wait }

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')

    $arguments = @('project', 'delete', 'source')
    foreach ($dir in $sourceDirs) { $arguments += @('--source-dir', $dir) }
    foreach ($component in $components) { $arguments += @('--metadata', $component) }
    if ($CheckOnly) { $arguments += '--check-only' }
    if ($ForceOverwrite) { $arguments += '--force-overwrite' }
    if ($TrackSource) { $arguments += '--track-source' }
    if ($PSBoundParameters.ContainsKey('TestLevel')) {
        $arguments += Get-SalesforceApexCliTestArguments @commonParams -TestLevel $TestLevel -Tests $Tests
    } elseif (@($Tests | Where-Object { $_ }).Count -gt 0) {
        throw "-Tests needs -TestLevel SpecificTests."
    }
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    if ($DetailedResults) { $arguments += '--verbose' }
    # psfdx asks first (or the caller said not to), so the CLI must not ask a second time.
    $arguments += '--no-prompt'
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'

    # A check-only run deletes nothing. -NoPrompt is the caller's decision not to be asked; it does not turn off -WhatIf.
    if ($NoPrompt -or $CheckOnly) { $ConfirmPreference = 'None' }
    $what = (@($sourceDirs) + @($components)) -join ', '
    if (-not $CheckOnly -and -not $PSCmdlet.ShouldProcess($what, 'Delete source from the org and the project')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceSourceTracking {
    <#
    .SYNOPSIS
    Deletes the local source tracking information of an org.

    .DESCRIPTION
    Runs sf project delete tracking. The local files that record what has changed between the project and the org are deleted; nothing in the org or in your source files changes, but the next deploy or retrieve cannot tell what changed. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time.

    .PARAMETER NoPrompt
    Do not ask for confirmation. Use it in unattended scripts. -WhatIf still shows what would happen without deleting.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceSourceTracking -TargetOrg dev1 -WhatIf
    Preview deleting the tracking files of dev1.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project delete tracking (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -NoPrompt = --no-prompt; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $arguments = @('project', 'delete', 'tracking', '--no-prompt')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    $target = if ($TargetOrg) { $TargetOrg } else { 'the default target org' }
    if ($PSCmdlet.ShouldProcess($target, 'Delete local source tracking information')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Reset-SalesforceSourceTracking {
    <#
    .SYNOPSIS
    Resets local and remote source tracking of an org to a revision.

    .DESCRIPTION
    Runs sf project reset tracking. Source tracking is reset to the latest revision in the org, or to the revision number you give with -Revision. After a reset the next deploy or retrieve starts from that point, so changes made before it are no longer reported. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time.

    .PARAMETER Revision
    SourceMember revision number to reset to. Passed as --revision. The CLI uses the latest revision when omitted; 0 resets to the beginning.

    .PARAMETER NoPrompt
    Do not ask for confirmation. Use it in unattended scripts. -WhatIf still shows what would happen without resetting.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Reset-SalesforceSourceTracking -Revision 0 -TargetOrg my-scratch -WhatIf
    Preview resetting tracking to the beginning.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project reset tracking (plugin @salesforce/plugin-deploy-retrieve)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Revision = --revision; -NoPrompt = --no-prompt; -TargetOrg = --target-org.
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
        [Parameter(Mandatory = $false)][ValidateRange(0, [int]::MaxValue)][int] $Revision,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $arguments = @('project', 'reset', 'tracking')
    if ($PSBoundParameters.ContainsKey('Revision')) { $arguments += @('--revision', $Revision) }
    $arguments += '--no-prompt'
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    $target = if ($TargetOrg) { $TargetOrg } else { 'the default target org' }
    if ($PSCmdlet.ShouldProcess($target, 'Reset source tracking')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

#endregion

#region DevOps Center pipeline deploys (beta)

function Get-SalesforcePipelineJobArguments {
    # Private: the --job-id / --use-most-recent choice of the sf project deploy pipeline commands.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $JobId,
        [Parameter(Mandatory = $false)][switch] $UseMostRecent
    )
    if ($JobId -and $UseMostRecent) { throw "Specify only one of -JobId or -UseMostRecent." }
    if (-not $JobId -and -not $UseMostRecent) { throw "Specify -JobId or -UseMostRecent." }
    if ($JobId) {
        if ($JobId -notmatch '^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?\z') {
            throw "Job ID '$JobId' is not a valid pipeline deploy job ID. Expected a 15 or 18 character ID."
        }
        return @('--job-id', $JobId)
    }
    return @('--use-most-recent')
}

function Get-SalesforcePipelineStartArguments {
    # Private: the arguments that sf project deploy pipeline start and validate share. Returns the arguments after the command words.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $DevOpsCenterUsername,
        [Parameter(Mandatory = $true)][string] $DevOpsCenterProjectName,
        [Parameter(Mandatory = $true)][string] $BranchName,
        [Parameter(Mandatory = $false)][string] $BundleVersionName,
        [Parameter(Mandatory = $false)][switch] $DeployAll,
        [Parameter(Mandatory = $false)][string] $TestLevel,
        [Parameter(Mandatory = $false)][string[]] $Tests,
        [Parameter(Mandatory = $false)][bool] $HasWait,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults,
        [Parameter(Mandatory = $false)][hashtable] $CommonParams = @{}
    )
    Test-SalesforceDeployResultOptions -ConciseResults ([bool]$ConciseResults) -DetailedResults ([bool]$DetailedResults)
    Test-SalesforceDeployWaitParams -HasWait $HasWait -Async ([bool]$Async)
    if ($HasWait) { Test-SalesforceValidDeployWait -Wait $Wait }
    $arguments = @('--devops-center-username', $DevOpsCenterUsername, '--devops-center-project-name', $DevOpsCenterProjectName, '--branch-name', $BranchName)
    if ($BundleVersionName) { $arguments += @('--bundle-version-name', $BundleVersionName) }
    if ($DeployAll) { $arguments += '--deploy-all' }
    if ($TestLevel) {
        $arguments += Get-SalesforceApexCliTestArguments @CommonParams -TestLevel $TestLevel -Tests $Tests
    } elseif (@($Tests | Where-Object { $_ }).Count -gt 0) {
        throw "-Tests needs -TestLevel SpecificTests."
    }
    if ($HasWait) { $arguments += @('--wait', $Wait) }
    if ($Async) { $arguments += '--async' }
    if ($ConciseResults) { $arguments += '--concise' }
    if ($DetailedResults) { $arguments += '--verbose' }
    return $arguments
}

function Start-SalesforcePipelineDeploy {
    <#
    .SYNOPSIS
    Deploys the changes of a branch to the org of a DevOps Center pipeline stage (beta).

    .DESCRIPTION
    Runs sf project deploy pipeline start, a beta command of the DevOps Center plugin. It needs a DevOps Center org that you are logged in to (-DevOpsCenterUsername) and the name of the DevOps Center project. Because the command is beta, its name, flags and result can change in a later CLI release. Asks for confirmation and supports -WhatIf. Returns the CLI result, which holds the job ID that Get-SalesforcePipelineDeployStatus, Resume-SalesforcePipelineDeploy and Start-SalesforcePipelineQuickDeploy take.

    .PARAMETER DevOpsCenterUsername
    Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.

    .PARAMETER DevOpsCenterProjectName
    Name of the DevOps Center project. Passed as --devops-center-project-name. Required.

    .PARAMETER BranchName
    Branch whose changes are deployed to the pipeline stage. Passed as --branch-name. Required.

    .PARAMETER BundleVersionName
    Version name of the bundle to deploy. Passed as --bundle-version-name.

    .PARAMETER DeployAll
    Deploy all the metadata in the branch, not only the changes. Adds --deploy-all.

    .PARAMETER TestLevel
    Apex testing level. Passed to sf as --test-level. Valid values: NoTests, SpecificTests, TestsInOrg, TestsInOrgAndPackages. Value mapping to the CLI: NoTests = NoTestRun, SpecificTests = RunSpecifiedTests, TestsInOrg = RunLocalTests, TestsInOrgAndPackages = RunAllTestsInOrg. The CLI default applies when omitted.

    .PARAMETER Tests
    Apex test classes to run with -TestLevel SpecificTests. Passed as one --tests per name.

    .PARAMETER Wait
    Number of minutes to wait for the deployment to finish. Passed as --wait. Cannot be used with -Async.

    .PARAMETER Async
    Start the deployment and return without waiting. Adds --async.

    .PARAMETER ConciseResults
    Show concise output of the result. Adds --concise.

    .PARAMETER DetailedResults
    Show verbose output of the result. Adds --verbose.

    .EXAMPLE
    Start-SalesforcePipelineDeploy -DevOpsCenterUsername doc-org -DevOpsCenterProjectName "Sales App" -BranchName feature/new-flow -TestLevel TestsInOrg -WhatIf
    Preview deploying a branch with all local tests.

    .NOTES
    This runs a beta Salesforce CLI command that needs a DevOps Center org. Beta commands can change or be removed without notice; psfdx does not promise they stay stable.
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy pipeline start (plugin @salesforce/plugin-devops-center, beta)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -DevOpsCenterUsername = --devops-center-username; -DevOpsCenterProjectName = --devops-center-project-name; -BranchName = --branch-name; -BundleVersionName = --bundle-version-name; -DeployAll = --deploy-all; -TestLevel = --test-level; -Tests = --tests; -Wait = --wait; -Async = --async; -ConciseResults = --concise; -DetailedResults = --verbose.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string] $DevOpsCenterUsername,
        [Parameter(Mandatory = $true)][string] $DevOpsCenterProjectName,
        [Parameter(Mandatory = $true)][string] $BranchName,
        [Parameter(Mandatory = $false)][string] $BundleVersionName,
        [Parameter(Mandatory = $false)][switch] $DeployAll,
        [Parameter(Mandatory = $false)][ValidateSet('NoTests', 'SpecificTests', 'TestsInOrg', 'TestsInOrgAndPackages')][string] $TestLevel,
        [Parameter(Mandatory = $false)][string[]] $Tests,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults
    )

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $arguments = @('project', 'deploy', 'pipeline', 'start')
    $arguments += Get-SalesforcePipelineStartArguments -DevOpsCenterUsername $DevOpsCenterUsername -DevOpsCenterProjectName $DevOpsCenterProjectName -BranchName $BranchName -BundleVersionName $BundleVersionName -DeployAll:$DeployAll -TestLevel $TestLevel -Tests $Tests -HasWait ($PSBoundParameters.ContainsKey('Wait')) -Wait $Wait -Async:$Async -ConciseResults:$ConciseResults -DetailedResults:$DetailedResults -CommonParams $commonParams
    $arguments += '--json'
    if ($PSCmdlet.ShouldProcess("branch $BranchName of $DevOpsCenterProjectName", 'Deploy to the pipeline stage')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Test-SalesforcePipelineDeploy {
    <#
    .SYNOPSIS
    Validates a deployment of a branch to the org of a DevOps Center pipeline stage, without deploying it (beta).

    .DESCRIPTION
    Runs sf project deploy pipeline validate, a beta command of the DevOps Center plugin. Nothing is deployed; a passing validation can be released with Start-SalesforcePipelineQuickDeploy. It needs a DevOps Center org that you are logged in to. Because the command is beta, its name, flags and result can change in a later CLI release.

    .PARAMETER DevOpsCenterUsername
    Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.

    .PARAMETER DevOpsCenterProjectName
    Name of the DevOps Center project. Passed as --devops-center-project-name. Required.

    .PARAMETER BranchName
    Branch whose changes are validated. Passed as --branch-name. Required.

    .PARAMETER BundleVersionName
    Version name of the bundle to validate. Passed as --bundle-version-name.

    .PARAMETER DeployAll
    Validate all the metadata in the branch, not only the changes. Adds --deploy-all.

    .PARAMETER TestLevel
    Apex testing level. Passed to sf as --test-level. Valid values: NoTests, SpecificTests, TestsInOrg, TestsInOrgAndPackages. Value mapping to the CLI: NoTests = NoTestRun, SpecificTests = RunSpecifiedTests, TestsInOrg = RunLocalTests, TestsInOrgAndPackages = RunAllTestsInOrg. The CLI default applies when omitted.

    .PARAMETER Tests
    Apex test classes to run with -TestLevel SpecificTests. Passed as one --tests per name.

    .PARAMETER Wait
    Number of minutes to wait for the validation to finish. Passed as --wait. Cannot be used with -Async.

    .PARAMETER Async
    Start the validation and return without waiting. Adds --async.

    .PARAMETER ConciseResults
    Show concise output of the result. Adds --concise.

    .PARAMETER DetailedResults
    Show verbose output of the result. Adds --verbose.

    .EXAMPLE
    Test-SalesforcePipelineDeploy -DevOpsCenterUsername doc-org -DevOpsCenterProjectName "Sales App" -BranchName main -TestLevel TestsInOrg -Wait 30
    Validate a branch with all local tests.

    .NOTES
    This runs a beta Salesforce CLI command that needs a DevOps Center org. Beta commands can change or be removed without notice; psfdx does not promise they stay stable.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy pipeline validate (plugin @salesforce/plugin-devops-center, beta)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -DevOpsCenterUsername = --devops-center-username; -DevOpsCenterProjectName = --devops-center-project-name; -BranchName = --branch-name; -BundleVersionName = --bundle-version-name; -DeployAll = --deploy-all; -TestLevel = --test-level; -Tests = --tests; -Wait = --wait; -Async = --async; -ConciseResults = --concise; -DetailedResults = --verbose.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $DevOpsCenterUsername,
        [Parameter(Mandatory = $true)][string] $DevOpsCenterProjectName,
        [Parameter(Mandatory = $true)][string] $BranchName,
        [Parameter(Mandatory = $false)][string] $BundleVersionName,
        [Parameter(Mandatory = $false)][switch] $DeployAll,
        [Parameter(Mandatory = $false)][ValidateSet('NoTests', 'SpecificTests', 'TestsInOrg', 'TestsInOrgAndPackages')][string] $TestLevel,
        [Parameter(Mandatory = $false)][string[]] $Tests,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults
    )

    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $arguments = @('project', 'deploy', 'pipeline', 'validate')
    $arguments += Get-SalesforcePipelineStartArguments -DevOpsCenterUsername $DevOpsCenterUsername -DevOpsCenterProjectName $DevOpsCenterProjectName -BranchName $BranchName -BundleVersionName $BundleVersionName -DeployAll:$DeployAll -TestLevel $TestLevel -Tests $Tests -HasWait ($PSBoundParameters.ContainsKey('Wait')) -Wait $Wait -Async:$Async -ConciseResults:$ConciseResults -DetailedResults:$DetailedResults -CommonParams $commonParams
    $arguments += '--json'
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Start-SalesforcePipelineQuickDeploy {
    <#
    .SYNOPSIS
    Deploys a validated pipeline deployment without running the tests again (beta).

    .DESCRIPTION
    Runs sf project deploy pipeline quick, a beta command of the DevOps Center plugin, for the job ID of a validation made with Test-SalesforcePipelineDeploy (or the most recent one with -UseMostRecent). Because the command is beta, its name, flags and result can change in a later CLI release. Asks for confirmation and supports -WhatIf.

    .PARAMETER DevOpsCenterUsername
    Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.

    .PARAMETER JobId
    Job ID of the validated deployment. A 15 or 18 character ID. Passed as --job-id.

    .PARAMETER UseMostRecent
    Use the validation the CLI ran most recently. Use instead of -JobId. Adds --use-most-recent.

    .PARAMETER Wait
    Number of minutes to wait for the deployment to finish. Passed as --wait. Cannot be used with -Async.

    .PARAMETER Async
    Start the deployment and return without waiting. Adds --async.

    .PARAMETER ConciseResults
    Show concise output of the result. Adds --concise.

    .PARAMETER DetailedResults
    Show verbose output of the result. Adds --verbose.

    .EXAMPLE
    Start-SalesforcePipelineQuickDeploy -DevOpsCenterUsername doc-org -UseMostRecent -WhatIf
    Preview the quick deploy of the last validation.

    .NOTES
    This runs a beta Salesforce CLI command that needs a DevOps Center org. Beta commands can change or be removed without notice; psfdx does not promise they stay stable.
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy pipeline quick (plugin @salesforce/plugin-devops-center, beta)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -DevOpsCenterUsername = --devops-center-username; -JobId = --job-id; -UseMostRecent = --use-most-recent; -Wait = --wait; -Async = --async; -ConciseResults = --concise; -DetailedResults = --verbose.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string] $DevOpsCenterUsername,
        [Parameter(Mandatory = $false)][string] $JobId,
        [Parameter(Mandatory = $false)][switch] $UseMostRecent,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $Async,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults
    )

    $jobParams = Get-SalesforcePipelineJobArguments -JobId $JobId -UseMostRecent:$UseMostRecent
    Test-SalesforceDeployResultOptions -ConciseResults ([bool]$ConciseResults) -DetailedResults ([bool]$DetailedResults)
    Test-SalesforceDeployWaitParams -HasWait ($PSBoundParameters.ContainsKey('Wait')) -Async ([bool]$Async)
    if ($PSBoundParameters.ContainsKey('Wait')) { Test-SalesforceValidDeployWait -Wait $Wait }

    $arguments = @('project', 'deploy', 'pipeline', 'quick', '--devops-center-username', $DevOpsCenterUsername) + $jobParams
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    if ($Async) { $arguments += '--async' }
    if ($ConciseResults) { $arguments += '--concise' }
    if ($DetailedResults) { $arguments += '--verbose' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $target = if ($JobId) { $JobId } else { 'most recent validated pipeline deployment' }
    if ($PSCmdlet.ShouldProcess($target, 'Quick deploy validated pipeline deployment')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Get-SalesforcePipelineDeployStatus {
    <#
    .SYNOPSIS
    Reports the status of a DevOps Center pipeline deployment (beta).

    .DESCRIPTION
    Runs sf project deploy pipeline report, a beta command of the DevOps Center plugin, for a job ID or for the most recent deployment with -UseMostRecent. Read-only. Because the command is beta, its name, flags and result can change in a later CLI release.

    .PARAMETER DevOpsCenterUsername
    Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.

    .PARAMETER JobId
    Job ID of the pipeline deployment. A 15 or 18 character ID. Passed as --job-id.

    .PARAMETER UseMostRecent
    Report on the deployment the CLI started most recently. Use instead of -JobId. Adds --use-most-recent.

    .EXAMPLE
    Get-SalesforcePipelineDeployStatus -DevOpsCenterUsername doc-org -UseMostRecent
    Status of the last pipeline deployment.

    .NOTES
    This runs a beta Salesforce CLI command that needs a DevOps Center org. Beta commands can change or be removed without notice; psfdx does not promise they stay stable.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy pipeline report (plugin @salesforce/plugin-devops-center, beta)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -DevOpsCenterUsername = --devops-center-username; -JobId = --job-id; -UseMostRecent = --use-most-recent.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $DevOpsCenterUsername,
        [Parameter(Mandatory = $false)][string] $JobId,
        [Parameter(Mandatory = $false)][switch] $UseMostRecent
    )

    $jobParams = Get-SalesforcePipelineJobArguments -JobId $JobId -UseMostRecent:$UseMostRecent
    $arguments = @('project', 'deploy', 'pipeline', 'report', '--devops-center-username', $DevOpsCenterUsername) + $jobParams
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Resume-SalesforcePipelineDeploy {
    <#
    .SYNOPSIS
    Resumes watching a DevOps Center pipeline deployment that is still running (beta).

    .DESCRIPTION
    Runs sf project deploy pipeline resume, a beta command of the DevOps Center plugin, for a job ID or for the most recent deployment with -UseMostRecent. Because the command is beta, its name, flags and result can change in a later CLI release.

    .PARAMETER DevOpsCenterUsername
    Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.

    .PARAMETER JobId
    Job ID of the pipeline deployment. A 15 or 18 character ID. Passed as --job-id.

    .PARAMETER UseMostRecent
    Resume the deployment the CLI started most recently. Use instead of -JobId. Adds --use-most-recent.

    .PARAMETER Wait
    Number of minutes to wait for the deployment to finish. Passed as --wait.

    .PARAMETER ConciseResults
    Show concise output of the result. Adds --concise.

    .PARAMETER DetailedResults
    Show verbose output of the result. Adds --verbose.

    .EXAMPLE
    Resume-SalesforcePipelineDeploy -DevOpsCenterUsername doc-org -UseMostRecent -Wait 10
    Wait up to ten more minutes for the last pipeline deployment.

    .NOTES
    This runs a beta Salesforce CLI command that needs a DevOps Center org. Beta commands can change or be removed without notice; psfdx does not promise they stay stable.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf project deploy pipeline resume (plugin @salesforce/plugin-devops-center, beta)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -DevOpsCenterUsername = --devops-center-username; -JobId = --job-id; -UseMostRecent = --use-most-recent; -Wait = --wait; -ConciseResults = --concise; -DetailedResults = --verbose.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $DevOpsCenterUsername,
        [Parameter(Mandatory = $false)][string] $JobId,
        [Parameter(Mandatory = $false)][switch] $UseMostRecent,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $ConciseResults,
        [Parameter(Mandatory = $false)][switch] $DetailedResults
    )

    $jobParams = Get-SalesforcePipelineJobArguments -JobId $JobId -UseMostRecent:$UseMostRecent
    Test-SalesforceDeployResultOptions -ConciseResults ([bool]$ConciseResults) -DetailedResults ([bool]$DetailedResults)
    if ($PSBoundParameters.ContainsKey('Wait')) { Test-SalesforceValidDeployWait -Wait $Wait }

    $arguments = @('project', 'deploy', 'pipeline', 'resume', '--devops-center-username', $DevOpsCenterUsername) + $jobParams
    if ($PSBoundParameters.ContainsKey('Wait')) { $arguments += @('--wait', $Wait) }
    if ($ConciseResults) { $arguments += '--concise' }
    if ($DetailedResults) { $arguments += '--verbose' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion



#region Describe

function Describe-SalesforceObjects {
    <#
    .SYNOPSIS
    Lists the objects in an org.

    .DESCRIPTION
    Runs sf sobject list and returns the object names. With no category the CLI lists all objects.

    .PARAMETER Category
    Which objects to list. Valid values: all, standard, custom. The CLI default is all. Passed to sf as --sobject.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Describe-SalesforceObjects -TargetOrg dev1
    Every object name.

    .EXAMPLE
    Describe-SalesforceObjects -Category custom -TargetOrg dev1
    Only the custom objects.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf sobject list (plugin @salesforce/plugin-schema)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org; -Category = --sobject.
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
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][ValidateSet('all', 'standard', 'custom')][string] $Category
    )
    $arguments = @('sobject', 'list')
    if ($Category) { $arguments += @('--sobject', $Category.ToLowerInvariant()) }
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

    .PARAMETER OutputFile
    Path of a file for the CLI to write the full result to (the type names with their suffix, directory and whether they have folders). Passed to sf as --output-file. The folder it goes in must exist. The cmdlet still returns the type names.

    .EXAMPLE
    Describe-SalesforceMetadataTypes -TargetOrg dev1
    Every metadata type the org supports.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org list metadata-types (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org; -OutputFile = --output-file.
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
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][string] $OutputFile
    )
    $arguments = @('org', 'list', 'metadata-types')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) {
        $arguments += @('--target-org', $TargetOrg)
    }
    if ($OutputFile) {
        $outputParent = Split-Path -Path $OutputFile -Parent
        if ($outputParent -and -not (Test-Path -LiteralPath $outputParent)) { throw "Output folder '$outputParent' does not exist." }
        $arguments += @('--output-file', $OutputFile)
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

function Get-SalesforceMetadataComponents {
    <#
    .SYNOPSIS
    Lists the metadata components of one type that exist in an org.

    .DESCRIPTION
    Runs sf org list metadata for a metadata type, for example ApexClass or CustomObject, and returns one object per component (fullName, fileName, type, id, createdDate, lastModifiedDate and who changed it). Use Describe-SalesforceMetadataTypes to see which types an org has. Types that live in folders, such as Report or EmailTemplate, need -Folder.

    .PARAMETER MetadataType
    Metadata type to list, for example ApexClass. Passed to sf as --metadata-type. Required. Tab completion offers the types of the org.

    .PARAMETER Folder
    Folder that holds the components, for types that are stored in folders. Passed to sf as --folder.

    .PARAMETER OutputFile
    Path of a file for the CLI to write the result to. Passed to sf as --output-file. The folder it goes in must exist. The cmdlet still returns the components.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceMetadataComponents -MetadataType ApexClass -TargetOrg dev1 | Select-Object fullName, lastModifiedDate
    Every Apex class in dev1 and when it last changed.

    .EXAMPLE
    Get-SalesforceMetadataComponents -MetadataType Report -Folder Sales -TargetOrg dev1
    The reports in the Sales folder.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org list metadata (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -MetadataType = --metadata-type; -Folder = --folder; -OutputFile = --output-file; -TargetOrg = --target-org.
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
    Param(
        [Parameter(Mandatory = $true)][ArgumentCompleter({ & (Get-Module psfdx-metadata -All | Select-Object -First 1) { Complete-SalesforceMetadataType @args } @args })][string] $MetadataType,
        [Parameter(Mandatory = $false)][string] $Folder,
        [Parameter(Mandatory = $false)][string] $OutputFile,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    Assert-SalesforceMetadataType -Type $MetadataType
    if ($OutputFile) {
        $outputParent = Split-Path -Path $OutputFile -Parent
        if ($outputParent -and -not (Test-Path -LiteralPath $outputParent)) { throw "Output folder '$outputParent' does not exist." }
    }
    $arguments = @('org', 'list', 'metadata', '--metadata-type', $MetadataType)
    if ($Folder) { $arguments += @('--folder', $Folder) }
    if ($OutputFile) { $arguments += @('--output-file', $OutputFile) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
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

#region Custom Metadata Types

# Wraps sf cmdt generate object, field, record, records and fromorg. They write metadata files into the current Salesforce DX project and return the CLI result as an object; only fromorg reads an org.

function New-SalesforceCustomMetadataType {
    <#
    .SYNOPSIS
    Creates the files of a new custom metadata type in the project.

    .DESCRIPTION
    Runs sf cmdt generate object, which writes the metadata file of a custom metadata type under a folder named <TypeName>__mdt. It works on local files and needs no org; run it inside a Salesforce DX project. Add fields with New-SalesforceCustomMetadataField and records with New-SalesforceCustomMetadataRecord. The result lists the type name, label, plural label and visibility.

    .PARAMETER TypeName
    Unique API name of the custom metadata type, without the __mdt suffix, for example MyCustomType. Letters, digits and underscores only. Passed to sf as --type-name. Required.

    .PARAMETER Label
    Label of the type. By default the CLI uses the type name. Passed to sf as --label.

    .PARAMETER PluralLabel
    Plural form of the label. By default the CLI uses the label. Passed to sf as --plural-label.

    .PARAMETER Visibility
    Who can see the type. Valid values: PackageProtected, Protected, Public. The CLI default is Public. Passed to sf as --visibility.

    .PARAMETER OutputDirectory
    Folder to write the type to, for example force-app/main/default/objects. By default the CLI writes to a <TypeName>__mdt folder in the current folder. Passed to sf as --output-directory.

    .EXAMPLE
    New-SalesforceCustomMetadataType -TypeName Feature_Flag -Label 'Feature Flag' -PluralLabel 'Feature Flags' -Visibility Protected -OutputDirectory force-app/main/default/objects
    Create a protected type in the project's objects folder.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf cmdt generate object (plugin @salesforce/plugin-custom-metadata)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TypeName = --type-name; -Label = --label; -PluralLabel = --plural-label; -Visibility = --visibility; -OutputDirectory = --output-directory.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-custom-metadata

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $TypeName,
        [Parameter(Mandatory = $false)][string] $Label,
        [Parameter(Mandatory = $false)][string] $PluralLabel,
        [Parameter(Mandatory = $false)][ValidateSet('PackageProtected', 'Protected', 'Public')][string] $Visibility,
        [Parameter(Mandatory = $false)][string] $OutputDirectory
    )
    $arguments = @('cmdt', 'generate', 'object', '--type-name', $TypeName)
    if ($Label) { $arguments += @('--label', $Label) }
    if ($PluralLabel) { $arguments += @('--plural-label', $PluralLabel) }
    if ($Visibility) { $arguments += @('--visibility', (@('PackageProtected', 'Protected', 'Public') | Where-Object { $_ -eq $Visibility } | Select-Object -First 1)) }
    if ($OutputDirectory) { $arguments += @('--output-directory', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceCustomMetadataField {
    <#
    .SYNOPSIS
    Creates the file of a new field of a custom metadata type.

    .DESCRIPTION
    Runs sf cmdt generate field, which writes a field definition file. Point -OutputDirectory at the type's folder, for example force-app/main/default/objects/MyCmdt__mdt, so the file lands in its fields folder. It works on local files and needs no org. A Picklist field needs -PicklistValues; -DecimalPlaces is for Number and Percent fields.

    .PARAMETER Name
    Unique API name of the field, without the __c suffix. Letters, digits and underscores only. Passed to sf as --name. Required.

    .PARAMETER Type
    Type of the field. Valid values: Checkbox, Date, DateTime, Email, Number, Percent, Phone, Picklist, Text, TextArea, LongTextArea, Url. Passed to sf as --type. Required.

    .PARAMETER Label
    Label of the field. By default the CLI uses the name. Passed to sf as --label.

    .PARAMETER DecimalPlaces
    Number of decimal places, for a Number or Percent field. Passed to sf as --decimal-places.

    .PARAMETER PicklistValues
    Values of a Picklist field. Each value is passed as its own --picklist-values. Required for a Picklist field. Passed to sf as --picklist-values.

    .PARAMETER OutputDirectory
    Folder to write the field definition to. By default the CLI writes to a fields folder in the current folder. Passed to sf as --output-directory.

    .EXAMPLE
    New-SalesforceCustomMetadataField -Name Mode -Type Picklist -PicklistValues On, Off, Auto -OutputDirectory force-app/main/default/objects/Feature_Flag__mdt
    Add a picklist field to a type.

    .EXAMPLE
    New-SalesforceCustomMetadataField -Name Threshold -Type Number -DecimalPlaces 2 -OutputDirectory force-app/main/default/objects/Feature_Flag__mdt
    Add a number field with two decimal places.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf cmdt generate field (plugin @salesforce/plugin-custom-metadata)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Type = --type; -Label = --label; -DecimalPlaces = --decimal-places; -PicklistValues = --picklist-values; -OutputDirectory = --output-directory.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-custom-metadata

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Name,
        [Parameter(Mandatory = $true)][ValidateSet('Checkbox', 'Date', 'DateTime', 'Email', 'Number', 'Percent', 'Phone', 'Picklist', 'Text', 'TextArea', 'LongTextArea', 'Url')][string] $Type,
        [Parameter(Mandatory = $false)][string] $Label,
        [Parameter(Mandatory = $false)][ValidateRange(0, 18)][int] $DecimalPlaces,
        [Parameter(Mandatory = $false)][string[]] $PicklistValues,
        [Parameter(Mandatory = $false)][string] $OutputDirectory
    )
    # ValidateSet ignores case, but the CLI does not: send the type spelled the way the CLI lists it.
    $Type = @('Checkbox', 'Date', 'DateTime', 'Email', 'Number', 'Percent', 'Phone', 'Picklist', 'Text', 'TextArea', 'LongTextArea', 'Url') | Where-Object { $_ -eq $Type } | Select-Object -First 1
    $values = @($PicklistValues | Where-Object { $_ })
    if ($Type -eq 'Picklist' -and $values.Count -eq 0) { throw 'A Picklist field needs -PicklistValues.' }
    if ($Type -ne 'Picklist' -and $values.Count -gt 0) { throw '-PicklistValues is only for a Picklist field.' }
    if ($PSBoundParameters.ContainsKey('DecimalPlaces') -and $Type -notin 'Number', 'Percent') { throw '-DecimalPlaces is only for a Number or Percent field.' }
    $arguments = @('cmdt', 'generate', 'field', '--name', $Name, '--type', $Type)
    if ($Label) { $arguments += @('--label', $Label) }
    if ($PSBoundParameters.ContainsKey('DecimalPlaces')) { $arguments += @('--decimal-places', $DecimalPlaces) }
    foreach ($value in $values) { $arguments += @('--picklist-values', $value) }
    if ($OutputDirectory) { $arguments += @('--output-directory', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceCustomMetadataRecord {
    <#
    .SYNOPSIS
    Creates the file of a new record of a custom metadata type.

    .DESCRIPTION
    Runs sf cmdt generate record, which writes a record file. The type must already be in the project (-InputDirectory says where to read its definition from). Give the field values as a hashtable in -Values, for example @{ Color__c = 'Red'; Size__c = 32 }; each pair is passed to the CLI as Field=Value. It works on local files and needs no org.

    .PARAMETER TypeName
    API name of the custom metadata type. The CLI needs the __mdt suffix, for example MyCmdt__mdt. Passed to sf as --type-name. Required.

    .PARAMETER RecordName
    Name of the new record. Passed to sf as --record-name. Required.

    .PARAMETER Label
    Label of the record. By default the CLI uses the record name. Passed to sf as --label.

    .PARAMETER Protected
    Protect the record when it is in a managed package. The switch sends the value true; without it the CLI default, false, applies. Passed to sf as --protected.

    .PARAMETER Values
    Field values as field name and value pairs. Field names are checked; a value may not contain a double quote or a line break. Each pair is passed to sf as Field=Value.

    .PARAMETER InputDirectory
    Folder to read the type definition from. The CLI default is force-app/main/default/objects. The folder must exist. Passed to sf as --input-directory.

    .PARAMETER OutputDirectory
    Folder to write the record to. The CLI default is force-app/main/default/customMetadata. Passed to sf as --output-directory.

    .EXAMPLE
    New-SalesforceCustomMetadataRecord -TypeName Feature_Flag__mdt -RecordName Checkout -Label 'Checkout' -Values @{ Mode__c = 'On'; Threshold__c = 2.5 }
    Create a record with two field values.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf cmdt generate record (plugin @salesforce/plugin-custom-metadata)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TypeName = --type-name; -RecordName = --record-name; -Label = --label; -Protected = --protected; -InputDirectory = --input-directory; -OutputDirectory = --output-directory.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-custom-metadata

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $TypeName,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $RecordName,
        [Parameter(Mandatory = $false)][string] $Label,
        [Parameter(Mandatory = $false)][switch] $Protected,
        [Parameter(Mandatory = $false)][System.Collections.IDictionary] $Values,
        [Parameter(Mandatory = $false)][string] $InputDirectory,
        [Parameter(Mandatory = $false)][string] $OutputDirectory
    )
    if ($InputDirectory -and -not (Test-Path -LiteralPath $InputDirectory -PathType Container)) { throw "Input directory '$InputDirectory' does not exist." }
    $pairs = @()
    if ($null -ne $Values) {
        foreach ($key in $Values.Keys) {
            $field = [string] $key
            if ($field -notmatch '^[A-Za-z][A-Za-z0-9_]*\z') { throw "'$field' is not a valid field name." }
            # A PowerShell boolean prints as True or False, which is not a valid XML boolean in the record file: write true or false.
            if ($Values[$key] -is [bool]) { $text = if ($Values[$key]) { 'true' } else { 'false' } }
            else { $text = [System.Convert]::ToString($Values[$key], [System.Globalization.CultureInfo]::InvariantCulture) }
            if ($text -match '["\r\n]') { throw "The value of '$field' contains a double quote or a line break, which the CLI cannot take safely." }
            $pairs += "$field=$text"
        }
    }
    $arguments = @('cmdt', 'generate', 'record', '--type-name', $TypeName, '--record-name', $RecordName)
    if ($Label) { $arguments += @('--label', $Label) }
    if ($Protected) { $arguments += @('--protected', 'true') }
    if ($InputDirectory) { $arguments += @('--input-directory', $InputDirectory) }
    if ($OutputDirectory) { $arguments += @('--output-directory', $OutputDirectory) }
    $arguments += $pairs
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceCustomMetadataRecordsFromCsv {
    <#
    .SYNOPSIS
    Creates custom metadata record files from the rows of a CSV file.

    .DESCRIPTION
    Runs sf cmdt generate records, which writes one record file per CSV row. The type must already be in the project. The Name column gives each record its name unless you pick another with -NameColumn; the other columns are field names. It returns one object per record. It works on local files and needs no org.

    .PARAMETER Csv
    Path of the CSV file. The file must exist. Passed to sf as --csv. Required.

    .PARAMETER TypeName
    API name of the custom metadata type. The CLI adds the __mdt suffix when it is left off. Passed to sf as --type-name. Required.

    .PARAMETER NameColumn
    CSV column that gives each record its name. The CLI default is Name. Passed to sf as --name-column.

    .PARAMETER InputDirectory
    Folder to read the type definition from. The CLI default is force-app/main/default/objects. The folder must exist. Passed to sf as --input-directory.

    .PARAMETER OutputDirectory
    Folder to write the records to. The CLI default is force-app/main/default/customMetadata. Passed to sf as --output-directory.

    .EXAMPLE
    New-SalesforceCustomMetadataRecordsFromCsv -Csv .\flags.csv -TypeName Feature_Flag -NameColumn Key
    One record per row, named from the Key column.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf cmdt generate records (plugin @salesforce/plugin-custom-metadata)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Csv = --csv; -TypeName = --type-name; -NameColumn = --name-column; -InputDirectory = --input-directory; -OutputDirectory = --output-directory.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-custom-metadata

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Csv,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $TypeName,
        [Parameter(Mandatory = $false)][string] $NameColumn,
        [Parameter(Mandatory = $false)][string] $InputDirectory,
        [Parameter(Mandatory = $false)][string] $OutputDirectory
    )
    if (-not (Test-Path -LiteralPath $Csv -PathType Leaf)) { throw "CSV file '$Csv' does not exist." }
    if ($InputDirectory -and -not (Test-Path -LiteralPath $InputDirectory -PathType Container)) { throw "Input directory '$InputDirectory' does not exist." }
    $arguments = @('cmdt', 'generate', 'records', '--csv', $Csv, '--type-name', $TypeName)
    if ($NameColumn) { $arguments += @('--name-column', $NameColumn) }
    if ($InputDirectory) { $arguments += @('--input-directory', $InputDirectory) }
    if ($OutputDirectory) { $arguments += @('--output-directory', $OutputDirectory) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceCustomMetadataTypeFromOrg {
    <#
    .SYNOPSIS
    Creates a custom metadata type, and a record for every row, from an object in an org.

    .DESCRIPTION
    Runs sf cmdt generate fromorg. It reads the fields and the records of a custom object or custom setting in the org and writes a custom metadata type with those fields and one record per row into the project, so you can move the data to custom metadata. A field of a type that custom metadata does not support becomes a text field, unless you pass -IgnoreUnsupported. Only local files are written; nothing in the org changes.

    .PARAMETER DevName
    API name for the new custom metadata type, without the __mdt suffix. Passed to sf as --dev-name. Required.

    .PARAMETER Sobject
    API name of the object in the org to copy, for example My_Settings__c. Passed to sf as --sobject. Required.

    .PARAMETER Label
    Label of the type. By default the CLI uses the name. Passed to sf as --label.

    .PARAMETER PluralLabel
    Plural form of the label. By default the CLI uses the label. Passed to sf as --plural-label.

    .PARAMETER Visibility
    Who can see the type. Valid values: PackageProtected, Protected, Public. The CLI default is Public. Passed to sf as --visibility.

    .PARAMETER IgnoreUnsupported
    Leave out fields of an unsupported type instead of turning them into text fields. Adds --ignore-unsupported.

    .PARAMETER TypeOutputDirectory
    Folder to write the type to. The CLI default is force-app/main/default/objects. Passed to sf as --type-output-directory.

    .PARAMETER RecordsOutputDir
    Folder to write the records to. The CLI default is force-app/main/default/customMetadata. Passed to sf as --records-output-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceCustomMetadataTypeFromOrg -DevName App_Config -Sobject App_Config__c -IgnoreUnsupported -TargetOrg dev1
    Turn the App_Config__c custom setting into a custom metadata type.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf cmdt generate fromorg (plugin @salesforce/plugin-custom-metadata)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -DevName = --dev-name; -Sobject = --sobject; -Label = --label; -PluralLabel = --plural-label; -Visibility = --visibility; -IgnoreUnsupported = --ignore-unsupported; -TypeOutputDirectory = --type-output-directory; -RecordsOutputDir = --records-output-dir; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-custom-metadata

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $DevName,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $Sobject,
        [Parameter(Mandatory = $false)][string] $Label,
        [Parameter(Mandatory = $false)][string] $PluralLabel,
        [Parameter(Mandatory = $false)][ValidateSet('PackageProtected', 'Protected', 'Public')][string] $Visibility,
        [Parameter(Mandatory = $false)][switch] $IgnoreUnsupported,
        [Parameter(Mandatory = $false)][string] $TypeOutputDirectory,
        [Parameter(Mandatory = $false)][string] $RecordsOutputDir,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('cmdt', 'generate', 'fromorg', '--dev-name', $DevName, '--sobject', $Sobject)
    if ($Label) { $arguments += @('--label', $Label) }
    if ($PluralLabel) { $arguments += @('--plural-label', $PluralLabel) }
    if ($Visibility) { $arguments += @('--visibility', (@('PackageProtected', 'Protected', 'Public') | Where-Object { $_ -eq $Visibility } | Select-Object -First 1)) }
    if ($IgnoreUnsupported) { $arguments += '--ignore-unsupported' }
    if ($TypeOutputDirectory) { $arguments += @('--type-output-directory', $TypeOutputDirectory) }
    if ($RecordsOutputDir) { $arguments += @('--records-output-dir', $RecordsOutputDir) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region Schema generators

# Wraps sf schema generate sobject, field, platformevent and tab. They write metadata files into the current Salesforce DX project. Three of them are interactive and run through Invoke-Salesforce -Interactive; tab takes everything from its parameters.

function Assert-SalesforceInteractiveSession {
    # Private: stops with a clear message when the session cannot ask questions, so an interactive generator does not wait for input that never comes.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Command
    )
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw "$Command asks questions, so it needs a terminal. Run it in an interactive PowerShell session, not in a script, job or pipeline whose input or output is redirected."
    }
}

function New-SalesforceCustomObject {
    <#
    .SYNOPSIS
    Creates the source files of a new custom object in the project, asking questions.

    .DESCRIPTION
    Runs sf schema generate sobject, which writes the metadata files of a custom object, with its Name field. It is interactive: it asks you questions (the API name, plural label, field type and so on, with suggestions based on the label), so it needs a terminal and a Salesforce DX project folder. Run it as a plain command. If you assign its output to a variable or pipe it, PowerShell captures the output and you cannot see the questions. It returns nothing; the files it writes are the result. Use -UseDefaultFeatures to switch on the optional features, such as reports and search, without being asked about each. To add fields afterwards use New-SalesforceCustomField.

    .PARAMETER Label
    Label of the custom object, for example My Object. The command suggests the API name and plural label from it. Passed to sf as --label. Required.

    .PARAMETER UseDefaultFeatures
    Turn on all the optional object features without asking. Adds --use-default-features.

    .EXAMPLE
    New-SalesforceCustomObject -Label 'Invoice' -UseDefaultFeatures
    Create the Invoice object and answer the rest of the questions at the prompt.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf schema generate sobject (plugin @salesforce/plugin-sobject)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Label = --label; -UseDefaultFeatures = --use-default-features.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-sobject

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Label,
        [Parameter(Mandatory = $false)][switch] $UseDefaultFeatures
    )
    Assert-SalesforceInteractiveSession -Command 'sf schema generate sobject'
    $arguments = @('schema', 'generate', 'sobject', '--label', $Label)
    if ($UseDefaultFeatures) { $arguments += '--use-default-features' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments -Interactive @commonParams
}

function New-SalesforceCustomField {
    <#
    .SYNOPSIS
    Creates the source files of a new custom field on an object in the project, asking questions.

    .DESCRIPTION
    Runs sf schema generate field, which writes the metadata file of a custom field on a standard or custom object. The object's source files must already be in the project (retrieve them first if they are not). It is interactive: it asks you questions (the API name, plural label, field type and so on, with suggestions based on the label), so it needs a terminal and a Salesforce DX project folder. Run it as a plain command. If you assign its output to a variable or pipe it, PowerShell captures the output and you cannot see the questions. It returns nothing; the files it writes are the result.

    .PARAMETER Label
    Label of the field, for example Invoice Total. The command suggests the API name from it. Passed to sf as --label. Required.

    .PARAMETER ObjectDirectory
    Folder that holds the object's source files, for example force-app/main/default/objects/Invoice__c. If you leave it out the command asks for the object. The folder must exist. Passed to sf as --object.

    .EXAMPLE
    New-SalesforceCustomField -Label 'Invoice Total' -ObjectDirectory force-app/main/default/objects/Invoice__c
    Add a field to the Invoice object and answer the questions about its type.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf schema generate field (plugin @salesforce/plugin-sobject)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Label = --label; -ObjectDirectory = --object.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-sobject

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Label,
        [Parameter(Mandatory = $false)][string] $ObjectDirectory
    )
    if ($ObjectDirectory -and -not (Test-Path -LiteralPath $ObjectDirectory -PathType Container)) { throw "Object folder '$ObjectDirectory' does not exist." }
    Assert-SalesforceInteractiveSession -Command 'sf schema generate field'
    $arguments = @('schema', 'generate', 'field', '--label', $Label)
    if ($ObjectDirectory) { $arguments += @('--object', $ObjectDirectory) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments -Interactive @commonParams
}

function New-SalesforcePlatformEvent {
    <#
    .SYNOPSIS
    Creates the source files of a new platform event in the project, asking questions.

    .DESCRIPTION
    Runs sf schema generate platformevent, which writes the metadata file of a platform event. It is interactive: it asks you questions (the API name, plural label, field type and so on, with suggestions based on the label), so it needs a terminal and a Salesforce DX project folder. Run it as a plain command. If you assign its output to a variable or pipe it, PowerShell captures the output and you cannot see the questions. It returns nothing; the files it writes are the result.

    .PARAMETER Label
    Label of the platform event, for example Order Shipped. The command suggests the API name from it. Passed to sf as --label. Required.

    .EXAMPLE
    New-SalesforcePlatformEvent -Label 'Order Shipped'
    Create the platform event and answer the rest of the questions at the prompt.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf schema generate platformevent (plugin @salesforce/plugin-sobject)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Label = --label.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-sobject

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Label
    )
    Assert-SalesforceInteractiveSession -Command 'sf schema generate platformevent'
    $arguments = @('schema', 'generate', 'platformevent', '--label', $Label)
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments -Interactive @commonParams
}

function New-SalesforceCustomTab {
    <#
    .SYNOPSIS
    Creates the source file of a new custom tab for a custom object.

    .DESCRIPTION
    Runs sf schema generate tab, which writes a custom tab file. Unlike the other schema generators it asks no questions: everything comes from the parameters. Run it inside a Salesforce DX project. The custom object's own source files do not have to be in the project. It returns the CLI result as an object.

    .PARAMETER ObjectName
    API name of the custom object the tab is for, for example Invoice__c. Letters, digits and underscores only. Passed to sf as --object. Required.

    .PARAMETER Directory
    Path of the tabs folder that will hold the tab file, for example force-app/main/default/tabs. The folder must already exist; the CLI does not create it. Passed to sf as --directory. Required.

    .PARAMETER Icon
    Number from 1 to 100 that picks the tab's color scheme and icon. The CLI default is 1, which is also used here. Passed to sf as --icon.

    .EXAMPLE
    New-SalesforceCustomTab -ObjectName Invoice__c -Directory force-app/main/default/tabs -Icon 54
    Create a tab for the Invoice object with icon 54.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf schema generate tab (plugin @salesforce/plugin-sobject)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ObjectName = --object; -Directory = --directory; -Icon = --icon.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-sobject

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string] $ObjectName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Directory,
        [Parameter(Mandatory = $false)][ValidateRange(1, 100)][int] $Icon
    )
    # The CLI does not create the tabs folder and fails with a bare ENOENT when it is missing.
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { throw "Tabs folder '$Directory' does not exist. Create it first, for example force-app/main/default/tabs." }
    if (-not $PSBoundParameters.ContainsKey('Icon')) { $Icon = 1 }
    $arguments = @('schema', 'generate', 'tab', '--object', $ObjectName, '--directory', $Directory, '--icon', $Icon)
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region DevOps Center

# Wraps sf devops, the DevOps Center commands: projects, work items, pipelines and their stages, branches and environments, and promotion. They need a DevOps Center org.
# The beta deploy commands of sf project deploy pipeline are in the region above.

function Get-SalesforceDevOpsProject {
    <#
    .SYNOPSIS
    Lists the DevOps Center projects of an org.

    .DESCRIPTION
    Runs sf devops project list. Returns the DevOps Center projects with their IDs, which the work item, pipeline and promotion cmdlets take. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDevOpsProject -TargetOrg devops-org
    List the projects.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops project list (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'project', 'list')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceDevOpsProject {
    <#
    .SYNOPSIS
    Creates a DevOps Center project.

    .DESCRIPTION
    Runs sf devops project create. Creates a project with a name and an optional description in the DevOps Center org. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER Name
    Name of the project. Passed to sf as --name. Required.

    .PARAMETER Description
    Description of the project. Passed to sf as --description.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceDevOpsProject -Name 'Sales App' -Description 'Quarterly releases' -TargetOrg devops-org -WhatIf
    Preview creating a project.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops project create (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Description = --description; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'project', 'create', '--name', $Name)
    if ($Description) { $arguments += @('--description', $Description) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($Name, 'Create DevOps Center project')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Update-SalesforceDevOpsProject {
    <#
    .SYNOPSIS
    Renames, describes or activates or deactivates a DevOps Center project.

    .DESCRIPTION
    Runs sf devops project update. Give at least one of -Name, -Description and -IsActive. Use -IsActive to activate the project and -IsActive:$false to deactivate it. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER ProjectId
    ID of the project to update. Passed to sf as --project-id. Required.

    .PARAMETER Name
    New name of the project. Passed to sf as --name.

    .PARAMETER Description
    New description of the project. Passed to sf as --description.

    .PARAMETER IsActive
    Set whether the project is active. Adds --is-active, or --no-is-active when you write -IsActive:$false. Passed to sf as --is-active.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Update-SalesforceDevOpsProject -ProjectId 0Hn000000000001 -IsActive:$false -TargetOrg devops-org -WhatIf
    Preview deactivating a project.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops project update (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ProjectId = --project-id; -Name = --name; -Description = --description; -IsActive = --is-active; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $ProjectId,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][switch] $IsActive,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if (-not $Name -and -not $Description -and -not $PSBoundParameters.ContainsKey('IsActive')) { throw 'Give at least one of -Name, -Description and -IsActive.' }
    $arguments = @('devops', 'project', 'update', '--project-id', $ProjectId)
    if ($Name) { $arguments += @('--name', $Name) }
    if ($Description) { $arguments += @('--description', $Description) }
    if ($PSBoundParameters.ContainsKey('IsActive')) { if ($IsActive) { $arguments += '--is-active' } else { $arguments += '--no-is-active' } }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($ProjectId, 'Update DevOps Center project')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDevOpsWorkItem {
    <#
    .SYNOPSIS
    Lists the work items of a DevOps Center project.

    .DESCRIPTION
    Runs sf devops work-item list. Each work item shows the branch, environment and repository details needed to check it out and promote it, and its ID, which the promotion cmdlets take. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER ProjectId
    ID of the project, from Get-SalesforceDevOpsProject. Passed to sf as --project-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDevOpsWorkItem -ProjectId 1Qg000000000001 -TargetOrg devops-org
    The work items of a project.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops work-item list (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ProjectId = --project-id; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $ProjectId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'work-item', 'list', '--project-id', $ProjectId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceDevOpsWorkItem {
    <#
    .SYNOPSIS
    Creates a work item in a DevOps Center project.

    .DESCRIPTION
    Runs sf devops work-item create. Creates a work item with a subject and an optional description. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER ProjectId
    ID of the project to create the work item in. Passed to sf as --project-id. Required.

    .PARAMETER Subject
    Subject (title) of the work item. Passed to sf as --subject. Required.

    .PARAMETER Description
    Description of the work item. Passed to sf as --description.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceDevOpsWorkItem -ProjectId 1Qg000000000001 -Subject 'Add invoice flow' -TargetOrg devops-org
    Create a work item.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops work-item create (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ProjectId = --project-id; -Subject = --subject; -Description = --description; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $ProjectId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Subject,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'work-item', 'create', '--project-id', $ProjectId, '--subject', $Subject)
    if ($Description) { $arguments += @('--description', $Description) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($Subject, 'Create DevOps Center work item')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Update-SalesforceDevOpsWorkItem {
    <#
    .SYNOPSIS
    Changes the subject, description or status of a work item.

    .DESCRIPTION
    Runs sf devops work-item update. Identify the work item by -WorkItemId or by -WorkItemName, and give at least one of -Subject, -Description and -Status. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER WorkItemId
    ID of the work item. Use it or -WorkItemName. Passed to sf as --work-item-id.

    .PARAMETER WorkItemName
    Name of the work item, such as WI-000001. Use it or -WorkItemId. Passed to sf as --work-item-name.

    .PARAMETER Subject
    New subject. Passed to sf as --subject.

    .PARAMETER Description
    New description. Passed to sf as --description.

    .PARAMETER Status
    New status. Valid values: In Progress, Ready to Promote. Passed to sf as --status.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Update-SalesforceDevOpsWorkItem -WorkItemName WI-000001 -Status 'Ready to Promote' -TargetOrg devops-org -WhatIf
    Preview marking a work item ready.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops work-item update (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -WorkItemId = --work-item-id; -WorkItemName = --work-item-name; -Subject = --subject; -Description = --description; -Status = --status; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $WorkItemId,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,79}\z')][string] $WorkItemName,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string] $Subject,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][ValidateSet('In Progress', 'Ready to Promote')][string] $Status,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($WorkItemId -and $WorkItemName) { throw 'Use -WorkItemId or -WorkItemName, not both.' }
    if (-not $WorkItemId -and -not $WorkItemName) { throw 'Give the work item with -WorkItemId or -WorkItemName.' }
    if (-not $Subject -and -not $Description -and -not $Status) { throw 'Give at least one of -Subject, -Description and -Status.' }
    if ($Status) { $Status = @('In Progress', 'Ready to Promote') | Where-Object { $_ -eq $Status } | Select-Object -First 1 }
    $arguments = @('devops', 'work-item', 'update')
    if ($WorkItemId) { $arguments += @('--work-item-id', $WorkItemId) }
    if ($WorkItemName) { $arguments += @('--work-item-name', $WorkItemName) }
    if ($Subject) { $arguments += @('--subject', $Subject) }
    if ($Description) { $arguments += @('--description', $Description) }
    if ($Status) { $arguments += @('--status', $Status) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($(if ($WorkItemId) { $WorkItemId } else { $WorkItemName }), 'Update DevOps Center work item')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Initialize-SalesforceDevOpsWorkItem {
    <#
    .SYNOPSIS
    Prepares a work item for a one-off promotion to a stage.

    .DESCRIPTION
    Runs sf devops work-item prepare. Creates the branches and pull requests in the source control repository that a one-off promotion needs. Run it before Start-SalesforceDevOpsPromotion for a one-off promotion. Get the IDs from Get-SalesforceDevOpsWorkItem. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER WorkItemId
    ID of the work item to prepare. Passed to sf as --work-item-id. Required.

    .PARAMETER TargetStageId
    ID of the pipeline stage to promote the work item to. Passed to sf as --target-stage-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Initialize-SalesforceDevOpsWorkItem -WorkItemId 1fk000000000001 -TargetStageId 1QV000000000001 -TargetOrg devops-org -WhatIf
    Preview preparing a work item.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops work-item prepare (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -WorkItemId = --work-item-id; -TargetStageId = --target-stage-id; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $WorkItemId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $TargetStageId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'work-item', 'prepare', '--work-item-id', $WorkItemId, '--target-stage-id', $TargetStageId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($WorkItemId, 'Prepare work item for promotion (creates branches and pull requests)')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Join-SalesforceDevOpsWorkItem {
    <#
    .SYNOPSIS
    Prepares work items to be combined and promoted together.

    .DESCRIPTION
    Runs sf devops work-item combine. Use it when work items in the same stage share metadata or depend on each other: DevOps Center combines the child work items into the parent so they are promoted as one unit. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER ParentWorkItemId
    ID of the parent work item. Passed to sf as --parent-work-item-id. Required.

    .PARAMETER ChildWorkItemId
    IDs of the work items to combine into the parent. Each is passed to sf as its own --child-work-item-id. Passed to sf as --child-work-item-id. Required.

    .PARAMETER TargetStageId
    ID of the pipeline stage to promote the combined work item to. Passed to sf as --target-stage-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Join-SalesforceDevOpsWorkItem -ParentWorkItemId 1fk000000000001 -ChildWorkItemId 1fk000000000002, 1fk000000000003 -TargetStageId 1QV000000000001 -TargetOrg devops-org -WhatIf
    Preview combining two work items into one.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops work-item combine (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ParentWorkItemId = --parent-work-item-id; -ChildWorkItemId = --child-work-item-id; -TargetStageId = --target-stage-id; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $ParentWorkItemId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string[]] $ChildWorkItemId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $TargetStageId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if (@($ChildWorkItemId | Where-Object { $_ }).Count -eq 0) { throw 'Give at least one -ChildWorkItemId.' }
    $arguments = @('devops', 'work-item', 'combine', '--parent-work-item-id', $ParentWorkItemId, '--target-stage-id', $TargetStageId)
    foreach ($item in @($ChildWorkItemId | Where-Object { $_ })) { $arguments += @('--child-work-item-id', $item) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($ParentWorkItemId, 'Combine work items')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceDevOpsReview {
    <#
    .SYNOPSIS
    Creates a pull request for a work item branch.

    .DESCRIPTION
    Runs sf devops review create. Creates the pull request through the DevOps Center API with the version control credentials stored in the org, for GitHub and Bitbucket, so no local login to the repository is needed. Identify the work item by -WorkItemId or -WorkItemName. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER WorkItemId
    ID of the work item. Use it or -WorkItemName. Passed to sf as --work-item-id.

    .PARAMETER WorkItemName
    Name of the work item, such as WI-000001. Use it or -WorkItemId. Passed to sf as --work-item-name.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceDevOpsReview -WorkItemName WI-000001 -TargetOrg devops-org -WhatIf
    Preview opening a pull request.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops review create (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -WorkItemId = --work-item-id; -WorkItemName = --work-item-name; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $WorkItemId,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,79}\z')][string] $WorkItemName,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($WorkItemId -and $WorkItemName) { throw 'Use -WorkItemId or -WorkItemName, not both.' }
    if (-not $WorkItemId -and -not $WorkItemName) { throw 'Give the work item with -WorkItemId or -WorkItemName.' }
    $arguments = @('devops', 'review', 'create')
    if ($WorkItemId) { $arguments += @('--work-item-id', $WorkItemId) }
    if ($WorkItemName) { $arguments += @('--work-item-name', $WorkItemName) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($(if ($WorkItemId) { $WorkItemId } else { $WorkItemName }), 'Create a pull request for the work item branch')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDevOpsPipeline {
    <#
    .SYNOPSIS
    Lists the DevOps Center pipelines.

    .DESCRIPTION
    Runs sf devops pipeline list. Returns every pipeline with its stages, repositories and connected projects. For one pipeline in detail use Get-SalesforceDevOpsPipelineDetails. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDevOpsPipeline -TargetOrg devops-org
    All pipelines.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops pipeline list (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'pipeline', 'list')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDevOpsPipelineDetails {
    <#
    .SYNOPSIS
    Shows one DevOps Center pipeline in detail.

    .DESCRIPTION
    Runs sf devops pipeline get. Returns one pipeline: its stages in order, the repository and branch of each stage, and its connected projects. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER PipelineId
    ID of the pipeline, from Get-SalesforceDevOpsPipeline. Passed to sf as --pipeline-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDevOpsPipelineDetails -PipelineId 0XB000000000001 -TargetOrg devops-org
    One pipeline in detail.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops pipeline get (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -PipelineId = --pipeline-id; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'pipeline', 'get', '--pipeline-id', $PipelineId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceDevOpsPipeline {
    <#
    .SYNOPSIS
    Creates a DevOps Center pipeline attached to a repository.

    .DESCRIPTION
    Runs sf devops pipeline create. Give the URL of an existing repository as -Repo, or use -CreateRepo with a repository name to create one on GitHub or Bitbucket. After you create the pipeline, add stages (unless you gave -Stage) and activate it with Update-SalesforceDevOpsPipeline -Activate. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER Name
    Name of the pipeline. Passed to sf as --name. Required.

    .PARAMETER Repo
    URL of an existing repository, or the name of a repository to create with -CreateRepo. Passed to sf as --repo. Required.

    .PARAMETER Stage
    Names of the pipeline stages in promotion order. Each is passed to sf as its own --stage. The CLI default is Integration, UAT, Staging and Production. Passed to sf as --stage.

    .PARAMETER ProjectId
    IDs of projects to associate with the pipeline. Each is passed to sf as its own --project-id. Passed to sf as --project-id.

    .PARAMETER CreateRepo
    Create the repository if it does not exist. Needs -RepoType, and -RepoOwner for GitHub or -BitbucketWorkspace for Bitbucket. Adds --create-repo.

    .PARAMETER RepoType
    Type of the repository. Valid values: github, bitbucket. Needed with -CreateRepo. Passed to sf as --repo-type.

    .PARAMETER RepoOwner
    Owner (organization or user) of the GitHub repository. Needed to create a GitHub repository. Passed to sf as --repo-owner.

    .PARAMETER BitbucketWorkspace
    Bitbucket workspace that will own the repository. Needed to create a Bitbucket repository. Passed to sf as --bitbucket-workspace.

    .PARAMETER BitbucketProjectKey
    Bitbucket project key to associate with the repository. Optional when creating a Bitbucket repository. Passed to sf as --bitbucket-project-key.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceDevOpsPipeline -Name 'Release Pipeline' -Repo https://github.com/myorg/myrepo -TargetOrg devops-org -WhatIf
    Preview creating a pipeline on an existing repository.

    .EXAMPLE
    New-SalesforceDevOpsPipeline -Name 'Release Pipeline' -Repo my-new-repo -CreateRepo -RepoType github -RepoOwner myorg -Stage Dev, QA, Prod -TargetOrg devops-org
    Create a pipeline, a new GitHub repository and three stages.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops pipeline create (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Name = --name; -Repo = --repo; -Stage = --stage; -ProjectId = --project-id; -CreateRepo = --create-repo; -RepoType = --repo-type; -RepoOwner = --repo-owner; -BitbucketWorkspace = --bitbucket-workspace; -BitbucketProjectKey = --bitbucket-project-key; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $true)][ValidatePattern('^[^\s-][^\s]*\z')][string] $Repo,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string[]] $Stage,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string[]] $ProjectId,
        [Parameter(Mandatory = $false)][switch] $CreateRepo,
        [Parameter(Mandatory = $false)][ValidateSet('github', 'bitbucket')][string] $RepoType,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string] $RepoOwner,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string] $BitbucketWorkspace,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string] $BitbucketProjectKey,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($CreateRepo -and -not $RepoType) { throw '-RepoType is needed with -CreateRepo.' }
    if ($CreateRepo -and $RepoType -eq 'github' -and -not $RepoOwner) { throw '-RepoOwner is needed to create a GitHub repository.' }
    if ($CreateRepo -and $RepoType -eq 'bitbucket' -and -not $BitbucketWorkspace) { throw '-BitbucketWorkspace is needed to create a Bitbucket repository.' }
    if ($RepoType) { $RepoType = @('github', 'bitbucket') | Where-Object { $_ -eq $RepoType } | Select-Object -First 1 }
    $arguments = @('devops', 'pipeline', 'create', '--name', $Name, '--repo', $Repo)
    foreach ($item in @($Stage | Where-Object { $_ })) { $arguments += @('--stage', $item) }
    foreach ($item in @($ProjectId | Where-Object { $_ })) { $arguments += @('--project-id', $item) }
    if ($CreateRepo) { $arguments += '--create-repo' }
    if ($RepoType) { $arguments += @('--repo-type', $RepoType) }
    if ($RepoOwner) { $arguments += @('--repo-owner', $RepoOwner) }
    if ($BitbucketWorkspace) { $arguments += @('--bitbucket-workspace', $BitbucketWorkspace) }
    if ($BitbucketProjectKey) { $arguments += @('--bitbucket-project-key', $BitbucketProjectKey) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($Name, 'Create DevOps Center pipeline')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Update-SalesforceDevOpsPipeline {
    <#
    .SYNOPSIS
    Renames, activates or deactivates a DevOps Center pipeline.

    .DESCRIPTION
    Runs sf devops pipeline update. Give at least one of -Name, -Activate and -Deactivate. A pipeline needs at least one stage before you can activate it, and you cannot change its stages after you activate it and promote changes through it, so -Activate asks for confirmation. You can combine -Deactivate and -Name. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER PipelineId
    ID of the pipeline. Passed to sf as --pipeline-id. Required.

    .PARAMETER Name
    New name of the pipeline. Passed to sf as --name.

    .PARAMETER Activate
    Activate the pipeline. Cannot be used with -Deactivate. Asks for confirmation by default. Adds --activate.

    .PARAMETER Deactivate
    Deactivate the pipeline. Cannot be used with -Activate. Adds --deactivate.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Update-SalesforceDevOpsPipeline -PipelineId 0XB000000000001 -Activate -TargetOrg devops-org -WhatIf
    Preview activating a pipeline.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops pipeline update (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -PipelineId = --pipeline-id; -Name = --name; -Activate = --activate; -Deactivate = --deactivate; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $false)][switch] $Activate,
        [Parameter(Mandatory = $false)][switch] $Deactivate,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($Activate -and $Deactivate) { throw 'Use -Activate or -Deactivate, not both.' }
    if (-not $Name -and -not $Activate -and -not $Deactivate) { throw 'Give at least one of -Name, -Activate and -Deactivate.' }
    if ($Activate -and -not $PSBoundParameters.ContainsKey('Confirm')) { $ConfirmPreference = 'Medium' }
    $arguments = @('devops', 'pipeline', 'update', '--pipeline-id', $PipelineId)
    if ($Name) { $arguments += @('--name', $Name) }
    if ($Activate) { $arguments += '--activate' }
    if ($Deactivate) { $arguments += '--deactivate' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($PipelineId, 'Update DevOps Center pipeline')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Add-SalesforceDevOpsPipelineProject {
    <#
    .SYNOPSIS
    Attaches a project to a DevOps Center pipeline.

    .DESCRIPTION
    Runs sf devops pipeline project add. Connects the project to the pipeline. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER PipelineId
    ID of the pipeline. Passed to sf as --pipeline-id. Required.

    .PARAMETER ProjectId
    ID of the project to attach. Passed to sf as --project-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Add-SalesforceDevOpsPipelineProject -PipelineId 0XB000000000001 -ProjectId 0Hn000000000001 -TargetOrg devops-org -WhatIf
    Preview attaching a project.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops pipeline project add (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -PipelineId = --pipeline-id; -ProjectId = --project-id; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $ProjectId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'pipeline', 'project', 'add', '--pipeline-id', $PipelineId, '--project-id', $ProjectId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($ProjectId, 'Attach project to DevOps Center pipeline')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceDevOpsPipelineProject {
    <#
    .SYNOPSIS
    Disconnects a project from a DevOps Center pipeline.

    .DESCRIPTION
    Runs sf devops pipeline project delete. Removes the connection between the project and the pipeline. The project itself is not deleted. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER PipelineId
    ID of the pipeline. Passed to sf as --pipeline-id. Required.

    .PARAMETER ProjectId
    ID of the project to disconnect. Passed to sf as --project-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceDevOpsPipelineProject -PipelineId 0XB000000000001 -ProjectId 0Hn000000000001 -TargetOrg devops-org -WhatIf
    Preview disconnecting a project.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops pipeline project delete (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -PipelineId = --pipeline-id; -ProjectId = --project-id; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $ProjectId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'pipeline', 'project', 'delete', '--pipeline-id', $PipelineId, '--project-id', $ProjectId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($ProjectId, 'Disconnect project from DevOps Center pipeline')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Add-SalesforceDevOpsPipelineStage {
    <#
    .SYNOPSIS
    Adds a stage to a DevOps Center pipeline.

    .DESCRIPTION
    Runs sf devops pipeline stage add. Inserts an empty stage before the stage given as -NextStageId. The new stage has no branch or environment: add them with Add-SalesforceDevOpsStageBranch and Add-SalesforceDevOpsStageEnvironment. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER PipelineId
    ID of the pipeline. Passed to sf as --pipeline-id. Required.

    .PARAMETER Name
    Name of the stage, such as Integration, UAT or Staging. Passed to sf as --name. Required.

    .PARAMETER NextStageId
    ID of the stage that follows the new stage. Passed to sf as --next-stage-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Add-SalesforceDevOpsPipelineStage -PipelineId 0XB000000000001 -Name QA -NextStageId 1QV000000000002 -TargetOrg devops-org -WhatIf
    Preview adding a QA stage.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops pipeline stage add (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -PipelineId = --pipeline-id; -Name = --name; -NextStageId = --next-stage-id; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $NextStageId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'pipeline', 'stage', 'add', '--pipeline-id', $PipelineId, '--name', $Name, '--next-stage-id', $NextStageId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($Name, 'Add stage to DevOps Center pipeline')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Update-SalesforceDevOpsPipelineStage {
    <#
    .SYNOPSIS
    Renames a stage of a DevOps Center pipeline.

    .DESCRIPTION
    Runs sf devops pipeline stage update. Changes the name of the stage. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER StageId
    ID of the stage. Passed to sf as --stage-id. Required.

    .PARAMETER Name
    New name of the stage. Passed to sf as --name. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Update-SalesforceDevOpsPipelineStage -StageId 1QV000000000002 -Name Staging -TargetOrg devops-org -WhatIf
    Preview renaming a stage.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops pipeline stage update (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -StageId = --stage-id; -Name = --name; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $StageId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'pipeline', 'stage', 'update', '--stage-id', $StageId, '--name', $Name)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($StageId, 'Rename DevOps Center pipeline stage')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceDevOpsPipelineStage {
    <#
    .SYNOPSIS
    Deletes a stage from a DevOps Center pipeline.

    .DESCRIPTION
    Runs sf devops pipeline stage delete. If the stage sits between two others, the stage before it is linked to the stage after it, so the chain stays whole. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER PipelineId
    ID of the pipeline that holds the stage. Passed to sf as --pipeline-id. Required.

    .PARAMETER StageId
    ID of the stage to delete. Passed to sf as --stage-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceDevOpsPipelineStage -PipelineId 0XB000000000001 -StageId 1QV000000000002 -TargetOrg devops-org -WhatIf
    Preview deleting a stage.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops pipeline stage delete (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -PipelineId = --pipeline-id; -StageId = --stage-id; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $StageId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'pipeline', 'stage', 'delete', '--pipeline-id', $PipelineId, '--stage-id', $StageId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($StageId, 'Delete DevOps Center pipeline stage')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Add-SalesforceDevOpsStageBranch {
    <#
    .SYNOPSIS
    Assigns a repository branch to a pipeline stage.

    .DESCRIPTION
    Runs sf devops stage branch add. By default the branch must already exist in the repository; -CreateVcsBranch creates it. A stage has one branch. If it already has one the command stops so the old branch is not orphaned, unless you give -Force, which replaces it. Branches are set from right to left: a stage can have a branch only after the stage to its right has one. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER PipelineId
    ID of the pipeline that holds the stage. Passed to sf as --pipeline-id. Required.

    .PARAMETER StageId
    ID of the stage. Passed to sf as --stage-id. Required.

    .PARAMETER BranchName
    Name of the repository branch. Passed to sf as --branch-name. Required.

    .PARAMETER CreateVcsBranch
    Create the branch in the remote repository if it does not exist. Adds --create-vcs-branch.

    .PARAMETER Force
    Replace the stage's existing branch. Adds --force.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Add-SalesforceDevOpsStageBranch -PipelineId 0XB000000000001 -StageId 1QV000000000002 -BranchName uat -CreateVcsBranch -TargetOrg devops-org -WhatIf
    Preview assigning a branch, creating it if needed.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops stage branch add (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -PipelineId = --pipeline-id; -StageId = --stage-id; -BranchName = --branch-name; -CreateVcsBranch = --create-vcs-branch; -Force = --force; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $StageId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $BranchName,
        [Parameter(Mandatory = $false)][switch] $CreateVcsBranch,
        [Parameter(Mandatory = $false)][switch] $Force,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'stage', 'branch', 'add', '--pipeline-id', $PipelineId, '--stage-id', $StageId, '--branch-name', $BranchName)
    if ($CreateVcsBranch) { $arguments += '--create-vcs-branch' }
    if ($Force) { $arguments += '--force' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($BranchName, 'Assign branch to DevOps Center pipeline stage')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceDevOpsStageBranch {
    <#
    .SYNOPSIS
    Removes the branch of a pipeline stage from the stage.

    .DESCRIPTION
    Runs sf devops stage branch delete. Only the link between the stage and its branch is removed; the branch in the repository stays. Branches are set from right to left, so this also removes the branches of every stage before it (to its left). The pipeline must be inactive. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER PipelineId
    ID of the pipeline that holds the stage. The CLI uses it to check that the pipeline is inactive. Passed to sf as --pipeline-id. Required.

    .PARAMETER StageId
    ID of the stage whose branch to remove. Passed to sf as --stage-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceDevOpsStageBranch -PipelineId 0XB000000000001 -StageId 1QV000000000002 -TargetOrg devops-org -WhatIf
    Preview removing a stage's branch.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops stage branch delete (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -PipelineId = --pipeline-id; -StageId = --stage-id; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $StageId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'stage', 'branch', 'delete', '--pipeline-id', $PipelineId, '--stage-id', $StageId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($StageId, 'Remove branch from DevOps Center pipeline stage (and from the stages before it)')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Add-SalesforceDevOpsStageEnvironment {
    <#
    .SYNOPSIS
    Adds a Salesforce environment to a pipeline stage.

    .DESCRIPTION
    Runs sf devops stage environment add. Starts an OAuth login to connect the environment, which opens a browser window (-NoBrowser prints the URL instead) and waits until you finish. A stage has one environment. If it already has one the command stops unless you give -Force, which adds the new one first and removes the old one after the new one is connected. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER PipelineId
    ID of the pipeline that holds the stage. Passed to sf as --pipeline-id. Required.

    .PARAMETER StageId
    ID of the stage. Passed to sf as --stage-id. Required.

    .PARAMETER EnvironmentName
    Name of the environment. Passed to sf as --environment-name. Required.

    .PARAMETER OrgType
    Type of the Salesforce org. Valid values: Production, Sandbox. Passed to sf as --org-type. Required.

    .PARAMETER NoBrowser
    Do not open the browser for the login; the CLI prints the URL to open yourself. Adds --no-browser.

    .PARAMETER Force
    Replace the stage's existing environment. Adds --force.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Add-SalesforceDevOpsStageEnvironment -PipelineId 0XB000000000001 -StageId 1QV000000000002 -EnvironmentName uat-sandbox -OrgType Sandbox -TargetOrg devops-org -WhatIf
    Preview connecting a sandbox to a stage.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops stage environment add (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -PipelineId = --pipeline-id; -StageId = --stage-id; -EnvironmentName = --environment-name; -OrgType = --org-type; -NoBrowser = --no-browser; -Force = --force; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $StageId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $EnvironmentName,
        [Parameter(Mandatory = $true)][ValidateSet('Production', 'Sandbox')][string] $OrgType,
        [Parameter(Mandatory = $false)][switch] $NoBrowser,
        [Parameter(Mandatory = $false)][switch] $Force,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($OrgType) { $OrgType = @('Production', 'Sandbox') | Where-Object { $_ -eq $OrgType } | Select-Object -First 1 }
    $arguments = @('devops', 'stage', 'environment', 'add', '--pipeline-id', $PipelineId, '--stage-id', $StageId, '--environment-name', $EnvironmentName, '--org-type', $OrgType)
    if ($NoBrowser) { $arguments += '--no-browser' }
    if ($Force) { $arguments += '--force' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($EnvironmentName, 'Add environment to DevOps Center pipeline stage (starts an OAuth login)')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceDevOpsStageEnvironment {
    <#
    .SYNOPSIS
    Removes an environment from a pipeline stage.

    .DESCRIPTION
    Runs sf devops stage environment delete. The pipeline must be inactive. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER PipelineId
    ID of the pipeline. The CLI uses it to check that the pipeline is inactive. Passed to sf as --pipeline-id. Required.

    .PARAMETER EnvironmentId
    ID of the environment to remove. Passed to sf as --environment-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceDevOpsStageEnvironment -PipelineId 0XB000000000001 -EnvironmentId 0Xx000000000001 -TargetOrg devops-org -WhatIf
    Preview removing an environment.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops stage environment delete (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -PipelineId = --pipeline-id; -EnvironmentId = --environment-id; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $PipelineId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $EnvironmentId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'stage', 'environment', 'delete', '--pipeline-id', $PipelineId, '--environment-id', $EnvironmentId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($EnvironmentId, 'Remove environment from DevOps Center pipeline stage')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Start-SalesforceDevOpsPromotion {
    <#
    .SYNOPSIS
    Promotes work items, or a whole stage, to a pipeline stage.

    .DESCRIPTION
    Runs sf devops promote. Give -WorkItemId to promote specific work items, or -StageId to promote all the approved work items of a source stage; exactly one of the two. It deploys to the org of the target stage. By default it stops if another promotion to the same stage is running (-Force overrides) and it checks first that each work item has a pull request (-SkipValidation skips that). It returns a request token that Get-SalesforceDevOpsRequestStatus takes. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER TargetStageId
    ID of the pipeline stage to promote to. Passed to sf as --target-stage-id. Required.

    .PARAMETER WorkItemId
    IDs of the work items to promote. Each is passed to sf as its own --work-item-id. Use it or -StageId. Passed to sf as --work-item-id.

    .PARAMETER StageId
    ID of the source stage whose approved work items are promoted. Use it or -WorkItemId. Passed to sf as --stage-id.

    .PARAMETER DeployAll
    Deploy all the metadata in the branch, not only the changes that are not yet in the target stage. Adds --deploy-all.

    .PARAMETER Force
    Submit the promotion even if another promotion to the same target stage is in progress. Adds --force.

    .PARAMETER SkipValidation
    Skip the check before the promotion that each work item has a pull request. Adds --skip-validation.

    .PARAMETER TestLevel
    Apex test level of the deployment. Valid values: NoTestRun, RunSpecifiedTests, RunLocalTests, RunAllTestsInOrg. NoTestRun is only for development orgs. Passed to sf as --test-level.

    .PARAMETER Tests
    Apex tests to run with -TestLevel RunSpecifiedTests. Each is passed to sf as its own --tests. Passed to sf as --tests.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Start-SalesforceDevOpsPromotion -StageId 1QV000000000001 -TargetStageId 1QV000000000002 -TargetOrg devops-org -WhatIf
    Preview promoting a whole stage.

    .EXAMPLE
    Start-SalesforceDevOpsPromotion -WorkItemId 1fk000000000001, 1fk000000000002 -TargetStageId 1QV000000000001 -TestLevel RunLocalTests -TargetOrg devops-org
    Promote two work items and run the local tests.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops promote (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetStageId = --target-stage-id; -WorkItemId = --work-item-id; -StageId = --stage-id; -DeployAll = --deploy-all; -Force = --force; -SkipValidation = --skip-validation; -TestLevel = --test-level; -Tests = --tests; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $TargetStageId,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string[]] $WorkItemId,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $StageId,
        [Parameter(Mandatory = $false)][switch] $DeployAll,
        [Parameter(Mandatory = $false)][switch] $Force,
        [Parameter(Mandatory = $false)][switch] $SkipValidation,
        [Parameter(Mandatory = $false)][ValidateSet('NoTestRun', 'RunSpecifiedTests', 'RunLocalTests', 'RunAllTestsInOrg')][string] $TestLevel,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string[]] $Tests,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $workItems = @($WorkItemId | Where-Object { $_ })
    if ($workItems.Count -gt 0 -and $StageId) { throw 'Use -WorkItemId or -StageId, not both.' }
    if ($workItems.Count -eq 0 -and -not $StageId) { throw 'Give the work items to promote with -WorkItemId, or a source stage with -StageId.' }
    if ($Tests -and $TestLevel -ne 'RunSpecifiedTests') { throw '-Tests is only used with -TestLevel RunSpecifiedTests.' }
    if ($TestLevel -eq 'RunSpecifiedTests' -and -not $Tests) { throw '-TestLevel RunSpecifiedTests needs the tests to run in -Tests.' }

    if ($TestLevel) { $TestLevel = @('NoTestRun', 'RunSpecifiedTests', 'RunLocalTests', 'RunAllTestsInOrg') | Where-Object { $_ -eq $TestLevel } | Select-Object -First 1 }
    $arguments = @('devops', 'promote', '--target-stage-id', $TargetStageId)
    foreach ($item in @($WorkItemId | Where-Object { $_ })) { $arguments += @('--work-item-id', $item) }
    if ($StageId) { $arguments += @('--stage-id', $StageId) }
    if ($DeployAll) { $arguments += '--deploy-all' }
    if ($Force) { $arguments += '--force' }
    if ($SkipValidation) { $arguments += '--skip-validation' }
    if ($TestLevel) { $arguments += @('--test-level', $TestLevel) }
    foreach ($item in @($Tests | Where-Object { $_ })) { $arguments += @('--tests', $item) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($TargetStageId, 'Promote to the pipeline stage (deploys to its org)')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Complete-SalesforceDevOpsPromotion {
    <#
    .SYNOPSIS
    Deploys work items that were merged outside DevOps Center to a stage.

    .DESCRIPTION
    Runs sf devops promotion complete. Deploys work items that were merged into the pipeline branch outside DevOps Center (externally merged) into the target stage's org and updates the DevOps Center records. It is the "Complete Promotion" action of the DevOps Center page for a stage that is out of sync. Without -WorkItemId it deploys every undeployed work item of the stage; if there are none it does nothing and succeeds. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER TargetStageId
    ID of the out-of-sync stage to deploy to. Passed to sf as --target-stage-id. Required.

    .PARAMETER WorkItemId
    IDs of specific work items to deploy. Each is passed to sf as its own --work-item-id. Leave it out to deploy all the undeployed work items of the stage; use it for the first stage of a pipeline, which has no source stage. Passed to sf as --work-item-id.

    .PARAMETER DeployAll
    Deploy all the metadata in the branch, not only the changes that are not yet in the stage. Adds --deploy-all.

    .PARAMETER TestLevel
    Apex test level of the deployment. Valid values: NoTestRun, RunSpecifiedTests, RunLocalTests, RunAllTestsInOrg. NoTestRun is only for development orgs. Passed to sf as --test-level.

    .PARAMETER Tests
    Apex tests to run with -TestLevel RunSpecifiedTests. Each is passed to sf as its own --tests. Passed to sf as --tests.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Complete-SalesforceDevOpsPromotion -TargetStageId 1QV000000000002 -TargetOrg devops-org -WhatIf
    Preview completing the promotion of a stage.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops promotion complete (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetStageId = --target-stage-id; -WorkItemId = --work-item-id; -DeployAll = --deploy-all; -TestLevel = --test-level; -Tests = --tests; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $TargetStageId,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string[]] $WorkItemId,
        [Parameter(Mandatory = $false)][switch] $DeployAll,
        [Parameter(Mandatory = $false)][ValidateSet('NoTestRun', 'RunSpecifiedTests', 'RunLocalTests', 'RunAllTestsInOrg')][string] $TestLevel,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string[]] $Tests,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($Tests -and $TestLevel -ne 'RunSpecifiedTests') { throw '-Tests is only used with -TestLevel RunSpecifiedTests.' }
    if ($TestLevel -eq 'RunSpecifiedTests' -and -not $Tests) { throw '-TestLevel RunSpecifiedTests needs the tests to run in -Tests.' }

    if ($TestLevel) { $TestLevel = @('NoTestRun', 'RunSpecifiedTests', 'RunLocalTests', 'RunAllTestsInOrg') | Where-Object { $_ -eq $TestLevel } | Select-Object -First 1 }
    $arguments = @('devops', 'promotion', 'complete', '--target-stage-id', $TargetStageId)
    foreach ($item in @($WorkItemId | Where-Object { $_ })) { $arguments += @('--work-item-id', $item) }
    if ($DeployAll) { $arguments += '--deploy-all' }
    if ($TestLevel) { $arguments += @('--test-level', $TestLevel) }
    foreach ($item in @($Tests | Where-Object { $_ })) { $arguments += @('--tests', $item) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($TargetStageId, 'Deploy undeployed work items to the stage org')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Test-SalesforceDevOpsPromotion {
    <#
    .SYNOPSIS
    Checks whether work items can be promoted to a stage.

    .DESCRIPTION
    Runs sf devops promotion validate. Validates the work items for the target stage: it looks for version control and object permission errors before a promotion is tried. It does not deploy anything. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER TargetStageId
    ID of the stage to validate the promotion to. Passed to sf as --target-stage-id. Required.

    .PARAMETER WorkItemId
    IDs of the work items to validate. Each is passed to sf as its own --work-item-id. Passed to sf as --work-item-id. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Test-SalesforceDevOpsPromotion -WorkItemId 1fk000000000001 -TargetStageId 1QV000000000002 -TargetOrg devops-org
    Can this work item be promoted?

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops promotion validate (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetStageId = --target-stage-id; -WorkItemId = --work-item-id; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $TargetStageId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string[]] $WorkItemId,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if (@($WorkItemId | Where-Object { $_ }).Count -eq 0) { throw 'Give at least one -WorkItemId.' }
    $arguments = @('devops', 'promotion', 'validate', '--target-stage-id', $TargetStageId)
    foreach ($item in @($WorkItemId | Where-Object { $_ })) { $arguments += @('--work-item-id', $item) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDevOpsRequestStatus {
    <#
    .SYNOPSIS
    Gets the status of a DevOps Center request.

    .DESCRIPTION
    Runs sf devops request status. Returns the current status of the request with the given token, such as the one Start-SalesforceDevOpsPromotion returns. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

    .PARAMETER RequestToken
    The request token from the promotion result. Passed to sf as --request-token. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceDevOpsRequestStatus -RequestToken $promotion.requestToken -TargetOrg devops-org
    Check on a promotion.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf devops request status (plugin @salesforce/plugin-devops-center)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -RequestToken = --request-token; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-devops-center

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,299}\z')][string] $RequestToken,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('devops', 'request', 'status', '--request-token', $RequestToken)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion
