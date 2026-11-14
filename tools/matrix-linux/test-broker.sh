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

# Which kind of network namespace can be made? userns: the test user makes its own (needs unprivileged user namespaces);
# rootns: root makes it (needs CAP_SYS_ADMIN). Neither works: refuse everything.
detect() {
  if $DROP unshare --user --map-current-user --net true 2>/dev/null; then echo userns
  elif unshare --net true 2>/dev/null; then echo rootns
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

  if [ "$NETNS" = userns ]; then unsh="unshare --user --map-current-user --net --pid --fork --kill-child"; else unsh="unshare --net --pid --fork --kill-child"; fi
  if [ "$NETNS" = rootns ]; then launch="$unsh $DROP"; else launch="$DROP $unsh"; fi
  if [ "$mode" = probe ]; then
    command="/opt/matrix/sandbox-probe.sh $worktree $results $scratch"
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
  # Hand everything back to the agent and clean up.
  chown -R --no-dereference 10001:10001 "$worktree"; chown 10001:10001 "$results"; chmod 0600 "$results"
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
