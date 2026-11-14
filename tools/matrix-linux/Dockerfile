# psfdx Matrix developer agent: isolated Linux container (AUTO-09).
# Runs under wslc (WSL containers); plain OCI, so it also builds with Docker. It holds Node, Git, the GitHub CLI, a pinned Claude Code,
# and PowerShell 7 with Pester 5, because Matrix builds and tests the code here before anything reaches GitHub (AUTO-07). It has no
# Docker CLI, no sudo and no set-id programs. Names are all prefixed psfdx-matrix- so it never shares anything with another worker.
# Build (context = repository root):  ./tools/matrix-linux/Start-MatrixPsfdx.ps1 -Action Build
# The pinned versions live in versions.json (checked by claude-version.mjs) and are passed in as build arguments.
ARG NODE_IMAGE=node:24-bookworm-slim
FROM ${NODE_IMAGE}

ARG CLAUDE_CODE_VERSION
ARG POWERSHELL_VERSION
ARG PESTER_VERSION
RUN test -n "$CLAUDE_CODE_VERSION" && test -n "$POWERSHELL_VERSION" && test -n "$PESTER_VERSION" \
 || (echo "Pass --build-arg CLAUDE_CODE_VERSION, POWERSHELL_VERSION and PESTER_VERSION (Start-MatrixPsfdx.ps1 -Action Build does)" >&2; exit 1)

# PowerShell and Pester are installed now, at build time, because the egress proxy does not allow the PowerShell Gallery at run time.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git gnupg jq util-linux procps \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && curl -fsSL https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -o /tmp/packages-microsoft-prod.deb \
 && dpkg -i /tmp/packages-microsoft-prod.deb && rm /tmp/packages-microsoft-prod.deb \
 && apt-get update && apt-get install -y --no-install-recommends gh "powershell=${POWERSHELL_VERSION}-1.deb" \
 && pwsh -NoProfile -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module Pester -RequiredVersion '${PESTER_VERSION}' -Scope AllUsers -Force -SkipPublisherCheck" \
 && pwsh -NoProfile -Command "if ((Get-Module Pester -ListAvailable | Where-Object { \$_.Version -eq [version]'${PESTER_VERSION}' }).Count -ne 1) { exit 1 }" \
 && npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
 && apt-get purge -y curl gnupg && apt-get autoremove -y && rm -rf /var/lib/apt/lists/* /root/.npm /root/.local /tmp/* \
 # No set-id binaries: nothing in this image can gain privilege.
 && find / -xdev -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

# Trusted worker code and configuration are baked in (read-only at run time), never mounted from the host. The folder layout
# keeps the relative imports (tools/matrix -> ../../scripts) working.
COPY --chown=root:root tools/matrix/*.mjs /opt/matrix/tools/matrix/
COPY --chown=root:root scripts/matrix/automerge.mjs /opt/matrix/scripts/matrix/
COPY --chown=root:root scripts/release/bump-lib.mjs /opt/matrix/scripts/release/
COPY --chown=root:root tools/matrix-linux/entrypoint.sh tools/matrix-linux/verify-isolation.sh tools/matrix-linux/test-broker.sh \
     tools/matrix-linux/sandbox-probe.sh tools/matrix-linux/run-tests-sandboxed tools/matrix-linux/worker.config.json tools/matrix-linux/versions.json /opt/matrix/
RUN chmod 0555 /opt/matrix/entrypoint.sh /opt/matrix/verify-isolation.sh /opt/matrix/test-broker.sh /opt/matrix/sandbox-probe.sh /opt/matrix/run-tests-sandboxed \
 && chmod 0444 /opt/matrix/worker.config.json /opt/matrix/versions.json /opt/matrix/tools/matrix/*.mjs /opt/matrix/scripts/*/*.mjs

# Two unprivileged identities with no login shell and no password: the worker (agent) and the test user (matrix-test).
# The test user runs agent-written code, so it shares no group with the agent and owns nothing except what the broker gives it.
RUN groupadd --gid 10001 agent && useradd --uid 10001 --gid 10001 --no-create-home --home-dir /home/agent --shell /usr/sbin/nologin agent \
 && groupadd --gid 10002 matrix-test && useradd --uid 10002 --gid 10002 --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin matrix-test
# Home folder owned by the agent so a mounted volume (the Claude sign-in) is writable by it. Only the agent can enter it.
RUN mkdir -p /home/agent /work /opt/host-secrets /run/matrix-secrets \
 && chown 10001:10001 /home/agent && chmod 0700 /home/agent \
 && chmod 0711 /work \
 # The host secrets mount point is closed to everyone except root, so neither the agent nor the test user can read the raw mount.
 && chmod 0700 /opt/host-secrets \
 && chown 10001:10001 /run/matrix-secrets && chmod 0500 /run/matrix-secrets

WORKDIR /work
ENV HOME=/home/agent \
    NODE_ENV=production \
    GIT_TERMINAL_PROMPT=0 \
    DISABLE_AUTOUPDATER=1 \
    POWERSHELL_TELEMETRY_OPTOUT=1 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1
# The container starts as root only to set up folders, copy the secrets and start the test broker. The entrypoint then drops to the agent
# with no capabilities and no-new-privileges, and everything the worker does runs as that user.
ENTRYPOINT ["/opt/matrix/entrypoint.sh"]
CMD ["verify"]
