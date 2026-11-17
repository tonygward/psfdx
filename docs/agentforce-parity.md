# Agentforce CLI parity matrix

Scope of the `psfdx-agentforce` module against the Salesforce CLI agent plugin (`@salesforce/plugin-agent`).

- **CLI version pinned for command checks:** `2.100.0` (`tests/cli-compatibility.json`).
- **Plugin:** `@salesforce/plugin-agent`, bundled with the CLI. If missing, install it with `sf plugins install @salesforce/plugin-agent`. Every cmdlet checks `sf plugins --core --json` first and stops with that guidance.
- **Status caveat:** the CLI marks some agent commands beta or developer preview and changes them between releases. This matrix was written without a live CLI, so confirm each row with `sf agent <command> --help` before relying on it. The opt-in help lane (`PSFDX_SF_CLI_HELP=1`) runs `--help` for every wrapped command.

## Wrapped

| CLI command | Cmdlet | Org-modifying |
| :--- | :--- | :--- |
| `sf plugins --core --json` | `Test-SalesforceAgentPlugin` | No |
| `sf agent test list` | `Get-SalesforceAgentTests` | No |
| `sf agent test run --api-name` | `Start-SalesforceAgentTest` | Creates a test run |
| `sf agent test results --job-id` | `Get-SalesforceAgentTestResult` | No |
| `sf agent activate --api-name` | `Enable-SalesforceAgent` | Yes, `ShouldProcess` (High) |
| `sf agent deactivate --api-name` | `Disable-SalesforceAgent` | Yes, `ShouldProcess` (High) |

## Not wrapped

| CLI command | Reason |
| :--- | :--- |
| `sf agent create`, `sf agent generate agent-spec` | Interactive or AI-assisted generation; not suited to a structured cmdlet yet. |
| `sf agent generate authoring-bundle`, `sf agent validate authoring-bundle`, `sf agent publish authoring-bundle` | Beta or developer preview. |
| `sf agent preview` (and `start`/`send`/`end`) | Interactive session, beta or developer preview. |
| `sf agent test create`, `sf agent test resume`, `sf agent generate test-spec` | Interactive or file-generating; candidates for a later change. |

Promote a row to "Wrapped" only once the command is stable in the pinned CLI.

## Tests

Pester tests mock `Invoke-Salesforce` and assert the exact command strings, JSON mapping, plugin-absent, invalid-argument and failure paths. No org is needed. A sandbox-backed smoke test is not included.
