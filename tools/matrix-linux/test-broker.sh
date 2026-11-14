#!/bin/sh
# Test broker. Runs as root inside the container and is the ONLY way anything runs as the test user (matrix-test).
# The code under test was written by the agent, so it gets no more access than the agent: the test user can read and write only
# the worktree being tested, its own results file and a scratch folder; it cannot read the secrets, the Claude sign-in, the state
# folder, the source clone or other worktrees; and it has no network (a new network namespace holds only a loopback device).
# Fails closed: if no network namespace can be created, every request is refused (exit code 125) and nothing runs.
#
# Protocol (files, so the agent needs no privilege):
#   the agent writes  /work/broker/in/<id>.req     line 1 worktree, line 2 results file, line 3 timeout in seconds, line 4 optional "probe"
#   the broker writes /work/broker/out/<id>.rc     exit code: 0 passed, 1 failed, 124 timed out, 125 refused, 3 sandbox error
# The command that runs is fixed here. The request only chooses which worktree and how long; it never supplies a command.
set -u
umask 077
IN=/work/broker/in
OUT=/work/broker/out
TEST_UID=10002
TEST_GID=10002
DROP="setpriv --reuid=$TEST_UID --regid=$TEST_GID --clear-groups --bounding-set=-all --inh-caps=-all --no-new-privs"

