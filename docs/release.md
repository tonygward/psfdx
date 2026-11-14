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
