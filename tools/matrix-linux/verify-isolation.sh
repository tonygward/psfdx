#!/bin/sh
# Negative and positive isolation tests, run inside the container as the agent. Exit status is non-zero if any check fails.
# These do not prove the host is safe; they prove this container is configured as designed.
fail=0
pass() { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; fail=1; }

[ "$(id -u)" != "0" ] && pass "runs as a non-root user ($(id -u))" || bad "running as root"
[ ! -S /var/run/docker.sock ] && [ ! -e /run/docker.sock ] && pass "no Docker socket" || bad "Docker socket is present"
command -v docker >/dev/null 2>&1 && bad "docker CLI present" || pass "no Docker CLI"
command -v sudo >/dev/null 2>&1 && bad "sudo present" || pass "no sudo"

# The agent user must not be able to change the image (wslc has no --read-only flag; file permissions enforce it).
if touch /probe 2>/dev/null; then rm -f /probe; bad "root file system is writable by the agent"; else pass "cannot write to the root file system"; fi
if touch /opt/matrix/probe 2>/dev/null; then rm -f /opt/matrix/probe; bad "the baked-in worker code is writable by the agent"; else pass "worker code is read-only to the agent"; fi
if touch /work/.probe 2>/dev/null; then rm -f /work/.probe; bad "/work itself is writable (only its subfolders should be)"; else pass "/work is not writable, its subfolders are"; fi
if touch /work/state/.probe 2>/dev/null; then rm -f /work/state/.probe; pass "state folder is writable"; else bad "state folder is not writable"; fi

# No Linux capabilities and no privilege gain.
caps=$(grep '^CapEff:' /proc/self/status | awk '{print $2}')
[ "$caps" = "0000000000000000" ] && pass "no effective capabilities" || bad "capabilities present: $caps"
bounding=$(grep '^CapBnd:' /proc/self/status | awk '{print $2}')
[ "$bounding" = "0000000000000000" ] && pass "capability bounding set is empty" || bad "capability bounding set is not empty: $bounding"
if grep -q '^NoNewPrivs:[[:space:]]*1' /proc/self/status; then pass "no-new-privileges set"
elif [ -z "$(find / -xdev -perm /6000 -type f 2>/dev/null | head -1)" ]; then pass "no set-id programs exist, so there is nothing to gain privilege from"
else bad "set-id programs exist and no-new-privileges is not set"; fi
[ -z "$(find / -xdev -perm /6000 -type f 2>/dev/null | head -1)" ] && pass "no set-id programs" || bad "set-id programs exist"

# Publishing credentials must never be available to the agent, and the mounted secrets must be the two we expect.
for name in RELEASE_TOKEN PSGALLERY_API_KEY GH_TOKEN GITHUB_TOKEN ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN; do
  [ -z "$(printenv "$name")" ] || bad "$name is set"
done
pass "no release, publishing or API-key credentials in the environment"
ls /run/matrix-secrets 2>/dev/null | grep -Eqi 'publish|release|gallery|cloudflare|r2|dispatch|anthropic' && bad "a publishing secret is present" || pass "no publishing secrets present"
for name in agent_github_token board_token; do
  [ ! -e "/run/matrix-secrets/$name" ] || { [ -r "/run/matrix-secrets/$name" ] && pass "$name is readable by the agent only" || bad "$name exists but is not readable by the agent"; }
done
[ ! -r /opt/host-secrets ] && pass "the raw secrets mount is closed to the agent" || bad "the raw secrets mount is open to the agent"

# Tools the worker needs. PowerShell 7 and Pester 5 are baked in because the proxy refuses the PowerShell Gallery.
claude --version >/dev/null 2>&1 && pass "claude CLI runs" || bad "claude CLI missing"
git --version >/dev/null 2>&1 && pass "git present" || bad "git missing"
gh --version >/dev/null 2>&1 && pass "gh present" || bad "gh missing"
node --version | grep -q '^v24\.' && pass "Node 24" || bad "Node is not 24"
pinned=$(node -e "const v=require('/opt/matrix/versions.json');console.log(v.powershell+' '+v.pester+' '+v.claudeCode)")
set -- $pinned
shell_version=$(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null)
[ "$shell_version" = "$1" ] && pass "PowerShell $shell_version (pinned)" || bad "PowerShell is '$shell_version', pinned $1"
pester_version=$(pwsh -NoProfile -Command '(Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString()' 2>/dev/null)
[ "$pester_version" = "$2" ] && pass "Pester $pester_version (pinned)" || bad "Pester is '$pester_version', pinned $2"
claude_version=$(claude --version 2>/dev/null | sed 's/ .*//')
[ "$claude_version" = "$3" ] && pass "Claude Code $claude_version (pinned)" || bad "Claude Code is '$claude_version', pinned $3"

