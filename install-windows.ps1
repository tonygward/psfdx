[CmdletBinding()]
Param(
    [ValidateSet('CurrentUser','AllUsers')][string] $Scope = 'CurrentUser',
    [switch] $IncludeTests
)

$ErrorActionPreference = 'Stop'

# Modules to install
$modules = @(
    'psfdx',
    'psfdx-logs',
    'psfdx-development',
    'psfdx-metadata',
    'psfdx-packages'
)

if ($Scope -eq 'AllUsers') {
    $dest = Join-Path $PSHOME 'Modules'
} else {
    $dest = Join-Path $HOME 'Documents/PowerShell/Modules'
}

if (-not (Test-Path -Path $dest)) {
    New-Item -Path $dest -ItemType Directory -Force | Out-Null
}

foreach ($m in $modules) {
    $src = Join-Path (Get-Location) $m
    if (-not (Test-Path -Path $src)) {
        Write-Verbose "Skipping missing module source: $src"
        continue
    }
    $target = Join-Path $dest $m
    if (Test-Path -Path $target) {
        Remove-Item -Path $target -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -Path $src -Destination $dest -Recurse -Force

    if (-not $IncludeTests) {
        Get-ChildItem -Path $target -Recurse -Filter '*Tests.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "Installed modules to: $dest" -ForegroundColor Green
