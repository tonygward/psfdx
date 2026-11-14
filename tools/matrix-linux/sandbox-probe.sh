#!/bin/sh
# Run by the test broker as the test user, inside the test sandbox, to prove what that user can and cannot do.
# Usage: sandbox-probe.sh <worktree> <results file> <scratch folder>. Prints PASS or FAIL lines; the self-test reads them.
worktree=$1; results=$2; scratch=$3; netns=${4:-unknown}
pass() { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; }
# Success means the probe was ALLOWED to do the thing, so for a forbidden action `allowed` is a failure.
forbid() { if "$@" >/dev/null 2>&1; then return 1; else return 0; fi; }

[ "$(id -u)" = "10002" ] && pass "test user is uid 10002, not root or the agent" || bad "test user is not uid 10002 ($(id -u))"
caps=$(grep '^CapEff:' /proc/self/status | awk '{print $2}')
[ "$caps" = "0000000000000000" ] && pass "test user has no capabilities" || bad "test user has capabilities: $caps"

# What it must NOT read.
for path in /run/matrix-secrets/agent_github_token /run/matrix-secrets/board_token /opt/host-secrets /home/agent /work/state /work/source /work/broker/in; do
  forbid sh -c "ls '$path' || cat '$path'" && pass "cannot read $path" || bad "can read $path"
done
other=$(ls -d /work/worktrees/*/repo 2>/dev/null | grep -v "^$worktree\$" | head -1)
if [ -n "$other" ]; then forbid ls "$other" && pass "cannot read another worktree ($other)" || bad "can read another worktree ($other)"; else pass "no other worktree to test (skipped)"; fi

# What it must NOT write.
for path in /etc/psfdx-probe /opt/matrix/psfdx-probe /work/state/psfdx-probe /work/worktrees/psfdx-probe /usr/local/bin/psfdx-probe /home/agent/psfdx-probe; do
  forbid sh -c "touch '$path'" && pass "cannot write $path" || { rm -f "$path" 2>/dev/null; bad "can write $path"; }
done

# What it MAY write: its worktree and its scratch folder.
touch "$worktree/.psfdx-probe" 2>/dev/null && { rm -f "$worktree/.psfdx-probe"; pass "can write its worktree"; } || bad "cannot write its worktree"
touch "$scratch/probe" 2>/dev/null && pass "can write its scratch folder" || bad "cannot write its scratch folder"

# Network: a new namespace with a loopback device only, no proxy settings, and no route to the proxy or the internet.
[ -z "${HTTPS_PROXY:-}${HTTP_PROXY:-}${https_proxy:-}${http_proxy:-}" ] && pass "no proxy variables" || bad "proxy variables are set"
devices=$(tail -n +3 /proc/net/dev | cut -d: -f1 | tr -d ' ' | grep -v '^lo$' | head -1)
if [ "$netns" = proxyauth ]; then
  # No network namespace is available here, so the test user shares the container network. It must still get nowhere: the proxy
  # demands a credential only the agent can read, and everything else is blocked by the internal network.
  pass "network isolation is by proxy credential (no namespace available)"
  status=$(node -e "
const http=require('http');
const r=http.request({host:'psfdx-matrix-egress',port:3128,method:'CONNECT',path:'api.github.com:443',timeout:8000});
r.on('connect',res=>{console.log(res.statusCode);process.exit(0)});r.on('error',()=>{console.log('error');process.exit(0)});r.on('timeout',()=>{console.log('timeout');process.exit(0)});r.end();" 2>/dev/null)
  [ "$status" = 407 ] && pass "the proxy refuses the test user without the credential (407)" || bad "the proxy did not refuse the test user (status $status)"
  forbid sh -c "cat /proc/1/environ" && pass "cannot read another process's environment" || bad "can read another process's environment"
else
  [ -z "$devices" ] && pass "no network device except loopback" || bad "network device present: $devices"
  if node -e "require('net').connect({host:'psfdx-matrix-egress',port:3128,timeout:2000}).on('connect',()=>process.exit(0)).on('error',()=>process.exit(1)).on('timeout',()=>process.exit(1))" 2>/dev/null; then bad "can reach the egress proxy"; else pass "cannot reach the egress proxy"; fi
fi
if node -e "require('net').connect({host:'1.1.1.1',port:443,timeout:2000}).on('connect',()=>process.exit(0)).on('error',()=>process.exit(1)).on('timeout',()=>process.exit(1))" 2>/dev/null; then bad "can reach the internet"; else pass "cannot reach the internet"; fi
exit 0
