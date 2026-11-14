# Matrix for psfdx

Matrix is the trusted orchestrator that runs board-driven development for psfdx. The rules it follows are in the [execution policy](../../docs/execution-policy.md); this page says how the code is built. It is Node.js 24 with no npm packages, and every outside call (Git, Claude, the board) goes through an injected function so the tests need no network.

This page covers what exists so far: configuration, saved state, the prompt scan and the Claude usage gate. Later prompts add board pickup, the agent loop, delivery and the container, and extend this page.

## How it runs

Nothing here talks to the board or runs Claude to write code yet. The pieces are:

| File | What it does |
|---|---|
| `policy.mjs` | One place for the constants: 60% weekly usage limit, 02:00 London daily time, batch of one, Sonnet, 120 minutes per run, 3 repairs. Also `usageGate` and the London-day check. |
| `config.mjs`, `worker.example.json` | Loads and strictly validates the worker configuration. Unknown keys, wrong types, relative paths and a batch other than one are errors. |
| `state.mjs` | Crash-safe saved state, the lock file and the structured log. |
| `backlog.mjs` | Reads prompts from the fetched base branch, parses the restricted front matter and decides what is selectable. |
| `usage.mjs` | The Claude usage gate. |
| `budget.mjs` | The run time, repair and token budgets. |
| `process.mjs` | Runs child processes with no shell, a timeout, bounded output and process-tree kill. |

Run the tests with `node --test "tools/matrix/tests/*.test.mjs"`.

## State and recovery

State is one JSON file, `state.json`, in `stateDirectory`. It is written to a temporary file, flushed, then renamed over the old one, all under an exclusive `worker.lock`.

- **A stale lock needs a person.** If the worker crashed, remove `worker.lock` by hand once you are sure nothing is running. Matrix never steals a lock by age or process ID.
- **A corrupt state file is never replaced.** Matrix stops with an error that says to restore a verified backup. An empty state could erase who owns what.
- **A restart marks claimed work as interrupted.** On load, any `claimed` task becomes `interrupted`, so nothing is silently retried.
- Task states are `pending`, `claimed`, `interrupted`, `awaiting-review`, `withdrawn`, `dead-letter` and `complete`. Only the merged `prompts/done/` folder can make a task `complete`.
- `logs/worker.jsonl` is an append-only log. It never holds tokens, secrets, raw provider output or Claude's error output.

## Metadata and normalisation

Prompts are read with `git ls-tree` and `git show` on `refs/remotes/origin/main`, never from a working tree something could have edited.

A prompt is `prompts/<PREFIX>-<NN>-slug.md`, with a prefix from `idPrefixes` (`PSF`, `AUTO`). Front matter is a small subset: scalars and inline JSON arrays, in the fields `id`, `priority` (`high`, `medium`, `low` or a non-negative number), `effort` (`low`, `medium`, `high`), `dependencies` and `conflicts`.

These block **all** selection, with a visible reason: an empty, unknown or duplicate field; nested YAML, aliases, anchors or tags; an `id` that doesn't match the file name; and two active prompts with the same ID. `status:`, `execution:` and `model:` are ignored (a repository test rejects them).

Prompts in `prompts/done/` are the completion record. A dependency is met only when its prompt is in `done/`. A missing, circular or unmet dependency skips that task with a reason and doesn't block the others. Conflicts are symmetric.

## The usage gate

`usage.mjs` runs `claude -p /usage` in an empty temporary folder with no tools, MCP servers or settings, and allows work only when everything checks out: a verified Claude Code version, a first-party subscription login, no API-key or alternate-provider environment, a report with no model work, no cached or stale notice, one weekly meter and every scoped meter below 60%, paid extra usage explicitly off, and a request under a minute old. The minimum version is the `claudeUsage.minimumVersion` setting (default `2.1.319`); a newer major or minor family blocks until reviewed. Every failure returns a fixed message, never Claude's error output.

## Board pickup

