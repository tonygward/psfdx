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
    $xdg = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path -Path $HOME -ChildPath '.local/share' }
    $dest = Join-Path -Path $xdg -ChildPath 'powershell/Modules'
}

if (-not (Test-Path -Path $dest)) {
    New-Item -Path $dest -ItemType Directory -Force | Out-Null
}

# The core module used to be installed as `psfdx`. That name now belongs to the Gallery umbrella package and the core module is psfdx-core, so an old
# copy of it would define every command twice next to the new one. It is recognised by psfdx.psm1 sitting directly in the folder (a Gallery install
# keeps its files in a version folder instead, and is left alone).
foreach ($legacy in Get-PsfdxLegacyModules) {
    $old = Join-Path -Path $dest -ChildPath $legacy
    if (Test-Path -Path (Join-Path -Path $old -ChildPath "$legacy.psm1")) {
        Remove-Item -Path $old -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed the old '$legacy' module from $dest (the core module is now psfdx-core)." -ForegroundColor Yellow
    }
}

foreach ($m in $modules) {
    $src = Join-Path -Path $PSScriptRoot -ChildPath $m
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
        Get-ChildItem -Path $target -Recurse -Filter '*.Tests.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "Installed modules to: $dest" -ForegroundColor Green
