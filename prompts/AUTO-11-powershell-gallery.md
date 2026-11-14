---
id: AUTO-11
priority: medium
effort: medium
dependencies: ["AUTO-03", "AUTO-08"]
conflicts: []
---

# AUTO-11: Publish releases to the PowerShell Gallery

Tracking issue: create `AUTO-11: Publish releases to the PowerShell Gallery` and link it here. **Put the card in Backlog**: the owner hasn't set up a Gallery account or API key yet, so this waits until they move it to Todo.

## Objective and user value

Users install and update psfdx with `Install-Module psfdx` and `Update-Module psfdx` instead of cloning the repository or downloading a zip. Every release that passed CI reaches the Gallery automatically.

## Current behaviour

After AUTO-03, each source merge produces a GitHub release `vX.Y.Z` with one zip. Nothing is published to the Gallery. Each module finds `psfdx-shared` through `Import-PsfdxSharedModule`, a function copied at the top of every `.psm1`, rather than through `RequiredModules`.

## Desired behaviour

Order: Matrix tests in its container → GitHub CI passes on the pull request → merge → version bump and tag → `CD - Publish release` creates the GitHub release → **`CD - Publish to PowerShell Gallery`** publishes the same version.

### Before any code: owner steps (record outcomes in the pull request)

1. Check the name `psfdx` is free on the Gallery, or already owned by the owner. If it is taken, stop and ask the owner.
2. Create the Gallery account and an API key **scoped to the `psfdx` package only**, with push rights, and the shortest expiry the owner accepts. Store it as the Actions secret `PSGALLERY_API_KEY` in a protected environment `psgallery` that only `main` can use.

### One bundled module (owner decision, 14 November 2026)

The Gallery gets **one** package, `psfdx`, containing every module. Users run `Install-Module psfdx` and `Import-Module psfdx` and get every cmdlet. The separate modules stay as they are in the repository (one folder, manifest, `.psm1` and test file each), so development and the cmdlet checklist don't change.

- **Build step, not a repository restructure.** Add `scripts/release/Build-GalleryPackage.ps1`, which assembles `out/psfdx/` from the repository:
  - copies each module folder (except the tests) into `out/psfdx/` as a subfolder;
  - generates the bundle manifest `out/psfdx/psfdx.psd1` from the core `psfdx/psfdx.psd1`: same `ModuleVersion` (from `VERSION`), `GUID`, author and compatibility. `NestedModules` lists `psfdx-shared` first, then the core module and the five others by their manifests. `FunctionsToExport` is the union of every module's `FunctionsToExport` (explicit names, never `*`). `RootModule` is unset or a small bundle `.psm1`;
  - fails if two modules export the same function name.
- **The repository's `psfdx/` folder is the core module and is also called psfdx.** The generated bundle manifest replaces it only inside `out/`; the core module becomes a nested module there under its own folder. Keep the core manifest's `GUID` for the bundle so the Gallery identity is stable, and give the nested core module a different `GUID` in the generated copy (record both in the script).
- **`Import-PsfdxSharedModule`:** each `.psm1` imports `psfdx-shared` itself. Make sure it works both standalone (clone or zip install, separate modules) and nested in the bundle, where `psfdx-shared` is a sibling folder that is already loaded. Prefer "already loaded? use it; otherwise load from the sibling folder, then by name". Change all six copies together, as `CLAUDE.md` requires.
- **Gallery metadata** goes in the bundle manifest's `PrivateData.PSData`: `Tags` (`Salesforce`, `SalesforceDX`, `sf`, `CLI`, `PSEdition_Desktop`, `PSEdition_Core`, `Windows`, `Linux`, `MacOS`), `LicenseUri`, `ProjectUri`, `IconUri` (the existing logo in `images/`, by its raw GitHub link) and `ReleaseNotes` (a link to the GitHub release). Keep the source for these values in one place the script reads (the core manifest is fine).
- **Repository tests** (they run in Matrix's local Pester and in CI): the bundle builds; `Test-ModuleManifest` passes on it; importing it in a fresh session exposes every function listed in every module manifest and nothing else; no duplicate exports; the bundle version equals `VERSION`.
- The GitHub release zip from AUTO-03 stays as it is (separate modules plus the install scripts) unless the owner asks for the bundle there too. Note this in the pull request.

### CD - Publish to PowerShell Gallery (`cd-publish-gallery.yml`)

- Trigger: `release` `published`, plus `workflow_dispatch` with a version for repairs. Runs in the `psgallery` environment on `ubuntu-latest` with `pwsh`.
- Check the release tag matches `VERSION` and the manifests, and that `CI - Pester tests` passed on the pull request merged into that version (the same exact-head check as AUTO-03). Otherwise fail and publish nothing.
- Build the bundle with `Build-GalleryPackage.ps1` and run `Test-ModuleManifest` on it.
- Publish `out/psfdx` with `Publish-PSResource` (or `Publish-Module` if the owner prefers), `-ApiKey` from the secret, never printed.
- **Idempotent:** if `psfdx` is already on the Gallery at that version, skip and say so; versions on the Gallery can't be replaced, so never retry with a changed package.
- Start with `-WhatIf` and a config switch `publish: false` so the first merge proves everything up to the upload; the owner flips it once.
- Add the workflow to `docs/pipelines.md` and the step to `docs/release.md`.

### Delivery

Turn on `delivery.psGallery.enabled` (AUTO-08), so the final comment includes `Install-Module psfdx -RequiredVersion X.Y.Z` and the Gallery link, and Done waits for the Gallery check.

### README

Add `Install-Module psfdx` as the first install option, keeping the clone and zip routes.

## Acceptance criteria

- With `publish: false`, a merge runs the workflow to the dry-run upload and reports what it would publish.
- With `publish: true`, the next release appears on the Gallery as one `psfdx` package at that version, and `Install-Module psfdx -RequiredVersion X.Y.Z` in a clean CI job installs it, and `Import-Module psfdx` exposes every cmdlet, on PowerShell 7 and Windows PowerShell 5.1.
- No API key appears in any log, artefact or comment.
- A person must merge this pull request (workflows and secrets).

## Tests

- Repository tests for the bundle as listed above (they run in Matrix's local Pester and in CI, on both PowerShell editions).
- A CI job, `CI - Gallery install check`, that runs after publishing: installs `psfdx` from the Gallery into a temporary module path on both PowerShell editions, imports it, and checks the exported command list matches the manifests.

## Dependencies and risks

- Depends on AUTO-03 (releases) and AUTO-08 (the delivery verifier switch).
- Gallery versions are permanent. A bad release can only be unlisted, not replaced, so the CI and local checks before it matter.
- The API key is a long-lived secret. Keep it scoped, in a protected environment, and out of the Matrix container entirely.

## Release expectations

User-facing: add a changelog bullet, "psfdx is now on the PowerShell Gallery: install it with `Install-Module psfdx`."
