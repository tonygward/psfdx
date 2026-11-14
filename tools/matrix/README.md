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
