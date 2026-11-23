<#
.SYNOPSIS
Checks that an installed copy of the psfdx suite behaves as one install of several modules.
.DESCRIPTION
Run it against a folder that Save-Module or Install-Module filled from a package repository (the PowerShell Gallery, or the local repository
the CI builds). It never imports anything from the source tree: every check runs in a fresh PowerShell process whose module path is that folder
alone, so it sees what a new user sees. It checks that:
  1. one install brought the umbrella `psfdx` and every module, each at the expected version;
  2. Get-Module -ListAvailable 'psfdx*' lists all of them;
  3. Get-Command -Module 'psfdx*' finds every exported command with no import at all, and each command's Source is the module that really
     holds it (psfdx-metadata, psfdx-development, psfdx-agentforce and so on), not the umbrella;
  4. Import-Module psfdx loads the whole suite, the umbrella exports nothing, and no command name exists twice;
  5. optionally, a standalone module installed on its own (with the dependencies the Gallery gives it) imports and exports its commands,
     without loading the rest of the suite.
What each module should export comes from the manifests in the repository (-Root). Works on Windows PowerShell 5.1 and PowerShell 7, needs no
Salesforce CLI and no org. Throws, listing every problem, when anything is wrong.
#>
[CmdletBinding()]
Param(
    # The folder that holds the installed module folders (the Save-Module -Path).
    [Parameter(Mandatory = $true)][string] $ModulePath,
    # The version that was installed. Defaults to the repository's VERSION.
    [Parameter(Mandatory = $false)][string] $Version,
    [Parameter(Mandatory = $false)][string] $Root,
    # A second folder that holds only one module saved on its own, with its dependencies.
    [Parameter(Mandatory = $false)][string] $StandalonePath,
    # The module saved in -StandalonePath.
    [Parameter(Mandatory = $false)][string] $StandaloneModule = 'psfdx-logs'
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) }
. (Join-Path $Root 'modules.ps1')
if (-not $Version) { $Version = (Get-Content -Path (Join-Path $Root 'VERSION') -Raw).Trim() }
$umbrella = Get-PsfdxUmbrellaModule
$modules = @(Get-PsfdxModules)
$dependencies = Get-PsfdxModuleDependencies
$expectedExports = @{}
foreach ($module in $modules) { $expectedExports[$module] = @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $Root $module) "$module.psd1")).FunctionsToExport | Sort-Object) }
$expectedNames = @(@($umbrella) + $modules | Sort-Object)
$shell = (Get-Process -Id $PID).Path
$problems = New-Object System.Collections.Generic.List[string]

# Runs a script in a fresh PowerShell whose module path is only $Path, and returns what it printed as an object.
function Invoke-FreshSession([string] $Path, [string] $Script) {
    $header = "`$ErrorActionPreference = 'Stop'; `$WarningPreference = 'SilentlyContinue'; `$env:PSModulePath = `$env:PSFDX_SUITE_PATH; "
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($header + $Script))
    $previous = $env:PSFDX_SUITE_PATH
    $env:PSFDX_SUITE_PATH = $Path
    try { $output = & $shell -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1 | Out-String } finally { $env:PSFDX_SUITE_PATH = $previous }
    if ($LASTEXITCODE -ne 0) { throw "A fresh PowerShell session failed:`n$output" }
    $json = @($output -split "`r?`n" | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -Last 1)
    if ($json.Count -eq 0) { throw "A fresh PowerShell session printed no result:`n$output" }
    return ($json[0] | ConvertFrom-Json)
}
function Add-Problem([string] $Text) { $problems.Add($Text) }
function Same([object[]] $A, [object[]] $B) { (@($A | Sort-Object) -join '|') -eq (@($B | Sort-Object) -join '|') }

# ---- 1. One install brought everything, at the right version ----
$folders = @(Get-ChildItem -LiteralPath $ModulePath -Directory | Where-Object { $_.Name -like 'psfdx*' } | ForEach-Object Name | Sort-Object)
if (-not (Same $folders $expectedNames)) { Add-Problem "The install folder holds [$($folders -join ', ')] but the suite is [$($expectedNames -join ', ')]" }
foreach ($name in $expectedNames) {
    $versionFolder = Join-Path (Join-Path $ModulePath $name) $Version
    if (-not (Test-Path -LiteralPath (Join-Path $versionFolder "$name.psd1"))) { Add-Problem "$name $Version is not installed (no $name.psd1 in $versionFolder)" }
}

