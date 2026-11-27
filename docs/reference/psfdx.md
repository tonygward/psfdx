# psfdx command reference

Generated from the commands' own help by `site/Update-ModuleReference.ps1`: do not edit it by hand. The same reference is on the website: <https://psfdx.com/modules/psfdx/>. It is part of the `psfdx` package; see the [installation guide](https://github.com/tonygward/psfdx/blob/main/docs/install.md).

39 commands. Every command also takes the common parameters, such as `-Verbose`.

## Commands

**Authentication and aliases**: [Add-SalesforceAlias](#add-salesforcealias), [Connect-Salesforce](#connect-salesforce), [Connect-SalesforceAccessToken](#connect-salesforceaccesstoken), [Connect-SalesforceApi](#connect-salesforceapi), [Connect-SalesforceAuthUrl](#connect-salesforceauthurl), [Connect-SalesforceJwt](#connect-salesforcejwt), [Disconnect-Salesforce](#disconnect-salesforce), [Get-SalesforceAlias](#get-salesforcealias), [Get-SalesforceAuthenticatedUser](#get-salesforceauthenticateduser), [Get-SalesforceAuthorizations](#get-salesforceauthorizations), [Get-SalesforceConnections](#get-salesforceconnections), [Open-Salesforce](#open-salesforce), [Remove-SalesforceAlias](#remove-salesforcealias), [Repair-SalesforceConnections](#repair-salesforceconnections)

**SOQL helpers**: [ConvertTo-SalesforceSoqlDateTime](#convertto-salesforcesoqldatetime), [ConvertTo-SalesforceSoqlIdentifier](#convertto-salesforcesoqlidentifier), [ConvertTo-SalesforceSoqlLiteral](#convertto-salesforcesoqlliteral)

**APIs**: [Get-SalesforceApiUsage](#get-salesforceapiusage), [Get-SalesforceApiVersions](#get-salesforceapiversions), [Get-SalesforceLatestApiVersion](#get-salesforcelatestapiversion), [Invoke-SalesforceApi](#invoke-salesforceapi), [Invoke-SalesforceGraphQL](#invoke-salesforcegraphql), [Invoke-SalesforceRestRequest](#invoke-salesforcerestrequest)

**Experience Cloud**: [Get-SalesforceCommunityTemplates](#get-salesforcecommunitytemplates), [New-SalesforceCommunity](#new-salesforcecommunity), [Publish-SalesforceCommunity](#publish-salesforcecommunity)

**Tools and org information**: [Get-SalesforceDataStorage](#get-salesforcedatastorage), [Get-SalesforceDateTime](#get-salesforcedatetime), [Get-SalesforceLimits](#get-salesforcelimits), [Get-SalesforceOrgDetails](#get-salesforceorgdetails), [Install-SalesforceCli](#install-salesforcecli), [Invoke-SalesforceDoctor](#invoke-salesforcedoctor), [Update-SalesforceCli](#update-salesforcecli)

**Users and permissions**: [Get-SalesforceOrgUser](#get-salesforceorguser), [Get-SalesforceUsers](#get-salesforceusers), [Grant-SalesforcePermissionSet](#grant-salesforcepermissionset), [Grant-SalesforcePermissionSetLicense](#grant-salesforcepermissionsetlicense), [New-SalesforceUser](#new-salesforceuser), [New-SalesforceUserPassword](#new-salesforceuserpassword)

## Authentication and aliases

### Add-SalesforceAlias

#### Synopsis

Sets a local alias for an org so you can use a short name instead of its username.

#### Syntax

```powershell
Add-SalesforceAlias [-Alias] <String> [-TargetOrg] <String> [<CommonParameters>]
```

#### Description

Stores the alias in the Salesforce CLI configuration on this computer; nothing changes in the org. Once set, the alias works anywhere a psfdx cmdlet takes -TargetOrg.

#### Parameters

- `-Alias` (String, required): The alias to create, for example prod or dev1. Setting an alias that already exists replaces it. Required.
- `-TargetOrg` (String, required): Username, or an existing alias, that the new alias should point to. Required.

#### Salesforce CLI

- `sf alias set`

#### Examples

```powershell
PS> Add-SalesforceAlias -Alias dev1 -TargetOrg user@example.com.dev1
```

Create the alias dev1 for that username.

#### Remarks

- To see the examples, type: "Get-Help Add-SalesforceAlias -Examples"
- For more information, type: "Get-Help Add-SalesforceAlias -Detailed"
- For technical information, type: "Get-Help Add-SalesforceAlias -Full"
- For online help, type: "Get-Help Add-SalesforceAlias -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-settings>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Connect-Salesforce

#### Synopsis

Logs in to an org in a web browser and saves the authorization.

#### Syntax

```powershell
Connect-Salesforce [-Sandbox] [[-CustomUrl] <String>] [[-Alias] <String>] [-SetDefault] [-SetDefaultDevHub] [[-Browser] <String>] [[-OAuthClientId] <String>] [[-ClientApp] <String>] [[-Scopes] <String>] [[-Username] <String>] [<CommonParameters>]
```

#### Description

Opens the login page of Salesforce in your browser. After you sign in, the Salesforce CLI stores the authorization on this computer so other psfdx cmdlets can use the org. Use -Sandbox for a sandbox, or -CustomUrl for a My Domain or other login URL.

#### Parameters

- `-Sandbox` (switch): Log in through the sandbox login host. psfdx passes --instance-url https://test.salesforce.com. Use -CustomUrl instead for a different host.
- `-CustomUrl` (String): URL of the instance that the org lives on. Passed to sf as --instance-url.
- `-Alias` (String): Alias for the org. Passed to sf as --alias.
- `-SetDefault` (switch): Set the authenticated org as the default that all org-related commands run against. Adds --set-default.
- `-SetDefaultDevHub` (switch): Set the authenticated org as the default Dev Hub. Adds --set-default-dev-hub.
- `-Browser` (String): Browser in which to open the org. Passed to sf as --browser. Valid values: chrome, edge, firefox.
- `-OAuthClientId` (String): OAuth client ID (also called consumer key) of your custom connected app. Passed to sf as --client-id.
- `-ClientApp` (String): Name that saves this login as a separate authorization for the same user, so you can log in to one org with more than one connected app. Passed to sf as --client-app. Use the same name with Disconnect-Salesforce -ClientApp to log it out.
- `-Scopes` (String): OAuth scopes to request, separated by spaces, for example "api web refresh_token". Passed to sf as --scopes. Use it with your own connected app (-OAuthClientId).
- `-Username` (String): User name to log in as, which pre-fills the login page. Passed to sf as --username.

#### Salesforce CLI

- `sf org login web`

#### Examples

```powershell
PS> Connect-Salesforce -Alias prod -SetDefault
```

Log in to production, give the org the alias prod and make it the default target org.

#### Remarks

- To see the examples, type: "Get-Help Connect-Salesforce -Examples"
- For more information, type: "Get-Help Connect-Salesforce -Detailed"
- For technical information, type: "Get-Help Connect-Salesforce -Full"
- For online help, type: "Get-Help Connect-Salesforce -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-auth>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Connect-SalesforceAccessToken

#### Synopsis

Logs in to an org with an access token you already have.

#### Syntax

```powershell
Connect-SalesforceAccessToken [-InstanceUrl] <String> [-AccessToken] <SecureString> [[-Alias] <String>] [-SetDefault] [-SetDefaultDevHub] [-NoPrompt] [<CommonParameters>]
```

#### Description

Runs sf org login access-token. Give the org's instance URL and the access token as a SecureString. The token is handed to the CLI in the SF_ACCESS_TOKEN environment variable of the sf process only, never on the command line, and the variable is put back to its earlier value afterwards. The login is saved on this computer so other psfdx cmdlets can use the org. The authorization cannot be refreshed, so it stops working when the token expires. Because the environment belongs to the whole process, logins started at the same time in one PowerShell process run one after the other. The URL must be an absolute https URL, because the token is sent to it. Tokens and authorization URLs are removed from the result.

#### Parameters

- `-InstanceUrl` (String, required): URL of the org, for example https://mycompany.my.salesforce.com. Must be an absolute https:// URL. Passed to sf as --instance-url. Required.
- `-AccessToken` (SecureString, required): The access token, as a SecureString, for example (Read-Host -AsSecureString). Passed to sf in the SF_ACCESS_TOKEN environment variable. Required.
- `-Alias` (String): Alias for the org. Passed to sf as --alias.
- `-SetDefault` (switch): Set the authenticated org as the default that all org-related commands run against. Adds --set-default.
- `-SetDefaultDevHub` (switch): Set the authenticated org as the default Dev Hub. Adds --set-default-dev-hub.
- `-NoPrompt` (switch): Don't prompt for confirmation, for example before overwriting an existing login. Adds --no-prompt.

#### Salesforce CLI

- `sf org login access-token`

#### Examples

```powershell
PS> Connect-SalesforceAccessToken -InstanceUrl https://mycompany.my.salesforce.com -AccessToken (Read-Host -AsSecureString) -Alias ci -NoPrompt
```

Log in with a token that you type at the prompt.

#### Remarks

- To see the examples, type: "Get-Help Connect-SalesforceAccessToken -Examples"
- For more information, type: "Get-Help Connect-SalesforceAccessToken -Detailed"
- For technical information, type: "Get-Help Connect-SalesforceAccessToken -Full"
- For online help, type: "Get-Help Connect-SalesforceAccessToken -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-auth>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Connect-SalesforceApi

#### Synopsis

Gets an access token for the Salesforce REST API with the username-password OAuth flow.

#### Syntax

```powershell
Connect-SalesforceApi [-TargetOrg] <String> [-Password] <Object> [-Token] <Object> [-ClientId] <String> [-ClientSecret] <Object> [-Sandbox] [[-CustomUrl] <String>] [<CommonParameters>]
```

#### Description

Does not use the Salesforce CLI. It posts the user name, the password plus security token, and the connected app client ID and secret to the org's /services/oauth2/token endpoint with Invoke-RestMethod and returns the response, which holds the access token and instance URL. The request is sent only over https. Pass the password, token and client secret as SecureString: they are converted to text only when the request is built and are never written to the verbose, debug or error output. Plain strings still work but write a warning, because they stay in your session history and memory.

#### Parameters

- `-TargetOrg` (String, required): The Salesforce user name to log in as (sent as the OAuth username). This is not an org alias. Required.
- `-Password` (Object, required): The user's password, as a SecureString (preferred) or a plain string (deprecated, writes a warning). The security token is appended to it. Required.
- `-Token` (Object, required): The user's security token, as a SecureString (preferred) or a plain string (deprecated, writes a warning). Appended to the password. Required.
- `-ClientId` (String, required): Consumer key of the connected app used for the login. Required.
- `-ClientSecret` (Object, required): Consumer secret of the connected app, as a SecureString (preferred) or a plain string (deprecated, writes a warning). Required.
- `-Sandbox` (switch): Use the sandbox login host https://test.salesforce.com instead of https://login.salesforce.com.
- `-CustomUrl` (String): Base URL of the login host to use instead, for example a My Domain. It must be an absolute https:// URL, otherwise the cmdlet stops before sending anything.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Connect-SalesforceApi -TargetOrg user@example.com -Password $pw -Token $tok -ClientId $key -ClientSecret $secret
```

Request an access token from production.

#### Remarks

- To see the examples, type: "Get-Help Connect-SalesforceApi -Examples"
- For more information, type: "Get-Help Connect-SalesforceApi -Detailed"
- For technical information, type: "Get-Help Connect-SalesforceApi -Full"
- For online help, type: "Get-Help Connect-SalesforceApi -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Connect-SalesforceAuthUrl

#### Synopsis

Logs in to an org with a Salesforce DX authorization URL stored in a file.

#### Syntax

```powershell
Connect-SalesforceAuthUrl [-SfdxUrlFile] <String> [[-Alias] <String>] [-SetDefault] [-SetDefaultDevHub] [-IncludeToken] [<CommonParameters>]
```

#### Description

Runs sf org login sfdx-url with the file you give. The result has the access token and auth URL removed unless you pass -IncludeToken. Keep the file safe: anyone who has it can log in as that user.

#### Parameters

- `-SfdxUrlFile` (String, required): Path to a file that contains the Salesforce DX authorization URL. Passed to sf as --sfdx-url-file. Required.
- `-Alias` (String): Alias for the org. Passed to sf as --alias.
- `-SetDefault` (switch): Set the authenticated org as the default that all org-related commands run against. Adds --set-default.
- `-SetDefaultDevHub` (switch): Set the authenticated org as the default Dev Hub. Adds --set-default-dev-hub.
- `-IncludeToken` (switch): Return the CLI result as it is. Current CLI versions do not return tokens or auth URLs for this command, so this may change nothing. Without it psfdx removes accessToken, refreshToken, sfdxAuthUrl, password, clientSecret and privateKey from the result.

#### Salesforce CLI

- `sf org login sfdx-url`

#### Examples

```powershell
PS> Connect-SalesforceAuthUrl -SfdxUrlFile .\auth.txt -Alias ci -SetDefault
```

Log in from the file and make the org the default.

#### Remarks

- To see the examples, type: "Get-Help Connect-SalesforceAuthUrl -Examples"
- For more information, type: "Get-Help Connect-SalesforceAuthUrl -Detailed"
- For technical information, type: "Get-Help Connect-SalesforceAuthUrl -Full"
- For online help, type: "Get-Help Connect-SalesforceAuthUrl -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-auth>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Connect-SalesforceJwt

#### Synopsis

Logs in to an org without a browser, using a JSON web token and a private key.

#### Syntax

```powershell
Connect-SalesforceJwt [-ConsumerKey] <String> [-TargetOrg] <String> [-JwtKeyfile] <String> [-Sandbox] [[-Alias] <String>] [-SetDefault] [-SetDefaultDevHub] [<CommonParameters>]
```

#### Description

Runs sf org login jwt with the connected app's consumer key, the user name and the private key file. It is meant for CI. The key file must exist; its content is never read or printed by psfdx. The login host is https://login.salesforce.com, or https://test.salesforce.com with -Sandbox.

#### Parameters

- `-ConsumerKey` (String, required): OAuth client ID (also called consumer key) of your custom connected app. Passed to sf as --client-id. Required.
- `-TargetOrg` (String, required): Username of the user logging in. Passed to sf as --username. Required.
- `-JwtKeyfile` (String, required): Path to a file containing the private key. Passed to sf as --jwt-key-file. Required.
- `-Sandbox` (switch): Log in at https://test.salesforce.com. psfdx always passes --instance-url: production by default, the sandbox host with this switch.
- `-Alias` (String): Alias for the org. Passed to sf as --alias.
- `-SetDefault` (switch): Set the authenticated org as the default that all org-related commands run against. Adds --set-default.
- `-SetDefaultDevHub` (switch): Set the authenticated org as the default Dev Hub. Adds --set-default-dev-hub.

#### Salesforce CLI

- `sf org login jwt`

#### Examples

```powershell
PS> Connect-SalesforceJwt -ConsumerKey $key -TargetOrg ci@example.com -JwtKeyfile .\server.key -Alias ci -SetDefault
```

Log in a CI user and make it the default target org.

#### Remarks

- To see the examples, type: "Get-Help Connect-SalesforceJwt -Examples"
- For more information, type: "Get-Help Connect-SalesforceJwt -Detailed"
- For technical information, type: "Get-Help Connect-SalesforceJwt -Full"
- For online help, type: "Get-Help Connect-SalesforceJwt -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-auth>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Disconnect-Salesforce

#### Synopsis

Logs out of one org, or all orgs, and removes the saved authorization.

#### Syntax

```powershell
Disconnect-Salesforce -TargetOrg <String> [-ClientApp <String>] [-NoPrompt] [-WhatIf] [-Confirm] [<CommonParameters>]
Disconnect-Salesforce -All [-NoPrompt] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf org logout. The authorization is removed from this computer; scratch orgs and sandboxes are not deleted. Asks for confirmation and supports -WhatIf.

#### Parameters

- `-All` (switch, required): Log out of every org this computer is authorized for. Use it instead of -TargetOrg. Required in the All parameter set.
- `-TargetOrg` (String, required): Username or alias of the target org. Passed to sf as --target-org. Required in the TargetOrg parameter set.
- `-ClientApp` (String): Name of the client app login to log out of, the name given to Connect-Salesforce -ClientApp. Passed to sf as --client-app. Use it with -TargetOrg.
- `-NoPrompt` (switch): Don't prompt for confirmation. Adds --no-prompt.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org logout`

#### Examples

```powershell
PS> Disconnect-Salesforce -TargetOrg dev1 -WhatIf
```

Show what would happen without logging out.

#### Remarks

- To see the examples, type: "Get-Help Disconnect-Salesforce -Examples"
- For more information, type: "Get-Help Disconnect-Salesforce -Detailed"
- For technical information, type: "Get-Help Disconnect-Salesforce -Full"
- For online help, type: "Get-Help Disconnect-Salesforce -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-auth>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceAlias

#### Synopsis

Lists the org aliases set on this computer.

#### Syntax

```powershell
Get-SalesforceAlias [<CommonParameters>]
```

#### Description

Runs sf alias list and returns the aliases, each with the value it points to. Reads local CLI configuration only; it does not contact an org.

#### Salesforce CLI

- `sf alias list`

#### Examples

```powershell
PS> Get-SalesforceAlias
```

List every alias.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceAlias -Examples"
- For more information, type: "Get-Help Get-SalesforceAlias -Detailed"
- For technical information, type: "Get-Help Get-SalesforceAlias -Full"
- For online help, type: "Get-Help Get-SalesforceAlias -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-settings>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceAuthenticatedUser

#### Synopsis

Lists the users of an org that the Salesforce CLI has authorised on this computer (sf org list users).

#### Syntax

```powershell
Get-SalesforceAuthenticatedUser [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Tokens are removed from the result. To search all users in the org, use Get-SalesforceUsers.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf org list users`

#### Examples

```powershell
PS> Get-SalesforceAuthenticatedUser -TargetOrg myscratch
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceAuthenticatedUser -Examples"
- For more information, type: "Get-Help Get-SalesforceAuthenticatedUser -Detailed"
- For technical information, type: "Get-Help Get-SalesforceAuthenticatedUser -Full"
- For online help, type: "Get-Help Get-SalesforceAuthenticatedUser -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-user>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceAuthorizations

#### Synopsis

Lists every authorization the Salesforce CLI has saved on this computer.

#### Syntax

```powershell
Get-SalesforceAuthorizations [<CommonParameters>]
```

#### Description

Runs sf org list auth and returns one object per saved authorization (user name, org ID, instance URL, aliases, how it was authorized and whether it has expired). Unlike Get-SalesforceConnections it does not contact the orgs, so it is quick and works offline. Tokens and authorization URLs are removed from the result.

#### Salesforce CLI

- `sf org list auth`

#### Examples

```powershell
PS> Get-SalesforceAuthorizations | Format-Table username, aliases, instanceUrl
PS> A quick overview of the saved logins.
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceAuthorizations -Examples"
- For more information, type: "Get-Help Get-SalesforceAuthorizations -Detailed"
- For technical information, type: "Get-Help Get-SalesforceAuthorizations -Full"
- For online help, type: "Get-Help Get-SalesforceAuthorizations -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-auth>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceConnections

#### Synopsis

Lists the orgs this computer is logged in to.

#### Syntax

```powershell
Get-SalesforceConnections [-ShowVerboseDetails] [<CommonParameters>]
```

#### Description

Runs sf org list and returns one object per org (orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias). Scratch orgs are not included here; use Get-SalesforceScratchOrgs for those.

#### Parameters

- `-ShowVerboseDetails` (switch): List more information about each org. Adds --verbose.

#### Salesforce CLI

- `sf org list`

#### Examples

```powershell
PS> Get-SalesforceConnections | Format-Table username, alias, connectedStatus
PS> A quick overview of connected orgs.
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceConnections -Examples"
- For more information, type: "Get-Help Get-SalesforceConnections -Detailed"
- For technical information, type: "Get-Help Get-SalesforceConnections -Full"
- For online help, type: "Get-Help Get-SalesforceConnections -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Open-Salesforce

#### Synopsis

Opens an org in your browser, or prints its login URL.

#### Syntax

```powershell
Open-Salesforce [[-TargetOrg] <String>] [-UrlOnly] [[-Browser] <String>] [-BrowserPrivateMode] [[-Path] <String>] [[-SourceFile] <String>] [<CommonParameters>]
```

#### Description

Runs sf org open. The URL contains a session token, so treat it like a password; -UrlOnly prints it instead of opening a browser.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-UrlOnly` (switch): Display navigation URL, but don't launch browser. Adds --url-only.
- `-Browser` (String): Browser where the org opens. Passed to sf as --browser. Valid values: chrome, edge, firefox.
- `-BrowserPrivateMode` (switch): Open the org in the browser's private (incognito) mode. A switch: adds --private, which takes no value.
- `-Path` (String): Page to open, relative to the org, for example /lightning/setup/SetupOneHome/home. Passed to sf as --path.
- `-SourceFile` (String): Path of a local file in the project. The CLI opens that component in the org, for example a Lightning page in the builder or an Apex class in the viewer. Passed to sf as --source-file. The file must exist.

#### Salesforce CLI

- `sf org open`

#### Examples

```powershell
PS> Open-Salesforce -TargetOrg dev1
```

Open the org in the default browser.

#### Remarks

- To see the examples, type: "Get-Help Open-Salesforce -Examples"
- For more information, type: "Get-Help Open-Salesforce -Detailed"
- For technical information, type: "Get-Help Open-Salesforce -Full"
- For online help, type: "Get-Help Open-Salesforce -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceAlias

#### Synopsis

Removes one org alias, or all of them, from this computer.

#### Syntax

```powershell
Remove-SalesforceAlias [[-Alias] <String>] [-All] [-NoPrompt] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf alias unset. Only the local aliases are removed; the orgs are not touched. Give -Alias to remove one, or -All to remove every alias, which asks for confirmation first because it cannot be undone. Supports -WhatIf. -NoPrompt skips the question so a script can run unattended; psfdx always passes --no-prompt to the CLI itself after it has asked, so the CLI never waits for an answer.

#### Parameters

- `-Alias` (String): The alias to remove. Required unless -All is given.
- `-All` (switch): Remove all the aliases that are set. Cannot be used with -Alias. Adds --all.
- `-NoPrompt` (switch): Do not ask for confirmation when removing all the aliases. Adds --no-prompt.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf alias unset`

#### Examples

```powershell
PS> Remove-SalesforceAlias -Alias dev1
```

Remove the alias dev1.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceAlias -Examples"
- For more information, type: "Get-Help Remove-SalesforceAlias -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceAlias -Full"
- For online help, type: "Get-Help Remove-SalesforceAlias -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-settings>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Repair-SalesforceConnections

#### Synopsis

Removes expired and deleted orgs from the list of connections.

#### Syntax

```powershell
Repair-SalesforceConnections [-NoPrompt] [<CommonParameters>]
```

#### Description

Runs sf org list --clean, which checks every org and offers to remove the ones that no longer exist or whose scratch org has expired. Without -NoPrompt the CLI asks first. It returns the CLI's text output.

#### Parameters

- `-NoPrompt` (switch): Don't prompt for confirmation. Adds --no-prompt.

#### Salesforce CLI

- `sf org list`

#### Examples

```powershell
PS> Repair-SalesforceConnections
```

Interactive clean-up.

#### Remarks

- To see the examples, type: "Get-Help Repair-SalesforceConnections -Examples"
- For more information, type: "Get-Help Repair-SalesforceConnections -Detailed"
- For technical information, type: "Get-Help Repair-SalesforceConnections -Full"
- For online help, type: "Get-Help Repair-SalesforceConnections -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## SOQL helpers

### ConvertTo-SalesforceSoqlDateTime

#### Synopsis

Formats a DateTime as a SOQL datetime literal in UTC, for example 2026-11-18T11:00:00Z.

#### Syntax

```powershell
ConvertTo-SalesforceSoqlDateTime [-Value] <DateTime> [[-TimeZone] <TimeZoneInfo>] [<CommonParameters>]
```

#### Description

Formats a DateTime as a SOQL datetime literal in UTC, for example 2026-11-18T11:00:00Z. It is not quoted.

The value is converted to UTC before the Z is written, so the literal is the same instant whatever the machine's time zone: Kind Utc used as it is Kind Local converted from the machine's local time zone, including daylight saving time Kind Unspecified treated as local time, the same as .NET's ToUniversalTime() does. A date parsed from text such as '2026-11-18 12:00' is Unspecified, so it means 12:00 where you are. -TimeZone names the zone to read a Local or Unspecified value in instead of the machine's. A time that does not exist in that zone (the hour skipped when the clocks go forward) is refused. A time that happens twice (the hour repeated when the clocks go back) is read as standard time, as .NET does. Fractions of a second are dropped, as the old 's' format did. 's' is culture-invariant.

#### Parameters

- `-Value` (DateTime, required): The date and time to format. A Local or Unspecified kind is read as local time and converted to UTC. Accepts pipeline input. Required. Accepts input from the pipeline.
- `-TimeZone` (TimeZoneInfo): Time zone to read an unspecified value in, for example Europe/London, instead of the computer's zone.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> ConvertTo-SalesforceSoqlDateTime -Value my-org
```

Runs ConvertTo-SalesforceSoqlDateTime with its required parameters.

#### Remarks

- To see the examples, type: "Get-Help ConvertTo-SalesforceSoqlDateTime -Examples"
- For more information, type: "Get-Help ConvertTo-SalesforceSoqlDateTime -Detailed"
- For technical information, type: "Get-Help ConvertTo-SalesforceSoqlDateTime -Full"
- For online help, type: "Get-Help ConvertTo-SalesforceSoqlDateTime -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### ConvertTo-SalesforceSoqlIdentifier

#### Synopsis

Checks that a value is a plain Salesforce object or field API name (letters, digits and underscores, starting with a letter, with optional dots for relationships) and returns it.

#### Syntax

```powershell
ConvertTo-SalesforceSoqlIdentifier [-Value] <String> [<CommonParameters>]
```

#### Description

Checks that a value is a plain Salesforce object or field API name (letters, digits and underscores, starting with a letter, with optional dots for relationships) and returns it. Identifiers cannot be quoted in SOQL, so anything else is refused instead of being placed in the query.

#### Parameters

- `-Value` (String, required): An object or field API name (letters, digits and underscores, with optional dots for relationships). Anything else makes the cmdlet throw. Accepts pipeline input. Required. Accepts input from the pipeline.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> ConvertTo-SalesforceSoqlIdentifier -Value my-org
```

Runs ConvertTo-SalesforceSoqlIdentifier with its required parameters.

#### Remarks

- To see the examples, type: "Get-Help ConvertTo-SalesforceSoqlIdentifier -Examples"
- For more information, type: "Get-Help ConvertTo-SalesforceSoqlIdentifier -Detailed"
- For technical information, type: "Get-Help ConvertTo-SalesforceSoqlIdentifier -Full"
- For online help, type: "Get-Help ConvertTo-SalesforceSoqlIdentifier -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### ConvertTo-SalesforceSoqlLiteral

#### Synopsis

Turns a value into a quoted SOQL string literal that is safe to place in a generated query.

#### Syntax

```powershell
ConvertTo-SalesforceSoqlLiteral [-Value] <String> [-Like] [<CommonParameters>]
```

#### Description

Turns a value into a quoted SOQL string literal that is safe to place in a generated query.

SOQL escapes a string with a backslash, not by doubling the quote: O'Brien is 'O\'Brien'. Backslash, apostrophe and double quote are escaped. Line breaks, tabs, backspace and form feed become \n \r \t \b \f, so a value never puts a real line break into the query. Any other control character is refused rather than guessed at. Unicode text is kept as it is.

With -Like, % and _ are escaped as well so they match themselves; without it they are left alone, because they are ordinary characters in an = comparison.

The result is also safe inside the double-quoted --query "..." argument that psfdx builds: a double quote or a backtick gets the command-line escape that ConvertTo-PsfdxArgumentList understands. Caller-authored queries passed to Select-SalesforceRecords -Query are not touched by this.

#### Parameters

- `-Value` (String, required): The text to turn into a quoted SOQL string. Quotes and backslashes are escaped; control characters other than line breaks and tabs are refused. Accepts pipeline input. Required. Accepts input from the pipeline.
- `-Like` (switch): Also escape % and _ so they match themselves inside a LIKE pattern.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> ConvertTo-SalesforceSoqlLiteral -Value my-org
```

Runs ConvertTo-SalesforceSoqlLiteral with its required parameters.

#### Remarks

- To see the examples, type: "Get-Help ConvertTo-SalesforceSoqlLiteral -Examples"
- For more information, type: "Get-Help ConvertTo-SalesforceSoqlLiteral -Detailed"
- For technical information, type: "Get-Help ConvertTo-SalesforceSoqlLiteral -Full"
- For online help, type: "Get-Help ConvertTo-SalesforceSoqlLiteral -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## APIs

### Get-SalesforceApiUsage

#### Synopsis

Shows how much of the daily API request limit an org has used.

#### Syntax

```powershell
Get-SalesforceApiUsage [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Reads the org limits with Get-SalesforceLimits and returns the DailyApiRequests entry with a Usage percentage added (used divided by max). Returns nothing if the org does not report that limit.

#### Parameters

- `-TargetOrg` (String): Username or alias of the org to check. If omitted, the Salesforce CLI uses the default target org (passed on to Get-SalesforceLimits).

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Get-SalesforceApiUsage -TargetOrg prod
```

See the API usage of the production org.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceApiUsage -Examples"
- For more information, type: "Get-Help Get-SalesforceApiUsage -Detailed"
- For technical information, type: "Get-Help Get-SalesforceApiUsage -Full"
- For online help, type: "Get-Help Get-SalesforceApiUsage -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceApiVersions

#### Synopsis

Lists the REST API versions the org supports.

#### Syntax

```powershell
Get-SalesforceApiVersions [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Sends a GET request to /services/data with sf api request rest and returns the list of versions as objects (label, url, version).

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf api request rest`

#### Examples

```powershell
PS> Get-SalesforceApiVersions -TargetOrg dev1 | Select-Object -Last 1
```

The newest API version of the org.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceApiVersions -Examples"
- For more information, type: "Get-Help Get-SalesforceApiVersions -Detailed"
- For technical information, type: "Get-Help Get-SalesforceApiVersions -Full"
- For online help, type: "Get-Help Get-SalesforceApiVersions -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-api>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceLatestApiVersion

#### Synopsis

Returns the newest REST API version the org supports, such as v62.0.

#### Syntax

```powershell
Get-SalesforceLatestApiVersion [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Calls Get-SalesforceApiVersions and returns the highest version prefixed with v. Returns nothing if the org reports no versions.

#### Parameters

- `-TargetOrg` (String): Username or alias of the org to ask. If omitted, the Salesforce CLI uses the default target org (passed on to Get-SalesforceApiVersions).

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Get-SalesforceLatestApiVersion -TargetOrg dev1
```

For example v62.0.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceLatestApiVersion -Examples"
- For more information, type: "Get-Help Get-SalesforceLatestApiVersion -Detailed"
- For technical information, type: "Get-Help Get-SalesforceLatestApiVersion -Full"
- For online help, type: "Get-Help Get-SalesforceLatestApiVersion -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Invoke-SalesforceApi

#### Synopsis

Calls a Salesforce REST API URL with an access token.

#### Syntax

```powershell
Invoke-SalesforceApi [-Url] <String> [-AccessToken] <String> [[-Method] <String>] [<CommonParameters>]
```

#### Description

Does not use the Salesforce CLI. It sends the request with Invoke-RestMethod and an Authorization: Bearer header, and returns the parsed response. The URL must be absolute and https, so the token is never sent over plain http. You choose the host; the cmdlet does not check that it is a Salesforce host.

#### Parameters

- `-Url` (String, required): Absolute https:// URL of the REST resource. Required.
- `-AccessToken` (String, required): Access token to send as the bearer token, for example from Connect-SalesforceApi. Required.
- `-Method` (String): HTTP method: GET (default), POST, PATCH or DELETE. Default: "GET". Valid values: GET, POST, PATCH, DELETE.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Invoke-SalesforceApi -Url https://example.my.salesforce.com/services/data -AccessToken $token
```

List the API versions of an org.

#### Remarks

- To see the examples, type: "Get-Help Invoke-SalesforceApi -Examples"
- For more information, type: "Get-Help Invoke-SalesforceApi -Detailed"
- For technical information, type: "Get-Help Invoke-SalesforceApi -Full"
- For online help, type: "Get-Help Invoke-SalesforceApi -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Invoke-SalesforceGraphQL

#### Synopsis

Runs a GraphQL statement against an org with the CLI's login.

#### Syntax

```powershell
Invoke-SalesforceGraphQL [[-Query] <String>] [[-QueryFile] <String>] [-Include] [[-StreamToFile] <String>] [-AsObject] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf api request graphql, which sends a GraphQL query or mutation to the Salesforce GraphQL API as the user you are logged in as. Give the statement as -Query, or put it in a file and give -QueryFile. The response is returned as text, or as an object with -AsObject. A mutation changes data, so a statement that starts with mutation asks for confirmation and supports -WhatIf; a query does not. A response the server marks as an error makes the cmdlet throw (PsfdxRequestFailed). On Windows the CLI's .cmd launcher cannot take a statement with a double quote or a line break, so use -QueryFile there.

#### Parameters

- `-Query` (String): The GraphQL statement. Use it or -QueryFile. Passed to sf as --body.
- `-QueryFile` (String): Path of a file that holds the GraphQL statement. It must exist. Use it or -Query. Passed to sf as --body.
- `-Include` (switch): Include the HTTP status and headers in the output. Adds --include.
- `-StreamToFile` (String): Write the response to this file instead of returning it. Cannot be used with -Include or -AsObject. Passed to sf as --stream-to-file.
- `-AsObject` (switch): Return the response converted from JSON instead of text. Not with -Include or -StreamToFile.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf api request graphql`

#### Examples

```powershell
PS> Invoke-SalesforceGraphQL -Query 'query { uiapi { query { Account { edges { node { Id Name { value } } } } } } }' -AsObject -TargetOrg dev1
```

Query accounts and get an object.

#### Remarks

- To see the examples, type: "Get-Help Invoke-SalesforceGraphQL -Examples"
- For more information, type: "Get-Help Invoke-SalesforceGraphQL -Detailed"
- For technical information, type: "Get-Help Invoke-SalesforceGraphQL -Full"
- For online help, type: "Get-Help Invoke-SalesforceGraphQL -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-api>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Invoke-SalesforceRestRequest

#### Synopsis

Makes an authenticated Salesforce REST API request with the CLI's login.

#### Syntax

```powershell
Invoke-SalesforceRestRequest [[-Url] <String>] [[-Method] <String>] [[-Body] <String>] [[-BodyFile] <String>] [[-File] <String>] [[-Header] <IDictionary>] [-Include] [[-StreamToFile] <String>] [-AsObject] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf api request rest, which calls any REST endpoint as the user you are logged in as, so you need no token. The response is returned as text, or as an object with -AsObject. A request that changes data (POST, PUT, PATCH or DELETE) asks for confirmation and supports -WhatIf; a read does not. An error response makes the cmdlet throw (PsfdxRequestFailed). Give the body as -Body, as a file with -BodyFile, or give the whole request (URL, method, headers and body) in a JSON -File. On Windows the CLI's .cmd launcher cannot take a body with a double quote, which JSON always has, so use -BodyFile or -File there. For the other psfdx REST helpers see Invoke-SalesforceApi, which uses an access token instead.

#### Parameters

- `-Url` (String): The endpoint, for example /services/data/v62.0/limits. Not needed if -File holds it. It is an argument of the command, not a flag.
- `-Method` (String): HTTP method. Valid values: GET, POST, PUT, PATCH, HEAD, DELETE, OPTIONS, TRACE. The CLI default is GET. Passed to sf as --method.
- `-Body` (String): The request body as text. Use one of -Body, -BodyFile and -File. Passed to sf as --body.
- `-BodyFile` (String): Path of a file that holds the request body. It must exist. The cmdlet sends it as --body @path. Use one of -Body, -BodyFile and -File.
- `-File` (String): Path of a JSON file that holds the URL, method, headers and body. It must exist. Use one of -Body, -BodyFile and -File. Passed to sf as --file.
- `-Header` (IDictionary): HTTP headers as name and value pairs. Each is passed to sf as its own --header name:value. Names are checked and a value may not contain a line break. Passed to sf as --header.
- `-Include` (switch): Include the HTTP status and headers in the output. Cannot be used with -StreamToFile or -AsObject. Adds --include.
- `-StreamToFile` (String): Write the response to this file instead of returning it. Cannot be used with -Include or -AsObject. Passed to sf as --stream-to-file.
- `-AsObject` (switch): Return the response converted from JSON instead of text.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf api request rest`

#### Examples

```powershell
PS> Invoke-SalesforceRestRequest -Url /services/data/v62.0/limits -AsObject -TargetOrg dev1
```

Read the org limits as an object.

#### Remarks

- To see the examples, type: "Get-Help Invoke-SalesforceRestRequest -Examples"
- For more information, type: "Get-Help Invoke-SalesforceRestRequest -Detailed"
- For technical information, type: "Get-Help Invoke-SalesforceRestRequest -Full"
- For online help, type: "Get-Help Invoke-SalesforceRestRequest -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-api>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Experience Cloud

### Get-SalesforceCommunityTemplates

#### Synopsis

Lists the Experience Cloud site templates available in an org.

#### Syntax

```powershell
Get-SalesforceCommunityTemplates [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf community list template and returns one object per template. Use a template name with New-SalesforceCommunity. It only reads.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf community list template`

#### Examples

```powershell
PS> Get-SalesforceCommunityTemplates -TargetOrg dev1
```

The templates the org offers.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceCommunityTemplates -Examples"
- For more information, type: "Get-Help Get-SalesforceCommunityTemplates -Detailed"
- For technical information, type: "Get-Help Get-SalesforceCommunityTemplates -Full"
- For online help, type: "Get-Help Get-SalesforceCommunityTemplates -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-community>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceCommunity

#### Synopsis

Creates an Experience Cloud site in an org from a template.

#### Syntax

```powershell
New-SalesforceCommunity [-Name] <String> [-TemplateName] <String> [[-UrlPathPrefix] <String>] [[-Description] <String>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf community create. The site is created in the org, as a draft that is not live yet; make it live with Publish-SalesforceCommunity. Digital Experiences must be turned on in the org. Supports -WhatIf and -Confirm; it does not prompt by default. To write the files of a site into a project instead, use New-SalesforceExperienceSite.

#### Parameters

- `-Name` (String, required): Name of the site. Passed to sf as --name. Required.
- `-TemplateName` (String, required): Template to build the site from, as listed by Get-SalesforceCommunityTemplates. Passed to sf as --template-name. Required.
- `-UrlPathPrefix` (String): URL path prefix of the site, appended to the domain of the org. Letters and digits only. Passed to sf as --url-path-prefix.
- `-Description` (String): Description of the site. Passed to sf as --description.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf community create`

#### Examples

```powershell
PS> New-SalesforceCommunity -Name 'Partner Portal' -TemplateName 'Customer Service' -UrlPathPrefix partners -TargetOrg dev1 -WhatIf
```

Preview creating a site.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceCommunity -Examples"
- For more information, type: "Get-Help New-SalesforceCommunity -Detailed"
- For technical information, type: "Get-Help New-SalesforceCommunity -Full"
- For online help, type: "Get-Help New-SalesforceCommunity -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-community>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Publish-SalesforceCommunity

#### Synopsis

Publishes an Experience Builder site to make its changes live.

#### Syntax

```powershell
Publish-SalesforceCommunity [-Name] <String> [-NoPrompt] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf community publish. Publishing makes the current draft of the site visible to its visitors, and it cannot be taken back with one command. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. The CLI command has no prompt of its own.

#### Parameters

- `-Name` (String, required): Name of the site to publish. Passed to sf as --name. Required.
- `-NoPrompt` (switch): Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf community publish`

#### Examples

```powershell
PS> Publish-SalesforceCommunity -Name 'Partner Portal' -TargetOrg dev1 -WhatIf
```

Preview publishing the site.

#### Remarks

- To see the examples, type: "Get-Help Publish-SalesforceCommunity -Examples"
- For more information, type: "Get-Help Publish-SalesforceCommunity -Detailed"
- For technical information, type: "Get-Help Publish-SalesforceCommunity -Full"
- For online help, type: "Get-Help Publish-SalesforceCommunity -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-community>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Tools and org information

### Get-SalesforceDataStorage

#### Synopsis

Shows how much data storage an org has used.

#### Syntax

```powershell
Get-SalesforceDataStorage [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Reads the org limits with Get-SalesforceLimits and returns the DataStorageMB entry with InUse and Usage (percentage) added. Returns nothing if the org does not report that limit.

#### Parameters

- `-TargetOrg` (String): Username or alias of the org to check. If omitted, the Salesforce CLI uses the default target org (passed on to Get-SalesforceLimits).

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Get-SalesforceDataStorage -TargetOrg prod
```

Data storage used, in MB and as a percentage.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceDataStorage -Examples"
- For more information, type: "Get-Help Get-SalesforceDataStorage -Detailed"
- For technical information, type: "Get-Help Get-SalesforceDataStorage -Full"
- For online help, type: "Get-Help Get-SalesforceDataStorage -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceDateTime

#### Synopsis

Formats a date and time as a SOQL datetime literal.

#### Syntax

```powershell
Get-SalesforceDateTime [[-Datetime] <DateTime>] [<CommonParameters>]
```

#### Description

Returns the value in UTC as 2026-11-18T11:00:00Z, ready to use in a SOQL WHERE clause. With no value it uses the current time. A local or unspecified time is converted to UTC first. It is a thin wrapper over ConvertTo-SalesforceSoqlDateTime.

#### Parameters

- `-Datetime` (DateTime): The moment to format. Defaults to now. A local or unspecified kind is read as local time and converted to UTC.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Get-SalesforceDateTime (Get-Date).AddDays(-1)
PS> Yesterday, as a literal for a CreatedDate filter.
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceDateTime -Examples"
- For more information, type: "Get-Help Get-SalesforceDateTime -Detailed"
- For technical information, type: "Get-Help Get-SalesforceDateTime -Full"
- For online help, type: "Get-Help Get-SalesforceDateTime -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceLimits

#### Synopsis

Shows the org's limits and how much of each is left.

#### Syntax

```powershell
Get-SalesforceLimits [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf org list limits and returns one object per limit with its name, max and remaining values.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf org list limits`

#### Examples

```powershell
PS> Get-SalesforceLimits -TargetOrg prod | Where-Object remaining -lt 1000
```

Limits that are nearly used up.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceLimits -Examples"
- For more information, type: "Get-Help Get-SalesforceLimits -Detailed"
- For technical information, type: "Get-Help Get-SalesforceLimits -Full"
- For online help, type: "Get-Help Get-SalesforceLimits -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-limits>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceOrgDetails

#### Synopsis

Shows the details of one org: its ID, instance URL, user name, status and API version.

#### Syntax

```powershell
Get-SalesforceOrgDetails [[-TargetOrg] <String>] [-ShowVerboseDetails] [-IncludeToken] [<CommonParameters>]
```

#### Description

Runs sf org display. The result has the access token and the Salesforce DX authorization URL removed, so the output is safe to log or share, unless you pass -IncludeToken. Anyone who has the token or the URL can act as that user, so only use -IncludeToken when you need it.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-ShowVerboseDetails` (switch): Include more details, such as the Salesforce DX authorization URL (removed again unless you pass -IncludeToken). Adds --verbose.
- `-IncludeToken` (switch): Return the CLI result as it is, with accessToken and sfdxAuthUrl. Without it psfdx removes accessToken, refreshToken, sfdxAuthUrl, password, clientSecret and privateKey from the result.

#### Salesforce CLI

- `sf org display`

#### Examples

```powershell
PS> Get-SalesforceOrgDetails -TargetOrg dev1
```

Show the org ID, instance URL and status of dev1, without any token.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceOrgDetails -Examples"
- For more information, type: "Get-Help Get-SalesforceOrgDetails -Detailed"
- For technical information, type: "Get-Help Get-SalesforceOrgDetails -Full"
- For online help, type: "Get-Help Get-SalesforceOrgDetails -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-org>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Install-SalesforceCli

#### Synopsis

Installs the Salesforce CLI globally with npm.

#### Syntax

```powershell
Install-SalesforceCli [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs npm install --global @salesforce/cli. This downloads and runs code from the npm registry. Node.js and npm must already be installed. Asks nothing by default, supports -WhatIf and -Confirm.

#### Parameters

- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Install-SalesforceCli -WhatIf
```

Show what would be installed.

#### Remarks

- To see the examples, type: "Get-Help Install-SalesforceCli -Examples"
- For more information, type: "Get-Help Install-SalesforceCli -Detailed"
- For technical information, type: "Get-Help Install-SalesforceCli -Full"
- For online help, type: "Get-Help Install-SalesforceCli -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Invoke-SalesforceDoctor

#### Synopsis

Runs the Salesforce CLI diagnostics and writes a report of its setup and problems.

#### Syntax

```powershell
Invoke-SalesforceDoctor [[-Command] <String>] [[-Plugin] <String>] [[-OutputDirectory] <String>] [-CreateIssue] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf doctor, which gathers the CLI's configuration and runs checks to find problems in your environment. The results are written to files in the output folder. With -Command it also runs that command in debug mode and logs it. -CreateIssue goes further: it opens a new issue on the Salesforce CLI's GitHub repository with the diagnostic results attached, which shares information about your machine outside it, so it asks for confirmation first. Supports -WhatIf and -Confirm.

#### Parameters

- `-Command` (String): A CLI command to run in debug mode, for example 'org list'. Its results go to a log file. Passed to sf as --command.
- `-Plugin` (String): Only run the diagnostics of this plugin. Passed to sf as --plugin.
- `-OutputDirectory` (String): Folder to save the created files in, instead of the current folder. It must exist. Passed to sf as --output-dir.
- `-CreateIssue` (switch): Create a new issue on the Salesforce CLI's GitHub repository with the diagnostic results attached. Asks for confirmation first. Adds --create-issue.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf doctor`

#### Examples

```powershell
PS> Invoke-SalesforceDoctor -OutputDirectory .\doctor
```

Run the diagnostics and keep the files in a folder.

#### Remarks

- To see the examples, type: "Get-Help Invoke-SalesforceDoctor -Examples"
- For more information, type: "Get-Help Invoke-SalesforceDoctor -Detailed"
- For technical information, type: "Get-Help Invoke-SalesforceDoctor -Full"
- For online help, type: "Get-Help Invoke-SalesforceDoctor -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-info>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Update-SalesforceCli

#### Synopsis

Updates the Salesforce CLI installed with npm.

#### Syntax

```powershell
Update-SalesforceCli [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs npm update --global @salesforce/cli. It downloads and runs code from the npm registry. Supports -WhatIf and -Confirm.

#### Parameters

- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Update-SalesforceCli -WhatIf
```

Show what would be updated.

#### Remarks

- To see the examples, type: "Get-Help Update-SalesforceCli -Examples"
- For more information, type: "Get-Help Update-SalesforceCli -Detailed"
- For technical information, type: "Get-Help Update-SalesforceCli -Full"
- For online help, type: "Get-Help Update-SalesforceCli -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Users and permissions

### Get-SalesforceOrgUser

#### Synopsis

Shows the user the CLI is signed in as in an org (sf org display user).

#### Syntax

```powershell
Get-SalesforceOrgUser [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

The access token and password are never returned: current Salesforce CLI versions replace both with a redaction message in this command, so there is nothing real to return. HasPassword says whether the CLI holds a password for the user. To set a known password, use New-SalesforceUserPassword.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf org display user`

#### Examples

```powershell
PS> Get-SalesforceOrgUser -TargetOrg myscratch
```

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceOrgUser -Examples"
- For more information, type: "Get-Help Get-SalesforceOrgUser -Detailed"
- For technical information, type: "Get-Help Get-SalesforceOrgUser -Full"
- For online help, type: "Get-Help Get-SalesforceOrgUser -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-user>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceUsers

#### Synopsis

Lists users of an org, newest login first.

#### Syntax

```powershell
Get-SalesforceUsers [[-Username] <String>] [-ActiveOnly] [[-Limit] <Int32>] [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Queries User (Id, Name, Username, Email, IsActive, LastLoginDate) through Select-SalesforceRecords, ordered by LastLoginDate descending. Values are escaped as SOQL literals.

#### Parameters

- `-Username` (String): Return only the user with this exact user name.
- `-ActiveOnly` (switch): Return only active users.
- `-Limit` (Int32): Maximum number of users to return. Default 200. Default: 200.
- `-TargetOrg` (String): Username or alias of the org to query. If omitted, the Salesforce CLI uses the default target org.

#### Salesforce CLI

No direct Salesforce CLI command.

#### Examples

```powershell
PS> Get-SalesforceUsers -ActiveOnly -Limit 20 -TargetOrg prod
```

The 20 most recently active users.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceUsers -Examples"
- For more information, type: "Get-Help Get-SalesforceUsers -Detailed"
- For technical information, type: "Get-Help Get-SalesforceUsers -Full"
- For online help, type: "Get-Help Get-SalesforceUsers -Online"

#### Related Links

- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Grant-SalesforcePermissionSet

#### Synopsis

Assigns permission sets to users (sf org assign permset).

#### Syntax

```powershell
Grant-SalesforcePermissionSet [-Name] <String[]> [[-OnBehalfOf] <String[]>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Without -OnBehalfOf the permission sets go to the target org's own user. Returns one object per user and permission set with Status Assigned or AlreadyAssigned; assigning a set the user already has is not an error, so a script can run again safely. Failures (a missing set, no permission) are returned with Status Failed and the cmdlet then throws PsfdxPermissionAssignmentFailed, whose TargetObject lists them. Asks for confirmation by default; -WhatIf makes no CLI call. Needs the Assign Permission Sets permission.

#### Parameters

- `-Name` (String[], required): Passed on to Test-SalesforceAssignmentNames -Name. Required.
- `-OnBehalfOf` (String[]): Passed on to Test-SalesforceAssignmentNames -OnBehalfOf.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org assign permset`

#### Examples

```powershell
PS> Grant-SalesforcePermissionSet -Name Sales_Admin, Reports_User -OnBehalfOf qa1, qa2 -TargetOrg myscratch -Confirm:$false
```

#### Remarks

- To see the examples, type: "Get-Help Grant-SalesforcePermissionSet -Examples"
- For more information, type: "Get-Help Grant-SalesforcePermissionSet -Detailed"
- For technical information, type: "Get-Help Grant-SalesforcePermissionSet -Full"
- For online help, type: "Get-Help Grant-SalesforcePermissionSet -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-user>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Grant-SalesforcePermissionSetLicense

#### Synopsis

Assigns permission set licenses to users (sf org assign permsetlicense).

#### Syntax

```powershell
Grant-SalesforcePermissionSetLicense [-Name] <String[]> [[-OnBehalfOf] <String[]>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Results, idempotency, failures and confirmation work as for Grant-SalesforcePermissionSet. The org must have the licence available.

Supports -WhatIf and -Confirm and asks for confirmation by default.

#### Parameters

- `-Name` (String[], required): Passed on to Test-SalesforceAssignmentNames -Name. Required.
- `-OnBehalfOf` (String[]): Passed on to Test-SalesforceAssignmentNames -OnBehalfOf.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org assign permsetlicense`

#### Examples

```powershell
PS> Grant-SalesforcePermissionSetLicense -Name SalesforceCPQ_Admin -OnBehalfOf qa1 -TargetOrg myscratch -Confirm:$false
```

#### Remarks

- To see the examples, type: "Get-Help Grant-SalesforcePermissionSetLicense -Examples"
- For more information, type: "Get-Help Grant-SalesforcePermissionSetLicense -Detailed"
- For technical information, type: "Get-Help Grant-SalesforcePermissionSetLicense -Full"
- For online help, type: "Get-Help Grant-SalesforcePermissionSetLicense -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-user>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceUser

#### Synopsis

Creates a user in an org and authorises it in the CLI (sf org create user).

#### Syntax

```powershell
New-SalesforceUser [[-DefinitionFile] <String>] [[-Field] <IDictionary>] [[-SetAlias] <String>] [-SetUniqueUsername] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Give the user's fields in a definition file (-DefinitionFile), in -Field, or both; fields in -Field override the file. Asks for confirmation only when $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. Field values go to the CLI as separate arguments, so quotes and spaces need no escaping, but a value with a double quote or a line break is rejected by the Windows CLI shim. Needs the Manage Users permission. The CLI creates users for scratch orgs and sandboxes it can sign in to.

#### Parameters

- `-DefinitionFile` (String): File path to a user definition file for customizing the new user. Passed to sf as --definition-file.
- `-Field` (IDictionary): Hashtable of user field values, for example @{ username = 'qa1@example.org'; profileName = 'Standard User' }. Each key=value is passed to the CLI as a separate argument, and a value here overrides the same field in -DefinitionFile.
- `-SetAlias` (String): Set an alias for the created username to reference in other CLI commands. Passed to sf as --set-alias.
- `-SetUniqueUsername` (switch): Force the username, if specified in the definition file or at the command line, to be unique by appending the org ID. Adds --set-unique-username.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org create user`

#### Examples

```powershell
PS> New-SalesforceUser -Field @{ username = 'qa1@example.org'; profileName = 'Standard User'; lastName = 'QA' } -SetAlias qa1 -TargetOrg myscratch
```

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceUser -Examples"
- For more information, type: "Get-Help New-SalesforceUser -Detailed"
- For technical information, type: "Get-Help New-SalesforceUser -Full"
- For online help, type: "Get-Help New-SalesforceUser -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-user>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceUserPassword

#### Synopsis

Generates a new password for a user and returns it as a SecureString (sf org generate password).

#### Syntax

```powershell
New-SalesforceUserPassword [[-OnBehalfOf] <String>] [[-Length] <Int32>] [[-Complexity] <Int32>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

This changes the user's password, so it asks for confirmation by default; -WhatIf makes no CLI call. The password is returned only as a SecureString in Password, and is never written to -Verbose, -Debug or error output by this cmdlet. Length is 20 to 1000 and complexity 3 to 5 (higher is stronger), as the CLI allows. One user at a time (-OnBehalfOf takes a single username or alias). Needs the Manage Users and Reset User Passwords and Unlock Users permissions.

#### Parameters

- `-OnBehalfOf` (String): Comma-separated list of usernames or aliases to assign the password to; must have been created locally with the "org create user" command. Passed to sf as --on-behalf-of.
- `-Length` (Int32): Number of characters in the generated password; valid values are between 20 and 1000. Default value is 20. Passed to sf as --length. Default: 20. Range: 20 to 1000.
- `-Complexity` (Int32): Level of password complexity or strength; the higher the value, the stronger the password. Passed to sf as --complexity. Default: 5. Range: 3 to 5.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf org generate password`

#### Examples

```powershell
PS> $p = New-SalesforceUserPassword -OnBehalfOf qa1 -TargetOrg myscratch -Confirm:$false; $p.Username
```

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceUserPassword -Examples"
- For more information, type: "Get-Help New-SalesforceUserPassword -Detailed"
- For technical information, type: "Get-Help New-SalesforceUserPassword -Full"
- For online help, type: "Get-Help New-SalesforceUserPassword -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-user>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>
