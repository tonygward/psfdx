[CmdletBinding()]
Param(
    # Where the package is assembled. This folder is the one package that gets published (default out/psfdx).
    [Parameter(Mandatory = $false)][string] $OutputFolder,
    [Parameter(Mandatory = $false)][string] $Root
)

# Builds the one `psfdx` package for the PowerShell Gallery. The repository keeps separate modules (one folder, manifest, .psm1 and test file
# each) so development doesn't change; this script only assembles them into out/psfdx/ and generates the package manifest. Works on Windows
# PowerShell 5.1 and PowerShell 7.
#
# What the package is: ONE Gallery package, installed by the one command `Install-Module psfdx`, that holds every module.
#   - `psfdx` is the core module and the package's root module. It defines only the core commands.
#   - Every other module sits in a folder of its own inside the package. When `psfdx` loads (Import-Module psfdx, or the first time any psfdx command
#     is used and PowerShell loads it), the end of psfdx.psm1 imports them with -Global, so each is a module in its own right: `Get-Module`,
#     `Get-Command -Module psfdx-logs` and `Get-Command -Module 'psfdx*'` show every command under the module that really holds it, with no
#     duplicates. The loader is generated here; it is not in the source psfdx.psm1.
#   - PowerShell finds modules only as folders of their own on the module path, and one package installs one folder, so before anything has loaded
#     only the psfdx manifest is read. That manifest therefore lists EVERY public command of the suite in FunctionsToExport. In a brand-new session
#     `Get-Command -Module 'psfdx*'` lists every command and any command autoloads by name (PowerShell imports psfdx, which loads the module that
#     holds it). Until that first load the commands show the Source `psfdx`; afterwards each shows its own module. A module exports only functions
#     it defines, so once loaded `Get-Command -Module psfdx` still shows only the core commands. docs/install.md explains this.
#
# GUIDs: the core module's GUID is the Gallery identity of the package `psfdx`, so the package keeps it. Every other module has its own.
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) }
$galleryGuid = '2785d2bf-775f-4f2b-9d00-ee98f0163cf0'

