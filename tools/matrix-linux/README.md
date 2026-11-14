# psfdx Matrix agent: isolated Linux container

This runs the [Matrix worker](../matrix/README.md) where a mistake or a hostile prompt can't reach the owner's files, the home network or any publishing credential. It is a non-root container whose only way out is an allow-list proxy to Anthropic and GitHub.

**Status: built and verified on one host, not yet used for real work.** On 14 November 2026 `Build` produced the image and `Verify` ended with `ALL CHECKS PASSED` on a WSL 2 host (kernel 6.18). That host's container runtime blocks network namespaces, so the test sandbox uses the [proxy credential](#the-test-sandbox) fallback. The worker has not run against real GitHub or Claude, and `Login` has not been done. See [what is not proven](#what-this-does-not-prove).

## Separate from any other worker

Every name starts with `psfdx-matrix-`, so this worker can share a host with another one (for example the Songsmith worker) without sharing anything:

| Thing | Name |
|---|---|
| Image | `psfdx-matrix-agent:dev` |
| Containers | `psfdx-matrix-agent`, `psfdx-matrix-egress` |
| Internal network | `psfdx-matrix-internal` |
| Volumes | `psfdx-matrix-home` (the Claude sign-in), `psfdx-matrix-work` (state, worktrees, logs) |
| Startup task | `psfdx Matrix Agent (start containers)` |

The two workers never share a volume, network, lock file or token. `Start-MatrixPsfdx.ps1` only touches objects with these names.

## What it enforces

| Control | How | Proved by |
|---|---|---|
| The worker is not root | The container starts as root only to prepare folders, copy the two secrets and start the test broker, then drops to uid 10001 (`agent`) with `setpriv`: no capabilities, empty bounding set, no-new-privileges | `Verify`: not root, `CapEff` and `CapBnd` empty, `NoNewPrivs` set |
| No way to gain privilege | No sudo, no set-id programs (stripped at build), no Docker CLI, no Docker socket | `Verify` |
| The image can't be changed | The worker code is copied into the image (root-owned, read-only), never mounted from the host | `Verify`: `/opt/matrix` and `/` not writable |
| Only the proxy leads out | The agent is on an internal-only network; the squid proxy is the only container with a route out | `Verify` (with the proxy): direct internet and the home network are blocked |
| Only the allow-listed hosts | The proxy allows HTTPS `CONNECT` on port 443, with its credential, to `anthropic.com` (which covers `api.anthropic.com`), `claude.ai` and `claude.com` (sign-in and usage), `github.com`, `api.github.com`, `codeload.github.com` and `objects.githubusercontent.com`, and refuses private and LAN addresses | `Verify`: allowed hosts connect; `example.com`, the PowerShell Gallery, npm and a LAN address are refused |
| Secrets stay small | A secrets folder outside any repository is mounted read-only at `/opt/host-secrets`, a root-only folder. The entrypoint gives the agent private copies of `agent_github_token` (psfdx only; Contents and Pull requests) and `board_token` (Projects and Issues). Never the `RELEASE_TOKEN`; no Anthropic API key | `Verify`: no release, publishing or API-key variable, the raw mount is closed to the agent |
| Subscription login only | The usage gate refuses API keys and alternate providers, so there is no key anywhere | The worker's usage check |
| PowerShell 7 and Pester 5 | Installed at build time at pinned exact versions (`versions.json`), because the proxy refuses the PowerShell Gallery at run time | `Verify`: the versions match the pins |
| Agent-written code gets no more access than the agent | The test sandbox, below | `Verify`: the probe |

## The test sandbox

Matrix runs Pester in the container before anything is pushed (AUTO-07). The code under test was written by the agent, so it runs as a second user, `matrix-test` (uid 10002), through a small **root test broker** (`test-broker.sh`):

- The worker calls `run-tests-sandboxed <worktree> <results file> <seconds>`, which writes a request file and waits. The broker is the only thing that can run code as the test user.
- **The command is fixed in the broker.** A request only chooses which worktree (it must be exactly `/work/worktrees/<PSF|AUTO>-<n>/repo`, a plain directory), where the results go (that task's `testResults.xml`) and how long (30 to 3600 seconds). It can't supply a command.
- The broker gives that one worktree to the test user while the tests run, and hands it back afterwards. The test user can read and write only that worktree, its results file and a scratch folder. It can't read the secrets, the Claude sign-in, the state folder, the source clone or any other worktree, and it can't write outside those places.
- **No network.** The broker picks the strongest method the runtime allows and `Verify` prints it (`network isolation for the test user: ...`):
  1. `userns`: the tests run in a new network namespace that holds only a loopback device (the test user makes its own, `unshare --user --map-current-user --net`);
  2. `rootns`: the same, made by root (needs `CAP_SYS_ADMIN`);
  3. `proxyauth`: used when the runtime's seccomp profile blocks `unshare` (as on the verified host). The test user shares the container network, but the only way out is the egress proxy, which **demands a credential** (a generated password kept outside the repository, given only to the agent's environment; the test user runs with an empty environment and can't read another process's). Direct connections are already blocked by the internal network. This is weaker than a namespace: the test user can open a TCP connection to the proxy and be refused with 407. The broker only picks it after checking that the proxy really answers 407 without the credential;
  4. `none`: **the broker refuses every request** (exit code 125), the worker stops in Blocked, and tests never run without isolation.
