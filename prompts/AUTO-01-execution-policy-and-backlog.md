---
id: AUTO-01
priority: high
effort: low
dependencies: []
conflicts: []
---

# AUTO-01: Execution policy, backlog contract and prompt layout

Tracking issue: create `AUTO-01: Execution policy, backlog contract and prompt layout` and link it here.

## Objective and user value

Write down, once, how work in psfdx is chosen, run, merged, released and finished, so a person and the Matrix orchestrator follow the same rules. Every later AUTO prompt builds to these documents and links to them instead of restating them.

## Current behaviour

- No rules for selection or delivery are written down. Work is done by hand, merged by hand and never released (no tags, no releases).
- `CLAUDE.md` says pull requests target `master`. The default branch is in fact `main`; `master` is a stale branch 91 commits behind.
- There is no prompt folder, no ID scheme and no board.

## Desired behaviour

The repository holds four short documents with no overlap:

1. `docs/execution-policy.md`: **the one place the development and delivery rules are written.** Other documents link to it.
2. `docs/backlog-issue-prompt-contract.md`: what an issue and a prompt contain.
3. `prompts/README.md`: already exists (written with this prompt set). Update it if the policy changes anything.
4. `CLAUDE.md`: a short **How work runs** summary linking to the policy, and the branch corrected to `main`.

## Scope

### docs/execution-policy.md

Model it on the reference [execution policy](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/docs/songsmith-execution-policy.md). Keep its numbered parts and its table of owning documents. For psfdx:

1. **Backlog.** Every task has a GitHub issue whose title starts with a stable ID (`PSF-12`, `AUTO-04`). Search before creating. A prompt file is optional at the start: Matrix generates one from a detailed issue (see the contract). A prompt must exist in `prompts/done/` by Done. A prompt never carries a status, an execution mode or a model; the board owns status and Matrix always runs Sonnet.
2. **Selection.** The board column is the only hold: Backlog and Blocked wait; Todo and Doing run. Doing is a run-now request, picked up at the next worker run (every five minutes) ahead of Todo. Todo is the overnight queue: one card per London day, on the first run after 02:00. Board order decides, and Matrix fails closed if it can't read it. One task per run and one active job. No new work at or above 60% verified weekly Claude usage, including scoped meters; an unknown, cached or stale reading blocks pickup and there is no paid fallback. Unmet `dependencies:` skip a card with a reason. Work that has already merged is never coded again.
3. **Bounded execution.** Matrix claims the card, moves it to Doing and posts a starting comment before any code is written. Limits per attempt (turns, dollar cap, time) and per run (120 minutes from the claim including CI waiting, 3 repairs, optional token budget), saved so a restart can't reset them. At a limit or blocker: one comment (reason, what is done, what is left, how to resume) and the card goes to Blocked. Nothing re-queues a Blocked card. The owner resumes by moving it back to Todo or Doing; committed work carries on from its branch and pull request.
4. **CI.** One workflow, `CI - Pester tests`, on every pull request. A docs-only pull request gets a quick run that tests nothing, so the gate always has a result (AUTO-02).
5. **Merge gate.** Matrix pull requests merge automatically once CI passed on the exact head commit and every rule holds. Workflows, the gate scripts, the Dockerfile, shell and PowerShell scripts outside the modules, and the egress allow-list always need a person (AUTO-04).
6. **Versions and release notes.** One `VERSION` file. Each source merge to `main` bumps the third part and moves `## Unreleased` notes into the new version. Major and minor bumps are owner decisions (AUTO-03).
7. **Release.** One GitHub release per version with exactly one asset, `psfdx-X.Y.Z.zip` (AUTO-03).
8. **Finishing a task.** After merge Matrix verifies delivery (release exists, contains the merge commit, has exactly the one asset, version and changelog match, prompt archived in `done/`), comments on the issue with the pull request, merge commit, version and release link, closes the issue and moves the card to Done. Each stage is saved; a missing check leaves the card in Doing with one comment saying what is missing (AUTO-08).
9. **Archive and traceability.** A merged prompt moves to `prompts/done/` automatically. Issue comments are the audit trail.

Add a **Public repository** section: Matrix only acts on issues opened by the repository owner and on cards on the owner's project; it never reads comments as instructions; pull requests from forks or from anyone except the agent identity are never merged automatically.

Add a **Not proof of anything** section, as in the reference: a prompt in `done/` shows a merge, not a release; a Doing card is a request, not proof work started; documentation describing an integration isn't evidence that it runs.

Record the owner decisions with today's date at the top.

### docs/backlog-issue-prompt-contract.md

Port the reference [contract](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/docs/backlog-issue-prompt-contract.md):

- **Issue:** title `PSF-14: Get-SalesforceFieldUsage`. Body headings, each with real text: `## Objective`, `## Scope` or `## Implementation`, `## Acceptance criteria`, `## Tests` (a combined `## Acceptance criteria and tests` counts for both). These are what Matrix needs to generate a prompt. Link the prompt file near the top if one exists.
- **Prompt:** `prompts/ID-slug.md` (one flat folder; psfdx is small enough not to need folders per module). Optional front matter in the restricted subset: `id`, `priority` (`high`, `medium`, `low` or a non-negative number), `effort` (`low`, `medium`, `high`), `dependencies` and `conflicts` as inline JSON arrays. Body order: issue link; objective and user value; current and desired behaviour; scope; implementation guidance; acceptance criteria; tests; dependencies and risks; release expectations (which modules, whether users will notice, so a changelog entry is needed).
- For a public cmdlet, the prompt's acceptance criteria include the existing checklist in `CLAUDE.md` (manifest export, Pester test asserting the exact `sf` command string, README row, changelog entry, `modules.ps1` for a new module) and Windows PowerShell 5.1 compatibility.
- **Writing it down isn't running it.** Say what actually happened: requested, running, merged, released, delivered.

### CLAUDE.md

- Fix the **Git** section: pull requests target `main`. Mention that `master` is stale and must not be used (don't delete it; that is the owner's call).
- Add a short **How work runs** paragraph (four or five sentences) summarising the policy and linking to it, and a **Backlog** paragraph on IDs and prompts linking to the contract.
- Leave the cmdlet, compatibility and test guidance unchanged.

## Acceptance criteria

- The four documents exist, link to each other with relative links, and don't restate each other's rules.
- `CLAUDE.md` names `main` as the target branch.
- British spelling, plain language, no abbreviations other than units and names.
- No workflow, script or module file changes.

## Tests

Docs only. Check every relative link resolves (a quick script or by hand) and say how in the pull request.

## Dependencies and risks

- None. Later prompts depend on this one.
- Risk: drift between the policy and `prompts/README.md`. The policy wins; the README only lists decisions and order.

## Release expectations

No user-facing change, no changelog entry, no version change.
