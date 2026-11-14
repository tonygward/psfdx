---
id: AUTO-08
priority: medium
effort: medium
dependencies: ["AUTO-07", "AUTO-03"]
conflicts: []
---

# AUTO-08: Delivery: verify, final comment, close, Done

Tracking issue: create `AUTO-08: Delivery: verify, final comment, close, Done` and link it here.

## Objective and user value

Finish every task hands-off and honestly: only after the change is in a published release does Matrix tell the owner it's done, with the version and the download link, close the issue and move the card to Done.

## Reference

Port from [`tools/matrix/delivery.mjs`](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/tools/matrix/delivery.mjs) and [`verifiers.mjs`](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/tools/matrix/verifiers.mjs) and their tests. **Replace the Songsmith verifiers** (two installers, R2, the beta website, Cloudflare Pages) with the psfdx ones below; keep the staging, retry and deduplication logic.

## Scope

Runs in the board tick for every task whose pull request has merged and whose card isn't Done.

### Verify (each a separate verifier returning `{ ok, evidence, missing }`)

1. **Merge:** the pull request merged into `main`; record the merge commit.
2. **Version:** a `[release] X.Y.Z` commit on `main` is a descendant of the merge commit, and it is the first such commit after it; record `X.Y.Z`.
3. **Release:** a published (not draft, not pre-release unless the policy says so) GitHub release `vX.Y.Z` exists, its tag points at that bump commit, and it has **exactly one asset** named `psfdx-X.Y.Z.zip` with a non-zero size.
4. **Notes:** the release notes are non-empty and match that version's section in `CHANGELOG.md` at the tag.
5. **Prompt archived:** the task's prompt is in `prompts/done/` on `main` (generated or hand-written).
6. **PowerShell Gallery** (only when `delivery.psGallery.enabled` is `true`, which AUTO-11 turns on): every module in the release is listed on the Gallery at version `X.Y.Z`. While it is `false`, the final comment says "Not published to the PowerShell Gallery yet". Build the verifier list from config so AUTO-11 only has to switch it on.

Downloads are not tested.

### Finish, in stages saved in state

1. **Comment** on the issue: task done; pull request; merge commit; version; release; download link (the release page); and, once AUTO-11 is live, the install command `Install-Module psfdx -RequiredVersion X.Y.Z` with the Gallery link. Deduplicated by marker.
2. **Close** the issue as completed.
3. **Move** the card to Done.

While any verifier is missing, the issue stays open and the card stays in Doing, with **one** comment saying what is missing (marker includes the missing list, so it's repeated only when that changes). A failed final comment blocks closing and Done; a failed close or Done retries on its own without a second comment.

A source merge whose bump was skipped because the pull request turned out docs-only (for example, a prompt-only task) has nothing to release: verifiers 2–4 are replaced by "no release needed (docs only)", which the comment says plainly.

## Acceptance criteria

- Unit tests with fixtures cover: each verifier passing and failing, release with a second asset, draft release, tag on the wrong commit, missing prompt archive, a docs-only task, comment failure blocking close, close failure retrying without a second comment, and a restart between every stage.
- The Matrix README gains a **Delivery** section, and `docs/execution-policy.md` part 8 matches the code.

## Tests

`node --test tools/matrix/tests`.

## Dependencies and risks

- Depends on AUTO-07 (merged tasks to deliver) and AUTO-03 (releases to verify).
- If two tasks merge before one bump runs, both land in the same release. The first `[release]` commit after each merge commit is the right evidence for both; test that case.

## Release expectations

Not user-facing; no changelog entry.
