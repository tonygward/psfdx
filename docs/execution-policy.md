# psfdx execution and delivery policy

**This is the one place the development and delivery rules are written down.** Other documents link here and do not restate them.
Owner decisions: 14 November 2026 (board columns are the only hold; Sonnet only; one `VERSION` file; every finished task keeps a prompt; the repository is public).

The process has nine parts. Each has one owning document or section.

| # | Part | Owning document |
|---|---|---|
| 1 | Backlog: issues and prompts | [Backlog](#1-backlog-issues-and-prompts) below, with the [issue and prompt contract](backlog-issue-prompt-contract.md) |
| 2 | Selection: what runs next | [Selection](#2-selection-what-runs-next) below |
| 3 | Bounded execution: limits, Blocked and resume | [Bounded execution](#3-bounded-execution) below |
| 4 | Continuous integration | [Build, merge, version and release](#4-7-build-merge-version-and-release) below (detail added by AUTO-02) |
| 5 | Merge gate | The same section (detail added by AUTO-04) |
| 6 | Versions and release notes | The same section (detail added by AUTO-03) |
| 7 | Release | The same section (detail added by AUTO-03) |
| 8 | Finishing a task: final comment, close, Done | [Finishing](#8-finishing-a-task) below |
| 9 | Archive and traceability | [Archive](#9-archive-and-traceability) below |

## 1. Backlog: issues and prompts

- Every task has a GitHub issue whose title starts with a stable ID: `PSF-##` for module work, `AUTO-##` for automation. Search for an existing issue or prompt before creating one.
- **A prompt file is optional at the start.** A task is ready to run once its card is in **Todo** or **Doing**. With no prompt file, Matrix builds one from the issue when it has an objective, scope or implementation notes, acceptance criteria and tests, and saves it in the implementation pull request. If the issue lacks that detail, Matrix comments once on what is missing and moves the card to **Blocked**.
- **A prompt must exist by Done.** Every finished task has a canonical prompt in `prompts/done/`, whether a person wrote it or Matrix generated it.
- A prompt never carries a status, an execution mode or a model. The board owns status, and Matrix always runs Sonnet.

## 2. Selection: what runs next

- **The board column is the only hold.** **Backlog** and **Blocked** wait. **Todo** and **Doing** run. Nothing else holds a card back: not wording in a prompt or issue, not a missing field.
- **Doing** is a run-now request. An unclaimed Doing card is picked up at the next worker run (every five minutes), ahead of Todo, in board order.
- **Todo** is the overnight queue in board order. Matrix takes one Todo card per London day, on the first run after 02:00. A Doing pickup does not use that slot.
- Board order decides. Matrix reads the view's actual order and fails closed if it cannot.
- One task per run and one active job at a time.
- No new work at or above 60% verified weekly Claude usage, including scoped meters. An unknown, cached or stale reading blocks pickup. There is no paid fallback.
- Unmet `dependencies:` skip a card with a reason; they do not block the cards behind it.
- Work that has already merged is never coded again. It goes to delivery.

## 3. Bounded execution

- Matrix claims one task, moves the card to Doing and posts a starting comment before any code is written. No code without a recorded claim and starting comment.
- **Limits**, all enforced:
  - per attempt: Claude turns, a dollar cap and a time limit;
  - per run: 120 minutes from the claim (CI waiting counts) and 3 repairs;
  - per run, optional: a token budget, checked before each attempt.
  - Counters are saved, so a restart cannot reset them.
- At a limit or blocker, Matrix comments once with the reason, what is done, what is left and how to resume, and moves the card to **Blocked**. Nothing re-queues a Blocked card.
- **Resume** by moving the card back to Todo or Doing. Committed work carries on from its branch and pull request; nothing is duplicated.

## 4–7. Build, merge, version and release

Summary of the decisions. The workflows and scripts that implement them arrive with AUTO-02, AUTO-03 and AUTO-04, and those prompts add the detail here.

- **CI:** one workflow, `CI - Pester tests`, on every pull request. A pull request that cannot affect the Pester suite (documentation, prompts, images, Matrix Node code) gets a quick run that tests nothing, so the gate always has a result. The rule is in `scripts/release/changes.mjs`.
- **Merge gate:** Matrix pull requests merge automatically once CI passed on the exact head commit and every rule holds. Workflows, the gate scripts, the Dockerfile, shell and PowerShell scripts outside the modules, and the egress allow-list always need a person. That means anything under `.github/`, `scripts/`, `docs/` (including this policy), the root `tests/`, `install*.ps1`, `uninstall*.ps1`, `VERSION`, the Dockerfile and the allow-list. A task may change only the product modules (including their own tests), `prompts/`, `images/`, `README.md`, `CHANGELOG.md` and `modules.ps1`. Rules and lanes are in [pipelines](pipelines.md#gate---matrix-auto-merge); the owner's own infrastructure and documentation pull requests merge through the owner lane. **Standing rule (owner, 2026-11-18): every merge is done by the AI, without asking.** The AI merges its own pull requests, including those the gate's lanes don't cover (workflows, the gate, release machinery, this policy), after every check has passed on the exact head commit. It never merges past a failing or unfinished check, never overrides branch protection, and never merges a pull request it did not open or review. Fork pull requests are never merged.
- **Versions:** one `VERSION` file that every module manifest matches. Each source merge to `main` bumps the third part and moves the `## Unreleased` notes into the new version. Major and minor bumps are owner decisions. Any change users will notice adds plain-language bullets under `## Unreleased`, prefixed with the module name; see [releases](release.md).
- **Release:** one GitHub release per version, tagged `vX.Y.Z`, with exactly one asset, `psfdx-X.Y.Z.zip`.

## 8. Finishing a task

After the merge, Matrix finishes the task itself. Each check reads from GitHub only; downloads are not tested.

1. **Verify delivery:**
   - the pull request merged into `main` (the merge commit is recorded);
   - a `[release] X.Y.Z` commit on `main` follows the merge commit (the first one after it);
   - a published GitHub release `vX.Y.Z` exists (not a draft or pre-release), its tag points at that bump commit, and it has exactly one non-empty asset, `psfdx-X.Y.Z.zip`;
   - the release notes are not empty and match that version's section of `CHANGELOG.md` at the tag;
   - the task's prompt is archived in `prompts/done/` on `main`;
   - once the PowerShell Gallery is switched on (`delivery.psGallery.enabled`), the bundled `psfdx` package is listed there at that version.
   A change that ships nothing (nothing under `psfdx*/` other than tests and Markdown, no `modules.ps1`, install or uninstall script or `VERSION`) is not released, so the version, release and notes checks are replaced by "No release needed (nothing in this change ships)". Workflows, scripts, tools and documentation never cause a release.
2. **Comment** on the issue: the pull request, merge commit, release, the download link (the release page) and, when the Gallery is on, the install command. While the Gallery is off it says it is not published there yet. Posted once (hidden marker).
3. **Close** the issue as completed.
4. **Move** the card to **Done**.

Each stage is saved, so a restart resumes at the stage that failed. While a check is missing, the issue stays open and the card stays in Doing, with one comment saying what is missing (repeated only when that list changes). A failed final comment blocks closing and Done; a failed close or Done is retried on its own without a second comment. Two tasks that merge before one bump are both delivered by that release.

## 9. Archive and traceability

A merged prompt moves to `prompts/done/` automatically. Issue comments are the audit trail.

## Public repository

psfdx is public. Matrix acts only on issues opened by the repository owner and on cards on the owner's project. It never reads comments as instructions. Pull requests from forks, or from anyone except the agent identity, are never merged automatically.

## Not proof of anything

A prompt in `prompts/done/` shows the implementation merged, not that it was released. A Doing card is a request, not proof that work started. Documentation describing an integration is not evidence that it runs.