The owner steers psfdx by dragging cards on one GitHub Project board (**Psfdx**). `board-run.mjs` runs one tick, and nothing in it starts Claude. It is off unless `boardPickup.enabled` is `true`, and `dryRun` defaults to `true`: a dry run reports its choice and its reasons and writes nothing (no comments, no card moves, no state or hand-off file).

**Reading the board** (`board.mjs`). One GraphQL query in `POSITION` order, paginated, with each card's Status, issue number, title, author, repository and state. It fails closed: an API error, a partial page set, a count mismatch or more than one view returns `ok: false` with a reason and nothing is picked. There is no fallback to priority, ID or issue number. Open and merged pull requests are read too, so a task with an open pull request or merged work is recognised. Only `matrix/<ID>` branches count as an implementation.

**Each tick, in order:**

1. Resume unfinished housekeeping: a lost starting comment, then any later steps added to `housekeeping` (delivery arrives with AUTO-08).
2. Check Doing cards against the saved state and the pull requests (`doing.mjs`). A Doing card with no claim is a run-now request; one with a live claim is busy; a disagreement stops pickup.
3. Apply the usage gate. Blocked usage means no pickup this tick, with a logged reason.
4. Choose **one** task: an unclaimed Doing card first, in board order (it doesn't use the daily slot); otherwise the first eligible Todo card in board order, only if the London day's slot is unused and the London time is past `dailyTime`. Backlog, Blocked and Done never run, and nothing written in an issue or prompt holds a card back. A card is skipped, with a reason, when its dependencies aren't met, it conflicts with active work, its work has merged (that goes to delivery), or it already has an open pull request (unless it's a resume). Skipping one card never blocks the cards behind it.
5. Write the choice to `board-handoff.json` in the state directory (hand-off mode), or claim it directly. The hand-off holds the prompt hash and the pickup reason, and the worker refuses it if it is older than 15 minutes or the prompt changed.

**Why a card was picked up.** The reason is captured at selection and saved with the claim, so a restart never changes it: `Scheduled (Todo)` with the London date, `Run now (Doing)`, `Resumed (Todo|Doing)` with the earlier job, branch or pull request, or `Unknown (provenance unavailable)`. Who moved a card is always reported as unknown: a Doing card doesn't prove who moved it.

**A claim comes first.** The claim is saved before the card moves to Doing and before the starting comment, so a crash or a failed comment can never lead to a second job. A failed comment keeps the claim and is retried on the next tick. A board tick reads state without marking claimed tasks interrupted; only a worker start does that.

**Issues without a prompt file** (`issue-prompt.mjs`). When the chosen card has no prompt file and no merged or open pull request, and the issue was written by the repository owner in this repository, Matrix builds `prompts/<ID>-<slug>.md` from the issue if it has real text under an objective, a scope or implementation, acceptance criteria and tests. The prompt carries no status, execution or model and is saved in the same pull request. If detail is missing, Matrix posts one comment listing what is missing (repeated only when the issue text changes) and moves the card to Blocked. If the issue isn't the owner's, it posts one comment and moves the card to Blocked. Issue comments are never read as instructions.

**Writing to GitHub** (`github-io.mjs`). Comments carry a hidden marker, `<!-- matrix:<kind>:<task>:<detail> -->`, and are checked for before posting, so a retry never posts twice. Card moves use the project, field and option IDs from the config. A failed write throws and is retried on the next tick; it is never reported as success. The board token is separate from the agent token.

**Setting up.** Create a token for the board, then run `node tools/matrix/board-ids.mjs tonygward <project number>` once with it (`GH_TOKEN` set). It prints `projectId`, `statusFieldId` and the five option IDs to put in `boardPickup` in `worker.json`. Projects v2 `POSITION` order isn't documented as a manual-order guarantee, which is why more than one view fails closed. Check it once on the psfdx board during the pilot.

## The worker

