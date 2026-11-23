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

Users run `Install-Module psfdx` and `Import-Module psfdx` whichever layout is live. `scripts/release/Build-GalleryPackage.ps1` builds what is published from the repository's separate modules (one folder, manifest, `.psm1` and test file each), in one of two layouts. `scripts/release/gallery.json` says which one is published (`"layout": "bundle"` or `"suite"`); the installer-facing guide is [install.md](install.md).

**Bundle (live today).** One package, `psfdx`, with every module inside it as a nested module. Each module folder (without tests) is copied in as a subfolder; the generated manifest has the version from `VERSION`, lists `psfdx-shared` first in `NestedModules`, and exports the union of every module's `FunctionsToExport` by explicit name. The build fails if two modules export the same function. Every command's `Source` is `psfdx`.

**Suite (built and tested by CI, not published yet).** Nine packages: `psfdx` is an umbrella with no code and no exports, and each module is a package under its own name (`psfdx-core`, `psfdx-shared`, `psfdx-metadata`, `psfdx-development`, `psfdx-logs`, `psfdx-sandbox`, `psfdx-packages`, `psfdx-agentforce`). Every module package gets a generated manifest whose `RequiredModules` lists the modules in `Get-PsfdxModuleDependencies` (`modules.ps1`) at the exact version of this release, with their GUIDs; the umbrella requires every module the same way. So `Install-Module psfdx` installs all nine, `Get-Module -ListAvailable 'psfdx*'` lists them, and `Get-Command -Module 'psfdx*'` shows each command under the module that holds it. The umbrella keeps the GUID `2785d2bf-775f-4f2b-9d00-ee98f0163cf0`, so the Gallery identity of `psfdx` does not change. The build refuses a dependency loop, a dependency on a module that is not in the repository, a module missing from the map, version drift, a duplicate export or GUID, a wildcard export, a prerelease, and a manifest key it would drop. `tests/Repository.Tests.ps1` checks the map against what each module's code actually calls.

Both layouts read the Gallery metadata (tags, project, icon and licence links) from the core manifest's `PrivateData.PSData` and ship the MIT `LICENSE` in every package. The GitHub release zip is unchanged (separate modules plus the install scripts).

`CD - Publish to PowerShell Gallery` runs when a release is published. It checks the tag against `VERSION` and the manifests, checks `CI - Pester tests` passed on the pull request that was merged, builds the packages for the layout in `gallery.json`, and publishes with `Publish-PSResource` using the `PSGALLERY_API_KEY` secret from the protected `psgallery` environment. For the bundle it skips if that version is already on the Gallery. For the suite, `scripts/release/Publish-PsfdxSuite.ps1` publishes the packages in dependency order, the umbrella last, skips any package whose version is already listed, and waits until the Gallery lists each package before it publishes the next one that requires it; if it stops half way, run it again (a manual run with the same version) and it carries on. Gallery versions are permanent, so it never retries with a changed package. `CI - Gallery install check` then installs the published version on three legs: for the bundle it compares the commands with the manifests; for the suite it runs `scripts/release/Test-PsfdxSuite.ps1`. Before any of that, `CI - Suite install` runs the whole suite flow on every pull request that changes a module or `scripts/release`, against a folder repository instead of the Gallery (see [pipelines](pipelines.md)).

### Switching the Gallery from the bundle to the suite

This is an owner decision, and it needs one thing only the owner can do: the current API key is scoped to the package `psfdx`, and the suite publishes eight packages under new names that the Gallery has not seen. Names are claimed by the first upload and versions are permanent, so do these in order:

1. Check the eight names are free (or yours): `psfdx-core`, `psfdx-shared`, `psfdx-metadata`, `psfdx-development`, `psfdx-logs`, `psfdx-sandbox`, `psfdx-packages`, `psfdx-agentforce`. They were free when the suite was built.
2. Create a new API key (or widen the old one) that can push these nine packages: the glob `psfdx*` with push rights and the shortest expiry you accept. Replace the `PSGALLERY_API_KEY` secret in the `psgallery` environment. Keep it out of the Matrix container.
3. In one pull request: set `"layout": "suite"` in `scripts/release/gallery.json`, add the changelog bullet that the modules are now separate packages (so `Get-Command -Module 'psfdx*'` shows each command's own module), and merge it. The next release publishes the suite.
4. Watch `CD - Publish to PowerShell Gallery` and then `CI - Gallery install check`. Only then close the ticket. If the publish stops part way, run it again by hand with the same version; nothing is published twice.

The first suite release replaces the bundle at a higher `psfdx` version, so `Update-Module psfdx` upgrades existing users (see [install.md](install.md#updating)). Older bundle versions stay on the Gallery.
**Publishing is on.** `scripts/release/gallery.json` says `"publish": true`, so each release uploads for real. If it is set back to `"publish": false`, the workflow runs everything up to `Publish-PSResource -WhatIf` and lists what it would publish, and the install check skips.

### Owner steps taken to switch publishing on (done; kept as a record and for rollback)

1. Confirm the name `psfdx` is free on the Gallery, or already yours.
2. Create the Gallery account and an API key scoped to the `psfdx` package only, with push rights and the shortest expiry you accept. Store it as the Actions secret `PSGALLERY_API_KEY` in a protected environment named `psgallery`, limited to the `main` branch and `v*` tags (release-triggered runs use the tag as their ref, so a `main`-only rule would block them). Keep it out of the Matrix container entirely.
3. Choose a licence and add a `LICENSE` file and `LicenseUri` (done: MIT, PSF-32).
4. In one pull request (a person must merge it): set `"publish": true` in `scripts/release/gallery.json`; set `delivery.psGallery.enabled` to `true` in `tools/matrix-linux/worker.config.json` so the final comment carries the install command and Done waits for the Gallery; add `www.powershellgallery.com` to `tools/matrix-linux/squid/squid.conf` (the delivery check reads the Gallery); rebuild the container; and add the changelog bullet "psfdx is now on the PowerShell Gallery: install it with `Install-Module psfdx`."

Don't set `delivery.psGallery.enabled` before publishing is on: Done would wait for a package that is never uploaded.

### Rolling back

A published Gallery version is permanent. To stop further uploads, set `"publish": false` in `scripts/release/gallery.json` (the workflow goes back to a dry run) and set `delivery.psGallery.enabled` back to `false` in `tools/matrix-linux/worker.config.json`. To hide a bad version, unlist it on powershellgallery.com (the API key is not allowed to unlist). To rotate the key, create a new one, replace the `PSGALLERY_API_KEY` secret and delete the old key; keys expire after 180 days.
