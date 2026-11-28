# psfdx-development command reference

Generated from the commands' own help by `site/Update-ModuleReference.ps1`: do not edit it by hand. The same reference is on the website: <https://psfdx.com/modules/psfdx-development/>. It is part of the `psfdx` package; see the [installation guide](https://github.com/tonygward/psfdx/blob/main/docs/install.md).

58 commands. Every command also takes the common parameters, such as `-Verbose`.

## Commands

**Jest tests**: [Debug-SalesforceJest](#debug-salesforcejest), [Install-SalesforceJest](#install-salesforcejest), [New-SalesforceJestTest](#new-salesforcejesttest), [Test-SalesforceJest](#test-salesforcejest), [Watch-SalesforceJest](#watch-salesforcejest)

**Project configuration**: [Disable-SalesforceSourceTracking](#disable-salesforcesourcetracking), [Enable-SalesforceSourceTracking](#enable-salesforcesourcetracking), [Get-SalesforceConfig](#get-salesforceconfig), [Get-SalesforceTargetDevHub](#get-salesforcetargetdevhub), [Get-SalesforceTargetOrg](#get-salesforcetargetorg), [New-SalesforceProject](#new-salesforceproject), [Remove-SalesforceTargetDevHub](#remove-salesforcetargetdevhub), [Remove-SalesforceTargetOrg](#remove-salesforcetargetorg), [Set-SalesforceTargetDevHub](#set-salesforcetargetdevhub), [Set-SalesforceTargetOrg](#set-salesforcetargetorg)

**Apex**: [Get-SalesforceApexClass](#get-salesforceapexclass), [Get-SalesforceApexCompileStatus](#get-salesforceapexcompilestatus), [Get-SalesforceApexTestResult](#get-salesforceapextestresult), [Get-SalesforceCodeCoverage](#get-salesforcecodecoverage), [Invoke-SalesforceApex](#invoke-salesforceapex), [New-SalesforceApexClass](#new-salesforceapexclass), [New-SalesforceApexTrigger](#new-salesforceapextrigger), [Start-SalesforceApexTest](#start-salesforceapextest), [Test-SalesforceApex](#test-salesforceapex), [Wait-SalesforceApexTest](#wait-salesforceapextest), [Watch-SalesforceApex](#watch-salesforceapex)

**Code Analyzer**: [Get-SalesforceCodeAnalyzerAst](#get-salesforcecodeanalyzerast), [Get-SalesforceCodeAnalyzerConfig](#get-salesforcecodeanalyzerconfig), [Get-SalesforceCodeAnalyzerRule](#get-salesforcecodeanalyzerrule), [Invoke-SalesforceCodeAnalyzer](#invoke-salesforcecodeanalyzer)

**Flow and logic tests**: [Get-SalesforceFlowTestResult](#get-salesforceflowtestresult), [Get-SalesforceLogicTestResult](#get-salesforcelogictestresult), [Test-SalesforceFlow](#test-salesforceflow), [Test-SalesforceLogic](#test-salesforcelogic)

**Org shapes and snapshots**: [Get-SalesforceOrgShapes](#get-salesforceorgshapes), [Get-SalesforceOrgSnapshot](#get-salesforceorgsnapshot), [Get-SalesforceOrgSnapshots](#get-salesforceorgsnapshots), [New-SalesforceOrgShape](#new-salesforceorgshape), [New-SalesforceOrgSnapshot](#new-salesforceorgsnapshot), [Remove-SalesforceOrgShape](#remove-salesforceorgshape), [Remove-SalesforceOrgSnapshot](#remove-salesforceorgsnapshot)

**Local development servers**: [Install-SalesforceLwcDevServer](#install-salesforcelwcdevserver), [Start-SalesforceLwcDevServer](#start-salesforcelwcdevserver), [Start-SalesforceUiBundleDevServer](#start-salesforceuibundledevserver)

**Component and template generation**: [New-SalesforceAnalyticsTemplate](#new-salesforceanalyticstemplate), [New-SalesforceExperienceSite](#new-salesforceexperiencesite), [New-SalesforceFlexiPage](#new-salesforceflexipage), [New-SalesforceLightningApp](#new-salesforcelightningapp), [New-SalesforceLightningComponent](#new-salesforcelightningcomponent), [New-SalesforceLightningEvent](#new-salesforcelightningevent), [New-SalesforceLightningInterface](#new-salesforcelightninginterface), [New-SalesforceLightningOutApp](#new-salesforcelightningoutapp), [New-SalesforceLightningTest](#new-salesforcelightningtest), [New-SalesforceStaticResource](#new-salesforcestaticresource), [New-SalesforceUiBundle](#new-salesforceuibundle), [New-SalesforceUiEmbedding](#new-salesforceuiembedding), [New-SalesforceVisualforceComponent](#new-salesforcevisualforcecomponent), [New-SalesforceVisualforcePage](#new-salesforcevisualforcepage)

## Jest tests

### Debug-SalesforceJest

#### Synopsis

Runs the LWC Jest tests of the current project in debug mode.

#### Syntax

```powershell
Debug-SalesforceJest [<CommonParameters>]
```

#### Description

Runs npm run test:unit:debug in the current folder, so the project's package.json must define that script (the sfdx project template does). Output is returned as text.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Debug-SalesforceJest
```

Start the Jest tests with the Node debugger.

#### Remarks

- To see the examples, type: "Get-Help Debug-SalesforceJest -Examples"
- For more information, type: "Get-Help Debug-SalesforceJest -Detailed"
- For technical information, type: "Get-Help Debug-SalesforceJest -Full"
- For online help, type: "Get-Help Debug-SalesforceJest -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Install-SalesforceJest

#### Synopsis

Installs the LWC Jest test runner into the current project.

#### Syntax

```powershell
Install-SalesforceJest [<CommonParameters>]
```

#### Description

Runs yarn add -D @salesforce/sfdx-lwc-jest when yarn is on the PATH, otherwise npm install -D @salesforce/sfdx-lwc-jest. This downloads and runs code from the package registry. Node.js is required.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Install-SalesforceJest
```

Add the Jest runner as a dev dependency.

#### Remarks

- To see the examples, type: "Get-Help Install-SalesforceJest -Examples"
- For more information, type: "Get-Help Install-SalesforceJest -Detailed"
- For technical information, type: "Get-Help Install-SalesforceJest -Full"
- For online help, type: "Get-Help Install-SalesforceJest -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceJestTest

#### Synopsis

Writes a starter Jest test for a Lightning web component.

#### Syntax

```powershell
New-SalesforceJestTest [-LwcName] <String> [[-ProjectPath] <String>] [-Force] [<CommonParameters>]
```

#### Description

Does not use the Salesforce CLI (the old sf force lightning lwc test create command was removed). It writes &lt;name&gt;.test.js into the component's __tests__ folder, with a test that renders the component. It refuses to overwrite an existing test unless you pass -Force.

#### Parameters

- `-LwcName` (String, required): Name of the Lightning web component (letters, digits and underscores, starting with a letter). Its folder must exist under force-app/main/default/lwc. Required.
- `-ProjectPath` (String): Root folder of the Salesforce DX project. It must exist. Default: ..
- `-Force` (switch): Overwrite the test file if it already exists.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> New-SalesforceJestTest -LwcName accountCard -ProjectPath .
```

Create force-app/main/default/lwc/accountCard/__tests__/accountCard.test.js.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceJestTest -Examples"
- For more information, type: "Get-Help New-SalesforceJestTest -Detailed"
- For technical information, type: "Get-Help New-SalesforceJestTest -Full"
- For online help, type: "Get-Help New-SalesforceJestTest -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Test-SalesforceJest

#### Synopsis

Runs the LWC Jest tests of the current project once.

#### Syntax

```powershell
Test-SalesforceJest [<CommonParameters>]
```

#### Description

Runs npm run test:unit in the current folder, so the project's package.json must define that script.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Test-SalesforceJest
```

Run every Jest test.

#### Remarks

- To see the examples, type: "Get-Help Test-SalesforceJest -Examples"
- For more information, type: "Get-Help Test-SalesforceJest -Detailed"
- For technical information, type: "Get-Help Test-SalesforceJest -Full"
- For online help, type: "Get-Help Test-SalesforceJest -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Watch-SalesforceJest

#### Synopsis

Runs the LWC Jest tests and re-runs them when files change.

#### Syntax

```powershell
Watch-SalesforceJest [<CommonParameters>]
```

#### Description

Runs npm run test:unit:watch in the current folder, so the project's package.json must define that script. It keeps running until you stop it.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Watch-SalesforceJest
```

Watch mode for Jest.

#### Remarks

- To see the examples, type: "Get-Help Watch-SalesforceJest -Examples"
- For more information, type: "Get-Help Watch-SalesforceJest -Detailed"
- For technical information, type: "Get-Help Watch-SalesforceJest -Full"
- For online help, type: "Get-Help Watch-SalesforceJest -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Project configuration

### Disable-SalesforceSourceTracking

#### Synopsis

Turns source tracking off for an org.

#### Syntax

```powershell
Disable-SalesforceSourceTracking [-NoPrompt] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf org disable tracking. After it, deploy and retrieve no longer report what changed between your project and the org, and source tracking may not be possible to turn on again for that org. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question.

#### Parameters

- `-NoPrompt` (switch): Don't ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org disable tracking`

#### Examples

```powershell
PS> Disable-SalesforceSourceTracking -TargetOrg dev1 -WhatIf
```

Preview the change without making it.

#### Remarks

- To see the examples, type: "Get-Help Disable-SalesforceSourceTracking -Examples"
- For more information, type: "Get-Help Disable-SalesforceSourceTracking -Detailed"
- For technical information, type: "Get-Help Disable-SalesforceSourceTracking -Full"
- For online help, type: "Get-Help Disable-SalesforceSourceTracking -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Enable-SalesforceSourceTracking

#### Synopsis

Turns source tracking on for an org that allows it.

#### Syntax

```powershell
Enable-SalesforceSourceTracking [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf org enable tracking. Source tracking lets deploy and retrieve report what changed between your project and the org. It can be enabled only in an org that supports it, such as a sandbox that was created with source tracking turned off. Supports -WhatIf.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org enable tracking`

#### Examples

```powershell
PS> Enable-SalesforceSourceTracking -TargetOrg dev1
```

Turn source tracking on for dev1.

#### Remarks

- To see the examples, type: "Get-Help Enable-SalesforceSourceTracking -Examples"
- For more information, type: "Get-Help Enable-SalesforceSourceTracking -Detailed"
- For technical information, type: "Get-Help Enable-SalesforceSourceTracking -Full"
- For online help, type: "Get-Help Enable-SalesforceSourceTracking -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceConfig

#### Synopsis

Lists the Salesforce CLI configuration variables that are set.

#### Syntax

```powershell
Get-SalesforceConfig [<CommonParameters>]
```

#### Description

Runs sf config list and returns one object per variable (name, value, location: Local or Global).

#### Salesforce CLI

- `sf config list`

#### Examples

```powershell
PS> Get-SalesforceConfig
```

Every variable that is set.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceConfig -Examples"
- For more information, type: "Get-Help Get-SalesforceConfig -Detailed"
- For technical information, type: "Get-Help Get-SalesforceConfig -Full"
- For online help, type: "Get-Help Get-SalesforceConfig -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-settings>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceTargetDevHub

#### Synopsis

Shows the default Dev Hub configured for the CLI.

#### Syntax

```powershell
Get-SalesforceTargetDevHub [-Global] [<CommonParameters>]
```

#### Description

Runs sf config get target-dev-hub and returns the value with where it is set (Local or Global). With -Global only the global setting is returned.

#### Parameters

- `-Global` (switch): Return only the global value (set for the whole computer), not a project-local one. The filter runs in PowerShell.

#### Salesforce CLI

- `sf config get`

#### Examples

```powershell
PS> Get-SalesforceTargetDevHub
```

The Dev Hub that new scratch orgs are created from.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceTargetDevHub -Examples"
- For more information, type: "Get-Help Get-SalesforceTargetDevHub -Detailed"
- For technical information, type: "Get-Help Get-SalesforceTargetDevHub -Full"
- For online help, type: "Get-Help Get-SalesforceTargetDevHub -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-settings>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceTargetOrg

#### Synopsis

Shows the default target org configured for the CLI.

#### Syntax

```powershell
Get-SalesforceTargetOrg [-Global] [<CommonParameters>]
```

#### Description

Runs sf config get target-org and returns the value with where it is set (Local or Global). With -Global only the global setting is returned.

#### Parameters

- `-Global` (switch): Return only the global value (set for the whole computer), not a project-local one. The filter runs in PowerShell.

#### Salesforce CLI

- `sf config get`

#### Examples

```powershell
PS> Get-SalesforceTargetOrg
```

The org that cmdlets use when you give no -TargetOrg.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceTargetOrg -Examples"
- For more information, type: "Get-Help Get-SalesforceTargetOrg -Detailed"
- For technical information, type: "Get-Help Get-SalesforceTargetOrg -Full"
- For online help, type: "Get-Help Get-SalesforceTargetOrg -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-settings>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceProject

#### Synopsis

Generates a new Salesforce DX project.

#### Syntax

```powershell
New-SalesforceProject [-Name] <String> [[-Template] <String>] [[-DefaultUserName] <String>] [[-OutputDirectory] <String>] [[-DefaultPackageDirectory] <String>] [[-Namespace] <String>] [-GenerateManifest] [[-LwcLanguage] <String>] [<CommonParameters>]
```

#### Description

Runs sf template generate project and creates the project folder with sfdx-project.json and the standard layout.

#### Parameters

- `-Name` (String, required): Name of the generated project. Passed to sf as --name. Required.
- `-Template` (String): Template to use for project creation. Passed to sf as --template. Default: standard. Valid values: standard, empty, analytics, reactinternalapp, reactexternalapp, angularinternalapp, angularexternalapp, vueinternalapp, agent.
- `-DefaultUserName` (String): A user name or alias to set as the default target org (target-org) after the project is created. psfdx does this with Set-SalesforceTargetOrg; it is not a flag of the CLI command.
- `-OutputDirectory` (String): Directory for saving the created files. Passed to sf as --output-dir.
- `-DefaultPackageDirectory` (String): Default package directory name. Passed to sf as --default-package-dir.
- `-Namespace` (String): Namespace associated with this project and any connected scratch orgs. Passed to sf as --namespace.
- `-GenerateManifest` (switch): Generate a manifest (package.xml) for change-set based development. Adds --manifest.
- `-LwcLanguage` (String): Language of the Lightning web components the project is set up for. Passed to sf as --lwc-language. Valid values: javascript, typescript. The CLI default is javascript.

#### Salesforce CLI

- `sf template generate project`

#### Examples

```powershell
PS> New-SalesforceProject -Name my-project -Template standard
PS> A standard project in a new folder.
```

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceProject -Examples"
- For more information, type: "Get-Help New-SalesforceProject -Detailed"
- For technical information, type: "Get-Help New-SalesforceProject -Full"
- For online help, type: "Get-Help New-SalesforceProject -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceTargetDevHub

#### Synopsis

Clears the default Dev Hub setting.

#### Syntax

```powershell
Remove-SalesforceTargetDevHub [-Global] [<CommonParameters>]
```

#### Description

Runs sf config unset target-dev-hub, locally or with -Global for the whole computer. Only configuration changes; no org is touched. Returns the CLI's list of successes.

#### Parameters

- `-Global` (switch): Clear the global setting instead of the one for the current project. Adds --global.

#### Salesforce CLI

- `sf config unset`

#### Examples

```powershell
PS> Remove-SalesforceTargetDevHub -Global
```

Forget the global default Dev Hub.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceTargetDevHub -Examples"
- For more information, type: "Get-Help Remove-SalesforceTargetDevHub -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceTargetDevHub -Full"
- For online help, type: "Get-Help Remove-SalesforceTargetDevHub -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-settings>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceTargetOrg

#### Synopsis

Clears the default target org setting.

#### Syntax

```powershell
Remove-SalesforceTargetOrg [-Global] [<CommonParameters>]
```

#### Description

Runs sf config unset target-org, locally or with -Global for the whole computer. Only configuration changes; no org is touched. Returns the CLI's list of successes.

#### Parameters

- `-Global` (switch): Clear the global setting instead of the one for the current project. Adds --global.

#### Salesforce CLI

- `sf config unset`

#### Examples

```powershell
PS> Remove-SalesforceTargetOrg
```

Forget the project's default target org.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceTargetOrg -Examples"
- For more information, type: "Get-Help Remove-SalesforceTargetOrg -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceTargetOrg -Full"
- For online help, type: "Get-Help Remove-SalesforceTargetOrg -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-settings>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Set-SalesforceTargetDevHub

#### Synopsis

Sets the default Dev Hub.

#### Syntax

```powershell
Set-SalesforceTargetDevHub [-Value] <String> [-Global] [<CommonParameters>]
```

#### Description

Runs sf config set target-dev-hub=&lt;value&gt;, for the current project or with -Global for the whole computer. Returns the CLI's list of successes.

#### Parameters

- `-Value` (String, required): Username or alias of the Dev Hub org. Required.
- `-Global` (switch): Set it for the whole computer instead of the current project. Adds --global.

#### Salesforce CLI

- `sf config set`

#### Examples

```powershell
PS> Set-SalesforceTargetDevHub -Value devhub -Global
```

Use the org with alias devhub as the Dev Hub everywhere.

#### Remarks

- To see the examples, type: "Get-Help Set-SalesforceTargetDevHub -Examples"
- For more information, type: "Get-Help Set-SalesforceTargetDevHub -Detailed"
- For technical information, type: "Get-Help Set-SalesforceTargetDevHub -Full"
- For online help, type: "Get-Help Set-SalesforceTargetDevHub -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-settings>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Set-SalesforceTargetOrg

#### Synopsis

Sets the default target org.

#### Syntax

```powershell
Set-SalesforceTargetOrg [-Value] <String> [-Global] [<CommonParameters>]
```

#### Description

Runs sf config set target-org=&lt;value&gt;, for the current project or with -Global for the whole computer. Cmdlets that take -TargetOrg then use this org when you do not give one. Returns the CLI's list of successes.

#### Parameters

- `-Value` (String, required): Username or alias of the org to use by default. Required.
- `-Global` (switch): Set it for the whole computer instead of the current project. Adds --global.

#### Salesforce CLI

- `sf config set`

#### Examples

```powershell
PS> Set-SalesforceTargetOrg -Value dev1
```

Make dev1 the default for this project.

#### Remarks

- To see the examples, type: "Get-Help Set-SalesforceTargetOrg -Examples"
- For more information, type: "Get-Help Set-SalesforceTargetOrg -Detailed"
- For technical information, type: "Get-Help Set-SalesforceTargetOrg -Full"
- For online help, type: "Get-Help Set-SalesforceTargetOrg -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-settings>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Apex

### Get-SalesforceApexClass

#### Synopsis

Gets an Apex class, including its source, from an org.

#### Syntax

```powershell
Get-SalesforceApexClass [-Name] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Queries ApexClass (Id, Name, Body) through the Tooling API with Select-SalesforceRecords. The name is matched exactly and escaped as a SOQL literal; at most one class is returned.

#### Parameters

- `-Name` (String, required): Exact name of the Apex class. Required.
- `-TargetOrg` (String): Username or alias of the org to query. If omitted, the Salesforce CLI uses the default target org.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> (Get-SalesforceApexClass -Name MyService -TargetOrg dev1).Body
```

The source code of MyService.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceApexClass -Examples"
- For more information, type: "Get-Help Get-SalesforceApexClass -Detailed"
- For technical information, type: "Get-Help Get-SalesforceApexClass -Full"
- For online help, type: "Get-Help Get-SalesforceApexClass -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceApexCompileStatus

#### Synopsis

Lists the Apex classes and triggers in an org that do not compile cleanly.

#### Syntax

```powershell
Get-SalesforceApexCompileStatus [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf apex get compile-status. It returns the compile results of only the Apex classes and triggers that are invalid or have warnings, instead of compiling the whole org, so it is a quick check after a deploy or an upgrade. It only reads. No result means that everything compiles.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf apex get compile-status`

#### Examples

```powershell
PS> Get-SalesforceApexCompileStatus -TargetOrg dev1
```

The classes and triggers in dev1 with compile errors or warnings.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceApexCompileStatus -Examples"
- For more information, type: "Get-Help Get-SalesforceApexCompileStatus -Detailed"
- For technical information, type: "Get-Help Get-SalesforceApexCompileStatus -Full"
- For online help, type: "Get-Help Get-SalesforceApexCompileStatus -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-apex>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceApexTestResult

#### Synopsis

Gets the results of an Apex test run by its TestRunId (sf apex get test).

#### Syntax

```powershell
Get-SalesforceApexTestResult [-TestRunId] <String> [-CodeCoverage] [-CodeCoverageDetailed] [-Concise] [[-OutputDirectory] <String>] [[-ResultFormat] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Returns one object: TestRunId, Summary (outcome, counts, times), Tests (one per test method with Outcome, RunTime, Message and StackTrace), Coverage (only with -CodeCoverage, and only if the run was started with coverage) and Completed. A run that is still queued or processing returns Completed = $false at once (the status is checked with a query first, because the CLI itself would wait) and does not throw; use Wait-SalesforceApexTest to wait. A finished run with failing tests writes the object and then throws PsfdxTestsFailed (TargetObject is the summary). Coverage is returned, never judged: there is no threshold here.

#### Parameters

- `-TestRunId` (String, required): ID of the test run. Passed to sf as --test-run-id. Required.
- `-CodeCoverage` (switch): Retrieve code coverage results. Adds --code-coverage.
- `-CodeCoverageDetailed` (switch): Display detailed code coverage per test. Adds --detailed-coverage.
- `-Concise` (switch): Display only failed test results; works with human-readable output only. Adds --concise.
- `-OutputDirectory` (String): Directory in which to store test result files. Passed to sf as --output-dir.
- `-ResultFormat` (String): Format of the results. Passed to sf as --result-format. Default: json, which returns the object described above. With human, tap or junit the CLI's text is returned as it is, and a run that is still queued or processing returns nothing but a warning. Valid values: human, tap, junit, json.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf apex get test`

#### Examples

```powershell
PS> $r = Get-SalesforceApexTestResult -TestRunId 707xx0000000001 -CodeCoverage -TargetOrg myorg; $r.Tests | Where-Object Outcome -ne 'Pass'
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceApexTestResult -Examples"
- For more information, type: "Get-Help Get-SalesforceApexTestResult -Detailed"
- For technical information, type: "Get-Help Get-SalesforceApexTestResult -Full"
- For online help, type: "Get-Help Get-SalesforceApexTestResult -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-apex>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceCodeCoverage

#### Synopsis

Shows per-test Apex code coverage as recorded in an org.

#### Syntax

```powershell
Get-SalesforceCodeCoverage [[-ApexClassOrTrigger] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Queries the Tooling API object ApexCodeCoverage with Select-SalesforceRecords and returns one object per class, trigger and test method with the percentage covered, the covered and uncovered line counts, and CodeCoverageOK (true at 75 percent or more). -ApexClassOrTrigger filters the result in PowerShell after the query.

#### Parameters

- `-ApexClassOrTrigger` (String): Keep only rows where this name is the class or trigger, or the test class. The filter runs in PowerShell, after the query.
- `-TargetOrg` (String): Username or alias of the org to query. If omitted, the Salesforce CLI uses the default target org.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Get-SalesforceCodeCoverage -ApexClassOrTrigger MyService -TargetOrg dev1
```

Coverage rows for MyService.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceCodeCoverage -Examples"
- For more information, type: "Get-Help Get-SalesforceCodeCoverage -Detailed"
- For technical information, type: "Get-Help Get-SalesforceCodeCoverage -Full"
- For online help, type: "Get-Help Get-SalesforceCodeCoverage -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Invoke-SalesforceApex

#### Synopsis

Runs the anonymous Apex in a file against an org.

#### Syntax

```powershell
Invoke-SalesforceApex [-ApexFile] <String> [[-DebugLevel] <String>] [[-CategoryLevel] <String[]>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf apex run --file. The code executes in the org with your user's permissions and can change data, so review it first. Returns the execution result (success, compile and run problems, and the debug log).

#### Parameters

- `-ApexFile` (String, required): Path of the local file that holds the Apex statements to run. Passed to sf as --file. Required.
- `-DebugLevel` (String): Debug level for the debug log that the run creates in the org. Passed to sf as --debug-level. Valid values: NONE, DEBUGONLY, DB, PROFILING, CALLOUT, DETAIL. Use it instead of -CategoryLevel, not with it.
- `-CategoryLevel` (String[]): Log level for one log category of that debug log, written as Category=Level, for example ApexCode=FINEST. Give the parameter several times, or a list, for several categories. Each one is passed to sf as its own --category-level. Use it instead of -DebugLevel, not with it.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf apex run`

#### Examples

```powershell
PS> Invoke-SalesforceApex -ApexFile .\scripts\apex\hello.apex -TargetOrg dev1
```

Run the script.

#### Remarks

- To see the examples, type: "Get-Help Invoke-SalesforceApex -Examples"
- For more information, type: "Get-Help Invoke-SalesforceApex -Detailed"
- For technical information, type: "Get-Help Invoke-SalesforceApex -Full"
- For online help, type: "Get-Help Invoke-SalesforceApex -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-apex>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceApexClass

#### Synopsis

Generates a new Apex class in the project.

#### Syntax

```powershell
New-SalesforceApexClass [-Name] <String> [[-Template] <String>] [[-OutputDirectory] <String>] [<CommonParameters>]
```

#### Description

Runs sf template generate apex class and writes the .cls and .cls-meta.xml files. The output folder must already exist.

#### Parameters

- `-Name` (String, required): Name of the generated Apex class. Passed to sf as --name. Required.
- `-Template` (String): Template to use for file creation. Passed to sf as --template. Default: DefaultApexClass. Valid values: DefaultApexClass, ApexUnitTest, InboundEmailService, ApexException, BasicUnitTest, Batchable, Queueable.
- `-OutputDirectory` (String): Directory for saving the created files. Passed to sf as --output-dir.

#### Salesforce CLI

- `sf template generate apex class`

#### Examples

```powershell
PS> New-SalesforceApexClass -Name AccountService -OutputDirectory force-app/main/default/classes
PS> A default class in the usual folder.
```

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceApexClass -Examples"
- For more information, type: "Get-Help New-SalesforceApexClass -Detailed"
- For technical information, type: "Get-Help New-SalesforceApexClass -Full"
- For online help, type: "Get-Help New-SalesforceApexClass -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceApexTrigger

#### Synopsis

Generates a new Apex trigger in the project.

#### Syntax

```powershell
New-SalesforceApexTrigger [-Name] <String> [[-Event] <String>] [[-SObject] <String>] [[-Template] <String>] [[-OutputDirectory] <String>] [<CommonParameters>]
```

#### Description

Runs sf template generate apex trigger and writes the .trigger and .trigger-meta.xml files. The output folder must already exist.

#### Parameters

- `-Name` (String, required): Name of the generated Apex trigger. Passed to sf as --name. Required.
- `-Event` (String): The trigger event. Default: before insert. Passed to sf as --event. Default: before insert. Valid values: before insert, before update, before delete, after insert, after update, after delete, after undelete.
- `-SObject` (String): Salesforce object to generate a trigger on. Passed to sf as --sobject.
- `-Template` (String): Template to use. Passed to sf as --template. Valid value: ApexTrigger, which is also the CLI default.
- `-OutputDirectory` (String): Directory for saving the created files. Passed to sf as --output-dir.

#### Salesforce CLI

- `sf template generate apex trigger`

#### Examples

```powershell
PS> New-SalesforceApexTrigger -Name AccountTrigger -SObject Account -Event 'before insert'
PS> A before-insert trigger on Account.
```

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceApexTrigger -Examples"
- For more information, type: "Get-Help New-SalesforceApexTrigger -Detailed"
- For technical information, type: "Get-Help New-SalesforceApexTrigger -Full"
- For online help, type: "Get-Help New-SalesforceApexTrigger -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Start-SalesforceApexTest

#### Synopsis

Starts an Apex test run in an org and returns its TestRunId without waiting (sf apex run test).

#### Syntax

```powershell
Start-SalesforceApexTest [[-ClassName] <String[]>] [[-TestName] <String[]>] [[-SuiteName] <String[]>] [[-TestLevel] <String>] [-CodeCoverage] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Name tests with -ClassName (all tests in the classes), -TestName (Class.method) or -SuiteName, one kind at a time, or give none to run the local tests. Salesforce only records code coverage for a run that asked for it, so give -CodeCoverage here if you will want coverage later; asking only when you fetch the results retrieves nothing new. The returned TestRunId works from any later session on any computer: pass it to Get-SalesforceApexTestResult or Wait-SalesforceApexTest. To run and wait in one call use Test-SalesforceApex.

#### Parameters

- `-ClassName` (String[]): Apex test classes to run. Passed as --class-names, one flag per class. Cannot be combined with -TestName or -SuiteName.
- `-TestName` (String[]): Individual test methods to run, written Class.method. Passed as --tests, one flag per test. Cannot be combined with -ClassName or -SuiteName.
- `-SuiteName` (String[]): Apex test suites to run. Passed as --suite-names, one flag per suite. Cannot be combined with -ClassName or -TestName.
- `-TestLevel` (String): Level of tests to run; default is RunLocalTests. Passed to sf as --test-level. Valid values: RunLocalTests, RunAllTestsInOrg, RunSpecifiedTests.
- `-CodeCoverage` (switch): Retrieve code coverage results. Adds --code-coverage.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf apex run test`

#### Examples

```powershell
PS> $run = Start-SalesforceApexTest -TestLevel RunLocalTests -CodeCoverage -TargetOrg myorg; $run.TestRunId
```

#### Remarks

- To see the examples, type: "Get-Help Start-SalesforceApexTest -Examples"
- For more information, type: "Get-Help Start-SalesforceApexTest -Detailed"
- For technical information, type: "Get-Help Start-SalesforceApexTest -Full"
- For online help, type: "Get-Help Start-SalesforceApexTest -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-apex>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Test-SalesforceApex

#### Synopsis

Runs Apex tests in an org and returns the result.

#### Syntax

```powershell
Test-SalesforceApex [[-ClassName] <String>] [[-TestName] <String>] [[-ResultFormat] <String>] [-Concise] [-CodeCoverage] [-CodeCoverageDetailed] [[-WaitMinutes] <Int32>] [[-OutputDirectory] <String>] [-TestsInProject] [[-PollIntervalSeconds] <Int32>] [-Synchronous] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf apex run test (waiting up to -WaitMinutes) and returns the result in the format you choose. -TestsInProject runs the test classes found in the local project. With the default json format the result is returned as an object. For a run that returns a run ID to poll, use Start-SalesforceApexTest.

#### Parameters

- `-ClassName` (String): Test class to run. psfdx passes it as --tests &lt;ClassName&gt;, or as --tests &lt;ClassName&gt;.&lt;TestName&gt; when -TestName is also given. Ignored with -TestsInProject.
- `-TestName` (String): A single test method to run, used together with -ClassName; psfdx passes --tests &lt;ClassName&gt;.&lt;TestName&gt;. Without -ClassName it has no effect. Ignored with -TestsInProject.
- `-ResultFormat` (String): Format of the test results. Passed to sf as --result-format. Default: json. Valid values: human, tap, junit, json.
- `-Concise` (switch): Display only failed test results; works with human-readable output only. Adds --concise.
- `-CodeCoverage` (switch): Retrieve code coverage results. Adds --code-coverage.
- `-CodeCoverageDetailed` (switch): Display detailed code coverage per test. Adds --detailed-coverage.
- `-WaitMinutes` (Int32): Sets the streaming client socket timeout in minutes; specify a longer wait time if timeouts occur frequently. Passed to sf as --wait. Default: 10.
- `-OutputDirectory` (String): Directory in which to store test run files. Passed to sf as --output-dir.
- `-TestsInProject` (switch): Run every Apex test class found in the local project. psfdx reads the project folder and passes one --tests &lt;class&gt; per class it finds, so there is no matching CLI flag. The cmdlet stops if it finds none. It takes the place of -ClassName and -TestName.
- `-PollIntervalSeconds` (Int32): Number of seconds to wait between checks while the tests run. Passed to sf as --poll-interval.
- `-Synchronous` (switch): Run the test methods of a single Apex class synchronously, so the command waits for the results; without it the tests run asynchronously. It needs -ClassName and cannot be used with -TestsInProject or -TestName. Adds --synchronous.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf apex run test`

#### Examples

```powershell
PS> Test-SalesforceApex -ClassName AccountServiceTest -CodeCoverage -TargetOrg dev1
```

Run one test class with coverage.

#### Remarks

- To see the examples, type: "Get-Help Test-SalesforceApex -Examples"
- For more information, type: "Get-Help Test-SalesforceApex -Detailed"
- For technical information, type: "Get-Help Test-SalesforceApex -Full"
- For online help, type: "Get-Help Test-SalesforceApex -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-apex>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Wait-SalesforceApexTest

#### Synopsis

Waits for an Apex test run to finish and returns its results.

#### Syntax

```powershell
Wait-SalesforceApexTest [-TestRunId] <String> [[-TimeoutMinutes] <Int32>] [[-PollSeconds] <Int32>] [-CodeCoverage] [-CodeCoverageDetailed] [-Concise] [[-OutputDirectory] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Polls Get-SalesforceApexTestResult every -PollSeconds until the run is no longer queued or processing, then returns the same object. If -TimeoutMinutes pass first it throws PsfdxTestRunTimeout, whose TargetObject is the TestRunId, and the run carries on in the org. Failing tests and CLI errors surface exactly as for Get-SalesforceApexTestResult.

#### Parameters

- `-TestRunId` (String, required): ID of the test run to wait for, as returned by Start-SalesforceApexTest or Test-SalesforceApex. It must start with 707. Required.
- `-TimeoutMinutes` (Int32): How long to wait, in minutes, before giving up with PsfdxTestRunTimeout. The run carries on in the org. Default 10. Default: 10. Range: 1 to 1440.
- `-PollSeconds` (Int32): Seconds to wait between checks of the run's status. Default 10. Default: 10. Range: 1 to 600.
- `-CodeCoverage` (switch): Include code coverage in the result. Passed on to Get-SalesforceApexTestResult as --code-coverage; the run must have been started with coverage.
- `-CodeCoverageDetailed` (switch): Include line-by-line code coverage. Passed on to Get-SalesforceApexTestResult as --detailed-coverage.
- `-Concise` (switch): Show only failing tests in human-readable output. Passed on to Get-SalesforceApexTestResult as --concise.
- `-OutputDirectory` (String): Folder to write the result files to. Passed on to Get-SalesforceApexTestResult as --output-dir.
- `-TargetOrg` (String): Username or alias of the org the run is in. If omitted, the Salesforce CLI uses the default target org.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> $run = Start-SalesforceApexTest -TargetOrg myorg; Wait-SalesforceApexTest -TestRunId $run.TestRunId -TimeoutMinutes 30 -CodeCoverage -TargetOrg myorg
```

#### Remarks

- To see the examples, type: "Get-Help Wait-SalesforceApexTest -Examples"
- For more information, type: "Get-Help Wait-SalesforceApexTest -Detailed"
- For technical information, type: "Get-Help Wait-SalesforceApexTest -Full"
- For online help, type: "Get-Help Wait-SalesforceApexTest -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Watch-SalesforceApex

#### Synopsis

Runs Apex tests and deploys automatically when you save an Apex file.

#### Syntax

```powershell
Watch-SalesforceApex [[-ProjectFolder] <String>] [[-CooldownMilliseconds] <Int32>] [-IgnoreErrors] [<CommonParameters>]
```

#### Description

Watches the project folder with a file system watcher. On each change to an Apex class or trigger file it deploys that one component and, when it finds test classes that reference it in the project, runs them as part of the deployment. It keeps running until you press Ctrl+C. The deployment goes to the default target org; there is no -TargetOrg.

#### Parameters

- `-ProjectFolder` (String): Folder of the Salesforce DX project to watch. Defaults to the current folder. It must exist.
- `-CooldownMilliseconds` (Int32): Ignore repeat events for the same file within this many milliseconds. Default 300. Default: 300.
- `-IgnoreErrors` (switch): Keep watching after a deploy or test fails instead of stopping.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Watch-SalesforceApex -ProjectFolder .
```

Deploy and test on every save.

#### Remarks

- To see the examples, type: "Get-Help Watch-SalesforceApex -Examples"
- For more information, type: "Get-Help Watch-SalesforceApex -Detailed"
- For technical information, type: "Get-Help Watch-SalesforceApex -Full"
- For online help, type: "Get-Help Watch-SalesforceApex -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Code Analyzer

### Get-SalesforceCodeAnalyzerAst

#### Synopsis

Shows the syntax tree that PMD builds for a source file.

#### Syntax

```powershell
Get-SalesforceCodeAnalyzerAst [-File] <String> [[-Language] <String>] [[-Format] <String>] [[-OutputFile] <String>] [<CommonParameters>]
```

#### Description

Runs sf code-analyzer ast-dump. The AST is what PMD sees when it parses the file, which helps you write and debug custom PMD rules. It works for Apex, Visualforce, HTML, XML and JavaScript files, and it needs Java 11 or later. The CLI writes the tree to a file, so psfdx reads that file: with -Format json (the default here) you get one object per node, with its name, attributes, parent and ancestors, as the CLI reports them; with -Format xml you get the raw tree as an XML document. Give -OutputFile to keep the file; without it a temporary file is used and removed.

#### Parameters

- `-File` (String, required): Path of the source file to parse. It must exist and be a file, not a folder. Passed to sf as --file. Required.
- `-Language` (String): Language of the source file. By default the CLI uses apex. Valid values: apex, visualforce, html, xml, javascript. Passed to sf as --language.
- `-Format` (String): Format of the tree. Valid values: json, xml. The CLI default is xml; this cmdlet uses json unless you say otherwise, because it gives objects. Passed to sf as --format.
- `-OutputFile` (String): File to write the tree to. The folder must exist. An existing file is overwritten. Passed to sf as --output-file.

#### Salesforce CLI

- `sf code-analyzer ast-dump`

#### Examples

```powershell
PS> Get-SalesforceCodeAnalyzerAst -File .\force-app\main\default\classes\MyClass.cls | Select-Object -First 5
```

The first nodes of an Apex class's tree.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceCodeAnalyzerAst -Examples"
- For more information, type: "Get-Help Get-SalesforceCodeAnalyzerAst -Detailed"
- For technical information, type: "Get-Help Get-SalesforceCodeAnalyzerAst -Full"
- For online help, type: "Get-Help Get-SalesforceCodeAnalyzerAst -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-code-analyzer>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceCodeAnalyzerConfig

#### Synopsis

Shows the current Code Analyzer configuration as YAML.

#### Syntax

```powershell
Get-SalesforceCodeAnalyzerConfig [[-Workspace] <String[]>] [[-Target] <String[]>] [[-RuleSelector] <String[]>] [[-ConfigFile] <String>] [[-OutputFile] <String>] [-IncludeUnmodifiedRules] [-NoSuppressions] [<CommonParameters>]
```

#### Description

Runs sf code-analyzer config and returns the configuration as one YAML string: the top-level settings and the engine and rule overrides for the selected rules, with any code-analyzer.yml in the current folder (or -ConfigFile) applied. The CLI has no --json flag, so the YAML is read from a file. Give -OutputFile to keep that file, for example to save the state as the new code-analyzer.yml (the CLI keeps the values and overwrites the comments); without it a temporary file is used and removed. A plugin or engine failure throws the CLI message with install guidance.

#### Parameters

- `-Workspace` (String[]): Set of files that make up your workspace. Each is passed to sf as its own --workspace. Each must exist. Passed to sf as --workspace.
- `-Target` (String[]): Subset of files within your workspace to target. Each is passed to sf as its own --target. Passed to sf as --target.
- `-RuleSelector` (String[]): Selection of rules, based on engine name, severity level, rule name, tag, or a combination of criteria. Each is passed to sf as its own --rule-selector. The CLI default is all. Passed to sf as --rule-selector.
- `-ConfigFile` (String): Path to an existing configuration file to start from. It must exist. Passed to sf as --config-file.
- `-OutputFile` (String): File to write the configuration state to, in YAML. The folder must exist. An existing file is overwritten. Passed to sf as --output-file.
- `-IncludeUnmodifiedRules` (switch): Also list the rules whose settings have not been changed, in the rule override settings. Adds --include-unmodified-rules.
- `-NoSuppressions` (switch): Leave suppressions out of the output configuration. Adds --no-suppressions.

#### Salesforce CLI

- `sf code-analyzer config`

#### Examples

```powershell
PS> Get-SalesforceCodeAnalyzerConfig
```

The YAML for all rules, with the code-analyzer.yml of the current folder applied.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceCodeAnalyzerConfig -Examples"
- For more information, type: "Get-Help Get-SalesforceCodeAnalyzerConfig -Detailed"
- For technical information, type: "Get-Help Get-SalesforceCodeAnalyzerConfig -Full"
- For online help, type: "Get-Help Get-SalesforceCodeAnalyzerConfig -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-code-analyzer>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceCodeAnalyzerRule

#### Synopsis

Lists the Code Analyzer rules that match a selector (sf code-analyzer rules).

#### Syntax

```powershell
Get-SalesforceCodeAnalyzerRule [[-RuleSelector] <String[]>] [[-Workspace] <String[]>] [[-Target] <String[]>] [[-ConfigFile] <String>] [[-View] <String>] [<CommonParameters>]
```

#### Description

Returns one object per rule (as the CLI reports it: name, engine, severity, tags, description, resources). The CLI has no --json flag, so the rules are read from a temporary JSON report file. With no selector the CLI lists its default rules. A selector such as Recommended, Security, pmd or pmd:Security narrows the list. A plugin or engine failure throws the CLI message with install guidance.

#### Parameters

- `-RuleSelector` (String[]): Selection of rules, based on engine name, severity level, rule name, tag, or a combination of criteria separated by colons. Passed to sf as --rule-selector.
- `-Workspace` (String[]): Set of files that make up your workspace. Passed to sf as --workspace.
- `-Target` (String[]): Subset of files within your workspace that you want to target for analysis. Passed to sf as --target.
- `-ConfigFile` (String): Path to the configuration file used to customize the engines and rules. Passed to sf as --config-file.
- `-View` (String): How the CLI displays the rules in the terminal. Passed to sf as --view. Valid values: detail, table. The cmdlet reads the rules from a report file, so this changes only the text the CLI prints, not the returned objects.

#### Salesforce CLI

- `sf code-analyzer rules`

#### Examples

```powershell
PS> Get-SalesforceCodeAnalyzerRule -RuleSelector Security | Select-Object name, engine, severity
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceCodeAnalyzerRule -Examples"
- For more information, type: "Get-Help Get-SalesforceCodeAnalyzerRule -Detailed"
- For technical information, type: "Get-Help Get-SalesforceCodeAnalyzerRule -Full"
- For online help, type: "Get-Help Get-SalesforceCodeAnalyzerRule -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-code-analyzer>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Invoke-SalesforceCodeAnalyzer

#### Synopsis

Runs Salesforce Code Analyzer over a workspace and returns the findings as objects (sf code-analyzer run).

#### Syntax

```powershell
Invoke-SalesforceCodeAnalyzer [[-Workspace] <String[]>] [[-Target] <String[]>] [[-RuleSelector] <String[]>] [[-ConfigFile] <String>] [[-SeverityThreshold] <String>] [-ThrowOnThreshold] [-IncludeFixes] [-IncludeSuggestions] [-NoSuppressions] [[-TargetOrg] <String>] [[-View] <String>] [[-OutputFile] <String[]>] [<CommonParameters>]
```

#### Description

Returns one object with Passed, ThresholdExceeded, ViolationCount, a count per severity, Violations (one object per finding with Rule, Engine, Severity, Message, File, StartLine, StartColumn, EndLine, EndColumn, Tags, Resources, and Fixes and Suggestions when the CLI reports them), RunDirectory and Versions. With -SeverityThreshold the CLI fails when a finding is at or above that severity. That is a threshold failure, not an error: the findings are still returned (the exit code is non-zero but the report is written) with Passed = $false and ThresholdExceeded = $true. Add -ThrowOnThreshold to turn it into an error (id PsfdxCodeAnalyzerThresholdExceeded, with the result as the target object) so a CI step fails. If the plugin or an engine cannot start there is no report, and the cmdlet always throws (id PsfdxCodeAnalyzerFailed) with the CLI message. The plugin is installed with the Salesforce CLI or with Install-SalesforcePlugin. Engines such as PMD and the Java-based rules need Java 11 or later; the CLI downloads engine dependencies on first use, so the first run can be slow and needs network access.

#### Parameters

- `-Workspace` (String[]): Set of files that make up your workspace. Passed to sf as --workspace.
- `-Target` (String[]): Subset of files within your workspace to be targeted for analysis. Passed to sf as --target.
- `-RuleSelector` (String[]): Selection of rules, based on engine name, severity level, rule name, tag, or a combination of criteria separated by colons. Passed to sf as --rule-selector.
- `-ConfigFile` (String): Path to the configuration file used to customize the engines and rules. Passed to sf as --config-file.
- `-SeverityThreshold` (String): Severity level of a found violation that must be met or exceeded to cause this command to fail with a non-zero exit code. Passed to sf as --severity-threshold. Valid values: 1, 2, 3, 4, 5, Critical, High, Moderate, Low, Info.
- `-ThrowOnThreshold` (switch): Throw an error (id PsfdxCodeAnalyzerThresholdExceeded, with the result as its target object) when a finding meets -SeverityThreshold, instead of returning the findings with ThresholdExceeded set. Meant for CI.
- `-IncludeFixes` (switch): Include fix data for the violations that have one. Each violation then has a Fixes property, as the CLI reports it. Adds --include-fixes.
- `-IncludeSuggestions` (switch): Include suggestion data for the violations that have one. Each violation then has a Suggestions property, as the CLI reports it. Adds --include-suggestions.
- `-NoSuppressions` (switch): Do not process inline and bulk suppression markers, so suppressed violations are reported again. Adds --no-suppressions.
- `-TargetOrg` (String): Username or alias of the org that remote analysis engines use, such as the engine that needs an org connection. Passed to sf as --target-org.
- `-View` (String): How the CLI displays the results in the terminal. Passed to sf as --view. Valid values: detail, table. The cmdlet reads the results from a report file, so this changes only the text the CLI prints, not the returned object.
- `-OutputFile` (String[]): Extra files to write the results to, in addition to the object that is returned. The file format follows each extension, such as .csv, .html or .xml. Each one is passed to sf as its own --output-file. The folders must exist.

#### Salesforce CLI

- `sf code-analyzer run`

#### Examples

```powershell
PS> Invoke-SalesforceCodeAnalyzer -Workspace force-app -RuleSelector Recommended -SeverityThreshold 2 -ThrowOnThreshold
```

#### Remarks

- To see the examples, type: "Get-Help Invoke-SalesforceCodeAnalyzer -Examples"
- For more information, type: "Get-Help Invoke-SalesforceCodeAnalyzer -Detailed"
- For technical information, type: "Get-Help Invoke-SalesforceCodeAnalyzer -Full"
- For online help, type: "Get-Help Invoke-SalesforceCodeAnalyzer -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-code-analyzer>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Flow and logic tests

### Get-SalesforceFlowTestResult

#### Synopsis

Gets the results of an earlier Flow test run (sf flow get test).

#### Syntax

```powershell
Get-SalesforceFlowTestResult [-TestRunId] <String> [[-ResultFormat] <String>] [-Concise] [-CodeCoverage] [-CodeCoverageDetailed] [[-OutputDirectory] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Takes the TestRunId that Test-SalesforceFlow returned. Failed tests throw PsfdxTestsFailed and a command that could not run throws PsfdxTestRunInvocationFailed, as for Test-SalesforceFlow. A run that has not finished yet is reported by the CLI as an invocation failure or as its current counts, depending on the CLI version.

#### Parameters

- `-TestRunId` (String, required): ID of the test run. Passed to sf as --test-run-id. Required.
- `-ResultFormat` (String): Format of the test results. Passed to sf as --result-format. Default: json. Valid values: human, tap, junit, json.
- `-Concise` (switch): Display only failed test results; works with human-readable output only. Adds --concise.
- `-CodeCoverage` (switch): Retrieve code coverage results. Adds --code-coverage.
- `-CodeCoverageDetailed` (switch): Not available for flow tests. Adds --detailed-coverage.
- `-OutputDirectory` (String): Directory in which to store test result files. Passed to sf as --output-dir.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf flow get test`

#### Examples

```powershell
PS> Get-SalesforceFlowTestResult -TestRunId 707xx0000000001 -TargetOrg myorg
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceFlowTestResult -Examples"
- For more information, type: "Get-Help Get-SalesforceFlowTestResult -Detailed"
- For technical information, type: "Get-Help Get-SalesforceFlowTestResult -Full"
- For online help, type: "Get-Help Get-SalesforceFlowTestResult -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-flow>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceLogicTestResult

#### Synopsis

Gets the results of an earlier Flow and Apex test run (sf logic get test).

#### Syntax

```powershell
Get-SalesforceLogicTestResult [-TestRunId] <String> [[-ResultFormat] <String>] [-Concise] [-CodeCoverage] [-CodeCoverageDetailed] [[-OutputDirectory] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Takes the TestRunId that Test-SalesforceLogic returned. Errors are the same as for Test-SalesforceLogic.

#### Parameters

- `-TestRunId` (String, required): ID of the test run. Passed to sf as --test-run-id. Required.
- `-ResultFormat` (String): Format of the test results. Passed to sf as --result-format. Default: json. Valid values: human, tap, junit, json.
- `-Concise` (switch): Display only failed test results; works with human-readable output only. Adds --concise.
- `-CodeCoverage` (switch): Retrieve code coverage results. Adds --code-coverage.
- `-CodeCoverageDetailed` (switch): Display detailed code coverage per test. Adds --detailed-coverage.
- `-OutputDirectory` (String): Directory in which to store test result files. Passed to sf as --output-dir.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf logic get test`

#### Examples

```powershell
PS> Get-SalesforceLogicTestResult -TestRunId 707xx0000000001 -CodeCoverage -TargetOrg myorg
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceLogicTestResult -Examples"
- For more information, type: "Get-Help Get-SalesforceLogicTestResult -Detailed"
- For technical information, type: "Get-Help Get-SalesforceLogicTestResult -Full"
- For online help, type: "Get-Help Get-SalesforceLogicTestResult -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-apex>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Test-SalesforceFlow

#### Synopsis

Runs Flow tests in an org (sf flow run test).

#### Syntax

```powershell
Test-SalesforceFlow [[-FlowName] <String[]>] [[-TestName] <String[]>] [[-SuiteName] <String[]>] [[-TestLevel] <String>] [-Synchronous] [[-ResultFormat] <String>] [-Concise] [-CodeCoverage] [[-OutputDirectory] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

By default the run is asynchronous: the cmdlet returns an object with a TestRunId, and Get-SalesforceFlowTestResult fetches the results later. With -Synchronous (one flow only) it waits and returns the results. Needs the "View All Data" permission.

A finished run returns one object with Summary, Tests and Coverage (Coverage is empty unless -CodeCoverage was given), and TestRunId. Without -Synchronous the CLI starts the run and returns at once.

Failed tests and a command that could not run are different errors. A failed test run writes the result object to the pipeline, then throws an error whose FullyQualifiedErrorId is PsfdxTestsFailed (the CLI summary is the error's TargetObject). Everything else, such as no authorisation or a missing plugin, throws PsfdxTestRunInvocationFailed.

Code coverage is returned but never judged; there is no coverage threshold.

#### Parameters

- `-FlowName` (String[]): Flows to test (--class-names). Cannot be combined with -TestName or -SuiteName.
- `-TestName` (String[]): Specific tests in Flow.Test form (--tests).
- `-SuiteName` (String[]): Test suites to run (--suite-names).
- `-TestLevel` (String): RunLocalTests (the CLI default), RunAllTestsInOrg or RunSpecifiedTests. Naming flows or tests needs RunSpecifiedTests, which is the default then.
- `-Synchronous` (switch): Run flow tests for one flow synchronously; if not specified, tests are run asynchronously. Adds --synchronous.
- `-ResultFormat` (String): Format of the test results. Passed to sf as --result-format. Default: json. Valid values: human, tap, junit, json.
- `-Concise` (switch): Display only failed test results; works with human-readable output only. Adds --concise.
- `-CodeCoverage` (switch): Retrieve code coverage results. Adds --code-coverage.
- `-OutputDirectory` (String): Directory in which to store test result files. Passed to sf as --output-dir.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf flow run test`

#### Examples

```powershell
PS> Test-SalesforceFlow -TestLevel RunLocalTests -TargetOrg myorg
```

#### Remarks

- To see the examples, type: "Get-Help Test-SalesforceFlow -Examples"
- For more information, type: "Get-Help Test-SalesforceFlow -Detailed"
- For technical information, type: "Get-Help Test-SalesforceFlow -Full"
- For online help, type: "Get-Help Test-SalesforceFlow -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-flow>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Test-SalesforceLogic

#### Synopsis

Runs Flow and Apex tests together in an org (sf logic run test).

#### Syntax

```powershell
Test-SalesforceLogic [[-ClassName] <String[]>] [[-TestName] <String[]>] [[-SuiteName] <String[]>] [[-TestCategory] <String[]>] [[-TestLevel] <String>] [-Synchronous] [[-WaitMinutes] <Int32>] [[-ResultFormat] <String>] [-Concise] [-CodeCoverage] [-CodeCoverageDetailed] [[-OutputDirectory] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Like Test-SalesforceFlow, but -TestName and -ClassName also accept Apex tests, and -TestCategory picks Apex, Flow or both. The run is asynchronous unless -Synchronous or -WaitMinutes is given; an asynchronous run, or a wait that times out, returns an object with a TestRunId for Get-SalesforceLogicTestResult. Failed tests throw PsfdxTestsFailed; a command that could not run throws PsfdxTestRunInvocationFailed. -TestCategory needs -TestLevel. The command is in beta in the CLI. Test-SalesforceApex still runs Apex alone.

#### Parameters

- `-ClassName` (String[]): Test classes to run. Passed as --class-names. Use only one of -ClassName, -TestName, -SuiteName and -TestCategory.
- `-TestName` (String[]): Individual tests to run: Apex as Class.method, flows as FlowName.TestName. Passed as --tests. Use only one of -ClassName, -TestName, -SuiteName and -TestCategory.
- `-SuiteName` (String[]): Test suites to run. Passed as --suite-names. Use only one of -ClassName, -TestName, -SuiteName and -TestCategory.
- `-TestCategory` (String[]): Run Apex tests, Flow tests or both, with -TestLevel. Passed as --test-category, one flag per category. Use only one of -ClassName, -TestName, -SuiteName and -TestCategory. Valid values: Apex, Flow.
- `-TestLevel` (String): Level of tests to run; default is RunLocalTests. Passed to sf as --test-level. Valid values: RunLocalTests, RunAllTestsInOrg, RunSpecifiedTests.
- `-Synchronous` (switch): Runs test methods from a single Apex class synchronously; if not specified, tests are run asynchronously. Adds --synchronous.
- `-WaitMinutes` (Int32): Sets the streaming client socket timeout in minutes; specify a longer wait time if timeouts occur frequently. Passed to sf as --wait. Range: 0 to 1440.
- `-ResultFormat` (String): Format of the test results. Passed to sf as --result-format. Default: json. Valid values: human, tap, junit, json.
- `-Concise` (switch): Display only failed test results; works with human-readable output only. Adds --concise.
- `-CodeCoverage` (switch): Retrieve code coverage results. Adds --code-coverage.
- `-CodeCoverageDetailed` (switch): Display detailed code coverage per test. Adds --detailed-coverage.
- `-OutputDirectory` (String): Directory in which to store test run files. Passed to sf as --output-dir.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf logic run test`

#### Examples

```powershell
PS> Test-SalesforceLogic -TestCategory Apex, Flow -TestLevel RunLocalTests -Synchronous -TargetOrg myorg
```

#### Remarks

- To see the examples, type: "Get-Help Test-SalesforceLogic -Examples"
- For more information, type: "Get-Help Test-SalesforceLogic -Detailed"
- For technical information, type: "Get-Help Test-SalesforceLogic -Full"
- For online help, type: "Get-Help Test-SalesforceLogic -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-apex>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Org shapes and snapshots

### Get-SalesforceOrgShapes

#### Synopsis

Lists the org shapes of the orgs this computer is logged in to.

#### Syntax

```powershell
Get-SalesforceOrgShapes [<CommonParameters>]
```

#### Description

Runs sf org list shape and returns one object per shape (the org it came from, the shape ID, its status and when it was created).

#### Salesforce CLI

- `sf org list shape`

#### Examples

```powershell
PS> Get-SalesforceOrgShapes | Format-Table
```

List every shape.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceOrgShapes -Examples"
- For more information, type: "Get-Help Get-SalesforceOrgShapes -Detailed"
- For technical information, type: "Get-Help Get-SalesforceOrgShapes -Full"
- For online help, type: "Get-Help Get-SalesforceOrgShapes -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-signups>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceOrgSnapshot

#### Synopsis

Shows one scratch org snapshot, including whether it is ready to use.

#### Syntax

```powershell
Get-SalesforceOrgSnapshot [-Snapshot] <String> [[-TargetDevHub] <String>] [<CommonParameters>]
```

#### Description

Runs sf org get snapshot for the snapshot name or ID. Use Get-SalesforceOrgSnapshots to list them all.

#### Parameters

- `-Snapshot` (String, required): Name or ID of the snapshot. Passed to sf as --snapshot. Required.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

#### Salesforce CLI

- `sf org get snapshot`

#### Examples

```powershell
PS> Get-SalesforceOrgSnapshot -Snapshot Release1 -TargetDevHub devhub
```

Show the status of the snapshot.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceOrgSnapshot -Examples"
- For more information, type: "Get-Help Get-SalesforceOrgSnapshot -Detailed"
- For technical information, type: "Get-Help Get-SalesforceOrgSnapshot -Full"
- For online help, type: "Get-Help Get-SalesforceOrgSnapshot -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-signups>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceOrgSnapshots

#### Synopsis

Lists the scratch org snapshots of a Dev Hub.

#### Syntax

```powershell
Get-SalesforceOrgSnapshots [[-TargetDevHub] <String>] [<CommonParameters>]
```

#### Description

Runs sf org list snapshot and returns one object per snapshot (name, ID, status, source org and when it was created).

#### Parameters

- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.

#### Salesforce CLI

- `sf org list snapshot`

#### Examples

```powershell
PS> Get-SalesforceOrgSnapshots -TargetDevHub devhub | Format-Table
```

List the snapshots of the Dev Hub.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceOrgSnapshots -Examples"
- For more information, type: "Get-Help Get-SalesforceOrgSnapshots -Detailed"
- For technical information, type: "Get-Help Get-SalesforceOrgSnapshots -Full"
- For online help, type: "Get-Help Get-SalesforceOrgSnapshots -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-signups>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceOrgShape

#### Synopsis

Creates an org shape from an org.

#### Syntax

```powershell
New-SalesforceOrgShape [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf org create shape. An org shape records the edition, features and settings of the source org, so that scratch orgs can be created to match it (see New-SalesforceScratchOrg -SourceOrgId). The org must have Scratch Org Shape turned on.

#### Parameters

- `-TargetOrg` (String): Username or alias of the org to take the shape from. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org create shape`

#### Examples

```powershell
PS> New-SalesforceOrgShape -TargetOrg prod
```

Create a shape from the prod org.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceOrgShape -Examples"
- For more information, type: "Get-Help New-SalesforceOrgShape -Detailed"
- For technical information, type: "Get-Help New-SalesforceOrgShape -Full"
- For online help, type: "Get-Help New-SalesforceOrgShape -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-signups>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceOrgSnapshot

#### Synopsis

Creates a scratch org snapshot from an org.

#### Syntax

```powershell
New-SalesforceOrgSnapshot [-SourceOrg] <String> [-SnapshotName] <String> [[-Description] <String>] [[-TargetDevHub] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf org create snapshot. A snapshot is a copy of a scratch org that you can create new scratch orgs from (see New-SalesforceScratchOrg -Snapshot). The snapshot is made in the Dev Hub. Snapshots are a pilot feature of Salesforce. Creation is asynchronous: use Get-SalesforceOrgSnapshot to see when it is ready.

#### Parameters

- `-SourceOrg` (String, required): Username or alias of the scratch org to copy. Passed to sf as --source-org. Required.
- `-SnapshotName` (String, required): Name of the snapshot. Passed to sf as --name. Required.
- `-Description` (String): Description of the snapshot. Passed to sf as --description.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org create snapshot`

#### Examples

```powershell
PS> New-SalesforceOrgSnapshot -SourceOrg my-scratch -SnapshotName Release1 -Description 'Before the upgrade' -TargetDevHub devhub
```

Take a snapshot of a scratch org.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceOrgSnapshot -Examples"
- For more information, type: "Get-Help New-SalesforceOrgSnapshot -Detailed"
- For technical information, type: "Get-Help New-SalesforceOrgSnapshot -Full"
- For online help, type: "Get-Help New-SalesforceOrgSnapshot -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-signups>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceOrgShape

#### Synopsis

Deletes the org shapes of an org.

#### Syntax

```powershell
Remove-SalesforceOrgShape [-NoPrompt] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf org delete shape. This cannot be undone, and scratch orgs can no longer be created from the deleted shape. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time.

#### Parameters

- `-NoPrompt` (switch): Don't ask for confirmation. Skips the PowerShell confirmation; psfdx always passes --no-prompt to the CLI after it has confirmed.
- `-TargetOrg` (String): Username or alias of the org whose shapes are deleted. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org delete shape`

#### Examples

```powershell
PS> Remove-SalesforceOrgShape -TargetOrg prod -WhatIf
```

Preview the delete.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceOrgShape -Examples"
- For more information, type: "Get-Help Remove-SalesforceOrgShape -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceOrgShape -Full"
- For online help, type: "Get-Help Remove-SalesforceOrgShape -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-signups>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceOrgSnapshot

#### Synopsis

Deletes a scratch org snapshot.

#### Syntax

```powershell
Remove-SalesforceOrgSnapshot [-Snapshot] <String> [-NoPrompt] [[-TargetDevHub] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf org delete snapshot. This cannot be undone. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. psfdx confirms first, so it always passes --no-prompt and the CLI does not ask a second time.

#### Parameters

- `-Snapshot` (String, required): Name or ID of the snapshot to delete. Passed to sf as --snapshot. Required.
- `-NoPrompt` (switch): Don't ask for confirmation. Skips the PowerShell confirmation; psfdx always passes --no-prompt to the CLI after it has confirmed.
- `-TargetDevHub` (String): Username or alias of the Dev Hub org. Not required if the `target-dev-hub` configuration variable is already set. Passed to sf as --target-dev-hub.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org delete snapshot`

#### Examples

```powershell
PS> Remove-SalesforceOrgSnapshot -Snapshot Release1 -TargetDevHub devhub -WhatIf
```

Preview the delete.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceOrgSnapshot -Examples"
- For more information, type: "Get-Help Remove-SalesforceOrgSnapshot -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceOrgSnapshot -Full"
- For online help, type: "Get-Help Remove-SalesforceOrgSnapshot -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-signups>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Local development servers

### Install-SalesforceLwcDevServer

#### Synopsis

Installs the Salesforce CLI plugin that provides the LWC local dev server.

#### Syntax

```powershell
Install-SalesforceLwcDevServer [<CommonParameters>]
```

#### Description

Runs sf plugins install @salesforce/plugin-lightning-dev. Start-SalesforceLwcDevServer stops with a message pointing here until the plugin is installed.

#### Salesforce CLI

- `sf plugins install`

#### Examples

```powershell
PS> Install-SalesforceLwcDevServer
```

Install the plugin.

#### Remarks

- To see the examples, type: "Get-Help Install-SalesforceLwcDevServer -Examples"
- For more information, type: "Get-Help Install-SalesforceLwcDevServer -Detailed"
- For technical information, type: "Get-Help Install-SalesforceLwcDevServer -Full"
- For online help, type: "Get-Help Install-SalesforceLwcDevServer -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/oclif/plugin-plugins>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Start-SalesforceLwcDevServer

#### Synopsis

Starts the local Lightning dev server for an app, a component or an Experience site.

#### Syntax

```powershell
Start-SalesforceLwcDevServer [[-Mode] <String>] [[-Name] <String>] [[-DeviceType] <String>] [[-DeviceId] <String>] [-ClientSelect] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf lightning dev app, component or site, chosen by -Mode, and keeps running until you stop it. Needs the @salesforce/plugin-lightning-dev plugin (Install-SalesforceLwcDevServer). -DeviceType only applies to -Mode App.

#### Parameters

- `-Mode` (String): What to preview: App (the default), Component or Site. psfdx runs the CLI command with that last word. Default: App. Valid values: App, Component, Site.
- `-Name` (String): Name of the app, component or site to preview. Passed as --name.
- `-DeviceType` (String): Type of device to display the app preview. Passed to sf as --device-type. Valid values: desktop, ios, android. Only with -Mode App.
- `-DeviceId` (String): ID of the mobile device to show the preview on, when -DeviceType is ios or android. By default the CLI uses the first mobile device it finds. Passed to sf as --device-id. Only with -Mode App.
- `-ClientSelect` (switch): Open the component preview without choosing a component first, so you pick one in the browser. Adds --client-select. Only with -Mode Component.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf lightning dev app`
- `sf lightning dev component`
- `sf lightning dev site`

#### Examples

```powershell
PS> Start-SalesforceLwcDevServer -Mode Component -Name accountCard -TargetOrg dev1
```

Preview one component.

#### Remarks

- To see the examples, type: "Get-Help Start-SalesforceLwcDevServer -Examples"
- For more information, type: "Get-Help Start-SalesforceLwcDevServer -Detailed"
- For technical information, type: "Get-Help Start-SalesforceLwcDevServer -Full"
- For online help, type: "Get-Help Start-SalesforceLwcDevServer -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-lightning-dev>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Start-SalesforceUiBundleDevServer

#### Synopsis

Previews a UI bundle on your computer, live, without deploying it to the org.

#### Syntax

```powershell
Start-SalesforceUiBundleDevServer [[-Name] <String>] [[-Url] <String>] [[-Port] <Int32>] [-Open] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf ui-bundle dev, which starts a local proxy in front of your own development server (such as a Vite server on https://localhost:5173). Pages, static files and hot updates are sent to your server, and Salesforce data and API requests go to the org with your login, so you can work on a UI bundle against real data before you deploy it. It keeps running until you stop it (Ctrl+C), so run it in its own terminal. Nothing is deployed and no org data changes. The command comes from the @salesforce/plugin-ui-bundle-dev plugin, which the CLI installs when it first needs it; if it is missing, install it with Install-SalesforcePlugin.

#### Parameters

- `-Name` (String): Name of the UI bundle to preview. If you leave it out the CLI looks in the project. Passed to sf as --name.
- `-Url` (String): URL where your development server runs, for example https://localhost:5173. It must be an absolute http:// or https:// URL. UI, static and hot update requests are forwarded to it. Passed to sf as --url.
- `-Port` (Int32): Local port the proxy listens on. Valid values: 1 to 65535. Passed to sf as --port.
- `-Open` (switch): Open the proxy URL in your default browser once the server is ready. Adds --open.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf ui-bundle dev`

#### Examples

```powershell
PS> Start-SalesforceUiBundleDevServer -Name myApp -Url https://localhost:5173 -Open -TargetOrg dev1
```

Proxy a local Vite server, with the org's data, and open the browser.

#### Remarks

- To see the examples, type: "Get-Help Start-SalesforceUiBundleDevServer -Examples"
- For more information, type: "Get-Help Start-SalesforceUiBundleDevServer -Detailed"
- For technical information, type: "Get-Help Start-SalesforceUiBundleDevServer -Full"
- For online help, type: "Get-Help Start-SalesforceUiBundleDevServer -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-ui-bundle-dev>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Component and template generation

### New-SalesforceAnalyticsTemplate

#### Synopsis

Creates the files of a simple CRM Analytics template in the project.

#### Syntax

```powershell
New-SalesforceAnalyticsTemplate [-Name] <String> [[-OutputDirectory] <String>] [-Force] [<CommonParameters>]
```

#### Description

Runs sf template generate analytics template. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the Analytics template already exists in the output folder the cmdlet stops, unless you pass -Force.

#### Parameters

- `-Name` (String, required): Name of the Analytics template. Letters, digits and underscores only. Passed to sf as --name. Required.
- `-OutputDirectory` (String): Folder to save the created files in. It must be a folder named waveTemplates, such as force-app/main/default/waveTemplates, or the CLI refuses. The CLI default is the current folder. Passed to sf as --output-dir.
- `-Force` (switch): Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

#### Salesforce CLI

- `sf template generate analytics template`

#### Examples

```powershell
PS> New-SalesforceAnalyticsTemplate -Name SalesDashboard -OutputDirectory force-app/main/default/waveTemplates
```

Generate the Analytics template.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceAnalyticsTemplate -Examples"
- For more information, type: "Get-Help New-SalesforceAnalyticsTemplate -Detailed"
- For technical information, type: "Get-Help New-SalesforceAnalyticsTemplate -Full"
- For online help, type: "Get-Help New-SalesforceAnalyticsTemplate -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceExperienceSite

#### Synopsis

Creates the files of a new Experience Cloud site in the project. Preview.

#### Syntax

```powershell
New-SalesforceExperienceSite [-Name] <String> [-TemplateName] <String> [[-AdminEmail] <String>] [[-UrlPathPrefix] <String>] [[-OutputDirectory] <String>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf template generate digital-experience site. This CLI command is a preview, so its flags, templates and output can change in a later release. It writes the site files into the project; it does not create the site in an org (deploy the files for that). It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput.

#### Parameters

- `-Name` (String, required): Name of the Experience Cloud site. Passed to sf as --name. Required.
- `-TemplateName` (String, required): Template to build the site from. Valid value: Build Your Own (LWR). Passed to sf as --template-name. Required.
- `-AdminEmail` (String): Email address of the site administrator. By default the CLI uses the user name of the authenticated user. Passed to sf as --admin-email.
- `-UrlPathPrefix` (String): URL path prefix of the site. Letters and digits only. Passed to sf as --url-path-prefix.
- `-OutputDirectory` (String): Folder to generate the site files in. Passed to sf as --output-dir.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf template generate digital-experience site`

#### Examples

```powershell
PS> New-SalesforceExperienceSite -Name 'Partner Portal' -TemplateName 'Build Your Own (LWR)' -UrlPathPrefix partners -TargetOrg dev1
```

Generate the files of an LWR site.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceExperienceSite -Examples"
- For more information, type: "Get-Help New-SalesforceExperienceSite -Detailed"
- For technical information, type: "Get-Help New-SalesforceExperienceSite -Full"
- For online help, type: "Get-Help New-SalesforceExperienceSite -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceFlexiPage

#### Synopsis

Creates a FlexiPage (Lightning page) in the project. Beta.

#### Syntax

```powershell
New-SalesforceFlexiPage [-Name] <String> [-Template] <String> [[-SObject] <String>] [[-Label] <String>] [[-Description] <String>] [[-PrimaryField] <String>] [[-SecondaryFields] <String[]>] [[-DetailFields] <String[]>] [[-OutputDirectory] <String>] [-Force] [<CommonParameters>]
```

#### Description

Runs sf template generate flexipage, which writes a record page, app page or home page under a flexipages folder in the output folder. This CLI command is in beta, so its flags and output can change in a later release. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. A record page needs -SObject. If the page already exists the cmdlet stops, unless you pass -Force.

#### Parameters

- `-Name` (String, required): API name of the FlexiPage. Letters, digits and underscores only. Passed to sf as --name. Required.
- `-Template` (String, required): Kind of page. Valid values: RecordPage, AppPage, HomePage. Passed to sf as --template. Required.
- `-SObject` (String): API name of the object the page is for. Required for a RecordPage. Passed to sf as --sobject.
- `-Label` (String): Label of the page. By default the CLI uses the name. Passed to sf as --label.
- `-Description` (String): Description of the page. Passed to sf as --description.
- `-PrimaryField` (String): Primary field of the highlights header, usually Name. Only for a RecordPage. Passed to sf as --primary-field.
- `-SecondaryFields` (String[]): Secondary fields of the highlights header, at most 11. Each is passed to sf as its own --secondary-fields. Only for a RecordPage. Passed to sf as --secondary-fields.
- `-DetailFields` (String[]): Fields to show in the Details tab, split into two columns. Each is passed to sf as its own --detail-fields. Only for a RecordPage. Passed to sf as --detail-fields.
- `-OutputDirectory` (String): Folder to save the created files in. It is created if it does not exist. The CLI default is the current folder. Passed to sf as --output-dir.
- `-Force` (switch): Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

#### Salesforce CLI

- `sf template generate flexipage`

#### Examples

```powershell
PS> New-SalesforceFlexiPage -Name Account_Record_Page -Template RecordPage -SObject Account -PrimaryField Name -SecondaryFields Industry, Phone -OutputDirectory force-app/main/default
```

Generate a record page for Account.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceFlexiPage -Examples"
- For more information, type: "Get-Help New-SalesforceFlexiPage -Detailed"
- For technical information, type: "Get-Help New-SalesforceFlexiPage -Full"
- For online help, type: "Get-Help New-SalesforceFlexiPage -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceLightningApp

#### Synopsis

Creates the files of a new Aura Lightning app in the project.

#### Syntax

```powershell
New-SalesforceLightningApp [-Name] <String> [[-Template] <String>] [[-OutputDirectory] <String>] [-Force] [<CommonParameters>]
```

#### Description

Runs sf template generate lightning app. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the Lightning app already exists in the output folder the cmdlet stops, unless you pass -Force.

#### Parameters

- `-Name` (String, required): Name of the Lightning app. Letters, digits and underscores only. Passed to sf as --name. Required.
- `-Template` (String): Template to use. Valid value: DefaultLightningApp, which is also the CLI default. Passed to sf as --template.
- `-OutputDirectory` (String): Folder to save the created files in. It must be a folder named aura, such as force-app/main/default/aura, or the CLI refuses. The CLI default is the current folder. Passed to sf as --output-dir.
- `-Force` (switch): Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

#### Salesforce CLI

- `sf template generate lightning app`

#### Examples

```powershell
PS> New-SalesforceLightningApp -Name MyApp -OutputDirectory force-app/main/default/aura
```

Generate the Lightning app.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceLightningApp -Examples"
- For more information, type: "Get-Help New-SalesforceLightningApp -Detailed"
- For technical information, type: "Get-Help New-SalesforceLightningApp -Full"
- For online help, type: "Get-Help New-SalesforceLightningApp -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceLightningComponent

#### Synopsis

Creates the files of a new Lightning web component or Aura component in the project.

#### Syntax

```powershell
New-SalesforceLightningComponent [-Name] <String> [[-Type] <String>] [[-Template] <String>] [[-OutputDirectory] <String>] [-Force] [<CommonParameters>]
```

#### Description

Runs sf template generate lightning component. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the component already exists in the output folder the cmdlet stops, unless you pass -Force. The output folder must be named lwc for a web component and aura for an Aura component.

#### Parameters

- `-Name` (String, required): Name of the component. Letters, digits and underscores only. Passed to sf as --name. Required.
- `-Type` (String): Kind of component. Valid values: aura, lwc. The CLI default is lwc. Passed to sf as --type.
- `-Template` (String): Template to use. Valid values: default, analyticsDashboard, analyticsDashboardWithStep, typescript. The CLI default is default. Passed to sf as --template.
- `-OutputDirectory` (String): Folder to save the created files in. It must be named lwc for -Type lwc and aura for -Type aura, or the CLI refuses. The CLI default is the current folder. Passed to sf as --output-dir.
- `-Force` (switch): Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

#### Salesforce CLI

- `sf template generate lightning component`

#### Examples

```powershell
PS> New-SalesforceLightningComponent -Name accountCard -Type lwc -OutputDirectory force-app/main/default/lwc
```

Generate a Lightning web component.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceLightningComponent -Examples"
- For more information, type: "Get-Help New-SalesforceLightningComponent -Detailed"
- For technical information, type: "Get-Help New-SalesforceLightningComponent -Full"
- For online help, type: "Get-Help New-SalesforceLightningComponent -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceLightningEvent

#### Synopsis

Creates the files of a new Aura Lightning event in the project.

#### Syntax

```powershell
New-SalesforceLightningEvent [-Name] <String> [[-Template] <String>] [[-OutputDirectory] <String>] [-Force] [<CommonParameters>]
```

#### Description

Runs sf template generate lightning event. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the Lightning event already exists in the output folder the cmdlet stops, unless you pass -Force.

#### Parameters

- `-Name` (String, required): Name of the Lightning event. Letters, digits and underscores only. Passed to sf as --name. Required.
- `-Template` (String): Template to use. Valid value: DefaultLightningEvt, which is also the CLI default. Passed to sf as --template.
- `-OutputDirectory` (String): Folder to save the created files in. It must be a folder named aura, such as force-app/main/default/aura, or the CLI refuses. The CLI default is the current folder. Passed to sf as --output-dir.
- `-Force` (switch): Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

#### Salesforce CLI

- `sf template generate lightning event`

#### Examples

```powershell
PS> New-SalesforceLightningEvent -Name MyEvent -OutputDirectory force-app/main/default/aura
```

Generate the Lightning event.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceLightningEvent -Examples"
- For more information, type: "Get-Help New-SalesforceLightningEvent -Detailed"
- For technical information, type: "Get-Help New-SalesforceLightningEvent -Full"
- For online help, type: "Get-Help New-SalesforceLightningEvent -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceLightningInterface

#### Synopsis

Creates the files of a new Aura Lightning interface in the project.

#### Syntax

```powershell
New-SalesforceLightningInterface [-Name] <String> [[-Template] <String>] [[-OutputDirectory] <String>] [-Force] [<CommonParameters>]
```

#### Description

Runs sf template generate lightning interface. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the Lightning interface already exists in the output folder the cmdlet stops, unless you pass -Force.

#### Parameters

- `-Name` (String, required): Name of the Lightning interface. Letters, digits and underscores only. Passed to sf as --name. Required.
- `-Template` (String): Template to use. Valid value: DefaultLightningIntf, which is also the CLI default. Passed to sf as --template.
- `-OutputDirectory` (String): Folder to save the created files in. It must be a folder named aura, such as force-app/main/default/aura, or the CLI refuses. The CLI default is the current folder. Passed to sf as --output-dir.
- `-Force` (switch): Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

#### Salesforce CLI

- `sf template generate lightning interface`

#### Examples

```powershell
PS> New-SalesforceLightningInterface -Name MyInterface -OutputDirectory force-app/main/default/aura
```

Generate the Lightning interface.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceLightningInterface -Examples"
- For more information, type: "Get-Help New-SalesforceLightningInterface -Detailed"
- For technical information, type: "Get-Help New-SalesforceLightningInterface -Full"
- For online help, type: "Get-Help New-SalesforceLightningInterface -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceLightningOutApp

#### Synopsis

Creates the metadata of a Lightning Out 2.0 app, with its External Client App.

#### Syntax

```powershell
New-SalesforceLightningOutApp [[-AppName] <String>] [[-Components] <String[]>] [[-DefinitionFile] <String>] [[-EcaName] <String>] [[-EcaContactEmail] <String>] [[-EcaCallbackUrl] <String>] [[-HostDomains] <String[]>] [[-Runtime] <String>] [[-OutputDirectory] <String>] [-Force] [<CommonParameters>]
```

#### Description

Runs sf template generate lightning-out, which scaffolds the files for a Lightning Out 2.0 app that puts Lightning web components in an outside web page. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. The CLI needs the External Client App name, contact email and callback URL, the runtime and the host domains. Give them as parameters, or in a -DefinitionFile JSON file; a parameter replaces the same value in the file. Without a file all of them are needed, and the cmdlet says which are missing before it runs sf.

#### Parameters

- `-AppName` (String): Developer name of the new Lightning Out 2.0 app. Passed to sf as --app-name.
- `-Components` (String[]): Components the app exposes, written as namespace/myComponent for a Lightning web component (c/myComponent for your own) or namespace:Name for an Aura component. Each is passed to sf as its own --components. They replace, not merge with, the components in the definition file. Passed to sf as --components.
- `-DefinitionFile` (String): Path of a JSON file that describes the app. It must exist. Parameters replace the matching values in it. Passed to sf as --definition-file.
- `-EcaName` (String): Developer name of the External Client App of the app. Passed to sf as --eca-name.
- `-EcaContactEmail` (String): Contact email of the External Client App. Passed to sf as --eca-contact-email.
- `-EcaCallbackUrl` (String): OAuth callback URL of the External Client App. It must be an absolute https:// URL. Passed to sf as --eca-callback-url.
- `-HostDomains` (String[]): HTTP or HTTPS origins of the outside pages that embed the app. Each is passed to sf as its own --host-domains. They replace, not merge with, the host domains in the definition file. Passed to sf as --host-domains.
- `-Runtime` (String): Runtime that serves the app. Valid values: LWR_CORE, CLWR. Passed to sf as --runtime.
- `-OutputDirectory` (String): Folder to save the created files in. It is created if it does not exist. The CLI default is the current folder. Passed to sf as --output-dir.
- `-Force` (switch): Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

#### Salesforce CLI

- `sf template generate lightning-out`

#### Examples

```powershell
PS> New-SalesforceLightningOutApp -AppName StoreWidget -Components storeCart -EcaName StoreWidgetEca -EcaContactEmail dev@example.com -EcaCallbackUrl https://shop.example.com/callback -HostDomains https://shop.example.com -Runtime LWR_CORE -OutputDirectory force-app/main/default
```

Generate the app with every required value given.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceLightningOutApp -Examples"
- For more information, type: "Get-Help New-SalesforceLightningOutApp -Detailed"
- For technical information, type: "Get-Help New-SalesforceLightningOutApp -Full"
- For online help, type: "Get-Help New-SalesforceLightningOutApp -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceLightningTest

#### Synopsis

Creates the static resource of a new Lightning test in the project.

#### Syntax

```powershell
New-SalesforceLightningTest [-Name] <String> [[-Template] <String>] [[-OutputDirectory] <String>] [-Force] [<CommonParameters>]
```

#### Description

Runs sf template generate lightning test. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the Lightning test already exists in the output folder the cmdlet stops, unless you pass -Force.

#### Parameters

- `-Name` (String, required): Name of the Lightning test. Letters, digits and underscores only. Passed to sf as --name. Required.
- `-Template` (String): Template to use. Valid value: DefaultLightningTest, which is also the CLI default. Passed to sf as --template.
- `-OutputDirectory` (String): Folder to save the created files in. It is created if it does not exist. The CLI default is the current folder. Passed to sf as --output-dir.
- `-Force` (switch): Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

#### Salesforce CLI

- `sf template generate lightning test`

#### Examples

```powershell
PS> New-SalesforceLightningTest -Name MyTest -OutputDirectory force-app/main/default/staticresources
```

Generate the Lightning test.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceLightningTest -Examples"
- For more information, type: "Get-Help New-SalesforceLightningTest -Detailed"
- For technical information, type: "Get-Help New-SalesforceLightningTest -Full"
- For online help, type: "Get-Help New-SalesforceLightningTest -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceStaticResource

#### Synopsis

Creates the files of a new static resource in the project.

#### Syntax

```powershell
New-SalesforceStaticResource [-Name] <String> [[-Type] <String>] [[-OutputDirectory] <String>] [-Force] [<CommonParameters>]
```

#### Description

Runs sf template generate static-resource. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. It writes the metadata file and an empty folder for the content. If the static resource already exists in the output folder the cmdlet stops, unless you pass -Force.

#### Parameters

- `-Name` (String, required): Name of the static resource. Letters, digits and underscores only. Passed to sf as --name. Required.
- `-Type` (String): Content (MIME) type of the static resource. The CLI default is application/zip. Passed to sf as --type.
- `-OutputDirectory` (String): Folder to save the created files in. It is created if it does not exist. The CLI default is the current folder. Passed to sf as --output-dir.
- `-Force` (switch): Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

#### Salesforce CLI

- `sf template generate static-resource`

#### Examples

```powershell
PS> New-SalesforceStaticResource -Name Logos -Type application/zip -OutputDirectory force-app/main/default/staticresources
```

Generate a zip static resource.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceStaticResource -Examples"
- For more information, type: "Get-Help New-SalesforceStaticResource -Detailed"
- For technical information, type: "Get-Help New-SalesforceStaticResource -Full"
- For online help, type: "Get-Help New-SalesforceStaticResource -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceUiBundle

#### Synopsis

Creates a UI bundle: the code and metadata of a React, Angular or Vue experience.

#### Syntax

```powershell
New-SalesforceUiBundle [-Name] <String> [[-Label] <String>] [[-Template] <String>] [[-OutputDirectory] <String>] [-Force] [<CommonParameters>]
```

#### Description

Runs sf template generate ui-bundle, which writes a bundle for a UI built with a non-native framework such as React or Angular, under a uiBundles folder in the output folder. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the bundle already exists the cmdlet stops, unless you pass -Force.

#### Parameters

- `-Name` (String, required): Name of the UI bundle. Letters, digits and underscores only. Passed to sf as --name. Required.
- `-Label` (String): Label of the UI bundle. By default the CLI uses the name. Passed to sf as --label.
- `-Template` (String): Template to use. Valid values: default, reactbasic, angularbasic, vuebasic. The CLI default is default. Passed to sf as --template.
- `-OutputDirectory` (String): Folder to save the created files in. It is created if it does not exist. The CLI default is the current folder. Passed to sf as --output-dir.
- `-Force` (switch): Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

#### Salesforce CLI

- `sf template generate ui-bundle`

#### Examples

```powershell
PS> New-SalesforceUiBundle -Name Storefront -Label Storefront -Template reactbasic -OutputDirectory force-app/main/default
```

Generate a React bundle.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceUiBundle -Examples"
- For more information, type: "Get-Help New-SalesforceUiBundle -Detailed"
- For technical information, type: "Get-Help New-SalesforceUiBundle -Full"
- For online help, type: "Get-Help New-SalesforceUiBundle -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceUiEmbedding

#### Synopsis

Creates a Lightning web component that embeds a web page with lightning-ui-embedding.

#### Syntax

```powershell
New-SalesforceUiEmbedding [-Name] <String> [-Src] <String> [-Title] <String> [-Sandbox] <String[]> [[-OutputDirectory] <String>] [-Force] [<CommonParameters>]
```

#### Description

Runs sf template generate ui-embedding, which writes a Lightning web component that wraps the lightning-ui-embedding base component and shows -Src in a sandboxed frame. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. The output folder must be named lwc. If the component already exists the cmdlet stops, unless you pass -Force.

#### Parameters

- `-Name` (String, required): Name of the component. Letters, digits and underscores only. Passed to sf as --name. Required.
- `-Src` (String, required): URL of the page to embed. It must be an absolute https:// URL. Passed to sf as --src. Required.
- `-Title` (String, required): Title of the embedded frame. Passed to sf as --title. Required.
- `-Sandbox` (String[], required): What the embedded page may do: one or more sandbox permissions. Each is passed to sf as its own --sandbox. Valid values: allow-forms, allow-modals, allow-orientation-lock, allow-pointer-lock, allow-popups, allow-popups-to-escape-sandbox, allow-presentation, allow-same-origin, allow-scripts, allow-storage-access-by-user-activation, allow-top-navigation, allow-top-navigation-by-user-activation. Passed to sf as --sandbox. Required.
- `-OutputDirectory` (String): Folder to save the created files in. It must be a folder named lwc, such as force-app/main/default/lwc, or the CLI refuses. The CLI default is the current folder. Passed to sf as --output-dir.
- `-Force` (switch): Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

#### Salesforce CLI

- `sf template generate ui-embedding`

#### Examples

```powershell
PS> New-SalesforceUiEmbedding -Name statusPage -Src https://status.example.com -Title 'Status' -Sandbox allow-scripts, allow-forms -OutputDirectory force-app/main/default/lwc
```

Embed a status page.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceUiEmbedding -Examples"
- For more information, type: "Get-Help New-SalesforceUiEmbedding -Detailed"
- For technical information, type: "Get-Help New-SalesforceUiEmbedding -Full"
- For online help, type: "Get-Help New-SalesforceUiEmbedding -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceVisualforceComponent

#### Synopsis

Creates the files of a new Visualforce component in the project.

#### Syntax

```powershell
New-SalesforceVisualforceComponent [-Name] <String> [-Label] <String> [[-Template] <String>] [[-OutputDirectory] <String>] [-Force] [<CommonParameters>]
```

#### Description

Runs sf template generate visualforce component. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the Visualforce component already exists in the output folder the cmdlet stops, unless you pass -Force.

#### Parameters

- `-Name` (String, required): Name of the Visualforce component. Letters, digits and underscores only. Passed to sf as --name. Required.
- `-Label` (String, required): Label of the Visualforce item, as shown in Setup. Passed to sf as --label. Required.
- `-Template` (String): Template to use. Valid value: DefaultVFComponent, which is also the CLI default. Passed to sf as --template.
- `-OutputDirectory` (String): Folder to save the created files in. It is created if it does not exist. The CLI default is the current folder. Passed to sf as --output-dir.
- `-Force` (switch): Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

#### Salesforce CLI

- `sf template generate visualforce component`

#### Examples

```powershell
PS> New-SalesforceVisualforceComponent -Name MyComponent -Label 'My Component' -OutputDirectory force-app/main/default/components
```

Generate the Visualforce component.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceVisualforceComponent -Examples"
- For more information, type: "Get-Help New-SalesforceVisualforceComponent -Detailed"
- For technical information, type: "Get-Help New-SalesforceVisualforceComponent -Full"
- For online help, type: "Get-Help New-SalesforceVisualforceComponent -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceVisualforcePage

#### Synopsis

Creates the files of a new Visualforce page in the project.

#### Syntax

```powershell
New-SalesforceVisualforcePage [-Name] <String> [-Label] <String> [[-OutputDirectory] <String>] [-Force] [<CommonParameters>]
```

#### Description

Runs sf template generate visualforce page. It writes local files and needs no org; run it inside a Salesforce DX project. It returns the CLI result: outputDir, created (the files it wrote) and rawOutput. If the Visualforce page already exists in the output folder the cmdlet stops, unless you pass -Force.

#### Parameters

- `-Name` (String, required): Name of the Visualforce page. Letters, digits and underscores only. Passed to sf as --name. Required.
- `-Label` (String, required): Label of the Visualforce item, as shown in Setup. Passed to sf as --label. Required.
- `-OutputDirectory` (String): Folder to save the created files in. It is created if it does not exist. The CLI default is the current folder. Passed to sf as --output-dir.
- `-Force` (switch): Generate even if the files already exist. Without it the cmdlet stops when the target is already there, because the CLI replaces any file that differs from the template without asking, and your changes in it would be lost. This switch is not a CLI flag.

#### Salesforce CLI

- `sf template generate visualforce page`

#### Examples

```powershell
PS> New-SalesforceVisualforcePage -Name MyPage -Label 'My Page' -OutputDirectory force-app/main/default/pages
```

Generate the Visualforce page.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceVisualforcePage -Examples"
- For more information, type: "Get-Help New-SalesforceVisualforcePage -Detailed"
- For technical information, type: "Get-Help New-SalesforceVisualforcePage -Full"
- For online help, type: "Get-Help New-SalesforceVisualforcePage -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-templates>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>
