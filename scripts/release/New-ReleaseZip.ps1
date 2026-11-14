[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)][string] $Version,
    [Parameter(Mandatory = $true)][string] $OutputFolder,
    [Parameter(Mandatory = $false)][string] $Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

# Builds psfdx-<Version>.zip with forward-slash entry names (Compress-Archive on 5.1 writes backslashes).
. (Join-Path $Root 'modules.ps1')
$entries = @(Get-PsfdxModules) + @(
    'install.ps1', 'install-windows.ps1', 'uninstall.ps1', 'uninstall-windows.ps1',
    'modules.ps1', 'README.md', 'CHANGELOG.md', 'LICENSE'
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder | Out-Null }
$zipPath = Join-Path $OutputFolder "psfdx-$Version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

$rootFull = (Resolve-Path $Root).Path.TrimEnd('\', '/')
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($entry in $entries) {
        $path = Join-Path $Root $entry
        if (-not (Test-Path $path)) { continue }   # LICENSE is optional
        $files = @()
        if ((Get-Item $path).PSIsContainer) { $files = @(Get-ChildItem -Path $path -Recurse -File) }
        else { $files = @(Get-Item $path) }
        foreach ($file in $files) {
            # Tests are not part of the release
            if ($file.Name -like '*.Tests.ps1') { continue }
            $relative = $file.FullName.Substring($rootFull.Length).TrimStart('\', '/') -replace '\\', '/'
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $relative) | Out-Null
        }
    }
}
finally {
    $zip.Dispose()
}
Write-Output $zipPath
