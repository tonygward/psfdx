# Installing psfdx from the PowerShell Gallery

One command installs everything:

```powershell
Install-Module psfdx
```

> **Status.** The packages described here are built and tested by CI (`CI - Suite install`) on every change, but the Gallery keeps serving one bundled `psfdx` package until `scripts/release/gallery.json` says `"layout": "suite"` (see [releases](release.md#powershell-gallery)). The one command, `Install-Module psfdx`, is the same either way. What changes is that each module then becomes a package of its own.

## What the one command installs

`psfdx` is an umbrella: a package with no code of its own whose manifest requires the rest of the suite, each at exactly its own version. PowerShellGet installs the whole set from the one command, and each module keeps its own name:

| Package | What it holds | Needs |
| :--- | :--- | :--- |
| `psfdx` | The umbrella. No commands. | every package below |
| `psfdx-core` | Authentication, orgs, aliases, records and SOQL, limits, REST and GraphQL requests, CLI and plugin management | `psfdx-shared` |
| `psfdx-metadata` | Retrieve, deploy and describe metadata; DevOps Center | `psfdx-shared` |
| `psfdx-development` | Projects, scratch orgs, Apex tests, Code Analyzer, templates, LWC | `psfdx-shared`, `psfdx-core` |
| `psfdx-logs` | Debug logs, login history, event monitoring | `psfdx-shared`, `psfdx-core` |
| `psfdx-sandbox` | Sandbox lifecycle | `psfdx-shared` |
| `psfdx-packages` | Packages and package versions | `psfdx-shared` |
| `psfdx-agentforce` | Agentforce agents | `psfdx-shared` |
| `psfdx-shared` | Helpers the other modules use | nothing |

The "Needs" column is generated from `Get-PsfdxModuleDependencies` in `modules.ps1`, and a repository test checks it against what each module's code calls.

## See what you have

```powershell
Get-Module -ListAvailable 'psfdx*'      # the umbrella and every module, each under its own name
Get-Command -Module 'psfdx*'            # every command, with its real module in the Source column
Get-Command Get-SalesforceDebugLogs     # a command is found by name too, and its module loads itself
```

None of these needs an import first. PowerShell finds the commands because every module lists its exports by name. They work the same on Windows PowerShell 5.1 and PowerShell 7 (CI checks both on every change).

`Import-Module psfdx` loads the whole suite. It defines no command twice, and it exports no commands itself: `Get-Command -Module psfdx` alone shows nothing, which is why the examples use `'psfdx*'`.

## Installing only part of the suite

Each module is a package of its own, so you can install one:

```powershell
Install-Module psfdx-logs        # also installs psfdx-core and psfdx-shared, which it needs
Import-Module psfdx-logs
```

That gives you `psfdx-logs` and the two modules it calls, and nothing else. Installing the umbrella later adds the rest.

## Updating

```powershell
Update-Module psfdx
```

Every module is released at the same version, and the umbrella requires each module at exactly that version, so `Update-Module psfdx` moves all nine together. PowerShellGet keeps the older versions in their own folders next to the new ones; they are not loaded. `Import-Module psfdx` loads the newest umbrella and, with it, exactly the module versions it names.

To update just one part you installed on its own, run `Update-Module psfdx-logs`: it brings the matching `psfdx-core` and `psfdx-shared` with it.

If you installed the single bundled package of an earlier release, `Update-Module psfdx` also works. The old version stays in its folder and is not loaded once the newer one exists. Do not import the old version and the new modules in the same session: both define the same commands.

## When something is missing

An install can lose a module (an antivirus quarantines a file, a folder is cleaned up, an update stops half way). `Import-Module psfdx` then fails and names the missing module, for example `psfdx-core`. Put it back by installing the same version of the umbrella again:

```powershell
Install-Module psfdx -RequiredVersion <the version you have> -Force
```

That installs every module at that version that is not already there. If you want to start clean, remove the suite and install it again:

```powershell
'psfdx', 'psfdx-agentforce', 'psfdx-packages', 'psfdx-metadata', 'psfdx-sandbox', 'psfdx-development', 'psfdx-logs', 'psfdx-core', 'psfdx-shared' |
    ForEach-Object { Uninstall-Module -Name $_ -AllVersions -Force -ErrorAction SilentlyContinue }
Install-Module psfdx
```

## Working from a clone

`./install.ps1` (Mac and Linux) and `./install-windows.ps1` copy the modules from a checkout into your module folder, one folder per module (`psfdx-core`, `psfdx-logs` and so on). They do not install the umbrella: `Import-Module psfdx-core`, or any module you want. The core module used to be installed as `psfdx`; the scripts remove that old copy, because it would define every command twice next to `psfdx-core`. They leave a Gallery install of `psfdx` alone. Do not use both on the same machine.

## How CI checks all of this

`CI - Suite install` builds the packages, publishes them to a folder repository, and installs from it on Ubuntu (PowerShell 7), Windows (PowerShell 7) and Windows PowerShell 5.1, with PowerShellGet:

- `Save-Module psfdx` must bring all nine packages at the right version, and nothing else is needed;
- `Get-Module -ListAvailable` and `Get-Command -Module 'psfdx*'` must see every module and every command, each command from its own module, with no import;
- `Import-Module psfdx` must load the suite and define no command twice;
- a module saved on its own must work with only its own dependencies;
- a newer version saved next to an older one must bring every module at the new version, a missing module must be named, and installing again must put it back; on the CI runner `Install-Module` then `Update-Module` do the same.

The scripts are `scripts/release/Test-PsfdxSuite.ps1` and `Test-PsfdxSuiteUpgrade.ps1`. After a release publishes the suite, `CI - Gallery install check` runs the same checks against the real Gallery.
