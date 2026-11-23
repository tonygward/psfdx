<#
.SYNOPSIS
Checks that upgrading the psfdx suite works, and that a broken install can be put right with one command.
.DESCRIPTION
Run it after New-PsfdxSuiteRepository.ps1 -IncludeUpgrade has published two versions to a folder repository, and that folder is registered with
PowerShellGet (Register-PSRepository). Uses PowerShellGet, the tool users have on Windows PowerShell 5.1 and PowerShell 7. It checks that:
  1. a newer psfdx, saved next to an older one, brings the newer version of every module it requires (the umbrella pins each module to its own
     version, so nothing is left stale), and the older versions sitting next to them do not load: Import-Module psfdx loads the newest of all nine
     modules and defines no command twice;
  2. when a required module is missing from an install (here the newer psfdx-core is deleted), Import-Module psfdx fails and names the missing module,
     and running the install again (Save-Module/Install-Module psfdx) puts it back and everything imports.
With -AllowInstall it also does what a user does: Install-Module the old version, Update-Module psfdx, and check that every module moved to the new
version. That writes to the current user's module folder (and removes the psfdx modules again afterwards), so it is meant for CI runners, never
for a machine that has psfdx installed.
Works on Windows PowerShell 5.1 and PowerShell 7. Throws, listing every problem.
#>
[CmdletBinding()]
Param(
    # The repository name registered with PowerShellGet.
    [Parameter(Mandatory = $true)][string] $RepositoryName,
    [Parameter(Mandatory = $true)][string] $OldVersion,
    [Parameter(Mandatory = $true)][string] $NewVersion,
    # A scratch folder; created if missing.
    [Parameter(Mandatory = $true)][string] $WorkPath,
    [Parameter(Mandatory = $false)][switch] $AllowInstall,
    [Parameter(Mandatory = $false)][string] $Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) }
. (Join-Path $Root 'modules.ps1')
$names = @(@(Get-PsfdxUmbrellaModule) + @(Get-PsfdxModules) | Sort-Object)
$expectedTotal = 0
foreach ($module in Get-PsfdxModules) { $expectedTotal += @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $Root $module) "$module.psd1")).FunctionsToExport).Count }
$shell = (Get-Process -Id $PID).Path
$problems = New-Object System.Collections.Generic.List[string]
function Add-Problem([string] $Text) { $problems.Add($Text) }

# Runs a script in a fresh PowerShell whose module path is $Path (or the default path when $Path is empty). Returns the exit code, the text and the
# last JSON line it printed.
function Invoke-Fresh([string] $Path, [string] $Script) {
    $header = "`$ErrorActionPreference = 'Stop'; `$WarningPreference = 'SilentlyContinue'; if (`$env:PSFDX_SUITE_PATH) { `$env:PSModulePath = `$env:PSFDX_SUITE_PATH }; "
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($header + $Script))
    $previous = $env:PSFDX_SUITE_PATH
    $env:PSFDX_SUITE_PATH = $Path
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = & $shell -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1 | Out-String; $code = $LASTEXITCODE }
    finally { $env:PSFDX_SUITE_PATH = $previous; $ErrorActionPreference = $saved }
    $json = @($output -split "`r?`n" | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -Last 1)
    $result = $null
    if ($json.Count -gt 0) { $result = $json[0] | ConvertFrom-Json }
    return [pscustomobject]@{ ExitCode = $code; Output = $output; Result = $result }
}

$importAll = @'
Import-Module psfdx
$loaded = @(Get-Module 'psfdx*' | ForEach-Object { $_.Name + ' ' + $_.Version })
$commands = @(Get-Command -Module 'psfdx*' | Where-Object { $_.CommandType -eq 'Function' })
$dups = @($commands | Group-Object Name | Where-Object { $_.Count -gt 1 } | ForEach-Object Name)
[pscustomobject]@{ loaded = $loaded; total = $commands.Count; duplicates = $dups } | ConvertTo-Json -Compress
'@

if ($PSVersionTable.PSEdition -eq 'Desktop') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
if (-not (Test-Path -LiteralPath $WorkPath)) { New-Item -ItemType Directory -Path $WorkPath | Out-Null }
$dir = Join-Path $WorkPath ('upgrade-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $dir | Out-Null

# ---- 1. A newer psfdx next to an older one ----
Save-Module -Name psfdx -RequiredVersion $OldVersion -Repository $RepositoryName -Path $dir -Force -ErrorAction Stop
Save-Module -Name psfdx -Repository $RepositoryName -Path $dir -Force -ErrorAction Stop
foreach ($name in $names) {
    foreach ($v in $OldVersion, $NewVersion) {
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $dir $name) $v) "$name.psd1"))) { Add-Problem "$name $v is not in the folder after the upgrade; the newer psfdx should bring every module at its own version" }
    }
}
$now = Invoke-Fresh $dir $importAll
if ($now.ExitCode -ne 0 -or -not $now.Result) { Add-Problem "Import-Module psfdx failed with both versions installed:`n$($now.Output)" }
else {
    $expectedLoaded = @($names | ForEach-Object { "$_ $NewVersion" } | Sort-Object)
    if ((@($now.Result.loaded | Sort-Object) -join '|') -ne ($expectedLoaded -join '|')) { Add-Problem "With $OldVersion and $NewVersion installed, Import-Module psfdx loaded [$(@($now.Result.loaded | Sort-Object) -join ', ')], expected every module at $NewVersion" }
    if (@($now.Result.duplicates).Count) { Add-Problem "Duplicate commands after the upgrade: $(@($now.Result.duplicates) -join ', ')" }
    if ($now.Result.total -ne $expectedTotal) { Add-Problem "After the upgrade there are $($now.Result.total) commands, expected $expectedTotal" }
}

