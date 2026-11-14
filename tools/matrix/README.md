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