- Exit codes: `0` passed, `1` failed, `124` timed out (the process tree is killed), `125` refused, `3` sandbox error.

`Verify` proves it with a probe that runs as the test user inside the sandbox: it can't read a secret, the state folder, the source clone, the broker's inbox or another worktree; can't write `/etc`, `/opt/matrix`, the state folder or other worktrees; has no capabilities; and can't reach the internet. With a namespace it sees no network device except loopback and can't reach the proxy; with `proxyauth` the proxy refuses it (407). It can write its own worktree and scratch folder.

## Running it

Run everything from this folder in PowerShell. Use the **same elevation every time**, because wslc keeps separate images per elevation.

```powershell
# One-time owner steps
./Start-MatrixPsfdx.ps1 -Action Build        # checks versions.json, then builds the image
./Start-MatrixPsfdx.ps1 -Action Verify       # the isolation self-test; it must end with ALL CHECKS PASSED
./Start-MatrixPsfdx.ps1 -Action Login        # sign in once with the Claude subscription (claude.ai)

# Start the worker (secrets folder is outside any repository: agent_github_token and board_token)
./Start-MatrixPsfdx.ps1 -Action Run -SecretsDirectory C:\Matrix\psfdx-secrets
```

| Action | What it does |
|---|---|
| `Build` | Runs `claude-version.mjs check` (exact stable pins; Claude Code in the usage gate's verified family), then builds the image |
| `Verify` | Starts the proxy and runs the self-test with the network checks. Prints `ALL CHECKS PASSED` only when every check passes |
| `Login` | One-time interactive Claude subscription sign-in, then prints the login status |
| `Run` | Starts the worker detached. This is the owner's go-ahead |
| `Ensure` | Starts the proxy, and the worker if it isn't running. Safe to run at every logon |
| `Logs` | Shows the worker's output |
| `Pause`, `Resume` | Stop or allow new work without stopping the container (a `PAUSED` file in the state folder) |
| `Stop` | Removes the worker container |
| `Down` | Removes the worker, the proxy and the network. The volumes are kept |

Every five minutes the entrypoint runs the board tick and then the worker (`worker.mjs`), and honours the pause file. A stale `worker.lock` can only be left by a killed container, so the entrypoint clears it at start-up; Matrix never steals a lock any other way.

### Start at logon

Create a scheduled task named **`psfdx Matrix Agent (start containers)`** that runs, at logon and with the same elevation you built with:

```powershell
pwsh -NoProfile -File <repository>\tools\matrix-linux\Start-MatrixPsfdx.ps1 -Action Ensure -SecretsDirectory C:\Matrix\psfdx-secrets
```

It is a separate task from any other worker's.

### Configuration

`worker.config.json` is baked into the image. It starts with `boardPickup.enabled: true` and `dryRun: true`: the worker reads the board and reports its choice but writes nothing. Before going live:

1. Run `node tools/matrix/board-ids.mjs tonygward 3` with the board token. The board needs the Status options **Backlog, Todo, Doing, Blocked and Done**; replace the three `REPLACE_WITH_board-ids_OUTPUT` option IDs.
2. Set `dryRun` to `false`. A change to `worker.config.json` is in the core lane, but the image must be rebuilt (`Build`, then `Down` and `Run`) for the container to see it.

### Updating the pins

`versions.json` records the exact Claude Code, PowerShell and Pester versions. `node claude-version.mjs decide --current <version>` suggests a newer Claude Code under the same rules as the reference (stable only, not deprecated, at least three days old, never a downgrade or a new major without a flag). Changing a pin, the Dockerfile, a script or the proxy allow-list always needs a person to merge.

## What this does not prove

The self-test proves this container is **configured as designed**. It does not prove the host is safe.

- wslc has no read-only root file system, capability-drop, no-new-privileges or PID-limit flags. File permissions and the entrypoint do that work instead, and `Verify` checks the result.
- The container starts as root for a few seconds, and the root test broker keeps running beside the worker. The broker is small and validates every request, but a bug in it would be a root bug inside the container.
- With `proxyauth` the test user is kept off the network by a credential rather than a namespace (see above). Stray test processes are killed after each run (`pkill -u matrix-test`) because there is no PID namespace either.
- The proxy limits where the container can connect, not what it sends to the allowed hosts. The agent token can write to psfdx, so keep it a fine-grained token for that one repository.
- Pull requests that Matrix opens are still checked by hosted CI and the merge gate, which are the real safeguards for what reaches `main`.
- Anything that widens the allow-list (for example the PowerShell Gallery check that AUTO-11 turns on) needs a person.