# ---- 2. A missing dependency, and the one-command recovery ----
$core = Join-Path (Join-Path $dir 'psfdx-core') $NewVersion
Remove-Item -LiteralPath $core -Recurse -Force
$broken = Invoke-Fresh $dir $importAll
if ($broken.ExitCode -eq 0) { Add-Problem "Import-Module psfdx succeeded although psfdx-core $NewVersion was missing" }
elseif ($broken.Output -notmatch 'psfdx-core') { Add-Problem "Import-Module psfdx failed without naming the missing module psfdx-core:`n$($broken.Output)" }
Save-Module -Name psfdx -Repository $RepositoryName -Path $dir -Force -ErrorAction Stop
if (-not (Test-Path -LiteralPath (Join-Path $core 'psfdx-core.psd1'))) { Add-Problem "Running Save-Module psfdx again did not bring psfdx-core $NewVersion back" }
$healed = Invoke-Fresh $dir $importAll
if ($healed.ExitCode -ne 0 -or -not $healed.Result) { Add-Problem "Import-Module psfdx still fails after running the install again:`n$($healed.Output)" }
elseif ($healed.Result.total -ne $expectedTotal) { Add-Problem "After the recovery there are $($healed.Result.total) commands, expected $expectedTotal" }

# ---- 3. What a user does: Install-Module, then Update-Module (CI runners only) ----
if ($AllowInstall) {
    try {
        Install-Module -Name psfdx -RequiredVersion $OldVersion -Repository $RepositoryName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        $installed = @(Get-InstalledModule -Name 'psfdx*' | ForEach-Object { $_.Name + ' ' + $_.Version } | Sort-Object)
        $expectedOld = @($names | ForEach-Object { "$_ $OldVersion" } | Sort-Object)
        if (($installed -join '|') -ne ($expectedOld -join '|')) { Add-Problem "Install-Module psfdx -RequiredVersion $OldVersion left [$($installed -join ', ')] installed, expected [$($expectedOld -join ', ')]" }
        Update-Module -Name psfdx -ErrorAction Stop
        # -AllVersions needs a single module name, so ask for each module on its own.
        $updated = @($names | Where-Object { $module = $_; @(Get-InstalledModule -Name $module -AllVersions -ErrorAction SilentlyContinue | Where-Object { [version]$_.Version -eq [version]$NewVersion }).Count -gt 0 } | Sort-Object)
        if (($updated -join '|') -ne ($names -join '|')) { Add-Problem "Update-Module psfdx moved [$($updated -join ', ')] to $NewVersion, expected all of [$($names -join ', ')]" }
        $afterUpdate = Invoke-Fresh '' $importAll
        if ($afterUpdate.ExitCode -ne 0 -or -not $afterUpdate.Result) { Add-Problem "Import-Module psfdx failed after Update-Module:`n$($afterUpdate.Output)" }
        else {
            $stale = @($afterUpdate.Result.loaded | Where-Object { $_ -notlike "* $NewVersion" })
            if ($stale.Count) { Add-Problem "After Update-Module, Import-Module psfdx loaded stale modules: $($stale -join ', ')" }
            if (@($afterUpdate.Result.duplicates).Count) { Add-Problem "Duplicate commands after Update-Module: $(@($afterUpdate.Result.duplicates) -join ', ')" }
        }
        # A dependency lost from an installed suite: install the same version again, with -Force, and it comes back.
        $coreLocation = (Get-InstalledModule -Name psfdx-core -RequiredVersion $NewVersion -ErrorAction Stop).InstalledLocation
        Remove-Item -LiteralPath $coreLocation -Recurse -Force
        Install-Module -Name psfdx -RequiredVersion $NewVersion -Repository $RepositoryName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        if (-not (Test-Path -LiteralPath (Join-Path $coreLocation 'psfdx-core.psd1'))) { Add-Problem "Install-Module psfdx -RequiredVersion $NewVersion -Force did not put the missing psfdx-core back" }
        $healedInstall = Invoke-Fresh '' $importAll
        if ($healedInstall.ExitCode -ne 0 -or -not $healedInstall.Result) { Add-Problem "Import-Module psfdx still fails after Install-Module -Force:`n$($healedInstall.Output)" }
    } finally {
        foreach ($name in @($names | Sort-Object -Descending)) { Uninstall-Module -Name $name -AllVersions -Force -ErrorAction SilentlyContinue }
    }
}

if ($problems.Count) { throw ("Upgrading the psfdx suite is not right (PowerShell $($PSVersionTable.PSVersion)):`n - " + ($problems -join "`n - ")) }
"Upgrading the psfdx suite from $OldVersion to $NewVersion works on PowerShell $($PSVersionTable.PSVersion): the newer psfdx brings all $($names.Count) modules at the new version, Import-Module psfdx loads only those, and a missing dependency is named and put back by running the install again$(if ($AllowInstall) { '; Install-Module then Update-Module moved every module' })."
