[CmdletBinding()]
Param(
    [ValidateSet('CurrentUser','AllUsers')][string] $Scope = 'CurrentUser',
    [switch] $IncludeTests
)

$ErrorActionPreference = 'Stop'

# Modules to install
$modules = @(
    'psfdx-common',
    'psfdx',
    'psfdx-logs',
    'psfdx-development',
    'psfdx-metadata',
    'psfdx-packages'
)

if ($Scope -eq 'AllUsers') {
    $dest = Join-Path -Path $PSHOME -ChildPath 'Modules'
} else {
    $xdg = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path -Path $HOME -ChildPath '.local/share' }
    $dest = Join-Path -Path $xdg -ChildPath 'powershell/Modules'
}

if (-not (Test-Path -Path $dest)) {
    New-Item -Path $dest -ItemType Directory -Force | Out-Null
}

foreach ($m in $modules) {
    $src = Join-Path -Path (Get-Location).Path -ChildPath $m
    if (-not (Test-Path -Path $src)) {
        Write-Verbose "Skipping missing module source: $src"
        continue
    }
    $target = Join-Path -Path $dest -ChildPath $m
    if (Test-Path -Path $target) {
        Remove-Item -Path $target -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -Path $src -Destination $dest -Recurse -Force

    if (-not $IncludeTests) {
        # Remove test files from installed module
        Get-ChildItem -Path $target -Recurse -Filter '*Tests.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "Installed modules to: $dest" -ForegroundColor Green
