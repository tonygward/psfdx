---
id: AUTO-09
priority: medium
effort: medium
dependencies: ["AUTO-07"]
conflicts: []
---

# AUTO-09: Isolated Linux container

Tracking issue: create `AUTO-09: Isolated Linux container` and link it here.

## Objective and user value

Run the psfdx worker where a mistake or a hostile prompt can't reach the owner's files, home network or publishing credentials: a non-root container whose only way out is an allow-list proxy to Anthropic and GitHub.

## Reference

Port [`tools/matrix-linux/`](https://github.com/tonygward/audio-plugins/tree/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/tools/matrix-linux) (`Dockerfile`, `entrypoint.sh`, `verify-isolation.sh`, `claude-version.mjs`, `squid/`, `Start-MatrixAgent.ps1`, `worker.config.json`, `README.md`) and read [ADR AUTO-05](https://github.com/tonygward/audio-plugins/blob/9e7e14a09f7e3b45c3dd11c2887d580f9cbea999/docs/adr/AUTO-05-linux-agent-container.md) for the trust boundaries and the limits of the isolation claim.

## Scope

Create `tools/matrix-linux/` in psfdx:

- **Separate from the Songsmith worker on the same host.** Every name is prefixed `psfdx-matrix-`: image, containers (`psfdx-matrix-agent`, `psfdx-matrix-egress`), internal network, and the two volumes (home, holding the Claude login; work, holding state, worktrees and logs). The two workers must never share a volume, network, lock or token.
- **Image:** Node 24, Git, GitHub CLI and a pinned Claude Code version recorded in a file and checked by `claude-version.mjs`. PowerShell is **not** needed: the worker never runs Pester (hosted CI does). Non-root user, no sudo, no set-id programs, no Docker CLI. The trusted worker code is copied into the image, never mounted from the host.
- **Network:** the agent is on an internal-only network; the egress proxy allows only `api.anthropic.com`, `claude.ai`, the Claude login hosts the reference allows, `github.com`, `api.github.com`, `codeload.github.com` and `objects.githubusercontent.com` over HTTPS, and refuses private and LAN addresses.
- **Secrets:** a secrets folder outside any repository, mounted read-only, holding `agent_github_token` (psfdx only; Contents and Pull requests) and `board_token` (Projects and Issues). Never the `RELEASE_TOKEN`. No Anthropic API key: the usage gate requires a subscription login.
- **Self-test** (`verify-isolation.sh`): port every reference check (non-root, no set-id, no Docker socket, can't reach LAN, can reach only allow-listed hosts, secrets read-only, no release tokens present, and so on) and print `ALL CHECKS PASSED` only when all pass.
- **Entrypoint:** every five minutes, the board tick then the worker; honour a pause file.
- **`Start-MatrixPsfdx.ps1`:** the reference actions (`Build`, `Verify`, `Login`, `Run`, `Ensure`, `Logs`, `Pause`, `Resume`, `Stop`, `Down`), with psfdx names. Same elevation every time (wslc keeps separate images per elevation).
- **`worker.config.json`:** the psfdx config with `boardPickup.enabled: true` and `dryRun: true` to start.
- **README:** what it enforces (table), how to run it, the startup scheduled task (a separate task name, `psfdx Matrix Agent (start containers)`), and the honest limits from the ADR (wslc lacks read-only root, capability drop, no-new-privileges and PID-limit flags; the self-test proves configuration, not host safety).

## Acceptance criteria

- `Build` then `Verify` passes on the owner's host, run by the owner (paste the self-test output in the pull request).
- With the Songsmith container running, starting and stopping the psfdx one doesn't affect it (owner check).
- The gate keeps every file in this folder except `worker.config.json` and `README.md` outside the core lane.

## Tests

The self-test, plus `node --test` for `claude-version.mjs`.

## Dependencies and risks

- Depends on AUTO-07 (the worker it runs).
- Owner-only steps: build, verify, login, secrets. The prompt's pull request can't prove them; say "not yet verified on the host" until the owner has.
- Changes to the Dockerfile, scripts and allow-list always need a person.

## Release expectations

Not user-facing; no changelog entry.
