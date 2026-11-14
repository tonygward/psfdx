---
id: AUTO-02
priority: high
effort: medium
dependencies: ["AUTO-01"]
conflicts: []
---

# AUTO-02: CI named by kind, one version number

Tracking issue: create `AUTO-02: CI named by kind, one version number` and link it here.

## Objective and user value

Give every pull request one trustworthy result the merge gate can rely on. Matrix runs Pester on PowerShell 7 in its Linux container before pushing (AUTO-07); CI is the wider check on more platforms, including Windows and Windows PowerShell 5.1, which the container can't run. Give psfdx one version number, so releases (AUTO-03) have something to bump.

## Current behaviour

- `.github/workflows/ci.yml` is named `CI` and runs Pester on `ubuntu-latest` only, on pull requests only.
- The manifests declare `PowerShellVersion = '5.1'` and `CompatiblePSEditions = @('Desktop','Core')`, but nothing tests 5.1. PR #87 fixed a module that didn't load on 5.1 at all.
- Each of the seven manifests carries `ModuleVersion = '0.8'` separately. There is no `VERSION` file.
- `claude.yml` and `claude-code-review.yml` exist and are not CI.

## Desired behaviour

### Workflows named by kind

Port the naming rule from the reference [pipelines document](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/docs/pipelines.md): every workflow name starts with `CI`, `Gate`, `CD` or `Housekeeping`. Write `docs/pipelines.md` for psfdx with the same two tables (prefixes, then workflows) and a **Names other things depend on** section. Rename:

- `ci.yml` → name `CI - Pester tests`.
- `claude.yml` → `Housekeeping - Claude on mention`; `claude-code-review.yml` → `Housekeeping - Claude code review`. These are advisory and never required by the gate.

### CI - Pester tests

- Triggers: `pull_request` to `main`, plus `workflow_dispatch`.
- **Docs-only changes get a quick run that tests nothing.** A first job classifies the changed files: if every file is Markdown, under `prompts/`, under `docs/`, or an image, it sets `docs_only=true` and the test jobs are skipped *at step level* (the job still reports success, so a required check never waits forever). Copy the approach in the reference [`build.yml`](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/.github/workflows/build.yml) change-detection job.
- Test legs, `fail-fast: false`:
  - `ubuntu-latest`, `pwsh`;
  - `windows-latest`, `pwsh`;
  - `windows-latest`, `shell: powershell` (Windows PowerShell 5.1).
- Pester pinned to 5.x on every leg (the reason is already in the workflow comment; keep it). On 5.1, install Pester 5 with `-SkipPublisherCheck` because Windows ships Pester 3.4.
- Each leg runs `Invoke-Pester -Path . -CI` and uploads `testResults.xml` as an artefact named for its leg.
- Stable job names, because branch protection and the gate match on them: `Changes`, `Pester (ubuntu, pwsh)`, `Pester (windows, pwsh)`, `Pester (windows, powershell 5.1)`.
- `permissions: contents: read`. Never `pull_request_target`.

If a test fails only on 5.1, fix the module code (that is a real bug) rather than skipping the leg. If that turns out large, mark the 5.1 leg `continue-on-error`, open `PSF-##` issues for each failure, and say so in the pull request.

### One version number

- Add `VERSION` at the repository root containing `0.8.0`.
- Set `ModuleVersion = '0.8.0'` in all seven manifests (`psfdx-shared` included).
- Add `tests/Repository.Tests.ps1` (Pester) that fails if:
  - any manifest's `ModuleVersion` differs from `VERSION`;
  - `VERSION` isn't three numeric parts;
  - `CHANGELOG.md` doesn't start with `# Changelog` followed by `## Unreleased`;
  - any workflow's `name:` doesn't start with `CI - `, `Gate - `, `CD - ` or `Housekeeping - `;
  - any prompt in `prompts/` (not `done/`) has a `status:`, `execution:` or `model:` front-matter line.
- Make sure `Invoke-Pester -Path .` picks the new test up and it runs on 5.1 (no `??`, no three-argument `Join-Path`).
- Add `testResults.xml` to `.gitignore` and remove the committed copy.

## Implementation guidance

- Read the manifests with `Import-PowerShellDataFile`, which works on 5.1.
- Don't change any cmdlet behaviour in this pull request unless a 5.1 test failure forces it.

## Acceptance criteria

- A docs-only pull request shows all four checks green within a minute or two and runs no Pester.
- A change to a `.psm1` runs all three Pester legs.
- Every workflow name follows the prefix rule and `docs/pipelines.md` lists each one.
- `VERSION` and all manifests say `0.8.0`; the repository test enforces it.
- The pull request lists the exact check names to require in branch protection (an owner step).

## Tests

- `tests/Repository.Tests.ps1` as above, passing on all three legs.
- Prove the docs-only path with a throwaway commit on the branch that only touches Markdown (revert it before merge) and link both runs in the pull request.

## Dependencies and risks

- Depends on AUTO-01 (the policy names these workflows).
- Windows runners cost more minutes than Linux. psfdx is public, so Actions minutes are free; note it anyway.

## Release expectations

Not user-facing; no changelog entry. The version format change (`0.8` → `0.8.0`) is internal.
