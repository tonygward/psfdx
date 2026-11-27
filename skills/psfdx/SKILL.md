---
name: psfdx
description: Use PSFDX PowerShell commands to query Salesforce, inspect orgs and metadata, and compose object pipelines. Activate for Salesforce tasks where PowerShell is available and PSFDX is installed or the user wants to set it up.
---

# PSFDX

Use PowerShell, the Salesforce CLI (`sf` on PATH), and the `psfdx` PowerShell Gallery package. Check availability with `Get-Command sf` and `Get-Module -ListAvailable psfdx`. With the user's approval to install software, run `Install-Module psfdx -Scope CurrentUser` after installing the [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli). Then run `Import-Module psfdx` to load the suite.

Use an existing authorized org. If sign-in is needed, ask the user to authenticate interactively with `Connect-Salesforce -Sandbox` for a sandbox, or consult `Get-Help Connect-Salesforce -Full` for another supported login flow. Never ask the user to paste tokens, auth URLs, passwords or client secrets into chat. Keep credentials out of commands, logs and exported results.

## Discover commands

1. List command names and modules with `Get-Command -Module 'psfdx*' | Select-Object Name, Source`. Narrow the list by task before requesting help.
2. Open `Get-Help <command> -Full`, or `Get-Help <command> -Examples`. Inspect parameter sets with `(Get-Command <command>).ParameterSets`. Prefer the installed command's metadata when it differs from a newer reference.
3. For offline lookup, read only the relevant file under [references](references/README.md). For example, use [psfdx-data](references/psfdx-data.md) for SOQL, records and bulk data, or [psfdx-metadata](references/psfdx-metadata.md) for deploy and retrieve. Find the remaining modules in the index. The [website reference](https://psfdx.com/modules/) is also available.

## Verify the org and get approval

Pass an explicit target alias or username to every org-scoped command. Confirm it resolves to the user's intended org before running the workflow. For example, use `sf org display --target-org my-sandbox --json` and extract only the org ID, username and instance URL from the JSON in the shell. Raw org display output can contain credentials. An alias alone does not establish that the org is a sandbox.

Obtain explicit approval before destructive operations or any production deployment. State the target org, objects or components, and expected effect. Use `-WhatIf` or a validation-only deployment when supported and appropriate. Never use confirmation-suppressing flags to replace user approval.

## Read-only workflows

Run a bounded query against the confirmed alias and select only the fields required:

```powershell
Select-SalesforceRecords -Query 'SELECT Id, Name FROM Account LIMIT 10' -TargetOrg my-sandbox
```

For a grouped summary, keep the results as PowerShell objects and project only the fields needed by the next step. This example groups a sample of accounts by industry:

```powershell
Select-SalesforceRecords -Query 'SELECT Industry FROM Account WHERE Industry != null LIMIT 100' -TargetOrg my-sandbox |
    Group-Object -Property Industry |
    Select-Object Name, Count |
    Sort-Object Count -Descending
```

Report that the summary is limited to the returned sample. If a command fails, preserve the actionable error and check the target, permissions and parameters before retrying.
