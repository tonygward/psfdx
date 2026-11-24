# Installing psfdx from the PowerShell Gallery

One command installs everything:

```powershell
Install-Module psfdx
```

There is one Gallery listing, `psfdx`, one install and one update path (`Update-Module psfdx`). The package holds every module: `psfdx` (the core commands), `psfdx-metadata`, `psfdx-devops`, `psfdx-bulk`, `psfdx-plugins`, `psfdx-development`, `psfdx-logs`, `psfdx-org`, `psfdx-packages`, `psfdx-agentforce` and the shared helpers `psfdx-shared`. There are no separate `psfdx-*` packages to install.

## What you get

Each module keeps its own name, so you can see where a command comes from and list a module's commands on their own:

```powershell
Import-Module psfdx                  # loads the package and, with it, every module
Get-Command -Module psfdx            # the core commands only, Source psfdx
Get-Command -Module psfdx-logs       # only the commands the logs module owns, Source psfdx-logs
Get-Command -Module 'psfdx*'         # every command, each attributed to the module that holds it
Get-Module 'psfdx*'                  # the loaded modules: psfdx, psfdx-logs, psfdx-metadata, ...
```

| Module | What it holds |
| :--- | :--- |
| `psfdx` | Authentication, orgs, aliases, records and SOQL, limits, REST and GraphQL requests, installing the Salesforce CLI itself |
| `psfdx-metadata` | Retrieve, deploy and describe metadata |
| `psfdx-devops` | Salesforce DevOps Center: projects, work items, pipelines, stages, promotion and the beta pipeline deploys |
| `psfdx-bulk` | Salesforce Bulk API 2.0: bulk export, import, update, upsert and delete, and bulk job status, results and resume |
| `psfdx-plugins` | Salesforce CLI plugins: install, list, inspect, update, uninstall, discover, reset, signature checks and the allowlist |
| `psfdx-development` | Projects, Apex tests, Code Analyzer, templates, LWC |
| `psfdx-logs` | Debug logs, login history, event monitoring |
| `psfdx-org` | Org lifecycle: sandboxes and scratch orgs |
| `psfdx-packages` | Packages and package versions |
| `psfdx-agentforce` | Agentforce agents |
| `psfdx-shared` | Internal: implementation helpers the other modules use. It exports no commands, so it is not part of the public command surface, `Get-Command -Module psfdx*` does not list it, and it has no page on the website |

No command is defined twice. `psfdx` exports only its own commands and does not re-export the others.

**Which module holds a command.** A cmdlet belongs to the module for the family of Salesforce CLI commands it wraps, and a command family that comes from one CLI plugin stays together. For example every cmdlet that runs a command of the DevOps Center plugin (`@salesforce/plugin-devops-center`) is in `psfdx-devops`: the 26 `sf devops` commands and the 5 beta `sf project deploy pipeline` commands, even though the second group looks like a deploy. They were in `psfdx-metadata` until a release that moved them. The same rule puts the Bulk API 2.0 cmdlets in `psfdx-bulk` (single-record changes, SOQL and the older data tree cmdlets stay in `psfdx`) and the Salesforce CLI plugin cmdlets (`sf plugins ...`) in `psfdx-plugins`; `Install-SalesforceCli` and `Update-SalesforceCli` stay in `psfdx` because they install the CLI itself, not a plugin. A command keeps its name and parameters when its module changes; only the module shown in `Get-Command` (the `Source`) differs, so scripts that call it by name keep working.

## When the other modules load

PowerShell finds a module only as a folder of its own on its module path, and `Install-Module` installs one package as one folder. So after the install only `psfdx` is discoverable, and the other modules arrive when it loads. `psfdx` loads when you `Import-Module psfdx`, when you use any core command (PowerShell loads it for you), and when you ask `Get-Command -Module psfdx`. Loading it loads every other module, each under its own name.

In practice:

- In a new session, `Get-Command -Module psfdx`, then `Get-Command -Module psfdx-logs`, then `Get-Command -Module 'psfdx*'` give the core commands, the logs commands and all commands, each correctly attributed.
- If the very first thing you do in a new session is `Get-Command -Module psfdx-logs` (or `-Module 'psfdx*'`), it shows no non-core commands yet, because nothing has loaded `psfdx`. Run `Import-Module psfdx` first.
- A command from a non-core module, such as `Get-SalesforceDebugLogs`, is not found by name until `psfdx` has loaded. Start a session with `Import-Module psfdx` (put it in your profile if you like) and everything is there.
- `Get-Module -ListAvailable 'psfdx*'` lists `psfdx`, the one package you installed. The other modules show in `Get-Module 'psfdx*'` once loaded.

This was chosen on purpose. Listing every command in the `psfdx` manifest would make all of them autoload by name, but it would label every command `psfdx` until the first import, and `Get-Command -Module psfdx` would no longer show only the core commands.

## Updating

```powershell
Update-Module psfdx
```

Every module is released at the same version and travels in the one package, so one update moves them all. PowerShellGet keeps the older version in its own folder; `Import-Module psfdx` loads the newest. Do not import an old version and a new one in the same session: both define the same commands.

If you have the earlier single package, `Update-Module psfdx` upgrades it the same way; its commands are all still there, and `Import-Module psfdx` still gives you all of them. What changes is that they now show under their own module names.

## When something is missing

An install can lose a file (an antivirus quarantines it, a folder is cleaned up, an update stops half way). `Import-Module psfdx` then fails and names the missing module, for example `psfdx-logs`. Install the same version again to put it back:

```powershell
Install-Module psfdx -RequiredVersion <the version you have> -Force
```

If you want to start clean:

```powershell
Uninstall-Module psfdx -AllVersions -Force
Install-Module psfdx
```

## Working from a clone

`./install.ps1` (Mac and Linux) and `./install-windows.ps1` copy the modules from a checkout into your module folder, one folder per module (`psfdx`, `psfdx-logs` and so on). Each is then discoverable on its own, so `Get-Command -Module psfdx-logs` works in a new session without importing anything, and you import the modules you want (`Import-Module psfdx-logs`). Do not use both a clone install and the Gallery package on the same machine: they define the same commands.

## How CI checks all of this

`CI - Suite install` builds the package, publishes it to a folder repository as a real NuGet package, and installs it from there with PowerShellGet on Ubuntu (PowerShell 7), Windows (PowerShell 7) and Windows PowerShell 5.1. `scripts/release/Test-PsfdxSuite.ps1` then runs in fresh sessions that see only the installed copy:

- one `Save-Module psfdx` brings the whole suite, and it is one package;
- in a fresh session `Get-Command -Module psfdx` shows only the core commands, Source `psfdx`;
- in one fresh session, in order, `-Module psfdx`, `-Module psfdx-logs` and `-Module 'psfdx*'` give the core commands, exactly the logs commands, and every command attributed to its own module, with nothing missing, twice or falsely attributed;
- the same after `Import-Module psfdx`, and after the first use of a core command with no import;
- a representative command from every module runs;
- it records the evidence: command counts per module, ownership, zero duplicates, the representative runs, and what a brand-new session shows. The workflow uploads it.

`scripts/release/Test-PsfdxSuiteUpgrade.ps1` checks an upgrade (a newer version next to an older one loads only the newer, all modules at the new version), a missing module folder (named in the error and put back by installing again), and, on the CI runner, `Install-Module` then `Update-Module` and `Install-Module -Force`. After a release publishes the package, `CI - Gallery install check` runs the same acceptance checks against the real Gallery.
