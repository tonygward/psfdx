---
id: AUTO-03
priority: high
effort: medium
dependencies: ["AUTO-02"]
conflicts: []
---

# AUTO-03: Automatic patch versions and GitHub releases

Tracking issue: create `AUTO-03: Automatic patch versions and GitHub releases` and link it here.

## Objective and user value

Every change that reaches users becomes a numbered release with plain release notes and a single download, without anyone editing a version by hand. Users can see what changed and install a known version.

## Current behaviour

No tags or releases. Users install from a clone with `install.ps1`. `CHANGELOG.md` has a long `## Unreleased` section and nothing else. After AUTO-02 there is one `VERSION` file at `0.8.0`.

## Desired behaviour

Two CD workflows, ported from the reference [release checkpoints](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/docs/automatic-release-checkpoints.md), [`bump-beta.mjs`](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/scripts/release/bump-beta.mjs), [`auto-beta-version.yml`](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/.github/workflows/auto-beta-version.yml) and [`auto-publish-release.yml`](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/.github/workflows/auto-publish-release.yml). psfdx is simpler: no native build, so there is no second packaging build.

### CD - Bump version after a source merge (`cd-bump-version.yml`)

- Trigger: `push` to `main`.
- Skip (quiet success) when the pushed commit is itself a bump commit (subject starts with `[release] `), or when every changed file is docs-only by the same rule as CI.
- Find the merged pull request for the commit. Check `CI - Pester tests` passed on that pull request's **exact head commit**; if it is still running, wait up to 15 minutes; if it failed or is missing, fail loudly and bump nothing.
- Run `scripts/release/bump.mjs`, which:
  - reads `VERSION`, increases the third part (0.8.0 → 0.8.1);
  - writes the new value into `VERSION` and every manifest's `ModuleVersion`;
  - moves everything under `## Unreleased` into a new `## X.Y.Z - YYYY-MM-DD` section and leaves an empty `## Unreleased` on top. If `## Unreleased` is empty, writes `- Maintenance release.` instead of failing;
  - refuses to run if `VERSION` and the manifests already disagree.
- Commit as `[release] X.Y.Z` (author `psfdx release bot`), tag `vX.Y.Z`, push both with `RELEASE_TOKEN` so the push isn't blocked by branch protection and does trigger the next workflow. Use a concurrency group so two merges can't bump at once; the second rebases and bumps again.

### CD - Publish release (`cd-publish-release.yml`)

- Trigger: push of a tag `v*.*.*`.
- Check the tag matches `VERSION` and the manifests at that commit.
- Run Pester once on `ubuntu-latest` at the tag as a final check.
- Build `psfdx-X.Y.Z.zip` containing exactly the module folders listed in `modules.ps1` plus `psfdx-shared`, `install.ps1`, `install-windows.ps1`, `uninstall.ps1`, `uninstall-windows.ps1`, `modules.ps1`, `README.md`, `CHANGELOG.md` and `LICENSE` if present. No tests, prompts, docs or `.github`.
- Create the GitHub release `vX.Y.Z` with the notes taken from that version's changelog section and **exactly one asset**. Before finishing, list the release's assets and fail if there is anything other than that one zip. Re-running for an existing release is a no-op if it already matches, and a failure if it differs (never overwrite).

### Release notes for people

Add a rule to `CLAUDE.md` and the policy: any pull request with a change users will notice adds plain-language bullets under `## Unreleased`, prefixed with the module name as today. No commit hashes, pull request titles or prompt IDs. Mark breaking changes `Breaking:`.

### Docs

`docs/release.md`: the path from merge to release, what a release contains, and how the owner makes a minor or major bump (edit `VERSION` and the manifests in a normal pull request titled `[minor]`/`[major]`; the next bump then increases the third part from there). Add both workflows to `docs/pipelines.md`.

## Implementation guidance

- Node 24, no npm packages, for `bump.mjs`. Keep the pure logic (version arithmetic, changelog move, manifest rewrite) in functions with `node --test` tests in `scripts/release/bump.test.mjs`, separate from the Git and file I/O.
- Rewrite only the `ModuleVersion` line in each manifest with a careful regular expression; don't reformat the file.
- Add `CI - Release scripts` (`ci-release-scripts.yml`): runs `node --test scripts/release` on pull requests that change `scripts/release/**` or the CD workflows.

## Acceptance criteria

- Merging a source pull request produces, with no manual step: a `[release] 0.8.1` commit, tag `v0.8.1`, and a release with exactly one zip and notes from the changelog.
- A docs-only merge produces nothing.
- A merge whose pull request CI didn't pass on its head commit produces no bump and a red run that says why.
- The zip installs: a test extracts it to a temporary folder and checks every module manifest in it loads with `Test-ModuleManifest`.

## Tests

- `node --test scripts/release` covering: patch bump, empty Unreleased, manifests already out of step, changelog with and without existing versions, Windows line endings.
- A Pester or Node test for the zip contents list.

## Dependencies and risks

- Depends on AUTO-02 (`VERSION`, the docs-only rule, `CI - Pester tests`).
- Owner step: the `RELEASE_TOKEN` secret, and allowing it to bypass branch protection for the bump commit only.
- The first real run will be the next merge after this one. Say in the pull request that the end-to-end path is "not yet verified" until then.

## Release expectations

This pull request is a source change, so it triggers the first bump once merged. Add a changelog bullet: "Releases are now published on GitHub with a single zip to download."