# ---- 2 and 3. Listing and discovery in a clean session, with no import ----
$discover = @'
$listed = @(Get-Module -ListAvailable 'psfdx*' | ForEach-Object { $_.Name + ' ' + $_.Version })
$loadedBefore = @(Get-Module 'psfdx*' | ForEach-Object Name)
$commands = @(Get-Command -Module 'psfdx*' | Where-Object { $_.CommandType -eq 'Function' })
$bySource = @{}
foreach ($g in ($commands | Group-Object Source)) { $bySource[$g.Name] = @($g.Group | ForEach-Object Name | Sort-Object) }
[pscustomobject]@{ listed = $listed; loadedBefore = $loadedBefore; bySource = $bySource } | ConvertTo-Json -Compress -Depth 4
'@
$found = Invoke-FreshSession $ModulePath $discover
$listedExpected = @($expectedNames | ForEach-Object { "$_ $Version" })
if (-not (Same @($found.listed) $listedExpected)) { Add-Problem "Get-Module -ListAvailable 'psfdx*' lists [$(@($found.listed) -join ', ')], expected [$($listedExpected -join ', ')]" }
if (@($found.loadedBefore).Count -ne 0) { Add-Problem "The clean session already had psfdx modules loaded: $(@($found.loadedBefore) -join ', ')" }
foreach ($module in $modules) {
    $names = @($found.bySource.$module)
    if (-not (Same $names $expectedExports[$module])) {
        $missing = @($expectedExports[$module] | Where-Object { $_ -notin $names }); $extra = @($names | Where-Object { $_ -and $_ -notin $expectedExports[$module] })
        Add-Problem "Get-Command -Module 'psfdx*' (no import) shows $($names.Count) commands from $module, expected $($expectedExports[$module].Count). Missing: $($missing -join ', '). Extra: $($extra -join ', ')"
    }
}
if (@($found.bySource.PSObject.Properties.Name | Where-Object { $_ -eq $umbrella }).Count -gt 0) { Add-Problem "Commands show $umbrella as their source; the umbrella must hold none, the modules own them" }

# ---- 4. Import-Module psfdx: the whole suite, nothing twice ----
$import = @'
Import-Module psfdx -RequiredVersion '__VERSION__'
$loaded = @(Get-Module 'psfdx*' | ForEach-Object { $_.Name + ' ' + $_.Version })
$commands = @(Get-Command -Module 'psfdx*' | Where-Object { $_.CommandType -eq 'Function' })
$bySource = @{}
foreach ($g in ($commands | Group-Object Source)) { $bySource[$g.Name] = @($g.Group | ForEach-Object Name | Sort-Object) }
$duplicates = @($commands | Group-Object Name | Where-Object { $_.Count -gt 1 } | ForEach-Object Name)
$umbrellaExports = @((Get-Module psfdx).ExportedFunctions.Keys)
[pscustomobject]@{ loaded = $loaded; bySource = $bySource; duplicates = $duplicates; umbrellaExports = $umbrellaExports; total = $commands.Count } | ConvertTo-Json -Compress -Depth 4
'@.Replace('__VERSION__', $Version)
$imported = Invoke-FreshSession $ModulePath $import
if (-not (Same @($imported.loaded) $listedExpected)) { Add-Problem "Import-Module psfdx loaded [$(@($imported.loaded) -join ', ')], expected [$($listedExpected -join ', ')]" }
if (@($imported.duplicates).Count -gt 0) { Add-Problem "These command names exist more than once after Import-Module psfdx: $(@($imported.duplicates) -join ', ')" }
if (@($imported.umbrellaExports).Count -gt 0) { Add-Problem "The umbrella psfdx exports $(@($imported.umbrellaExports).Count) commands; it must export none" }
foreach ($module in $modules) {
    if (-not (Same @($imported.bySource.$module) $expectedExports[$module])) { Add-Problem "After Import-Module psfdx the commands of $module are not the ones its manifest lists" }
}
$expectedTotal = 0; foreach ($module in $modules) { $expectedTotal += $expectedExports[$module].Count }
if ($imported.total -ne $expectedTotal) { Add-Problem "After Import-Module psfdx there are $($imported.total) commands, expected $expectedTotal" }

# ---- 5. A standalone module with its own dependencies ----
if ($StandalonePath) {
    $needed = @(@($StandaloneModule) + @($dependencies[$StandaloneModule]) | Sort-Object)
    $standaloneScript = @'
Import-Module '__MODULE__' -RequiredVersion '__VERSION__'
$loaded = @(Get-Module 'psfdx*' | ForEach-Object Name)
$exports = @((Get-Module '__MODULE__').ExportedFunctions.Keys | Sort-Object)
$listed = @(Get-Module -ListAvailable 'psfdx*' | ForEach-Object Name)
[pscustomobject]@{ loaded = $loaded; exports = $exports; listed = $listed } | ConvertTo-Json -Compress -Depth 4
'@.Replace('__MODULE__', $StandaloneModule).Replace('__VERSION__', $Version)
    $alone = Invoke-FreshSession $StandalonePath $standaloneScript
    if (-not (Same @($alone.listed) $needed)) { Add-Problem "Installing $StandaloneModule alone left [$(@($alone.listed) -join ', ')] available, expected [$($needed -join ', ')]" }
    if (-not (Same @($alone.exports) $expectedExports[$StandaloneModule])) { Add-Problem "$StandaloneModule installed alone does not export what its manifest lists" }
    $extraLoaded = @($alone.loaded | Where-Object { $_ -notin $needed })
    if ($extraLoaded.Count) { Add-Problem "Importing $StandaloneModule alone also loaded: $($extraLoaded -join ', ')" }
}

if ($problems.Count) { throw ("The installed psfdx suite is not right (PowerShell $($PSVersionTable.PSVersion)):`n - " + ($problems -join "`n - ")) }
"The psfdx suite $Version installs as $($expectedNames.Count) modules on PowerShell $($PSVersionTable.PSVersion): Get-Module -ListAvailable and Get-Command -Module 'psfdx*' see all of them with no import ($expectedTotal commands, each from its own module), Import-Module psfdx loads them with no duplicate command$(if ($StandalonePath) { ", and $StandaloneModule works on its own with $(@($dependencies[$StandaloneModule]).Count) dependencies" })."
