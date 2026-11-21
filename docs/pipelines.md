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
| `CI - Website build` | `ci-site.yml` | CI | Pull requests changing `site/**` or `images/psfdx-logo.png`; runs the site tests, builds it and attaches the built site to the run |
| `CD - Bump version` | `cd-bump-version.yml` | CD | Push to `main`; see [releases](release.md) |
| `CD - Publish to PowerShell Gallery` | `cd-publish-gallery.yml` | CD | A GitHub release being published (or by hand); dry run until `scripts/release/gallery.json` says `"publish": true`; see [releases](release.md#powershell-gallery) |
| `CI - Salesforce CLI compatibility` | `ci-cli-compat.yml` | CI | Pull requests that touch a module or the check, every Monday, and by hand; installs the latest stable Salesforce CLI on Ubuntu and Windows and checks every `sf` command and flag psfdx uses against its `--help`; see [cli-compatibility](cli-compatibility.md) |
| `CI - Gallery install check` | `ci-gallery-install.yml` | CI | After the Gallery publish; installs `psfdx` from the Gallery on Ubuntu, Windows PowerShell 7 and Windows PowerShell 5.1, compares its commands with the manifests, and checks the help of every installed command (`scripts/release/Test-PsfdxHelp.ps1`) |
| `CD - Publish release` | `cd-publish-release.yml` | CD | Push of a `v*.*.*` tag; see [releases](release.md) |
| `Housekeeping - Scratch org integration smoke tests` | `housekeeping-integration.yml` | Housekeeping | By hand (the owner approves the `scratch-org-integration` environment), or weekly if the repository variable `PSFDX_INTEGRATION_SCHEDULE` is `true`; never on pull requests. Creates a one-day scratch org from a dedicated Dev Hub, runs `tests/integration` against it, always deletes it, and uploads a report; advisory, never required by the gate. See [integration testing](integration-testing.md) |
| `Housekeeping - Claude on mention` | `claude.yml` | Housekeeping | `@claude` mentions |
| `Housekeeping - Claude code review` | `claude-code-review.yml` | Housekeeping | Pull requests |

## CI - Pester tests

A first job, `Changes`, classifies the changed files. If no changed file can affect the Pester suite, it sets `docs_only=true`. That is every file that is Markdown, under `prompts/`, `docs/` or `images/`, an image, or under `tools/` (except the Matrix launcher's PowerShell, which Pester tests). The rule is `scripts/release/changes.mjs` (`node scripts/release/changes.mjs tests`), the same file `CD - Bump version` uses to decide whether a change ships. The test jobs then skip their steps (the job itself still succeeds), so a required check never waits forever.

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

Runs from `main`'s own copy and never checks out pull request code. It only runs when the repository variable `MATRIX_AUTOMERGE_ENABLED` is `true`. The decision is the pure function in `scripts/matrix/automerge.mjs`; the identities are in `scripts/matrix/gate.config.json`: `agentLogin` (the worker account, which opens task and core pull requests) and `releaseLogin` (the owner identity behind `RELEASE_TOKEN`, which opens the archive pull requests). It merges (squash, with `RELEASE_TOKEN`, matching the exact head commit) only when every rule holds, and otherwise comments once per commit with the reasons. There are four lanes:

- **Task:** branch `matrix/PSF-##-...` or `matrix/AUTO-##-...`, opened by the agent, with a `Matrix job:` line in the description. Files only under `psfdx*/` (module tests live there), `prompts/`, `images/`, `README.md`, `CHANGELOG.md` and `modules.ps1`. Never `docs/`, the root `tests/`, `scripts/`, `tools/` or `.github/`.
- **Core:** branch `matrix/core/<name>` with the statement `Matrix core change: owner-approved lane`. Files only under `tools/matrix/` (code, JSON, Markdown and its tests), `tools/matrix-linux/worker.config.json` and `tools/matrix-linux/README.md` (the Dockerfile, scripts, proxy allow-list and version pins stay with a person). The execution policy and every other file under `docs/` stay with a person too. It waits for `CI - Matrix orchestration tests` unless only Markdown changed.
- **Archive:** branch `housekeeping/archive-<ID>` with the statement `Housekeeping: archive merged prompt`, touching only `prompts/`.
- **Owner:** branch `infra/<name>` or `docs/<name>`, opened by `releaseLogin` (the owner's own account), with the statement `Owner change: infrastructure auto-merge lane`. It may change `docs/`, the root `tests/`, `scripts/` and `tools/` (except the parts listed next), `images/`, `prompts/`, `README.md`, `CHANGELOG.md` and the `ci-*.yml` workflows. It never covers the product (`psfdx*/`, `modules.ps1`, installers, `VERSION`), the gate and its identities (`gate-*`, `ci-matrix-gate.yml`, `scripts/matrix/`), the release and publish machinery (`cd-*`, `scripts/release/`), `claude*.yml`, the Matrix container files other than its README and `worker.config.json`, or `docs/execution-policy.md`. Those need a person. Besides the usual rules, every other workflow run for the commit must have finished and succeeded, and the gate wakes when `CI - Salesforce CLI compatibility`, `CI - Release scripts` or `CI - Matrix gate tests` finishes last, so a slow run is waited for.

In every lane the `CI - Pester tests` run must have succeeded for the pull request's exact head commit with all four required jobs successful (not skipped), and no other non-advisory run for that commit may have failed. Fork pull requests never merge.

## Housekeeping - Archive merged prompt

After a `matrix/` pull request merges, moves `prompts/<ID>-*.md` to `prompts/done/` on a `housekeeping/archive-<ID>` branch and opens a docs-only pull request, which the gate merges after the quick CI run. Archive merges never cause a version bump. Run it by hand with a pull request number (and the task ID) to repair or to archive a prompt merged by a person.
