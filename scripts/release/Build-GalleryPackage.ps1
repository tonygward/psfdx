[CmdletBinding()]
Param(
    # Where the packages are assembled. Bundle: this folder is the one package that gets published (default out/psfdx).
    # Suite: this folder holds one subfolder per package (default out/suite).
    [Parameter(Mandatory = $false)][string] $OutputFolder,
    [Parameter(Mandatory = $false)][string] $Root,
    # Bundle: one `psfdx` package with every module nested inside it (what is on the Gallery today).
    # Suite: nine packages, `psfdx` (an umbrella that holds no code) plus each module under its own name, tied together with
    # RequiredModules, so Install-Module psfdx installs them all and Get-Command shows each command's real module.
    [Parameter(Mandatory = $false)][ValidateSet('Bundle', 'Suite')][string] $Layout = 'Bundle'
)

# Builds what is published to the PowerShell Gallery. The repository keeps its separate modules (one folder, manifest, .psm1 and
# test file each) so development doesn't change; this script only assembles them. Works on Windows PowerShell 5.1 and PowerShell 7.
#
# GUIDs: the Gallery package `psfdx` keeps the GUID 2785d2bf-775f-4f2b-9d00-ee98f0163cf0 in both layouts, so its identity is stable. Every
# repository module has its own GUID; the core module (psfdx-core) has its own too, since the name psfdx now belongs to the umbrella.
#
# Output: Bundle writes the one package folder and returns its path. Suite returns the package folders in the order to publish them: every
# package comes after the packages it requires, and the umbrella is last.
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) }
$umbrellaGuid = '2785d2bf-775f-4f2b-9d00-ee98f0163cf0'

