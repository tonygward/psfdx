---
id: AUTO-07
priority: high
effort: high
dependencies: ["AUTO-06", "AUTO-04"]
conflicts: []
---

# AUTO-07: Bounded Claude agent loop with CI repair, Blocked and resume

Tracking issue: create `AUTO-07: Bounded Claude agent loop with CI repair, Blocked and resume` and link it here.

## Objective and user value

Turn a hand-off into a reviewed pull request: claim, let Claude write the change and its tests with file tools only, **run Pester in the container until it passes**, push, wait for hosted CI on the exact commit (the wider check: Windows, PowerShell 5.1), repair failures within strict limits, and either hand a green pull request to the gate or stop cleanly in Blocked with an explanation. Never duplicate work after a restart.

Matrix, not a person's machine, writes, builds and tests the code. GitHub CI then checks it on more platforms. Nothing is pushed that hasn't passed locally first.

## Reference

Port from [`tools/matrix/`](https://github.com/tonygward/audio-plugins/tree/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/tools/matrix): `linux-worker.mjs` (the live worker), the Claude invocation in `worker.mjs`, `blocked.mjs`, `recover.mjs`, `ci-comment.mjs`, and their tests. README sections: **Blocked outcomes, resume and the run budget**, **CI-passed note on the issue**, and the restart recovery bullet.

## Scope

### Claim and start (`worker.mjs` entry, run after the board tick each five minutes)

- Under the worker's own lock, re-check the hand-off against a fresh fetch of `main` (prompt hash matches, task still eligible). A stale or invalid hand-off does nothing.
- Claim in state, move the card to Doing, post the starting comment (task, Matrix job ID, prompt revision, repository, limits, pickup reason). **If the claim or comment fails, write no code** and block the task.

### Workspace

- Create a Git worktree under `worktreeRoot` on a new branch `matrix/<ID>-<slug>` from `origin/main`.
- Refuse a repository with symbolic links or submodules in the index (owner review).
- Write the task instructions to a file in the worktree's parent folder, not inside the repository.

### Running Claude

- Arguments, as in the reference: `-p --model sonnet --max-turns <n> --max-budget-usd <n> --output-format json --permission-mode acceptEdits --tools Read,Edit,Write,Glob,Grep --allowedTools Read,Edit,Write,Glob,Grep`, plus the reference's safe-mode and restricted flags for the pinned Claude Code version. **No Bash, no web, no MCP, no GitHub token in Claude's environment.** The working directory is the worktree.
- The instructions tell Claude to follow `CLAUDE.md` and `.claude/rules/`, implement the prompt, add Pester tests that assert the exact `sf` command string, update the manifest export, README row and `## Unreleased` changelog entry, keep Windows PowerShell 5.1 compatibility, and write a short summary file for the pull request description. Claude doesn't run commands itself; the trusted worker runs the tests (below) and hands the results back.
- Enforce the per-attempt time limit by killing the process tree. The reported `num_turns` doesn't reliably follow `--max-turns`; the binding limits are the dollar cap and the timeout (keep the reference comment explaining this).
- Record tokens (AUTO-05 `budget.mjs`) and check the run limits before every attempt: 120 minutes from the claim (CI waiting counts), 3 repairs, optional token budget, and the usage gate again before each repair.

### Local tests before push

After each Claude attempt, the **trusted worker** (not Claude) runs the tests in the worktree:

- `pwsh -NoProfile -NonInteractive -Command "Invoke-Pester -Path . -CI"` with Pester 5 from the image (AUTO-09), plus the repository tests from AUTO-02. Output `testResults.xml` to the worktree's parent folder, not the repository.
- Run it **as the separate test user in the sandbox from AUTO-09**: no network, no access to the secrets folder, the state directory or other worktrees, a time limit (`worker.testTimeoutSeconds`, default 600) and a process-tree kill. The code under test was written by the agent, so it gets no more access than the agent.
- **Fail:** write the failing tests and messages to a file and give Claude the path in the next attempt (never paste the output into the instructions). This counts as a local repair, with its own limit `worker.maximumLocalRepairs` (default 5), separate from the 3 CI repairs; both count towards the 120-minute run limit and the token budget.
- **Pass:** commit and push. Record the local result (passed count, failed count, duration, Pester version) in state and in the pull request description under `Local tests (Matrix, PowerShell 7 on Linux)`.
- Local runs can't cover Windows PowerShell 5.1 or Windows paths; that is what hosted CI is for. A pass locally followed by a CI failure is normal and goes to the CI repair loop.
- If the local limit is reached, push nothing new and stop in Blocked, naming the limit and including the last failure summary.

### Change scope

Before committing, list staged and untracked files. Anything outside the agent scope (the same allow-list as gate rule 5 in AUTO-04) is reverted and reported; if the change is then empty, block. The trusted worker, not Claude, does every Git and GitHub operation.

### Pull request

- Commit as `Matrix <noreply>` with the task ID in the subject; push; open a **draft** pull request titled `<ID>: <issue title>` with a description containing `Matrix job: <id>`, the summary, test expectations and "Not yet verified against a real org". Reuse an existing pull request for the branch rather than opening a second.
- Before pushing, merge `origin/main` if the branch is behind. A conflict only in `CHANGELOG.md` is resolved automatically by keeping both sets of `## Unreleased` bullets; any other conflict blocks with "main changed in files this change touches".

### Waiting for CI and repairing

- Find the `CI - Pester tests` run for the branch **and exact head commit** (event `pull_request`); ignore runs for older commits.
- Pass: mark the pull request ready for review, set the task `awaiting-review` and leave merging to the gate. Post the **CI-passed note** on the tracking issue once per task, pull request and head commit (marker `matrix-ci-passed:<task>:<pr>:<sha>:success`), saying it is not delivered yet.
- Fail: save the failed-job log (`gh run view --log-failed`) to a file and give Claude the file path, **never the log text inside the instructions** (logs are untrusted). Count a repair. After Claude's fix, the local tests run again and must pass before the next push. Repeat until pass or a limit.
- Never started, or no result in the time left: interrupted, with the pull request and commit saved.

### Blocked and resume (`blocked.mjs`)

- Any stop posts one comment (reason naming the limit, job, attempts, branch, pull request, what is done, what is left, how to resume), deduplicated by marker, and moves the card to Blocked. Both steps retry on later ticks if they fail. Nothing re-queues a Blocked card.
- Resume when the owner moves the card back to Todo or Doing: budgets start fresh. With no committed work, start clean. With committed work, check the saved worktree path is under `worktreeRoot` and the last pushed commit is still on the branch, recreate a lost worktree from the pushed branch, ask CI about that commit, and only run Claude if that build failed. Reuse the pull request and rewrite its description so an old Blocked section doesn't linger.
- A task whose pull request merged is never resumed (delivery owns it). One whose pull request was closed without merging is held: one comment, back to Blocked.

### Restart recovery (`recover.mjs`)

After a restart, an `interrupted` task with a pushed branch and an open pull request is looked up by branch and exact head commit. Passing or running CI returns it to `awaiting-review`; a failed build, a head commit Matrix didn't push, or no result within 90 minutes leaves it interrupted, so it is reported and parked in Blocked. Recovery never starts Claude and never pushes.

## Acceptance criteria

- Every path above has a unit test with fake Git, GitHub, Claude and clock adapters, ported from the reference tests and adapted to psfdx names (`main`, `CI - Pester tests`, `prompts/`).
- A dry-run mode exercises claim-to-pull-request against fakes end to end in one test.
- Tests cover the local loop: fail then pass, the local repair limit, a test run that times out, a test run that tries to read the secrets folder or reach the network (the sandbox adapter reports it refused), and nothing pushed after a local failure.
- The Matrix README gains the Blocked, resume, run budget, CI-passed note and recovery sections.

## Tests

`node --test tools/matrix/tests` on all three operating systems.

## Dependencies and risks

- Depends on AUTO-06 (hand-off) and AUTO-04 (the gate that merges what this produces).
- Biggest risk is duplicate work after a crash. The saved phase (`claimed`, `pushed`, `pr-open`, `awaiting-review`) and the "look up before create" rule for branches, pull requests and comments are what prevent it; test each.

## Release expectations

Not user-facing; no changelog entry.
