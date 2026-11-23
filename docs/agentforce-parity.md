# Agentforce CLI parity matrix

Scope of the `psfdx-agentforce` module against the Salesforce CLI agent plugin (`@salesforce/plugin-agent`). Every `sf agent` command, and the two agent commands that live under `sf org`, is wrapped. The generated [CLI parity report](cli-parity.md) is the source of truth for flags and values; this page explains the choices.

- **CLI version:** not pinned. `CI - Salesforce CLI compatibility` checks every wrapped command against the latest stable CLI and records the exact version in its report (see [cli-compatibility.md](cli-compatibility.md)).
- **Plugin:** `@salesforce/plugin-agent`, bundled with the CLI. If missing, install it with `sf plugins install @salesforce/plugin-agent`. Every cmdlet checks `sf plugins --core --json` first and stops with that guidance.
- **Beta and preview:** the CLI marks some agent commands beta or preview and changes them between releases. They are wrapped, and their help says so. The live help lane (`PSFDX_SF_CLI_HELP=1`) is the signal when one changes.

## Wrapped

| CLI command | Cmdlet | Kind |
| :--- | :--- | :--- |
| `sf plugins --core --json` | `Test-SalesforceAgentPlugin` | Read |
| `sf agent activate` / `deactivate` | `Enable-SalesforceAgent` / `Disable-SalesforceAgent` | Org change, `ShouldProcess` High |
| `sf agent create` | `New-SalesforceAgent` | Org change, `ShouldProcess` Medium |
| `sf agent generate agent-spec` | `New-SalesforceAgentSpec` | Local file; interactive only with `-FullInterview` |
| `sf agent generate template` | `New-SalesforceAgentTemplate` | Local file |
| `sf agent generate test-spec` | `New-SalesforceAgentTestSpec` | Local file; interactive unless `-FromDefinition` |
| `sf agent generate authoring-bundle` | `New-SalesforceAgentAuthoringBundle` | Local files |
| `sf agent validate` / `publish authoring-bundle` | `Test-SalesforceAgentAuthoringBundle` / `Publish-SalesforceAgentAuthoringBundle` | Read / org change (High) |
| `sf agent test list` / `run` / `results` | `Get-SalesforceAgentTests` / `Start-SalesforceAgentTest` / `Get-SalesforceAgentTestResult` | Read / creates a run / read |
| `sf agent test create` | `New-SalesforceAgentTest` | Org change, Medium |
| `sf agent test resume` | `Resume-SalesforceAgentTest` | Read |
| `sf agent test run-eval` (beta) | `Start-SalesforceAgentEvaluation` | Runs a test, no org change |
| `sf agent preview start` / `send` / `end` / `sessions` | `Start-SalesforceAgentPreview` / `Send-SalesforceAgentPreviewMessage` / `Stop-SalesforceAgentPreview` / `Get-SalesforceAgentPreviewSessions` | Programmatic session; `end` asks first |
| `sf agent preview` | `Invoke-SalesforceAgentPreview` | Interactive |
| `sf agent trace list` / `read` / `delete` | `Get-SalesforceAgentTraces` / `Read-SalesforceAgentTrace` / `Remove-SalesforceAgentTrace` | Local files; `delete` is High and needs a filter |
| `sf agent adl create` / `update` / `delete` | `New-` / `Update-` / `Remove-SalesforceAgentDataLibrary` | Org change (Medium, Medium, High) |
| `sf agent adl get` / `list` / `status` | `Get-SalesforceAgentDataLibrary` / `Get-SalesforceAgentDataLibraries` / `Get-SalesforceAgentDataLibraryStatus` | Read |
| `sf agent adl file add` / `upload` / `delete` / `list` | `Add-` / `Send-` / `Remove-` / `Get-SalesforceAgentDataLibraryFile(s)` | Org change (Medium, Medium, High) / read |
| `sf agent mcp create` / `update` / `delete` (preview) | `New-` / `Update-` / `Remove-SalesforceMcpServer` | Org change (Medium, Medium, High) |
| `sf agent mcp get` / `list` (preview) | `Get-SalesforceMcpServer` / `Get-SalesforceMcpServers` | Read |
| `sf agent mcp asset list` / `fetch` / `replace` (preview) | `Get-SalesforceMcpAssets` / `Get-SalesforceMcpServerLiveAssets` / `Set-SalesforceMcpAssets` | Read / read / org change, Medium |
| `sf org create agent-user` | `New-SalesforceAgentUser` | Org change, Medium |
| `sf org open agent` | `Open-SalesforceAgent` | Opens a browser, or prints a link with `-UrlOnly` |

## Decisions

- **Interactive commands.** `sf agent preview`, `agent generate test-spec` (without a definition file) and `agent generate agent-spec --full-interview` ask questions and have no JSON mode. They run through `Invoke-Salesforce -Interactive`, which keeps the console, and stop with a clear message in a session without a terminal. Run them as plain commands: an assigned or piped result hides the questions.
- **Secrets.** The MCP client secret is a `SecureString`, turned into text only when the command is built, and the CLI's own verbose line masks `--client-secret`. A server URL must be an absolute https URL, because credentials are sent to it.
- **Confirmation.** Deletes are `ConfirmImpact = 'High'`. Where the CLI has `--no-prompt` (`agent preview end`, `agent trace delete`, `agent mcp delete`), psfdx asks first and always passes it, so the CLI does not ask twice; `-NoPrompt` skips only the PowerShell question and never overrides `-WhatIf`. `Remove-SalesforceAgentTrace` needs at least one filter, so a call cannot delete every trace by accident.
- **Result formats.** Cmdlets that take `-ResultFormat` return an object for `json` (and when it is left off, as before), and the CLI text for `human`, `junit` and `tap`, so a CI step can redirect JUnit XML to a file.
- **Input checks.** Names, IDs and file paths are checked before `sf` runs. Context variables are `Field=value` pairs with checked names, so a name cannot become an option and a value that looks like a flag is passed as a value.
- **Windows and double quotes.** On Windows the Salesforce CLI is a `.cmd` launcher that cannot be given an argument with a double quote or a line break. JSON always has quotes, so `-ContextVariablesJson` (preview) and `-Assets` / `-AssetList` (MCP assets) cannot work there, and neither can an utterance with a quote. The cmdlets say so in their help and, when the launcher refuses, name the alternative: `-ContextVariables` and `-AssetsFile`. They work normally on macOS and Linux.

## Tests

Pester tests mock `Invoke-Salesforce` and assert the exact argument array, JSON mapping, plugin-absent, invalid-argument and failure paths for every cmdlet. No org is needed. The live help lane checks every flag against the real CLI help. A sandbox-backed smoke test is not included, so the org-backed behavior of the new commands (and the shape of results that need a real agent, such as a preview session) has not been seen against a live org.
