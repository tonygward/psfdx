<#
.SYNOPSIS
Checks that an installed copy of the psfdx package behaves as one install of several modules, and records the evidence.
.DESCRIPTION
Run it against a folder that Save-Module or Install-Module filled from a package repository (the PowerShell Gallery, or the local repository the CI
builds). It never imports anything from the source tree: every check runs in a fresh PowerShell process whose module path is that folder alone, so it
sees what a new user sees after `Install-Module psfdx` and nothing else. It checks that:
  1. the install is the one package `psfdx`, at the expected version, holding every module (no separate psfdx-* package beside it);
  2. in a fresh session, before anything has loaded, Get-Command -Module 'psfdx*' lists every command of the suite (the psfdx manifest lists them
     all, so they show the Source `psfdx` until it loads), a non-core command is found by name and reports its own module (looking it up loads
     psfdx), and Get-Command -Module psfdx shows only the core commands, each with the Source `psfdx`;
  3. in one fresh session, in this order: Get-Command -Module psfdx, then -Module psfdx-logs, then -Module 'psfdx*' give the core commands, exactly
     the commands the logs module owns (Source psfdx-logs), and every command of the suite with each one attributed to the module that holds it,
     with nothing missing, nothing twice and nothing falsely attributed (asking for psfdx is what loads the package, and loading it loads the rest);
  4. the same holds after Import-Module psfdx, and after the first use of a core command with no import at all (PowerShell loads psfdx by itself);
  5. a representative command from every module runs.
What a brand-new session cannot do is recorded, not hidden: PowerShell discovers modules only as folders of their own on the module path and one package
installs one folder, so before psfdx has loaded, `-Module psfdx-logs` shows nothing and `-Module 'psfdx*'` shows every command with the Source `psfdx`.
The report says so (see docs/install.md).
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
    # Where to write the evidence as JSON (command counts per module, representative runs, what a brand-new session shows).
    [Parameter(Mandatory = $false)][string] $EvidencePath
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) }
. (Join-Path $Root 'modules.ps1')
if (-not $Version) { $Version = (Get-Content -Path (Join-Path $Root 'VERSION') -Raw).Trim() }
$modules = @(Get-PsfdxModules)
$core = 'psfdx'
$others = @($modules | Where-Object { $_ -ne $core })
$expectedExports = @{}
foreach ($module in $modules) { $expectedExports[$module] = @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $Root $module) "$module.psd1")).FunctionsToExport | Sort-Object) }
$expectedTotal = 0; foreach ($module in $modules) { $expectedTotal += $expectedExports[$module].Count }
$shell = (Get-Process -Id $PID).Path
$problems = New-Object System.Collections.Generic.List[string]
function Add-Problem([string] $Text) { $problems.Add($Text) }
function Same([object[]] $A, [object[]] $B) { (@($A | Sort-Object) -join '|') -eq (@($B | Sort-Object) -join '|') }

# One command that runs from every module without a Salesforce CLI or an org. Each must run (not throw) and be owned by the module named.
$representative = [ordered]@{
    'psfdx'             = @{ Command = 'Get-SalesforceDateTime'; Run = "Get-SalesforceDateTime -Datetime ([datetime]'2026-01-02T03:04:05Z')"; Expect = '2026-01-02T03:04:05Z' }
    'psfdx-logs'        = @{ Command = 'Convert-SalesforceDebugLog'; Run = "Convert-SalesforceDebugLog -Log ('59.0 APEX_CODE,DEBUG' + [Environment]::NewLine + '12:00:00.1 (1000)|EXECUTION_STARTED')"; Expect = $null }
    'psfdx-metadata'    = @{ Command = 'Clear-SalesforceMetadataTypeCache'; Run = 'Clear-SalesforceMetadataTypeCache'; Expect = $null }
    'psfdx-plugins'     = @{ Command = 'Uninstall-SalesforcePlugin'; Run = 'Uninstall-SalesforcePlugin -Name sfdx-nothing -WhatIf'; Expect = $null }
    'psfdx-data'        = @{ Command = 'Remove-SalesforceBulkData'; Run = "`$probe = Join-Path ([IO.Path]::GetTempPath()) 'psfdx-data-probe.csv'; Set-Content -LiteralPath `$probe -Value 'Id'; Remove-SalesforceBulkData -File `$probe -Object Account -WhatIf"; Expect = $null }
    'psfdx-devops'      = @{ Command = 'New-SalesforceDevOpsProject'; Run = "New-SalesforceDevOpsProject -Name 'x' -WhatIf"; Expect = $null }
    'psfdx-development' = @{ Command = 'Disable-SalesforceSourceTracking'; Run = 'Disable-SalesforceSourceTracking -TargetOrg nosuch -WhatIf'; Expect = $null }
    'psfdx-org'         = @{ Command = 'Remove-SalesforceSandbox'; Run = 'Remove-SalesforceSandbox -TargetOrg nosuch -WhatIf'; Expect = $null }
    'psfdx-packages'    = @{ Command = 'Uninstall-SalesforcePackage'; Run = 'Uninstall-SalesforcePackage -Package 04t000000000001 -TargetOrg nosuch -WhatIf'; Expect = $null }
    # Every agent command asks for the Salesforce CLI first, which a clean machine does not have. This one rejects a bad combination in the module's own code
    # before any CLI call, so its own error message proves the module's code ran.
    'psfdx-agentforce'  = @{ Command = 'Start-SalesforceAgentPreview'; Run = 'Start-SalesforceAgentPreview -ApiName Agent_One -AuthoringBundle Agent_Two'; Expect = $null; ExpectError = 'not both' }
}

