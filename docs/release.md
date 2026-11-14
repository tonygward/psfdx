# Releases

How a merge becomes a release. The rules are in the [execution policy](execution-policy.md); the workflows are listed in [pipelines](pipelines.md).

## From merge to release

1. A pull request merges to `main` after `CI - Pester tests` passed on its head commit.
2. `CD - Bump version` runs. It skips bump commits and docs-only merges. Otherwise it checks that CI passed on the pull request's exact head commit (waiting up to 15 minutes), then runs `scripts/release/bump.mjs`.
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

The Gallery gets **one** package, `psfdx`, containing every module, so users run `Install-Module psfdx` and `Import-Module psfdx`. The repository keeps its seven separate modules; `scripts/release/Build-GalleryPackage.ps1` assembles `out/psfdx/` from them:

- Each module folder (without tests) is copied in as a subfolder. The core module (`psfdx/`) becomes the nested module `psfdx-core` with its own GUID; the bundle keeps the core module's GUID (`2785d2bf-775f-4f2b-9d00-ee98f0163cf0`) so the Gallery identity is stable.
- The generated bundle manifest has the version from `VERSION`, lists `psfdx-shared` first in `NestedModules`, and exports the union of every module's `FunctionsToExport` by explicit name. The build fails if two modules export the same function.
- Gallery metadata (tags, project and icon links) is read from the core manifest's `PrivateData.PSData`. There is no `LicenseUri` yet because the repository has no licence file.
- The GitHub release zip is unchanged (separate modules plus the install scripts).

`CD - Publish to PowerShell Gallery` runs when a release is published. It checks the tag against `VERSION` and the manifests, checks `CI - Pester tests` passed on the pull request that was merged, builds the bundle, skips if that version is already on the Gallery (versions can't be replaced, so it never retries with a changed package), and publishes with `Publish-PSResource` using the `PSGALLERY_API_KEY` secret from the protected `psgallery` environment. `CI - Gallery install check` then installs the published version on three legs and compares the commands with the manifests.

**It is a dry run until the owner flips it.** While `scripts/release/gallery.json` says `"publish": false`, the workflow runs everything up to `Publish-PSResource -WhatIf` and lists what it would publish, and the install check skips.

### Owner steps before flipping the switch

1. Confirm the name `psfdx` is free on the Gallery, or already yours.
2. Create the Gallery account and an API key scoped to the `psfdx` package only, with push rights and the shortest expiry you accept. Store it as the Actions secret `PSGALLERY_API_KEY` in a protected environment named `psgallery` that only `main` can use. Keep it out of the Matrix container entirely.
3. Choose a licence and add a `LICENSE` file and `LicenseUri`, if you want one shown on the Gallery.
4. In one pull request (a person must merge it): set `"publish": true` in `scripts/release/gallery.json`; set `delivery.psGallery.enabled` to `true` in `tools/matrix-linux/worker.config.json` so the final comment carries the install command and Done waits for the Gallery; add `www.powershellgallery.com` to `tools/matrix-linux/squid/squid.conf` (the delivery check reads the Gallery); rebuild the container; and add the changelog bullet "psfdx is now on the PowerShell Gallery: install it with `Install-Module psfdx`."

Don't set `delivery.psGallery.enabled` before publishing is on: Done would wait for a package that is never uploaded.
