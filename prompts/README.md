# psfdx prompts

These prompts set up board-driven, autonomous development for psfdx. **Matrix** is a trusted orchestrator. It picks one card at a time from a GitHub Project board, has Claude write the change in an isolated container, opens a pull request, waits for CI, merges once the checks pass, releases a patch version, then closes the issue and moves the card to Done.

The design is ported from the Matrix orchestrator in [`tonygward/audio-plugins`](https://github.com/tonygward/audio-plugins/tree/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999). Every prompt links to its reference files at that pinned commit. **Port the behaviour and its tests, not the Songsmith specifics** (JUCE builds, two installers, R2, the beta website). Where psfdx differs, the prompt says so.

## Order

Run these by hand (in Claude Code, one prompt per pull request, in this order) until AUTO-10 has proved the worker. After that, new work goes through the board.

| ID | Prompt | Depends on | Needs a person to merge |
|---|---|---|---|
| AUTO-01 | [Execution policy, backlog contract and prompt layout](AUTO-01-execution-policy-and-backlog.md) | none | no (docs only) |
| AUTO-02 | [CI named by kind, one version number](AUTO-02-ci-and-one-version.md) | AUTO-01 | yes (workflows) |
| AUTO-03 | [Automatic patch versions and GitHub releases](AUTO-03-automatic-patch-release.md) | AUTO-02 | yes (workflows) |
| AUTO-04 | [Merge gate and prompt archive](AUTO-04-merge-gate-and-archive.md) | AUTO-03 | yes (workflows, gate) |
| AUTO-05 | [Matrix foundation: config, state, prompt scan, usage gate](AUTO-05-matrix-foundation.md) | AUTO-01 | yes (first Matrix code) |
| AUTO-06 | [Board pickup, issue as prompt, pickup reason](AUTO-06-board-pickup.md) | AUTO-05 | yes |
| AUTO-07 | [Bounded Claude agent loop with CI repair, Blocked and resume](AUTO-07-bounded-agent-loop.md) | AUTO-06, AUTO-04 | yes |
| AUTO-08 | [Delivery: verify, final comment, close, Done](AUTO-08-delivery.md) | AUTO-07, AUTO-03 | yes |
| AUTO-09 | [Isolated Linux container](AUTO-09-linux-container.md) | AUTO-07 | yes (Dockerfile, scripts) |
| AUTO-10 | [Supervised end-to-end pilot](AUTO-10-supervised-pilot.md) | AUTO-08, AUTO-09 | not applicable: owner-run |

AUTO-05 to AUTO-08 can each be built and unit-tested without a live board, Claude or container: every outside call goes through an injected adapter.

## Decisions already made for psfdx

| Topic | Decision |
|---|---|
| Default branch | `main` (`master` is stale; AUTO-01 corrects CLAUDE.md) |
| Task IDs | `PSF-##` for module work, `AUTO-##` for automation. Issue titles start with the ID |
| Board | A new GitHub Project, **psfdx Development**, with one table view and the Status options Backlog, Todo, Doing, Blocked, Done |
| Selection | Same as Songsmith: Doing runs now, Todo runs one card a London day after 02:00, Backlog and Blocked wait, one task at a time, nothing new at or above 60% weekly Claude usage, Sonnet only |
| Version | One `VERSION` file (`0.8.0` to start) that every module manifest matches. Each source merge to `main` bumps the third part |
| Delivery | One GitHub release per version, `vX.Y.Z`, with exactly one asset: `psfdx-X.Y.Z.zip`. The final comment links to the release page. PowerShell Gallery publishing is out of scope until the owner decides otherwise |
| Worker language | Node.js 24, no npm packages, `node --test` (the same as the reference, so the ported tests carry across) |
| Host | The same always-on PC as the Songsmith worker, in a separate container with its own name, volumes, secrets folder, board token and state |
| Public repository | psfdx is public, so Matrix acts only on issues opened by the owner and on cards the owner placed. Pull requests from forks never merge automatically. See AUTO-06 and AUTO-04 |

## Owner steps no prompt can do

1. Create the **psfdx Development** project and its Status options, link it to the repository, and record the project, field and option IDs (AUTO-06 prints them with a helper).
2. Create two fine-grained tokens, one for the agent (Contents and Pull requests on psfdx only) and one for the board (Projects, Issues read and write; no Contents write). Keep them in a secrets folder outside any repository.
3. Add a `RELEASE_TOKEN` Actions secret for the gate and CD workflows (Contents and Pull requests write), since merges made with `GITHUB_TOKEN` don't trigger other workflows.
4. Turn on branch protection for `main` and require the `CI - Pester tests` checks.
5. Build the container, run the isolation self-test, and sign in once with the Claude subscription (AUTO-09).
6. Supervise the pilot (AUTO-10).

## Open prompts

This is an index, not the queue: the board decides what runs and in what order.

| ID | Prompt | Tracking issue |
|---|---|---|
| AUTO-01 to AUTO-10 | See the order above | Create one issue per prompt, titled `AUTO-0N: <title>` |

## Merged implementation archive

Merged prompts move to [`done/`](done/). An archived prompt means the work merged, not that it was released.
