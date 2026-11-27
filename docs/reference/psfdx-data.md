# psfdx-data command reference

Generated from the commands' own help by `site/Update-ModuleReference.ps1`: do not edit it by hand. The same reference is on the website: <https://psfdx.com/modules/psfdx-data/>. It is part of the `psfdx` package; see the [installation guide](https://github.com/tonygward/psfdx/blob/main/docs/install.md).

20 commands. Every command also takes the common parameters, such as `-Verbose`.

## Commands

**Bulk API 2.0**: [Export-SalesforceBulkData](#export-salesforcebulkdata), [Get-SalesforceBulkJobStatus](#get-salesforcebulkjobstatus), [Get-SalesforceBulkResult](#get-salesforcebulkresult), [Import-SalesforceBulkData](#import-salesforcebulkdata), [Remove-SalesforceBulkData](#remove-salesforcebulkdata), [Resume-SalesforceBulkJob](#resume-salesforcebulkjob), [Update-SalesforceBulkData](#update-salesforcebulkdata), [Upsert-SalesforceBulkData](#upsert-salesforcebulkdata)

**Tree data**: [Export-SalesforceTreeData](#export-salesforcetreedata), [Import-SalesforceTreeData](#import-salesforcetreedata)

**Records and queries**: [Get-SalesforceRecord](#get-salesforcerecord), [Get-SalesforceRecordType](#get-salesforcerecordtype), [Get-SalesforceSObjectRecordCount](#get-salesforcesobjectrecordcount), [New-SalesforceFile](#new-salesforcefile), [New-SalesforceRecord](#new-salesforcerecord), [Remove-SalesforceRecord](#remove-salesforcerecord), [Search-SalesforceRecords](#search-salesforcerecords), [Select-SalesforceRecords](#select-salesforcerecords), [Set-SalesforceRecord](#set-salesforcerecord), [Upsert-SalesforceRecord](#upsert-salesforcerecord)

## Bulk API 2.0

### Export-SalesforceBulkData

#### Synopsis

Exports the records of a SOQL query to a file with Bulk API 2.0 (sf data export bulk).

#### Syntax

```powershell
Export-SalesforceBulkData [-OutputFile] <String> [[-Query] <String>] [[-QueryFile] <String>] [[-ResultFormat] <String>] [-AllRows] [[-ColumnDelimiter] <String>] [[-LineEnding] <String>] [[-WaitMinutes] <Int32>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Give the query as -Query or -QueryFile (a file avoids line breaks, which the Windows CLI shim rejects as an argument). The query is passed to the CLI unchanged. Without -WaitMinutes the job is created and its JobId returned; finish it later with Resume-SalesforceBulkJob -Operation Export. With -WaitMinutes the cmdlet waits and returns TotalSize.

#### Parameters

- `-OutputFile` (String, required): File where records are written. Passed to sf as --output-file. Required.
- `-Query` (String): SOQL query to execute. Passed to sf as --query.
- `-QueryFile` (String): File that contains the SOQL query. Passed to sf as --query-file.
- `-ResultFormat` (String): Format to write the results. Passed to sf as --result-format. Default: csv. Valid values: csv, json.
- `-AllRows` (switch): Include records that have been soft-deleted due to a merge or delete. By default, deleted records are not returned. Adds --all-rows.
- `-ColumnDelimiter` (String): Column delimiter to be used when writing CSV output. Default is COMMA. Passed to sf as --column-delimiter. Valid values: BACKQUOTE, CARET, COMMA, PIPE, SEMICOLON, TAB.
- `-LineEnding` (String): Line ending to be used when writing CSV output. Default value on Windows is is `CRLF`; on macOS and Linux it's `LR`. Passed to sf as --line-ending. Valid values: LF, CRLF.
- `-WaitMinutes` (Int32): Time to wait for the command to finish, in minutes. Passed to sf as --wait. Default: 0. Range: 0 to 1440.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf data export bulk`

#### Examples

```powershell
PS> Export-SalesforceBulkData -Query 'SELECT Id, Name FROM Account' -OutputFile .\accounts.csv -WaitMinutes 10 -TargetOrg myorg
```

#### Remarks

- To see the examples, type: "Get-Help Export-SalesforceBulkData -Examples"
- For more information, type: "Get-Help Export-SalesforceBulkData -Detailed"
- For technical information, type: "Get-Help Export-SalesforceBulkData -Full"
- For online help, type: "Get-Help Export-SalesforceBulkData -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceBulkJobStatus

#### Synopsis

Shows the status of a bulk data load job, or of one batch in it (sf data resume).

#### Syntax

```powershell
Get-SalesforceBulkJobStatus [-JobId] <String> [[-BatchId] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf data resume, which reads the state of a bulk job from the org and returns it as an object. It only reads: it does not continue or change the job. For a Bulk API 2.0 job started with -WaitMinutes 0, use Resume-SalesforceBulkJob to continue it and Get-SalesforceBulkResult for its row results.

#### Parameters

- `-JobId` (String, required): ID of the bulk job. Passed to sf as --job-id. Required.
- `-BatchId` (String): ID of one batch in the job. Passed to sf as --batch-id.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf data resume`

#### Examples

```powershell
PS> Get-SalesforceBulkJobStatus -JobId 750xx0000000001AAA -TargetOrg myorg
```

The state of the job.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceBulkJobStatus -Examples"
- For more information, type: "Get-Help Get-SalesforceBulkJobStatus -Detailed"
- For technical information, type: "Get-Help Get-SalesforceBulkJobStatus -Full"
- For online help, type: "Get-Help Get-SalesforceBulkJobStatus -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceBulkResult

#### Synopsis

Gets the outcome of a Bulk API 2.0 ingest job and saves its row results as CSV files (sf data bulk results).

#### Syntax

```powershell
Get-SalesforceBulkResult [-JobId] <String> [[-OutputDirectory] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

The CLI writes &lt;JobId&gt;-success-records.csv, &lt;JobId&gt;-failed-records.csv and &lt;JobId&gt;-unprocessed-records.csv into its working directory, so the cmdlet runs it in -OutputDirectory (the current directory by default) and returns the full paths of the files it wrote. Records that failed do not make this cmdlet throw: check HasFailures or FailedRecords. A job that has not finished is an error. Works for any job in the org, including ones this computer did not create.

#### Parameters

- `-JobId` (String, required): Job ID of the bulk job. Passed to sf as --job-id. Required.
- `-OutputDirectory` (String): Folder the result files are written to. It is created if it does not exist. Defaults to the current folder. The cmdlet runs the CLI there and returns the full paths of the files it wrote.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf data bulk results`

#### Examples

```powershell
PS> $r = Get-SalesforceBulkResult -JobId 750xx0000000001 -OutputDirectory .\bulk -TargetOrg myorg; if ($r.HasFailures) { Import-Csv $r.FailedFilePath }
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceBulkResult -Examples"
- For more information, type: "Get-Help Get-SalesforceBulkResult -Detailed"
- For technical information, type: "Get-Help Get-SalesforceBulkResult -Full"
- For online help, type: "Get-Help Get-SalesforceBulkResult -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Import-SalesforceBulkData

#### Synopsis

Inserts the rows of a CSV file with Bulk API 2.0 (sf data import bulk).

#### Syntax

```powershell
Import-SalesforceBulkData [-File] <String> [-Object] <String> [[-ColumnDelimiter] <String>] [[-LineEnding] <String>] [[-WaitMinutes] <Int32>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Creates records. Asks for confirmation only when $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. Without -WaitMinutes the job is created and its JobId returned; with it the cmdlet waits and returns the counts. A job with failed rows throws PsfdxBulkJobFailed (see Get-SalesforceBulkResult for the row results).

#### Parameters

- `-File` (String, required): CSV file that contains the Salesforce object records you want to import. Passed to sf as --file. Required.
- `-Object` (String, required): API name of the Salesforce object, either standard or custom, into which you're importing records. Passed to sf as --sobject. Required.
- `-ColumnDelimiter` (String): Column delimiter used in the CSV file. Passed to sf as --column-delimiter. Valid values: BACKQUOTE, CARET, COMMA, PIPE, SEMICOLON, TAB.
- `-LineEnding` (String): Line ending used in the CSV file. Default value on Windows is `CRLF`; on macOS and Linux it's `LF`. Passed to sf as --line-ending. Valid values: LF, CRLF.
- `-WaitMinutes` (Int32): Time to wait for the command to finish, in minutes. Passed to sf as --wait. Default: 0. Range: 0 to 1440.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf data import bulk`

#### Examples

```powershell
PS> Import-SalesforceBulkData -File '.\new accounts.csv' -Object Account -WaitMinutes 10 -TargetOrg myorg
```

#### Remarks

- To see the examples, type: "Get-Help Import-SalesforceBulkData -Examples"
- For more information, type: "Get-Help Import-SalesforceBulkData -Detailed"
- For technical information, type: "Get-Help Import-SalesforceBulkData -Full"
- For online help, type: "Get-Help Import-SalesforceBulkData -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceBulkData

#### Synopsis

Deletes the records whose IDs are in a CSV file with Bulk API 2.0 (sf data delete bulk).

#### Syntax

```powershell
Remove-SalesforceBulkData [-File] <String> [-Object] <String> [-HardDelete] [[-LineEnding] <String>] [[-WaitMinutes] <Int32>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

The CSV needs an Id column. By default the records go to the Recycle Bin; -HardDelete deletes them permanently, which cannot be undone, and needs the Bulk API Hard Delete permission. Asks for confirmation by default, naming the object, the file, the org and whether the delete is permanent; -WhatIf makes no CLI call. Scripts that run unattended need -Confirm:$false. Without -WaitMinutes the job is created and its JobId returned; finish it with Resume-SalesforceBulkJob -Operation Delete. With -WaitMinutes the cmdlet waits and returns the counts. A job with failed rows throws PsfdxBulkJobFailed (see Get-SalesforceBulkResult for the row results).

#### Parameters

- `-File` (String, required): CSV file that contains the IDs of the records to delete. Passed to sf as --file. Required.
- `-Object` (String, required): API name of the Salesforce object, either standard or custom, that you want to delete records from. Passed to sf as --sobject. Required.
- `-HardDelete` (switch): Delete the records permanently, without moving them to the Recycle Bin. Adds --hard-delete. The user needs the Bulk API Hard Delete permission.
- `-LineEnding` (String): Line ending used in the CSV file. Default value on Windows is `CRLF`; on macOS and Linux it's `LF`. Passed to sf as --line-ending. Valid values: LF, CRLF.
- `-WaitMinutes` (Int32): Time to wait for the command to finish, in minutes. Passed to sf as --wait. Default: 0. Range: 0 to 1440.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf data delete bulk`

#### Examples

```powershell
PS> Remove-SalesforceBulkData -File .\old-accounts.csv -Object Account -WaitMinutes 10 -TargetOrg myorg -WhatIf
```

Preview the delete without sending anything.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceBulkData -Examples"
- For more information, type: "Get-Help Remove-SalesforceBulkData -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceBulkData -Full"
- For online help, type: "Get-Help Remove-SalesforceBulkData -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Resume-SalesforceBulkJob

#### Synopsis

Resumes a Bulk API 2.0 job started without -WaitMinutes (sf data export|import|update|upsert|delete resume).

#### Syntax

```powershell
Resume-SalesforceBulkJob -Operation <String> -JobId <String> [-WaitMinutes <Int32>] [-TargetOrg <String>] [<CommonParameters>]
Resume-SalesforceBulkJob -Operation <String> -UseMostRecent [-WaitMinutes <Int32>] [-TargetOrg <String>] [<CommonParameters>]
```

#### Description

Pass the JobId from the earlier step and the -Operation that created it, or -UseMostRecent for the job the CLI started last. The CLI remembers jobs it created on this computer, so import, update and export resumes find the org from that record; they do not take -TargetOrg (it is ignored with a warning), and a job created elsewhere cannot be resumed here: use Get-SalesforceBulkResult with -TargetOrg instead. Upsert and Delete resumes do take -TargetOrg. Export resumes do not take -WaitMinutes. Resuming only continues the existing job, so it does not ask for confirmation. Errors are as for the cmdlet that created the job.

#### Parameters

- `-Operation` (String, required): The kind of bulk job to resume: Export, Import, Update, Upsert or Delete. It selects which command runs: sf data export, import, update, upsert or delete resume. Required. Valid values: Export, Import, Update, Upsert, Delete.
- `-JobId` (String, required): Job ID of the bulk job. Passed to sf as --job-id. Required unless you give -UseMostRecent.
- `-UseMostRecent` (switch, required): Resume the job that was started most recently, instead of giving -JobId. Adds --use-most-recent.
- `-WaitMinutes` (Int32): Time to wait for the command to finish, in minutes. Passed to sf as --wait. Default: 0. Range: 0 to 1440.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the "target-org" configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf data export resume`
- `sf data import resume`
- `sf data update resume`
- `sf data upsert resume`
- `sf data delete resume`

#### Examples

```powershell
PS> Resume-SalesforceBulkJob -Operation Upsert -JobId 750xx0000000001 -WaitMinutes 10 -TargetOrg myorg
```

#### Remarks

- To see the examples, type: "Get-Help Resume-SalesforceBulkJob -Examples"
- For more information, type: "Get-Help Resume-SalesforceBulkJob -Detailed"
- For technical information, type: "Get-Help Resume-SalesforceBulkJob -Full"
- For online help, type: "Get-Help Resume-SalesforceBulkJob -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Update-SalesforceBulkData

#### Synopsis

Updates records from the rows of a CSV file with Bulk API 2.0 (sf data update bulk).

#### Syntax

```powershell
Update-SalesforceBulkData [-File] <String> [-Object] <String> [[-ColumnDelimiter] <String>] [[-LineEnding] <String>] [[-WaitMinutes] <Int32>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

The CSV needs an Id column. Asks for confirmation only when $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. Results are as for Import-SalesforceBulkData.

#### Parameters

- `-File` (String, required): CSV file that contains the Salesforce object records you want to update. Passed to sf as --file. Required.
- `-Object` (String, required): API name of the Salesforce object, either standard or custom, which you are updating. Passed to sf as --sobject. Required.
- `-ColumnDelimiter` (String): Column delimiter used in the CSV file. Passed to sf as --column-delimiter. Valid values: BACKQUOTE, CARET, COMMA, PIPE, SEMICOLON, TAB.
- `-LineEnding` (String): Line ending used in the CSV file. Default value on Windows is `CRLF`; on macOS and Linux it's `LF`. Passed to sf as --line-ending. Valid values: LF, CRLF.
- `-WaitMinutes` (Int32): Time to wait for the command to finish, in minutes. Passed to sf as --wait. Default: 0. Range: 0 to 1440.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf data update bulk`

#### Examples

```powershell
PS> Update-SalesforceBulkData -File .\changes.csv -Object Contact -WaitMinutes 10 -TargetOrg myorg
```

#### Remarks

- To see the examples, type: "Get-Help Update-SalesforceBulkData -Examples"
- For more information, type: "Get-Help Update-SalesforceBulkData -Detailed"
- For technical information, type: "Get-Help Update-SalesforceBulkData -Full"
- For online help, type: "Get-Help Update-SalesforceBulkData -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Upsert-SalesforceBulkData

#### Synopsis

Inserts or updates records from the rows of a CSV file by external ID with Bulk API 2.0 (sf data upsert bulk).

#### Syntax

```powershell
Upsert-SalesforceBulkData [-File] <String> [-Object] <String> [-ExternalIdField] <String> [[-ColumnDelimiter] <String>] [[-LineEnding] <String>] [[-WaitMinutes] <Int32>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

-ExternalIdField names the external ID field the CSV matches on, and its column must be in the file. Asks for confirmation only when $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. For one record use Upsert-SalesforceRecord.

#### Parameters

- `-File` (String, required): CSV file that contains the IDs of the records to update or delete. Passed to sf as --file. Required.
- `-Object` (String, required): API name of the Salesforce object, either standard or custom, that you want to update or delete records from. Passed to sf as --sobject. Required.
- `-ExternalIdField` (String, required): Name of the external ID field, or the Id field. Passed to sf as --external-id. Required.
- `-ColumnDelimiter` (String): Column delimiter used in the CSV file. Passed to sf as --column-delimiter. Valid values: BACKQUOTE, CARET, COMMA, PIPE, SEMICOLON, TAB.
- `-LineEnding` (String): Line ending used in the CSV file. Default value on Windows is `CRLF`; on macOS and Linux it's `LF`. Passed to sf as --line-ending. Valid values: LF, CRLF.
- `-WaitMinutes` (Int32): Number of minutes to wait for the command to complete before displaying the results. Passed to sf as --wait. Default: 0. Range: 0 to 1440.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf data upsert bulk`

#### Examples

```powershell
PS> Upsert-SalesforceBulkData -File .\accounts.csv -Object Account -ExternalIdField Ext_Id__c -WaitMinutes 10 -TargetOrg myorg
```

#### Remarks

- To see the examples, type: "Get-Help Upsert-SalesforceBulkData -Examples"
- For more information, type: "Get-Help Upsert-SalesforceBulkData -Detailed"
- For technical information, type: "Get-Help Upsert-SalesforceBulkData -Full"
- For online help, type: "Get-Help Upsert-SalesforceBulkData -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Tree data

### Export-SalesforceTreeData

#### Synopsis

Exports records, with their related child records, to JSON files for Import-SalesforceTreeData (sf data export tree).

#### Syntax

```powershell
Export-SalesforceTreeData [-Query] <String[]> [-Plan] [[-Prefix] <String>] [[-OutputDirectory] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Each -Query is a SOQL query; a query with a subquery exports parent and children together. The queries go to the CLI unchanged, so use one line and no double quotes (the Windows CLI shim rejects line breaks and double quotes in an argument). Without -Plan the records are returned in Records and the CLI writes one JSON file per query. With -Plan the CLI writes one file per object and a plan file that references them, which Import-SalesforceTreeData -Plan reads; Files and PlanFile hold their paths. The CLI creates -OutputDirectory if it does not exist.

#### Parameters

- `-Query` (String[], required): One or more SOQL queries whose records, with the related records they select, are exported. Each query is passed as its own --query. A query with a parent-to-child subquery exports the children too. Required.
- `-Plan` (switch): Generate multiple sObject tree files and a plan definition file for aggregated import. Adds --plan.
- `-Prefix` (String): Prefix of generated files. Passed to sf as --prefix.
- `-OutputDirectory` (String): Directory in which to generate the JSON files; default is current directory. Passed to sf as --output-dir.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf data export tree`

#### Examples

```powershell
PS> Export-SalesforceTreeData -Query "SELECT Id, Name, (SELECT Id, LastName FROM Contacts) FROM Account WHERE Name LIKE 'Acme%'" -Plan -OutputDirectory .\data -TargetOrg source
PS> Import-SalesforceTreeData -Plan .\data\Account-Contact-plan.json -TargetOrg scratch
```

#### Remarks

- To see the examples, type: "Get-Help Export-SalesforceTreeData -Examples"
- For more information, type: "Get-Help Export-SalesforceTreeData -Detailed"
- For technical information, type: "Get-Help Export-SalesforceTreeData -Full"
- For online help, type: "Get-Help Export-SalesforceTreeData -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Import-SalesforceTreeData

#### Synopsis

Imports records and their related child records from JSON files into an org (sf data import tree).

#### Syntax

```powershell
Import-SalesforceTreeData -Plan <String> [-TargetOrg <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
Import-SalesforceTreeData -File <String[]> [-TargetOrg <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Give either -Plan (a plan file from Export-SalesforceTreeData -Plan) or -File (one or more tree JSON files), not both. Asks for confirmation only when $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. Returns one object per record created: RefId, Type and Id. If Salesforce rejects records, nothing is returned and the cmdlet throws PsfdxTreeImportFailed, whose TargetObject lists each failed reference with its StatusCode, Message and Fields. The Tree API imports at most 200 records per call.

#### Parameters

- `-Plan` (String, required): Plan definition file to insert multiple data files. Passed to sf as --plan. Required in the Plan parameter set.
- `-File` (String[], required): Comma-separated and in-order JSON files that contain the records, in sObject tree format, that you want to insert. Passed to sf as --files. Required in the Files parameter set.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf data import tree`

#### Examples

```powershell
PS> Import-SalesforceTreeData -Plan .\data\Account-Contact-plan.json -TargetOrg scratch
```

#### Remarks

- To see the examples, type: "Get-Help Import-SalesforceTreeData -Examples"
- For more information, type: "Get-Help Import-SalesforceTreeData -Detailed"
- For technical information, type: "Get-Help Import-SalesforceTreeData -Full"
- For online help, type: "Get-Help Import-SalesforceTreeData -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Records and queries

### Get-SalesforceRecord

#### Synopsis

Gets one record, by ID or by field values (sf data get record).

#### Syntax

```powershell
Get-SalesforceRecord -Type <String> -Id <String> [-UseToolingApi] [-TargetOrg <String>] [<CommonParameters>]
Get-SalesforceRecord -Type <String> -Where <IDictionary> [-UseToolingApi] [-TargetOrg <String>] [<CommonParameters>]
```

#### Description

Select the record with -Id, or with -Where, a hashtable of field values that identify exactly one record (the CLI reports an error for none or for several). They are alternatives: the CLI accepts only one. The record is returned as an object of its fields, without the internal attributes property. A value in -Where is passed to the CLI as Field='value'; because the CLI has no way to escape a quote inside a value, a value that contains a single quote, a double quote or a line break is refused. For anything more complex use Select-SalesforceRecords. A record that does not exist makes the cmdlet throw the CLI's message.

#### Parameters

- `-Type` (String, required): API name of the Salesforce or Tooling API object that you're retrieving a record from. Passed to sf as --sobject. Required.
- `-Id` (String, required): ID of the record you're retrieving. Passed to sf as --record-id. Required in the ById parameter set. Alias: RecordId. Accepts input from the pipeline by property name.
- `-Where` (IDictionary, required): List of &lt;fieldName&gt;=&lt;value&gt; pairs that identify the record you want to display. Passed to sf as --where. Required in the ByFields parameter set.
- `-UseToolingApi` (switch): Use Tooling API so you can retrieve a record from a Tooling API object. Adds --use-tooling-api.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf data get record`

#### Examples

```powershell
PS> Get-SalesforceRecord -Type Account -Id 001xx000003DGb2AAG -TargetOrg myorg
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceRecord -Examples"
- For more information, type: "Get-Help Get-SalesforceRecord -Detailed"
- For technical information, type: "Get-Help Get-SalesforceRecord -Full"
- For online help, type: "Get-Help Get-SalesforceRecord -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceRecordType

#### Synopsis

Lists record types, optionally for one object.

#### Syntax

```powershell
Get-SalesforceRecordType [-ObjectType] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Queries the RecordType object (Id, SobjectType, Name, DeveloperName, IsActive) through Select-SalesforceRecords. The object name is escaped as a SOQL literal.

#### Parameters

- `-ObjectType` (String, required): API name of the object whose record types you want, for example Account. Without it, record types of every object are returned. Required.
- `-TargetOrg` (String): Username or alias of the org to query. If omitted, the Salesforce CLI uses the default target org.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Get-SalesforceRecordType -ObjectType Account -TargetOrg dev1
```

Record types of Account.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceRecordType -Examples"
- For more information, type: "Get-Help Get-SalesforceRecordType -Detailed"
- For technical information, type: "Get-Help Get-SalesforceRecordType -Full"
- For online help, type: "Get-Help Get-SalesforceRecordType -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceSObjectRecordCount

#### Synopsis

Shows how many records objects have in an org.

#### Syntax

```powershell
Get-SalesforceSObjectRecordCount [[-SObject] <String[]>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Returns approximate counts from the org's stored totals, which can differ from the results of a SOQL COUNT() query. By default it includes every standard and custom object that supports this operation. Use -SObject to request counts for specific objects.

#### Parameters

- `-SObject` (String[]): API names of the objects to count, for example Account, Contact or Invoice__c. Each name is passed as its own --sobject. Names may contain only letters, digits and underscores.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf org list sobject record-counts`

#### Examples

```powershell
PS> Get-SalesforceSObjectRecordCount -SObject Account, Contact -TargetOrg dev1
```

Record counts of Account and Contact.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceSObjectRecordCount -Examples"
- For more information, type: "Get-Help Get-SalesforceSObjectRecordCount -Detailed"
- For technical information, type: "Get-Help Get-SalesforceSObjectRecordCount -Full"
- For online help, type: "Get-Help Get-SalesforceSObjectRecordCount -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-limits>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceFile

#### Synopsis

Uploads a local file to an org as a Salesforce File.

#### Syntax

```powershell
New-SalesforceFile [-File] <String> [[-ParentId] <String>] [[-Title] <String>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf data create file. The file becomes a ContentVersion, so it shows under Files in the org. Give -ParentId to attach it to a record, for example an account. Supports -WhatIf and -Confirm; it does not prompt by default. The file is read by the CLI; psfdx only checks that it exists.

#### Parameters

- `-File` (String, required): Path of the local file to upload. Passed to sf as --file. It must exist. Required.
- `-ParentId` (String): ID of the record to attach the file to (a 15 or 18 character ID). Passed to sf as --parent-id.
- `-Title` (String): Title of the file in Salesforce. By default the CLI uses the file name. Passed to sf as --title.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf data create file`

#### Examples

```powershell
PS> New-SalesforceFile -File '.\Q4 report.pdf' -ParentId 001xx000003DGb2AAG -Title 'Q4 report' -TargetOrg myorg
```

Upload the PDF and attach it to the account.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceFile -Examples"
- For more information, type: "Get-Help New-SalesforceFile -Detailed"
- For technical information, type: "Get-Help New-SalesforceFile -Full"
- For online help, type: "Get-Help New-SalesforceFile -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceRecord

#### Synopsis

Creates one record (sf data create record).

#### Syntax

```powershell
New-SalesforceRecord [-Type] <String> [-FieldUpdates] <String> [[-TargetOrg] <String>] [-UseToolingApi] [-SkipAssignmentRules] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

-FieldUpdates is the CLI's values string, for example "Name='Acme' Industry='Energy'". Supports -WhatIf and -Confirm; it does not prompt by default.

#### Parameters

- `-Type` (String, required): API name of the Salesforce or Tooling API object that you're inserting a record into. Passed to sf as --sobject. Required.
- `-FieldUpdates` (String, required): Values for the flags in the form &lt;fieldName&gt;=&lt;value&gt;, separate multiple pairs with spaces. Passed to sf as --values. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-UseToolingApi` (switch): Use Tooling API so you can insert a record in a Tooling API object. Adds --use-tooling-api.
- `-SkipAssignmentRules` (switch): Do not run the assignment rules when the record is created. This matters for a Case or Lead, which are assigned by rule otherwise. Adds --skip-assignment-rules.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf data create record`

#### Examples

```powershell
PS> New-SalesforceRecord -Type Account -FieldUpdates "Name='Acme'" -WhatIf
```

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceRecord -Examples"
- For more information, type: "Get-Help New-SalesforceRecord -Detailed"
- For technical information, type: "Get-Help New-SalesforceRecord -Full"
- For online help, type: "Get-Help New-SalesforceRecord -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceRecord

#### Synopsis

Deletes one record, by ID or by field values (sf data delete record).

#### Syntax

```powershell
Remove-SalesforceRecord -Type <String> -Id <String> [-UseToolingApi] [-TargetOrg <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
Remove-SalesforceRecord -Type <String> -Where <IDictionary> [-UseToolingApi] [-TargetOrg <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Select the record as for Get-SalesforceRecord: -Id, or -Where (field values that identify exactly one record). Asks for confirmation by default, naming the object, the record and the org; -WhatIf makes no CLI call. Returns the CLI's result (the deleted record's Id). A record that does not exist, or a -Where that matches several, makes the cmdlet throw the CLI's message, so nothing is hidden. Scripts that run unattended need -Confirm:$false.

#### Parameters

- `-Type` (String, required): API name of the Salesforce or Tooling API object that you're deleting a record from. Passed to sf as --sobject. Required.
- `-Id` (String, required): ID of the record you're deleting. Passed to sf as --record-id. Required in the ById parameter set. Alias: RecordId. Accepts input from the pipeline by property name.
- `-Where` (IDictionary, required): List of &lt;fieldName&gt;=&lt;value&gt; pairs that identify the record you want to delete. Passed to sf as --where. Required in the ByFields parameter set.
- `-UseToolingApi` (switch): Use Tooling API so you can delete a record from a Tooling API object. Adds --use-tooling-api.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf data delete record`

#### Examples

```powershell
PS> Remove-SalesforceRecord -Type Account -Id 001xx000003DGb2AAG -TargetOrg myorg -WhatIf
```

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceRecord -Examples"
- For more information, type: "Get-Help Remove-SalesforceRecord -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceRecord -Full"
- For online help, type: "Get-Help Remove-SalesforceRecord -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Search-SalesforceRecords

#### Synopsis

Runs a SOSL text search and returns the matching records as objects.

#### Syntax

```powershell
Search-SalesforceRecords -Query <String> [-ResultFormat <String>] [-TargetOrg <String>] [<CommonParameters>]
Search-SalesforceRecords -File <String> [-ResultFormat <String>] [-TargetOrg <String>] [<CommonParameters>]
```

#### Description

Runs sf data search with --query or --file. SOSL searches the text fields of several objects at once, for example FIND {Acme} IN ALL FIELDS RETURNING Account(Id, Name), Contact(Id, Name). With the default -ResultFormat json the records are returned as objects without their attributes property, each with an SObject property that holds the object it came from; no match returns nothing (wrap the call in @() for an empty array). With human or csv the CLI text is returned as it is. A bad search throws the CLI message. The query is passed as one argument, so braces and quotes need no escaping; on Windows the CLI shim rejects a double quote or a line break in an argument, so put such a query in a file and use -File.

#### Parameters

- `-Query` (String, required): SOSL query to execute. Passed to sf as --query. Give -Query or -File.
- `-File` (String, required): File that contains the SOSL query. Passed to sf as --file. It must exist. Give -Query or -File.
- `-ResultFormat` (String): Format to display the results. Default: json. Valid values: human, csv, json. Passed to sf as --result-format for human and csv; json is read through --json.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf data search`

#### Examples

```powershell
PS> Search-SalesforceRecords -Query 'FIND {Acme} IN NAME FIELDS RETURNING Account(Id, Name), Contact(Id, Name)' -TargetOrg dev1
```

Accounts and contacts whose name matches Acme.

#### Remarks

- To see the examples, type: "Get-Help Search-SalesforceRecords -Examples"
- For more information, type: "Get-Help Search-SalesforceRecords -Detailed"
- For technical information, type: "Get-Help Search-SalesforceRecords -Full"
- For online help, type: "Get-Help Search-SalesforceRecords -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Select-SalesforceRecords

#### Synopsis

Runs a SOQL query and returns the records as objects.

#### Syntax

```powershell
Select-SalesforceRecords [[-Query] <String>] [[-File] <String>] [[-TargetOrg] <String>] [-UseToolingApi] [-IncludeDeletedRows] [[-ResultFormat] <String>] [[-OutputFile] <String>] [<CommonParameters>]
```

#### Description

Runs sf data query with --query or --file. With the default -ResultFormat json the records are returned as objects without their attributes property; an empty result returns nothing (wrap the call in @() for an empty array). With human or csv the CLI text is returned as it is. A failing query throws the CLI message. The query text is passed as one argument, so quotes and special characters need no escaping.

#### Parameters

- `-Query` (String): SOQL query to execute. Passed to sf as --query.
- `-File` (String): File that contains the SOQL query. Passed to sf as --file.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-UseToolingApi` (switch): Use Tooling API so you can run queries on Tooling API objects. Adds --use-tooling-api.
- `-IncludeDeletedRows` (switch): Include deleted records. By default, deleted records are not returned. Adds --all-rows.
- `-ResultFormat` (String): Format to display the results; the --json flag overrides this flag. Default: json. Valid values: human, json, csv.
- `-OutputFile` (String): File where records are written; only CSV and JSON output formats are supported. Passed to sf as --output-file.

#### Salesforce CLI

- `sf data query`

#### Examples

```powershell
PS> Select-SalesforceRecords -Query 'SELECT Id, Name FROM Account LIMIT 5' -TargetOrg dev1
```

Five accounts as objects.

#### Remarks

- To see the examples, type: "Get-Help Select-SalesforceRecords -Examples"
- For more information, type: "Get-Help Select-SalesforceRecords -Detailed"
- For technical information, type: "Get-Help Select-SalesforceRecords -Full"
- For online help, type: "Get-Help Select-SalesforceRecords -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Set-SalesforceRecord

#### Synopsis

Updates one record by ID (sf data update record).

#### Syntax

```powershell
Set-SalesforceRecord -Id <String> -Type <String> -FieldUpdates <String> [-TargetOrg <String>] [-UseToolingApi] [-SkipAssignmentRules] [-WhatIf] [-Confirm] [<CommonParameters>]
Set-SalesforceRecord -Where <IDictionary> -Type <String> -FieldUpdates <String> [-TargetOrg <String>] [-UseToolingApi] [-SkipAssignmentRules] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Select the record by -Id (which can come from the pipeline, as an Id or RecordId property), or by -Where, field values that identify exactly one record, as for Get-SalesforceRecord. -FieldUpdates is the CLI's values string, for example "Name='Acme' Active__c=true". Supports -WhatIf and -Confirm; it does not prompt by default. A -Where that matches no record, or several, makes the cmdlet throw the CLI's message.

#### Parameters

- `-Id` (String, required): ID of the record you're updating. Passed to sf as --record-id. Required in the ById parameter set. Alias: RecordId. Accepts input from the pipeline by property name.
- `-Where` (IDictionary, required): List of &lt;fieldName&gt;=&lt;value&gt; pairs that identify the record you want to update, for example @{ Name = 'Acme' }. Passed to sf as --where. Required in the ByFields parameter set. Values may not contain quotes or control characters.
- `-Type` (String, required): API name of the Salesforce or Tooling API object that contains the record you're updating. Passed to sf as --sobject. Required.
- `-FieldUpdates` (String, required): Fields that you're updating, in the format of &lt;fieldName&gt;=&lt;value&gt; pairs. Passed to sf as --values. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-UseToolingApi` (switch): Use Tooling API so you can update a record in a Tooling API object. Adds --use-tooling-api.
- `-SkipAssignmentRules` (switch): Do not run the assignment rules when the record is updated. This matters for a Case or Lead. Adds --skip-assignment-rules.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf data update record`

#### Examples

```powershell
PS> Select-SalesforceRecords -Query "SELECT Id FROM Account WHERE Name = 'Old'" | Set-SalesforceRecord -Type Account -FieldUpdates "Name='New'" -WhatIf
```

#### Remarks

- To see the examples, type: "Get-Help Set-SalesforceRecord -Examples"
- For more information, type: "Get-Help Set-SalesforceRecord -Detailed"
- For technical information, type: "Get-Help Set-SalesforceRecord -Full"
- For online help, type: "Get-Help Set-SalesforceRecord -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Upsert-SalesforceRecord

#### Synopsis

Creates or updates one record, matched by an external ID.

#### Syntax

```powershell
Upsert-SalesforceRecord [-Type] <String> [-ExternalIdField] <String> [-ExternalId] <String> [-Fields] <IDictionary> [[-ApiVersion] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Matches an existing record by its external ID and updates it, or creates a record if no match exists. The result reports Created or Updated and includes the record Id when the API returns it.

#### Parameters

- `-Type` (String, required): API name of the object, for example Account. Required.
- `-ExternalIdField` (String, required): API name of the external ID field used to find the record. Required.
- `-ExternalId` (String, required): Value of the external ID. It is URL-escaped in the request path. Required.
- `-Fields` (IDictionary, required): Hashtable of field API names and values to set, for example @{ Name = 'Acme' }. It must not be empty. Required.
- `-ApiVersion` (String): REST API version to use, for example v62.0 or 62.0. If omitted, the latest version the org supports is used.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf api request rest`

#### Examples

```powershell
PS> Upsert-SalesforceRecord -Type Account -ExternalIdField Ext_Id__c -ExternalId A-100 -Fields @{ Name = 'Acme' } -TargetOrg dev1
```

Create or update the account whose Ext_Id__c is A-100.

#### Remarks

- To see the examples, type: "Get-Help Upsert-SalesforceRecord -Examples"
- For more information, type: "Get-Help Upsert-SalesforceRecord -Detailed"
- For technical information, type: "Get-Help Upsert-SalesforceRecord -Full"
- For online help, type: "Get-Help Upsert-SalesforceRecord -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-api>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>