# Runs a script in a fresh PowerShell whose module path is only $Path. Returns the exit code, the text and the last JSON line it printed.
function Invoke-FreshSession([string] $Script) {
    $header = "`$ErrorActionPreference = 'Stop'; `$WarningPreference = 'SilentlyContinue'; `$env:PSModulePath = `$env:PSFDX_SUITE_PATH; "
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($header + $Script))
    $previous = $env:PSFDX_SUITE_PATH
    $env:PSFDX_SUITE_PATH = $ModulePath
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = & $shell -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1 | Out-String; $code = $LASTEXITCODE }
    finally { $env:PSFDX_SUITE_PATH = $previous; $ErrorActionPreference = $saved }
    $json = @($output -split "`r?`n" | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -Last 1)
    $result = $null
    if ($json.Count -gt 0) { $result = $json[0] | ConvertFrom-Json }
    if ($code -ne 0 -or -not $result) { throw "A fresh PowerShell session failed (exit $code):`n$output" }
    return $result
}

# A script fragment that lists what Get-Command -Module <pattern> shows, as name and source, and puts it in $r.<key>.
$collect = {
    param([string] $Key, [string] $Pattern)
    "`$c = @(Get-Command -Module '$Pattern' -ErrorAction SilentlyContinue | Where-Object { `$_.CommandType -eq 'Function' }); `$r['$Key'] = @(`$c | ForEach-Object { `$_.Name + '@' + `$_.Source }); "
}
function BySource([object[]] $Items) {
    $by = @{}
    foreach ($item in @($Items | Where-Object { $_ })) { $name, $source = $item -split '@', 2; if (-not $by.ContainsKey($source)) { $by[$source] = New-Object System.Collections.Generic.List[string] }; $by[$source].Add($name) }
    return $by
}

# ---- 1. One package, every module in it ----
$packageFolders = @(Get-ChildItem -LiteralPath $ModulePath -Directory | ForEach-Object Name | Sort-Object)
if (-not (Same $packageFolders @('psfdx'))) { Add-Problem "The install folder holds [$($packageFolders -join ', ')], expected the one package [psfdx] and no separate psfdx-* package" }
$packageFolder = Join-Path (Join-Path $ModulePath 'psfdx') $Version
if (-not (Test-Path -LiteralPath (Join-Path $packageFolder 'psfdx.psd1'))) { Add-Problem "psfdx $Version is not installed (no psfdx.psd1 in $packageFolder)" }
foreach ($module in $others) {
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $packageFolder $module) "$module.psd1"))) { Add-Problem "The package does not hold the module $module (no $module.psd1 in $packageFolder)" }
}

