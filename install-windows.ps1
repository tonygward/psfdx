[CmdletBinding()]
Param(
    [ValidateSet('CurrentUser','AllUsers')][string] $Scope = 'CurrentUser',
    [switch] $IncludeTests
)

$ErrorActionPreference = 'Stop'

# Load shared module list
. (Join-Path -Path $PSScriptRoot -ChildPath 'modules.ps1')
$modules = Get-PsfdxModules

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
        Get-ChildItem -Path $target -Recurse -Filter '*.Tests.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "Installed modules to: $dest" -ForegroundColor Green
