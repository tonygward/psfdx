# psfdx prompts

These prompts set up board-driven, autonomous development for psfdx. **Matrix** is a trusted orchestrator running on the Matrix server. It picks one card at a time from a GitHub Project board, has Claude write the change and its tests in an isolated container, **runs Pester there until it passes**, opens a pull request, hands over to GitHub CI for the wider check (Windows, Windows PowerShell 5.1), merges once the checks pass, releases a patch version (and, once AUTO-11 is set up, publishes it to the PowerShell Gallery), then closes the issue and moves the card to Done.

**Where work runs:** Matrix writes, builds and tests the code; GitHub CI tests it on more platforms; CD publishes. The owner's development machine (Cybertron) writes prompts and reviews; it never builds or runs tests.

The design is ported from the Matrix orchestrator in [`tonygward/audio-plugins`](https://github.com/tonygward/audio-plugins/tree/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999). Every prompt links to its reference files at that pinned commit. **Port the behaviour and its tests, not the Songsmith specifics** (JUCE builds, two installers, R2, the beta website). Where psfdx differs, the prompt says so.

## Order

Until the psfdx worker exists, run these **on the Matrix server** in an interactive Claude Code session (one prompt per pull request, in this order), never on Cybertron. After AUTO-10 has proved the worker, new work goes through the board, AUTO-11 included.

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
| AUTO-11 | [Publish releases to the PowerShell Gallery](AUTO-11-powershell-gallery.md) (**Backlog**: waits for the owner's Gallery account and API key) | AUTO-03, AUTO-08 | yes (workflows, secrets) |

AUTO-05 to AUTO-08 can each be built and unit-tested without a live board, Claude or container: every outside call goes through an injected adapter.

## Decisions already made for psfdx

| Topic | Decision |
|---|---|
| Default branch | `main` (`master` is stale; AUTO-01 corrects CLAUDE.md) |
| Task IDs | `PSF-##` for module work, `AUTO-##` for automation. Issue titles start with the ID |
| Board | A new GitHub Project, **psfdx Development**, with one table view and the Status options Backlog, Todo, Doing, Blocked, Done |
| Selection | Same as Songsmith: Doing runs now, Todo runs one card a London day after 02:00, Backlog and Blocked wait, one task at a time, nothing new at or above 60% weekly Claude usage, Sonnet only |
| Version | One `VERSION` file (`0.8.0` to start) that every module manifest matches. Each source merge to `main` bumps the third part |
| Testing | Matrix runs Pester (PowerShell 7) in its container, in a sandbox with no network or secrets, and pushes only when it passes. GitHub CI then runs Ubuntu, Windows PowerShell 7 and Windows PowerShell 5.1 |
| Delivery | One GitHub release per version, `vX.Y.Z`, with exactly one asset: `psfdx-X.Y.Z.zip`. The final comment links to the release page. PowerShell Gallery publishing follows once CI has passed and the release exists (AUTO-11, a To Do until the owner sets up the Gallery account) |
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
7. When ready for AUTO-11: a PowerShell Gallery account, an API key scoped to the psfdx package names, and the `PSGALLERY_API_KEY` secret in a protected `psgallery` environment.

## Open prompts

This is an index, not the queue: the board decides what runs and in what order.

| ID | Prompt | Tracking issue |
|---|---|---|
| AUTO-01 to AUTO-11 | See the order above | Create one issue per prompt, titled `AUTO-NN: <title>` |

## Merged implementation archive

Merged prompts move to [`done/`](done/). An archived prompt means the work merged, not that it was released.
