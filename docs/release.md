# Releases

How a merge becomes a release. The rules are in the [execution policy](execution-policy.md); the workflows are listed in [pipelines](pipelines.md).

## From merge to release

1. A pull request merges to `main` after `CI - Pester tests` passed on its head commit.
2. `CD - Bump version` runs. It skips bump commits and any merge that ships nothing. Only a change to what users install (`psfdx*/` other than tests and Markdown, `modules.ps1`, the install and uninstall scripts, `VERSION`) is released; workflows, scripts, tools, tests and documentation never are. The rule is `scripts/release/changes.mjs`, shared with CI and Matrix. Otherwise it checks that CI passed on the pull request's exact head commit (waiting up to 15 minutes), then runs `scripts/release/bump.mjs`.
3. The script raises the third part of `VERSION`, writes it into every manifest, and moves everything under `## Unreleased` in `CHANGELOG.md` into a dated section for the new version. An empty `## Unreleased` becomes `- Maintenance release.`. It refuses to run if `VERSION` and the manifests disagree.
4. The workflow commits `[release] X.Y.Z`, tags `vX.Y.Z` and pushes both with `RELEASE_TOKEN`.
5. `CD - Publish release` runs on the tag. It checks the tag against `VERSION` and the manifests, runs Pester once more, builds the zip and creates the GitHub release. It then lists the release's assets and fails if there is anything but the one zip. A release that already exists is never overwritten.

## What a release contains

One asset, `psfdx-X.Y.Z.zip`, holding the module folders from `modules.ps1` (without tests), the install and uninstall scripts, `modules.ps1`, `README.md`, `CHANGELOG.md` and `LICENSE` if present. The release notes are that version's changelog section.

## Release notes

Any pull request with a change users will notice adds plain-language bullets under `## Unreleased`, prefixed with the module name. No commit hashes, pull request titles or prompt IDs. Mark breaking changes `Breaking:`.

## Minor and major bumps

These are owner decisions. Edit `VERSION` and every manifest's `ModuleVersion` in a normal pull request titled `[minor]` or `[major]`. The next automatic bump then increases the third part from there.

## Owner setup

Add a `RELEASE_TOKEN` Actions secret (Contents and Pull requests write) and let it bypass branch protection for the bump commit only.

## PowerShell Gallery

The Gallery gets **one** package, `psfdx`, containing every module, so users run `Install-Module psfdx` and nothing else ([install.md](install.md) is the guide for users). The repository keeps its separate modules (`psfdx/` is the core module, then `psfdx-logs`, `psfdx-metadata` and the rest); `scripts/release/Build-GalleryPackage.ps1` assembles `out/psfdx/` from them:

- **`psfdx` is the core module and the package's root module.** The generated `psfdx.psd1` is the core manifest with the version from `VERSION`, the Gallery metadata and the core module's explicit `FunctionsToExport`, so `Get-Command -Module psfdx` shows the core commands and nothing else, each with the Source `psfdx`. The core module's GUID (`2785d2bf-775f-4f2b-9d00-ee98f0163cf0`) is the Gallery identity of the package, so the build refuses to ship if it ever changes.
- **Every other module sits in a folder of its own in the package** (`psfdx-shared/`, `psfdx-logs/`, ...), copied without its tests, with its own manifest, GUID and explicit exports. `RequiredModules` is emptied in those copies, because `psfdx` loads them and a module that required `psfdx` would ask for the module that is still loading.
- **A loader is added to the end of `psfdx.psm1`** (and a one-line start that loads `psfdx-shared` first, so `Import-PsfdxSharedModule` finds it). When `psfdx` loads, the loader imports the other modules with `-Global`, in the order `modules.ps1` lists them, so each is a module in its own right: `Get-Module`, `Get-Command -Module psfdx-logs` and `Get-Command -Module 'psfdx*'` attribute every command to the module that holds it, with none twice. `Remove-Module psfdx` removes them again. The repository's `psfdx.psm1` is not changed; the build adds the loader and a test checks the original code is inside the built file untouched.
- The build refuses version drift, a wildcard export, a function exported by two modules, a duplicate GUID, a prerelease, a manifest key it would not carry over, and a changed core GUID. `tests/Repository.Tests.ps1` also checks the manifests.
- The GitHub release zip is unchanged (separate modules plus the install scripts).