# The test sandbox: ask the broker to run the probe as the test user.
netns=$(cat /work/broker/netns 2>/dev/null)
echo "INFO  network isolation for the test user: ${netns:-unknown}"
if [ "$netns" = userns ] || [ "$netns" = rootns ] || [ "$netns" = proxyauth ]; then
  if [ "$netns" = proxyauth ]; then pass "no network namespace is possible here, so the proxy credential keeps the test user off the network"; else pass "a network namespace can be created for the test user ($netns)"; fi
  mkdir -p /work/worktrees/AUTO-00/repo /work/worktrees/AUTO-01/repo
  echo "do not read" > /work/worktrees/AUTO-01/repo/other.txt; chmod 0600 /work/worktrees/AUTO-01/repo/other.txt
  echo "secret-canary" > /work/state/canary; chmod 0600 /work/state/canary
  PSFDX_SANDBOX_MODE=probe /opt/matrix/run-tests-sandboxed /work/worktrees/AUTO-00/repo /work/worktrees/AUTO-00/testResults.xml 60
  rc=$?
  [ "$rc" = 0 ] && pass "the sandbox probe ran" || bad "the sandbox probe did not run cleanly (exit code $rc)"
  while IFS= read -r line; do
    case "$line" in
      PASS*) pass "test user: ${line#PASS  }" ;;
      FAIL*) bad "test user: ${line#FAIL  }" ;;
    esac
  done < /work/worktrees/AUTO-00/testResults.xml
  grep -q '^PASS' /work/worktrees/AUTO-00/testResults.xml || bad "the sandbox probe produced no results"
  rm -rf /work/worktrees/AUTO-00 /work/worktrees/AUTO-01 /work/state/canary
else
  bad "no network namespace can be created for the test user, so the test sandbox refuses to run tests"
fi

# Network: only the egress proxy is reachable; direct internet and the home network are not.
if [ -n "${EGRESS_CHECK:-}" ]; then
  if node -e "require('net').connect({host:'1.1.1.1',port:443,timeout:3000}).on('connect',()=>process.exit(0)).on('error',()=>process.exit(1)).on('timeout',()=>process.exit(1))" 2>/dev/null; then bad "direct internet access works (bypasses the proxy)"; else pass "direct internet access blocked"; fi
  if node -e "require('net').connect({host:'192.168.1.1',port:80,timeout:3000}).on('connect',()=>process.exit(0)).on('error',()=>process.exit(1)).on('timeout',()=>process.exit(1))" 2>/dev/null; then bad "home network reachable"; else pass "home network not reachable"; fi
  connect() { node -e "
const http=require('http');const p=new URL(process.env.HTTPS_PROXY);
const h={};if(p.username)h['Proxy-Authorization']='Basic '+Buffer.from(decodeURIComponent(p.username)+':'+decodeURIComponent(p.password)).toString('base64');
const r=http.request({host:p.hostname,port:p.port,method:'CONNECT',path:process.argv[1]+':443',headers:h,timeout:8000});
r.on('connect',res=>{console.log(res.statusCode);process.exit(0)});r.on('error',()=>{console.log('error');process.exit(0)});r.on('timeout',()=>{console.log('timeout');process.exit(0)});r.end();" "$1" 2>/dev/null; }
  for host in example.com 192.168.1.1 registry.npmjs.org; do
    status=$(connect "$host")
    [ "$status" != "200" ] && pass "proxy refuses $host ($status)" || bad "proxy allowed $host"
  done
  # Without the credential the proxy must refuse even an allowed host (this is what keeps the test user out).
  anon=$(node -e "
const http=require('http');const p=new URL(process.env.HTTPS_PROXY);
const r=http.request({host:p.hostname,port:p.port,method:'CONNECT',path:'api.github.com:443',timeout:8000});
r.on('connect',res=>{console.log(res.statusCode);process.exit(0)});r.on('error',()=>{console.log('error');process.exit(0)});r.on('timeout',()=>{console.log('timeout');process.exit(0)});r.end();" 2>/dev/null)
  [ "$anon" = "407" ] && pass "proxy demands its credential (407 without it)" || bad "proxy answered $anon without a credential"
  for host in api.anthropic.com api.github.com github.com www.powershellgallery.com; do
    status=$(connect "$host")
    [ "$status" = "200" ] && pass "proxy allows $host" || bad "proxy refused $host ($status)"
  done
else
  echo "SKIP  network checks (run through Start-MatrixPsfdx.ps1 -Action Verify)"
fi

[ "$fail" = 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit "$fail"
