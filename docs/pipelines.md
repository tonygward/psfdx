# psfdx pipelines

Every workflow name starts with one of four prefixes, so its kind is clear at a glance. `tests/Repository.Tests.ps1` fails if a workflow breaks the rule. The rules the pipelines serve are in the [execution policy](execution-policy.md).

## Prefixes

| Prefix | Meaning | Required by the gate |
|---|---|---|
| `CI - ` | Builds and tests a pull request | Yes |
| `Gate - ` | Decides whether a pull request may merge (AUTO-04) | Yes |
| `CD - ` | Versions, releases and publishes after a merge (AUTO-03, AUTO-11) | No |
| `Housekeeping - ` | Advisory helpers | Never |

## Workflows

| Workflow | File | Kind | Runs on |
|---|---|---|---|
| `CI - Pester tests` | `ci.yml` | CI | Pull requests to `main`, and manual runs |
| `CI - Matrix orchestration tests` | `ci-matrix-tests.yml` | CI | Pull requests changing `tools/matrix/**` (Markdown excluded); Ubuntu, Windows and macOS |
| `CI - Matrix gate tests` | `ci-matrix-gate.yml` | CI | Pull requests changing `scripts/matrix/**` or the gate and archive workflows; Ubuntu, Windows and macOS |
| `Gate - Matrix auto-merge` | `gate-auto-merge.yml` | Gate | After `CI - Pester tests` completes; see below |
| `Housekeeping - Archive merged prompt` | `housekeeping-archive-prompt.yml` | Housekeeping | A merged `matrix/` pull request, or by hand |
| `CI - Release scripts` | `ci-release-scripts.yml` | CI | Pull requests changing `scripts/release/**` or the CD workflows |
| `CD - Bump version` | `cd-bump-version.yml` | CD | Push to `main`; see [releases](release.md) |
| `CD - Publish release` | `cd-publish-release.yml` | CD | Push of a `v*.*.*` tag; see [releases](release.md) |
| `Housekeeping - Claude on mention` | `claude.yml` | Housekeeping | `@claude` mentions |
| `Housekeeping - Claude code review` | `claude-code-review.yml` | Housekeeping | Pull requests |

## CI - Pester tests

A first job, `Changes`, classifies the changed files. If every file is Markdown, under `prompts/`, `docs/` or `tools/`, or an image, it sets `docs_only=true`. The test jobs then skip their steps (the job itself still succeeds), so a required check never waits forever.

Pester is pinned to 5.x on every leg: the tests use `Assert-MockCalled`, which Pester 6 can't load. On Windows PowerShell 5.1, Pester 5 is installed with `-SkipPublisherCheck` because Windows ships Pester 3.4. Each leg uploads its `testResults.xml`.

## Names other things depend on

Branch protection and the merge gate match these check names exactly. Don't rename them without updating both.

- `Changes`
- `Pester (ubuntu, pwsh)`
- `Pester (windows, pwsh)`
- `Pester (windows, powershell 5.1)`

The workflow name `CI - Pester tests` is also depended on.

## Cost

Windows runners use more minutes than Linux. psfdx is public, so Actions minutes are free.

## Gate - Matrix auto-merge

Runs from `main`'s own copy and never checks out pull request code. It only runs when the repository variable `MATRIX_AUTOMERGE_ENABLED` is `true`. The decision is the pure function in `scripts/matrix/automerge.mjs`; the agent identity is in `scripts/matrix/gate.config.json`. It merges (squash, with `RELEASE_TOKEN`, matching the exact head commit) only when every rule holds, and otherwise comments once per commit with the reasons. There are three lanes:

- **Task:** branch `matrix/PSF-##-...` or `matrix/AUTO-##-...`, opened by the agent, with a `Matrix job:` line in the description. Files only under `psfdx*/`, `tests/`, `prompts/`, `docs/`, `images/`, `README.md`, `CHANGELOG.md` and `modules.ps1`.
- **Core:** branch `matrix/core/<name>` with the statement `Matrix core change: owner-approved lane`. Files only under `tools/matrix/` (code, JSON, Markdown and its tests), `tools/matrix-linux/worker.config.json` and `docs/execution-policy.md`. It waits for `CI - Matrix orchestration tests` unless only Markdown changed.
- **Archive:** branch `housekeeping/archive-<ID>` with the statement `Housekeeping: archive merged prompt`, touching only `prompts/`.

In every lane the `CI - Pester tests` run must have succeeded for the pull request's exact head commit with all four required jobs successful (not skipped), and no other non-advisory run for that commit may have failed. Fork pull requests never merge.

## Housekeeping - Archive merged prompt

After a `matrix/` pull request merges, moves `prompts/<ID>-*.md` to `prompts/done/` on a `housekeeping/archive-<ID>` branch and opens a docs-only pull request, which the gate merges after the quick CI run. Archive merges never cause a version bump. Run it by hand with a pull request number (and the task ID) to repair or to archive a prompt merged by a person.