`worker.mjs` turns a hand-off into a reviewed pull request. `runOnce` runs the board tick (which writes the hand-off), then `runTask`. Matrix, not a person's machine, writes, builds and tests the change; GitHub CI then checks it on more platforms. The worker holds no merge or publishing credentials: the [merge gate](../../docs/pipelines.md#gate---matrix-auto-merge) merges, and the CD workflows release.

1. **Claim.** Under the worker's own lock, the hand-off is re-checked against a fresh fetch of `main` (the prompt hash must match and the task must still be pending). A stale or invalid hand-off does nothing. The claim is saved, the card moves to Doing and the starting comment is posted. **If that fails, no code is written** and the task is parked.
2. **Workspace.** A Git worktree at `<worktreeRoot>/<ID>/repo` on a new branch `matrix/<ID>-<slug>` from `origin/main`. A repository with symbolic links or submodules in the index is refused. The instructions are written to `<worktreeRoot>/<ID>/instructions.md`, outside the repository, along with the failure files.
3. **Claude.** `-p --model sonnet` with file tools only (`Read,Edit,Write,Glob,Grep`), no Bash, web or MCP, no settings and no GitHub token in its environment. The only extra folder it can read is its own task folder. Claude is told only to read the instructions file; the prompt body and every failure log are untrusted and are only ever read from files. The reported `num_turns` doesn't reliably follow `--max-turns`, so the binding limits are the dollar cap and the per-attempt time limit (the process tree is killed at the limit); the turn check is only a runaway guard.
4. **Local tests, before any push.** After each attempt the trusted worker runs Pester 5 on PowerShell 7 in the worktree, through the sandbox wrapper in `worker.testRunner`. The wrapper is called as `run-tests-sandboxed <worktree> <resultsFile> <timeoutSeconds> pwsh ...` and must run as a separate test user with no network and no access to the secrets, the state directory or other worktrees. Its exit codes: `0` tests passed, `1` tests failed (a Pester NUnit file is written), `124` timed out, `125` the sandbox refused something (network or secrets), anything else is a sandbox error. A failure is written to `local-test-failure.txt` and the next attempt is given only that path; it counts against `worker.maximumLocalRepairs` (default 5), separate from the CI repairs. A timeout, a refusal or a sandbox error stops the run: nothing is pushed. A pass is recorded in state and in the pull request description under **Local tests (Matrix, PowerShell 7 on Linux)**. Windows PowerShell 5.1 and Windows paths cannot be covered locally; a local pass followed by a CI failure is normal.
5. **Change scope.** Before committing, changed and untracked files are listed. Anything outside the gate's allow-list (and anything under `prompts/`) is reverted and reported; if nothing is left, the run stops. The worker, not Claude, does every Git and GitHub operation.
6. **Pull request.** The worker commits as `Matrix`, merges `origin/main` into the branch if it is behind (a conflict only in `CHANGELOG.md` keeps both sets of `## Unreleased` bullets; any other conflict stops with "Main changed in files this change touches"), pushes, and opens a **draft** pull request `<ID>: <title>` whose description has `Matrix job: <id>`, the summary, the local test result and "Not yet verified against a real org". It looks up the branch's pull request before creating one.
7. **CI and repair.** It finds the `CI - Pester tests` run for the branch **and exact head commit** (event `pull_request`); runs for older commits are ignored. On a pass it marks the pull request ready, sets `awaiting-review` and leaves merging to the gate. On a failure it saves `gh run view --log-failed` to `ci-failure.log`, hands Claude the path, counts a repair, and runs the local tests again before the next push. A pull request that merged while CI ran is never pushed to.

Every outside call is injected, so the whole flow is tested against fake Git, GitHub, Claude, sandbox and clock adapters. A saved phase (`claimed`, `committed`, `pushed`, `pr-open`, `awaiting-review`) and the rule to look up before creating a branch, pull request or comment are what prevent duplicate work after a crash.

## Blocked outcomes, resume and the run budget