# How is the test user kept off the network? In order of strength:
#   userns:    the test user makes its own network namespace (needs unprivileged user namespaces)
#   rootns:    root makes it (needs CAP_SYS_ADMIN)
#   proxyauth: no namespace is possible (a container runtime whose seccomp profile blocks unshare). The test user shares the
#              container network, but the only way out is the egress proxy, which refuses anyone without the proxy credential,
#              and only the agent can read that credential. Direct connections are already blocked by the internal network.
#              This is weaker (the test user can open a TCP connection to the proxy and be refused), and it is only used when the
#              proxy really does demand credentials, which is checked here.
#   none:      refuse every request.
proxy_demands_auth() {
  [ -n "${HTTPS_PROXY:-}" ] || return 1
  status=$(node -e "
const http=require('http');const u=new URL(process.env.HTTPS_PROXY);
const r=http.request({host:u.hostname,port:u.port,method:'CONNECT',path:'api.github.com:443',timeout:8000});
r.on('connect',res=>{console.log(res.statusCode);process.exit(0)});r.on('error',()=>{console.log('error');process.exit(0)});r.on('timeout',()=>{console.log('timeout');process.exit(0)});r.end();" 2>/dev/null)
  [ "$status" = 407 ]
}
detect() {
  if $DROP unshare --user --map-current-user --net true 2>/dev/null; then echo userns
  elif unshare --net true 2>/dev/null; then echo rootns
  elif proxy_demands_auth; then echo proxyauth
  else echo none; fi
}
NETNS=$(detect)
echo "$NETNS" > /work/broker/netns
chmod 0644 /work/broker/netns
echo "broker started $(date -u +%FT%TZ); network isolation: $NETNS"

reply() { printf '%s\n' "$2" > "$OUT/$1.rc.tmp" && chmod 0644 "$OUT/$1.rc.tmp" && mv "$OUT/$1.rc.tmp" "$OUT/$1.rc"; }

handle() {
  req=$1; id=$(basename "$req" .req)
  case "$id" in *[!A-Za-z0-9_-]*|'') rm -f "$req"; return ;; esac
  [ "$NETNS" = none ] && { echo "refused $id: no network isolation available"; rm -f "$req"; reply "$id" 125; return; }
  # The agent owns the request file, so read it once, as text, and validate every field before using it.
  worktree=$(sed -n 1p "$req"); results=$(sed -n 2p "$req"); seconds=$(sed -n 3p "$req"); mode=$(sed -n 4p "$req"); rm -f "$req"
  # Exactly /work/worktrees/<PSF|AUTO>-<number>/repo and nothing else (case patterns would let a star match slashes).
  printf '%s' "$worktree" | grep -Eq '^/work/worktrees/(PSF|AUTO)-[0-9]+/repo$' || { echo "refused $id: bad worktree"; reply "$id" 125; return; }
  task=$(dirname "$worktree")
  [ "$results" = "$task/testResults.xml" ] || { echo "refused $id: results file is not in the task folder"; reply "$id" 125; return; }
  case "$seconds" in ''|*[!0-9]*) echo "refused $id: bad time limit"; reply "$id" 125; return ;; esac
  [ "$seconds" -ge 30 ] && [ "$seconds" -le 3600 ] || { echo "refused $id: time limit out of range"; reply "$id" 125; return; }
  # Real directories only: a symbolic link could point the ownership change somewhere else.
  [ -d "$worktree" ] && [ ! -L "$worktree" ] && [ ! -L "$task" ] && [ "$(realpath "$worktree")" = "$worktree" ] || { echo "refused $id: not a plain directory"; reply "$id" 125; return; }

  scratch=/work/scratch/$id
  mkdir -p "$scratch" && chown "$TEST_UID:$TEST_GID" "$scratch" && chmod 0700 "$scratch"
  : > "$results" && chown "$TEST_UID:$TEST_GID" "$results" && chmod 0600 "$results"
  # Only this worktree is handed to the test user, and only while it runs.
  chown -R --no-dereference "$TEST_UID:$TEST_GID" "$worktree"
  # The test user must be able to walk to its worktree and results file, but not list its siblings: open only this task folder.
  chmod 0711 "$task"

  case "$NETNS" in
    userns) launch="$DROP unshare --user --map-current-user --net --pid --fork --kill-child" ;;
    rootns) launch="unshare --net --pid --fork --kill-child $DROP" ;;
    *) launch="$DROP" ;;   # proxyauth: no namespace; the proxy credential keeps the test user off the network
  esac
  if [ "$mode" = probe ]; then
    command="/opt/matrix/sandbox-probe.sh $worktree $results $scratch $NETNS"
  else
    # Fixed Pester 5 command. The results file is NUnit XML in the task folder, outside the repository.
    command="pwsh -NoProfile -NonInteractive -Command"
    script="Import-Module Pester -MinimumVersion 5.0.0 -MaximumVersion 5.99.99; \$c = New-PesterConfiguration; \$c.Run.Path = '.'; \$c.Run.Exit = \$true; \$c.TestResult.Enabled = \$true; \$c.TestResult.OutputPath = '$results'; Invoke-Pester -Configuration \$c"
  fi
  cd "$worktree" || { reply "$id" 3; return; }
  if [ "$mode" = probe ]; then
    timeout -s KILL "$seconds" $launch env -i HOME="$scratch" TMPDIR="$scratch" PATH=/usr/local/bin:/usr/bin:/bin $command >> "$results" 2>&1
  else
    timeout -s KILL "$seconds" $launch env -i HOME="$scratch" TMPDIR="$scratch" PATH=/usr/local/bin:/usr/bin:/bin \
      POWERSHELL_TELEMETRY_OPTOUT=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 $command "$script" > "$scratch/output.log" 2>&1
  fi
  rc=$?
  cd /
  # Without a PID namespace nothing else stops stray processes, so end everything the test user still owns.
  pkill -KILL -u "$TEST_UID" 2>/dev/null
  # Hand everything back to the agent and clean up.
  chown -R --no-dereference 10001:10001 "$worktree"; chown 10001:10001 "$results"; chmod 0600 "$results"; chmod 0700 "$task"
  rm -rf "$scratch"
  if [ "$rc" = 0 ]; then reply "$id" 0
  elif [ "$rc" = 124 ] || [ "$rc" = 137 ]; then reply "$id" 124
  elif [ -s "$results" ]; then reply "$id" 1   # tests ran and failed (Pester exits with the failure count) or the probe found problems
  else reply "$id" 3; fi
  echo "finished $id rc=$rc"
}

while :; do
  for req in "$IN"/*.req; do
    [ -e "$req" ] || continue
    handle "$req"
  done
  sleep 1
done