# ---- 2. A brand-new session: what is discoverable before anything has loaded ----
$fresh = Invoke-FreshSession @"
`$r = [ordered]@{}
`$r['listed'] = @(Get-Module -ListAvailable 'psfdx*' | ForEach-Object { `$_.Name + ' ' + `$_.Version })
`$r['loadedBefore'] = @(Get-Module 'psfdx*' | ForEach-Object Name)
$(& $collect 'core' 'psfdx')
[pscustomobject]`$r | ConvertTo-Json -Compress -Depth 4
"@
if (-not (Same @($fresh.listed) @("psfdx $Version"))) { Add-Problem "Get-Module -ListAvailable 'psfdx*' lists [$(@($fresh.listed) -join ', ')], expected [psfdx $Version]" }
if (@($fresh.loadedBefore).Count -ne 0) { Add-Problem "The clean session already had psfdx modules loaded: $(@($fresh.loadedBefore) -join ', ')" }
$expectedAll = @($modules | ForEach-Object { $expectedExports[$_] })
$discovered = Invoke-FreshSession @"
`$r = [ordered]@{}
`$r['all'] = @(Get-Command -Module 'psfdx*' -ErrorAction SilentlyContinue | Where-Object { `$_.CommandType -eq 'Function' } | ForEach-Object Name)
`$r['loadedAfterList'] = @(Get-Module 'psfdx*').Count
`$r['byName'] = (Get-Command '$($representative['psfdx-logs'].Command)' -ErrorAction SilentlyContinue).Source
[pscustomobject]`$r | ConvertTo-Json -Compress -Depth 4
"@
if (-not (Same @($discovered.all) $expectedAll)) {
    $missing = @($expectedAll | Where-Object { $_ -notin @($discovered.all) })
    Add-Problem "In a fresh session, before psfdx has loaded, Get-Command -Module 'psfdx*' shows $(@($discovered.all).Count) commands, expected all $expectedTotal. Missing: $($missing -join ', ')"
}
if ($discovered.loadedAfterList -ne 0) { Add-Problem "Get-Command -Module 'psfdx*' in a fresh session loaded $($discovered.loadedAfterList) modules; listing should not load anything" }
if ($discovered.byName -ne 'psfdx-logs') { Add-Problem "In a fresh session, Get-Command $($representative['psfdx-logs'].Command) reports the Source '$($discovered.byName)', expected psfdx-logs: a non-core command must be found by name before psfdx has loaded" }
$bySource = BySource @($fresh.core)
if (-not (Same @($bySource['psfdx']) $expectedExports[$core]) -or @($bySource.Keys | Where-Object { $_ -ne 'psfdx' }).Count) {
    Add-Problem "In a fresh session Get-Command -Module psfdx shows $(@($fresh.core).Count) commands from [$(@($bySource.Keys) -join ', ')], expected the $($expectedExports[$core].Count) core commands, every one with the Source psfdx"
}

# ---- 3. The ticket's three Get-Command checks, in order, in one fresh session ----
$perModule = ($others | ForEach-Object { & $collect "m_$_" $_ }) -join ''
$ordered = Invoke-FreshSession @"
`$r = [ordered]@{}
$(& $collect 'g1' 'psfdx')
$(& $collect 'g2' 'psfdx-logs')
$(& $collect 'g3' 'psfdx*')
$perModule
`$r['loaded'] = @(Get-Module 'psfdx*' | ForEach-Object { `$_.Name + ' ' + `$_.Version })
[pscustomobject]`$r | ConvertTo-Json -Compress -Depth 4
"@
$expectedLoaded = @($modules | ForEach-Object { "$_ $Version" })
function Test-Ownership([object] $Result, [string] $When) {
    $g1 = BySource @($Result.g1)
    if (-not (Same @($g1['psfdx']) $expectedExports[$core]) -or @($g1.Keys | Where-Object { $_ -ne 'psfdx' }).Count) { Add-Problem "$When Get-Command -Module psfdx does not show only the core commands with the Source psfdx (it shows $(@($Result.g1).Count) from [$(@($g1.Keys) -join ', ')])" }
    $g2 = BySource @($Result.g2)
    if (-not (Same @($g2['psfdx-logs']) $expectedExports['psfdx-logs']) -or @($g2.Keys | Where-Object { $_ -ne 'psfdx-logs' }).Count) { Add-Problem "$When Get-Command -Module psfdx-logs does not show exactly the logs commands with the Source psfdx-logs (it shows $(@($Result.g2).Count) from [$(@($g2.Keys) -join ', ')], expected $($expectedExports['psfdx-logs'].Count))" }
    $g3 = BySource @($Result.g3)
    foreach ($module in $modules) {
        if (-not (Same @($g3[$module]) $expectedExports[$module])) {
            $have = @($g3[$module]); $missing = @($expectedExports[$module] | Where-Object { $_ -notin $have }); $extra = @($have | Where-Object { $_ -and $_ -notin $expectedExports[$module] })
            Add-Problem "$When Get-Command -Module 'psfdx*' shows $($have.Count) commands from $module, expected $($expectedExports[$module].Count). Missing: $($missing -join ', '). Extra: $($extra -join ', ')"
        }
    }
    if (@($g3.Keys | Where-Object { $_ -notin $modules }).Count) { Add-Problem "$When Get-Command -Module 'psfdx*' attributes commands to unknown modules: $(@($g3.Keys | Where-Object { $_ -notin $modules }) -join ', ')" }
    $names = @(@($Result.g3) | ForEach-Object { ($_ -split '@', 2)[0] })
    $dups = @($names | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object Name)
    if ($dups.Count) { Add-Problem "$When these command names appear more than once: $($dups -join ', ')" }
    if (@($Result.g3).Count -ne $expectedTotal) { Add-Problem "$When Get-Command -Module 'psfdx*' shows $(@($Result.g3).Count) commands, expected $expectedTotal" }
    foreach ($module in $others) {
        $own = BySource @($Result."m_$module")
        if (-not (Same @($own[$module]) $expectedExports[$module]) -or @($own.Keys | Where-Object { $_ -ne $module }).Count) { Add-Problem "$When Get-Command -Module $module does not show exactly its $($expectedExports[$module].Count) commands with the Source $module" }
    }
    if (-not (Same @($Result.loaded) $expectedLoaded)) { Add-Problem "$When the loaded modules are [$(@($Result.loaded) -join ', ')], expected [$($expectedLoaded -join ', ')]" }
}
Test-Ownership $ordered 'In one fresh session (psfdx, then psfdx-logs, then psfdx*):'

# ---- 4. After Import-Module psfdx, and after the first use of a core command with no import ----
$viaImport = Invoke-FreshSession @"
Import-Module psfdx -RequiredVersion '$Version'
`$r = [ordered]@{}
$(& $collect 'g1' 'psfdx')
$(& $collect 'g2' 'psfdx-logs')
$(& $collect 'g3' 'psfdx*')
$perModule
`$r['loaded'] = @(Get-Module 'psfdx*' | ForEach-Object { `$_.Name + ' ' + `$_.Version })
[pscustomobject]`$r | ConvertTo-Json -Compress -Depth 4
"@
Test-Ownership $viaImport 'After Import-Module psfdx:'
$viaFirstUse = Invoke-FreshSession @"
`$null = Get-SalesforceDateTime
`$r = [ordered]@{}
$(& $collect 'g1' 'psfdx')
$(& $collect 'g2' 'psfdx-logs')
$(& $collect 'g3' 'psfdx*')
$perModule
`$r['loaded'] = @(Get-Module 'psfdx*' | ForEach-Object { `$_.Name + ' ' + `$_.Version })
[pscustomobject]`$r | ConvertTo-Json -Compress -Depth 4
"@
Test-Ownership $viaFirstUse 'After the first use of a core command, with no import:'

# ---- 5. A representative command from every module runs, and belongs to its module ----
$runs = ($representative.Keys | ForEach-Object {
    $m = $_; $spec = $representative[$m]
    # Normally the command must run without an error. A command with ExpectError must fail with a message that matches it: its own code rejected the call.
    $expectError = ''
    if ($spec.ExpectError) { $expectError = ([string]$spec.ExpectError).Replace("'", "''") }
    "`$expectError = '$expectError'; try { `$out = @($($spec.Run)) | Out-String; `$ok = (`$expectError -eq ''); `$err = ''; if (`$expectError) { `$err = 'it was expected to fail with ' + `$expectError + ' but did not fail' } } catch { `$out = ''; `$err = `$_.Exception.Message; `$ok = ((`$expectError -ne '') -and (`$err -match `$expectError)) }; `$r['run_$m'] = [pscustomobject]@{ ok = `$ok; out = `$out.Trim(); err = `$err; source = (Get-Command '$($spec.Command)' -ErrorAction SilentlyContinue | Select-Object -First 1).Source }; "
}) -join ''
$ran = Invoke-FreshSession @"
# The representative commands must not need the Salesforce CLI, so hide it: this machine and a CI runner then behave the same.
`$env:PATH = ((`$env:PATH -split [IO.Path]::PathSeparator) | Where-Object { -not ((Test-Path (Join-Path `$_ 'sf')) -or (Test-Path (Join-Path `$_ 'sf.cmd')) -or (Test-Path (Join-Path `$_ 'sf.exe'))) }) -join [IO.Path]::PathSeparator
Import-Module psfdx -RequiredVersion '$Version'
`$r = [ordered]@{}
$runs
[pscustomobject]`$r | ConvertTo-Json -Compress -Depth 4
"@
$runEvidence = [ordered]@{}
foreach ($m in $representative.Keys) {
    $spec = $representative[$m]
    $got = $ran."run_$m"
    $runEvidence[$m] = [ordered]@{ command = $spec.Command; source = $got.source; ran = [bool]$got.ok }
    if (-not $got.ok) { Add-Problem "The representative command $($spec.Command) of $m did not run: $($got.err)" }
    elseif ($got.source -ne $m) { Add-Problem "$($spec.Command) reports the Source '$($got.source)', expected $m" }
    elseif ($spec.Expect -and $got.out -ne $spec.Expect) { Add-Problem "$($spec.Command) returned '$($got.out)', expected '$($spec.Expect)'" }
}

# ---- 6. Internal helpers stay internal ----
# psfdx-shared exports nothing. Every helper it holds must stay undiscoverable after the package has loaded, the three SOQL converters excepted: they are public and
# belong to the core module (their Source is checked with the other core commands above). The other modules must still work, which the representative runs above prove.
$internalNames = @()
foreach ($internal in @(Get-PsfdxInternalModules)) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $Root $internal) -Filter '*.ps1' | Where-Object { $_.Name -notlike '*.Tests.ps1' }) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
        $internalNames += @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) | ForEach-Object { $_.Name })
    }
}
$publicFromInternal = @($expectedExports[$core] | Where-Object { $_ -in $internalNames })
$hiddenNames = @($internalNames | Where-Object { $_ -notin $publicFromInternal })
$namesLiteral = ($hiddenNames | ForEach-Object { "'$_'" }) -join ','
$hidden = Invoke-FreshSession @"
Import-Module psfdx -RequiredVersion '$Version'
`$r = [ordered]@{}
`$r['leaked'] = @(@($namesLiteral) | Where-Object { Get-Command `$_ -ErrorAction SilentlyContinue })
`$r['internalModuleCommands'] = @(Get-Command -Module psfdx-shared -ErrorAction SilentlyContinue).Count
[pscustomobject]`$r | ConvertTo-Json -Compress -Depth 4
"@
if (@($hidden.leaked).Count) { Add-Problem "These internal helpers are discoverable commands after Import-Module psfdx: $(@($hidden.leaked) -join ', ')" }
if ($hidden.internalModuleCommands -ne 0) { Add-Problem "Get-Command -Module psfdx-shared shows $($hidden.internalModuleCommands) commands, expected none: it is an internal module" }
if ($hiddenNames.Count -lt 5) { Add-Problem "Only $($hiddenNames.Count) internal helpers were found to check; the check cannot be trusted" }

# ---- The evidence ----
$counts = [ordered]@{}
foreach ($module in $modules) { $counts[$module] = $expectedExports[$module].Count }
$evidence = [ordered]@{
    version = $Version
    powershell = [string]$PSVersionTable.PSVersion
    edition = [string]$PSVersionTable.PSEdition
    package = 'psfdx'
    totalCommands = $expectedTotal
    commandsPerModule = $counts
    duplicateCommandNames = 0
    brandNewSession = [ordered]@{
        listedModules = @($fresh.listed)
        coreCommandsShown = @($fresh.core).Count
        commandsDiscoverableBeforeLoad = @($discovered.all).Count
        note = 'Before psfdx has loaded only psfdx is discoverable as a module: PowerShell finds modules as folders of their own on the module path, and one package installs one folder. Its manifest lists every command, so all of them are discoverable and autoload by name, with the Source psfdx until it loads. Asking for psfdx, importing it or using any command loads the rest under their own names.'
    }
    representativeCommands = $runEvidence
}
if ($EvidencePath) { ($evidence | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $EvidencePath -Encoding UTF8 }

if ($problems.Count) { throw ("The installed psfdx package is not right (PowerShell $($PSVersionTable.PSVersion)):`n - " + ($problems -join "`n - ")) }
$summary = ($modules | ForEach-Object { "$_=$($counts[$_])" }) -join ', '
"psfdx $Version is one package holding $($modules.Count) modules, checked on PowerShell $($PSVersionTable.PSVersion): in a fresh session every command is discoverable and Get-Command -Module psfdx shows only the $($counts[$core]) core commands; once psfdx has loaded (Get-Command -Module psfdx, Import-Module psfdx or a first core command) Get-Command -Module psfdx-logs shows exactly the $($counts['psfdx-logs']) logs commands and -Module 'psfdx*' shows all $expectedTotal with each attributed to its own module ($summary) and no duplicate; one representative command from each of the $($modules.Count) modules runs."
