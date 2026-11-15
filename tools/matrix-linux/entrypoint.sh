#!/bin/sh
# Container entry point. It starts as root only to prepare folders, copy the secrets and start the test broker, then drops to the
# unprivileged agent (no capabilities, no-new-privileges) and re-runs itself. Secrets are read-only files and are never printed.
# The worker process itself never has the GitHub token in its environment: it reads the file only when it calls git or gh, and
# Claude (the agent) never receives it at all.
set -eu
umask 077
CONFIG=/opt/matrix/worker.config.json
SOURCE=/work/source
STATE=/work/state

if [ "$(id -u)" = "0" ]; then
  # ---- root: setup only ----
  install -d -m 0711 /work
  install -d -o 10001 -g 10001 -m 0700 "$STATE"
  # The agent clones the repository here. Only the agent can enter it (the test user and other users cannot).
  install -d -o 10001 -g 10001 -m 0700 "$SOURCE"
  install -d -o 10001 -g 10001 -m 0711 /work/worktrees
  install -d -m 0711 /work/scratch /work/broker
  install -d -o 10001 -g 10001 -m 0700 /work/broker/in
  # The agent reads and removes the broker's answers, so it owns the answers folder (the test user can't enter /work/broker/out).
  install -d -o 10001 -g 10001 -m 0700 /work/broker/out
  # The raw mount (/opt/host-secrets) is root-only. The agent gets private copies it alone can read.
  for name in agent_github_token board_token; do
    if [ -r "/opt/host-secrets/$name" ]; then install -m 0400 -o 10001 -g 10001 "/opt/host-secrets/$name" "/run/matrix-secrets/$name"; fi
  done
  # This script is the only launcher, so a leftover lock can only be from a killed container.
  rm -f "$STATE/worker.lock" /work/broker/in/* /work/broker/out/* 2>/dev/null || true
  # The broker is the only thing that can run code as the test user. It is root, tiny, and validates every request.
  /opt/matrix/test-broker.sh >> /work/broker/broker.log 2>&1 &
  exec setpriv --reuid=10001 --regid=10001 --clear-groups --bounding-set=-all --inh-caps=-all --no-new-privs "$0" "$@"
fi

# ---- agent ----
case "${1:-verify}" in
  verify)
    exec /opt/matrix/verify-isolation.sh
    ;;
  login)
    # One-time, interactive: subscription sign-in. The usage gate requires a claude.ai subscription login
    # (it refuses API keys and alternate providers), so no API key is used anywhere in this container.
    exec claude auth login
    ;;
  claude-version)
    claude --version | sed 's/ .*//'
    ;;
  claude-check)
    exec claude auth status --json
    ;;
  worker)
    [ -r /run/matrix-secrets/agent_github_token ] || { echo "Missing agent_github_token (mount a secrets folder; see README)." >&2; exit 2; }
    mkdir -p /work/state /work/worktrees
    # A fresh clone is the canonical checkout; the worker only ever fetches and creates worktrees from it.
    if [ ! -d "$SOURCE/.git" ]; then
      ( GH_TOKEN=$(cat /run/matrix-secrets/agent_github_token) \
        GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        git -c credential.helper= -c 'credential.helper=!/usr/bin/gh auth git-credential' \
        clone --no-tags https://github.com/tonygward/psfdx.git "$SOURCE" )
    fi
    echo "psfdx Matrix worker started $(date -u +%FT%TZ). Pause: touch $STATE/PAUSED"
    # Every five minutes: the board tick, then the worker (worker.mjs runs both and honours the pause file).
    while :; do
      node /opt/matrix/tools/matrix/worker.mjs "$CONFIG" || true
      sleep 300
    done
    ;;
  *)
    echo "Unknown mode: $1 (use verify, login, claude-check, claude-version or worker)" >&2
    exit 64
    ;;
esac
