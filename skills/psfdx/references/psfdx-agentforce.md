# psfdx-agentforce command reference

Generated from the commands' own help by `site/Update-ModuleReference.ps1`: do not edit it by hand. The same reference is on the website: <https://psfdx.com/modules/psfdx-agentforce/>. It is part of the `psfdx` package; see the [installation guide](https://github.com/tonygward/psfdx/blob/main/docs/install.md).

44 commands. Every command also takes the common parameters, such as `-Verbose`.

## Commands

**Data libraries**: [Add-SalesforceAgentDataLibraryFile](#add-salesforceagentdatalibraryfile), [Get-SalesforceAgentDataLibraries](#get-salesforceagentdatalibraries), [Get-SalesforceAgentDataLibrary](#get-salesforceagentdatalibrary), [Get-SalesforceAgentDataLibraryFiles](#get-salesforceagentdatalibraryfiles), [Get-SalesforceAgentDataLibraryStatus](#get-salesforceagentdatalibrarystatus), [New-SalesforceAgentDataLibrary](#new-salesforceagentdatalibrary), [Remove-SalesforceAgentDataLibrary](#remove-salesforceagentdatalibrary), [Remove-SalesforceAgentDataLibraryFile](#remove-salesforceagentdatalibraryfile), [Send-SalesforceAgentDataLibraryFile](#send-salesforceagentdatalibraryfile), [Update-SalesforceAgentDataLibrary](#update-salesforceagentdatalibrary)

**Agent setup and authoring**: [Disable-SalesforceAgent](#disable-salesforceagent), [Enable-SalesforceAgent](#enable-salesforceagent), [New-SalesforceAgent](#new-salesforceagent), [New-SalesforceAgentAuthoringBundle](#new-salesforceagentauthoringbundle), [New-SalesforceAgentSpec](#new-salesforceagentspec), [New-SalesforceAgentTemplate](#new-salesforceagenttemplate), [New-SalesforceAgentUser](#new-salesforceagentuser), [Open-SalesforceAgent](#open-salesforceagent), [Publish-SalesforceAgentAuthoringBundle](#publish-salesforceagentauthoringbundle), [Test-SalesforceAgentAuthoringBundle](#test-salesforceagentauthoringbundle), [Test-SalesforceAgentPlugin](#test-salesforceagentplugin)

**Preview and traces**: [Get-SalesforceAgentPreviewSessions](#get-salesforceagentpreviewsessions), [Get-SalesforceAgentTraces](#get-salesforceagenttraces), [Invoke-SalesforceAgentPreview](#invoke-salesforceagentpreview), [Read-SalesforceAgentTrace](#read-salesforceagenttrace), [Remove-SalesforceAgentTrace](#remove-salesforceagenttrace), [Send-SalesforceAgentPreviewMessage](#send-salesforceagentpreviewmessage), [Start-SalesforceAgentPreview](#start-salesforceagentpreview), [Stop-SalesforceAgentPreview](#stop-salesforceagentpreview)

**Tests and evaluations**: [Get-SalesforceAgentTestResult](#get-salesforceagenttestresult), [Get-SalesforceAgentTests](#get-salesforceagenttests), [New-SalesforceAgentTest](#new-salesforceagenttest), [New-SalesforceAgentTestSpec](#new-salesforceagenttestspec), [Resume-SalesforceAgentTest](#resume-salesforceagenttest), [Start-SalesforceAgentEvaluation](#start-salesforceagentevaluation), [Start-SalesforceAgentTest](#start-salesforceagenttest)

**MCP servers and assets**: [Get-SalesforceMcpAssets](#get-salesforcemcpassets), [Get-SalesforceMcpServer](#get-salesforcemcpserver), [Get-SalesforceMcpServerLiveAssets](#get-salesforcemcpserverliveassets), [Get-SalesforceMcpServers](#get-salesforcemcpservers), [New-SalesforceMcpServer](#new-salesforcemcpserver), [Remove-SalesforceMcpServer](#remove-salesforcemcpserver), [Set-SalesforceMcpAssets](#set-salesforcemcpassets), [Update-SalesforceMcpServer](#update-salesforcemcpserver)

## Data libraries

### Add-SalesforceAgentDataLibraryFile

#### Synopsis

Adds files to an existing data library.

#### Syntax

```powershell
Add-SalesforceAgentDataLibraryFile [-LibraryId] <String> [-Path] <String[]> [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent adl file add for each path you give. Supports -WhatIf and -Confirm; it does not prompt by default. For an SFDRIVE library that you want to wait on, use Send-SalesforceAgentDataLibraryFile.

#### Parameters

- `-LibraryId` (String, required): ID of the data library. Passed to sf as --library-id. Required.
- `-Path` (String[], required): Files to add. Each is passed to sf as its own --path. Each must exist. Passed to sf as --path. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent adl file add`

#### Examples

```powershell
PS> Add-SalesforceAgentDataLibraryFile -LibraryId 1JDxx0000000001 -Path .\manual.pdf, .\faq.pdf -TargetOrg dev1
```

Add two files.

#### Remarks

- To see the examples, type: "Get-Help Add-SalesforceAgentDataLibraryFile -Examples"
- For more information, type: "Get-Help Add-SalesforceAgentDataLibraryFile -Detailed"
- For technical information, type: "Get-Help Add-SalesforceAgentDataLibraryFile -Full"
- For online help, type: "Get-Help Add-SalesforceAgentDataLibraryFile -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceAgentDataLibraries

#### Synopsis

Lists the Agentforce Data Libraries in an org.

#### Syntax

```powershell
Get-SalesforceAgentDataLibraries [[-SourceType] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent adl list and returns one object per library. It only reads.

#### Parameters

- `-SourceType` (String): Only libraries with this source. Valid values: sfdrive, knowledge, retriever. Passed to sf as --source-type.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent adl list`

#### Examples

```powershell
PS> Get-SalesforceAgentDataLibraries -SourceType sfdrive -TargetOrg dev1
```

The file-based libraries.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceAgentDataLibraries -Examples"
- For more information, type: "Get-Help Get-SalesforceAgentDataLibraries -Detailed"
- For technical information, type: "Get-Help Get-SalesforceAgentDataLibraries -Full"
- For online help, type: "Get-Help Get-SalesforceAgentDataLibraries -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceAgentDataLibrary

#### Synopsis

Shows the details of one Agentforce Data Library.

#### Syntax

```powershell
Get-SalesforceAgentDataLibrary [-LibraryId] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent adl get. It only reads.

#### Parameters

- `-LibraryId` (String, required): ID of the data library. Passed to sf as --library-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent adl get`

#### Examples

```powershell
PS> Get-SalesforceAgentDataLibrary -LibraryId 1JDxx0000000001 -TargetOrg dev1
```

The details of one library.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceAgentDataLibrary -Examples"
- For more information, type: "Get-Help Get-SalesforceAgentDataLibrary -Detailed"
- For technical information, type: "Get-Help Get-SalesforceAgentDataLibrary -Full"
- For online help, type: "Get-Help Get-SalesforceAgentDataLibrary -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceAgentDataLibraryFiles

#### Synopsis

Lists the files in a data library.

#### Syntax

```powershell
Get-SalesforceAgentDataLibraryFiles [-LibraryId] <String> [[-Status] <String>] [[-Offset] <Int32>] [[-PageSize] <Int32>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent adl file list and returns one object per file, with its status. It only reads. Use -Offset and -PageSize to page through a big library.

#### Parameters

- `-LibraryId` (String, required): ID of the data library. Passed to sf as --library-id. Required.
- `-Status` (String): Only files with this status. Valid values: uploaded, indexing, indexed, index_failed, deleting, delete_failed. Passed to sf as --status.
- `-Offset` (Int32): Number of files to skip, for paging. Passed to sf as --offset.
- `-PageSize` (Int32): Number of files to return. Passed to sf as --page-size.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent adl file list`

#### Examples

```powershell
PS> Get-SalesforceAgentDataLibraryFiles -LibraryId 1JDxx0000000001 -Status index_failed -TargetOrg dev1
```

The files that did not index.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceAgentDataLibraryFiles -Examples"
- For more information, type: "Get-Help Get-SalesforceAgentDataLibraryFiles -Detailed"
- For technical information, type: "Get-Help Get-SalesforceAgentDataLibraryFiles -Full"
- For online help, type: "Get-Help Get-SalesforceAgentDataLibraryFiles -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceAgentDataLibraryStatus

#### Synopsis

Shows the indexing status of a data library.

#### Syntax

```powershell
Get-SalesforceAgentDataLibraryStatus [-LibraryId] <String> [-IncludeArtifacts] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent adl status, which says whether the library's content is indexed and ready for an agent to use. It only reads.

#### Parameters

- `-LibraryId` (String, required): ID of the data library. Passed to sf as --library-id. Required.
- `-IncludeArtifacts` (switch): Also list the artifacts (indexes and related records) the indexing made. Adds --include-artifacts.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent adl status`

#### Examples

```powershell
PS> Get-SalesforceAgentDataLibraryStatus -LibraryId 1JDxx0000000001 -TargetOrg dev1
PS> Is the library indexed yet?
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceAgentDataLibraryStatus -Examples"
- For more information, type: "Get-Help Get-SalesforceAgentDataLibraryStatus -Detailed"
- For technical information, type: "Get-Help Get-SalesforceAgentDataLibraryStatus -Full"
- For online help, type: "Get-Help Get-SalesforceAgentDataLibraryStatus -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceAgentDataLibrary

#### Synopsis

Creates an Agentforce Data Library, the knowledge an agent is grounded in.

#### Syntax

```powershell
New-SalesforceAgentDataLibrary [-Name] <String> [-DeveloperName] <String> [-SourceType] <String> [[-Description] <String>] [[-IndexMode] <String>] [[-ContentFields] <String[]>] [[-DataCategoryIds] <String[]>] [[-DataCategoryNames] <String[]>] [[-PrimaryIndexField1] <String>] [[-PrimaryIndexField2] <String>] [[-RetrieverId] <String>] [[-WaitMinutes] <Int32>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent adl create. The source decides what the library holds: sfdrive (files you upload), knowledge (Salesforce Knowledge articles) or retriever (an existing retriever). Supports -WhatIf and -Confirm; it does not prompt by default. Without -WaitMinutes the CLI returns before indexing is done; check with Get-SalesforceAgentDataLibraryStatus.

#### Parameters

- `-Name` (String, required): Name (label) of the library. Passed to sf as --name. Required.
- `-DeveloperName` (String, required): API name of the library. Passed to sf as --developer-name. Required.
- `-SourceType` (String, required): Where the library's content comes from. Valid values: sfdrive, knowledge, retriever. Passed to sf as --source-type. Required.
- `-Description` (String): Description of the library. Passed to sf as --description.
- `-IndexMode` (String): How the content is indexed. Valid values: basic, enhanced. Passed to sf as --index-mode.
- `-ContentFields` (String[]): Knowledge fields to index. For a knowledge library. The values are joined with commas and passed as one --content-fields.
- `-DataCategoryIds` (String[]): IDs of the data categories to include. For a knowledge library. The values are joined with commas and passed as one --data-category-ids. Use it or -DataCategoryNames, not both.
- `-DataCategoryNames` (String[]): Names of the data categories to include. Qualified names such as Group_API_Name.Category, for a knowledge library. The values are joined with commas and passed as one --data-category-names. Use it or -DataCategoryIds, not both.
- `-PrimaryIndexField1` (String): First field of the primary index. For a retriever library. Passed to sf as --primary-index-field1.
- `-PrimaryIndexField2` (String): Second field of the primary index. For a retriever library. Passed to sf as --primary-index-field2.
- `-RetrieverId` (String): ID of the retriever. For a retriever library. Passed to sf as --retriever-id.
- `-WaitMinutes` (Int32): Number of minutes to wait for the library to be created. Passed to sf as --wait.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent adl create`

#### Examples

```powershell
PS> New-SalesforceAgentDataLibrary -Name 'Product Manuals' -DeveloperName Product_Manuals -SourceType sfdrive -WaitMinutes 5 -TargetOrg dev1
```

Create a library for uploaded files.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceAgentDataLibrary -Examples"
- For more information, type: "Get-Help New-SalesforceAgentDataLibrary -Detailed"
- For technical information, type: "Get-Help New-SalesforceAgentDataLibrary -Full"
- For online help, type: "Get-Help New-SalesforceAgentDataLibrary -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceAgentDataLibrary

#### Synopsis

Deletes an Agentforce Data Library.

#### Syntax

```powershell
Remove-SalesforceAgentDataLibrary [-LibraryId] <String> [-NoPrompt] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent adl delete. Agents that use the library lose that knowledge, and this cannot be undone. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. The CLI command has no prompt of its own.

#### Parameters

- `-LibraryId` (String, required): ID of the data library. Passed to sf as --library-id. Required.
- `-NoPrompt` (switch): Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent adl delete`

#### Examples

```powershell
PS> Remove-SalesforceAgentDataLibrary -LibraryId 1JDxx0000000001 -TargetOrg dev1 -WhatIf
```

Preview the delete.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceAgentDataLibrary -Examples"
- For more information, type: "Get-Help Remove-SalesforceAgentDataLibrary -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceAgentDataLibrary -Full"
- For online help, type: "Get-Help Remove-SalesforceAgentDataLibrary -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceAgentDataLibraryFile

#### Synopsis

Deletes one file from a data library.

#### Syntax

```powershell
Remove-SalesforceAgentDataLibraryFile [-LibraryId] <String> [-FileId] <String> [-NoPrompt] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent adl file delete. This cannot be undone. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. The CLI command has no prompt of its own.

#### Parameters

- `-LibraryId` (String, required): ID of the data library. Passed to sf as --library-id. Required.
- `-FileId` (String, required): ID of the file to delete, from Get-SalesforceAgentDataLibraryFiles. Passed to sf as --file-id. Required.
- `-NoPrompt` (switch): Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent adl file delete`

#### Examples

```powershell
PS> Remove-SalesforceAgentDataLibraryFile -LibraryId 1JDxx0000000001 -FileId 0Pexx0000000001 -TargetOrg dev1 -WhatIf
```

Preview the delete.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceAgentDataLibraryFile -Examples"
- For more information, type: "Get-Help Remove-SalesforceAgentDataLibraryFile -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceAgentDataLibraryFile -Full"
- For online help, type: "Get-Help Remove-SalesforceAgentDataLibraryFile -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Send-SalesforceAgentDataLibraryFile

#### Synopsis

Uploads files to an SFDRIVE data library.

#### Syntax

```powershell
Send-SalesforceAgentDataLibraryFile [-LibraryId] <String> [-File] <String[]> [[-WaitMinutes] <Int32>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent adl upload, which uploads local files to a library whose source is sfdrive and can wait for them to be indexed. Supports -WhatIf and -Confirm; it does not prompt by default.

#### Parameters

- `-LibraryId` (String, required): ID of the data library. Passed to sf as --library-id. Required.
- `-File` (String[], required): Files to upload. Each is passed to sf as its own --file. Each must exist. Passed to sf as --file. Required.
- `-WaitMinutes` (Int32): Number of minutes to wait for the upload and indexing. Passed to sf as --wait.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent adl upload`

#### Examples

```powershell
PS> Send-SalesforceAgentDataLibraryFile -LibraryId 1JDxx0000000001 -File .\manual.pdf -WaitMinutes 10 -TargetOrg dev1
```

Upload a file and wait.

#### Remarks

- To see the examples, type: "Get-Help Send-SalesforceAgentDataLibraryFile -Examples"
- For more information, type: "Get-Help Send-SalesforceAgentDataLibraryFile -Detailed"
- For technical information, type: "Get-Help Send-SalesforceAgentDataLibraryFile -Full"
- For online help, type: "Get-Help Send-SalesforceAgentDataLibraryFile -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Update-SalesforceAgentDataLibrary

#### Synopsis

Changes the settings of a data library.

#### Syntax

```powershell
Update-SalesforceAgentDataLibrary [-LibraryId] <String> [[-Name] <String>] [[-Description] <String>] [[-ContentFields] <String[]>] [[-RetrieverId] <String>] [-DataCategoryRule] [-RestrictToPublicArticles] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent adl update. Only the settings you give are changed. Supports -WhatIf and -Confirm; it does not prompt by default.

#### Parameters

- `-LibraryId` (String, required): ID of the data library. Passed to sf as --library-id. Required.
- `-Name` (String): New name (label). Passed to sf as --name.
- `-Description` (String): New description. Passed to sf as --description.
- `-ContentFields` (String[]): Knowledge fields to index. The values are joined with commas and passed as one --content-fields.
- `-RetrieverId` (String): ID of the retriever, for a retriever library. Passed to sf as --retriever-id.
- `-DataCategoryRule` (switch): Turn on the data category rule of a knowledge library. Adds --data-category-rule; -DataCategoryRule:$false sends --no-data-category-rule to turn it off.
- `-RestrictToPublicArticles` (switch): Index only public articles of a knowledge library. Adds --restrict-to-public-articles; -RestrictToPublicArticles:$false sends --no-restrict-to-public-articles to turn it off.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent adl update`

#### Examples

```powershell
PS> Update-SalesforceAgentDataLibrary -LibraryId 1JDxx0000000001 -Description 'Current manuals' -TargetOrg dev1 -WhatIf
```

Preview the change.

#### Remarks

- To see the examples, type: "Get-Help Update-SalesforceAgentDataLibrary -Examples"
- For more information, type: "Get-Help Update-SalesforceAgentDataLibrary -Detailed"
- For technical information, type: "Get-Help Update-SalesforceAgentDataLibrary -Full"
- For online help, type: "Get-Help Update-SalesforceAgentDataLibrary -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Agent setup and authoring

### Disable-SalesforceAgent

#### Synopsis

Deactivates an Agentforce agent in an org.

#### Syntax

```powershell
Disable-SalesforceAgent [-ApiName] <String> [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent deactivate for the agent API name. The plugin @salesforce/plugin-agent must be installed; the cmdlet stops with install guidance if it is not. Asks for confirmation and supports -WhatIf.

#### Parameters

- `-ApiName` (String, required): API name of the agent to deactivate; if not specified, the command provides a list that you choose from. Passed to sf as --api-name. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent deactivate`

#### Examples

```powershell
PS> Disable-SalesforceAgent -ApiName Service_Agent -TargetOrg dev1 -WhatIf
```

Show what would be deactivated.

#### Remarks

- To see the examples, type: "Get-Help Disable-SalesforceAgent -Examples"
- For more information, type: "Get-Help Disable-SalesforceAgent -Detailed"
- For technical information, type: "Get-Help Disable-SalesforceAgent -Full"
- For online help, type: "Get-Help Disable-SalesforceAgent -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Enable-SalesforceAgent

#### Synopsis

Activates an Agentforce agent in an org.

#### Syntax

```powershell
Enable-SalesforceAgent [-ApiName] <String> [[-Version] <Int32>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent activate for the agent API name and, optionally, a version. Activating makes the agent available to users. Needs the @salesforce/plugin-agent plugin. Asks for confirmation and supports -WhatIf.

#### Parameters

- `-ApiName` (String, required): API name of the agent to activate; if not specified, the command provides a list that you choose from. Passed to sf as --api-name. Required.
- `-Version` (Int32): Version number of the agent to activate; if not specified, the command provides a list that you choose from. Passed to sf as --version. Range: 1 to 9999.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent activate`

#### Examples

```powershell
PS> Enable-SalesforceAgent -ApiName Service_Agent -Version 2 -TargetOrg dev1 -WhatIf
```

Preview activating version 2.

#### Remarks

- To see the examples, type: "Get-Help Enable-SalesforceAgent -Examples"
- For more information, type: "Get-Help Enable-SalesforceAgent -Detailed"
- For technical information, type: "Get-Help Enable-SalesforceAgent -Full"
- For online help, type: "Get-Help Enable-SalesforceAgent -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceAgent

#### Synopsis

Creates an agent in an org from a local agent spec file.

#### Syntax

```powershell
New-SalesforceAgent [[-Spec] <String>] [[-Name] <String>] [[-ApiName] <String>] [-Preview] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent create. The agent spec is the YAML file made by New-SalesforceAgentSpec. With -Preview the CLI shows what it would create without creating it. Supports -WhatIf and -Confirm; it does not prompt by default.

#### Parameters

- `-Spec` (String): Path of the agent spec YAML file. It must exist. Passed to sf as --spec.
- `-Name` (String): Name (label) of the agent. By default the CLI uses the name in the spec. Passed to sf as --name.
- `-ApiName` (String): API name of the new agent. By default the CLI derives it from the name. Passed to sf as --api-name.
- `-Preview` (switch): Show what would be created, without creating the agent. Adds --preview.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent create`

#### Examples

```powershell
PS> New-SalesforceAgent -Spec .\specs\service-agent.yaml -Name 'Service Agent' -TargetOrg dev1 -WhatIf
```

Preview the create.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceAgent -Examples"
- For more information, type: "Get-Help New-SalesforceAgent -Detailed"
- For technical information, type: "Get-Help New-SalesforceAgent -Full"
- For online help, type: "Get-Help New-SalesforceAgent -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceAgentAuthoringBundle

#### Synopsis

Generates an authoring bundle (Agent Script) for an agent (sf agent generate authoring-bundle).

#### Syntax

```powershell
New-SalesforceAgentAuthoringBundle [-Name] <String> [[-ApiName] <String>] [[-Spec] <String>] [-NoSpec] [[-OutputDir] <String>] [-ForceOverwrite] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Writes files into the project, so it asks for confirmation and supports -WhatIf. The CLI requires -Name (the agent label) and either -Spec (an agent spec file made by the agent plugin) or -NoSpec to generate a blank bundle; both are checked before the CLI is called. -OutputDir is where the bundle goes (the CLI default is the project's authoring bundle folder). Returns the CLI result, which includes the paths written. Needs the @salesforce/plugin-agent plugin, a recent version, and Agentforce enabled in the org.

#### Parameters

- `-Name` (String, required): Name (label) of the authoring bundle; if not specified, you're prompted for the name. Passed to sf as --name. Required.
- `-ApiName` (String): API name of the new authoring bundle; if not specified, the API name is derived from the authoring bundle name (label); the API name can't exist in the org. Passed to sf as --api-name.
- `-Spec` (String): Path to the agent spec YAML file. If you don't specify the flag, the command provides a list that you can choose from. Use the --no-spec flag to skip using an agent spec entirely.
- `-NoSpec` (switch): Skip prompting for an agent spec and use the default Agent Script boilerplate in the generated authoring bundle. Adds --no-spec.
- `-OutputDir` (String): Directory where the authoring bundle files are generated. Passed to sf as --output-dir.
- `-ForceOverwrite` (switch): Overwrite an existing authoring bundle of that name without asking. Without it the CLI refuses to replace one. Adds --force-overwrite.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent generate authoring-bundle`

#### Examples

```powershell
PS> New-SalesforceAgentAuthoringBundle -Name 'Service Agent' -ApiName Service_Agent -Spec specs/agentSpec.yaml -TargetOrg my-org
```

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceAgentAuthoringBundle -Examples"
- For more information, type: "Get-Help New-SalesforceAgentAuthoringBundle -Detailed"
- For technical information, type: "Get-Help New-SalesforceAgentAuthoringBundle -Full"
- For online help, type: "Get-Help New-SalesforceAgentAuthoringBundle -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceAgentSpec

#### Synopsis

Generates an agent spec: a YAML file that describes what an agent can do, with AI-suggested topics.

#### Syntax

```powershell
New-SalesforceAgentSpec [[-Role] <String>] [[-CompanyName] <String>] [[-CompanyDescription] <String>] [[-CompanyWebsite] <String>] [[-Type] <String>] [[-Tone] <String>] [[-AgentUser] <String>] [[-MaxTopics] <Int32>] [[-GroundingContext] <String>] [[-PromptTemplate] <String>] [[-EnrichLogs] <String>] [[-Spec] <String>] [[-OutputFile] <String>] [-ForceOverwrite] [-FullInterview] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent generate agent-spec. The model of your org uses the role and company details to propose the agent's topics; edit the file afterwards, then create the agent with New-SalesforceAgent. Give the details as parameters and the cmdlet returns the CLI result. With -FullInterview the CLI asks for every property, so it is interactive: it needs a terminal, and you should run it as a plain command (an assigned or piped result hides the questions). To improve an existing spec, give it as -Spec.

#### Parameters

- `-Role` (String): The role of the agent in your company. Passed to sf as --role.
- `-CompanyName` (String): Name of your company. Passed to sf as --company-name.
- `-CompanyDescription` (String): Description of your company. Passed to sf as --company-description.
- `-CompanyWebsite` (String): Website of your company. Passed to sf as --company-website.
- `-Type` (String): Kind of agent. Valid values: customer, internal. Passed to sf as --type.
- `-Tone` (String): Tone of the agent. Valid values: formal, casual, neutral. Passed to sf as --tone.
- `-AgentUser` (String): User name of the agent user that the agent runs as. Passed to sf as --agent-user.
- `-MaxTopics` (Int32): Number of topics to propose. Passed to sf as --max-topics.
- `-GroundingContext` (String): Extra text that grounds the model, such as products or policies. Passed to sf as --grounding-context.
- `-PromptTemplate` (String): API name of the prompt template to use to generate the topics. Passed to sf as --prompt-template.
- `-EnrichLogs` (String): Whether to add the generated data to the agent logs. Valid values: true, false. Passed to sf as --enrich-logs.
- `-Spec` (String): An existing spec file to improve. It must exist. Passed to sf as --spec.
- `-OutputFile` (String): File to write the spec to. The CLI default is specs/agentSpec.yaml. The folder must exist. Passed to sf as --output-file.
- `-ForceOverwrite` (switch): Overwrite the output file without asking if it already exists. Adds --force-overwrite.
- `-FullInterview` (switch): Let the CLI ask for every property. Interactive: needs a terminal. Adds --full-interview.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent generate agent-spec`

#### Examples

```powershell
PS> New-SalesforceAgentSpec -Role 'Answers order questions' -CompanyName Acme -CompanyDescription 'We sell anvils' -Type customer -Tone casual -OutputFile .\specs\orders.yaml -TargetOrg dev1
```

Generate a spec without any questions.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceAgentSpec -Examples"
- For more information, type: "Get-Help New-SalesforceAgentSpec -Detailed"
- For technical information, type: "Get-Help New-SalesforceAgentSpec -Full"
- For online help, type: "Get-Help New-SalesforceAgentSpec -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceAgentTemplate

#### Synopsis

Generates an agent template from an agent in the project, to package in a managed package.

#### Syntax

```powershell
New-SalesforceAgentTemplate [-AgentFile] <String> [-AgentVersion] <Int32> [-SourceOrg] <String> [[-OutputDir] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent generate template. It reads the agent from the project and the org it came from, and writes a template that you can put in a second-generation managed package so others can install it. It writes local files and reads the source org.

#### Parameters

- `-AgentFile` (String, required): Path of the agent's bot metadata file in the project. It must exist. Passed to sf as --agent-file. Required.
- `-AgentVersion` (Int32, required): Version of the agent to turn into a template. Passed to sf as --agent-version. Required.
- `-SourceOrg` (String, required): Username or alias of the org the agent was retrieved from. Passed to sf as --source-org. Required.
- `-OutputDir` (String): Folder to write the template to. The CLI default is the project's default package folder. Passed to sf as --output-dir.

#### Salesforce CLI

- `sf agent generate template`

#### Examples

```powershell
PS> New-SalesforceAgentTemplate -AgentFile force-app/main/default/bots/Service_Agent/Service_Agent.bot-meta.xml -AgentVersion 1 -SourceOrg dev1
```

Generate a template from version 1 of the agent.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceAgentTemplate -Examples"
- For more information, type: "Get-Help New-SalesforceAgentTemplate -Detailed"
- For technical information, type: "Get-Help New-SalesforceAgentTemplate -Full"
- For online help, type: "Get-Help New-SalesforceAgentTemplate -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceAgentUser

#### Synopsis

Creates the default user that an agent runs as.

#### Syntax

```powershell
New-SalesforceAgentUser [[-BaseUsername] <String>] [[-FirstName] <String>] [[-LastName] <String>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf org create agent-user, which creates the Einstein Agent user an agent uses to run its actions. Without the name parameters the CLI picks defaults. Supports -WhatIf and -Confirm; it does not prompt by default.

#### Parameters

- `-BaseUsername` (String): User name to base the new agent user's name on. The CLI adds a unique suffix. Passed to sf as --base-username.
- `-FirstName` (String): First name of the agent user. Passed to sf as --first-name.
- `-LastName` (String): Last name of the agent user. Passed to sf as --last-name.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org create agent-user`

#### Examples

```powershell
PS> New-SalesforceAgentUser -FirstName Service -LastName Agent -TargetOrg dev1 -WhatIf
```

Preview creating the agent user.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceAgentUser -Examples"
- For more information, type: "Get-Help New-SalesforceAgentUser -Detailed"
- For technical information, type: "Get-Help New-SalesforceAgentUser -Full"
- For online help, type: "Get-Help New-SalesforceAgentUser -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Open-SalesforceAgent

#### Synopsis

Opens an agent in Agentforce Builder, or prints the link.

#### Syntax

```powershell
Open-SalesforceAgent [[-ApiName] <String>] [[-AuthoringBundle] <String>] [[-Version] <Int32>] [[-Browser] <String>] [-BrowserPrivateMode] [-UrlOnly] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf org open agent. The URL contains a session token, so treat it like a password; -UrlOnly prints it instead of opening a browser. Give -ApiName for a published agent or -AuthoringBundle for a local Agent Script agent.

#### Parameters

- `-ApiName` (String): API name of the agent to open. Use it or -AuthoringBundle, not both. Passed to sf as --api-name.
- `-AuthoringBundle` (String): API name of the authoring bundle to open. Use it or -ApiName, not both. Passed to sf as --authoring-bundle.
- `-Version` (Int32): Version of the agent to open. Passed to sf as --version.
- `-Browser` (String): Browser to open the agent in. Valid values: chrome, edge, firefox. Passed to sf as --browser.
- `-BrowserPrivateMode` (switch): Open the agent in the browser's private (incognito) mode. Adds --private.
- `-UrlOnly` (switch): Show the URL but do not open a browser. Adds --url-only.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf org open agent`

#### Examples

```powershell
PS> Open-SalesforceAgent -ApiName Service_Agent -UrlOnly -TargetOrg dev1
```

Print the Builder link of a published agent.

#### Remarks

- To see the examples, type: "Get-Help Open-SalesforceAgent -Examples"
- For more information, type: "Get-Help Open-SalesforceAgent -Detailed"
- For technical information, type: "Get-Help Open-SalesforceAgent -Full"
- For online help, type: "Get-Help Open-SalesforceAgent -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Publish-SalesforceAgentAuthoringBundle

#### Synopsis

Publishes an authoring bundle to the org as an agent (sf agent publish authoring-bundle).

#### Syntax

```powershell
Publish-SalesforceAgentAuthoringBundle [-ApiName] <String> [-SkipRetrieve] [-Concise] [-ExtendedDetails] [[-SourceType] <String>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Changes the org, so it asks for confirmation and supports -WhatIf. Returns the CLI result (the published agent). By default the CLI retrieves the published agent metadata afterwards; -SkipRetrieve turns that off. Validate first with Test-SalesforceAgentAuthoringBundle.

#### Parameters

- `-ApiName` (String, required): API name of the authoring bundle you want to publish; if not specified, the command provides a list that you can choose from. Passed to sf as --api-name. Required.
- `-SkipRetrieve` (switch): Don't retrieve the metadata associated with the agent to your DX project. Adds --skip-retrieve.
- `-Concise` (switch): Show a short summary of the publish instead of the full detail. Adds --concise.
- `-ExtendedDetails` (switch): Show more detail of the publish, such as each step. Adds --verbose. Cannot be used with -Concise.
- `-SourceType` (String): The kind of agent source that is published. Passed to sf as --source-type. Valid value: Bot, which is also the CLI default.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent publish authoring-bundle`

#### Examples

```powershell
PS> Publish-SalesforceAgentAuthoringBundle -ApiName Service_Agent -TargetOrg my-org
```

#### Remarks

- To see the examples, type: "Get-Help Publish-SalesforceAgentAuthoringBundle -Examples"
- For more information, type: "Get-Help Publish-SalesforceAgentAuthoringBundle -Detailed"
- For technical information, type: "Get-Help Publish-SalesforceAgentAuthoringBundle -Full"
- For online help, type: "Get-Help Publish-SalesforceAgentAuthoringBundle -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Test-SalesforceAgentAuthoringBundle

#### Synopsis

Validates an authoring bundle and returns the diagnostics as objects (sf agent validate authoring-bundle).

#### Syntax

```powershell
Test-SalesforceAgentAuthoringBundle [-ApiName] <String> [-ThrowOnInvalid] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Read-only. Returns Valid, ApiName and Diagnostics (Message, Line, Column, Severity). Invalid Agent Script is returned as Valid = $false with its diagnostics, not thrown, so a script can print or filter them; add -ThrowOnInvalid to fail a CI step (error id PsfdxAgentValidationFailed, with the result as the target object). Failures that are not validation problems, such as an unknown org, always throw.

#### Parameters

- `-ApiName` (String, required): API name of the authoring bundle you want to validate; if not specified, the command provides a list that you can choose from. Passed to sf as --api-name. Required.
- `-ThrowOnInvalid` (switch): Throw an error (id PsfdxAgentValidationFailed, with the result as its target object) when the bundle is not valid, instead of returning Valid = $false with its diagnostics. Meant for CI.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent validate authoring-bundle`

#### Examples

```powershell
PS> $v = Test-SalesforceAgentAuthoringBundle -ApiName Service_Agent -TargetOrg my-org; $v.Diagnostics | Format-Table Line, Message
```

#### Remarks

- To see the examples, type: "Get-Help Test-SalesforceAgentAuthoringBundle -Examples"
- For more information, type: "Get-Help Test-SalesforceAgentAuthoringBundle -Detailed"
- For technical information, type: "Get-Help Test-SalesforceAgentAuthoringBundle -Full"
- For online help, type: "Get-Help Test-SalesforceAgentAuthoringBundle -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Test-SalesforceAgentPlugin

#### Synopsis

Checks whether the Salesforce CLI agent plugin is installed.

#### Syntax

```powershell
Test-SalesforceAgentPlugin [<CommonParameters>]
```

#### Description

Runs sf plugins --core --json and returns $true when @salesforce/plugin-agent is listed, otherwise $false. The other agent cmdlets run this check first.

#### Salesforce CLI

- `sf plugins`

#### Examples

```powershell
PS> if (-not (Test-SalesforceAgentPlugin)) { Install-SalesforcePlugin -Name @salesforce/plugin-agent }
```

Install the plugin when it is missing.

#### Remarks

- To see the examples, type: "Get-Help Test-SalesforceAgentPlugin -Examples"
- For more information, type: "Get-Help Test-SalesforceAgentPlugin -Detailed"
- For technical information, type: "Get-Help Test-SalesforceAgentPlugin -Full"
- For online help, type: "Get-Help Test-SalesforceAgentPlugin -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/oclif/plugin-plugins>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Preview and traces

### Get-SalesforceAgentPreviewSessions

#### Synopsis

Lists the preview sessions that are still open.

#### Syntax

```powershell
Get-SalesforceAgentPreviewSessions [<CommonParameters>]
```

#### Description

Runs sf agent preview sessions and returns one object per known programmatic preview session (its ID and the agent). It reads local session records, so it needs no org.

#### Salesforce CLI

- `sf agent preview sessions`

#### Examples

```powershell
PS> Get-SalesforceAgentPreviewSessions
```

Every open session.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceAgentPreviewSessions -Examples"
- For more information, type: "Get-Help Get-SalesforceAgentPreviewSessions -Detailed"
- For technical information, type: "Get-Help Get-SalesforceAgentPreviewSessions -Full"
- For online help, type: "Get-Help Get-SalesforceAgentPreviewSessions -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceAgentTraces

#### Synopsis

Lists the trace files recorded during agent preview sessions.

#### Syntax

```powershell
Get-SalesforceAgentTraces [[-Agent] <String>] [[-SessionId] <String>] [[-Since] <DateTime>] [<CommonParameters>]
```

#### Description

Runs sf agent trace list. Trace files record how an agent handled each turn of a preview. It reads local files and needs no org.

#### Parameters

- `-Agent` (String): Only traces of the agent with this API name (a published agent or an authoring bundle). Passed to sf as --agent.
- `-SessionId` (String): Only traces of this preview session. Passed to sf as --session-id.
- `-Since` (DateTime): Only traces recorded on or after this date. It is sent as a date in the form yyyy-MM-dd. Passed to sf as --since.

#### Salesforce CLI

- `sf agent trace list`

#### Examples

```powershell
PS> Get-SalesforceAgentTraces -Agent Service_Agent -Since (Get-Date).AddDays(-7)
```

Last week's traces of an agent.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceAgentTraces -Examples"
- For more information, type: "Get-Help Get-SalesforceAgentTraces -Detailed"
- For technical information, type: "Get-Help Get-SalesforceAgentTraces -Full"
- For online help, type: "Get-Help Get-SalesforceAgentTraces -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Invoke-SalesforceAgentPreview

#### Synopsis

Talks to an agent in the terminal to see how it responds.

#### Syntax

```powershell
Invoke-SalesforceAgentPreview [[-ApiName] <String>] [[-AuthoringBundle] <String>] [[-ContextVariables] <IDictionary>] [[-ContextVariablesJson] <String>] [-ApexDebug] [-UseLiveActions] [[-OutputDir] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent preview, the CLI version of the Preview panel in Agentforce Builder: you type utterances and read the answers. It is interactive, so it needs a terminal, and you should run it as a plain command (an assigned or piped result hides the conversation). Without -ApiName or -AuthoringBundle the CLI lets you pick an agent. For a conversation driven by a script use Start-SalesforceAgentPreview.

#### Parameters

- `-ApiName` (String): API name of a published, activated agent. Use it or -AuthoringBundle, not both. Passed to sf as --api-name.
- `-AuthoringBundle` (String): API name of a local authoring bundle (an Agent Script agent in the project). Use it or -ApiName, not both. Passed to sf as --authoring-bundle.
- `-ContextVariables` (IDictionary): Context variables for the conversation as name and value pairs. Each pair is passed to sf as its own --context-variables name=value. Names are checked, and a value may not contain a double quote or line break. Cannot be used with -ContextVariablesJson. Passed to sf as --context-variables.
- `-ContextVariablesJson` (String): Context variables as a JSON string, for example '{"order":"1001"}'. It must be valid JSON. On Windows the CLI's .cmd launcher cannot take an argument with double quotes, which JSON always has, so this does not work there: use -ContextVariables. Cannot be used with -ContextVariables. Passed to sf as --context-variables-json.
- `-ApexDebug` (switch): Show Apex debug logs of the agent's actions. Adds --apex-debug.
- `-UseLiveActions` (switch): Run the real actions of the agent, which can change data. Only for an authoring bundle. Adds --use-live-actions.
- `-OutputDir` (String): Folder to save the conversation transcript and traces to. Passed to sf as --output-dir.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent preview`

#### Examples

```powershell
PS> Invoke-SalesforceAgentPreview -ApiName Service_Agent -TargetOrg dev1
```

Chat with a published agent.

#### Remarks

- To see the examples, type: "Get-Help Invoke-SalesforceAgentPreview -Examples"
- For more information, type: "Get-Help Invoke-SalesforceAgentPreview -Detailed"
- For technical information, type: "Get-Help Invoke-SalesforceAgentPreview -Full"
- For online help, type: "Get-Help Invoke-SalesforceAgentPreview -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Read-SalesforceAgentTrace

#### Synopsis

Reads the trace of a preview session: what the agent did in each turn.

#### Syntax

```powershell
Read-SalesforceAgentTrace [-SessionId] <String> [[-Format] <String>] [[-Dimension] <String>] [[-Turn] <Int32>] [<CommonParameters>]
```

#### Description

Runs sf agent trace read. -Format picks how much you get: summary (the default), detail, or raw. With -Format detail, -Dimension narrows it to one kind of question. A turn is one utterance and response, counted from 1. It reads local files and needs no org.

#### Parameters

- `-SessionId` (String, required): ID of the preview session to read. Passed to sf as --session-id. Required.
- `-Format` (String): How much to show. Valid values: summary, detail, raw. The CLI default is summary. Passed to sf as --format.
- `-Dimension` (String): What to look at with -Format detail. Valid values: actions, grounding, routing, errors. Passed to sf as --dimension.
- `-Turn` (Int32): Only this turn, counted from 1. Passed to sf as --turn.

#### Salesforce CLI

- `sf agent trace read`

#### Examples

```powershell
PS> Read-SalesforceAgentTrace -SessionId $session.sessionId -Format detail -Dimension routing
```

How the agent routed each turn.

#### Remarks

- To see the examples, type: "Get-Help Read-SalesforceAgentTrace -Examples"
- For more information, type: "Get-Help Read-SalesforceAgentTrace -Detailed"
- For technical information, type: "Get-Help Read-SalesforceAgentTrace -Full"
- For online help, type: "Get-Help Read-SalesforceAgentTrace -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceAgentTrace

#### Synopsis

Deletes trace files of preview sessions.

#### Syntax

```powershell
Remove-SalesforceAgentTrace [[-Agent] <String>] [[-SessionId] <String>] [[-OlderThan] <String>] [-NoPrompt] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent trace delete for the traces that match -Agent, -SessionId and -OlderThan. At least one filter is needed, so a call cannot delete every trace by accident. This cannot be undone. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time. It only touches local files.

#### Parameters

- `-Agent` (String): Only traces of the agent with this API name. Passed to sf as --agent.
- `-SessionId` (String): Only traces of this preview session. Passed to sf as --session-id.
- `-OlderThan` (String): Only traces older than this: a number and a unit, m (minutes), h (hours), d (days) or w (weeks), for example 7d or 24h. Passed to sf as --older-than.
- `-NoPrompt` (switch): Do not ask for confirmation. Skips the PowerShell question; psfdx always passes --no-prompt to the CLI after it has confirmed.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent trace delete`

#### Examples

```powershell
PS> Remove-SalesforceAgentTrace -Agent Service_Agent -OlderThan 30d -WhatIf
```

Preview deleting a month-old traces.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceAgentTrace -Examples"
- For more information, type: "Get-Help Remove-SalesforceAgentTrace -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceAgentTrace -Full"
- For online help, type: "Get-Help Remove-SalesforceAgentTrace -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Send-SalesforceAgentPreviewMessage

#### Synopsis

Sends a message to a preview session and returns the agent's answer.

#### Syntax

```powershell
Send-SalesforceAgentPreviewMessage [-Utterance] <String> [[-SessionId] <String>] [[-ApiName] <String>] [[-AuthoringBundle] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent preview send. This is a programmatic preview session: each step is its own command, so a script or another tool can drive the conversation. Give the session with -SessionId, or the agent with -ApiName or -AuthoringBundle if there is only one open session for it. The message is passed as one argument, so special characters need no escaping. On Windows the CLI's .cmd launcher cannot take a double quote or a line break in an argument, so leave those out there.

#### Parameters

- `-Utterance` (String, required): What to say to the agent. Passed to sf as --utterance. Required.
- `-SessionId` (String): ID of the preview session, from Start-SalesforceAgentPreview. Passed to sf as --session-id.
- `-ApiName` (String): API name of a published, activated agent. Use it or -AuthoringBundle, not both. Passed to sf as --api-name.
- `-AuthoringBundle` (String): API name of a local authoring bundle (an Agent Script agent in the project). Use it or -ApiName, not both. Passed to sf as --authoring-bundle.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent preview send`

#### Examples

```powershell
PS> Send-SalesforceAgentPreviewMessage -SessionId $session.sessionId -Utterance 'Where is my order?' -TargetOrg dev1
```

Ask the agent a question.

#### Remarks

- To see the examples, type: "Get-Help Send-SalesforceAgentPreviewMessage -Examples"
- For more information, type: "Get-Help Send-SalesforceAgentPreviewMessage -Detailed"
- For technical information, type: "Get-Help Send-SalesforceAgentPreviewMessage -Full"
- For online help, type: "Get-Help Send-SalesforceAgentPreviewMessage -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Start-SalesforceAgentPreview

#### Synopsis

Starts a programmatic preview session with an agent.

#### Syntax

```powershell
Start-SalesforceAgentPreview [[-ApiName] <String>] [[-AuthoringBundle] <String>] [[-ContextVariables] <IDictionary>] [[-ContextVariablesJson] <String>] [-SimulateActions] [-UseLiveActions] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent preview start and returns the session, with the session ID that Send-SalesforceAgentPreviewMessage, Stop-SalesforceAgentPreview and Get-SalesforceAgentTrace* use. This is a programmatic preview session: each step is its own command, so a script or another tool can drive the conversation. Give -ApiName for a published agent or -AuthoringBundle for a local Agent Script agent. For a conversation you type yourself use Invoke-SalesforceAgentPreview.

#### Parameters

- `-ApiName` (String): API name of a published, activated agent. Use it or -AuthoringBundle, not both. Passed to sf as --api-name.
- `-AuthoringBundle` (String): API name of a local authoring bundle (an Agent Script agent in the project). Use it or -ApiName, not both. Passed to sf as --authoring-bundle.
- `-ContextVariables` (IDictionary): Context variables for the conversation as name and value pairs. Each pair is passed to sf as its own --context-variables name=value. Names are checked, and a value may not contain a double quote or line break. Cannot be used with -ContextVariablesJson. Passed to sf as --context-variables.
- `-ContextVariablesJson` (String): Context variables as a JSON string, for example '{"order":"1001"}'. It must be valid JSON. On Windows the CLI's .cmd launcher cannot take an argument with double quotes, which JSON always has, so this does not work there: use -ContextVariables. Cannot be used with -ContextVariables. Passed to sf as --context-variables-json.
- `-SimulateActions` (switch): Simulate the agent's actions instead of running them. Only for an authoring bundle. Adds --simulate-actions.
- `-UseLiveActions` (switch): Run the real actions of the agent, which can change data. Only for an authoring bundle. Adds --use-live-actions.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent preview start`

#### Examples

```powershell
PS> $session = Start-SalesforceAgentPreview -ApiName Service_Agent -TargetOrg dev1
```

Start a session with a published agent.

#### Remarks

- To see the examples, type: "Get-Help Start-SalesforceAgentPreview -Examples"
- For more information, type: "Get-Help Start-SalesforceAgentPreview -Detailed"
- For technical information, type: "Get-Help Start-SalesforceAgentPreview -Full"
- For online help, type: "Get-Help Start-SalesforceAgentPreview -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Stop-SalesforceAgentPreview

#### Synopsis

Ends a preview session and returns where its trace files are.

#### Syntax

```powershell
Stop-SalesforceAgentPreview [[-SessionId] <String>] [-All] [[-ApiName] <String>] [[-AuthoringBundle] <String>] [-NoPrompt] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent preview end. Give the session with -SessionId, the agent with -ApiName or -AuthoringBundle, or -All to end every session. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time.

#### Parameters

- `-SessionId` (String): ID of the preview session to end. Passed to sf as --session-id.
- `-All` (switch): End every preview session. Adds --all.
- `-ApiName` (String): API name of a published, activated agent. Use it or -AuthoringBundle, not both. Passed to sf as --api-name.
- `-AuthoringBundle` (String): API name of a local authoring bundle (an Agent Script agent in the project). Use it or -ApiName, not both. Passed to sf as --authoring-bundle.
- `-NoPrompt` (switch): Do not ask for confirmation. Skips the PowerShell question; psfdx always passes --no-prompt to the CLI after it has confirmed.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent preview end`

#### Examples

```powershell
PS> Stop-SalesforceAgentPreview -SessionId $session.sessionId -TargetOrg dev1 -Confirm:$false
```

End one session without a question.

#### Remarks

- To see the examples, type: "Get-Help Stop-SalesforceAgentPreview -Examples"
- For more information, type: "Get-Help Stop-SalesforceAgentPreview -Detailed"
- For technical information, type: "Get-Help Stop-SalesforceAgentPreview -Full"
- For online help, type: "Get-Help Stop-SalesforceAgentPreview -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Tests and evaluations

### Get-SalesforceAgentTestResult

#### Synopsis

Gets the results of an Agentforce agent test run.

#### Syntax

```powershell
Get-SalesforceAgentTestResult [-JobId] <String> [-ExtendedDetails] [[-OutputDir] <String>] [[-ResultFormat] <String>] [[-TestRunner] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent test results for a job ID returned by Start-SalesforceAgentTest. Needs the @salesforce/plugin-agent plugin.

#### Parameters

- `-JobId` (String, required): Job ID of the completed agent test run. Passed to sf as --job-id. Required.
- `-ExtendedDetails` (switch): Show the generated data, such as the full response of each test, in the results. Adds --verbose.
- `-OutputDir` (String): Folder to write the results files to. Passed to sf as --output-dir.
- `-ResultFormat` (String): Format of the results. Passed to sf as --result-format. Valid values: json, human, junit, tap. Without it the cmdlet returns the result as an object, as before. With json it does too; with human, junit or tap the CLI text is returned as it is.
- `-TestRunner` (String): The test runner that holds the test. Passed to sf as --test-runner. Valid values: agentforce-studio, testing-center.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent test results`

#### Examples

```powershell
PS> Get-SalesforceAgentTestResult -JobId 4KBxx0000000001 -TargetOrg dev1
```

Results of that run.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceAgentTestResult -Examples"
- For more information, type: "Get-Help Get-SalesforceAgentTestResult -Detailed"
- For technical information, type: "Get-Help Get-SalesforceAgentTestResult -Full"
- For online help, type: "Get-Help Get-SalesforceAgentTestResult -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceAgentTests

#### Synopsis

Lists the agent tests available in an org.

#### Syntax

```powershell
Get-SalesforceAgentTests [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent test list and returns the test definitions as objects (an empty array when there are none). Needs the @salesforce/plugin-agent plugin.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent test list`

#### Examples

```powershell
PS> Get-SalesforceAgentTests -TargetOrg dev1
```

Agent tests in the org.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceAgentTests -Examples"
- For more information, type: "Get-Help Get-SalesforceAgentTests -Detailed"
- For technical information, type: "Get-Help Get-SalesforceAgentTests -Full"
- For online help, type: "Get-Help Get-SalesforceAgentTests -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceAgentTest

#### Synopsis

Creates an agent test in an org from a local test spec file.

#### Syntax

```powershell
New-SalesforceAgentTest [[-Spec] <String>] [[-ApiName] <String>] [-Preview] [-ForceOverwrite] [[-TestRunner] <String>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent test create. The spec is the YAML file made by New-SalesforceAgentTestSpec. With -Preview the CLI shows what it would create without creating it. Supports -WhatIf and -Confirm; it does not prompt by default.

#### Parameters

- `-Spec` (String): Path of the test spec YAML file. It must exist. Passed to sf as --spec.
- `-ApiName` (String): API name of the new test. By default the CLI derives it from the spec. Passed to sf as --api-name.
- `-Preview` (switch): Show what would be created, without creating the test. Adds --preview.
- `-ForceOverwrite` (switch): Replace the test without asking if one with that API name already exists. Adds --force-overwrite.
- `-TestRunner` (String): The test runner that holds or runs the test. Valid values: agentforce-studio, testing-center. Passed to sf as --test-runner.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent test create`

#### Examples

```powershell
PS> New-SalesforceAgentTest -Spec .\specs\orders-testSpec.yaml -ApiName Orders_Test -TargetOrg dev1 -WhatIf
```

Preview the create.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceAgentTest -Examples"
- For more information, type: "Get-Help New-SalesforceAgentTest -Detailed"
- For technical information, type: "Get-Help New-SalesforceAgentTest -Full"
- For online help, type: "Get-Help New-SalesforceAgentTest -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceAgentTestSpec

#### Synopsis

Generates an agent test spec: a YAML file that lists the test cases of an agent.

#### Syntax

```powershell
New-SalesforceAgentTestSpec [[-FromDefinition] <String>] [[-OutputFile] <String>] [-ForceOverwrite] [[-TestRunner] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent generate test-spec, the first step of making an agent test. By default the CLI asks questions (the agent, then the utterances, expected topic, actions and outcome of each test case), so it is interactive: it needs a terminal, and you should run it as a plain command (an assigned or piped result hides the questions). With -FromDefinition it converts an existing test definition file instead and asks nothing. It reads the project and writes a local file; it never looks in your org. Create the test in the org with New-SalesforceAgentTest.

#### Parameters

- `-FromDefinition` (String): Path of an existing test definition file to convert into a spec, instead of answering questions. It must exist. Passed to sf as --from-definition.
- `-OutputFile` (String): File to write the spec to. The CLI default is specs/&lt;agent&gt;-testSpec.yaml. The folder must exist. Passed to sf as --output-file.
- `-ForceOverwrite` (switch): Overwrite the output file without asking if it already exists. Adds --force-overwrite.
- `-TestRunner` (String): The test runner that holds or runs the test. Valid values: agentforce-studio, testing-center. Passed to sf as --test-runner.

#### Salesforce CLI

- `sf agent generate test-spec`

#### Examples

```powershell
PS> New-SalesforceAgentTestSpec -OutputFile .\specs\orders-testSpec.yaml
```

Answer the questions to build a spec.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceAgentTestSpec -Examples"
- For more information, type: "Get-Help New-SalesforceAgentTestSpec -Detailed"
- For technical information, type: "Get-Help New-SalesforceAgentTestSpec -Full"
- For online help, type: "Get-Help New-SalesforceAgentTestSpec -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Resume-SalesforceAgentTest

#### Synopsis

Waits for an agent test run you started earlier and returns its results.

#### Syntax

```powershell
Resume-SalesforceAgentTest -JobId <String> [-WaitMinutes <Int32>] [-ExtendedDetails] [-OutputDir <String>] [-ResultFormat <String>] [-TestRunner <String>] [-TargetOrg <String>] [<CommonParameters>]
Resume-SalesforceAgentTest -UseMostRecent [-WaitMinutes <Int32>] [-ExtendedDetails] [-OutputDir <String>] [-ResultFormat <String>] [-TestRunner <String>] [-TargetOrg <String>] [<CommonParameters>]
```

#### Description

Runs sf agent test resume for the job ID that Start-SalesforceAgentTest returned, or for the most recent run with -UseMostRecent. With -ResultFormat json (the default) the results come back as an object; the other formats return the CLI text. It does not change anything in the org.

#### Parameters

- `-JobId` (String, required): ID of the test run (the job ID). Required unless you give -UseMostRecent. Passed to sf as --job-id. Required.
- `-UseMostRecent` (switch, required): Resume the most recent test run instead of giving -JobId. Adds --use-most-recent. Required.
- `-WaitMinutes` (Int32): Number of minutes to wait for the run to finish. Passed to sf as --wait.
- `-ExtendedDetails` (switch): Show the generated data, such as the full response of each test, in the results. Adds --verbose.
- `-OutputDir` (String): Folder to write the results files to. Passed to sf as --output-dir.
- `-ResultFormat` (String): Format of the results. Valid values: json, human, junit, tap. With json the result is returned as an object; with the others the CLI text is returned as it is. Passed to sf as --result-format.
- `-TestRunner` (String): The test runner that holds or runs the test. Valid values: agentforce-studio, testing-center. Passed to sf as --test-runner.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent test resume`

#### Examples

```powershell
PS> Resume-SalesforceAgentTest -UseMostRecent -WaitMinutes 10 -TargetOrg dev1
```

Wait for the latest run.

#### Remarks

- To see the examples, type: "Get-Help Resume-SalesforceAgentTest -Examples"
- For more information, type: "Get-Help Resume-SalesforceAgentTest -Detailed"
- For technical information, type: "Get-Help Resume-SalesforceAgentTest -Full"
- For online help, type: "Get-Help Resume-SalesforceAgentTest -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Start-SalesforceAgentEvaluation

#### Synopsis

Runs rich evaluation tests against an agent. Beta.

#### Syntax

```powershell
Start-SalesforceAgentEvaluation [-Spec] <String> [[-ApiName] <String>] [[-BatchSize] <Int32>] [-NoNormalize] [[-ResultFormat] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent test run-eval, which runs the test cases of a spec file (YAML or JSON) against an agent, without a test being created in the org. This CLI command is in beta, so its flags and output can change in a later release. With -ResultFormat json the results come back as an object; the CLI default, human, and the other formats return text.

#### Parameters

- `-Spec` (String, required): Path of the test spec file (YAML or JSON). It must exist. Passed to sf as --spec. Required.
- `-ApiName` (String): API name of the agent to test. By default the CLI reads it from the spec's subjectName. Passed to sf as --api-name.
- `-BatchSize` (Int32): Number of tests to send per request. The CLI default is 5 and the maximum is 5. Passed to sf as --batch-size.
- `-NoNormalize` (switch): Do not normalize field names and shorthand references in the spec. Adds --no-normalize.
- `-ResultFormat` (String): Format of the results. Valid values: json, human, junit, tap. With json the result is returned as an object; with the others the CLI text is returned as it is. Passed to sf as --result-format.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent test run-eval`

#### Examples

```powershell
PS> Start-SalesforceAgentEvaluation -Spec .\specs\orders-eval.yaml -ResultFormat json -TargetOrg dev1
```

Run an evaluation and get the results as an object.

#### Remarks

- To see the examples, type: "Get-Help Start-SalesforceAgentEvaluation -Examples"
- For more information, type: "Get-Help Start-SalesforceAgentEvaluation -Detailed"
- For technical information, type: "Get-Help Start-SalesforceAgentEvaluation -Full"
- For online help, type: "Get-Help Start-SalesforceAgentEvaluation -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Start-SalesforceAgentTest

#### Synopsis

Starts an Agentforce agent test and optionally waits for it.

#### Syntax

```powershell
Start-SalesforceAgentTest [-ApiName] <String> [[-WaitMinutes] <Int32>] [-ExtendedDetails] [[-OutputDir] <String>] [[-ResultFormat] <String>] [[-TestRunner] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent test run for the test API name. Without -WaitMinutes the run is started and the job ID is returned; fetch the outcome later with Get-SalesforceAgentTestResult. Needs the @salesforce/plugin-agent plugin.

#### Parameters

- `-ApiName` (String, required): API name of the agent test to run; corresponds to the name of the AiEvaluationDefinition metadata component that implements the agent test. Passed to sf as --api-name. Required.
- `-WaitMinutes` (Int32): Number of minutes to wait for the command to complete and display results to the terminal window. Passed to sf as --wait. Range: 1 to 1440.
- `-ExtendedDetails` (switch): Show the generated data, such as the full response of each test, in the results. Adds --verbose.
- `-OutputDir` (String): Folder to write the results files to. Passed to sf as --output-dir.
- `-ResultFormat` (String): Format of the results. Passed to sf as --result-format. Valid values: json, human, junit, tap. Without it the cmdlet returns the result as an object, as before. With json it does too; with human, junit or tap the CLI text is returned as it is.
- `-TestRunner` (String): The test runner that holds the test. Passed to sf as --test-runner. Valid values: agentforce-studio, testing-center.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent test run`

#### Examples

```powershell
PS> Start-SalesforceAgentTest -ApiName Service_Agent_Test -WaitMinutes 10 -TargetOrg dev1
```

Run the test and wait up to ten minutes.

#### Remarks

- To see the examples, type: "Get-Help Start-SalesforceAgentTest -Examples"
- For more information, type: "Get-Help Start-SalesforceAgentTest -Detailed"
- For technical information, type: "Get-Help Start-SalesforceAgentTest -Full"
- For online help, type: "Get-Help Start-SalesforceAgentTest -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## MCP servers and assets

### Get-SalesforceMcpAssets

#### Synopsis

Lists the assets (tools, prompts and resources) of an MCP server in the catalog. Preview.

#### Syntax

```powershell
Get-SalesforceMcpAssets [-McpServerId] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent mcp asset list: the assets that are allowed in the catalog. Use Get-SalesforceMcpServerLiveAssets for what the server offers right now. This CLI command is a preview, so its flags and output can change in a later release. It only reads.

#### Parameters

- `-McpServerId` (String, required): ID of the MCP server in the API Catalog. Passed to sf as --mcp-server-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent mcp asset list`

#### Examples

```powershell
PS> Get-SalesforceMcpAssets -McpServerId 0Xxxx0000000001 -TargetOrg dev1
```

The allowed assets of a server.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceMcpAssets -Examples"
- For more information, type: "Get-Help Get-SalesforceMcpAssets -Detailed"
- For technical information, type: "Get-Help Get-SalesforceMcpAssets -Full"
- For online help, type: "Get-Help Get-SalesforceMcpAssets -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceMcpServer

#### Synopsis

Shows one MCP server of the API Catalog. Preview.

#### Syntax

```powershell
Get-SalesforceMcpServer [-McpServerId] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent mcp get. This CLI command is a preview, so its flags and output can change in a later release. It only reads.

#### Parameters

- `-McpServerId` (String, required): ID of the MCP server in the API Catalog. Passed to sf as --mcp-server-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent mcp get`

#### Examples

```powershell
PS> Get-SalesforceMcpServer -McpServerId 0Xxxx0000000001 -TargetOrg dev1
```

The details of one server.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceMcpServer -Examples"
- For more information, type: "Get-Help Get-SalesforceMcpServer -Detailed"
- For technical information, type: "Get-Help Get-SalesforceMcpServer -Full"
- For online help, type: "Get-Help Get-SalesforceMcpServer -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceMcpServerLiveAssets

#### Synopsis

Asks an MCP server for the assets it offers right now. Preview.

#### Syntax

```powershell
Get-SalesforceMcpServerLiveAssets [-McpServerId] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent mcp fetch, which connects to the server and returns the tools, prompts and resources it advertises. Compare it with Get-SalesforceMcpAssets, then change the allowed set with Set-SalesforceMcpAssets. This CLI command is a preview, so its flags and output can change in a later release. It does not change the catalog.

#### Parameters

- `-McpServerId` (String, required): ID of the MCP server in the API Catalog. Passed to sf as --mcp-server-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent mcp fetch`

#### Examples

```powershell
PS> Get-SalesforceMcpServerLiveAssets -McpServerId 0Xxxx0000000001 -TargetOrg dev1
```

What the server offers now.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceMcpServerLiveAssets -Examples"
- For more information, type: "Get-Help Get-SalesforceMcpServerLiveAssets -Detailed"
- For technical information, type: "Get-Help Get-SalesforceMcpServerLiveAssets -Full"
- For online help, type: "Get-Help Get-SalesforceMcpServerLiveAssets -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceMcpServers

#### Synopsis

Lists the MCP servers of the API Catalog. Preview.

#### Syntax

```powershell
Get-SalesforceMcpServers [[-Label] <String>] [[-Status] <String>] [[-Type] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf agent mcp list and returns one object per server. This CLI command is a preview, so its flags and output can change in a later release. It only reads.

#### Parameters

- `-Label` (String): Only servers with this label. Passed to sf as --label.
- `-Status` (String): Only servers with this status. Valid values: ACTIVE, DISCONNECTED. Passed to sf as --status.
- `-Type` (String): Only servers of this type. Valid value: EXTERNAL. Passed to sf as --type.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf agent mcp list`

#### Examples

```powershell
PS> Get-SalesforceMcpServers -Status ACTIVE -TargetOrg dev1
```

The servers that are connected.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceMcpServers -Examples"
- For more information, type: "Get-Help Get-SalesforceMcpServers -Detailed"
- For technical information, type: "Get-Help Get-SalesforceMcpServers -Full"
- For online help, type: "Get-Help Get-SalesforceMcpServers -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceMcpServer

#### Synopsis

Registers an MCP server in the API Catalog. Preview.

#### Syntax

```powershell
New-SalesforceMcpServer [-Name] <String> [-ServerUrl] <String> [[-AuthType] <String>] [[-Label] <String>] [[-Description] <String>] [[-IdentityProvider] <String>] [[-Scope] <String>] [[-ClientId] <String>] [[-ClientSecret] <SecureString>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent mcp create, which adds a Model Context Protocol server to the org's API Catalog so agents can use its tools. This CLI command is a preview, so its flags and output can change in a later release. The server URL must be an absolute https URL, because credentials are sent to it. Supports -WhatIf and -Confirm; it does not prompt by default.

#### Parameters

- `-Name` (String, required): Unique name of the server. Passed to sf as --name. Required.
- `-ServerUrl` (String, required): URL of the MCP server. It must be an absolute https:// URL. Passed to sf as --server-url. Required.
- `-AuthType` (String): How the server is authenticated. Valid values: OAUTH, NO_AUTH. Passed to sf as --auth-type.
- `-Label` (String): Label shown for the server. Passed to sf as --label.
- `-Description` (String): Description of the server. Passed to sf as --description.
- `-IdentityProvider` (String): Name of the identity provider, for OAUTH. Passed to sf as --identity-provider.
- `-Scope` (String): OAuth scope, for OAUTH. Passed to sf as --scope.
- `-ClientId` (String): OAuth client ID, for OAUTH. Passed to sf as --client-id.
- `-ClientSecret` (SecureString): OAuth client secret of the server, as a SecureString, for example (Read-Host -AsSecureString). It is turned into text only when the command is built, and the CLI's own verbose line hides it. Passed to sf as --client-secret.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent mcp create`

#### Examples

```powershell
PS> New-SalesforceMcpServer -Name Orders_Mcp -ServerUrl https://mcp.example.com/orders -AuthType OAUTH -ClientId $id -ClientSecret (Read-Host -AsSecureString) -TargetOrg dev1 -WhatIf
```

Preview registering a server.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceMcpServer -Examples"
- For more information, type: "Get-Help New-SalesforceMcpServer -Detailed"
- For technical information, type: "Get-Help New-SalesforceMcpServer -Full"
- For online help, type: "Get-Help New-SalesforceMcpServer -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceMcpServer

#### Synopsis

Deletes an MCP server from the API Catalog. Preview.

#### Syntax

```powershell
Remove-SalesforceMcpServer [-McpServerId] <String> [-NoPrompt] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent mcp delete. Agents that use the server lose its tools, and this cannot be undone. This CLI command is a preview, so its flags and output can change in a later release. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time.

#### Parameters

- `-McpServerId` (String, required): ID of the MCP server in the API Catalog. Passed to sf as --mcp-server-id. Required.
- `-NoPrompt` (switch): Do not ask for confirmation. Skips the PowerShell question; psfdx always passes --no-prompt to the CLI after it has confirmed.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent mcp delete`

#### Examples

```powershell
PS> Remove-SalesforceMcpServer -McpServerId 0Xxxx0000000001 -TargetOrg dev1 -WhatIf
```

Preview the delete.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceMcpServer -Examples"
- For more information, type: "Get-Help Remove-SalesforceMcpServer -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceMcpServer -Full"
- For online help, type: "Get-Help Remove-SalesforceMcpServer -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Set-SalesforceMcpAssets

#### Synopsis

Replaces the allowed assets of an MCP server in the catalog. Preview.

#### Syntax

```powershell
Set-SalesforceMcpAssets [-McpServerId] <String> [[-Assets] <String>] [[-AssetList] <Object>] [[-AssetsFile] <String>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent mcp asset replace. The set you give replaces the allowed set, so an asset that is not in it is no longer allowed. Give the set as a JSON string in -Assets, as an object or array in -AssetList (psfdx converts it to JSON), or as a JSON file in -AssetsFile. This CLI command is a preview, so its flags and output can change in a later release. Supports -WhatIf and -Confirm; it does not prompt by default.

#### Parameters

- `-McpServerId` (String, required): ID of the MCP server in the API Catalog. Passed to sf as --mcp-server-id. Required.
- `-Assets` (String): The allowed assets as a JSON string. It must be valid JSON. On Windows the CLI's .cmd launcher cannot take an argument with double quotes, which JSON always has, so this does not work there: use -AssetsFile. Use one of -Assets, -AssetList and -AssetsFile. Passed to sf as --assets.
- `-AssetList` (Object): The allowed assets as a PowerShell object or array, sent as JSON. On Windows the CLI's .cmd launcher cannot take an argument with double quotes, which JSON always has, so this does not work there: use -AssetsFile. Use one of -Assets, -AssetList and -AssetsFile. Sent to sf as --assets.
- `-AssetsFile` (String): Path of a JSON file with the allowed assets. It must exist. Use one of -Assets, -AssetList and -AssetsFile. Passed to sf as --assets-file.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent mcp asset replace`

#### Examples

```powershell
PS> Set-SalesforceMcpAssets -McpServerId 0Xxxx0000000001 -AssetsFile .\assets.json -TargetOrg dev1 -WhatIf
```

Preview replacing the set.

#### Remarks

- To see the examples, type: "Get-Help Set-SalesforceMcpAssets -Examples"
- For more information, type: "Get-Help Set-SalesforceMcpAssets -Detailed"
- For technical information, type: "Get-Help Set-SalesforceMcpAssets -Full"
- For online help, type: "Get-Help Set-SalesforceMcpAssets -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Update-SalesforceMcpServer

#### Synopsis

Changes an MCP server in the API Catalog. Preview.

#### Syntax

```powershell
Update-SalesforceMcpServer [-McpServerId] <String> [[-ServerUrl] <String>] [[-AuthType] <String>] [[-Label] <String>] [[-Description] <String>] [[-IdentityProvider] <String>] [[-Scope] <String>] [[-ClientId] <String>] [[-ClientSecret] <SecureString>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf agent mcp update. Only the settings you give are changed. This CLI command is a preview, so its flags and output can change in a later release. A new server URL must be an absolute https URL. Supports -WhatIf and -Confirm; it does not prompt by default.

#### Parameters

- `-McpServerId` (String, required): ID of the MCP server in the API Catalog. Passed to sf as --mcp-server-id. Required.
- `-ServerUrl` (String): New URL of the server. It must be an absolute https:// URL. Passed to sf as --server-url.
- `-AuthType` (String): How the server is authenticated. Valid values: OAUTH, NO_AUTH. Passed to sf as --auth-type.
- `-Label` (String): New label. Passed to sf as --label.
- `-Description` (String): New description. Passed to sf as --description.
- `-IdentityProvider` (String): New identity provider name. Passed to sf as --identity-provider.
- `-Scope` (String): New OAuth scope. Passed to sf as --scope.
- `-ClientId` (String): New OAuth client ID. Passed to sf as --client-id.
- `-ClientSecret` (SecureString): OAuth client secret of the server, as a SecureString, for example (Read-Host -AsSecureString). It is turned into text only when the command is built, and the CLI's own verbose line hides it. Passed to sf as --client-secret.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf agent mcp update`

#### Examples

```powershell
PS> Update-SalesforceMcpServer -McpServerId 0Xxxx0000000001 -Description 'Orders tools' -TargetOrg dev1 -WhatIf
```

Preview the change.

#### Remarks

- To see the examples, type: "Get-Help Update-SalesforceMcpServer -Examples"
- For more information, type: "Get-Help Update-SalesforceMcpServer -Detailed"
- For technical information, type: "Get-Help Update-SalesforceMcpServer -Full"
- For online help, type: "Get-Help Update-SalesforceMcpServer -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-agent>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>
