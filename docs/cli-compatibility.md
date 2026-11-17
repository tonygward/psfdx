# Salesforce CLI compatibility checks

`tests/CliCompatibility.Tests.ps1` guards psfdx against Salesforce CLI (`sf`) changes. It sits beside the mocked Pester tests and never needs an org or credentials.

## Default lane (offline, runs in `Invoke-Pester -Path . -CI`)

It parses every module `.psm1` and `psfdx-shared` script and takes each string that starts with `sf `. It checks them against `tests/cli-compatibility.json`:

| Check | Fails when | Suggestion in the message |
| :--- | :--- | :--- |
| Removed command | the command is in `removedCommands` (`sfdx`, `sf force ...`, `sf deploy metadata`) | the replacement |
| Legacy flag | a string contains a flag in `legacyFlags` (for example `--targetusername`) | the new flag |
| Unknown command | the command is not in `knownCommands` | run `sf <command> --help`, then add it or replace it |

A failure reads `psfdx-logs/psfdx-logs.psm1 Get-Thing: <problem> (<command>). Suggested: <replacement>`. Only the command words are reported, never flag values, so no secrets reach the output or the report.

The same test runs on Ubuntu and Windows because it only reads files. Commands whose later words are variables (`sf lightning dev $Mode`) match on the leading words.

### Report

The run writes a JSON report with `pinnedCliVersion`, the commands checked (file, function, command) and any findings. Set `PSFDX_CLI_COMPAT_REPORT` to a path to keep it; otherwise it goes to Pester's `$TestDrive` and is discarded.

## Opt-in lane (needs the pinned CLI, still no org)

```powershell
npm install --global @salesforce/cli@<pinnedCliVersion>
$env:PSFDX_SF_CLI_HELP = '1'
Invoke-Pester -Path ./tests/CliCompatibility.Tests.ps1
```

It checks that `sf --version` matches the pin and that `sf <command> --help` succeeds for every known command. It is skipped unless the variable is `1` and `sf` is on the path. Org-backed integration tests are not part of this lane.

## Pinned version and refresh

`pinnedCliVersion` in `tests/cli-compatibility.json` is the reviewed CLI version. The CLI is never updated automatically. To refresh it, install the new version, run the opt-in lane, fix or add commands in `knownCommands`, `removedCommands` and `legacyFlags`, then change the pin in a reviewed pull request.

## Rollback

The check is test-only. To roll back, revert the change to `tests/cli-compatibility.json` or remove the test file. Nothing in the modules depends on it.

## Not yet done

Adding the opt-in lane to a scheduled workflow, and uploading the report as an artifact, change `.github/workflows/` and need human approval under [execution-policy.md](execution-policy.md).
