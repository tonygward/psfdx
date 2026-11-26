# psfdx-metadata command reference

Generated from the commands' own help by `site/Update-ModuleReference.ps1`: do not edit it by hand. The same reference is on the website: <https://psfdx.com/modules/psfdx-metadata/>. It is part of the `psfdx` package; see the [installation guide](../install.md).

39 commands. Every command also takes the common parameters, such as `-Verbose`.

## Commands

**Objects, fields and metadata discovery**: [Build-SalesforceQuery](#build-salesforcequery), [Clear-SalesforceMetadataTypeCache](#clear-salesforcemetadatatypecache), [Describe-SalesforceFields](#describe-salesforcefields), [Describe-SalesforceMetadataTypes](#describe-salesforcemetadatatypes), [Describe-SalesforceObject](#describe-salesforceobject), [Describe-SalesforceObjects](#describe-salesforceobjects), [Get-SalesforceMetadataComponents](#get-salesforcemetadatacomponents)

**Source and tracking**: [ConvertTo-SalesforceMdapiFormat](#convertto-salesforcemdapiformat), [ConvertTo-SalesforceSourceFormat](#convertto-salesforcesourceformat), [Enable-SalesforceSourceBehavior](#enable-salesforcesourcebehavior), [Get-SalesforceIgnoredFiles](#get-salesforceignoredfiles), [Remove-SalesforceSource](#remove-salesforcesource), [Remove-SalesforceSourceTracking](#remove-salesforcesourcetracking), [Reset-SalesforceSourceTracking](#reset-salesforcesourcetracking)

**Deployments**: [Deploy-SalesforceComponent](#deploy-salesforcecomponent), [Deploy-SalesforceMetadata](#deploy-salesforcemetadata), [Get-SalesforceDeployPreview](#get-salesforcedeploypreview), [Get-SalesforceDeployStatus](#get-salesforcedeploystatus), [Resume-SalesforceDeploy](#resume-salesforcedeploy), [Start-SalesforceQuickDeploy](#start-salesforcequickdeploy), [Stop-SalesforceDeploy](#stop-salesforcedeploy), [Test-SalesforceDeploy](#test-salesforcedeploy)

**Retrieval**: [Get-SalesforceRetrievePreview](#get-salesforceretrievepreview), [Retrieve-SalesforceComponent](#retrieve-salesforcecomponent), [Retrieve-SalesforceField](#retrieve-salesforcefield), [Retrieve-SalesforceMetadata](#retrieve-salesforcemetadata), [Retrieve-SalesforceOrg](#retrieve-salesforceorg), [Retrieve-SalesforcePackage](#retrieve-salesforcepackage), [Retrieve-SalesforceValidationRule](#retrieve-salesforcevalidationrule)

**Metadata generation**: [New-SalesforceCustomField](#new-salesforcecustomfield), [New-SalesforceCustomMetadataField](#new-salesforcecustommetadatafield), [New-SalesforceCustomMetadataRecord](#new-salesforcecustommetadatarecord), [New-SalesforceCustomMetadataRecordsFromCsv](#new-salesforcecustommetadatarecordsfromcsv), [New-SalesforceCustomMetadataType](#new-salesforcecustommetadatatype), [New-SalesforceCustomMetadataTypeFromOrg](#new-salesforcecustommetadatatypefromorg), [New-SalesforceCustomObject](#new-salesforcecustomobject), [New-SalesforceCustomTab](#new-salesforcecustomtab), [New-SalesforceManifest](#new-salesforcemanifest), [New-SalesforcePlatformEvent](#new-salesforceplatformevent)

## Objects, fields and metadata discovery

### Build-SalesforceQuery

#### Synopsis

Builds a SELECT statement that lists every field of an object.

#### Syntax

```powershell
Build-SalesforceQuery [-ObjectName] <String> [[-TargetOrg] <String>] [-UseToolingApi] [-ExcludeAuditFields] [-ExcludeNameFields] [-ExcludeContextFields] [<CommonParameters>]
```

#### Description

Reads the object's fields with Describe-SalesforceFields and returns the query text, for example SELECT Id,Name FROM Account. Use the switches to leave out groups of fields. Returns an empty string when the object has no fields. Field and object names are checked so only valid API names end up in the query.

#### Parameters

- `-ObjectName` (String, required): API name of the object. Required.
- `-TargetOrg` (String): Username or alias of the org to describe. If omitted, the Salesforce CLI uses the default target org.
- `-UseToolingApi` (switch): Describe a Tooling API object instead of a standard or custom one.
- `-ExcludeAuditFields` (switch): Leave out CreatedById, CreatedDate, LastModifiedById, LastModifiedDate, SystemModstamp and IsDeleted.
- `-ExcludeNameFields` (switch): Leave out Name, FirstName, LastName and Subject.
- `-ExcludeContextFields` (switch): Leave out OwnerId, RecordTypeId, CurrencyIsoCode and Division.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Build-SalesforceQuery -ObjectName Account -ExcludeAuditFields -TargetOrg dev1
PS> A query for the fields of Account without the audit fields.
```

#### Remarks

- To see the examples, type: "Get-Help Build-SalesforceQuery -Examples"
- For more information, type: "Get-Help Build-SalesforceQuery -Detailed"
- For technical information, type: "Get-Help Build-SalesforceQuery -Full"
- For online help, type: "Get-Help Build-SalesforceQuery -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Clear-SalesforceMetadataTypeCache

#### Synopsis

Forgets the metadata types psfdx cached for -Type completion.

#### Syntax

```powershell
Clear-SalesforceMetadataTypeCache [<CommonParameters>]
```

#### Description

Does not use the Salesforce CLI. psfdx caches the list of metadata types for the session so -Type can be completed and checked; this removes the cache so the next use asks the org again.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Clear-SalesforceMetadataTypeCache
```

Force a fresh list of metadata types.

#### Remarks

- To see the examples, type: "Get-Help Clear-SalesforceMetadataTypeCache -Examples"
- For more information, type: "Get-Help Clear-SalesforceMetadataTypeCache -Detailed"
- For technical information, type: "Get-Help Clear-SalesforceMetadataTypeCache -Full"
- For online help, type: "Get-Help Clear-SalesforceMetadataTypeCache -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Describe-SalesforceFields

#### Synopsis

Lists the fields of an object.

#### Syntax

```powershell
Describe-SalesforceFields [-ObjectName] <String> [[-TargetOrg] <String>] [-UseToolingApi] [<CommonParameters>]
```

#### Description

Describes the object with Describe-SalesforceObject and returns name, label, type and byteLength for each field, sorted by name.

#### Parameters

- `-ObjectName` (String, required): API name of the object. Required.
- `-TargetOrg` (String): Username or alias of the org. If omitted, the Salesforce CLI uses the default target org.
- `-UseToolingApi` (switch): Describe a Tooling API object instead of a standard or custom one.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Describe-SalesforceFields -ObjectName Account -TargetOrg dev1
```

The fields of Account.

#### Remarks

- To see the examples, type: "Get-Help Describe-SalesforceFields -Examples"
- For more information, type: "Get-Help Describe-SalesforceFields -Detailed"
- For technical information, type: "Get-Help Describe-SalesforceFields -Full"
- For online help, type: "Get-Help Describe-SalesforceFields -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Describe-SalesforceMetadataTypes

#### Synopsis

Lists the metadata types enabled in an org.

#### Syntax

```powershell
Describe-SalesforceMetadataTypes [[-TargetOrg] <String>] [[-OutputFile] <String>] [<CommonParameters>]
```

#### Description

Runs sf org list metadata-types and returns just the type names (the xmlName of each type), for example ApexClass. Returns an empty array when the org reports none.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-OutputFile` (String): Path of a file for the CLI to write the full result to (the type names with their suffix, directory and whether they have folders). Passed to sf as --output-file. The folder it goes in must exist. The cmdlet still returns the type names.

#### Salesforce CLI

- `sf org list metadata-types`

#### Examples

```powershell
PS> Describe-SalesforceMetadataTypes -TargetOrg dev1
```

Every metadata type the org supports.

#### Remarks

- To see the examples, type: "Get-Help Describe-SalesforceMetadataTypes -Examples"
- For more information, type: "Get-Help Describe-SalesforceMetadataTypes -Detailed"
- For technical information, type: "Get-Help Describe-SalesforceMetadataTypes -Full"
- For online help, type: "Get-Help Describe-SalesforceMetadataTypes -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Describe-SalesforceObject

#### Synopsis

Describes one object: fields, relationships and settings.

#### Syntax

```powershell
Describe-SalesforceObject [-Name] <String> [[-TargetOrg] <String>] [-UseToolingApi] [<CommonParameters>]
```

#### Description

Runs sf sobject describe and returns the full description as an object. Use Describe-SalesforceFields for just the field list.

#### Parameters

- `-Name` (String, required): API name of the object. Passed as --sobject. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-UseToolingApi` (switch): Use Tooling API to display metadata for Tooling API objects. Adds --use-tooling-api.

#### Salesforce CLI

- `sf sobject describe`

#### Examples

```powershell
PS> Describe-SalesforceObject -Name Account -TargetOrg dev1
```

The full description of Account.

#### Remarks

- To see the examples, type: "Get-Help Describe-SalesforceObject -Examples"
- For more information, type: "Get-Help Describe-SalesforceObject -Detailed"
- For technical information, type: "Get-Help Describe-SalesforceObject -Full"
- For online help, type: "Get-Help Describe-SalesforceObject -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-schema>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Describe-SalesforceObjects

#### Synopsis

Lists the objects in an org.

#### Syntax

```powershell
Describe-SalesforceObjects [[-TargetOrg] <String>] [[-Category] <String>] [<CommonParameters>]
```

#### Description

Runs sf sobject list and returns the object names. With no category the CLI lists all objects.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-Category` (String): Which objects to list. Valid values: all, standard, custom. The CLI default is all. Passed to sf as --sobject.

#### Salesforce CLI

- `sf sobject list`

#### Examples

```powershell
PS> Describe-SalesforceObjects -TargetOrg dev1
```

Every object name.

#### Remarks

- To see the examples, type: "Get-Help Describe-SalesforceObjects -Examples"
- For more information, type: "Get-Help Describe-SalesforceObjects -Detailed"
- For technical information, type: "Get-Help Describe-SalesforceObjects -Full"
- For online help, type: "Get-Help Describe-SalesforceObjects -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-schema>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceMetadataComponents

#### Synopsis

Lists the metadata components of one type that exist in an org.

#### Syntax

```powershell
Get-SalesforceMetadataComponents [-MetadataType] <String> [[-Folder] <String>] [[-OutputFile] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf org list metadata for a metadata type, for example ApexClass or CustomObject, and returns one object per component (fullName, fileName, type, id, createdDate, lastModifiedDate and who changed it). Use Describe-SalesforceMetadataTypes to see which types an org has. Types that live in folders, such as Report or EmailTemplate, need -Folder.

#### Parameters

- `-MetadataType` (String, required): Metadata type to list, for example ApexClass. Passed to sf as --metadata-type. Required. Tab completion offers the types of the org.
- `-Folder` (String): Folder that holds the components, for types that are stored in folders. Passed to sf as --folder.
- `-OutputFile` (String): Path of a file for the CLI to write the result to. Passed to sf as --output-file. The folder it goes in must exist. The cmdlet still returns the components.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf org list metadata`

#### Examples

```powershell
PS> Get-SalesforceMetadataComponents -MetadataType ApexClass -TargetOrg dev1 | Select-Object fullName, lastModifiedDate
```

Every Apex class in dev1 and when it last changed.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceMetadataComponents -Examples"
- For more information, type: "Get-Help Get-SalesforceMetadataComponents -Detailed"
- For technical information, type: "Get-Help Get-SalesforceMetadataComponents -Full"
- For online help, type: "Get-Help Get-SalesforceMetadataComponents -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Source and tracking

### ConvertTo-SalesforceMdapiFormat

#### Synopsis

Converts Salesforce DX source files into Metadata API (mdapi) format.

#### Syntax

```powershell
ConvertTo-SalesforceMdapiFormat [[-RootDir] <String>] [[-SourceDir] <String[]>] [[-OutputDir] <String>] [[-Manifest] <String>] [[-Metadata] <String[]>] [[-PackageName] <String>] [<CommonParameters>]
```

#### Description

Runs sf project convert source. The source in the project (or in -RootDir or -SourceDir) is converted into the format that Metadata API deploys, and written to -OutputDir. Works on local files only; it does not touch an org.

#### Parameters

- `-RootDir` (String): Folder that holds the source files. Passed as --root-dir. The CLI uses the project package folders when omitted.
- `-SourceDir` (String[]): Source folders or files to convert. Each path must exist. Passed as one --source-dir per value.
- `-OutputDir` (String): Folder that receives the converted files. Passed as --output-dir.
- `-Manifest` (String): Path of a package.xml that selects what to convert. The file must exist. Passed as --manifest.
- `-Metadata` (String[]): Metadata components to convert, such as ApexClass:MyClass. Passed as one --metadata per value.
- `-PackageName` (String): Name of the package the converted files belong to. Passed as --package-name.

#### Salesforce CLI

- `sf project convert source`

#### Examples

```powershell
PS> ConvertTo-SalesforceMdapiFormat -SourceDir force-app -OutputDir .\mdapi
```

Convert force-app to Metadata API format.

#### Remarks

- To see the examples, type: "Get-Help ConvertTo-SalesforceMdapiFormat -Examples"
- For more information, type: "Get-Help ConvertTo-SalesforceMdapiFormat -Detailed"
- For technical information, type: "Get-Help ConvertTo-SalesforceMdapiFormat -Full"
- For online help, type: "Get-Help ConvertTo-SalesforceMdapiFormat -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### ConvertTo-SalesforceSourceFormat

#### Synopsis

Converts Metadata API (mdapi) files into the source format of a Salesforce DX project.

#### Syntax

```powershell
ConvertTo-SalesforceSourceFormat [-RootDir] <String> [[-OutputDir] <String>] [[-Manifest] <String>] [[-Metadata] <String[]>] [[-MetadataDir] <String[]>] [<CommonParameters>]
```

#### Description

Runs sf project convert mdapi. The files in -RootDir, which you retrieved as a package, are converted into source format and written to -OutputDir, or to the default package folder of the project. Use -Manifest, -Metadata or -MetadataDir to convert only part of them. Works on local files only; it does not touch an org.

#### Parameters

- `-RootDir` (String, required): Folder that holds the Metadata API files. It must exist. Passed as --root-dir. Required.
- `-OutputDir` (String): Folder that receives the source format files. Passed as --output-dir. The CLI uses the default package folder when omitted.
- `-Manifest` (String): Path of a package.xml that selects what to convert. The file must exist. Passed as --manifest.
- `-Metadata` (String[]): Metadata components to convert, such as ApexClass:MyClass. Passed as one --metadata per value.
- `-MetadataDir` (String[]): Folders inside -RootDir to convert. Passed as one --metadata-dir per value.

#### Salesforce CLI

- `sf project convert mdapi`

#### Examples

```powershell
PS> ConvertTo-SalesforceSourceFormat -RootDir .\retrieved -OutputDir force-app
```

Convert a retrieved package into source format.

#### Remarks

- To see the examples, type: "Get-Help ConvertTo-SalesforceSourceFormat -Examples"
- For more information, type: "Get-Help ConvertTo-SalesforceSourceFormat -Detailed"
- For technical information, type: "Get-Help ConvertTo-SalesforceSourceFormat -Full"
- For online help, type: "Get-Help ConvertTo-SalesforceSourceFormat -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Enable-SalesforceSourceBehavior

#### Synopsis

Turns on a beta source behavior, such as decomposed permission sets, and updates the project to use it (beta).

#### Syntax

```powershell
Enable-SalesforceSourceBehavior [-Behavior] <String> [-DryRun] [-PreserveTempDir] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf project convert source-behavior, a beta command, so its name, flags and result can change in a later CLI release. It rewrites the source files of the project and adds the behavior to sfdx-project.json. Supports -WhatIf and -Confirm (no prompt by default). -DryRun asks the CLI to show what it would change and changes nothing, so it runs without confirmation.

#### Parameters

- `-Behavior` (String, required): The behavior to turn on. Valid values: decomposeCustomLabelsBeta2, decomposeCustomLabelsBeta, decomposePermissionSetBeta, decomposePermissionSetBeta2, decomposeSharingRulesBeta, decomposeWorkflowBeta, decomposeExternalServiceRegistrationBeta. Passed as --behavior. Required.
- `-DryRun` (switch): Show what would change without changing it. Adds --dry-run.
- `-PreserveTempDir` (switch): Keep the temporary folder the CLI uses during the conversion. Adds --preserve-temp-dir.
- `-TargetOrg` (String): Username or alias of the target org. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf project convert source-behavior`

#### Examples

```powershell
PS> Enable-SalesforceSourceBehavior -Behavior decomposePermissionSetBeta2 -DryRun
```

See what the behavior would change.

#### Remarks

- To see the examples, type: "Get-Help Enable-SalesforceSourceBehavior -Examples"
- For more information, type: "Get-Help Enable-SalesforceSourceBehavior -Detailed"
- For technical information, type: "Get-Help Enable-SalesforceSourceBehavior -Full"
- For online help, type: "Get-Help Enable-SalesforceSourceBehavior -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceIgnoredFiles

#### Synopsis

Lists the files in the project package folders that .forceignore leaves out.

#### Syntax

```powershell
Get-SalesforceIgnoredFiles [[-SourceDir] <String>] [<CommonParameters>]
```

#### Description

Runs sf project list ignored and returns one path per ignored file. Read-only. Use -SourceDir to check one folder instead of every package directory.

#### Parameters

- `-SourceDir` (String): Folder or file to check. It must exist. Passed as --source-dir. The CLI checks every package directory when omitted.

#### Salesforce CLI

- `sf project list ignored`

#### Examples

```powershell
PS> Get-SalesforceIgnoredFiles -SourceDir force-app/main/default/classes
```

Which class files does .forceignore skip.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceIgnoredFiles -Examples"
- For more information, type: "Get-Help Get-SalesforceIgnoredFiles -Detailed"
- For technical information, type: "Get-Help Get-SalesforceIgnoredFiles -Full"
- For online help, type: "Get-Help Get-SalesforceIgnoredFiles -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceSource

#### Synopsis

Deletes components from the org and from the local project.

#### Syntax

```powershell
Remove-SalesforceSource [[-SourceDir] <String[]>] [[-Metadata] <String[]>] [-CheckOnly] [-ForceOverwrite] [-TrackSource] [[-TestLevel] <String>] [[-Tests] <String[]>] [[-Wait] <Int32>] [-DetailedResults] [-NoPrompt] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf project delete source. The named source files or metadata components are deleted from a org that does not use source tracking, and their files are deleted from the project. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. -CheckOnly validates the delete without making it, so it needs no confirmation. Give -SourceDir or -Metadata. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time.

#### Parameters

- `-SourceDir` (String[]): Source folders or files to delete. Each path must exist. Passed as one --source-dir per value.
- `-Metadata` (String[]): Metadata components to delete, such as ApexClass:MyClass. Passed as one --metadata per value.
- `-CheckOnly` (switch): Validate the delete, run any tests, and change nothing. Adds --check-only.
- `-ForceOverwrite` (switch): Delete even if it overwrites changes in a source-tracked org. Adds --force-overwrite.
- `-TrackSource` (switch): Update source tracking after the delete. Adds --track-source.
- `-TestLevel` (String): Apex testing level. Passed to sf as --test-level. Valid values: NoTests, SpecificTests, TestsInOrg, TestsInOrgAndPackages, RelevantTests. Value mapping to the CLI: NoTests = NoTestRun, SpecificTests = RunSpecifiedTests, TestsInOrg = RunLocalTests, TestsInOrgAndPackages = RunAllTestsInOrg, RelevantTests = RunRelevantTests. The CLI default applies when omitted.
- `-Tests` (String[]): Apex test classes to run with -TestLevel SpecificTests. Passed as one --tests per name.
- `-Wait` (Int32): Number of minutes to wait for the command to finish. Passed as --wait.
- `-DetailedResults` (switch): Show verbose output of the delete result. Adds --verbose.
- `-NoPrompt` (switch): Do not ask for confirmation. Use it in unattended scripts. -WhatIf still shows what would happen without deleting.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf project delete source`

#### Examples

```powershell
PS> Remove-SalesforceSource -Metadata ApexClass:OldHelper -TargetOrg dev1 -WhatIf
```

Preview deleting one class from the org and the project.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceSource -Examples"
- For more information, type: "Get-Help Remove-SalesforceSource -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceSource -Full"
- For online help, type: "Get-Help Remove-SalesforceSource -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceSourceTracking

#### Synopsis

Deletes the local source tracking information of an org.

#### Syntax

```powershell
Remove-SalesforceSourceTracking [-NoPrompt] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf project delete tracking. The local files that record what has changed between the project and the org are deleted; nothing in the org or in your source files changes, but the next deploy or retrieve cannot tell what changed. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time.

#### Parameters

- `-NoPrompt` (switch): Do not ask for confirmation. Use it in unattended scripts. -WhatIf still shows what would happen without deleting.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf project delete tracking`

#### Examples

```powershell
PS> Remove-SalesforceSourceTracking -TargetOrg dev1 -WhatIf
```

Preview deleting the tracking files of dev1.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceSourceTracking -Examples"
- For more information, type: "Get-Help Remove-SalesforceSourceTracking -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceSourceTracking -Full"
- For online help, type: "Get-Help Remove-SalesforceSourceTracking -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Reset-SalesforceSourceTracking

#### Synopsis

Resets local and remote source tracking of an org to a revision.

#### Syntax

```powershell
Reset-SalesforceSourceTracking [[-Revision] <Int32>] [-NoPrompt] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf project reset tracking. Source tracking is reset to the latest revision in the org, or to the revision number you give with -Revision. After a reset the next deploy or retrieve starts from that point, so changes made before it are no longer reported. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time.

#### Parameters

- `-Revision` (Int32): SourceMember revision number to reset to. Passed as --revision. The CLI uses the latest revision when omitted; 0 resets to the beginning.
- `-NoPrompt` (switch): Do not ask for confirmation. Use it in unattended scripts. -WhatIf still shows what would happen without resetting.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf project reset tracking`

#### Examples

```powershell
PS> Reset-SalesforceSourceTracking -Revision 0 -TargetOrg my-scratch -WhatIf
```

Preview resetting tracking to the beginning.

#### Remarks

- To see the examples, type: "Get-Help Reset-SalesforceSourceTracking -Examples"
- For more information, type: "Get-Help Reset-SalesforceSourceTracking -Detailed"
- For technical information, type: "Get-Help Reset-SalesforceSourceTracking -Full"
- For online help, type: "Get-Help Reset-SalesforceSourceTracking -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Deployments

### Deploy-SalesforceComponent

#### Synopsis

Deploys one metadata component, or a source path, to an org.

#### Syntax

```powershell
Deploy-SalesforceComponent [[-Type] <String>] [[-Name] <String>] [[-SourceDir] <String>] [-IgnoreConflicts] [-IgnoreWarnings] [-IgnoreErrors] [[-Wait] <Int32>] [[-TestLevel] <String>] [[-Tests] <String[]>] [-Async] [[-CoverageFormatters] <String[]>] [-Junit] [[-ResultsDir] <String>] [-DryRun] [-ConciseResults] [-DetailedResults] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf project deploy start with --metadata Type:Name or --source-dir, with optional test level and tests. -DryRun adds --dry-run, which validates without deploying, so only a real deployment is confirmed. Supports -WhatIf and -Confirm (no prompt by default).

#### Parameters

- `-Type` (String): Metadata type, for example ApexClass. Completes from the org's metadata types. Needed unless -SourceDir is given. Passed to sf as --metadata.
- `-Name` (String): Name of the component. Needs -Type. Passed as --metadata Type:Name.
- `-SourceDir` (String): Path to the local source files to deploy. Passed to sf as --source-dir.
- `-IgnoreConflicts` (switch): Ignore conflicts and deploy local files, even if they overwrite changes in the org. Adds --ignore-conflicts.
- `-IgnoreWarnings` (switch): Ignore warnings and allow a deployment to complete successfully. Adds --ignore-warnings.
- `-IgnoreErrors` (switch): Ignore any errors and don't roll back deployment. Adds --ignore-errors.
- `-Wait` (Int32): Number of minutes to wait for command to complete and display results. Passed to sf as --wait.
- `-TestLevel` (String): How tests run. psfdx level names are translated to the CLI's (see the value mapping). Passed to sf as --test-level. Default: NoTests. Valid values: NoTests, SpecificTests, ReferencedTests, TestsInFolder, TestsInOrg, TestsInOrgAndPackages, RelevantTests. Value mapping to the CLI: NoTests = NoTestRun, SpecificTests = RunSpecifiedTests, ReferencedTests = RunSpecifiedTests, TestsInFolder = RunSpecifiedTests, TestsInOrg = RunLocalTests, TestsInOrgAndPackages = RunAllTestsInOrg, RelevantTests = RunRelevantTests.
- `-Tests` (String[]): Test classes to run for -TestLevel SpecificTests. Passed as one --tests per name.
- `-Async` (switch): Start the deployment and return without waiting for it (use Get-SalesforceDeployStatus or Resume-SalesforceDeploy later). Adds --async.
- `-CoverageFormatters` (String[]): Format of the code coverage results written to the results folder. Valid values: clover, cobertura, html-spa, html, json, json-summary, lcovonly, none, teamcity, text, text-summary. Passed as one --coverage-formatters per value.
- `-Junit` (switch): Also write JUnit test results. Adds --junit.
- `-ResultsDir` (String): Folder that receives the test and coverage results. Passed as --results-dir.
- `-DryRun` (switch): Validate only. Passed as --dry-run; nothing is deployed.
- `-ConciseResults` (switch): Show concise output of the deploy result. Adds --concise.
- `-DetailedResults` (switch): Show verbose output of the deploy result. Adds --verbose.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf project deploy start`

#### Examples

```powershell
PS> Deploy-SalesforceComponent -Type ApexClass -Name AccountService -TargetOrg dev1 -WhatIf
```

Preview deploying one class.

#### Remarks

- To see the examples, type: "Get-Help Deploy-SalesforceComponent -Examples"
- For more information, type: "Get-Help Deploy-SalesforceComponent -Detailed"
- For technical information, type: "Get-Help Deploy-SalesforceComponent -Full"
- For online help, type: "Get-Help Deploy-SalesforceComponent -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Deploy-SalesforceMetadata

#### Synopsis

Deploys metadata described by a manifest or a metadata folder.

#### Syntax

```powershell
Deploy-SalesforceMetadata [[-Manifest] <String>] [[-InputDir] <String>] [-ManifestPackage] [[-TargetOrg] <String>] [-IgnoreConflicts] [-IgnoreWarnings] [-IgnoreErrors] [[-PreDestructiveChanges] <String>] [[-PostDestructiveChanges] <String>] [-PurgeOnDelete] [-Async] [[-CoverageFormatters] <String[]>] [-Junit] [[-ResultsDir] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf project deploy start with --manifest, --metadata-dir or --single-package. Give exactly one of -Manifest, -InputDir and -ManifestPackage. Supports -WhatIf and -Confirm (no prompt by default).

#### Parameters

- `-Manifest` (String): Path of package.xml. Passed as --manifest.
- `-InputDir` (String): Folder of metadata in metadata (mdapi) format. Passed as --metadata-dir.
- `-ManifestPackage` (switch): Treat the metadata directory as a single package. Passed as --single-package.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-IgnoreConflicts` (switch): Ignore conflicts and deploy local files, even if they overwrite changes in the org. Adds --ignore-conflicts.
- `-IgnoreWarnings` (switch): Ignore warnings and allow a deployment to complete successfully. Adds --ignore-warnings.
- `-IgnoreErrors` (switch): Ignore any errors and don't roll back deployment. Adds --ignore-errors.
- `-PreDestructiveChanges` (String): Path of a destructiveChangesPre.xml file; the components it lists are deleted before the deploy. The file must exist. Passed as --pre-destructive-changes.
- `-PostDestructiveChanges` (String): Path of a destructiveChangesPost.xml file; the components it lists are deleted after the deploy. The file must exist. Passed as --post-destructive-changes.
- `-PurgeOnDelete` (switch): Delete the destructive-changes components permanently instead of keeping them in the Recycle Bin. Needs -PreDestructiveChanges or -PostDestructiveChanges. Adds --purge-on-delete.
- `-Async` (switch): Start the deployment and return without waiting for it (use Get-SalesforceDeployStatus or Resume-SalesforceDeploy later). Adds --async.
- `-CoverageFormatters` (String[]): Format of the code coverage results written to the results folder. Valid values: clover, cobertura, html-spa, html, json, json-summary, lcovonly, none, teamcity, text, text-summary. Passed as one --coverage-formatters per value.
- `-Junit` (switch): Also write JUnit test results. Adds --junit.
- `-ResultsDir` (String): Folder that receives the test and coverage results. Passed as --results-dir.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf project deploy start`

#### Examples

```powershell
PS> Deploy-SalesforceMetadata -Manifest manifest/package.xml -TargetOrg dev1 -WhatIf
```

Preview deploying a manifest.

#### Remarks

- To see the examples, type: "Get-Help Deploy-SalesforceMetadata -Examples"
- For more information, type: "Get-Help Deploy-SalesforceMetadata -Detailed"
- For technical information, type: "Get-Help Deploy-SalesforceMetadata -Full"
- For online help, type: "Get-Help Deploy-SalesforceMetadata -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceDeployPreview

#### Synopsis

Shows what a deploy would send, and what conflicts with the org, without deploying (sf project deploy preview).

#### Syntax

```powershell
Get-SalesforceDeployPreview [[-SourceDir] <String[]>] [[-Manifest] <String>] [[-Metadata] <String[]>] [-IgnoreConflicts] [-ConciseResults] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Read-only: nothing is deployed, retrieved or deleted. Returns one object with ToDeploy, ToRetrieve, ToDelete, Conflicts and Ignored, plus HasChanges, HasConflicts and Summary. With no changes the lists are empty and Summary is 'No changes'. Source tracking is required: scratch orgs and tracked sandboxes work; other orgs return the CLI error with guidance. Narrow the preview with -SourceDir, -Manifest (one package.xml; the CLI accepts only one) or -Metadata (any combination the CLI accepts).

#### Parameters

- `-SourceDir` (String[]): Path to the local source files to preview. Passed to sf as --source-dir.
- `-Manifest` (String): Full file path for manifest (package.xml) of components to preview. Passed to sf as --manifest.
- `-Metadata` (String[]): Metadata component names to preview. Passed to sf as --metadata.
- `-IgnoreConflicts` (switch): Don't display conflicts in preview of the deployment. Adds --ignore-conflicts.
- `-ConciseResults` (switch): Show concise output. Adds --concise.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf project deploy preview`

#### Examples

```powershell
PS> Get-SalesforceDeployPreview -TargetOrg my-sandbox
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceDeployPreview -Examples"
- For more information, type: "Get-Help Get-SalesforceDeployPreview -Detailed"
- For technical information, type: "Get-Help Get-SalesforceDeployPreview -Full"
- For online help, type: "Get-Help Get-SalesforceDeployPreview -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceDeployStatus

#### Synopsis

Reports the status of a deployment.

#### Syntax

```powershell
Get-SalesforceDeployStatus [[-JobId] <String>] [-UseMostRecent] [[-Wait] <Int32>] [[-TargetOrg] <String>] [[-CoverageFormatters] <String[]>] [-Junit] [[-ResultsDir] <String>] [<CommonParameters>]
```

#### Description

Runs sf project deploy report for a job ID, or for the most recent deployment with -UseMostRecent. Give one of the two. With -Wait the CLI keeps polling.

#### Parameters

- `-JobId` (String): Job ID of the deploy operation you want to check the status of. Passed to sf as --job-id.
- `-UseMostRecent` (switch): Report on the deployment the CLI started most recently. Use instead of -JobId.
- `-Wait` (Int32): Number of minutes to wait for command to complete and display results. Passed to sf as --wait.
- `-TargetOrg` (String): Username or alias of the target org. Passed to sf as --target-org.
- `-CoverageFormatters` (String[]): Format of the code coverage results written to the results folder. Valid values: clover, cobertura, html-spa, html, json, json-summary, lcovonly, none, teamcity, text, text-summary. Passed as one --coverage-formatters per value.
- `-Junit` (switch): Also write JUnit test results. Adds --junit.
- `-ResultsDir` (String): Folder that receives the test and coverage results. Passed as --results-dir.

#### Salesforce CLI

- `sf project deploy report`

#### Examples

```powershell
PS> Get-SalesforceDeployStatus -UseMostRecent -TargetOrg dev1
```

Status of the last deployment.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceDeployStatus -Examples"
- For more information, type: "Get-Help Get-SalesforceDeployStatus -Detailed"
- For technical information, type: "Get-Help Get-SalesforceDeployStatus -Full"
- For online help, type: "Get-Help Get-SalesforceDeployStatus -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Resume-SalesforceDeploy

#### Synopsis

Resumes watching a deployment that is still running.

#### Syntax

```powershell
Resume-SalesforceDeploy [[-JobId] <String>] [-UseMostRecent] [[-Wait] <Int32>] [-ConciseResults] [-DetailedResults] [[-CoverageFormatters] <String[]>] [-Junit] [[-ResultsDir] <String>] [<CommonParameters>]
```

#### Description

Runs sf project deploy resume for a job ID, or the most recent one with -UseMostRecent. The CLI finds the org from its record of the job, so there is no -TargetOrg.

#### Parameters

- `-JobId` (String): Job ID of the deploy operation you want to resume. Passed to sf as --job-id.
- `-UseMostRecent` (switch): Resume the deployment the CLI started most recently. Use instead of -JobId.
- `-Wait` (Int32): Number of minutes to wait for the command to complete and display results. Passed to sf as --wait.
- `-ConciseResults` (switch): Show concise output of the deploy operation result. Adds --concise.
- `-DetailedResults` (switch): Show verbose output of the deploy operation result. Adds --verbose.
- `-CoverageFormatters` (String[]): Format of the code coverage results written to the results folder. Valid values: clover, cobertura, html-spa, html, json, json-summary, lcovonly, none, teamcity, text, text-summary. Passed as one --coverage-formatters per value.
- `-Junit` (switch): Also write JUnit test results. Adds --junit.
- `-ResultsDir` (String): Folder that receives the test and coverage results. Passed as --results-dir.

#### Salesforce CLI

- `sf project deploy resume`

#### Examples

```powershell
PS> Resume-SalesforceDeploy -UseMostRecent -Wait 10
```

Wait up to ten more minutes for the last deployment.

#### Remarks

- To see the examples, type: "Get-Help Resume-SalesforceDeploy -Examples"
- For more information, type: "Get-Help Resume-SalesforceDeploy -Detailed"
- For technical information, type: "Get-Help Resume-SalesforceDeploy -Full"
- For online help, type: "Get-Help Resume-SalesforceDeploy -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Start-SalesforceQuickDeploy

#### Synopsis

Deploys a validated deployment without running the tests again.

#### Syntax

```powershell
Start-SalesforceQuickDeploy [[-JobId] <String>] [-UseMostRecent] [[-Wait] <Int32>] [-Async] [-ConciseResults] [-DetailedResults] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf project deploy quick for the validation job ID (or the most recent with -UseMostRecent). The validation must have passed recently. Asks for confirmation and supports -WhatIf.

#### Parameters

- `-JobId` (String): Job ID of the deployment you want to quick deploy. Passed to sf as --job-id.
- `-UseMostRecent` (switch): Use the validation the CLI ran most recently. Use instead of -JobId.
- `-Wait` (Int32): Number of minutes to wait for the command to complete and display results. Passed to sf as --wait.
- `-Async` (switch): Run the command asynchronously. Adds --async.
- `-ConciseResults` (switch): Show concise output of the deploy result. Adds --concise.
- `-DetailedResults` (switch): Show verbose output of the deploy result. Adds --verbose.
- `-TargetOrg` (String): Username or alias of the target org. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf project deploy quick`

#### Examples

```powershell
PS> Start-SalesforceQuickDeploy -JobId 0Af000000000001AAA -TargetOrg prod -WhatIf
```

Preview the quick deploy.

#### Remarks

- To see the examples, type: "Get-Help Start-SalesforceQuickDeploy -Examples"
- For more information, type: "Get-Help Start-SalesforceQuickDeploy -Detailed"
- For technical information, type: "Get-Help Start-SalesforceQuickDeploy -Full"
- For online help, type: "Get-Help Start-SalesforceQuickDeploy -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Stop-SalesforceDeploy

#### Synopsis

Cancels a deployment that is running.

#### Syntax

```powershell
Stop-SalesforceDeploy [[-JobId] <String>] [-UseMostRecent] [[-Wait] <Int32>] [-Async] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf project deploy cancel for a job ID or the most recent one. Asks for confirmation and supports -WhatIf.

#### Parameters

- `-JobId` (String): Job ID of the deploy operation you want to cancel. Passed to sf as --job-id.
- `-UseMostRecent` (switch): Cancel the deployment the CLI started most recently. Use instead of -JobId.
- `-Wait` (Int32): Number of minutes to wait for the command to complete and display results. Passed to sf as --wait.
- `-Async` (switch): Run the command asynchronously. Adds --async.
- `-TargetOrg` (String): Username or alias of the target org. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf project deploy cancel`

#### Examples

```powershell
PS> Stop-SalesforceDeploy -UseMostRecent -TargetOrg dev1 -WhatIf
```

Preview the cancel.

#### Remarks

- To see the examples, type: "Get-Help Stop-SalesforceDeploy -Examples"
- For more information, type: "Get-Help Stop-SalesforceDeploy -Detailed"
- For technical information, type: "Get-Help Stop-SalesforceDeploy -Full"
- For online help, type: "Get-Help Stop-SalesforceDeploy -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Test-SalesforceDeploy

#### Synopsis

Validates a deployment, running tests, without deploying it.

#### Syntax

```powershell
Test-SalesforceDeploy [[-Manifest] <String>] [[-SourceDir] <String>] [[-InputDir] <String>] [[-Metadata] <String[]>] [[-PreDestructiveChanges] <String>] [[-PostDestructiveChanges] <String>] [-PurgeOnDelete] [[-CoverageFormatters] <String[]>] [-Junit] [[-ResultsDir] <String>] [-ManifestPackage] [[-TestLevel] <String>] [[-Tests] <String[]>] [-IgnoreWarnings] [[-Wait] <Int32>] [-Async] [-ConciseResults] [-DetailedResults] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf project deploy validate. Nothing is deployed; a passing validation can be released later with Start-SalesforceQuickDeploy. The test level must run tests (NoTests is not offered).

#### Parameters

- `-Manifest` (String): Full file path for manifest (package.xml) of components to validate for deployment. Passed to sf as --manifest.
- `-SourceDir` (String): Path to the local source files to validate for deployment. Passed to sf as --source-dir.
- `-InputDir` (String): Root of directory or zip file of metadata formatted files to deploy. Passed to sf as --metadata-dir.
- `-Metadata` (String[]): Metadata components to validate, such as ApexClass:MyClass. Use instead of -Manifest, -SourceDir and -InputDir. Passed as one --metadata per value.
- `-PreDestructiveChanges` (String): Path of a destructiveChangesPre.xml file; the components it lists are deleted before the deploy. The file must exist. Passed as --pre-destructive-changes.
- `-PostDestructiveChanges` (String): Path of a destructiveChangesPost.xml file; the components it lists are deleted after the deploy. The file must exist. Passed as --post-destructive-changes.
- `-PurgeOnDelete` (switch): Delete the destructive-changes components permanently instead of keeping them in the Recycle Bin. Needs -PreDestructiveChanges or -PostDestructiveChanges. Adds --purge-on-delete.
- `-CoverageFormatters` (String[]): Format of the code coverage results written to the results folder. Valid values: clover, cobertura, html-spa, html, json, json-summary, lcovonly, none, teamcity, text, text-summary. Passed as one --coverage-formatters per value.
- `-Junit` (switch): Also write JUnit test results. Adds --junit.
- `-ResultsDir` (String): Folder that receives the test and coverage results. Passed as --results-dir.
- `-ManifestPackage` (switch): Indicates that the metadata zip file points to a directory structure for a single package. Adds --single-package.
- `-TestLevel` (String): Deployment Apex testing level. Passed to sf as --test-level. Default: TestsInOrg. Valid values: SpecificTests, ReferencedTests, TestsInFolder, TestsInOrg, TestsInOrgAndPackages, RelevantTests. Value mapping to the CLI: NoTests = NoTestRun, SpecificTests = RunSpecifiedTests, ReferencedTests = RunSpecifiedTests, TestsInFolder = RunSpecifiedTests, TestsInOrg = RunLocalTests, TestsInOrgAndPackages = RunAllTestsInOrg, RelevantTests = RunRelevantTests.
- `-Tests` (String[]): Apex tests to run when --test-level is RunSpecifiedTests.
- `-IgnoreWarnings` (switch): Ignore warnings and allow a deployment to complete successfully. Adds --ignore-warnings.
- `-Wait` (Int32): Number of minutes to wait for the command to complete and display results. Passed to sf as --wait.
- `-Async` (switch): Run the command asynchronously. Adds --async.
- `-ConciseResults` (switch): Show concise output of the validation result. Adds --concise.
- `-DetailedResults` (switch): Show verbose output of the validation result. Adds --verbose.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf project deploy validate`

#### Examples

```powershell
PS> Test-SalesforceDeploy -SourceDir force-app -TestLevel TestsInOrg -TargetOrg prod
```

Validate against production with all local tests.

#### Remarks

- To see the examples, type: "Get-Help Test-SalesforceDeploy -Examples"
- For more information, type: "Get-Help Test-SalesforceDeploy -Detailed"
- For technical information, type: "Get-Help Test-SalesforceDeploy -Full"
- For online help, type: "Get-Help Test-SalesforceDeploy -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Retrieval

### Get-SalesforceRetrievePreview

#### Synopsis

Shows what a retrieve would bring down, and what conflicts with local files, without retrieving (sf project retrieve preview).

#### Syntax

```powershell
Get-SalesforceRetrievePreview [-IgnoreConflicts] [-ConciseResults] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Read-only: nothing is retrieved or changed. Returns the same object as Get-SalesforceDeployPreview. The CLI command takes no selection flags, so it previews the org's tracked changes. Source tracking is required (see Get-SalesforceDeployPreview).

#### Parameters

- `-IgnoreConflicts` (switch): Don't display conflicts in the preview of the retrieval. Adds --ignore-conflicts.
- `-ConciseResults` (switch): Show concise output. Adds --concise.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf project retrieve preview`

#### Examples

```powershell
PS> Get-SalesforceRetrievePreview -TargetOrg my-scratch
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceRetrievePreview -Examples"
- For more information, type: "Get-Help Get-SalesforceRetrievePreview -Detailed"
- For technical information, type: "Get-Help Get-SalesforceRetrievePreview -Full"
- For online help, type: "Get-Help Get-SalesforceRetrievePreview -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Retrieve-SalesforceComponent

#### Synopsis

Retrieves one metadata component from an org.

#### Syntax

```powershell
Retrieve-SalesforceComponent [[-Type] <String>] [[-Name] <String>] [[-ChildName] <String>] [[-SourceDir] <String[]>] [[-RootTypeWithDependencies] <String[]>] [[-TargetOrg] <String>] [[-Wait] <Int32>] [[-OutputDir] <String>] [-IgnoreConflicts] [<CommonParameters>]
```

#### Description

Runs sf project retrieve start with --metadata Type, Type:Name or Type:Name.ChildName. The type is checked against the org's metadata types.

#### Parameters

- `-Type` (String): Metadata type, for example ApexClass or CustomField. Required unless you give -SourceDir; completes from the org's metadata types and is checked.
- `-Name` (String): Name of the component, for example an object name for a field. Together with -Type it forms --metadata Type:Name.
- `-ChildName` (String): Metadata component names to retrieve. Wildcards (`*`) supported as long as you use quotes, such as `ApexClass:MyClass*`. Passed to sf as --metadata.
- `-SourceDir` (String[]): Local source folders or files whose components are retrieved from the org. Each path must exist. Use instead of -Type. Passed as one --source-dir per value.
- `-RootTypeWithDependencies` (String[]): Metadata types to retrieve together with the components they depend on. Valid values: Bot, AiAgentDefinitionVersion. Passed as one --root-type-with-dependencies per value.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-Wait` (Int32): Number of minutes to wait for the command to complete and display results to the terminal window. Passed to sf as --wait.
- `-OutputDir` (String): Directory root for the retrieved source files. Passed to sf as --output-dir.
- `-IgnoreConflicts` (switch): Ignore conflicts and retrieve and save files to your local filesystem, even if they overwrite your local changes. Adds --ignore-conflicts.

#### Salesforce CLI

- `sf project retrieve start`

#### Examples

```powershell
PS> Retrieve-SalesforceComponent -Type ApexClass -Name AccountService -TargetOrg dev1
```

Retrieve one class into the project.

#### Remarks

- To see the examples, type: "Get-Help Retrieve-SalesforceComponent -Examples"
- For more information, type: "Get-Help Retrieve-SalesforceComponent -Detailed"
- For technical information, type: "Get-Help Retrieve-SalesforceComponent -Full"
- For online help, type: "Get-Help Retrieve-SalesforceComponent -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Retrieve-SalesforceField

#### Synopsis

Retrieves one custom field into the project.

#### Syntax

```powershell
Retrieve-SalesforceField [-ObjectName] <String> [-FieldName] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

A shortcut for Retrieve-SalesforceComponent -Type CustomField with the object as the name and the field as the child name.

#### Parameters

- `-ObjectName` (String, required): API name of the object that holds the field. Required.
- `-FieldName` (String, required): API name of the field, for example Rating__c. Required.
- `-TargetOrg` (String): Username or alias of the org. If omitted, the Salesforce CLI uses the default target org.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Retrieve-SalesforceField -ObjectName Account -FieldName Rating__c -TargetOrg dev1
```

Retrieve Account.Rating__c.

#### Remarks

- To see the examples, type: "Get-Help Retrieve-SalesforceField -Examples"
- For more information, type: "Get-Help Retrieve-SalesforceField -Detailed"
- For technical information, type: "Get-Help Retrieve-SalesforceField -Full"
- For online help, type: "Get-Help Retrieve-SalesforceField -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Retrieve-SalesforceMetadata

#### Synopsis

Retrieves the metadata a manifest lists, as a package, into a folder.

#### Syntax

```powershell
Retrieve-SalesforceMetadata [-Manifest] <String> [-OutputDir] <String> [[-Wait] <Int32>] [-Unzip] [-SinglePackage] [[-ZipFileName] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf project retrieve start with --manifest and --target-metadata-dir, optionally unzipped. Both the manifest file and the output folder must exist.

#### Parameters

- `-Manifest` (String, required): File path for the manifest (package.xml) that specifies the components to retrieve. Passed to sf as --manifest. Required.
- `-OutputDir` (String, required): Folder that receives the retrieved package. Passed as --target-metadata-dir. Required.
- `-Wait` (Int32): Number of minutes to wait for the command to complete and display results to the terminal window. Passed to sf as --wait.
- `-Unzip` (switch): Extract the retrieved zip. Passed as --unzip.
- `-SinglePackage` (switch): Treat the manifest as a single package (the retrieved zip holds one package folder). Adds --single-package.
- `-ZipFileName` (String): File name of the retrieved zip. Passed as --zip-file-name. The CLI uses unpackaged.zip when omitted.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf project retrieve start`

#### Examples

```powershell
PS> Retrieve-SalesforceMetadata -Manifest manifest/package.xml -OutputDir .\retrieved -Unzip -TargetOrg dev1
```

Retrieve and unzip.

#### Remarks

- To see the examples, type: "Get-Help Retrieve-SalesforceMetadata -Examples"
- For more information, type: "Get-Help Retrieve-SalesforceMetadata -Detailed"
- For technical information, type: "Get-Help Retrieve-SalesforceMetadata -Full"
- For online help, type: "Get-Help Retrieve-SalesforceMetadata -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Retrieve-SalesforceOrg

#### Synopsis

Retrieves all the metadata of an org into the project.

#### Syntax

```powershell
Retrieve-SalesforceOrg [[-TargetOrg] <String>] [-IncludePackages] [<CommonParameters>]
```

#### Description

Runs two commands. First sf project generate manifest --from-org --name=allMetadata --output-dir . writes allMetadata.xml in the current folder; then sf project retrieve start --manifest allMetadata.xml retrieves everything it lists. This can take a long time on a large org.

#### Parameters

- `-TargetOrg` (String): Username or alias of the org to retrieve from. Passed as --from-org to sf project generate manifest and as --target-org to sf project retrieve start. If omitted, the CLI uses the default target org.
- `-IncludePackages` (switch): Also include the org's unlocked package contents. psfdx passes --include-packages=unlocked. Use New-SalesforceManifest for managed packages.

#### Salesforce CLI

- `sf project generate manifest`
- `sf project retrieve start`

#### Examples

```powershell
PS> Retrieve-SalesforceOrg -TargetOrg dev1
```

Write allMetadata.xml and retrieve all metadata.

#### Remarks

- To see the examples, type: "Get-Help Retrieve-SalesforceOrg -Examples"
- For more information, type: "Get-Help Retrieve-SalesforceOrg -Detailed"
- For technical information, type: "Get-Help Retrieve-SalesforceOrg -Full"
- For online help, type: "Get-Help Retrieve-SalesforceOrg -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Retrieve-SalesforcePackage

#### Synopsis

Retrieves a package's metadata into a folder.

#### Syntax

```powershell
Retrieve-SalesforcePackage [-Name] <String> [-OutputDir] <String> [[-Wait] <Int32>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf project retrieve start with --package-name and --output-dir. The output folder must exist.

#### Parameters

- `-Name` (String, required): Name of the package to retrieve. Passed as --package-name. Required.
- `-OutputDir` (String, required): Directory root for the retrieved source files. Passed to sf as --output-dir. Required.
- `-Wait` (Int32): Number of minutes to wait for the command to complete and display results to the terminal window. Passed to sf as --wait.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf project retrieve start`

#### Examples

```powershell
PS> Retrieve-SalesforcePackage -Name MyPackage -OutputDir .\pkg -TargetOrg dev1
```

Retrieve one package.

#### Remarks

- To see the examples, type: "Get-Help Retrieve-SalesforcePackage -Examples"
- For more information, type: "Get-Help Retrieve-SalesforcePackage -Detailed"
- For technical information, type: "Get-Help Retrieve-SalesforcePackage -Full"
- For online help, type: "Get-Help Retrieve-SalesforcePackage -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Retrieve-SalesforceValidationRule

#### Synopsis

Retrieves one validation rule into the project.

#### Syntax

```powershell
Retrieve-SalesforceValidationRule [-ObjectName] <String> [-RuleName] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

A shortcut for Retrieve-SalesforceComponent -Type ValidationRule with the object and rule name combined.

#### Parameters

- `-ObjectName` (String, required): API name of the object that holds the rule. Required.
- `-RuleName` (String, required): Name of the validation rule. Required.
- `-TargetOrg` (String): Username or alias of the org. If omitted, the Salesforce CLI uses the default target org.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Retrieve-SalesforceValidationRule -ObjectName Account -RuleName Require_Name -TargetOrg dev1
```

Retrieve one rule.

#### Remarks

- To see the examples, type: "Get-Help Retrieve-SalesforceValidationRule -Examples"
- For more information, type: "Get-Help Retrieve-SalesforceValidationRule -Detailed"
- For technical information, type: "Get-Help Retrieve-SalesforceValidationRule -Full"
- For online help, type: "Get-Help Retrieve-SalesforceValidationRule -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Metadata generation

### New-SalesforceCustomField

#### Synopsis

Creates the source files of a new custom field on an object in the project, asking questions.

#### Syntax

```powershell
New-SalesforceCustomField [-Label] <String> [[-ObjectDirectory] <String>] [<CommonParameters>]
```

#### Description

Runs sf schema generate field, which writes the metadata file of a custom field on a standard or custom object. The object's source files must already be in the project (retrieve them first if they are not). It is interactive: it asks you questions (the API name, plural label, field type and so on, with suggestions based on the label), so it needs a terminal and a Salesforce DX project folder. Run it as a plain command. If you assign its output to a variable or pipe it, PowerShell captures the output and you cannot see the questions. It returns nothing; the files it writes are the result.

#### Parameters

- `-Label` (String, required): Label of the field, for example Invoice Total. The command suggests the API name from it. Passed to sf as --label. Required.
- `-ObjectDirectory` (String): Folder that holds the object's source files, for example force-app/main/default/objects/Invoice__c. If you leave it out the command asks for the object. The folder must exist. Passed to sf as --object.

#### Salesforce CLI

- `sf schema generate field`

#### Examples

```powershell
PS> New-SalesforceCustomField -Label 'Invoice Total' -ObjectDirectory force-app/main/default/objects/Invoice__c
```

Add a field to the Invoice object and answer the questions about its type.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceCustomField -Examples"
- For more information, type: "Get-Help New-SalesforceCustomField -Detailed"
- For technical information, type: "Get-Help New-SalesforceCustomField -Full"
- For online help, type: "Get-Help New-SalesforceCustomField -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-sobject>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceCustomMetadataField

#### Synopsis

Creates the file of a new field of a custom metadata type.

#### Syntax

```powershell
New-SalesforceCustomMetadataField [-Name] <String> [-Type] <String> [[-Label] <String>] [[-DecimalPlaces] <Int32>] [[-PicklistValues] <String[]>] [[-OutputDirectory] <String>] [<CommonParameters>]
```

#### Description

Runs sf cmdt generate field, which writes a field definition file. Point -OutputDirectory at the type's folder, for example force-app/main/default/objects/MyCmdt__mdt, so the file lands in its fields folder. It works on local files and needs no org. A Picklist field needs -PicklistValues; -DecimalPlaces is for Number and Percent fields.

#### Parameters

- `-Name` (String, required): Unique API name of the field, without the __c suffix. Letters, digits and underscores only. Passed to sf as --name. Required.
- `-Type` (String, required): Type of the field. Valid values: Checkbox, Date, DateTime, Email, Number, Percent, Phone, Picklist, Text, TextArea, LongTextArea, Url. Passed to sf as --type. Required.
- `-Label` (String): Label of the field. By default the CLI uses the name. Passed to sf as --label.
- `-DecimalPlaces` (Int32): Number of decimal places, for a Number or Percent field. Passed to sf as --decimal-places.
- `-PicklistValues` (String[]): Values of a Picklist field. Each value is passed as its own --picklist-values. Required for a Picklist field. Passed to sf as --picklist-values.
- `-OutputDirectory` (String): Folder to write the field definition to. By default the CLI writes to a fields folder in the current folder. Passed to sf as --output-directory.

#### Salesforce CLI

- `sf cmdt generate field`

#### Examples

```powershell
PS> New-SalesforceCustomMetadataField -Name Mode -Type Picklist -PicklistValues On, Off, Auto -OutputDirectory force-app/main/default/objects/Feature_Flag__mdt
```

Add a picklist field to a type.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceCustomMetadataField -Examples"
- For more information, type: "Get-Help New-SalesforceCustomMetadataField -Detailed"
- For technical information, type: "Get-Help New-SalesforceCustomMetadataField -Full"
- For online help, type: "Get-Help New-SalesforceCustomMetadataField -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-custom-metadata>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceCustomMetadataRecord

#### Synopsis

Creates the file of a new record of a custom metadata type.

#### Syntax

```powershell
New-SalesforceCustomMetadataRecord [-TypeName] <String> [-RecordName] <String> [[-Label] <String>] [-Protected] [[-Values] <IDictionary>] [[-InputDirectory] <String>] [[-OutputDirectory] <String>] [<CommonParameters>]
```

#### Description

Runs sf cmdt generate record, which writes a record file. The type must already be in the project (-InputDirectory says where to read its definition from). Give the field values as a hashtable in -Values, for example @{ Color__c = 'Red'; Size__c = 32 }; each pair is passed to the CLI as Field=Value. It works on local files and needs no org.

#### Parameters

- `-TypeName` (String, required): API name of the custom metadata type. The CLI needs the __mdt suffix, for example MyCmdt__mdt. Passed to sf as --type-name. Required.
- `-RecordName` (String, required): Name of the new record. Passed to sf as --record-name. Required.
- `-Label` (String): Label of the record. By default the CLI uses the record name. Passed to sf as --label.
- `-Protected` (switch): Protect the record when it is in a managed package. The switch sends the value true; without it the CLI default, false, applies. Passed to sf as --protected.
- `-Values` (IDictionary): Field values as field name and value pairs. Field names are checked; a value may not contain a double quote or a line break. Each pair is passed to sf as Field=Value.
- `-InputDirectory` (String): Folder to read the type definition from. The CLI default is force-app/main/default/objects. The folder must exist. Passed to sf as --input-directory.
- `-OutputDirectory` (String): Folder to write the record to. The CLI default is force-app/main/default/customMetadata. Passed to sf as --output-directory.

#### Salesforce CLI

- `sf cmdt generate record`

#### Examples

```powershell
PS> New-SalesforceCustomMetadataRecord -TypeName Feature_Flag__mdt -RecordName Checkout -Label 'Checkout' -Values @{ Mode__c = 'On'; Threshold__c = 2.5 }
```

Create a record with two field values.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceCustomMetadataRecord -Examples"
- For more information, type: "Get-Help New-SalesforceCustomMetadataRecord -Detailed"
- For technical information, type: "Get-Help New-SalesforceCustomMetadataRecord -Full"
- For online help, type: "Get-Help New-SalesforceCustomMetadataRecord -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-custom-metadata>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceCustomMetadataRecordsFromCsv

#### Synopsis

Creates custom metadata record files from the rows of a CSV file.

#### Syntax

```powershell
New-SalesforceCustomMetadataRecordsFromCsv [-Csv] <String> [-TypeName] <String> [[-NameColumn] <String>] [[-InputDirectory] <String>] [[-OutputDirectory] <String>] [<CommonParameters>]
```

#### Description

Runs sf cmdt generate records, which writes one record file per CSV row. The type must already be in the project. The Name column gives each record its name unless you pick another with -NameColumn; the other columns are field names. It returns one object per record. It works on local files and needs no org.

#### Parameters

- `-Csv` (String, required): Path of the CSV file. The file must exist. Passed to sf as --csv. Required.
- `-TypeName` (String, required): API name of the custom metadata type. The CLI adds the __mdt suffix when it is left off. Passed to sf as --type-name. Required.
- `-NameColumn` (String): CSV column that gives each record its name. The CLI default is Name. Passed to sf as --name-column.
- `-InputDirectory` (String): Folder to read the type definition from. The CLI default is force-app/main/default/objects. The folder must exist. Passed to sf as --input-directory.
- `-OutputDirectory` (String): Folder to write the records to. The CLI default is force-app/main/default/customMetadata. Passed to sf as --output-directory.

#### Salesforce CLI

- `sf cmdt generate records`

#### Examples

```powershell
PS> New-SalesforceCustomMetadataRecordsFromCsv -Csv .\flags.csv -TypeName Feature_Flag -NameColumn Key
```

One record per row, named from the Key column.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceCustomMetadataRecordsFromCsv -Examples"
- For more information, type: "Get-Help New-SalesforceCustomMetadataRecordsFromCsv -Detailed"
- For technical information, type: "Get-Help New-SalesforceCustomMetadataRecordsFromCsv -Full"
- For online help, type: "Get-Help New-SalesforceCustomMetadataRecordsFromCsv -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-custom-metadata>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceCustomMetadataType

#### Synopsis

Creates the files of a new custom metadata type in the project.

#### Syntax

```powershell
New-SalesforceCustomMetadataType [-TypeName] <String> [[-Label] <String>] [[-PluralLabel] <String>] [[-Visibility] <String>] [[-OutputDirectory] <String>] [<CommonParameters>]
```

#### Description

Runs sf cmdt generate object, which writes the metadata file of a custom metadata type under a folder named &lt;TypeName&gt;__mdt. It works on local files and needs no org; run it inside a Salesforce DX project. Add fields with New-SalesforceCustomMetadataField and records with New-SalesforceCustomMetadataRecord. The result lists the type name, label, plural label and visibility.

#### Parameters

- `-TypeName` (String, required): Unique API name of the custom metadata type, without the __mdt suffix, for example MyCustomType. Letters, digits and underscores only. Passed to sf as --type-name. Required.
- `-Label` (String): Label of the type. By default the CLI uses the type name. Passed to sf as --label.
- `-PluralLabel` (String): Plural form of the label. By default the CLI uses the label. Passed to sf as --plural-label.
- `-Visibility` (String): Who can see the type. Valid values: PackageProtected, Protected, Public. The CLI default is Public. Passed to sf as --visibility.
- `-OutputDirectory` (String): Folder to write the type to, for example force-app/main/default/objects. By default the CLI writes to a &lt;TypeName&gt;__mdt folder in the current folder. Passed to sf as --output-directory.

#### Salesforce CLI

- `sf cmdt generate object`

#### Examples

```powershell
PS> New-SalesforceCustomMetadataType -TypeName Feature_Flag -Label 'Feature Flag' -PluralLabel 'Feature Flags' -Visibility Protected -OutputDirectory force-app/main/default/objects
```

Create a protected type in the project's objects folder.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceCustomMetadataType -Examples"
- For more information, type: "Get-Help New-SalesforceCustomMetadataType -Detailed"
- For technical information, type: "Get-Help New-SalesforceCustomMetadataType -Full"
- For online help, type: "Get-Help New-SalesforceCustomMetadataType -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-custom-metadata>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceCustomMetadataTypeFromOrg

#### Synopsis

Creates a custom metadata type, and a record for every row, from an object in an org.

#### Syntax

```powershell
New-SalesforceCustomMetadataTypeFromOrg [-DevName] <String> [-Sobject] <String> [[-Label] <String>] [[-PluralLabel] <String>] [[-Visibility] <String>] [-IgnoreUnsupported] [[-TypeOutputDirectory] <String>] [[-RecordsOutputDir] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf cmdt generate fromorg. It reads the fields and the records of a custom object or custom setting in the org and writes a custom metadata type with those fields and one record per row into the project, so you can move the data to custom metadata. A field of a type that custom metadata does not support becomes a text field, unless you pass -IgnoreUnsupported. Only local files are written; nothing in the org changes.

#### Parameters

- `-DevName` (String, required): API name for the new custom metadata type, without the __mdt suffix. Passed to sf as --dev-name. Required.
- `-Sobject` (String, required): API name of the object in the org to copy, for example My_Settings__c. Passed to sf as --sobject. Required.
- `-Label` (String): Label of the type. By default the CLI uses the name. Passed to sf as --label.
- `-PluralLabel` (String): Plural form of the label. By default the CLI uses the label. Passed to sf as --plural-label.
- `-Visibility` (String): Who can see the type. Valid values: PackageProtected, Protected, Public. The CLI default is Public. Passed to sf as --visibility.
- `-IgnoreUnsupported` (switch): Leave out fields of an unsupported type instead of turning them into text fields. Adds --ignore-unsupported.
- `-TypeOutputDirectory` (String): Folder to write the type to. The CLI default is force-app/main/default/objects. Passed to sf as --type-output-directory.
- `-RecordsOutputDir` (String): Folder to write the records to. The CLI default is force-app/main/default/customMetadata. Passed to sf as --records-output-dir.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf cmdt generate fromorg`

#### Examples

```powershell
PS> New-SalesforceCustomMetadataTypeFromOrg -DevName App_Config -Sobject App_Config__c -IgnoreUnsupported -TargetOrg dev1
```

Turn the App_Config__c custom setting into a custom metadata type.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceCustomMetadataTypeFromOrg -Examples"
- For more information, type: "Get-Help New-SalesforceCustomMetadataTypeFromOrg -Detailed"
- For technical information, type: "Get-Help New-SalesforceCustomMetadataTypeFromOrg -Full"
- For online help, type: "Get-Help New-SalesforceCustomMetadataTypeFromOrg -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-custom-metadata>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceCustomObject

#### Synopsis

Creates the source files of a new custom object in the project, asking questions.

#### Syntax

```powershell
New-SalesforceCustomObject [-Label] <String> [-UseDefaultFeatures] [<CommonParameters>]
```

#### Description

Runs sf schema generate sobject, which writes the metadata files of a custom object, with its Name field. It is interactive: it asks you questions (the API name, plural label, field type and so on, with suggestions based on the label), so it needs a terminal and a Salesforce DX project folder. Run it as a plain command. If you assign its output to a variable or pipe it, PowerShell captures the output and you cannot see the questions. It returns nothing; the files it writes are the result. Use -UseDefaultFeatures to switch on the optional features, such as reports and search, without being asked about each. To add fields afterwards use New-SalesforceCustomField.

#### Parameters

- `-Label` (String, required): Label of the custom object, for example My Object. The command suggests the API name and plural label from it. Passed to sf as --label. Required.
- `-UseDefaultFeatures` (switch): Turn on all the optional object features without asking. Adds --use-default-features.

#### Salesforce CLI

- `sf schema generate sobject`

#### Examples

```powershell
PS> New-SalesforceCustomObject -Label 'Invoice' -UseDefaultFeatures
```

Create the Invoice object and answer the rest of the questions at the prompt.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceCustomObject -Examples"
- For more information, type: "Get-Help New-SalesforceCustomObject -Detailed"
- For technical information, type: "Get-Help New-SalesforceCustomObject -Full"
- For online help, type: "Get-Help New-SalesforceCustomObject -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-sobject>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceCustomTab

#### Synopsis

Creates the source file of a new custom tab for a custom object.

#### Syntax

```powershell
New-SalesforceCustomTab [-ObjectName] <String> [-Directory] <String> [[-Icon] <Int32>] [<CommonParameters>]
```

#### Description

Runs sf schema generate tab, which writes a custom tab file. Unlike the other schema generators it asks no questions: everything comes from the parameters. Run it inside a Salesforce DX project. The custom object's own source files do not have to be in the project. It returns the CLI result as an object.

#### Parameters

- `-ObjectName` (String, required): API name of the custom object the tab is for, for example Invoice__c. Letters, digits and underscores only. Passed to sf as --object. Required.
- `-Directory` (String, required): Path of the tabs folder that will hold the tab file, for example force-app/main/default/tabs. The folder must already exist; the CLI does not create it. Passed to sf as --directory. Required.
- `-Icon` (Int32): Number from 1 to 100 that picks the tab's color scheme and icon. The CLI default is 1, which is also used here. Passed to sf as --icon.

#### Salesforce CLI

- `sf schema generate tab`

#### Examples

```powershell
PS> New-SalesforceCustomTab -ObjectName Invoice__c -Directory force-app/main/default/tabs -Icon 54
```

Create a tab for the Invoice object with icon 54.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceCustomTab -Examples"
- For more information, type: "Get-Help New-SalesforceCustomTab -Detailed"
- For technical information, type: "Get-Help New-SalesforceCustomTab -Full"
- For online help, type: "Get-Help New-SalesforceCustomTab -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-sobject>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceManifest

#### Synopsis

Writes a package.xml manifest from metadata names, local source or an org.

#### Syntax

```powershell
New-SalesforceManifest [[-Metadata] <String[]>] [[-ExcludedMetadata] <String[]>] [[-SourceDir] <String[]>] [[-FromOrg] <String>] [[-IncludePackages] <String[]>] [[-Name] <String>] [[-OutputDir] <String>] [[-Type] <String>] [<CommonParameters>]
```

#### Description

Runs sf project generate manifest and returns the CLI result (the path of the manifest written). Build the manifest from -Metadata names, from -SourceDir files, or from the metadata of an org with -FromOrg. Use -Type to write a destructive-changes or package manifest instead of package.xml. The output folder must already exist.

#### Parameters

- `-Metadata` (String[]): Metadata components to put in the manifest, such as ApexClass:MyClass. Passed as one --metadata per value.
- `-ExcludedMetadata` (String[]): Metadata types to leave out of a manifest built with -FromOrg. Passed as one --excluded-metadata per value.
- `-SourceDir` (String[]): Local source folders or files to build the manifest from. Passed as one --source-dir per value. Each path must exist.
- `-FromOrg` (String): Username or alias of an org to build the manifest from. Passed as --from-org.
- `-IncludePackages` (String[]): Also include the contents of managed or unlocked packages when building from an org. Valid values: managed, unlocked. Passed as one --include-packages per value.
- `-Name` (String): File name of the manifest, without the .xml extension. Passed as --name. The CLI chooses a name from -Type when omitted.
- `-OutputDir` (String): Folder that receives the manifest. It must exist. Passed as --output-dir.
- `-Type` (String): Kind of manifest to write. Valid values: pre, post, destroy, package. Passed as --type.

#### Salesforce CLI

- `sf project generate manifest`

#### Examples

```powershell
PS> New-SalesforceManifest -SourceDir force-app -Name package -OutputDir manifest
```

Write manifest/package.xml for everything in force-app.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceManifest -Examples"
- For more information, type: "Get-Help New-SalesforceManifest -Detailed"
- For technical information, type: "Get-Help New-SalesforceManifest -Full"
- For online help, type: "Get-Help New-SalesforceManifest -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-deploy-retrieve>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforcePlatformEvent

#### Synopsis

Creates the source files of a new platform event in the project, asking questions.

#### Syntax

```powershell
New-SalesforcePlatformEvent [-Label] <String> [<CommonParameters>]
```

#### Description

Runs sf schema generate platformevent, which writes the metadata file of a platform event. It is interactive: it asks you questions (the API name, plural label, field type and so on, with suggestions based on the label), so it needs a terminal and a Salesforce DX project folder. Run it as a plain command. If you assign its output to a variable or pipe it, PowerShell captures the output and you cannot see the questions. It returns nothing; the files it writes are the result.

#### Parameters

- `-Label` (String, required): Label of the platform event, for example Order Shipped. The command suggests the API name from it. Passed to sf as --label. Required.

#### Salesforce CLI

- `sf schema generate platformevent`

#### Examples

```powershell
PS> New-SalesforcePlatformEvent -Label 'Order Shipped'
```

Create the platform event and answer the rest of the questions at the prompt.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforcePlatformEvent -Examples"
- For more information, type: "Get-Help New-SalesforcePlatformEvent -Detailed"
- For technical information, type: "Get-Help New-SalesforcePlatformEvent -Full"
- For online help, type: "Get-Help New-SalesforcePlatformEvent -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-sobject>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>
