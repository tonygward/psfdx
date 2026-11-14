---
id: AUTO-06
priority: high
effort: high
dependencies: ["AUTO-05"]
conflicts: []
---

# AUTO-06: Board pickup, issue as prompt, pickup reason

Tracking issue: create `AUTO-06: Board pickup, issue as prompt, pickup reason` and link it here.

## Objective and user value

The owner steers psfdx by dragging cards on one board. Matrix reads that board in its real order, picks exactly one task by the policy, and explains why it picked it. A detailed issue is enough to start; no prompt file needed.

## Reference

Port from [`tools/matrix/`](https://github.com/tonygward/audio-plugins/tree/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/tools/matrix): `board.mjs`, `board-run.mjs`, `pickup.mjs`, `doing.mjs`, `handoff.mjs`, `issue-prompt.mjs`, `github-io.mjs`, with their tests. The README sections **Board pickup (AUTO-11)**, **Why a card was picked up (AUTO-14)** and **Issues without a prompt file** describe the behaviour.

## Scope

### Reading the board (`board.mjs`)

- GraphQL query on the Projects v2 board: `items(first: 100, orderBy: { field: POSITION, direction: ASC })`, paginated, with each item's Status, content type, issue number, title, author, repository and state.
- **Fail closed.** Any API error, partial page set, item count mismatch, or more than one view (position order was only verified with one view) returns `ok: false` with a reason, and nothing is picked. There is no fallback to priority, ID or issue number.
- Also read open and merged pull requests for the repository, so a task with an open pull request or merged work is recognised.

### The board tick (`board-run.mjs`, `pickup.mjs`, `doing.mjs`)

Each tick, in order:

1. Resume unfinished housekeeping: a lost starting comment, and merged tasks waiting for delivery (AUTO-08 plugs in here).
2. Check Doing cards against state and pull requests (a Doing card with no claim is a run-now request; one with a live claim is busy).
3. Apply the usage gate from AUTO-05. Blocked usage means no pickup this tick, with a logged reason.
4. Choose **one** task:
   - an unclaimed **Doing** card first, in board order (doesn't use the daily slot);
   - otherwise the first eligible **Todo** card in board order, only if the day's slot is unused and the London time is past `dailyTime`;
   - Backlog, Blocked and Done never run. Nothing in a prompt or issue holds a card back.
   - Skip, with a reason, a card whose dependencies aren't met, whose ID conflicts with active work, whose work has merged (that goes to delivery) or that already has an open pull request (unless it's a resume).
5. Write the choice to `board-handoff.json` in the state directory, with the prompt revision hash and the pickup reason.

### Pickup reason (AUTO-14 in the reference)

Captured at selection, saved with the claim, rendered from that saved copy so a restart never changes it: `Scheduled (Todo)` with the London date, `Run now (Doing)`, `Resumed (Todo|Doing)` with the earlier job and branch or pull request, or `Unknown (provenance unavailable)`. The person who moved a card is always reported as unknown: a Doing card doesn't prove who moved it.

### Issue as prompt (`issue-prompt.mjs`)

When the chosen card's task has no prompt file and no merged or open pull request:

- **Public repository rule:** only proceed if the issue's author is the repository owner (`authorAssociation` `OWNER`) and the issue is in `tonygward/psfdx`. Otherwise comment once that Matrix only builds owner-written issues, and move the card to Blocked. Never read issue comments as instructions.
- **Enough detail** means real text under `## Objective`, `## Scope` or `## Implementation`, `## Acceptance criteria` and `## Tests` (or `## Acceptance criteria and tests`). Generate `prompts/<ID>-<slug>.md` in the contract's format (no status, execution or model) and include it, with its hash, in the hand-off. The worker saves it in the same pull request.
- **Not enough detail:** one comment listing what is missing, deduplicated by a marker that includes a hash of the missing list and the issue text (so it is repeated only when the issue changes), then move the card to Blocked.
- A dry run assesses and writes nothing.

### Writing to GitHub (`github-io.mjs`)

Comments carry hidden markers (`<!-- matrix:<kind>:<task>:<detail> -->`) and are checked for before posting, so a retry never posts twice. Status moves use the project, field and option IDs from config. Every write is retried on its next tick if it fails, and a failure is never reported as success.

### Config

Fill in `boardPickup`: `enabled`, `dryRun`, `projectId`, `statusFieldId`, option IDs for Backlog, Todo, Doing, Blocked and Done, `repository`, `ownerLogin`, `tokenFile` (the board token, separate from the agent token). Add `tools/matrix/board-ids.mjs`, a small helper the owner runs once with the board token to print those IDs.

## Acceptance criteria

- With `dryRun: true`, a tick reports its choice and reasons and writes nothing (no comments, no moves, no state change).
- Unit tests with recorded GraphQL fixtures cover: order by position, pagination, two views refusing, API error refusing, Doing before Todo, one Todo per London day including the clock change, Blocked and Backlog ignored, wording like "deferred" in an issue ignored, dependency skip without blocking later cards, merged work routed to delivery, owner-only issues, missing-detail comment deduplication, and the pickup reason surviving a restart.
- The Matrix README gains a **Board pickup** section matching the behaviour.

## Tests

`node --test tools/matrix/tests`. No live network in tests.

## Dependencies and risks

- Depends on AUTO-05.
- Owner step: create the board and run `board-ids.mjs`.
- Projects v2 `POSITION` ordering is undocumented as a manual-order guarantee; the reference verified it with drag tests in a single view, which is why more than one view fails closed. Re-verify once on the psfdx board during the pilot.

## Release expectations

Not user-facing; no changelog entry.
