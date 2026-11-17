[CmdletBinding()]
Param(
    # Where the bundle is assembled. out/psfdx is the folder that gets published.
    [Parameter(Mandatory = $false)][string] $OutputFolder,
    [Parameter(Mandatory = $false)][string] $Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

# Builds the one bundled `psfdx` package for the PowerShell Gallery. The repository keeps seven separate modules (one folder,
# manifest, .psm1 and test file each) so development doesn't change; this script only assembles them into out/psfdx/ and
# generates the bundle manifest. Works on Windows PowerShell 5.1 and PowerShell 7.
#
# GUIDs: the repository's core module (psfdx/) keeps its GUID 2785d2bf-775f-4f2b-9d00-ee98f0163cf0 for the BUNDLE, so the Gallery
# identity is stable. Inside the bundle the core module becomes a nested module in the folder psfdx-core and gets the GUID below.
$ErrorActionPreference = 'Stop'
$bundleGuid = '2785d2bf-775f-4f2b-9d00-ee98f0163cf0'
$nestedCoreGuid = '5d3b1c7e-6a0e-4b8e-9f43-7c1a2e0d9b64'

if (-not $OutputFolder) { $OutputFolder = Join-Path (Join-Path $Root 'out') 'psfdx' }
. (Join-Path $Root 'modules.ps1')
$version = (Get-Content -Path (Join-Path $Root 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION must be three numeric parts, got '$version'" }

# Order matters: the shared helpers load first, then the core module, then the rest as modules.ps1 lists them.
$modules = @('psfdx-shared', 'psfdx') + @(Get-PsfdxModules | Where-Object { $_ -notin @('psfdx-shared', 'psfdx') })
$folderFor = @{}
foreach ($module in $modules) { $folderFor[$module] = if ($module -eq 'psfdx') { 'psfdx-core' } else { $module } }

if (Test-Path -LiteralPath $OutputFolder) { Remove-Item -LiteralPath $OutputFolder -Recurse -Force }
New-Item -ItemType Directory -Path $OutputFolder | Out-Null
$outputFull = (Resolve-Path -LiteralPath $OutputFolder).Path

# 1. Copy each module (without tests) and fix its manifest for life inside the bundle.
$exports = @{}
foreach ($module in $modules) {
    $source = Join-Path $Root $module
    $target = Join-Path $outputFull $folderFor[$module]
    New-Item -ItemType Directory -Path $target | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $source -Recurse -File) {
        if ($item.Name -like '*.Tests.ps1') { continue }
        $relative = $item.FullName.Substring($source.TrimEnd('\', '/').Length).TrimStart('\', '/')
        $destination = Join-Path $target $relative
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $item.FullName -Destination $destination
    }
    $manifestPath = Join-Path $source "$module.psd1"
    $data = Import-PowerShellDataFile -Path $manifestPath
    if ($data.ModuleVersion -ne $version) { throw "$module is $($data.ModuleVersion), expected $version" }
    foreach ($name in @($data.FunctionsToExport)) {
        if ($name -match '[*?]') { throw "$module exports a wildcard ('$name'); exports must be explicit" }
        if ($exports.ContainsKey($name)) { throw "Function '$name' is exported by both $($exports[$name]) and $module" }
        $exports[$name] = $module
    }
    # The nested copy of the manifest: the core module is renamed (the bundle takes the name psfdx), and RequiredModules is
    # emptied because inside the bundle the modules load each other as siblings.
    $text = Get-Content -LiteralPath $manifestPath -Raw
    $newName = $folderFor[$module]
    $text = [regex]::Replace($text, "(RootModule\s*=\s*)'$([regex]::Escape($module)).psm1'", "`$1'$newName.psm1'")
    $text = [regex]::Replace($text, '(?m)^(\s*RequiredModules\s*=\s*)@\([^)]*\)', '$1@()')
    if ($module -eq 'psfdx') { $text = [regex]::Replace($text, "(GUID\s*=\s*)'[0-9a-fA-F-]+'", "`$1'$nestedCoreGuid'") }
    Set-Content -LiteralPath (Join-Path $target "$newName.psd1") -Value $text -Encoding UTF8
    if ($module -eq 'psfdx') {
        Move-Item -LiteralPath (Join-Path $target 'psfdx.psm1') -Destination (Join-Path $target 'psfdx-core.psm1')
        Remove-Item -LiteralPath (Join-Path $target 'psfdx.psd1') -Force
    }
}

# The licence text ships in the bundle root, next to the manifest.
$licenseFile = Join-Path $Root 'LICENSE'
if (-not (Test-Path -LiteralPath $licenseFile)) { throw "LICENSE not found at $licenseFile" }
Copy-Item -LiteralPath $licenseFile -Destination (Join-Path $outputFull 'LICENSE')

# 2. The Gallery metadata comes from one place: the core module's manifest (PrivateData.PSData).
$core = Import-PowerShellDataFile -Path (Join-Path (Join-Path $Root 'psfdx') 'psfdx.psd1')
$psData = $core.PrivateData.PSData
$tags = @($psData.Tags)
$projectUri = [string]$psData.ProjectUri
$iconUri = [string]$psData.IconUri
$licenseUri = [string]$psData.LicenseUri
$releaseNotes = "$projectUri/releases/tag/v$version"

# 3. Generate the bundle manifest. NestedModules lists the shared helpers first, then the core module and the others.
$nested = @($modules | ForEach-Object { "'$($folderFor[$_])/$($folderFor[$_]).psd1'" })
$functionList = @($exports.Keys | Sort-Object | ForEach-Object { "        '$_'" })
$lines = @(
    '@{'
    "    ModuleVersion        = '$version'"
    "    GUID                 = '$bundleGuid'"
    "    Author               = '$($core.Author)'"
    "    CompanyName          = 'psfdx'"
    "    Copyright            = 'Copyright (c) 2020 Tony Ward.'"
    "    Description          = '$(([string]$core.Description).Replace("'", "''"))'"
    "    PowerShellVersion    = '5.1'"
    "    CompatiblePSEditions = @('Desktop', 'Core')"
    "    NestedModules        = @($($nested -join ', '))"
    '    FunctionsToExport    = @('
    ($functionList -join ",`n")
    '    )'
    '    CmdletsToExport      = @()'
    '    VariablesToExport    = @()'
    '    AliasesToExport      = @()'
    '    PrivateData          = @{'
    '        PSData = @{'
    "            Tags         = @($(($tags | ForEach-Object { "'$_'" }) -join ', '))"
    "            ProjectUri   = '$projectUri'"
)
if ($licenseUri) { $lines += "            LicenseUri   = '$licenseUri'" }
if ($iconUri) { $lines += "            IconUri      = '$iconUri'" }
$lines += @(
    "            ReleaseNotes = '$releaseNotes'"
    '        }'
    '    }'
    '}'
)
Set-Content -LiteralPath (Join-Path $outputFull 'psfdx.psd1') -Value ($lines -join "`n") -Encoding UTF8

Write-Output $outputFull