. (Join-Path $Root 'modules.ps1')
$umbrella = Get-PsfdxUmbrellaModule
$version = (Get-Content -Path (Join-Path $Root 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION must be three numeric parts, got '$version'" }

# ---- Checks shared by both layouts: the module list, versions, exports, GUIDs and the dependency map ----
$repoModules = @(Get-PsfdxModules)
$dependencies = Get-PsfdxModuleDependencies
if ($repoModules -contains $umbrella) { throw "'$umbrella' is the umbrella, so it cannot also be one of the modules" }
foreach ($module in $repoModules) {
    if (-not $dependencies.Contains($module)) { throw "Get-PsfdxModuleDependencies has no entry for $module" }
    foreach ($needed in @($dependencies[$module])) { if ($needed -notin $repoModules) { throw "$module requires $needed, which is not a module in this repository" } }
}
foreach ($name in @($dependencies.Keys)) { if ($name -notin $repoModules) { throw "Get-PsfdxModuleDependencies lists $name, which is not in Get-PsfdxModules" } }

# Order: every module after the modules it requires. A loop is an error.
$order = New-Object System.Collections.Generic.List[string]
$pending = New-Object System.Collections.Generic.List[string]
foreach ($module in $dependencies.Keys) { $pending.Add($module) }
while ($pending.Count -gt 0) {
    $ready = @($pending | Where-Object { $m = $_; @($dependencies[$m] | Where-Object { $_ -notin $order }).Count -eq 0 } | Select-Object -First 1)
    if ($ready.Count -eq 0) { throw "The module dependencies loop: $($pending -join ', ') require each other" }
    $order.Add($ready[0]); [void]$pending.Remove($ready[0])
}

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
    if ($guids.ContainsKey($d.GUID) -or $d.GUID -eq $umbrellaGuid) { throw "$module's GUID $($d.GUID) is also used by $($guids[$d.GUID])" }
    $guids[$d.GUID] = $module
    if ($d.PrivateData -and $d.PrivateData.PSData -and $d.PrivateData.PSData.Prerelease) { throw "$module has Prerelease = '$($d.PrivateData.PSData.Prerelease)'; a prerelease cannot be required at an exact version" }
    foreach ($key in 'NestedModules', 'ScriptsToProcess', 'TypesToProcess', 'FormatsToProcess', 'RequiredAssemblies', 'FileList') {
        if (@($d[$key] | Where-Object { $_ }).Count -gt 0) { throw "$module sets $key, which the package builder does not carry over" }
    }
    foreach ($name in @($d.FunctionsToExport)) {
        if ($name -match '[*?]') { throw "$module exports a wildcard ('$name'); exports must be explicit" }
        if ($exports.ContainsKey($name)) { throw "Function '$name' is exported by both $($exports[$name]) and $module" }
        $exports[$name] = $module
    }
}
$core = $data['psfdx-core']
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

if ($Layout -eq 'Bundle') {
    if (-not $OutputFolder) { $OutputFolder = Join-Path (Join-Path $Root 'out') 'psfdx' }
    if (Test-Path -LiteralPath $OutputFolder) { Remove-Item -LiteralPath $OutputFolder -Recurse -Force }
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
    $outputFull = (Resolve-Path -LiteralPath $OutputFolder).Path

    # The shared helpers load first, then the core module, then the rest as modules.ps1 lists them.
    $modules = @('psfdx-shared', 'psfdx-core') + @($repoModules | Where-Object { $_ -notin @('psfdx-shared', 'psfdx-core') })
    foreach ($module in $modules) {
        $target = Join-Path $outputFull $module
        Copy-ModuleFiles (Join-Path $Root $module) $target
        # RequiredModules is emptied because inside the bundle the modules load each other as siblings.
        $manifestPath = Join-Path $target "$module.psd1"
        $text = Get-Content -LiteralPath $manifestPath -Raw
        $text = [regex]::Replace($text, '(?m)^(\s*RequiredModules\s*=\s*)@\([^)]*\)', '$1@()')
        Set-Content -LiteralPath $manifestPath -Value $text -Encoding UTF8
    }
    Copy-Item -LiteralPath $licenseFile -Destination (Join-Path $outputFull 'LICENSE')

    $tags = @($psData.Tags)
    $nested = @($modules | ForEach-Object { "'$_/$_.psd1'" })
    $functionList = @($exports.Keys | Sort-Object | ForEach-Object { "        '$_'" })
    $lines = @(
        '@{'
        "    ModuleVersion        = '$version'"
        "    GUID                 = '$umbrellaGuid'"
        "    Author               = '$($core.Author)'"
        "    CompanyName          = 'psfdx'"
        "    Copyright            = 'Copyright (c) 2020 Tony Ward.'"
        "    Description          = $(Q ([string]$core.Description))"
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
    Write-Output $outputFull
    return
}

# ---- Suite ----
if (-not $OutputFolder) { $OutputFolder = Join-Path (Join-Path $Root 'out') 'suite' }
if (Test-Path -LiteralPath $OutputFolder) { Remove-Item -LiteralPath $OutputFolder -Recurse -Force }
New-Item -ItemType Directory -Path $OutputFolder | Out-Null
$outputFull = (Resolve-Path -LiteralPath $OutputFolder).Path

$commonTags = @('Salesforce', 'SalesforceDX', 'sf', 'CLI', 'psfdx', 'PSEdition_Desktop', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
function New-PackageManifest([string] $Name, [string] $Guid, [string] $Description, [string[]] $Tags, [object[]] $Required, [string[]] $Functions, [bool] $HasRootModule) {
    $tagList = @($commonTags + $Tags | Select-Object -Unique)
    $lines = @('@{')
    if ($HasRootModule) { $lines += "    RootModule           = '$Name.psm1'" }
    $lines += @(
        "    ModuleVersion        = '$version'"
        "    GUID                 = '$Guid'"
        "    Author               = $(Q ([string]$core.Author))"
        "    CompanyName          = 'psfdx'"
        "    Copyright            = 'Copyright (c) 2020 Tony Ward.'"
        "    Description          = $(Q $Description)"
        "    PowerShellVersion    = '5.1'"
        "    CompatiblePSEditions = @('Desktop', 'Core')"
    )
    if ($Required.Count -gt 0) {
        $lines += '    RequiredModules      = @('
        $lines += (($Required | ForEach-Object { "        @{ ModuleName = '$($_.Name)'; RequiredVersion = '$version'; GUID = '$($_.Guid)' }" }) -join ",`n")
        $lines += '    )'
    }
    $lines += '    FunctionsToExport    = @('
    if ($Functions.Count -gt 0) { $lines += (($Functions | Sort-Object | ForEach-Object { "        '$_'" }) -join ",`n") }
    $lines += @(
        '    )'
        '    CmdletsToExport      = @()'
        '    VariablesToExport    = @()'
        '    AliasesToExport      = @()'
        '    PrivateData          = @{'
        '        PSData = @{'
        "            Tags         = @($(($tagList | ForEach-Object { Q $_ }) -join ', '))"
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
    return ($lines -join "`n")
}

$packages = New-Object System.Collections.Generic.List[string]
foreach ($module in $order) {
    $target = Join-Path $outputFull $module
    Copy-ModuleFiles (Join-Path $Root $module) $target
    Copy-Item -LiteralPath $licenseFile -Destination (Join-Path $target 'LICENSE')
    $required = @($dependencies[$module] | ForEach-Object { [pscustomobject]@{ Name = $_; Guid = $data[$_].GUID } })
    $moduleTags = @()
    if ($data[$module].PrivateData -and $data[$module].PrivateData.PSData) { $moduleTags = @($data[$module].PrivateData.PSData.Tags | Where-Object { $_ -and $_ -notin $commonTags }) }
    $text = New-PackageManifest -Name $module -Guid $data[$module].GUID -Description ([string]$data[$module].Description) -Tags $moduleTags -Required $required -Functions @($data[$module].FunctionsToExport) -HasRootModule $true
    Set-Content -LiteralPath (Join-Path $target "$module.psd1") -Value $text -Encoding UTF8
    $packages.Add($target)
}

# The umbrella: no code, no exports. It requires every module, so installing it installs them all, each under its own name.
$umbrellaFolder = Join-Path $outputFull $umbrella
New-Item -ItemType Directory -Path $umbrellaFolder | Out-Null
Copy-Item -LiteralPath $licenseFile -Destination (Join-Path $umbrellaFolder 'LICENSE')
$umbrellaRequired = @($order | ForEach-Object { [pscustomobject]@{ Name = $_; Guid = $data[$_].GUID } })
$umbrellaText = New-PackageManifest -Name $umbrella -Guid $umbrellaGuid -Description 'The psfdx suite: PowerShell modules that wrap the Salesforce CLI (sf). Install-Module psfdx installs every module (psfdx-core, psfdx-metadata, psfdx-development, psfdx-logs, psfdx-sandbox, psfdx-packages, psfdx-agentforce and the shared helpers), each under its own name.' -Tags @() -Required $umbrellaRequired -Functions @() -HasRootModule $false
Set-Content -LiteralPath (Join-Path $umbrellaFolder "$umbrella.psd1") -Value $umbrellaText -Encoding UTF8
$packages.Add($umbrellaFolder)

Write-Output @($packages)
