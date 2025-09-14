[CmdletBinding(SupportsShouldProcess = $true)]
Param(
    [ValidateSet('CurrentUser','AllUsers')][string] $Scope = 'CurrentUser'
)

$ErrorActionPreference = 'Stop'

# Load shared module list
. (Join-Path -Path $PSScriptRoot -ChildPath 'modules.ps1')
$modules = Get-PsfdxModules

# Resolve target module root similar to install-windows.ps1
if ($Scope -eq 'AllUsers') {
    $dest = Join-Path -Path $PSHOME -ChildPath 'Modules'
} else {
    $dest = $env:PSModulePath -split [System.IO.Path]::PathSeparator |
        Where-Object { $_.StartsWith($HOME, [System.StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
    if (-not $dest) {
        $dest = Join-Path -Path $HOME -ChildPath 'Documents/PowerShell/Modules'
    }
}

$removed = @()
$notFound = @()
$failed = @()

foreach ($m in $modules) {
    $target = Join-Path -Path $dest -ChildPath $m
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

if ($removed.Count -gt 0) {
    Write-Host "Removed modules from: $dest" -ForegroundColor Green
    $removed | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "No installed modules were found to remove in: $dest" -ForegroundColor Yellow
}

if ($failed.Count -gt 0) {
    Write-Host 'Failed to remove (administrator privileges may be required for AllUsers).' -ForegroundColor Red
    $failed | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
    Write-Host 'Try rerunning from an elevated PowerShell, for example:' -ForegroundColor Yellow
    Write-Host '  pwsh -NoProfile -File .\uninstall-windows.ps1 -Scope AllUsers -Confirm:$false' -ForegroundColor Yellow
    Write-Host '  powershell.exe -NoProfile -File .\uninstall-windows.ps1 -Scope AllUsers -Confirm:$false' -ForegroundColor Yellow
}

Write-Verbose 'Uninstall complete.'
