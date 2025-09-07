$ErrorActionPreference = 'Stop'

# Modules to install
$modules = @(
    'psfdx',
    'psfdx-logs',
    'psfdx-development',
    'psfdx-metadata',
    'psfdx-packages'
)

$dest = Join-Path $PSHOME 'Modules'
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
}

Write-Host "Installed modules to: $dest" -ForegroundColor Green
