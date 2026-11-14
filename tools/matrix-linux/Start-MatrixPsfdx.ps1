[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Build', 'Verify', 'Login', 'Run', 'Ensure', 'Logs', 'Pause', 'Resume', 'Stop', 'Down')][string]$Action,
    # Build only: override the pinned versions in versions.json (exact versions).
    [string]$ClaudeCodeVersion,
    [string]$PowerShellVersion,
    [string]$PesterVersion,
    # Folder OUTSIDE the repository holding agent_github_token and board_token (one value per file).
    [string]$SecretsDirectory
)
# Drives the psfdx Matrix agent container with wslc (WSL containers). Compose is not available in wslc, so this script
# does what compose.yaml would do: an internal-only network, an allow-list proxy and an unprivileged agent.
# It only touches objects named psfdx-matrix-*. Nothing else is started or removed, so a second Matrix worker on the
# same host (its own image, containers, network and volumes) is never affected.
# Use the same elevation (normal or administrator) every time: wslc keeps separate images per elevation.
#   Build   build the image            Login   one-time Claude subscription sign-in (interactive)
#   Verify  isolation self-test        Run     start the worker (detached; this is the owner's go-ahead)
#   Ensure  start the proxy and the worker if they are not running (safe at every logon)
#   Logs    show worker output         Pause / Resume   stop or allow new work without stopping the container
#   Stop    stop the worker            Down    remove the worker, proxy and network (volumes are kept)
$ErrorActionPreference = 'Stop'
$image = 'psfdx-matrix-agent:dev'
$network = 'psfdx-matrix-internal'
$proxy = 'psfdx-matrix-egress'
$agent = 'psfdx-matrix-agent'
$homeVolume = 'psfdx-matrix-home'   # holds the Claude sign-in
$workVolume = 'psfdx-matrix-work'   # holds state, worktrees and logs
$squidImage = 'ubuntu/squid:6.6-24.04_edge'
$here = $PSScriptRoot
$root = (Resolve-Path (Join-Path (Join-Path $here '..') '..')).Path

function Invoke-Wslc { & wslc @args; if ($LASTEXITCODE -ne 0) { throw "wslc $($args -join ' ') failed ($LASTEXITCODE)" } }
function Test-Wslc { & wslc @args *> $null; $LASTEXITCODE -eq 0 }
function Test-AgentRunning { @(& wslc list 2>$null | Select-String -SimpleMatch $agent).Count -gt 0 }

function Get-Pins {
    $pins = Get-Content -Raw (Join-Path $here 'versions.json') | ConvertFrom-Json
    if ($ClaudeCodeVersion) { $pins.claudeCode = $ClaudeCodeVersion }
    if ($PowerShellVersion) { $pins.powershell = $PowerShellVersion }
    if ($PesterVersion) { $pins.pester = $PesterVersion }
    $pins
}

function Start-Egress {
    if (-not (Test-Wslc network inspect $network)) { Invoke-Wslc network create --internal $network | Out-Null }
    if (-not (Test-Wslc inspect $proxy)) {
        Invoke-Wslc run -d --name $proxy --network $network -v "$(Join-Path (Join-Path $here 'squid') 'squid.conf'):/etc/squid/squid.conf:ro" $squidImage | Out-Null
        # The proxy is the only container with a route out; the agent network itself stays internal.
        Invoke-Wslc network connect bridge $proxy
    } else { & wslc start $proxy *> $null }
}

# Hardening available in wslc: memory and CPU limits, an internal network and a read-only secrets mount. The container starts as root
# only so the entrypoint can prepare folders and start the test broker; it then drops to an unprivileged user with no capabilities.
# wslc has no read-only-root, capability-drop, no-new-privileges or PID-limit flags (see the README), so the entrypoint and the file
# permissions do that work, and Verify proves it.
function Get-AgentArguments([switch]$Secrets) {
    $arguments = @('--memory', '4G', '--cpus', '2', '--tmpfs', '/tmp',
        '-v', "${workVolume}:/work", '-v', "${homeVolume}:/home/agent",
        '--network', $network, '-e', "HTTPS_PROXY=http://${proxy}:3128", '-e', "HTTP_PROXY=http://${proxy}:3128", '-e', "NO_PROXY=$proxy")
    if ($Secrets) {
        if (-not $SecretsDirectory -or -not (Test-Path (Join-Path $SecretsDirectory 'agent_github_token'))) { throw 'Pass -SecretsDirectory <folder containing agent_github_token and board_token>' }
        $arguments += @('-v', "${SecretsDirectory}:/opt/host-secrets:ro")
    }
    $arguments
}

switch ($Action) {
    'Build' {
        $pins = Get-Pins
        # The pins must be exact stable versions, and Claude Code must be in the family the usage gate accepts.
        & node (Join-Path $here 'claude-version.mjs') check --claude $pins.claudeCode --powershell $pins.powershell --pester $pins.pester
        if ($LASTEXITCODE -ne 0) { throw 'The pinned versions are not acceptable (see the message above).' }
        Invoke-Wslc build --build-arg "CLAUDE_CODE_VERSION=$($pins.claudeCode)" --build-arg "POWERSHELL_VERSION=$($pins.powershell)" --build-arg "PESTER_VERSION=$($pins.pester)" -f (Join-Path $here 'Dockerfile') -t $image $root
        Write-Output "Built $image with Claude Code $($pins.claudeCode), PowerShell $($pins.powershell) and Pester $($pins.pester)."
    }
    'Verify' {
        Start-Egress
        $arguments = Get-AgentArguments
        & wslc run --rm @arguments -e EGRESS_CHECK=1 $image verify
        exit $LASTEXITCODE
    }
    'Login' {
        Start-Egress
        $arguments = Get-AgentArguments
        & wslc run --rm -it @arguments $image login
        & wslc run --rm @arguments $image claude-check
    }
    'Run' {
        Start-Egress
        if (Test-Wslc inspect $agent) { throw "$agent already exists; use -Action Stop or Down first" }
        $arguments = Get-AgentArguments -Secrets
        Invoke-Wslc run -d --name $agent @arguments $image worker | Out-Null
        Write-Output "Worker started. Follow it with: ./Start-MatrixPsfdx.ps1 -Action Logs"
    }
    'Ensure' {
        # Safe to run at every logon: start the proxy, and start the worker only if it is not already running.
        # A stopped worker (for example after a reboot) is recreated; its state lives in the volumes.
        Start-Egress
        if (Test-AgentRunning) { Write-Output "$agent is already running."; break }
        if (Test-Wslc inspect $agent) { Invoke-Wslc remove --force $agent }
        $arguments = Get-AgentArguments -Secrets
        Invoke-Wslc run -d --name $agent @arguments $image worker | Out-Null
        Write-Output "$agent started."
    }
    'Logs' { & wslc logs $agent }
    'Pause' { Invoke-Wslc exec $agent touch /work/state/PAUSED; Write-Output 'Paused: no new work starts; work in progress finishes.' }
    'Resume' { Invoke-Wslc exec $agent rm -f /work/state/PAUSED; Write-Output 'Resumed.' }
    'Stop' { if (Test-Wslc inspect $agent) { Invoke-Wslc remove --force $agent } }
    'Down' {
        foreach ($name in $agent, $proxy) { if (Test-Wslc inspect $name) { Invoke-Wslc remove --force $name } }
        if (Test-Wslc network inspect $network) { Invoke-Wslc network remove $network }
    }
}
