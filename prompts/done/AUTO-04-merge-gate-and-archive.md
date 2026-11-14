---
id: AUTO-04
priority: high
effort: medium
dependencies: ["AUTO-03"]
conflicts: []
---

# AUTO-04: Merge gate and prompt archive

Tracking issue: create `AUTO-04: Merge gate and prompt archive` and link it here.

## Objective and user value

Let Matrix pull requests merge themselves once CI has passed on the exact commit under review and every safety rule holds, while anything that could widen Matrix's own powers still needs a person. Archive each finished prompt so it can never be selected again.

## Current behaviour

Every pull request is merged by hand. There is no prompt archive step.

## Desired behaviour

Port the reference gate: [`scripts/matrix/automerge.mjs`](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/scripts/matrix/automerge.mjs), [`gate-cli.mjs`](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/scripts/matrix/gate-cli.mjs), [`matrix-auto-merge.yml`](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/.github/workflows/matrix-auto-merge.yml), [`archive-cli.mjs`](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/scripts/matrix/archive-cli.mjs) and [`matrix-archive-prompt.yml`](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/.github/workflows/matrix-archive-prompt.yml), and their tests in [`test/`](https://github.com/tonygward/audio-plugins/tree/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/test).

### Gate - Matrix auto-merge (`gate-auto-merge.yml`)

- Trigger: `workflow_run` on `CI - Pester tests` (and later `CI - Matrix orchestration tests`) with `types: [completed]`. The workflow runs `main`'s own copy of the gate and **never checks out pull request code**.
- The pure decision lives in `scripts/matrix/automerge.mjs` and returns `{ merge: boolean, reasons: string[] }`. Merge only when **every** rule holds:
  1. The run concluded `success` and every required job in it succeeded (not skipped at job level).
  2. The run's `head_sha` equals the pull request's current head (no stale results).
  3. The pull request is open, not draft-blocked by a person (Matrix opens drafts and marks them ready itself), targets `main`, and comes from a branch **in this repository** (`head.repo.full_name` equals the base repository). Fork pull requests never merge.
  4. The author is the agent identity in the gate config (`scripts/matrix/gate.config.json`: `agentLogin`) and the branch starts with `matrix/`.
  5. Every changed file is inside the allowed scope: module folders (`psfdx*/**`), `tests/**`, `README.md`, `CHANGELOG.md`, `modules.ps1`, `prompts/**`, `docs/**` and `images/**`. Anything else (`.github/**`, `scripts/**`, `tools/**`, `install*.ps1`, `uninstall*.ps1`, `VERSION`, `.gitignore`, the Dockerfile, the egress allow-list) blocks the merge with a reason.
  6. No other workflow run for that head commit failed.
- **Core lane** for Matrix's own code, as in the reference: a branch `matrix/core/<name>` whose description contains `Matrix core change: owner-approved lane` may change `tools/matrix/*.mjs|json|md`, `tools/matrix/tests/**`, `tools/matrix-linux/worker.config.json` and `docs/execution-policy.md`, and merges after `CI - Matrix orchestration tests` passes on its exact head. The gate itself, workflows, scripts, the Dockerfile and the egress allow-list are never in any lane.
- Merge with a squash merge using `RELEASE_TOKEN` (so the push to `main` triggers `CD - Bump version`). Post one comment with the reasons when the gate declines a Matrix pull request, deduplicated by a hidden marker containing the head commit.

### Housekeeping - Archive merged prompt (`housekeeping-archive-prompt.yml`)

- Trigger: `pull_request` `closed` with `merged == true`, from a `matrix/` branch, plus `workflow_dispatch` with a pull request number for repairs.
- Find the task ID from the branch (`matrix/AUTO-07-...` → `AUTO-07`) and the matching active prompt `prompts/<ID>-*.md`. Move it to `prompts/done/` with `git mv`, update the links in `prompts/README.md` (the row leaves Open prompts; a link appears under the archive), and fix any relative links inside the moved file.
- Commit as `[archive] <ID>` on a `housekeeping/archive-<ID>` branch and open a pull request; that pull request is docs-only, so the gate merges it on the quick CI run. (Pushing straight to `main` would bypass branch protection.)
- Archive commits and pull requests never trigger a version bump (docs-only).

### Tests and naming

- `CI - Matrix gate tests` (`ci-matrix-gate.yml`): `node --test scripts/matrix test` on pull requests touching `scripts/matrix/**`, `test/**` or the gate and archive workflows.
- Port the reference naming test: fail if a workflow name doesn't follow the `CI`/`Gate`/`CD`/`Housekeeping` rule, if a `workflow_run` trigger names a workflow that doesn't exist, or if the gate's run-name constants drift from the workflow files.

## Implementation guidance

- Node 24, no npm packages. The CLIs read the event payload and call the GitHub REST API with `fetch`; keep every decision in pure functions that take plain objects, so the tests need no network.
- Use `GITHUB_TOKEN` with `actions: read`, `pull-requests: read` to evaluate and `RELEASE_TOKEN` only for the merge itself.
- Log the decision and every reason in the job summary.

## Acceptance criteria

- Unit tests cover each rule, both lanes, a fork pull request, a stale head, a skipped job, a disallowed file and a non-agent author.
- A person's pull request is never merged automatically.
- Docs: add both workflows to `docs/pipelines.md`, and list what needs a person in `docs/execution-policy.md` part 5.

## Tests

`node --test scripts/matrix test`, run on all three operating systems in `CI - Matrix gate tests`.

## Dependencies and risks

- Depends on AUTO-03 (`RELEASE_TOKEN`, the bump workflow the merge triggers).
- Owner step: set `agentLogin`. Until a bot account exists the agent token is the owner's identity, so rule 4 also requires the `matrix/` branch prefix **and** a `Matrix job:` line in the description written by the worker. Note in the pull request that a bot account would make rule 4 stronger.
- This pull request changes workflows and the gate, so a person must merge it.

## Release expectations

Not user-facing; no changelog entry.
