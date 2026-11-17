# Salesforce CLI compatibility checks

psfdx is tested against the **latest stable Salesforce CLI** (`sf`). No CLI version is pinned anywhere. Two lanes guard against CLI changes; neither needs an org or credentials. Both live in `tests/CliCompatibility.Tests.ps1`, with shared code in `tests/CliCompatibility.Helpers.ps1` and the command list in `tests/cli-compatibility.json`.

| Lane | Needs the CLI | Where it runs | What it proves |
| :--- | :--- | :--- | :--- |
| Offline | No | Every `Invoke-Pester -Path . -CI`, on every leg | psfdx builds no removed command, no legacy flag and no command outside the known list. It compares against a list, **not** against the CLI, so it is **not proof** that psfdx works with the current CLI. |
| Live | Yes, the latest stable | `CI - Salesforce CLI compatibility`: pull requests that touch a module, every Monday, and by hand; Ubuntu and Windows | Every command psfdx runs answers `sf <command> --help` on the current CLI, and every flag psfdx passes is listed in that help. |

## Offline lane

It parses every module `.psm1` and `psfdx-shared` script and takes each string that starts with `sf `. It checks them against `tests/cli-compatibility.json`:

| Check | Fails when | Suggestion in the message |
| :--- | :--- | :--- |
| Removed command | the command is in `removedCommands` (`sfdx`, `sf force ...`, `sf deploy metadata`, `sf org clone sandbox`) | the replacement |
| Legacy flag | a string contains a flag in `legacyFlags` (for example `--targetusername`) | the new flag |
| Unknown command | the command is not in `knownCommands` | run `sf <command> --help`, then add it or replace it |

A failure reads `psfdx-logs/psfdx-logs.psm1 Get-Thing: <problem> (<command>). Suggested: <replacement>`. Only the command words are reported, never flag values, so no secrets reach the output or the report. Commands whose later words are variables (`sf lightning dev $Mode`) match on the leading words.

## Live lane

Run it yourself:

```powershell
npm install --global @salesforce/cli@latest   # the latest stable release; never a release candidate
$env:PSFDX_SF_CLI_HELP = '1'
Invoke-Pester -Path ./tests/CliCompatibility.Tests.ps1 -CI -Output Detailed
```

- **The CLI version is logged.** The test prints `Salesforce CLI version under test: X.Y.Z`, and the same version is in the JSON report, the job summary and the uploaded artifact.
- **It fails, never skips.** With `PSFDX_SF_CLI_HELP=1`, a missing CLI is a failure: `Salesforce CLI ('sf') was not found on PATH. Install the latest stable CLI...`.
- **Commands.** `sf <command> --help` must succeed for every command psfdx uses. A command that vanished, or whose plugin is missing, is reported with the suggestion `sf <command> --help` and `sf commands`.
- **Flags.** The flags psfdx passes in a function (a string that is an `sf` command or starts with `--`) must all appear in the FLAGS or GLOBAL FLAGS section of the help for that function's commands. A missing flag is reported as `<file> <function>: Flag '--x' is not listed by the CLI help (sf <command>)`.
- **Topic commands.** `sf lightning dev` is a topic whose help lists subcommands, not flags, so its flags are not checked. The report lists these under `topicCommands`.
- **Plugins.** The agent and Lightning plugins come bundled with the CLI. If a command's plugin is ever not bundled, install it in the workflow and the failure message will say so.

### Report

Both lanes write a JSON report: `lane` (`offline` or `live-help`), `cliVersion` (the exact version, or `not checked (offline lane)`), the commands checked and any findings. Set `PSFDX_CLI_COMPAT_REPORT` to a path to keep it. The workflow uploads it as the artifact `cli-compatibility-ubuntu` / `cli-compatibility-windows` and writes the version and findings into the job summary.

### What a failure means

The live lane fails when the **CLI** changed, not only when psfdx did, so a Monday run can fail with no code change. Fix psfdx (the cmdlet's command string and its test), then update `knownCommands`, `removedCommands` or `legacyFlags` if needed. The merge gate also holds Matrix pull requests while a workflow run for their commit is failing, so a failing live lane stops auto-merge for module changes until it is fixed.

## Keeping the list current

`tests/cli-compatibility.json` holds `knownCommands`, `removedCommands` and `legacyFlags`. It has no CLI version. When psfdx starts using a new `sf` command, add it to `knownCommands`; the live lane then checks it against the real CLI.

## Rollback

The checks are test-only. To stop the live lane, disable or delete `.github/workflows/ci-cli-compat.yml`. To remove the checks entirely, revert the test files; nothing in the modules depends on them.