**What PowerShell allows, and what it doesn't.** PowerShell finds a module only as a folder of its own on the module path, and `Install-Module` puts one package in one folder. So in a brand-new session only `psfdx` is discoverable. Asking for it loads it, and loading it loads the rest. The effect, proved on Windows PowerShell 5.1 and PowerShell 7 by `Test-PsfdxSuite.ps1`:

| In a fresh session | Result |
| :--- | :--- |
| `Get-Command -Module psfdx` | the core commands only, Source `psfdx` |
| then `Get-Command -Module psfdx-logs`, then `Get-Command -Module 'psfdx*'` (the same session) | exactly the logs commands (Source `psfdx-logs`), then every command of the suite with each attributed to its own module, none missing, none twice |
| `Import-Module psfdx`, or the first core command (PowerShell loads `psfdx` itself), then any of the above | the same |
| `Get-Command -Module psfdx-logs` or `-Module 'psfdx*'` as the very first command, before `psfdx` has loaded | no non-core commands: those modules cannot be discovered until `psfdx` loads |
| a non-core command by name (`Get-SalesforceDebugLogs`) before `psfdx` has loaded | not found; `Import-Module psfdx` first |

Listing every command in the `psfdx` manifest would make non-core commands autoload by name, but it would label every command `psfdx` before the first import and `Get-Command -Module psfdx` would no longer show only the core. That trade was made on purpose (issue 267); to change it, change what `FunctionsToExport` the build writes.

`CD - Publish to PowerShell Gallery` runs when a release is published. It checks the tag against `VERSION` and the manifests, checks `CI - Pester tests` passed on the pull request that was merged, builds the package, skips if that version is already on the Gallery (versions can't be replaced, so it never retries with a changed package), and publishes with `Publish-PSResource` using the `PSGALLERY_API_KEY` secret from the protected `psgallery` environment. `CI - Gallery install check` then installs the published version on three legs with one `Save-Module` and runs `scripts/release/Test-PsfdxSuite.ps1` and the help check against it. Before any release, `CI - Suite install` runs the same checks on every pull request that changes a module or `scripts/release`: it builds the package, publishes it to a folder repository as a real NuGet package, and installs it with PowerShellGet on Ubuntu, Windows PowerShell 7 and Windows PowerShell 5.1, plus an upgrade, `Update-Module` and a missing module folder (`Test-PsfdxSuiteUpgrade.ps1`); see [pipelines](pipelines.md).
**Publishing is on.** `scripts/release/gallery.json` says `"publish": true`, so each release uploads for real. If it is set back to `"publish": false`, the workflow runs everything up to `Publish-PSResource -WhatIf` and lists what it would publish, and the install check skips.

### Owner steps taken to switch publishing on (done; kept as a record and for rollback)

1. Confirm the name `psfdx` is free on the Gallery, or already yours.
2. Create the Gallery account and an API key scoped to the `psfdx` package only, with push rights and the shortest expiry you accept. Store it as the Actions secret `PSGALLERY_API_KEY` in a protected environment named `psgallery`, limited to the `main` branch and `v*` tags (release-triggered runs use the tag as their ref, so a `main`-only rule would block them). Keep it out of the Matrix container entirely.
3. Choose a licence and add a `LICENSE` file and `LicenseUri` (done: MIT, PSF-32).
4. In one pull request (a person must merge it): set `"publish": true` in `scripts/release/gallery.json`; set `delivery.psGallery.enabled` to `true` in `tools/matrix-linux/worker.config.json` so the final comment carries the install command and Done waits for the Gallery; add `www.powershellgallery.com` to `tools/matrix-linux/squid/squid.conf` (the delivery check reads the Gallery); rebuild the container; and add the changelog bullet "psfdx is now on the PowerShell Gallery: install it with `Install-Module psfdx`."

Don't set `delivery.psGallery.enabled` before publishing is on: Done would wait for a package that is never uploaded.

### Rolling back

A published Gallery version is permanent. To stop further uploads, set `"publish": false` in `scripts/release/gallery.json` (the workflow goes back to a dry run) and set `delivery.psGallery.enabled` back to `false` in `tools/matrix-linux/worker.config.json`. To hide a bad version, unlist it on powershellgallery.com (the API key is not allowed to unlist). To rotate the key, create a new one, replace the `PSGALLERY_API_KEY` secret and delete the old key; keys expire after 180 days.
