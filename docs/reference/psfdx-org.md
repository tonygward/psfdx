# psfdx-org command reference

Generated from the commands' own help by `site/Update-ModuleReference.ps1`: do not edit it by hand. The same reference is on the website: <https://psfdx.com/modules/psfdx-org/>. It is part of the `psfdx` package; see the [installation guide](../install.md).

12 commands. Every command also takes the common parameters, such as `-Verbose`.

## Commands

**Sandboxes**: [Copy-SalesforceSandbox](#copy-salesforcesandbox), [Get-SalesforceSandboxes](#get-salesforcesandboxes), [Get-SalesforceSandboxRefreshStatus](#get-salesforcesandboxrefreshstatus), [New-SalesforceSandbox](#new-salesforcesandbox), [Remove-SalesforceSandbox](#remove-salesforcesandbox), [Resume-SalesforceSandbox](#resume-salesforcesandbox), [Update-SalesforceSandbox](#update-salesforcesandbox)

**Scratch Orgs**: [Get-SalesforceScratchOrgs](#get-salesforcescratchorgs), [New-SalesforceScratchOrg](#new-salesforcescratchorg), [Remove-SalesforceScratchOrg](#remove-salesforcescratchorg), [Remove-SalesforceScratchOrgs](#remove-salesforcescratchorgs), [Resume-SalesforceScratchOrg](#resume-salesforcescratchorg)

## Sandboxes

### Copy-SalesforceSandbox

#### Synopsis

Creates a sandbox as a copy of another sandbox.

#### Syntax

```powershell
Copy-SalesforceSandbox -SourceSandboxName <String> -CloneSandboxName <String> [-LicenseType <String>] [-Alias <String>] [-WaitMinutes <Int32>] [-NoPrompt] [-Async] [-PollIntervalSeconds <Int32>] [-SetDefault] [-TargetOrg <String>] [<CommonParameters>]
Copy-SalesforceSandbox -SourceId <String> -CloneSandboxName <String> [-LicenseType <String>] [-Alias <String>] [-WaitMinutes <Int32>] [-NoPrompt] [-Async] [-PollIntervalSeconds <Int32>] [-SetDefault] [-TargetOrg <String>] [<CommonParameters>]
```

#### Description

Runs sf org create sandbox with --source-sandbox-name, which clones an existing sandbox. The CLI waits only when you give -WaitMinutes.

#### Parameters

- `-SourceSandboxName` (String, required): Name of the sandbox org to clone. Passed to sf as --source-sandbox-name. Required unless you give -SourceId.
- `-SourceId` (String, required): ID of the sandbox to clone, instead of its name. Passed to sf as --source-id. Use it instead of -SourceSandboxName.
- `-CloneSandboxName` (String, required): Name of the sandbox org. Passed to sf as --name. Required.
- `-LicenseType` (String): Type of sandbox license. Passed to sf as --license-type.
- `-Alias` (String): Alias for the sandbox org. Passed to sf as --alias.
- `-WaitMinutes` (Int32): Number of minutes to wait for the sandbox org to be ready. Passed to sf as --wait.
- `-NoPrompt` (switch): Don't prompt for confirmation about the sandbox configuration. Adds --no-prompt.
- `-Async` (switch): Request the clone and return at once, without waiting for it to be ready. Finish with Resume-SalesforceSandbox. Adds --async.
- `-PollIntervalSeconds` (Int32): Number of seconds to wait between checks while waiting for the sandbox. Passed to sf as --poll-interval.
- `-SetDefault` (switch): Set the sandbox as your default org once it is ready. Adds --set-default.
- `-TargetOrg` (String): Username or alias of the production org that contains the sandbox license. Passed to sf as --target-org.

#### Salesforce CLI

- `sf org create sandbox`

#### Examples

```powershell
PS> Copy-SalesforceSandbox -SourceSandboxName dev1 -CloneSandboxName dev2 -TargetOrg prod
```

Clone dev1 as dev2.

#### Remarks

- To see the examples, type: "Get-Help Copy-SalesforceSandbox -Examples"
- For more information, type: "Get-Help Copy-SalesforceSandbox -Detailed"
- For technical information, type: "Get-Help Copy-SalesforceSandbox -Full"
- For online help, type: "Get-Help Copy-SalesforceSandbox -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceSandboxes

#### Synopsis

Lists the sandboxes this computer is logged in to.

#### Syntax

```powershell
Get-SalesforceSandboxes [[-Name] <String>] [<CommonParameters>]
```

#### Description

Runs sf org list and returns the connected orgs that are sandboxes. With -Name, only those whose sandbox name, user name or alias equals it. It reads the local list of orgs; there is no -TargetOrg.

#### Parameters

- `-Name` (String): Keep only sandboxes whose sandbox name, user name or alias equals this value. The filter runs in PowerShell.

#### Salesforce CLI

- `sf org list`

#### Examples

```powershell
PS> Get-SalesforceSandboxes
```

Every sandbox this computer knows about.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceSandboxes -Examples"
- For more information, type: "Get-Help Get-SalesforceSandboxes -Detailed"
- For technical information, type: "Get-Help Get-SalesforceSandboxes -Full"
- For online help, type: "Get-Help Get-SalesforceSandboxes -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceSandboxRefreshStatus

#### Synopsis

Shows when a sandbox was last refreshed and its refresh state.

#### Syntax

```powershell
Get-SalesforceSandboxRefreshStatus [-Name] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf data query on the Tooling API objects SandboxInfo and SandboxProcess (two queries) for the sandbox name, and combines them. The name is escaped as a SOQL literal.

#### Parameters

- `-Name` (String, required): Name of the sandbox. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf data query`

#### Examples

```powershell
PS> Get-SalesforceSandboxRefreshStatus -Name dev1 -TargetOrg prod
```

The refresh status of dev1.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceSandboxRefreshStatus -Examples"
- For more information, type: "Get-Help Get-SalesforceSandboxRefreshStatus -Detailed"
- For technical information, type: "Get-Help Get-SalesforceSandboxRefreshStatus -Full"
- For online help, type: "Get-Help Get-SalesforceSandboxRefreshStatus -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-data>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceSandbox

#### Synopsis

Creates a sandbox from production.

#### Syntax

```powershell
New-SalesforceSandbox [-SandboxName] <String> [[-Alias] <String>] [[-DefinitionFile] <String>] [[-LicenseType] <String>] [[-WaitMinutes] <Int32>] [-NoPrompt] [-NoTrackSource] [-Async] [[-PollIntervalSeconds] <Int32>] [-SetDefault] [[-SourceId] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf org create sandbox. A sandbox uses a license of your production org. The CLI waits only when you give -WaitMinutes; otherwise finish with Resume-SalesforceSandbox.

#### Parameters

- `-SandboxName` (String, required): Name of the sandbox org. Passed to sf as --name. Required.
- `-Alias` (String): Alias for the sandbox org. Passed to sf as --alias.
- `-DefinitionFile` (String): Path to a sandbox definition file. Passed to sf as --definition-file.
- `-LicenseType` (String): Type of sandbox license. Passed to sf as --license-type. Default: Developer. Valid values: Developer, Developer_Pro, Partial, Full.
- `-WaitMinutes` (Int32): Number of minutes to wait for the sandbox org to be ready. Passed to sf as --wait.
- `-NoPrompt` (switch): Don't prompt for confirmation about the sandbox configuration. Adds --no-prompt.
- `-NoTrackSource` (switch): Do not use source tracking for this sandbox. Adds --no-track-source.
- `-Async` (switch): Request the sandbox and return at once, without waiting for it to be ready. Finish with Resume-SalesforceSandbox. Adds --async.
- `-PollIntervalSeconds` (Int32): Number of seconds to wait between checks while waiting for the sandbox. Passed to sf as --poll-interval.
- `-SetDefault` (switch): Set the sandbox as your default org once it is ready. Adds --set-default.
- `-SourceId` (String): ID of the sandbox to clone, as an alternative to -SourceSandboxName of Copy-SalesforceSandbox. Passed to sf as --source-id.
- `-TargetOrg` (String): Username or alias of the production org that contains the sandbox license. Passed to sf as --target-org.

#### Salesforce CLI

- `sf org create sandbox`

#### Examples

```powershell
PS> New-SalesforceSandbox -SandboxName dev2 -LicenseType Developer -TargetOrg prod
```

Create a developer sandbox.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceSandbox -Examples"
- For more information, type: "Get-Help New-SalesforceSandbox -Detailed"
- For technical information, type: "Get-Help New-SalesforceSandbox -Full"
- For online help, type: "Get-Help New-SalesforceSandbox -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceSandbox

#### Synopsis

Deletes a sandbox.

#### Syntax

```powershell
Remove-SalesforceSandbox [-NoPrompt] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf org delete sandbox. This cannot be undone. Asks for confirmation and supports -WhatIf; -NoPrompt also turns off the CLI's own question.

#### Parameters

- `-NoPrompt` (switch): Don't prompt the user to confirm the deletion. Adds --no-prompt.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org delete sandbox`

#### Examples

```powershell
PS> Remove-SalesforceSandbox -TargetOrg dev2 -WhatIf
```

Preview the delete.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceSandbox -Examples"
- For more information, type: "Get-Help Remove-SalesforceSandbox -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceSandbox -Full"
- For online help, type: "Get-Help Remove-SalesforceSandbox -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Resume-SalesforceSandbox

#### Synopsis

Checks a sandbox creation and logs in to it when it is ready.

#### Syntax

```powershell
Resume-SalesforceSandbox -SandboxName <String> [-WaitMinutes <Int32>] [-TargetOrg <String>] [<CommonParameters>]
Resume-SalesforceSandbox -JobId <String> [-WaitMinutes <Int32>] [-TargetOrg <String>] [<CommonParameters>]
Resume-SalesforceSandbox -UseMostRecent [-WaitMinutes <Int32>] [-TargetOrg <String>] [<CommonParameters>]
```

#### Description

Runs sf org resume sandbox. Use it after New-SalesforceSandbox, Copy-SalesforceSandbox or Update-SalesforceSandbox returned without waiting. Say which sandbox with -SandboxName, with the -JobId of the sandbox process, or with -UseMostRecent for the latest one.

#### Parameters

- `-SandboxName` (String, required): Name of the sandbox org. Passed to sf as --name. Required unless you give -JobId or -UseMostRecent.
- `-JobId` (String, required): ID of the sandbox creation or refresh process (the SandboxProcess ID, starting 0GR). Passed to sf as --job-id. Use it instead of -SandboxName.
- `-UseMostRecent` (switch, required): Resume the most recent sandbox creation or refresh. Adds --use-most-recent. Use it instead of -SandboxName.
- `-WaitMinutes` (Int32): Number of minutes to wait for the sandbox org to be ready. Passed to sf as --wait.
- `-TargetOrg` (String): Username or alias of the production org that contains the sandbox license. Passed to sf as --target-org.

#### Salesforce CLI

- `sf org resume sandbox`

#### Examples

```powershell
PS> Resume-SalesforceSandbox -SandboxName dev2 -WaitMinutes 30 -TargetOrg prod
```

Wait up to 30 minutes.

#### Remarks

- To see the examples, type: "Get-Help Resume-SalesforceSandbox -Examples"
- For more information, type: "Get-Help Resume-SalesforceSandbox -Detailed"
- For technical information, type: "Get-Help Resume-SalesforceSandbox -Full"
- For online help, type: "Get-Help Resume-SalesforceSandbox -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Update-SalesforceSandbox

#### Synopsis

Refreshes a sandbox from production or from another sandbox.

#### Syntax

```powershell
Update-SalesforceSandbox [[-SandboxName] <String>] [[-DefinitionFile] <String>] [[-SourceSandboxName] <String>] [[-SourceId] <String>] [-NoAutoActivate] [-Async] [[-WaitMinutes] <Int32>] [[-PollIntervalSeconds] <Int32>] [-NoPrompt] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf org refresh sandbox. A refresh replaces the sandbox's data and metadata with a fresh copy, so everything in it that is not in the source is lost. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time. The CLI waits only when you give -WaitMinutes; otherwise finish with Resume-SalesforceSandbox. Give the sandbox with -SandboxName, or put its name in a -DefinitionFile.

#### Parameters

- `-SandboxName` (String): Name of the sandbox to refresh. Passed to sf as --name.
- `-DefinitionFile` (String): Path to a sandbox definition file that holds the refresh settings, such as the license type. Passed to sf as --definition-file.
- `-SourceSandboxName` (String): Name of the sandbox to refresh from, instead of production. Passed to sf as --source-sandbox-name.
- `-SourceId` (String): ID of the sandbox to refresh from, instead of its name. Passed to sf as --source-id.
- `-NoAutoActivate` (switch): Do not activate the sandbox when the refresh finishes; you activate it yourself later. Adds --no-auto-activate.
- `-Async` (switch): Start the refresh and return at once, without waiting for it to finish. Finish with Resume-SalesforceSandbox. Adds --async.
- `-WaitMinutes` (Int32): Number of minutes to wait for the refresh to finish. Passed to sf as --wait.
- `-PollIntervalSeconds` (Int32): Number of seconds to wait between checks while waiting for the refresh. Passed to sf as --poll-interval.
- `-NoPrompt` (switch): Don't ask for confirmation. Skips the PowerShell confirmation; psfdx always passes --no-prompt to the CLI after it has confirmed.
- `-TargetOrg` (String): Username or alias of the production org that owns the sandbox. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org refresh sandbox`

#### Examples

```powershell
PS> Update-SalesforceSandbox -SandboxName dev1 -TargetOrg prod -WhatIf
```

Preview the refresh without starting it.

#### Remarks

- To see the examples, type: "Get-Help Update-SalesforceSandbox -Examples"
- For more information, type: "Get-Help Update-SalesforceSandbox -Detailed"
- For technical information, type: "Get-Help Update-SalesforceSandbox -Full"
- For online help, type: "Get-Help Update-SalesforceSandbox -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Scratch Orgs

### Get-SalesforceScratchOrgs

#### Synopsis

Lists the scratch orgs this computer knows about.

#### Syntax

```powershell
Get-SalesforceScratchOrgs [-SkipConnectionStatus] [-Last] [<CommonParameters>]
```

#### Description

Runs sf org list --all and returns the scratch orgs (orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias). With -Last only the most recently used one is returned.

#### Parameters

- `-SkipConnectionStatus` (switch): Skip retrieving the connection status of non-scratch orgs. Adds --skip-connection-status.
- `-Last` (switch): Return only the scratch org with the latest lastUsed date. The sorting happens in PowerShell.

#### Salesforce CLI

- `sf org list`

#### Examples

```powershell
PS> Get-SalesforceScratchOrgs | Where-Object connectedStatus -eq 'Connected'
```

Scratch orgs that are reachable.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceScratchOrgs -Examples"
- For more information, type: "Get-Help Get-SalesforceScratchOrgs -Detailed"
- For technical information, type: "Get-Help Get-SalesforceScratchOrgs -Full"
- For online help, type: "Get-Help Get-SalesforceScratchOrgs -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceScratchOrg

#### Synopsis

Creates a scratch org.

#### Syntax

```powershell
New-SalesforceScratchOrg [[-TargetDevHub] <String>] [-SetDefault] [[-DurationDays] <Int32>] [[-DefinitionFile] <String>] [[-WaitMinutes] <Int32>] [-Async] [[-Edition] <String>] [[-Snapshot] <String>] [[-AdminEmail] <String>] [[-Description] <String>] [[-Name] <String>] [[-Release] <String>] [[-SourceOrgId] <String>] [[-AdminUsername] <String>] [[-Alias] <String>] [[-OAuthClientId] <String>] [-NoAncestors] [-NoNamespace] [-NoTrackSource] [<CommonParameters>]
```

#### Description

Runs sf org create scratch from a scratch org definition file. Use -Async to return before the org is ready, then finish with Resume-SalesforceScratchOrg. Scratch orgs use your Dev Hub's allocation and expire after the duration.

#### Parameters

- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Passed to sf as --target-dev-hub.
- `-SetDefault` (switch): Set the scratch org as your default org. Adds --set-default.
- `-DurationDays` (Int32): Number of days before the org expires. Passed to sf as --duration-days.
- `-DefinitionFile` (String): Path to a scratch org definition file. Passed to sf as --definition-file. Default: config/project-scratch-def.json.
- `-WaitMinutes` (Int32): Number of minutes to wait for the scratch org to be ready. Passed to sf as --wait.
- `-Async` (switch): Request the org, but don't wait for it to complete. Adds --async.
- `-Edition` (String): Salesforce edition of the scratch org. Overrides the value of the "edition" option in the definition file, if set. Passed to sf as --edition. Valid values: developer, enterprise, group, professional, partner-developer, partner-enterprise, partner-group, partner-professional.
- `-Snapshot` (String): Name of the snapshot to use when creating this scratch org. Overrides the value of the "snapshot" option in the defintion file, if set. Passed to sf as --snapshot.
- `-AdminEmail` (String): Email address that will be applied to the org's admin user. Overrides the value of the "adminEmail" option in the definition file, if set. Passed to sf as --admin-email.
- `-Description` (String): Description of the scratch org in the Dev Hub. Overrides the value of the "description" option in the definition file, if set. Passed to sf as --description.
- `-Name` (String): Name of the org, such as "Acme Company". Overrides the value of the "orgName" option in the definition file, if set. Passed to sf as --name.
- `-Release` (String): Release of the scratch org as compared to the Dev Hub release. Passed to sf as --release. Valid values: preview, previous.
- `-SourceOrgId` (String): 15-character ID of the org shape that the new scratch org is based on. Overrides the value of the "sourceOrg" option in the definition file, if set. Passed to sf as --source-org.
- `-AdminUsername` (String): Username of the scratch org admin user. Overrides the value of the "username" option in the definition file, if set. Passed to sf as --username.
- `-Alias` (String): Alias for the scratch org. Passed to sf as --alias.
- `-OAuthClientId` (String): OAuth client ID (also called consumer key) of your connected app, used to log in to the new scratch org. Passed to sf as --client-id.
- `-NoAncestors` (switch): Don't include second-generation managed package (2GP) ancestors in the scratch org. Adds --no-ancestors.
- `-NoNamespace` (switch): Create the scratch org without the namespace of the Dev Hub or the project, even if the project has one. Adds --no-namespace.
- `-NoTrackSource` (switch): Create the scratch org without source tracking. Scratch orgs have source tracking on by default. Adds --no-track-source.

#### Salesforce CLI

- `sf org create scratch`

#### Examples

```powershell
PS> New-SalesforceScratchOrg -DefinitionFile config/project-scratch-def.json -Name ci-1 -DurationDays 3 -SetDefault
```

Create a three-day scratch org and make it the default.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceScratchOrg -Examples"
- For more information, type: "Get-Help New-SalesforceScratchOrg -Detailed"
- For technical information, type: "Get-Help New-SalesforceScratchOrg -Full"
- For online help, type: "Get-Help New-SalesforceScratchOrg -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceScratchOrg

#### Synopsis

Deletes a scratch org.

#### Syntax

```powershell
Remove-SalesforceScratchOrg [-TargetOrg] <String> [-NoPrompt] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf org delete scratch. This cannot be undone. Asks for confirmation and supports -WhatIf; -NoPrompt also turns off the CLI's own question.

#### Parameters

- `-TargetOrg` (String, required): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org. Required.
- `-NoPrompt` (switch): Don't prompt the user to confirm the deletion. Adds --no-prompt.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org delete scratch`

#### Examples

```powershell
PS> Remove-SalesforceScratchOrg -TargetOrg ci-1 -WhatIf
```

Show which org would be deleted.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceScratchOrg -Examples"
- For more information, type: "Get-Help Remove-SalesforceScratchOrg -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceScratchOrg -Full"
- For online help, type: "Get-Help Remove-SalesforceScratchOrg -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceScratchOrgs

#### Synopsis

Deletes every scratch org this computer knows about.

#### Syntax

```powershell
Remove-SalesforceScratchOrgs [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Lists scratch orgs with Get-SalesforceScratchOrgs and deletes each one with Remove-SalesforceScratchOrg -NoPrompt. One confirmation names all of them. This cannot be undone. Supports -WhatIf.

#### Parameters

- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Remove-SalesforceScratchOrgs -WhatIf
```

List the orgs that would be deleted.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceScratchOrgs -Examples"
- For more information, type: "Get-Help Remove-SalesforceScratchOrgs -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceScratchOrgs -Full"
- For online help, type: "Get-Help Remove-SalesforceScratchOrgs -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Resume-SalesforceScratchOrg

#### Synopsis

Resumes a scratch org creation that was started with New-SalesforceScratchOrg -Async or that timed out (sf org resume scratch).

#### Syntax

```powershell
Resume-SalesforceScratchOrg [[-JobId] <String>] [-UseMostRecent] [[-WaitMinutes] <Int32>] [<CommonParameters>]
```

#### Description

Select the creation by -JobId (the scratch org info ID, starting 2SR, reported when the creation was started) or by -UseMostRecent. The CLI keeps a local record of the job, so there is no -TargetOrg; resume from the machine that started it. Returns the CLI result (org ID, username, instance URL) with Completed: true once the org is ready. A creation that is still running when -WaitMinutes ends (the CLI's StillInProgressError) returns Completed: false with Status InProgress, so a script can poll; a failed creation throws the CLI message. Permission sets are assigned afterwards with Grant-SalesforcePermissionSet (psfdx), which asks for confirmation.

#### Parameters

- `-JobId` (String): Job ID of the incomplete scratch org create that you want to resume. Passed to sf as --job-id.
- `-UseMostRecent` (switch): Resume the creation the CLI started most recently. Passed as --use-most-recent. Use instead of -JobId.
- `-WaitMinutes` (Int32): Number of minutes to wait for the scratch org to be ready. Passed to sf as --wait. Range: 1 to 1440.

#### Salesforce CLI

- `sf org resume scratch`

#### Examples

```powershell
PS> New-SalesforceScratchOrg -Async -Name ci-1 | Out-Null
PS> Resume-SalesforceScratchOrg -UseMostRecent -WaitMinutes 10
PS> Grant-SalesforcePermissionSet -Name MyPermSet -TargetOrg ci-1
```

#### Remarks

- To see the examples, type: "Get-Help Resume-SalesforceScratchOrg -Examples"
- For more information, type: "Get-Help Resume-SalesforceScratchOrg -Detailed"
- For technical information, type: "Get-Help Resume-SalesforceScratchOrg -Full"
- For online help, type: "Get-Help Resume-SalesforceScratchOrg -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>
