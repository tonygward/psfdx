# psfdx-plugins command reference

Generated from the commands' own help by `site/Update-ModuleReference.ps1`: do not edit it by hand. The same reference is on the website: <https://psfdx.com/modules/psfdx-plugins/>. It is part of the `psfdx` package; see the [installation guide](https://github.com/tonygward/psfdx/blob/main/docs/install.md).

11 commands. Every command also takes the common parameters, such as `-Verbose`.

## Commands

[Add-SalesforcePluginAllowlist](#add-salesforcepluginallowlist), [Find-SalesforcePlugins](#find-salesforceplugins), [Get-SalesforcePluginAllowlist](#get-salesforcepluginallowlist), [Get-SalesforcePluginDetails](#get-salesforceplugindetails), [Get-SalesforcePlugins](#get-salesforceplugins), [Install-SalesforcePlugin](#install-salesforceplugin), [Remove-SalesforcePluginAllowlist](#remove-salesforcepluginallowlist), [Reset-SalesforcePlugins](#reset-salesforceplugins), [Test-SalesforcePluginSignature](#test-salesforcepluginsignature), [Uninstall-SalesforcePlugin](#uninstall-salesforceplugin), [Update-SalesforcePlugins](#update-salesforceplugins)

### Add-SalesforcePluginAllowlist

#### Synopsis

Allows plugins that Salesforce has not signed to be installed.

#### Syntax

```powershell
Add-SalesforcePluginAllowlist [-Name] <String[]> [-NoPrompt] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf plugins trust allowlist add. This lowers a safety check of the CLI: a plugin on the allowlist installs without a Salesforce signature, so only add a plugin whose code you trust. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. The CLI command has no prompt of its own.

#### Parameters

- `-Name` (String[], required): Plugins to allow, as npm package names. Each is passed to sf as its own --name. Passed to sf as --name. Required.
- `-NoPrompt` (switch): Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf plugins trust allowlist add`

#### Examples

```powershell
PS> Add-SalesforcePluginAllowlist -Name my-company-plugin -WhatIf
```

Preview allowing a plugin.

#### Remarks

- To see the examples, type: "Get-Help Add-SalesforcePluginAllowlist -Examples"
- For more information, type: "Get-Help Add-SalesforcePluginAllowlist -Detailed"
- For technical information, type: "Get-Help Add-SalesforcePluginAllowlist -Full"
- For online help, type: "Get-Help Add-SalesforcePluginAllowlist -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-trust>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Find-SalesforcePlugins

#### Synopsis

Lists third-party plugins you can install.

#### Syntax

```powershell
Find-SalesforcePlugins [<CommonParameters>]
```

#### Description

Runs sf plugins discover and returns the third-party plugins that Salesforce lists. It reads a list on the internet and changes nothing. Install one with Install-SalesforcePlugin.

#### Salesforce CLI

- `sf plugins discover`

#### Examples

```powershell
PS> Find-SalesforcePlugins
```

The plugins you can add.

#### Remarks

- To see the examples, type: "Get-Help Find-SalesforcePlugins -Examples"
- For more information, type: "Get-Help Find-SalesforcePlugins -Detailed"
- For technical information, type: "Get-Help Find-SalesforcePlugins -Full"
- For online help, type: "Get-Help Find-SalesforcePlugins -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-marketplace>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforcePluginAllowlist

#### Synopsis

Lists the plugins the CLI is allowed to install without a Salesforce signature.

#### Syntax

```powershell
Get-SalesforcePluginAllowlist [<CommonParameters>]
```

#### Description

Runs sf plugins trust allowlist list. Plugins on the allowlist can be installed even though they are not signed by Salesforce. It only reads.

#### Salesforce CLI

- `sf plugins trust allowlist list`

#### Examples

```powershell
PS> Get-SalesforcePluginAllowlist
```

The allowed unsigned plugins.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePluginAllowlist -Examples"
- For more information, type: "Get-Help Get-SalesforcePluginAllowlist -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePluginAllowlist -Full"
- For online help, type: "Get-Help Get-SalesforcePluginAllowlist -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-trust>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforcePluginDetails

#### Synopsis

Shows the installation details of plugins.

#### Syntax

```powershell
Get-SalesforcePluginDetails [-Name] <String[]> [-ExtendedDetails] [<CommonParameters>]
```

#### Description

Runs sf plugins inspect for each plugin and returns what the CLI knows about it, such as its version and where it is installed. It only reads. For the list of installed plugins see Get-SalesforcePlugins.

#### Parameters

- `-Name` (String[], required): Plugins to inspect, as npm package names such as @salesforce/plugin-agent. Required.
- `-ExtendedDetails` (switch): Show more detail. Adds --verbose.

#### Salesforce CLI

- `sf plugins inspect`

#### Examples

```powershell
PS> Get-SalesforcePluginDetails -Name @salesforce/plugin-agent
```

Version and location of one plugin.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePluginDetails -Examples"
- For more information, type: "Get-Help Get-SalesforcePluginDetails -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePluginDetails -Full"
- For online help, type: "Get-Help Get-SalesforcePluginDetails -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/@oclif/plugin-plugins>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforcePlugins

#### Synopsis

Lists the Salesforce CLI plugins that are installed.

#### Syntax

```powershell
Get-SalesforcePlugins [-IncludeCore] [<CommonParameters>]
```

#### Description

Runs sf plugins and returns the CLI's own text output, one plugin per line. Add -IncludeCore to include the plugins that ship with the CLI.

#### Parameters

- `-IncludeCore` (switch): Also list the plugins that ship with the Salesforce CLI. Adds --core.

#### Salesforce CLI

- `sf plugins`

#### Examples

```powershell
PS> Get-SalesforcePlugins -IncludeCore
```

Every plugin, including the bundled ones.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePlugins -Examples"
- For more information, type: "Get-Help Get-SalesforcePlugins -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePlugins -Full"
- For online help, type: "Get-Help Get-SalesforcePlugins -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/oclif/plugin-plugins>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Install-SalesforcePlugin

#### Synopsis

Installs a Salesforce CLI plugin (sf plugins install).

#### Syntax

```powershell
Install-SalesforcePlugin [-Name] <String> [-Force] [-Silent] [-ExtendedDetails] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

A plugin is code that runs with your permissions, so install only plugins you trust: the CLI may ask you to confirm one that is not on its allow list. -Name is an npm package name (optionally scoped and with a version, such as @salesforce/plugin-agent@latest) or a GitHub URL. A value that starts with a dash or contains spaces or control characters is refused, so it cannot be read as a CLI option. Supports -WhatIf and -Confirm.

#### Parameters

- `-Name` (String, required): The plugin to install: an npm package name such as @salesforce/plugin-agent, optionally with a version, or a GitHub URL. A value that starts with a dash or contains spaces or control characters is refused, so it cannot be read as a CLI option. Required.
- `-Force` (switch): Make npm fetch the plugin again even if a copy is already on disk. Adds --force.
- `-Silent` (switch): Silence the output of npm. Adds --silent.
- `-ExtendedDetails` (switch): Show the verbose output of npm. Adds --verbose.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf plugins install`

#### Examples

```powershell
PS> Install-SalesforcePlugin -Name @salesforce/plugin-agent -WhatIf
```

#### Remarks

- To see the examples, type: "Get-Help Install-SalesforcePlugin -Examples"
- For more information, type: "Get-Help Install-SalesforcePlugin -Detailed"
- For technical information, type: "Get-Help Install-SalesforcePlugin -Full"
- For online help, type: "Get-Help Install-SalesforcePlugin -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/oclif/plugin-plugins>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforcePluginAllowlist

#### Synopsis

Takes plugins off the allowlist of unsigned plugins.

#### Syntax

```powershell
Remove-SalesforcePluginAllowlist [-Name] <String[]> [-NoPrompt] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf plugins trust allowlist remove. The plugins can no longer be installed without a Salesforce signature. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. The CLI command has no prompt of its own.

#### Parameters

- `-Name` (String[], required): Plugins to remove from the allowlist. Each is passed to sf as its own --name. Passed to sf as --name. Required.
- `-NoPrompt` (switch): Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf plugins trust allowlist remove`

#### Examples

```powershell
PS> Remove-SalesforcePluginAllowlist -Name my-company-plugin -WhatIf
```

Preview taking a plugin off the list.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforcePluginAllowlist -Examples"
- For more information, type: "Get-Help Remove-SalesforcePluginAllowlist -Detailed"
- For technical information, type: "Get-Help Remove-SalesforcePluginAllowlist -Full"
- For online help, type: "Get-Help Remove-SalesforcePluginAllowlist -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-trust>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Reset-SalesforcePlugins

#### Synopsis

Removes every plugin you installed or linked in the Salesforce CLI.

#### Syntax

```powershell
Reset-SalesforcePlugins [-Hard] [-Reinstall] [-NoPrompt] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf plugins reset. All user-installed and linked plugins are uninstalled, so commands that came from them stop working until you install them again (or use -Reinstall). Plugins that ship with the CLI stay. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. The CLI command has no prompt of its own.

#### Parameters

- `-Hard` (switch): Also delete node_modules and the package manager files, not only uninstall the plugins. Adds --hard.
- `-Reinstall` (switch): Install all the plugins again after removing them. Adds --reinstall.
- `-NoPrompt` (switch): Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf plugins reset`

#### Examples

```powershell
PS> Reset-SalesforcePlugins -Reinstall -WhatIf
```

Preview a clean reinstall of the plugins.

#### Remarks

- To see the examples, type: "Get-Help Reset-SalesforcePlugins -Examples"
- For more information, type: "Get-Help Reset-SalesforcePlugins -Detailed"
- For technical information, type: "Get-Help Reset-SalesforcePlugins -Full"
- For online help, type: "Get-Help Reset-SalesforcePlugins -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/@oclif/plugin-plugins>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Test-SalesforcePluginSignature

#### Synopsis

Checks the digital signature of an npm plugin package.

#### Syntax

```powershell
Test-SalesforcePluginSignature [-Npm] <String> [[-Registry] <String>] [<CommonParameters>]
```

#### Description

Runs sf plugins trust verify, which checks that the signature of the npm package matches the signature and key stored at the URLs the CLI expects. It tells you whether the plugin is signed by Salesforce before you install it. It only reads.

#### Parameters

- `-Npm` (String, required): The npm package name, which can include a tag or version, for example @salesforce/plugin-agent@latest. Passed to sf as --npm. Required.
- `-Registry` (String): The npm registry to use. It must be an absolute https:// URL. The CLI default is the registry npm uses. Passed to sf as --registry.

#### Salesforce CLI

- `sf plugins trust verify`

#### Examples

```powershell
PS> Test-SalesforcePluginSignature -Npm @salesforce/plugin-agent
PS> Is the package signed?
```

#### Remarks

- To see the examples, type: "Get-Help Test-SalesforcePluginSignature -Examples"
- For more information, type: "Get-Help Test-SalesforcePluginSignature -Detailed"
- For technical information, type: "Get-Help Test-SalesforcePluginSignature -Full"
- For online help, type: "Get-Help Test-SalesforcePluginSignature -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-trust>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Uninstall-SalesforcePlugin

#### Synopsis

Removes plugins from the Salesforce CLI.

#### Syntax

```powershell
Uninstall-SalesforcePlugin [-Name] <String[]> [-ExtendedDetails] [-NoPrompt] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf plugins uninstall for each name. Commands the plugin provided stop working, and psfdx cmdlets that need it (for example the agent cmdlets need @salesforce/plugin-agent) will say it is missing. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. The CLI command has no prompt of its own.

#### Parameters

- `-Name` (String[], required): Plugins to remove, as npm package names such as @salesforce/plugin-agent. Each must be a plain name: it must not start with a dash or contain spaces. Required.
- `-ExtendedDetails` (switch): Show more detail of what the CLI does. Adds --verbose.
- `-NoPrompt` (switch): Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf plugins uninstall`

#### Examples

```powershell
PS> Uninstall-SalesforcePlugin -Name @salesforce/plugin-agent -WhatIf
```

Preview removing a plugin.

#### Remarks

- To see the examples, type: "Get-Help Uninstall-SalesforcePlugin -Examples"
- For more information, type: "Get-Help Uninstall-SalesforcePlugin -Detailed"
- For technical information, type: "Get-Help Uninstall-SalesforcePlugin -Full"
- For online help, type: "Get-Help Uninstall-SalesforcePlugin -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/@oclif/plugin-plugins>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Update-SalesforcePlugins

#### Synopsis

Updates the installed Salesforce CLI plugins.

#### Syntax

```powershell
Update-SalesforcePlugins [-ExtendedDetails] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf plugins update. Supports -WhatIf and -Confirm.

#### Parameters

- `-ExtendedDetails` (switch): Show the verbose output of the update. Adds --verbose.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf plugins update`

#### Examples

```powershell
PS> Update-SalesforcePlugins -WhatIf
```

Show what would be updated.

#### Remarks

- To see the examples, type: "Get-Help Update-SalesforcePlugins -Examples"
- For more information, type: "Get-Help Update-SalesforcePlugins -Detailed"
- For technical information, type: "Get-Help Update-SalesforcePlugins -Full"
- For online help, type: "Get-Help Update-SalesforcePlugins -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/oclif/plugin-plugins>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>
