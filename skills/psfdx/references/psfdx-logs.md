# psfdx-logs command reference

Generated from the commands' own help by `site/Update-ModuleReference.ps1`: do not edit it by hand. The same reference is on the website: <https://psfdx.com/modules/psfdx-logs/>. It is part of the `psfdx` package; see the [installation guide](https://github.com/tonygward/psfdx/blob/main/docs/install.md).

16 commands. Every command also takes the common parameters, such as `-Verbose`.

## Commands

[Convert-SalesforceDebugLog](#convert-salesforcedebuglog), [Disable-SalesforceDebugLogging](#disable-salesforcedebuglogging), [Enable-SalesforceDebugLogging](#enable-salesforcedebuglogging), [Export-SalesforceDebugLogs](#export-salesforcedebuglogs), [Export-SalesforceEventFile](#export-salesforceeventfile), [Export-SalesforceEventFiles](#export-salesforceeventfiles), [Get-SalesforceDebugLogging](#get-salesforcedebuglogging), [Get-SalesforceDebugLogs](#get-salesforcedebuglogs), [Get-SalesforceEventFile](#get-salesforceeventfile), [Get-SalesforceFlowInterviews](#get-salesforceflowinterviews), [Get-SalesforceLoginFailures](#get-salesforceloginfailures), [Get-SalesforceLoginHistory](#get-salesforceloginhistory), [Out-Notepad](#out-notepad), [Select-SalesforceDebugLogs](#select-salesforcedebuglogs), [Select-SalesforceEventFiles](#select-salesforceeventfiles), [Watch-SalesforceDebugLogs](#watch-salesforcedebuglogs)

### Convert-SalesforceDebugLog

#### Synopsis

Converts the text of a debug log into one object per line (in development).

#### Syntax

```powershell
Convert-SalesforceDebugLog [-Log] <String> [<CommonParameters>]
```

#### Description

Does not use the Salesforce CLI. Pipe in the text of a log, for example from Get-SalesforceDebugLogs -Raw; the first (header) line is skipped and each remaining line is split on | into DateTime, LogType and, when present, SubType and Detail. It writes a warning that it is still in development, so the properties may change.

#### Parameters

- `-Log` (String, required): The log text to convert. Accepts pipeline input. Required.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Get-SalesforceDebugLogs -Last 1 -Raw -TargetOrg dev1 | Convert-SalesforceDebugLog | Select-Object -First 20
```

The first twenty log lines as objects.

#### Remarks

- To see the examples, type: "Get-Help Convert-SalesforceDebugLog -Examples"
- For more information, type: "Get-Help Convert-SalesforceDebugLog -Detailed"
- For technical information, type: "Get-Help Convert-SalesforceDebugLog -Full"
- For online help, type: "Get-Help Convert-SalesforceDebugLog -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Disable-SalesforceDebugLogging

#### Synopsis

Deletes a trace flag to stop debug logging (sf apex trace delete).

#### Syntax

```powershell
Disable-SalesforceDebugLogging [-TraceId] <String> [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

-TraceId can come from the pipeline: a trace flag from Get-SalesforceDebugLogging is used through its Id. Each flag is confirmed on its own, so -WhatIf previews every delete, and an org with no trace flags deletes nothing.

#### Parameters

- `-TraceId` (String, required): ID of the trace flag to delete. Passed to sf as --trace-flag-id. Required. Alias: Id, TraceFlagId. Accepts input from the pipeline by property name.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf apex trace delete`

#### Examples

```powershell
PS> Get-SalesforceDebugLogging -TargetOrg myorg | Disable-SalesforceDebugLogging -TargetOrg myorg -WhatIf
```

#### Remarks

- To see the examples, type: "Get-Help Disable-SalesforceDebugLogging -Examples"
- For more information, type: "Get-Help Disable-SalesforceDebugLogging -Detailed"
- For technical information, type: "Get-Help Disable-SalesforceDebugLogging -Full"
- For online help, type: "Get-Help Disable-SalesforceDebugLogging -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-apex>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Enable-SalesforceDebugLogging

#### Synopsis

Turns on debug logging for a user, Apex class or Apex trigger by creating a trace flag.

#### Syntax

```powershell
Enable-SalesforceDebugLogging -TracedEntityId <String> -DebugLevel <String> [-LogType <String>] [-Duration <Int32>] [-TargetOrg <String>] [<CommonParameters>]
Enable-SalesforceDebugLogging -Username <String> -DebugLevel <String> [-LogType <String>] [-Duration <Int32>] [-TargetOrg <String>] [<CommonParameters>]
Enable-SalesforceDebugLogging -ApexClass <String> -DebugLevel <String> [-LogType <String>] [-Duration <Int32>] [-TargetOrg <String>] [<CommonParameters>]
Enable-SalesforceDebugLogging -ApexTrigger <String> -DebugLevel <String> [-LogType <String>] [-Duration <Int32>] [-TargetOrg <String>] [<CommonParameters>]
```

#### Description

Runs sf apex trace create. Identify what to trace with one of -TracedEntityId, -Username, -ApexClass or -ApexTrigger; the last three are looked up with a SOQL query first and the cmdlet stops if no record, or more than one, matches. -DebugLevel names an existing debug level. The trace flag stays until it expires or you remove it with Disable-SalesforceDebugLogging.

#### Parameters

- `-TracedEntityId` (String, required): ID of the user, Apex class, or Apex trigger to trace. Passed to sf as --traced-entity-id. Required in the Id parameter set.
- `-Username` (String, required): User name of the user to trace. psfdx looks up the user's ID and passes it as --traced-entity-id. Required in the Username parameter set.
- `-ApexClass` (String, required): Name of the Apex class to trace. psfdx looks up its ID and passes it as --traced-entity-id. Required in the ApexClass parameter set.
- `-ApexTrigger` (String, required): Name of the Apex trigger to trace. psfdx looks up its ID and passes it as --traced-entity-id. Required in the ApexTrigger parameter set.
- `-DebugLevel` (String, required): Developer name of an existing debug level to apply. Passed to sf as --debug-level. Required.
- `-LogType` (String): Type of trace flag to create. Passed to sf as --log-type. Valid values: DEVELOPER_LOG, USER_DEBUG.
- `-Duration` (Int32): Duration, in minutes, before the trace flag expires. Maximum is 1440 (24 hours). Passed to sf as --duration. Range: 1 to 1440.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf apex trace create`

#### Examples

```powershell
PS> Enable-SalesforceDebugLogging -Username me@example.com -DebugLevel SFDC_DevConsole -Duration 60 -TargetOrg dev1
```

Trace one user for an hour.

#### Remarks

- To see the examples, type: "Get-Help Enable-SalesforceDebugLogging -Examples"
- For more information, type: "Get-Help Enable-SalesforceDebugLogging -Detailed"
- For technical information, type: "Get-Help Enable-SalesforceDebugLogging -Full"
- For online help, type: "Get-Help Enable-SalesforceDebugLogging -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-apex>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Export-SalesforceDebugLogs

#### Synopsis

Saves the most recent debug logs to files.

#### Syntax

```powershell
Export-SalesforceDebugLogs [[-Limit] <Int32>] [[-OutputFolder] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Lists the logs with Select-SalesforceDebugLogs, keeps the first -Limit of them and writes each one with Get-SalesforceDebugLogs to &lt;log id&gt;.log in the output folder, with a progress bar. Existing files with the same name are overwritten.

#### Parameters

- `-Limit` (Int32): How many logs to save, taken from the start of the list the CLI returns. Default 50. Default: 50.
- `-OutputFolder` (String): Folder to write the .log files to. It must exist. Defaults to the current folder.
- `-TargetOrg` (String): Username or alias of the org to read the logs from. If omitted, the Salesforce CLI uses the default target org.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Export-SalesforceDebugLogs -Limit 5 -OutputFolder .\logs -TargetOrg dev1
```

Save the five newest logs.

#### Remarks

- To see the examples, type: "Get-Help Export-SalesforceDebugLogs -Examples"
- For more information, type: "Get-Help Export-SalesforceDebugLogs -Detailed"
- For technical information, type: "Get-Help Export-SalesforceDebugLogs -Full"
- For online help, type: "Get-Help Export-SalesforceDebugLogs -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Export-SalesforceEventFile

#### Synopsis

Downloads one Event Monitoring log file and saves it as a CSV.

#### Syntax

```powershell
Export-SalesforceEventFile [-Id] <String> [[-OutputFolder] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Gets the file with Get-SalesforceEventFile and writes it to &lt;Id&gt;.csv in the output folder. The ID must be a 15 or 18 character Salesforce ID, so it cannot point outside the folder.

#### Parameters

- `-Id` (String, required): ID of the EventLogFile record. Required.
- `-OutputFolder` (String): Folder to write the CSV to. It must exist. Defaults to the current folder.
- `-TargetOrg` (String): Username or alias of the org. If omitted, the Salesforce CLI uses the default target org.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Export-SalesforceEventFile -Id 0AT000000000001AAA -OutputFolder .\events -TargetOrg prod
```

Save one event log file.

#### Remarks

- To see the examples, type: "Get-Help Export-SalesforceEventFile -Examples"
- For more information, type: "Get-Help Export-SalesforceEventFile -Detailed"
- For technical information, type: "Get-Help Export-SalesforceEventFile -Full"
- For online help, type: "Get-Help Export-SalesforceEventFile -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Export-SalesforceEventFiles

#### Synopsis

Downloads several Event Monitoring log files as CSVs.

#### Syntax

```powershell
Export-SalesforceEventFiles [[-EventType] <String>] [[-After] <DateTime>] [[-Before] <DateTime>] [[-Limit] <Int32>] [[-OutputFolder] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Finds files with Select-SalesforceEventFiles using the filters you give, then saves each one with Export-SalesforceEventFile, with a progress bar. See Select-SalesforceEventFiles for how the filters work.

#### Parameters

- `-EventType` (String): SOQL query to execute. Passed to sf as --query.
- `-After` (DateTime): SOQL query to execute. Passed to sf as --query.
- `-Before` (DateTime): SOQL query to execute. Passed to sf as --query.
- `-Limit` (Int32): SOQL query to execute. Passed to sf as --query. Default: 200.
- `-OutputFolder` (String): Folder to write the CSV files to. It must exist. Defaults to the current folder.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf data query`

#### Examples

```powershell
PS> Export-SalesforceEventFiles -EventType Login -After (Get-Date).AddDays(-7) -OutputFolder .\events -TargetOrg prod
```

Last week's login event files.

#### Remarks

- To see the examples, type: "Get-Help Export-SalesforceEventFiles -Examples"
- For more information, type: "Get-Help Export-SalesforceEventFiles -Detailed"
- For technical information, type: "Get-Help Export-SalesforceEventFiles -Full"
- For online help, type: "Get-Help Export-SalesforceEventFiles -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceDebugLogging

#### Synopsis

Lists the trace flags that turn on debug logging.

#### Syntax

```powershell
Get-SalesforceDebugLogging [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf apex trace list and returns one object per trace flag. Pipe them to Disable-SalesforceDebugLogging to remove them.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf apex trace list`

#### Examples

```powershell
PS> Get-SalesforceDebugLogging -TargetOrg dev1
```

Active trace flags.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceDebugLogging -Examples"
- For more information, type: "Get-Help Get-SalesforceDebugLogging -Detailed"
- For technical information, type: "Get-Help Get-SalesforceDebugLogging -Full"
- For online help, type: "Get-Help Get-SalesforceDebugLogging -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-apex>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceDebugLogs

#### Synopsis

Fetches one debug log, or the newest few, from an org.

#### Syntax

```powershell
Get-SalesforceDebugLogs [[-OutputDir] <String>] [[-LogId] <String>] [[-Last] <Int32>] [-Raw] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf apex get log with --log-id or --number. Give exactly one of -LogId and -Last. With -OutputDir the CLI saves the logs as files; with -Raw the text is returned as it is.

#### Parameters

- `-OutputDir` (String): Directory for saving the log files. Passed to sf as --output-dir.
- `-LogId` (String): ID of the specific log to display. Passed to sf as --log-id.
- `-Last` (Int32): Fetch this many of the newest logs. Passed as --number. Use instead of -LogId.
- `-Raw` (switch): Return the log text as the CLI prints it.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf apex get log`

#### Examples

```powershell
PS> Get-SalesforceDebugLogs -Last 1 -Raw -TargetOrg dev1
```

The newest log, as text.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceDebugLogs -Examples"
- For more information, type: "Get-Help Get-SalesforceDebugLogs -Detailed"
- For technical information, type: "Get-Help Get-SalesforceDebugLogs -Full"
- For online help, type: "Get-Help Get-SalesforceDebugLogs -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-apex>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceEventFile

#### Synopsis

Downloads the content of one Event Monitoring log file.

#### Syntax

```powershell
Get-SalesforceEventFile [-Id] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Finds the newest REST API version of the org, then runs sf api request rest on /services/data/&lt;version&gt;/sobjects/EventLogFile/&lt;Id&gt;/Logfile and returns the CSV text. The ID must be a 15 or 18 character Salesforce ID.

#### Parameters

- `-Id` (String, required): ID of the EventLogFile record. Required.
- `-TargetOrg` (String): Username or alias of the org. If omitted, the Salesforce CLI uses the default target org. Passed to sf as --target-org.

#### Salesforce CLI

- `sf api request rest`

#### Examples

```powershell
PS> Get-SalesforceEventFile -Id 0AT000000000001AAA -TargetOrg prod
```

The CSV of that file.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceEventFile -Examples"
- For more information, type: "Get-Help Get-SalesforceEventFile -Detailed"
- For technical information, type: "Get-Help Get-SalesforceEventFile -Full"
- For online help, type: "Get-Help Get-SalesforceEventFile -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-api>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceFlowInterviews

#### Synopsis

Lists flow interviews, for example the ones that failed.

#### Syntax

```powershell
Get-SalesforceFlowInterviews [[-Type] <String>] [[-After] <DateTime>] [[-Limit] <Int32>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf data query on FlowInterview (Id, CreatedDate, InterviewLabel, InterviewStatus, Error) filtered by status and optional date, newest first. Values are escaped as SOQL literals.

#### Parameters

- `-Type` (String): Interview status to list: Error, Paused, Running, Completed, VersionPaused, Autosaved, Expired, or All (the default). Default: All. Valid values: Error, Paused, Running, Completed, VersionPaused, Autosaved, Expired, All.
- `-After` (DateTime): Only interviews created at or after this time.
- `-Limit` (Int32): SOQL query to execute. Passed to sf as --query. Default: 200.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf data query`

#### Examples

```powershell
PS> Get-SalesforceFlowInterviews -Type Error -After (Get-Date).AddDays(-1) -TargetOrg prod
```

Flow errors in the last day.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceFlowInterviews -Examples"
- For more information, type: "Get-Help Get-SalesforceFlowInterviews -Detailed"
- For technical information, type: "Get-Help Get-SalesforceFlowInterviews -Full"
- For online help, type: "Get-Help Get-SalesforceFlowInterviews -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceLoginFailures

#### Synopsis

Lists login attempts that did not succeed.

#### Syntax

```powershell
Get-SalesforceLoginFailures [[-After] <DateTime>] [[-Before] <DateTime>] [[-Limit] <Int32>] [[-Username] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Calls Get-SalesforceLoginHistory with the same filters and keeps the rows whose Status is not Success. Returns an empty array when there are none.

#### Parameters

- `-After` (DateTime): Only logins at or after this time.
- `-Before` (DateTime): Only logins at or before this time.
- `-Limit` (Int32): Maximum number of login history rows to read before filtering.
- `-Username` (String): Only this user name.
- `-TargetOrg` (String): Username or alias of the org. If omitted, the Salesforce CLI uses the default target org.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Get-SalesforceLoginFailures -After (Get-Date).AddDays(-1) -TargetOrg prod
```

Failed logins in the last day.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceLoginFailures -Examples"
- For more information, type: "Get-Help Get-SalesforceLoginFailures -Detailed"
- For technical information, type: "Get-Help Get-SalesforceLoginFailures -Full"
- For online help, type: "Get-Help Get-SalesforceLoginFailures -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceLoginHistory

#### Synopsis

Lists login history records, newest first.

#### Syntax

```powershell
Get-SalesforceLoginHistory [[-After] <DateTime>] [[-Before] <DateTime>] [[-Username] <String>] [[-Limit] <Int32>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf data query on LoginHistory (Id, LoginTime, UserId, SourceIp, Application, Status). The user filter is applied through a subquery on User. Values are escaped as SOQL literals.

#### Parameters

- `-After` (DateTime): Only logins at or after this time.
- `-Before` (DateTime): Only logins at or before this time.
- `-Username` (String): Only this user name.
- `-Limit` (Int32): SOQL query to execute. Passed to sf as --query.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf data query`

#### Examples

```powershell
PS> Get-SalesforceLoginHistory -Username me@example.com -Limit 20 -TargetOrg prod
```

The last twenty logins of one user.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceLoginHistory -Examples"
- For more information, type: "Get-Help Get-SalesforceLoginHistory -Detailed"
- For technical information, type: "Get-Help Get-SalesforceLoginHistory -Full"
- For online help, type: "Get-Help Get-SalesforceLoginHistory -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Out-Notepad

#### Synopsis

Shows text in Notepad (Windows only).

#### Syntax

```powershell
Out-Notepad [-Content] <String> [<CommonParameters>]
```

#### Description

Does not use the Salesforce CLI. Pipe text in; it is written to a new temporary file that Notepad opens. The file is not deleted afterwards, so remove it if the text is sensitive. On other systems it does nothing.

#### Parameters

- `-Content` (String, required): The text to show. Accepts pipeline input. Required.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Get-SalesforceDebugLogs -Last 1 -Raw -TargetOrg dev1 | Out-Notepad
```

Read the newest log in Notepad.

#### Remarks

- To see the examples, type: "Get-Help Out-Notepad -Examples"
- For more information, type: "Get-Help Out-Notepad -Detailed"
- For technical information, type: "Get-Help Out-Notepad -Full"
- For online help, type: "Get-Help Out-Notepad -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Select-SalesforceDebugLogs

#### Synopsis

Lists the debug logs in an org.

#### Syntax

```powershell
Select-SalesforceDebugLogs [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf apex list log and returns one object per log (Id, Application, Operation, StartTime, LogLength, and so on), in the order the CLI returns them.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf apex list log`

#### Examples

```powershell
PS> Select-SalesforceDebugLogs -TargetOrg dev1 | Select-Object -First 5
```

The five newest logs.

#### Remarks

- To see the examples, type: "Get-Help Select-SalesforceDebugLogs -Examples"
- For more information, type: "Get-Help Select-SalesforceDebugLogs -Detailed"
- For technical information, type: "Get-Help Select-SalesforceDebugLogs -Full"
- For online help, type: "Get-Help Select-SalesforceDebugLogs -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-apex>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Select-SalesforceEventFiles

#### Synopsis

Lists Event Monitoring log files.

#### Syntax

```powershell
Select-SalesforceEventFiles [[-EventType] <String>] [[-After] <DateTime>] [[-Before] <DateTime>] [[-Limit] <Int32>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf data query on EventLogFile (Id, EventType, LogDate, LogFileLength, Sequence, Interval, CreatedDate), newest log date first, with optional filters. Values are escaped as SOQL literals.

#### Parameters

- `-EventType` (String): Only this event type, for example Login or ApexExecution. Passed to sf as --query.
- `-After` (DateTime): Only files with a LogDate at or after this time. Passed to sf as --query.
- `-Before` (DateTime): Only files with a LogDate at or before this time. Passed to sf as --query.
- `-Limit` (Int32): Maximum number of files to return. Passed to sf as --query.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf data query`

#### Examples

```powershell
PS> Select-SalesforceEventFiles -EventType Login -Limit 10 -TargetOrg prod
```

The ten newest login files.

#### Remarks

- To see the examples, type: "Get-Help Select-SalesforceEventFiles -Examples"
- For more information, type: "Get-Help Select-SalesforceEventFiles -Detailed"
- For technical information, type: "Get-Help Select-SalesforceEventFiles -Full"
- For online help, type: "Get-Help Select-SalesforceEventFiles -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Watch-SalesforceDebugLogs

#### Synopsis

Streams debug logs from an org to the terminal.

#### Syntax

```powershell
Watch-SalesforceDebugLogs [[-DebugLevel] <String>] [-SkipTraceFlag] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf apex tail log with --color, which keeps running until you press Ctrl+C. Unless you pass -SkipTraceFlag the CLI first creates a trace flag for you, which stays after you stop.

#### Parameters

- `-DebugLevel` (String): Debug level to set on the DEVELOPER_LOG trace flag for your user. Passed to sf as --debug-level.
- `-SkipTraceFlag` (switch): Skip trace flag setup. Assumes that a trace flag and debug level are fully set up. Adds --skip-trace-flag.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf apex tail log`

#### Examples

```powershell
PS> Watch-SalesforceDebugLogs -DebugLevel SFDC_DevConsole -TargetOrg dev1
```

Follow the logs of the org.

#### Remarks

- To see the examples, type: "Get-Help Watch-SalesforceDebugLogs -Examples"
- For more information, type: "Get-Help Watch-SalesforceDebugLogs -Detailed"
- For technical information, type: "Get-Help Watch-SalesforceDebugLogs -Full"
- For online help, type: "Get-Help Watch-SalesforceDebugLogs -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-apex>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>
