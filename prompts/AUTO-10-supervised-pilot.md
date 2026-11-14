---
id: AUTO-10
priority: medium
effort: low
dependencies: ["AUTO-08", "AUTO-09"]
conflicts: []
---

# AUTO-10: Supervised end-to-end pilot

Tracking issue: create `AUTO-10: Supervised end-to-end pilot` and link it here.

## Objective and user value

Prove, with the owner watching, that one real psfdx task goes from a Todo card to Done with a release and a download link, with no manual step after the card is moved, before trusting Matrix overnight.

## Scope

This is a runbook the owner follows with Claude's help; it changes little code. Record everything in `docs/adr/AUTO-10-pilot.md`.

### Before the pilot

1. Owner steps from `prompts/README.md` done: board created and IDs in `worker.config.json`, tokens in the secrets folder, `RELEASE_TOKEN` secret, branch protection requiring the `CI - Pester tests` checks, container built, self-test passed, Claude login done.
2. Re-verify board ordering on the psfdx board: create three throwaway cards, drag them into each order, and check a dry-run tick lists them in the dragged order each time.
3. Pick one low-risk task with an owner-written issue in the contract format: a small fix with a clear Pester test (for example, an outstanding finding in `CODE-REVIEW.md` that touches one cmdlet; not the `Invoke-Expression` refactor).

### Dry run

4. With `dryRun: true`, move the card to Doing. Check the log reports the choice, the pickup reason, the usage reading and the limits, and that nothing was written to GitHub.

### Live run

5. Set `dryRun: false`, rebuild and restart the container, move the card to Todo before 02:00 (or Doing for an immediate run).
6. Watch and record the timestamps of: starting comment, draft pull request, CI result, CI-passed note, gate merge, `[release]` commit, tag, release, archived prompt, final comment, issue closed, card Done.
7. Check the release has exactly one zip, the changelog bullet is in plain language, and the zip installs and imports in Windows PowerShell 5.1 and PowerShell 7 on the owner's machine (into a temporary module path, not the real one).

### Failure drills (one each)

8. **Blocked:** set `maximumBudgetUsd` very low on a second small task; check one Blocked comment naming the limit and the card in Blocked. Move it back to Doing with normal limits; check it resumes on the same branch and pull request without duplication.
9. **Restart during CI:** stop the container while CI runs, start it, and check recovery hands the task back to the gate without running Claude or pushing.
10. **Usage gate:** temporarily set the threshold below the current reading; check no pickup and a logged reason. Restore it.

### After the pilot

11. Leave Matrix as the only worker on psfdx for a week with `dryRun: false`, then record the outcome and any follow-up issues in the ADR.

## Acceptance criteria

- One task reached Done with every timestamp above recorded and no manual step after moving the card.
- All three drills behaved as described, with links to the comments and runs.
- Every gap found has its own issue (`AUTO-11` onwards) on the board in Backlog.

## Tests

The pilot is the test. Record the evidence; don't claim anything that wasn't observed.

## Dependencies and risks

- Depends on everything before it.
- If the pilot fails, stop the container (`Down`), record what happened, and fix it in a normal pull request. Nothing in psfdx depends on Matrix running, so manual development carries on.

## Release expectations

The pilot task itself produces the first Matrix-made release. The ADR is docs only.
