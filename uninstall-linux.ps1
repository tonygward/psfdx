[CmdletBinding(SupportsShouldProcess = $true)]
Param(
    [ValidateSet('CurrentUser','AllUsers','Both')][string] $Scope = 'CurrentUser'
)

$ErrorActionPreference = 'Stop'

# Load shared module list
. (Join-Path -Path $PSScriptRoot -ChildPath 'modules.ps1')
$modules = Get-PsfdxModules

# Determine uninstall targets based on Scope (mirror install-linux.ps1)
if ($Scope -eq 'AllUsers') {
    $destinations = @((Join-Path -Path $PSHOME -ChildPath 'Modules'))
} elseif ($Scope -eq 'Both') {
    $xdg = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path -Path $HOME -ChildPath '.local/share' }
    $userDest = Join-Path -Path $xdg -ChildPath 'powershell/Modules'
    $allDest = Join-Path -Path $PSHOME -ChildPath 'Modules'
    $destinations = @($userDest, $allDest)
} else {
    $xdg = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path -Path $HOME -ChildPath '.local/share' }
    $destinations = @((Join-Path -Path $xdg -ChildPath 'powershell/Modules'))
}

$removed = @()
$notFound = @()
$failed = @()

foreach ($root in $destinations) {
    foreach ($m in $modules) {
        $target = Join-Path -Path $root -ChildPath $m
        if (Test-Path -Path $target) {
            if ($PSCmdlet.ShouldProcess($target, 'Remove module directory')) {
                try {
                    Remove-Item -Path $target -Recurse -Force -ErrorAction Stop
                    $removed += $target
                } catch {
                    $failed += $target
                    Write-Verbose ("Failed to remove {0}: {1}" -f $target, $_.Exception.Message)
                }
            }
        } else {
            $notFound += $target
        }
    }
}

if ($removed.Count -gt 0) {
    Write-Host 'Removed modules:' -ForegroundColor Green
    $removed | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host 'No installed modules were found to remove for $Scope (try -Scope Both).' -ForegroundColor Yellow
}

if ($failed.Count -gt 0) {
    Write-Host 'Failed to remove (permission required for system paths).' -ForegroundColor Red
    $failed | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
    Write-Host 'Try running with sudo, for example:' -ForegroundColor Yellow
    Write-Host '  sudo pwsh -NoProfile -File ./uninstall-linux.ps1 -Scope AllUsers -Confirm:$false' -ForegroundColor Yellow
    Write-Host '  sudo pwsh -NoProfile -File ./uninstall-linux.ps1 -Scope Both -Confirm:$false' -ForegroundColor Yellow
}

Write-Verbose 'Uninstall complete.'
