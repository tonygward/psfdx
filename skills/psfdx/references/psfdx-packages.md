# psfdx-packages command reference

Generated from the commands' own help by `site/Update-ModuleReference.ps1`: do not edit it by hand. The same reference is on the website: <https://psfdx.com/modules/psfdx-packages/>. It is part of the `psfdx` package; see the [installation guide](https://github.com/tonygward/psfdx/blob/main/docs/install.md).

30 commands. Every command also takes the common parameters, such as `-Verbose`.

## Commands

**First-generation packages**: [Convert-SalesforcePackage](#convert-salesforcepackage), [Get-SalesforceFirstGenPackageVersion](#get-salesforcefirstgenpackageversion), [Get-SalesforceFirstGenPackageVersionCreateStatus](#get-salesforcefirstgenpackageversioncreatestatus), [Get-SalesforceFirstGenPackageVersions](#get-salesforcefirstgenpackageversions), [New-SalesforceFirstGenPackageVersion](#new-salesforcefirstgenpackageversion)

**Package management**: [Get-SalesforcePackage](#get-salesforcepackage), [Get-SalesforcePackages](#get-salesforcepackages), [New-SalesforcePackage](#new-salesforcepackage), [Remove-SalesforcePackage](#remove-salesforcepackage), [Update-SalesforcePackage](#update-salesforcepackage)

**Installation and removal from orgs**: [Get-SalesforcePackageInstallStatus](#get-salesforcepackageinstallstatus), [Get-SalesforcePackagesInstalled](#get-salesforcepackagesinstalled), [Get-SalesforcePackageUninstallStatus](#get-salesforcepackageuninstallstatus), [Install-SalesforcePackageVersion](#install-salesforcepackageversion), [Uninstall-SalesforcePackage](#uninstall-salesforcepackage)

**Package versions**: [Get-SalesforcePackageVersion](#get-salesforcepackageversion), [Get-SalesforcePackageVersionAncestry](#get-salesforcepackageversionancestry), [Get-SalesforcePackageVersionCreateRequests](#get-salesforcepackageversioncreaterequests), [Get-SalesforcePackageVersionCreateStatus](#get-salesforcepackageversioncreatestatus), [Get-SalesforcePackageVersionDependencies](#get-salesforcepackageversiondependencies), [Get-SalesforcePackageVersions](#get-salesforcepackageversions), [New-SalesforcePackageVersion](#new-salesforcepackageversion), [Promote-SalesforcePackageVersion](#promote-salesforcepackageversion), [Remove-SalesforcePackageVersion](#remove-salesforcepackageversion), [Retrieve-SalesforcePackageVersion](#retrieve-salesforcepackageversion), [Update-SalesforcePackageVersion](#update-salesforcepackageversion)

**Push upgrades**: [Get-SalesforcePushUpgrade](#get-salesforcepushupgrade), [Get-SalesforcePushUpgrades](#get-salesforcepushupgrades), [New-SalesforcePushUpgrade](#new-salesforcepushupgrade), [Stop-SalesforcePushUpgrade](#stop-salesforcepushupgrade)

## First-generation packages

### Convert-SalesforcePackage

#### Synopsis

Converts a first-generation managed package into a second-generation managed package.

#### Syntax

```powershell
Convert-SalesforcePackage [-Package] <String> [[-DefinitionFile] <String>] [[-InstallationKey] <String>] [-InstallationKeyBypass] [-CodeCoverage] [[-PatchVersion] <String>] [[-SeedMetadata] <String>] [-ExtendedDetails] [[-WaitMinutes] <Int32>] [[-TargetDevHub] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf package convert. The first-generation package must be managed and released (it has a released version). The conversion creates a second-generation package and a first package version in the Dev Hub; it can take a long time, so give -WaitMinutes or follow up with Get-SalesforcePackageVersionCreateStatus. Supports -WhatIf and -Confirm; it does not prompt by default.

#### Parameters

- `-Package` (String, required): ID of the first-generation managed package to convert (starts with 033). Passed to sf as --package. Required.
- `-DefinitionFile` (String): Path to a scratch org definition file used to validate the converted package version. The file must exist. Passed to sf as --definition-file.
- `-InstallationKey` (String): Installation key for the converted package version, a password that subscribers give when they install it. Give -InstallationKey or -InstallationKeyBypass, not both. Passed to sf as --installation-key.
- `-InstallationKeyBypass` (switch): Do not protect the converted package version with an installation key. Adds --installation-key-bypass.
- `-CodeCoverage` (switch): Calculate and store the code coverage of the converted package version. Adds --code-coverage.
- `-PatchVersion` (String): Patch version number to give the converted package version. Passed to sf as --patch-version.
- `-SeedMetadata` (String): Folder of metadata to include in the converted package version, which is not part of the first-generation package. The folder must exist. Passed to sf as --seed-metadata.
- `-ExtendedDetails` (switch): Show extended details of the conversion. Adds --verbose.
- `-WaitMinutes` (Int32): Number of minutes to wait for the conversion to finish. Passed to sf as --wait.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf package convert`

#### Examples

```powershell
PS> Convert-SalesforcePackage -Package 033xx0000000001AAA -InstallationKeyBypass -WaitMinutes 30 -TargetDevHub devhub
```

Convert the package and wait up to 30 minutes.

#### Remarks

- To see the examples, type: "Get-Help Convert-SalesforcePackage -Examples"
- For more information, type: "Get-Help Convert-SalesforcePackage -Detailed"
- For technical information, type: "Get-Help Convert-SalesforcePackage -Full"
- For online help, type: "Get-Help Convert-SalesforcePackage -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceFirstGenPackageVersion

#### Synopsis

Shows the details of a first-generation package version.

#### Syntax

```powershell
Get-SalesforceFirstGenPackageVersion [-PackageVersionId] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf package1 version display. It only reads.

#### Parameters

- `-PackageVersionId` (String, required): ID of the package version (starts with 04t). Passed to sf as --package-version-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf package1 version display`

#### Examples

```powershell
PS> Get-SalesforceFirstGenPackageVersion -PackageVersionId 04txx0000000001AAA -TargetOrg packaging
```

The details of one version.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceFirstGenPackageVersion -Examples"
- For more information, type: "Get-Help Get-SalesforceFirstGenPackageVersion -Detailed"
- For technical information, type: "Get-Help Get-SalesforceFirstGenPackageVersion -Full"
- For online help, type: "Get-Help Get-SalesforceFirstGenPackageVersion -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceFirstGenPackageVersionCreateStatus

#### Synopsis

Shows the status of a first-generation package version upload.

#### Syntax

```powershell
Get-SalesforceFirstGenPackageVersionCreateStatus [-RequestId] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf package1 version create get for the request ID from New-SalesforceFirstGenPackageVersion. It only reads.

#### Parameters

- `-RequestId` (String, required): ID of the upload request. Passed to sf as --request-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf package1 version create get`

#### Examples

```powershell
PS> Get-SalesforceFirstGenPackageVersionCreateStatus -RequestId 0HD000000000001 -TargetOrg packaging
```

The state of the upload.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceFirstGenPackageVersionCreateStatus -Examples"
- For more information, type: "Get-Help Get-SalesforceFirstGenPackageVersionCreateStatus -Detailed"
- For technical information, type: "Get-Help Get-SalesforceFirstGenPackageVersionCreateStatus -Full"
- For online help, type: "Get-Help Get-SalesforceFirstGenPackageVersionCreateStatus -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceFirstGenPackageVersions

#### Synopsis

Lists first-generation package versions.

#### Syntax

```powershell
Get-SalesforceFirstGenPackageVersions [[-PackageId] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf package1 version list and returns one object per version. Without -PackageId it lists the versions of every package in the org. It only reads.

#### Parameters

- `-PackageId` (String): ID of the first-generation package (starts with 033). By default all packages of the org. Passed to sf as --package-id.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf package1 version list`

#### Examples

```powershell
PS> Get-SalesforceFirstGenPackageVersions -TargetOrg packaging | Format-Table
```

Every first-generation version in the org.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceFirstGenPackageVersions -Examples"
- For more information, type: "Get-Help Get-SalesforceFirstGenPackageVersions -Detailed"
- For technical information, type: "Get-Help Get-SalesforceFirstGenPackageVersions -Full"
- For online help, type: "Get-Help Get-SalesforceFirstGenPackageVersions -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceFirstGenPackageVersion

#### Synopsis

Uploads a new version of a first-generation package.

#### Syntax

```powershell
New-SalesforceFirstGenPackageVersion [-PackageId] <String> [-Name] <String> [[-Description] <String>] [[-Version] <String>] [[-InstallationKey] <String>] [-ManagedReleased] [[-PostInstallUrl] <String>] [[-ReleaseNotesUrl] <String>] [[-WaitMinutes] <Int32>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf package1 version create in the packaging org that owns the first-generation package. The upload can take a while: give -WaitMinutes, or follow up with Get-SalesforceFirstGenPackageVersionCreateStatus. For second-generation packages use New-SalesforcePackageVersion. Supports -WhatIf and -Confirm; it does not prompt by default.

#### Parameters

- `-PackageId` (String, required): ID of the first-generation package (starts with 033). Passed to sf as --package-id. Required.
- `-Name` (String, required): Name of the package version. Passed to sf as --name. Required.
- `-Description` (String): Description of the package version. Passed to sf as --description.
- `-Version` (String): Version number of the package version, for example 1.2. Passed to sf as --version.
- `-InstallationKey` (String): Installation key that subscribers give when they install the version. Passed to sf as --installation-key.
- `-ManagedReleased` (switch): Upload the version as managed-released, which cannot be deleted or changed. Without it the version is a beta. Adds --managed-released.
- `-PostInstallUrl` (String): URL of the post-install instructions. Passed to sf as --post-install-url.
- `-ReleaseNotesUrl` (String): URL of the release notes. Passed to sf as --release-notes-url.
- `-WaitMinutes` (Int32): Number of minutes to wait for the upload to finish. Passed to sf as --wait.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf package1 version create`

#### Examples

```powershell
PS> New-SalesforceFirstGenPackageVersion -PackageId 033xx0000000001AAA -Name 'Spring release' -Version 2.1 -WaitMinutes 20 -TargetOrg packaging
```

Upload a beta version and wait.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceFirstGenPackageVersion -Examples"
- For more information, type: "Get-Help New-SalesforceFirstGenPackageVersion -Detailed"
- For technical information, type: "Get-Help New-SalesforceFirstGenPackageVersion -Full"
- For online help, type: "Get-Help New-SalesforceFirstGenPackageVersion -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Package management

### Get-SalesforcePackage

#### Synopsis

Finds one package by name.

#### Syntax

```powershell
Get-SalesforcePackage [-Name] <String> [[-TargetDevHub] <String>] [-ExtendedPackageDetails] [<CommonParameters>]
```

#### Description

Lists the packages with Get-SalesforcePackages and returns the one whose name matches exactly, or nothing.

#### Parameters

- `-Name` (String, required): Exact name of the package. Required.
- `-TargetDevHub` (String): Passed on to Get-SalesforcePackages -TargetDevHub.
- `-ExtendedPackageDetails` (switch): Passed on to Get-SalesforcePackages -ExtendedPackageDetails.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Get-SalesforcePackage -Name MyPackage -TargetDevHub devhub
```

The package record.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePackage -Examples"
- For more information, type: "Get-Help Get-SalesforcePackage -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePackage -Full"
- For online help, type: "Get-Help Get-SalesforcePackage -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforcePackages

#### Synopsis

Lists the packages in a Dev Hub.

#### Syntax

```powershell
Get-SalesforcePackages [[-TargetDevHub] <String>] [-ExtendedPackageDetails] [<CommonParameters>]
```

#### Description

Runs sf package list and returns one object per package.

#### Parameters

- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.
- `-ExtendedPackageDetails` (switch): Display extended package detail. Adds --verbose.

#### Salesforce CLI

- `sf package list`

#### Examples

```powershell
PS> Get-SalesforcePackages -TargetDevHub devhub
```

Every package in the Dev Hub.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePackages -Examples"
- For more information, type: "Get-Help Get-SalesforcePackages -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePackages -Full"
- For online help, type: "Get-Help Get-SalesforcePackages -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforcePackage

#### Synopsis

Creates a package in a Dev Hub.

#### Syntax

```powershell
New-SalesforcePackage [-Name] <String> [[-PackageType] <String>] [-IsOrgDependent] [[-Path] <String>] [[-Description] <String>] [[-ErrorNotificationUsername] <String>] [-NoNamespace] [[-TargetDevHub] <String>] [<CommonParameters>]
```

#### Description

Runs sf package create. The package type is unlocked or managed.

#### Parameters

- `-Name` (String, required): Name of the package to create. Passed to sf as --name. Required.
- `-PackageType` (String): Type of package. Passed to sf as --package-type. Default: "Unlocked". Valid values: Managed, Unlocked.
- `-IsOrgDependent` (switch): Depends on unpackaged metadata in the installation org; applies to unlocked packages only. Adds --org-dependent.
- `-Path` (String): Path to directory that contains the contents of the package. Passed to sf as --path. Default: "force-app/main/default".
- `-Description` (String): Description of the package. Passed to sf as --description.
- `-ErrorNotificationUsername` (String): Active Dev Hub user designated to receive email notifications for package errors. Passed to sf as --error-notification-username.
- `-NoNamespace` (switch): Create the package with no namespace; available only for unlocked packages. Adds --no-namespace.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

#### Salesforce CLI

- `sf package create`

#### Examples

```powershell
PS> New-SalesforcePackage -Name MyPackage -PackageType Unlocked -Path force-app -TargetDevHub devhub
```

An unlocked package for the force-app folder.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforcePackage -Examples"
- For more information, type: "Get-Help New-SalesforcePackage -Detailed"
- For technical information, type: "Get-Help New-SalesforcePackage -Full"
- For online help, type: "Get-Help New-SalesforcePackage -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforcePackage

#### Synopsis

Deletes a package.

#### Syntax

```powershell
Remove-SalesforcePackage [-Name] <String> [[-TargetDevHub] <String>] [-NoPrompt] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf package delete. Asks for confirmation and supports -WhatIf.

#### Parameters

- `-Name` (String, required): ID (starts with 0Ho) or alias of the package to delete. Passed to sf as --package. Required.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.
- `-NoPrompt` (switch): Don't prompt before deleting the package. Adds --no-prompt.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf package delete`

#### Examples

```powershell
PS> Remove-SalesforcePackage -Name MyPackage -TargetDevHub devhub -WhatIf
```

Preview the delete.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforcePackage -Examples"
- For more information, type: "Get-Help Remove-SalesforcePackage -Detailed"
- For technical information, type: "Get-Help Remove-SalesforcePackage -Full"
- For online help, type: "Get-Help Remove-SalesforcePackage -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Update-SalesforcePackage

#### Synopsis

Changes the details of a package in the Dev Hub.

#### Syntax

```powershell
Update-SalesforcePackage [-Package] <String> [[-Name] <String>] [[-Description] <String>] [[-ErrorNotificationUsername] <String>] [-EnableAppAnalytics] [[-RecommendedVersionId] <String>] [-SkipAncestorCheck] [[-TargetDevHub] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf package update. Only the properties you give are changed. Supports -WhatIf and -Confirm; it does not prompt by default.

#### Parameters

- `-Package` (String, required): ID (starts with 0Ho) or alias of the package to update. Passed to sf as --package. Required.
- `-Name` (String): New name of the package. Passed to sf as --name.
- `-Description` (String): New description of the package. Passed to sf as --description.
- `-ErrorNotificationUsername` (String): User name of the person who gets emails when a package error happens, such as a failed subscriber install. Passed to sf as --error-notification-username.
- `-EnableAppAnalytics` (switch): Turn on AppExchange App Analytics for the managed package. Adds --enable-app-analytics.
- `-RecommendedVersionId` (String): ID of the package version to recommend to subscribers, starting with 04t. Passed to sf as --recommended-version-id.
- `-SkipAncestorCheck` (switch): Do not check that the recommended version has the right ancestor. Adds --skip-ancestor-check.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf package update`

#### Examples

```powershell
PS> Update-SalesforcePackage -Package MyPkg -Description 'Core features' -TargetDevHub devhub -WhatIf
```

Preview the change without making it.

#### Remarks

- To see the examples, type: "Get-Help Update-SalesforcePackage -Examples"
- For more information, type: "Get-Help Update-SalesforcePackage -Detailed"
- For technical information, type: "Get-Help Update-SalesforcePackage -Full"
- For online help, type: "Get-Help Update-SalesforcePackage -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Installation and removal from orgs

### Get-SalesforcePackageInstallStatus

#### Synopsis

Gets the status of a package install request (sf package install report).

#### Syntax

```powershell
Get-SalesforcePackageInstallStatus [-RequestId] <String> [-ThrowOnFailure] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Pass the install request ID: the Id (0Hf...) of the object that Install-SalesforcePackageVersion returned when run with -AsObject. The result has Status (IN_PROGRESS, SUCCESS, ERROR or UNKNOWN), Completed, Succeeded, the SubscriberPackageVersionKey (04t) and Errors. A job still running returns Completed = $false. A failed install is returned as a status with its Errors; add -ThrowOnFailure to make it throw PsfdxPackageJobFailed after the object is written. The report is read from the org the package is being installed into (-TargetOrg).

#### Parameters

- `-RequestId` (String, required): ID of the package install request you want to check; starts with 0Hf. Passed to sf as --request-id. Required.
- `-ThrowOnFailure` (switch): Throw an error (id PsfdxPackageJobFailed) when the installation failed, instead of returning it with Status ERROR. Meant for CI.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf package install report`

#### Examples

```powershell
PS> $install = Install-SalesforcePackageVersion -PackageVersionId 04t000000000001 -WaitMinutes 0 -NoPrompt -AsObject -TargetOrg myorg; Get-SalesforcePackageInstallStatus -RequestId $install.Id -TargetOrg myorg
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePackageInstallStatus -Examples"
- For more information, type: "Get-Help Get-SalesforcePackageInstallStatus -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePackageInstallStatus -Full"
- For online help, type: "Get-Help Get-SalesforcePackageInstallStatus -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforcePackagesInstalled

#### Synopsis

Lists the packages installed in an org.

#### Syntax

```powershell
Get-SalesforcePackagesInstalled [[-TargetOrg] <String>] [[-ApiVersion] <String>] [<CommonParameters>]
```

#### Description

Runs sf package installed list and returns one object per installed package version.

#### Parameters

- `-TargetOrg` (String): Username or alias of the org. If omitted, the Salesforce CLI uses the default target org. Passed to sf as --target-org.
- `-ApiVersion` (String): REST API version to use for the request, for example 62.0. Passed as --api-version; this is the one cmdlet that exposes it.

#### Salesforce CLI

- `sf package installed list`

#### Examples

```powershell
PS> Get-SalesforcePackagesInstalled -TargetOrg dev1
```

What is installed.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePackagesInstalled -Examples"
- For more information, type: "Get-Help Get-SalesforcePackagesInstalled -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePackagesInstalled -Full"
- For online help, type: "Get-Help Get-SalesforcePackagesInstalled -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforcePackageUninstallStatus

#### Synopsis

Shows the status of a package uninstall request.

#### Syntax

```powershell
Get-SalesforcePackageUninstallStatus [-RequestId] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf package uninstall report. The request ID comes from Uninstall-SalesforcePackage when it returned without waiting. It only reads.

#### Parameters

- `-RequestId` (String, required): ID of the uninstall request, from Uninstall-SalesforcePackage. Passed to sf as --request-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf package uninstall report`

#### Examples

```powershell
PS> Get-SalesforcePackageUninstallStatus -RequestId 06yxx0000000001AAA -TargetOrg dev1
```

The state of the uninstall.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePackageUninstallStatus -Examples"
- For more information, type: "Get-Help Get-SalesforcePackageUninstallStatus -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePackageUninstallStatus -Full"
- For online help, type: "Get-Help Get-SalesforcePackageUninstallStatus -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Install-SalesforcePackageVersion

#### Synopsis

Installs a package version in an org.

#### Syntax

```powershell
Install-SalesforcePackageVersion [-PackageVersionId] <String> [[-TargetOrg] <String>] [-NoPrompt] [[-WaitMinutes] <Int32>] [[-SecurityType] <String>] [-AsObject] [[-ApexCompile] <String>] [[-InstallationKey] <String>] [[-UpgradeType] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf package install for a version ID (04t...). With -AsObject the result comes back as an object whose Id is the install request ID for Get-SalesforcePackageInstallStatus; without it the CLI's text is returned. Supports -WhatIf and -Confirm (no prompt by default).

#### Parameters

- `-PackageVersionId` (String, required): ID (starts with 04t) or alias of the package version to install. Passed to sf as --package. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-NoPrompt` (switch): Don't prompt for confirmation. Adds --no-prompt.
- `-WaitMinutes` (Int32): Maximum number of minutes to wait for the Subscriber Package Version ID to become available in the target org before canceling the install request. Passed to sf as --publish-wait. Default: 10.
- `-SecurityType` (String): Security access type for the installed package. Available options are AdminsOnly and AllUsers. Passed to sf as --security-type. Default: AdminsOnly. Valid values: AllUsers, AdminsOnly.
- `-AsObject` (switch): Return the install request as an object (adds --json) instead of the CLI's text. Its Id, which starts with 0Hf, is the request ID for Get-SalesforcePackageInstallStatus.
- `-ApexCompile` (String): Compile all the Apex in the org and the package, or only the Apex in the package, after the install. Passed to sf as --apex-compile. Valid values: all, package. The CLI default is all.
- `-InstallationKey` (String): Installation key of the package version, for a version that is protected by one. Passed to sf as --installation-key.
- `-UpgradeType` (String): What happens to the components that an upgrade removes. Passed to sf as --upgrade-type. Valid values: DeprecateOnly, Mixed, Delete. The CLI default is Mixed. Only used for an upgrade of an unlocked package.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf package install`

#### Examples

```powershell
PS> Install-SalesforcePackageVersion -PackageVersionId 04t000000000001AAA -TargetOrg dev1 -WhatIf
```

Preview the install.

#### Remarks

- To see the examples, type: "Get-Help Install-SalesforcePackageVersion -Examples"
- For more information, type: "Get-Help Install-SalesforcePackageVersion -Detailed"
- For technical information, type: "Get-Help Install-SalesforcePackageVersion -Full"
- For online help, type: "Get-Help Install-SalesforcePackageVersion -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Uninstall-SalesforcePackage

#### Synopsis

Uninstalls a second-generation package from an org.

#### Syntax

```powershell
Uninstall-SalesforcePackage [-Package] <String> [[-WaitMinutes] <Int32>] [-NoPrompt] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf package uninstall. The package version and its components are removed from the org, which can delete data stored in the package's custom objects. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. Without -WaitMinutes the request is made and returned; follow it with Get-SalesforcePackageUninstallStatus.

#### Parameters

- `-Package` (String, required): ID (starts with 04t) or alias of the package version to uninstall. Passed to sf as --package. Required.
- `-WaitMinutes` (Int32): Number of minutes to wait for the uninstall to finish. Passed to sf as --wait.
- `-NoPrompt` (switch): Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf package uninstall`

#### Examples

```powershell
PS> Uninstall-SalesforcePackage -Package 04txx0000000001AAA -WaitMinutes 10 -TargetOrg dev1 -WhatIf
```

Preview the uninstall without starting it.

#### Remarks

- To see the examples, type: "Get-Help Uninstall-SalesforcePackage -Examples"
- For more information, type: "Get-Help Uninstall-SalesforcePackage -Detailed"
- For technical information, type: "Get-Help Uninstall-SalesforcePackage -Full"
- For online help, type: "Get-Help Uninstall-SalesforcePackage -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Package versions

### Get-SalesforcePackageVersion

#### Synopsis

Shows the details of one package version.

#### Syntax

```powershell
Get-SalesforcePackageVersion [-PackageVersionId] <String> [-ExtendedDetails] [[-TargetDevHub] <String>] [<CommonParameters>]
```

#### Description

Runs sf package version report and returns the version's details (version number, branch, tag, code coverage, validation state, ancestor and more). It only reads. Use Get-SalesforcePackageVersions to list versions.

#### Parameters

- `-PackageVersionId` (String, required): ID (starts with 04t) or alias of the package version. Passed to sf as --package. Required.
- `-ExtendedDetails` (switch): Show extended details, such as the package version's ancestry. Adds --verbose.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

#### Salesforce CLI

- `sf package version report`

#### Examples

```powershell
PS> Get-SalesforcePackageVersion -PackageVersionId 04txx0000000001AAA -TargetDevHub devhub
```

The details of one version.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePackageVersion -Examples"
- For more information, type: "Get-Help Get-SalesforcePackageVersion -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePackageVersion -Full"
- For online help, type: "Get-Help Get-SalesforcePackageVersion -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforcePackageVersionAncestry

#### Synopsis

Shows the ancestry tree of a second-generation managed package.

#### Syntax

```powershell
Get-SalesforcePackageVersionAncestry [-Package] <String> [-DotCode] [-ExtendedDetails] [[-TargetDevHub] <String>] [<CommonParameters>]
```

#### Description

Runs sf package version displayancestry. The ancestry shows which version each version builds on. It works for second-generation managed packages. With -DotCode the result is DOT graph code that you can draw with Graphviz.

#### Parameters

- `-Package` (String, required): ID (starts with 0Ho) or alias of the package, or ID (starts with 04t) or alias of a package version. Passed to sf as --package. Required.
- `-DotCode` (switch): Return the ancestry as DOT code for Graphviz. Adds --dot-code.
- `-ExtendedDetails` (switch): Show extended details of each version, such as its ID. Adds --verbose.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

#### Salesforce CLI

- `sf package version displayancestry`

#### Examples

```powershell
PS> Get-SalesforcePackageVersionAncestry -Package MyManagedPkg -TargetDevHub devhub
```

The ancestry tree of the package.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePackageVersionAncestry -Examples"
- For more information, type: "Get-Help Get-SalesforcePackageVersionAncestry -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePackageVersionAncestry -Full"
- For online help, type: "Get-Help Get-SalesforcePackageVersionAncestry -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforcePackageVersionCreateRequests

#### Synopsis

Lists the package version creation requests of a Dev Hub.

#### Syntax

```powershell
Get-SalesforcePackageVersionCreateRequests [[-CreatedLastDays] <Int32>] [-ConversionsOnly] [[-Status] <String>] [-ExtendedDetails] [[-TargetDevHub] <String>] [<CommonParameters>]
```

#### Description

Runs sf package version create list and returns one object per request (ID, status, package, version, branch, created date). Use Get-SalesforcePackageVersionCreateStatus for one request.

#### Parameters

- `-CreatedLastDays` (Int32): Only requests created in the last this many days. 0 means today. Passed to sf as --created-last-days.
- `-ConversionsOnly` (switch): Only requests that convert a first-generation package. Adds --show-conversions-only.
- `-Status` (String): Only requests with this status. Valid values: Queued, InProgress, Success, Error. Passed to sf as --status.
- `-ExtendedDetails` (switch): Show extended details of each request. Adds --verbose.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

#### Salesforce CLI

- `sf package version create list`

#### Examples

```powershell
PS> Get-SalesforcePackageVersionCreateRequests -Status Error -CreatedLastDays 7 -TargetDevHub devhub
```

Version creations that failed this week.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePackageVersionCreateRequests -Examples"
- For more information, type: "Get-Help Get-SalesforcePackageVersionCreateRequests -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePackageVersionCreateRequests -Full"
- For online help, type: "Get-Help Get-SalesforcePackageVersionCreateRequests -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforcePackageVersionCreateStatus

#### Synopsis

Gets the status of a package version create request (sf package version create report).

#### Syntax

```powershell
Get-SalesforcePackageVersionCreateStatus [-RequestId] <String> [-ThrowOnFailure] [[-TargetDevHub] <String>] [<CommonParameters>]
```

#### Description

Pass the create request ID: the Id (08c...) of the object that New-SalesforcePackageVersion returned. It is asked of the Dev Hub that owns the package (-TargetDevHub). The result has Status, Completed and Succeeded, the IDs (RequestId, PackageId, PackageVersionId, SubscriberPackageVersionId, the 04t ID to install) and Errors, a list of messages when the job failed. A job still queued or running returns Completed = $false. A failed job is returned as a status (Status = Error) rather than thrown, so a script can read its Errors; add -ThrowOnFailure to make a failed job throw PsfdxPackageJobFailed after the object is written, for CI.

#### Parameters

- `-RequestId` (String, required): ID (starts with 08c) of the package version creation request you want to display. Passed to sf as --package-create-request-id. Required.
- `-ThrowOnFailure` (switch): Throw an error (id PsfdxPackageJobFailed) when the version creation failed, instead of returning it with its status. Meant for CI.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

#### Salesforce CLI

- `sf package version create report`

#### Examples

```powershell
PS> $create = New-SalesforcePackageVersion -PackageName MyPkg -TargetDevHub devhub; Get-SalesforcePackageVersionCreateStatus -RequestId $create.Id -TargetDevHub devhub
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePackageVersionCreateStatus -Examples"
- For more information, type: "Get-Help Get-SalesforcePackageVersionCreateStatus -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePackageVersionCreateStatus -Full"
- For online help, type: "Get-Help Get-SalesforcePackageVersionCreateStatus -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforcePackageVersionDependencies

#### Synopsis

Shows the dependency graph of an unlocked or second-generation managed package version.

#### Syntax

```powershell
Get-SalesforcePackageVersionDependencies [-PackageVersionId] <String> [[-EdgeDirection] <String>] [[-InstallationKey] <String>] [-ExtendedDetails] [[-TargetDevHub] <String>] [<CommonParameters>]
```

#### Description

Runs sf package version displaydependencies. It lists the package versions that the version depends on. The package must have the dependencies set in its project file.

#### Parameters

- `-PackageVersionId` (String, required): ID (starts with 04t) or alias of the package version. Passed to sf as --package. Required.
- `-EdgeDirection` (String): Direction of the graph edges. Valid values: root-first, root-last. The CLI default is root-first. Passed to sf as --edge-direction.
- `-InstallationKey` (String): Installation key of the package version, if it has one. Passed to sf as --installation-key.
- `-ExtendedDetails` (switch): Show extended details of each dependency. Adds --verbose.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

#### Salesforce CLI

- `sf package version displaydependencies`

#### Examples

```powershell
PS> Get-SalesforcePackageVersionDependencies -PackageVersionId 04txx0000000001AAA -TargetDevHub devhub
```

What the version depends on.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePackageVersionDependencies -Examples"
- For more information, type: "Get-Help Get-SalesforcePackageVersionDependencies -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePackageVersionDependencies -Full"
- For online help, type: "Get-Help Get-SalesforcePackageVersionDependencies -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforcePackageVersions

#### Synopsis

Lists package versions in a Dev Hub.

#### Syntax

```powershell
Get-SalesforcePackageVersions [[-PackageId] <String>] [[-PackageName] <String>] [-Released] [-Concise] [-ExtendedDetails] [-ConversionsOnly] [[-Branch] <String>] [[-CreatedLastDays] <Int32>] [[-ModifiedLastDays] <Int32>] [[-OrderBy] <String>] [[-TargetDevHub] <String>] [<CommonParameters>]
```

#### Description

Runs sf package version list, for one package (by -PackageId or -PackageName) or for all. Pipe the result to Remove-SalesforcePackageVersion or Promote-SalesforcePackageVersion.

#### Parameters

- `-PackageId` (String): Comma-delimited list of packages (aliases or 0Ho IDs) to list. Passed to sf as --packages.
- `-PackageName` (String): Name of the package. psfdx finds its ID with Get-SalesforcePackage and passes it as --packages. Use instead of -PackageId.
- `-Released` (switch): Display released versions only (IsReleased=true). Adds --released.
- `-Concise` (switch): Display limited package version details. Adds --concise.
- `-ExtendedDetails` (switch): Display extended package version details. Adds --verbose.
- `-ConversionsOnly` (switch): Filter the list output to display only converted package version. Adds --show-conversions-only.
- `-Branch` (String): Branch in your source control system used to filter the results; only package versions based on the specified branch are listed. Passed to sf as --branch.
- `-CreatedLastDays` (Int32): Only versions created in the last this many days. 0 means today. Passed to sf as --created-last-days.
- `-ModifiedLastDays` (Int32): Only versions modified in the last this many days. 0 means today. Passed to sf as --modified-last-days.
- `-OrderBy` (String): Package version fields to order the list by, separated by commas, for example PatchVersion,MajorVersion. Passed to sf as --order-by.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

#### Salesforce CLI

- `sf package version list`

#### Examples

```powershell
PS> Get-SalesforcePackageVersions -PackageName MyPackage -Released -TargetDevHub devhub
```

Released versions of one package.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePackageVersions -Examples"
- For more information, type: "Get-Help Get-SalesforcePackageVersions -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePackageVersions -Full"
- For online help, type: "Get-Help Get-SalesforcePackageVersions -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforcePackageVersion

#### Synopsis

Creates a package version.

#### Syntax

```powershell
New-SalesforcePackageVersion [[-PackageId] <String>] [[-PackageName] <String>] [[-Name] <String>] [[-Description] <String>] [[-Tag] <String>] [[-InstallationKey] <String>] [-InstallationKeyBypass] [-CodeCoverage] [-SkipValidation] [[-WaitMinutes] <Int32>] [[-ScratchOrgDefinitionFile] <String>] [[-Path] <String>] [[-Branch] <String>] [[-VersionNumber] <String>] [[-Language] <String>] [[-PostInstallScript] <String>] [[-UninstallScript] <String>] [[-PostInstallUrl] <String>] [[-ReleaseNotesUrl] <String>] [-SkipAncestorCheck] [-AsyncValidation] [-GeneratePackageZip] [-ExtendedDetails] [[-TargetDevHub] <String>] [<CommonParameters>]
```

#### Description

Runs sf package version create. Without -WaitMinutes the request is queued and its ID (starts with 08c) is returned for Get-SalesforcePackageVersionCreateStatus.

#### Parameters

- `-PackageId` (String): ID (starts with 0Ho) or alias of the package to create a version of. Passed to sf as --package.
- `-PackageName` (String): Name of the package. psfdx finds its ID with Get-SalesforcePackage and passes it as --package. Use instead of -PackageId.
- `-Name` (String): Name of the package version to be created; overrides the sfdx-project.json value. Passed to sf as --version-name.
- `-Description` (String): Description of the package version to be created; overrides the sfdx-project.json value. Passed to sf as --version-description.
- `-Tag` (String): Package version's tag. Passed to sf as --tag.
- `-InstallationKey` (String): Installation key for key-protected package. (either --installation-key or --installation-key-bypass is required).
- `-InstallationKeyBypass` (switch): Bypass the installation key requirement. (either --installation-key or --installation-key-bypass is required).
- `-CodeCoverage` (switch): Calculate and store the code coverage percentage by running the packaged Apex tests included in this package version. Adds --code-coverage.
- `-SkipValidation` (switch): Skip validation during package version creation; you can't promote unvalidated package versions. Adds --skip-validation.
- `-WaitMinutes` (Int32): Number of minutes to wait for the package version to be created. Passed to sf as --wait.
- `-ScratchOrgDefinitionFile` (String): Path to a definition file similar to scratch org definition file that contains the list of features and org preferences that the metadata of the package version depends on. Passed to sf as --definition-file. Default: "config/project-scratch-def.json".
- `-Path` (String): Path to the directory that contains the contents of the package version, as an alternative to -PackageId or -PackageName. Passed to sf as --path. The directory must exist.
- `-Branch` (String): Name of the branch in your source control system that the package version is created from. Passed to sf as --branch.
- `-VersionNumber` (String): Version number of the package version, for example 1.2.0.NEXT. Overrides the sfdx-project.json value. Passed to sf as --version-number.
- `-Language` (String): Language of the package version's metadata, as a language code such as en_US. Passed to sf as --language.
- `-PostInstallScript` (String): Name of the Apex class that runs after the package is installed (managed packages only). Passed to sf as --post-install-script.
- `-UninstallScript` (String): Name of the Apex class that runs when the package is uninstalled (managed packages only). Passed to sf as --uninstall-script.
- `-PostInstallUrl` (String): URL of the post-install instructions. Passed to sf as --post-install-url.
- `-ReleaseNotesUrl` (String): URL of the release notes. Passed to sf as --releasenotes-url.
- `-SkipAncestorCheck` (switch): Do not check that the new version has the right ancestor. Adds --skip-ancestor-check.
- `-AsyncValidation` (switch): Return the version as soon as it is created and run the validation, including the Apex tests, in the background. Adds --async-validation.
- `-GeneratePackageZip` (switch): Also create a zip file of the package contents and keep it, for managed package versions. Adds --generate-pkg-zip.
- `-ExtendedDetails` (switch): Show extended details of the version creation. Adds --verbose.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

#### Salesforce CLI

- `sf package version create`

#### Examples

```powershell
PS> New-SalesforcePackageVersion -PackageName MyPackage -InstallationKeyBypass -WaitMinutes 30 -TargetDevHub devhub
```

Create a version and wait.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforcePackageVersion -Examples"
- For more information, type: "Get-Help New-SalesforcePackageVersion -Detailed"
- For technical information, type: "Get-Help New-SalesforcePackageVersion -Full"
- For online help, type: "Get-Help New-SalesforcePackageVersion -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Promote-SalesforcePackageVersion

#### Synopsis

Promotes a package version to released (sf package version promote).

#### Syntax

```powershell
Promote-SalesforcePackageVersion [-PackageVersionId] <String> [[-TargetDevHub] <String>] [-NoPrompt] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Promotion cannot be undone: a released version can no longer be deleted. The cmdlet asks for confirmation and supports -WhatIf. -NoPrompt means you have already decided (as it does for the CLI), so it skips the confirmation and keeps existing unattended scripts working; -WhatIf still makes no call. -PackageVersionId can come from the pipeline, through the SubscriberPackageVersionId (04t) of a version from Get-SalesforcePackageVersions.

#### Parameters

- `-PackageVersionId` (String, required): ID (starts with 04t) or alias of the package version to promote. Passed to sf as --package. Required. Alias: SubscriberPackageVersionId. Accepts input from the pipeline by property name.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.
- `-NoPrompt` (switch): Don't prompt to confirm setting the package version as released. Adds --no-prompt.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf package version promote`

#### Examples

```powershell
PS> Get-SalesforcePackageVersions -PackageName MyPkg | Select-Object -First 1 | Promote-SalesforcePackageVersion -WhatIf
```

#### Remarks

- To see the examples, type: "Get-Help Promote-SalesforcePackageVersion -Examples"
- For more information, type: "Get-Help Promote-SalesforcePackageVersion -Detailed"
- For technical information, type: "Get-Help Promote-SalesforcePackageVersion -Full"
- For online help, type: "Get-Help Promote-SalesforcePackageVersion -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforcePackageVersion

#### Synopsis

Deletes a package version (sf package version delete).

#### Syntax

```powershell
Remove-SalesforcePackageVersion [-PackageVersionId] <String> [[-TargetDevHub] <String>] [-NoPrompt] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

-PackageVersionId can come from the pipeline: a version from Get-SalesforcePackageVersions is used through its SubscriberPackageVersionId (04t). Each version is confirmed on its own, so -WhatIf previews every delete.

#### Parameters

- `-PackageVersionId` (String, required): ID (starts with 04t) or alias of the package version to delete. Passed to sf as --package. Required. Alias: SubscriberPackageVersionId. Accepts input from the pipeline by property name.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.
- `-NoPrompt` (switch): Don't prompt before deleting the package version. Adds --no-prompt.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf package version delete`

#### Examples

```powershell
PS> Get-SalesforcePackageVersions -PackageName MyPkg | Where-Object { -not $_.IsReleased } | Remove-SalesforcePackageVersion -WhatIf
```

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforcePackageVersion -Examples"
- For more information, type: "Get-Help Remove-SalesforcePackageVersion -Detailed"
- For technical information, type: "Get-Help Remove-SalesforcePackageVersion -Full"
- For online help, type: "Get-Help Remove-SalesforcePackageVersion -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Retrieve-SalesforcePackageVersion

#### Synopsis

Downloads the metadata of a package version into a folder.

#### Syntax

```powershell
Retrieve-SalesforcePackageVersion [-PackageVersionId] <String> [[-OutputDir] <String>] [[-TargetDevHub] <String>] [<CommonParameters>]
```

#### Description

Runs sf package version retrieve. It works only for second-generation managed package versions and unlocked package versions. The metadata is written under -OutputDir.

#### Parameters

- `-PackageVersionId` (String, required): ID (starts with 04t) or alias of the package version to retrieve. Passed to sf as --package. Required.
- `-OutputDir` (String): Folder to write the metadata to. By default the CLI uses a temporary folder and reports it. Passed to sf as --output-dir.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

#### Salesforce CLI

- `sf package version retrieve`

#### Examples

```powershell
PS> Retrieve-SalesforcePackageVersion -PackageVersionId 04txx0000000001AAA -OutputDir .\pkg-source -TargetDevHub devhub
```

Download the version's metadata.

#### Remarks

- To see the examples, type: "Get-Help Retrieve-SalesforcePackageVersion -Examples"
- For more information, type: "Get-Help Retrieve-SalesforcePackageVersion -Detailed"
- For technical information, type: "Get-Help Retrieve-SalesforcePackageVersion -Full"
- For online help, type: "Get-Help Retrieve-SalesforcePackageVersion -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Update-SalesforcePackageVersion

#### Synopsis

Changes the details of a package version.

#### Syntax

```powershell
Update-SalesforcePackageVersion [-PackageVersionId] <String> [[-Branch] <String>] [[-InstallationKey] <String>] [[-Tag] <String>] [[-Description] <String>] [[-Name] <String>] [[-TargetDevHub] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf package version update. Only the properties you give are changed. A released version can change only some of them. Supports -WhatIf and -Confirm; it does not prompt by default.

#### Parameters

- `-PackageVersionId` (String, required): ID (starts with 04t) or alias of the package version to update. Passed to sf as --package. Required.
- `-Branch` (String): New branch of the package version. Passed to sf as --branch.
- `-InstallationKey` (String): New installation key, a password that subscribers give when they install the version. Passed to sf as --installation-key.
- `-Tag` (String): New tag of the package version. Passed to sf as --tag.
- `-Description` (String): New description of the package version. Passed to sf as --version-description.
- `-Name` (String): New name of the package version. Passed to sf as --version-name.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf package version update`

#### Examples

```powershell
PS> Update-SalesforcePackageVersion -PackageVersionId 04txx0000000001AAA -Tag release-1 -TargetDevHub devhub
```

Tag a version.

#### Remarks

- To see the examples, type: "Get-Help Update-SalesforcePackageVersion -Examples"
- For more information, type: "Get-Help Update-SalesforcePackageVersion -Detailed"
- For technical information, type: "Get-Help Update-SalesforcePackageVersion -Full"
- For online help, type: "Get-Help Update-SalesforcePackageVersion -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Push upgrades

### Get-SalesforcePushUpgrade

#### Synopsis

Shows the status of one push upgrade request.

#### Syntax

```powershell
Get-SalesforcePushUpgrade [-PushRequestId] <String> [[-TargetDevHub] <String>] [<CommonParameters>]
```

#### Description

Runs sf package push-upgrade report for the request ID that New-SalesforcePushUpgrade returned. It only reads.

#### Parameters

- `-PushRequestId` (String, required): ID of the push upgrade request (starts with 0DV). Passed to sf as --push-request-id. Required.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

#### Salesforce CLI

- `sf package push-upgrade report`

#### Examples

```powershell
PS> Get-SalesforcePushUpgrade -PushRequestId 0DVxx0000000001AAA -TargetDevHub devhub
```

The state of one push upgrade.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePushUpgrade -Examples"
- For more information, type: "Get-Help Get-SalesforcePushUpgrade -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePushUpgrade -Full"
- For online help, type: "Get-Help Get-SalesforcePushUpgrade -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforcePushUpgrades

#### Synopsis

Lists the push upgrade requests of a package.

#### Syntax

```powershell
Get-SalesforcePushUpgrades [-Package] <String> [[-ScheduledLastDays] <Int32>] [-ShowMigrationsOnly] [[-Status] <String>] [[-TargetDevHub] <String>] [<CommonParameters>]
```

#### Description

Runs sf package push-upgrade list and returns one object per request (ID, status, package version, scheduled start and end). It only reads.

#### Parameters

- `-Package` (String, required): ID (starts with 0Ho) or alias of the package. Passed to sf as --package. Required.
- `-ScheduledLastDays` (Int32): Only requests scheduled in the last this many days. Passed to sf as --scheduled-last-days.
- `-ShowMigrationsOnly` (switch): Only requests that migrate subscribers to a second-generation package. Adds --show-push-migrations-only.
- `-Status` (String): Only requests with this status. Valid values: Created, Cancelled, Pending, In Progress, Failed, Succeeded. Passed to sf as --status.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

#### Salesforce CLI

- `sf package push-upgrade list`

#### Examples

```powershell
PS> Get-SalesforcePushUpgrades -Package MyManagedPkg -Status Pending -TargetDevHub devhub
```

Push upgrades that have not started.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePushUpgrades -Examples"
- For more information, type: "Get-Help Get-SalesforcePushUpgrades -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePushUpgrades -Full"
- For online help, type: "Get-Help Get-SalesforcePushUpgrades -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforcePushUpgrade

#### Synopsis

Schedules a push upgrade of a managed package version to subscriber orgs.

#### Syntax

```powershell
New-SalesforcePushUpgrade [-Package] <String> [[-OrgList] <String[]>] [[-OrgFile] <String>] [[-StartTime] <DateTime>] [-MigrateTo2gp] [[-TargetDevHub] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf package push-upgrade schedule. A push upgrade installs a package version in subscriber orgs without their admins starting it. It cannot be undone once it starts, though a request that has not started can be stopped with Stop-SalesforcePushUpgrade. Give the subscriber orgs as -OrgList or -OrgFile. Asks for confirmation and supports -WhatIf.

#### Parameters

- `-Package` (String, required): ID (starts with 04t) or alias of the package version to push. Passed to sf as --package. Required.
- `-OrgList` (String[]): IDs of the subscriber orgs to upgrade (start with 00D). Joined with commas. Passed to sf as --org-list.
- `-OrgFile` (String): Path of a CSV file that lists the subscriber org IDs, one per line. The file must exist. Passed to sf as --org-file.
- `-StartTime` (DateTime): When to start the push upgrade, as a date and time. It is sent in UTC (a time without a time zone is read as local time). By default the upgrade starts as soon as possible. Passed to sf as --start-time.
- `-MigrateTo2gp` (switch): Migrate the subscriber orgs from a first-generation to a second-generation package. Adds --migrate-to-2gp.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf package push-upgrade schedule`

#### Examples

```powershell
PS> New-SalesforcePushUpgrade -Package 04txx0000000001AAA -OrgList 00Dxx0000000001, 00Dxx0000000002 -StartTime '2026-12-01 02:00' -TargetDevHub devhub -WhatIf
```

Preview a scheduled push upgrade.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforcePushUpgrade -Examples"
- For more information, type: "Get-Help New-SalesforcePushUpgrade -Detailed"
- For technical information, type: "Get-Help New-SalesforcePushUpgrade -Full"
- For online help, type: "Get-Help New-SalesforcePushUpgrade -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Stop-SalesforcePushUpgrade

#### Synopsis

Cancels a scheduled push upgrade.

#### Syntax

```powershell
Stop-SalesforcePushUpgrade [-PushRequestId] <String> [-NoPrompt] [[-TargetDevHub] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf package push-upgrade abort. Only a request with the status Created or Pending can be aborted; one that has started cannot. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question.

#### Parameters

- `-PushRequestId` (String, required): ID of the push upgrade request to abort (starts with 0DV). Passed to sf as --push-request-id. Required.
- `-NoPrompt` (switch): Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf package push-upgrade abort`

#### Examples

```powershell
PS> Stop-SalesforcePushUpgrade -PushRequestId 0DVxx0000000001AAA -TargetDevHub devhub -WhatIf
```

Preview the abort.

#### Remarks

- To see the examples, type: "Get-Help Stop-SalesforcePushUpgrade -Examples"
- For more information, type: "Get-Help Stop-SalesforcePushUpgrade -Detailed"
- For technical information, type: "Get-Help Stop-SalesforcePushUpgrade -Full"
- For online help, type: "Get-Help Stop-SalesforcePushUpgrade -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-packaging>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>
