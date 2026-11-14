---
id: AUTO-05
priority: high
effort: high
dependencies: ["AUTO-01"]
conflicts: []
---

# AUTO-05: Matrix foundation: config, state, prompt scan, usage gate

Tracking issue: create `AUTO-05: Matrix foundation: config, state, prompt scan, usage gate` and link it here.

## Objective and user value

Build the trusted, testable core that every later Matrix step uses: validated config, crash-safe saved state, a strict prompt scanner and the Claude usage gate. Nothing here talks to the board or runs Claude for coding yet.

## Reference

Port from [`tools/matrix/`](https://github.com/tonygward/audio-plugins/tree/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/tools/matrix): `policy.mjs`, `state.mjs`, `process.mjs`, `validation.mjs`, `backlog.mjs`, `usage.mjs`, `budget.mjs`, and their tests in `tools/matrix/tests/`. Read the [Matrix README](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/tools/matrix/README.md) first. Bring the tests across with the code and keep every edge case they cover; they encode bugs already found in production.

## Scope

Create `tools/matrix/` in psfdx:

### `policy.mjs`

Constants in one place: `WEEKLY_LIMIT_PERCENT = 60`, `DAILY_TIME = '02:00'`, time zone `Europe/London`, `BATCH_LIMIT = 1`, `MODEL = 'sonnet'`, maximum run minutes 120, maximum repairs 3, and the `usageGate(snapshot, now)` decision.

### `config.mjs` and `worker.example.json`

Load and strictly validate the worker config: unknown keys, wrong types, relative paths and a `batchLimit` or `maximumPrompts` other than 1 are errors. Fields: `repositorySlug` (`tonygward/psfdx`), `baseBranch` (`main`), `stateDirectory`, `worktreeRoot`, `promptDirectory` (`prompts`), `idPrefixes` (`["PSF", "AUTO"]`), `claudeUsage` (`enabled`, `executable`), `worker` limits (`maximumTurns`, `maximumBudgetUsd`, `timeoutSeconds`, `maximumRunMinutes`, `maximumRepairs`, optional `maximumTokens` from 10,000 to 100,000,000), and a `boardPickup` block that AUTO-06 fills in. Nothing Songsmith-specific: no plugin scopes, JUCE, PowerShell build scripts or Windows accounts.

### `state.mjs`

- One JSON file in `stateDirectory`, replaced atomically (write a temporary file, `fsync`, rename) under an exclusive lock file. A stale lock after a crash needs a person: never steal it automatically.
- Task states: `pending`, `claimed`, `interrupted`, `awaiting-review`, `withdrawn`, `dead-letter`, `complete`.
- On load, any `claimed` task becomes `interrupted` (a restart happened mid-run).
- **Never replace a corrupt or unreadable state file with an empty one**; stop with an error instead, because an empty state could erase who owns what.
- Append-only structured log `logs/worker.jsonl`. Never log secrets, tokens, raw provider output or stderr from Claude.

### `backlog.mjs` (prompt scan)

- Read prompts from the `main` revision fetched from the remote (`git ls-tree` / `git show` on `refs/remotes/origin/main`), never from a working tree that something could have edited.
- Restricted front matter: scalars and inline JSON arrays only; fields `id`, `priority`, `effort`, `dependencies`, `conflicts`. Empty, unknown or duplicate fields, nested YAML, aliases or tags, and an `id` that doesn't match the file name **block all selection** with a visible reason. `status:`, `execution:` and `model:` are ignored (the repository test from AUTO-02 already rejects them).
- IDs come from the file name `prompts/<PREFIX>-<NN>-slug.md` with a prefix from `idPrefixes`.
- Prompts in `prompts/done/` are completion evidence: a dependency is met only when the dependency's prompt is in `done/` on `main`. Missing, circular or unmet dependencies skip the task with a reason; they don't block other tasks. Conflicts are symmetric.
- Duplicate active IDs block all selection.

### `usage.mjs` (Claude usage gate)

Port the reference adapter closely. It runs `claude -p /usage` in a fresh empty temporary directory with no tools, no MCP servers and no settings sources, parses the `stream-json` report, and allows work only when all of these hold:

- Claude Code version is in the verified range (keep this a config value with the reference's minimum; a newer major or minor family blocks until reviewed);
- `claude auth status --json` shows a first-party claude.ai subscription login; any `ANTHROPIC_*`, `CLAUDE_CODE_USE_*`, `CLAUDE_CODE_OAUTH_TOKEN` or `CLAUDE_CONFIG_DIR` in the environment blocks (no API-key or alternate-provider fallback);
- the report did no model work (zero turns, zero cost) and has exactly one structured usage report;
- no cached, stale, rate-limited or "couldn't fetch" notice;
- exactly one `weekly_all` meter, below 60%; every `weekly_scoped` meter below 60%; the session meter below 100%; reset times in the future and within eight days; unknown meter kinds block;
- paid extra usage is explicitly disabled (missing counts as unknown, which blocks);
- the request is less than a minute old.

Every failure returns `allowed: false` with a fixed diagnostic, never subprocess stderr.

### `budget.mjs`

Token budget: count input, output and cache-write tokens from each attempt (not cache reads), saved with the task, checked before each attempt.

### `process.mjs`

Run child processes with `shell: false`, explicit arguments, timeouts, kill of the whole process tree on timeout, bounded output buffers and `windowsHide`.

### `README.md`

How Matrix works in psfdx, mirroring the reference README's sections: how it runs, state and recovery, metadata and normalisation. Keep it accurate to what exists after this pull request; later prompts extend it.

## Acceptance criteria

- `node --test tools/matrix/tests` passes on Windows, macOS and Linux with Node 24 and no npm packages.
- Add `CI - Matrix orchestration tests` (`ci-matrix-tests.yml`) running those tests on all three operating systems for pull requests that change `tools/matrix/**` (Markdown excluded), and add it to the gate's run names and `docs/pipelines.md`.
- Ported tests cover at least: atomic replace and lock, corrupt state refusal, claimed → interrupted on load, every front-matter rejection, dependency and conflict handling, duplicate IDs, and every usage-report rejection in the reference tests.

## Tests

As above. Use injected fakes for `spawnSync`, the clock and the file system where the reference does.

## Dependencies and risks

- Depends on AUTO-01 only, so it can be built in parallel with AUTO-02 to AUTO-04; the CI workflow line needs AUTO-04's gate to exist before it merges automatically.
- The usage report format belongs to Claude Code and can change. That is why the version is pinned and any unexpected shape blocks.

## Release expectations

Not user-facing; no changelog entry. Add `tools/` to the docs-only exclusion so Matrix code changes don't trigger a module release (they aren't in the zip).
