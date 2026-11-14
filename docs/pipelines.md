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
| `CI - Release scripts` | `ci-release-scripts.yml` | CI | Pull requests changing `scripts/release/**` or the CD workflows |
| `CD - Bump version` | `cd-bump-version.yml` | CD | Push to `main`; see [releases](release.md) |
| `CD - Publish release` | `cd-publish-release.yml` | CD | Push of a `v*.*.*` tag; see [releases](release.md) |
| `Housekeeping - Claude on mention` | `claude.yml` | Housekeeping | `@claude` mentions |
| `Housekeeping - Claude code review` | `claude-code-review.yml` | Housekeeping | Pull requests |

## CI - Pester tests

A first job, `Changes`, classifies the changed files. If every file is Markdown, under `prompts/` or `docs/`, or an image, it sets `docs_only=true`. The test jobs then skip their steps (the job itself still succeeds), so a required check never waits forever.

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