. (Join-Path $Root 'modules.ps1')
$version = (Get-Content -Path (Join-Path $Root 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION must be three numeric parts, got '$version'" }
if (-not $OutputFolder) { $OutputFolder = Join-Path (Join-Path $Root 'out') 'psfdx' }

# ---- Checks: the module list, versions, exports and GUIDs ----
$repoModules = @(Get-PsfdxModules)
$coreName = 'psfdx'
if ($repoModules -notcontains $coreName) { throw "Get-PsfdxModules must list the core module '$coreName'" }
if ($repoModules -notcontains 'psfdx-shared') { throw "Get-PsfdxModules must list psfdx-shared" }
# Load order: the shared helpers first, then the other modules as modules.ps1 lists them. (The core module is the package's root module.)
$siblings = @('psfdx-shared') + @($repoModules | Where-Object { $_ -notin @($coreName, 'psfdx-shared') })

$data = @{}
$exports = @{}
$guids = @{}
foreach ($module in $repoModules) {
    $manifestPath = Join-Path (Join-Path $Root $module) "$module.psd1"
    $d = Import-PowerShellDataFile -Path $manifestPath
    $data[$module] = $d
    if ($d.ModuleVersion -ne $version) { throw "$module is $($d.ModuleVersion), expected $version" }
    if ($d.RootModule -ne "$module.psm1") { throw "$module's RootModule is '$($d.RootModule)', expected $module.psm1" }
    if (-not $d.GUID) { throw "$module has no GUID" }
    if ($guids.ContainsKey($d.GUID)) { throw "$module's GUID $($d.GUID) is also used by $($guids[$d.GUID])" }
    $guids[$d.GUID] = $module
    if ($d.PrivateData -and $d.PrivateData.PSData -and $d.PrivateData.PSData.Prerelease) { throw "$module has Prerelease = '$($d.PrivateData.PSData.Prerelease)'; the package must not be a prerelease" }
    foreach ($key in 'NestedModules', 'ScriptsToProcess', 'TypesToProcess', 'FormatsToProcess', 'RequiredAssemblies', 'FileList') {
        if (@($d[$key] | Where-Object { $_ }).Count -gt 0) { throw "$module sets $key, which the package builder does not carry over" }
    }
    foreach ($name in @($d.FunctionsToExport)) {
        if ($name -match '[*?]') { throw "$module exports a wildcard ('$name'); exports must be explicit" }
        if ($exports.ContainsKey($name)) { throw "Function '$name' is exported by both $($exports[$name]) and $module" }
        $exports[$name] = $module
    }
}
$core = $data[$coreName]
if ($core.GUID -ne $galleryGuid) { throw "The core module's GUID is $($core.GUID); it is the Gallery identity of the package psfdx and must stay $galleryGuid" }
$psData = $core.PrivateData.PSData
$projectUri = [string]$psData.ProjectUri
$iconUri = [string]$psData.IconUri
$licenseUri = [string]$psData.LicenseUri
$releaseNotes = "$projectUri/releases/tag/v$version"
$licenseFile = Join-Path $Root 'LICENSE'
if (-not (Test-Path -LiteralPath $licenseFile)) { throw "LICENSE not found at $licenseFile" }

function Q([string] $Text) { "'" + $Text.Replace("'", "''") + "'" }
function Copy-ModuleFiles([string] $Source, [string] $Target) {
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Recurse -File) {
        if ($item.Name -like '*.Tests.ps1') { continue }
        $relative = $item.FullName.Substring($Source.TrimEnd('\', '/').Length).TrimStart('\', '/')
        $destination = Join-Path $Target $relative
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $item.FullName -Destination $destination
    }
}

if (Test-Path -LiteralPath $OutputFolder) { Remove-Item -LiteralPath $OutputFolder -Recurse -Force }
New-Item -ItemType Directory -Path $OutputFolder | Out-Null
$outputFull = (Resolve-Path -LiteralPath $OutputFolder).Path

# ---- The other modules, each in a folder of its own ----
foreach ($module in $siblings) {
    $target = Join-Path $outputFull $module
    Copy-ModuleFiles (Join-Path $Root $module) $target
    # RequiredModules is emptied: the modules are loaded by psfdx itself, in order, and a module that required `psfdx` would ask for the module that is
    # still loading.
    $manifestPath = Join-Path $target "$module.psd1"
    $text = [System.IO.File]::ReadAllText($manifestPath)
    $text = [regex]::Replace($text, '(?m)^(\s*RequiredModules\s*=\s*)@\([^)]*\)', '$1@()')
    [System.IO.File]::WriteAllText($manifestPath, $text, (New-Object System.Text.UTF8Encoding($false)))
}

# ---- The core module: psfdx.psm1 gets a short start and a loader at the end ----
Copy-ModuleFiles (Join-Path $Root $coreName) $outputFull
Remove-Item -LiteralPath (Join-Path $outputFull "$coreName.psd1") -Force
$sourcePsm1 = Join-Path (Join-Path $Root $coreName) "$coreName.psm1"
$bytes = [System.IO.File]::ReadAllBytes($sourcePsm1)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$coreText = [System.IO.File]::ReadAllText($sourcePsm1)
$crlf = $coreText.Contains("`r`n")
$coreText = $coreText.Replace("`r`n", "`n")
if (-not $hasBom -and $coreText -match '[^\x00-\x7F]') { throw "$coreName.psm1 has characters outside ASCII and no byte order mark; Windows PowerShell 5.1 would misread it" }

$start = @'
# psfdx Gallery package. This line and the loader at the end of this file are added by scripts/release/Build-GalleryPackage.ps1; they are not in the
# repository's psfdx.psm1. The shared helpers sit in a folder of this package, not next to it, so they are loaded first and Import-PsfdxSharedModule
# below finds them already loaded.
Import-Module (Join-Path $PSScriptRoot 'psfdx-shared\psfdx-shared.psd1') -Global -DisableNameChecking -ErrorAction Stop

'@
$names = ($siblings | ForEach-Object { "'$_'" }) -join ', '
$loader = @"

#region psfdx Gallery package: the other modules of the suite
# Added by scripts/release/Build-GalleryPackage.ps1; it is not in the repository's psfdx.psm1.
# One Gallery package installs one module folder, so PowerShell only discovers psfdx. Loading psfdx loads the rest of the suite here, each module
# under its own name (Get-Module, Get-Command -Module psfdx-logs), so every command is attributed to the module that holds it. They are imported
# with -Global so their commands are visible to the caller, and removed again when psfdx is removed.
`$psfdxSuiteModules = @($names)
foreach (`$psfdxSuiteModule in `$psfdxSuiteModules) {
    Import-Module (Join-Path `$PSScriptRoot (Join-Path `$psfdxSuiteModule "`$psfdxSuiteModule.psd1")) -Global -DisableNameChecking -ErrorAction Stop
}
`$ExecutionContext.SessionState.Module.OnRemove = {
    foreach (`$psfdxSuiteModule in @('$(($siblings | Sort-Object -Descending) -join "', '")')) { Remove-Module -Name `$psfdxSuiteModule -Force -ErrorAction SilentlyContinue }
}
#endregion
"@
$newText = $start + $coreText.TrimEnd() + "`n" + $loader
if ($crlf) { $newText = $newText.Replace("`n", "`r`n") }
[System.IO.File]::WriteAllText((Join-Path $outputFull "$coreName.psm1"), $newText, (New-Object System.Text.UTF8Encoding($hasBom)))

# ---- The package manifest: the core module's, listing every public command of the suite so all of them are discoverable before psfdx loads ----
$tags = @($psData.Tags)
$functionList = @(@($exports.Keys) | Sort-Object | ForEach-Object { "        '$_'" })
$lines = @(
    '@{'
    "    RootModule           = 'psfdx.psm1'"
    "    ModuleVersion        = '$version'"
    "    GUID                 = '$galleryGuid'"
    "    Author               = $(Q ([string]$core.Author))"
    "    CompanyName          = 'psfdx'"
    "    Copyright            = 'Copyright (c) 2020 Tony Ward.'"
    "    Description          = $(Q ([string]$core.Description))"
    "    PowerShellVersion    = '5.1'"
    "    CompatiblePSEditions = @('Desktop', 'Core')"
    '    FunctionsToExport    = @('
    ($functionList -join ",`n")
    '    )'
    '    CmdletsToExport      = @()'
    '    VariablesToExport    = @()'
    '    AliasesToExport      = @()'
    '    PrivateData          = @{'
    '        PSData = @{'
    "            Tags         = @($(($tags | ForEach-Object { Q $_ }) -join ', '))"
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
Copy-Item -LiteralPath $licenseFile -Destination (Join-Path $outputFull 'LICENSE')

Write-Output $outputFull
