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

1. Check the names `psfdx`, `psfdx-shared`, `psfdx-metadata`, `psfdx-development`, `psfdx-logs`, `psfdx-sandbox` and `psfdx-packages` are free on the Gallery, or already owned by the owner. If any is taken, stop and ask the owner.
2. Create the Gallery account and an API key **scoped to those package names only**, with push rights, and the shortest expiry the owner accepts. Store it as the Actions secret `PSGALLERY_API_KEY` in a protected environment `psgallery` that only `main` can use.
3. Decide (owner): publish **seven modules** with dependencies, or **one** `psfdx` module that bundles the rest as nested modules. The recommendation is seven, matching how users import them today, but the decision is the owner's.

### Module dependencies

- Make the manifests declare their real dependencies: each module except `psfdx-shared` lists `RequiredModules = @(@{ ModuleName = 'psfdx-shared'; RequiredVersion = 'X.Y.Z' })`, and `psfdx` too if others depend on it. The bump script (AUTO-03) keeps those versions in step with `VERSION`; extend its tests.
- Keep `Import-PsfdxSharedModule` working for people who install from a clone or the zip. Change all six copies together, as `CLAUDE.md` requires.
- Add the Gallery metadata to each manifest's `PrivateData.PSData`: `Tags`, `LicenseUri`, `ProjectUri`, `IconUri` (the existing logo in `images/`, by its raw GitHub link) and `ReleaseNotes` (a link to the release).
- Add a repository test that fails if a manifest is missing that metadata or its `RequiredModules` versions differ from `VERSION`.

### CD - Publish to PowerShell Gallery (`cd-publish-gallery.yml`)

- Trigger: `release` `published`, plus `workflow_dispatch` with a version for repairs. Runs in the `psgallery` environment on `ubuntu-latest` with `pwsh`.
- Check the release tag matches `VERSION` and the manifests, and that `CI - Pester tests` passed on the pull request merged into that version (the same exact-head check as AUTO-03). Otherwise fail and publish nothing.
- Run `Test-ModuleManifest` on every module.
- Publish in dependency order (`psfdx-shared` first) with `Publish-PSResource` (or `Publish-Module` if the owner prefers), `-ApiKey` from the secret, never printed.
- **Idempotent:** if a module is already on the Gallery at that version, skip it and say so; versions on the Gallery can't be replaced, so never retry with a changed package.
- Start with `-WhatIf` and a config switch `publish: false` so the first merge proves everything up to the upload; the owner flips it once.
- Add the workflow to `docs/pipelines.md` and the step to `docs/release.md`.

### Delivery

Turn on `delivery.psGallery.enabled` (AUTO-08), so the final comment includes `Install-Module psfdx -RequiredVersion X.Y.Z` and the Gallery link, and Done waits for the Gallery check.

### README

Add `Install-Module psfdx` as the first install option, keeping the clone and zip routes.

## Acceptance criteria

- With `publish: false`, a merge runs the workflow to the dry-run upload and reports what it would publish.
- With `publish: true`, the next release appears on the Gallery for every module at the same version, and `Install-Module psfdx -RequiredVersion X.Y.Z` in a clean CI job installs and imports it on PowerShell 7 and Windows PowerShell 5.1.
- No API key appears in any log, artefact or comment.
- A person must merge this pull request (workflows and secrets).

## Tests

- Repository tests for manifest metadata and dependency versions (they run in Matrix's local Pester and in CI).
- `node --test scripts/release` for the extended bump.
- A CI job, `CI - Gallery install check`, that runs after publishing: installs from the Gallery into a temporary module path on both PowerShell editions and imports each module.

## Dependencies and risks

- Depends on AUTO-03 (releases) and AUTO-08 (the delivery verifier switch).
- Gallery versions are permanent. A bad release can only be unlisted, not replaced, so the CI and local checks before it matter.
- The API key is a long-lived secret. Keep it scoped, in a protected environment, and out of the Matrix container entirely.

## Release expectations

User-facing: add a changelog bullet, "psfdx is now on the PowerShell Gallery: install it with `Install-Module psfdx`."