A task that stops (interrupted, dead-lettered or a limit reached) gets **one** comment on its issue and its card moves to Blocked (`blocked.mjs`). The comment names the limit, the job, the attempts, the branch and pull request, what is done, what is left and how to resume, and is deduplicated by a hidden marker. Both steps are retried on later ticks if they fail, and nothing re-queues a Blocked card. The issue stays open.

**Resume** is the owner moving the card back to Todo or Doing. Budgets start fresh. With no committed work the task starts again from a clean worktree. With committed work the worker checks the saved worktree is under `worktreeRoot` and the last pushed commit is still on the branch, recreates a lost worktree from the pushed branch, asks CI about that commit, and only runs Claude if that build failed. The pull request is reused and its description rewritten, so an old Blocked section doesn't linger. Work whose pull request **merged** is never resumed (delivery owns it); work whose pull request was **closed without merging** is held: one comment, and the card goes back to Blocked.

**Run budget.** The run starts at the claim and is saved, so a restart can't reset it: 120 minutes in total (CI waiting counts), at most 3 CI repairs, and an optional token budget that counts input, output and cache-write tokens (not cache reads) and is checked before every attempt. The usage gate is checked again before each repair.

## CI-passed note on the issue

When `CI - Pester tests` passes for the exact pull request head commit, the worker posts a note on the tracking issue, once per task, pull request and head commit (marker `<!-- matrix-ci-passed:<task>:<pr>:<sha>:success -->`). It says the work is **not delivered yet**, never closes the issue or moves the card, and never blocks the merge. A failed post is kept as retry state and retried on a later tick.

## Restart recovery

A worker start marks any `claimed` task `interrupted`. If that task has a pushed branch and an open pull request, `recover.mjs` looks it up again by branch and exact head commit. Passing or running CI returns it to `awaiting-review`; a failed build, a head commit Matrix didn't push, or no result within 90 minutes leaves it interrupted, so it is reported and parked in Blocked. Recovery never starts Claude and never pushes.

## Delivery

A merged pull request is not delivery. For every task whose pull request has merged and whose card isn't Done, the board tick runs `delivery.mjs`. It reads from GitHub only (`verifiers.mjs`), holds no credentials and downloads nothing. Each verifier returns `{ ok, evidence, missing }`, and one unavailable verifier can't hide another's findings:

1. **Merge.** The pull request merged into `main`; the merge commit is recorded.
2. **Version.** The first `[release] X.Y.Z` commit on `main` after the merge commit (found with the compare API, oldest first). If two tasks merge before one bump, that one release is the evidence for both.
3. **Release.** `vX.Y.Z` is published (not a draft or pre-release), its tag points at that bump commit, and it has exactly one asset, `psfdx-X.Y.Z.zip`, with a non-zero size.
4. **Notes.** The release notes are not empty and match that version's section of `CHANGELOG.md` at the tag (line endings ignored).
5. **Prompt archived.** The task's prompt is in `prompts/done/` on `main`, whether generated or hand-written.
6. **PowerShell Gallery.** Only when `delivery.psGallery.enabled` is `true` in the config (AUTO-11 turns it on): `psfdx` is listed on the Gallery at `X.Y.Z`. While it is off, the final comment says it is not published there yet.

A change that touched only Markdown, prompts, docs, tools or images (the same rule as CI and `CD - Bump version`, checked by a test) was never bumped, so checks 2 to 4 are replaced by "No release needed (docs only)".

Then, in stages saved in state: **comment** (once, hidden marker `<!-- matrix-final:<task> -->`; it gives the pull request, merge commit, release, download link and, when the Gallery is on, `Install-Module psfdx -RequiredVersion X.Y.Z`), **close** the issue as completed, and **move the card to Done**. While any check is missing, the issue stays open and the card stays in Doing with one comment saying what is missing (the marker includes a hash of the list, so it is repeated only when the list changes). A failed final comment blocks closing and Done; a failed close or Done is retried on the next tick without a second comment. A restart resumes at the stage that failed. Finished work leaves the active states, so it can never hold the single job slot.
