# AUTO-10: Supervised end-to-end pilot

**Status: not started.** This is the runbook for the pilot and the place to record what actually happened. It is a template until the owner runs it. **Nothing below the line "Evidence" has been observed**, and every empty row means exactly that. Don't fill a row from memory or from what should have happened.

The pilot proves that one real psfdx task goes from a Todo card to Done, with a release and a download link and no manual step after the card is moved, before Matrix is trusted overnight. The rules it tests are in the [execution policy](../execution-policy.md); how the parts work is in the [Matrix README](../../tools/matrix/README.md) and the [container README](../../tools/matrix-linux/README.md).

Don't build or test on the owner's development machine (Cybertron). Matrix builds and tests in its container, and GitHub CI covers Windows PowerShell 5.1 and PowerShell 7 on Windows.

## State of the prerequisites when this was written (14 November 2026)

These were read from GitHub, not assumed. Re-check each one before the pilot.

| Prerequisite | Seen on 14 November 2026 |
|---|---|
| Board | The **Psfdx** project (number 3) exists with one view. Its Status field has only **Todo, In Progress and Done**. It needs **Backlog, Todo, Doing, Blocked and Done**, so the option IDs for Backlog, Doing and Blocked don't exist yet |
| `RELEASE_TOKEN` Actions secret | Not set. `CD - Bump version` fails at checkout on every source merge ("Input required and not supplied: token"), so no `[release]` commit, tag or release has been made yet |
| Branch protection on `main` | Not set (GitHub answers "Branch not protected") |
| `MATRIX_AUTOMERGE_ENABLED` variable | Not set, so the gate and the archive workflow are off |
| Container | Not built; `Verify` not run (owner step) |
| Claude login in the container | Not done (owner step) |
| Tokens | Not created (owner step) |

## Before the pilot

1. Finish the owner steps in [`prompts/README.md`](../../prompts/README.md#owner-steps-no-prompt-can-do): the board's five Status options and `node tools/matrix/board-ids.mjs tonygward 3` output pasted into `worker.config.json`; the two tokens in the secrets folder; the `RELEASE_TOKEN` secret (allowed to bypass branch protection for the bump commit only); branch protection requiring `Changes`, `Pester (ubuntu, pwsh)`, `Pester (windows, pwsh)` and `Pester (windows, powershell 5.1)`; the repository variable `MATRIX_AUTOMERGE_ENABLED=true` when ready; the container built, `Verify` passing and the Claude login done. Record the `Verify` output below.
2. **Re-verify board ordering.** Create three throwaway cards, drag them into each order, and check that a dry-run tick lists them in the dragged order every time. Matrix fails closed with more than one view, so confirm the board still has exactly one.
3. **Pick one low-risk task** with an owner-written issue in the [contract format](../backlog-issue-prompt-contract.md): a small fix with a clear Pester test, for example one outstanding finding in `CODE-REVIEW.md` that touches a single cmdlet (not the `Invoke-Expression` refactor).

## Dry run

4. With `boardPickup.dryRun: true`, move the card to Doing. Check the log reports the choice, the pickup reason, the usage reading and the limits, and that **nothing was written to GitHub** (no comment, no card move).

## Live run

5. Set `dryRun: false`, rebuild and restart the container, then move the card to Todo before 02:00 London time (or to Doing for an immediate run).
6. Watch and record the time of each step in the table below.
7. Check the release has exactly one zip and the changelog bullet is in plain language.

## Failure drills (one each)

8. **Blocked.** Set `maximumBudgetUsd` very low on a second small task. Expect one Blocked comment naming the limit, and the card in Blocked. Move it back to Doing with normal limits and check it resumes on the same branch and pull request without duplication.
9. **Restart during CI.** Stop the container while CI runs, start it, and check recovery hands the task back to the gate without running Claude or pushing.
10. **Local test failure.** Give Matrix a task whose acceptance criteria include a test that fails until the change is right. Check from the log that it repaired locally, pushed only after Pester passed, and that the sandbox self-test still passes.
11. **Usage gate.** Temporarily set the threshold below the current reading. Check there is no pickup and a logged reason. Restore it.

## After the pilot

12. Leave Matrix as the only worker on psfdx for a week with `dryRun: false`, then record the outcome and any follow-up issues here. Every gap found gets its own issue (`AUTO-11` is already taken by the PowerShell Gallery work, so number gaps from `AUTO-12`) on the board in Backlog.

If the pilot fails, stop the container (`Start-MatrixPsfdx.ps1 -Action Down`), record what happened, and fix it in a normal pull request. Nothing in psfdx depends on Matrix running, so manual development carries on.

## Evidence

Record links to the comment, run, pull request or commit for every row. A row with no link was not observed.

### Self-test (step 1)

```
(paste the output of Start-MatrixPsfdx.ps1 -Action Verify here; it must end with ALL CHECKS PASSED)
```

Network isolation reported for the test user (`userns`, `rootns` or `none`):

### Board ordering (step 2)

| Dragged order | Dry-run tick listed | Same? | Link |
|---|---|---|---|
| | | | |
| | | | |
| | | | |

### Dry run (step 4)

| Check | Observed | Link |
|---|---|---|
| Choice reported | | |
| Pickup reason reported | | |
| Usage reading reported | | |
| Limits reported | | |
| Nothing written to GitHub | | |

### Live run (steps 5 to 7)

Task: &nbsp; Issue: &nbsp; Pull request: &nbsp; Release:

| Step | Time (London) | Link |
|---|---|---|
| Card moved to Todo or Doing | | |
| Starting comment | | |
| Local Pester run 1 | | |
| Local repairs (count) | | |
| Draft pull request opened | | |
| CI result (`CI - Pester tests`) | | |
| CI-passed note | | |
| Gate merge | | |
| `[release]` commit | | |
| Tag | | |
| Release published | | |
| Prompt archived | | |
| Final comment | | |
| Issue closed | | |
| Card Done | | |

| Check | Observed | Link |
|---|---|---|
| Exactly one asset, `psfdx-X.Y.Z.zip` | | |
| Changelog bullet is plain language | | |
| No manual step after moving the card | | |

### Drills (steps 8 to 11)

| Drill | Expected | Observed | Links |
|---|---|---|---|
| 8. Blocked, then resume | One Blocked comment naming the limit; card in Blocked; resumes on the same branch and pull request with no duplicate | | |
| 9. Restart during CI | Recovery hands the task back to the gate; Claude not run; nothing pushed | | |
| 10. Local test failure | Repaired locally; pushed only after Pester passed; sandbox self-test still passes | | |
| 11. Usage gate | No pickup; reason logged; threshold restored | | |

### After the pilot (step 12)

| Item | Outcome | Link |
|---|---|---|
| One week as the only worker, `dryRun: false` | | |
| Follow-up issues | | |

## Decision

Not yet decided. Record here, once the evidence above is complete, whether Matrix may run overnight, and any conditions.
