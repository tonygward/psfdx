<#
.SYNOPSIS
Checks that upgrading the psfdx package works, and that a broken install can be put right with one command.
.DESCRIPTION
Run it after New-PsfdxSuiteRepository.ps1 -IncludeUpgrade has published two versions of the package to a folder repository, and that folder is
registered with PowerShellGet (Register-PSRepository). Uses PowerShellGet, the tool users have on Windows PowerShell 5.1 and PowerShell 7. It checks that:
  1. a newer psfdx saved next to an older one brings every module at the new version (they all travel in the one package), the older version sitting
     next to it is not used, and Import-Module psfdx loads the newer one with all eight modules from it and defines no command twice;
  2. when a module folder is missing from the installed package (here psfdx-logs of the newer version is deleted), Import-Module psfdx fails and names the
     missing module, and installing the same version again (Save-Module or Install-Module psfdx) puts it back and everything imports.
With -AllowInstall it also does what a user does: Install-Module the old version, Update-Module psfdx, check that every module now comes from the new
version, then delete a module folder and repair it with Install-Module -Force. That writes to the current user's module folder (and removes psfdx again
afterwards), so it is meant for CI runners, never for a machine that has psfdx installed.
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
$modules = @(Get-PsfdxModules)
$expectedTotal = 0
foreach ($module in $modules) { $expectedTotal += @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $Root $module) "$module.psd1")).FunctionsToExport).Count }
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
$loaded = @(Get-Module 'psfdx*' | ForEach-Object { $_.Name + ' ' + $_.Version + ' ' + $_.ModuleBase })
$commands = @(Get-Command -Module 'psfdx*' | Where-Object { $_.CommandType -eq 'Function' })
$dups = @($commands | Group-Object Name | Where-Object { $_.Count -gt 1 } | ForEach-Object Name)
[pscustomobject]@{ loaded = $loaded; total = $commands.Count; duplicates = $dups } | ConvertTo-Json -Compress
'@

# Every loaded psfdx module must be at the version and come from inside that version's package folder.
function Test-LoadedFrom([object] $Result, [string] $Version, [string] $When) {
    $names = @($Result.loaded | ForEach-Object { ($_ -split ' ', 3)[0] } | Sort-Object)
    if ((@($names) -join '|') -ne (@($modules | Sort-Object) -join '|')) { Add-Problem "$When loaded [$($names -join ', ')], expected [$(@($modules | Sort-Object) -join ', ')]" }
    foreach ($entry in @($Result.loaded)) {
        $name, $v, $base = $entry -split ' ', 3
        $inside = ($base -like "*$([IO.Path]::DirectorySeparatorChar)psfdx$([IO.Path]::DirectorySeparatorChar)$Version" -or $base -like "*$([IO.Path]::DirectorySeparatorChar)psfdx$([IO.Path]::DirectorySeparatorChar)$Version$([IO.Path]::DirectorySeparatorChar)*")
        if ($v -ne $Version -or -not $inside) { Add-Problem "$When $name is $v from $base; every module should be $Version from inside the psfdx $Version package" }
    }
    if (@($Result.duplicates).Count) { Add-Problem "$When these command names are defined twice: $(@($Result.duplicates) -join ', ')" }
    if ($Result.total -ne $expectedTotal) { Add-Problem "$When there are $($Result.total) commands, expected $expectedTotal" }
}

if ($PSVersionTable.PSEdition -eq 'Desktop') { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 }
if (-not (Test-Path -LiteralPath $WorkPath)) { New-Item -ItemType Directory -Path $WorkPath | Out-Null }
$dir = Join-Path $WorkPath ('upgrade-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $dir | Out-Null

# ---- 1. A newer psfdx next to an older one ----
Save-Module -Name psfdx -RequiredVersion $OldVersion -Repository $RepositoryName -Path $dir -Force -ErrorAction Stop
Save-Module -Name psfdx -Repository $RepositoryName -Path $dir -Force -ErrorAction Stop
foreach ($v in $OldVersion, $NewVersion) {
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $dir 'psfdx') $v) 'psfdx.psd1'))) { Add-Problem "psfdx $v is not in the folder after the upgrade" }
}
foreach ($module in @($modules | Where-Object { $_ -ne 'psfdx' })) {
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path (Join-Path $dir 'psfdx') $NewVersion) $module) "$module.psd1"))) { Add-Problem "The psfdx $NewVersion package does not hold $module" }
}
$now = Invoke-Fresh $dir $importAll
if ($now.ExitCode -ne 0 -or -not $now.Result) { Add-Problem "Import-Module psfdx failed with both versions installed:`n$($now.Output)" }
else { Test-LoadedFrom $now.Result $NewVersion "With $OldVersion and $NewVersion installed, Import-Module psfdx" }

# ---- 2. A missing module folder, and the one-command repair ----
$logs = Join-Path (Join-Path (Join-Path $dir 'psfdx') $NewVersion) 'psfdx-logs'
Remove-Item -LiteralPath $logs -Recurse -Force
$broken = Invoke-Fresh $dir $importAll
if ($broken.ExitCode -eq 0) { Add-Problem "Import-Module psfdx succeeded although psfdx-logs was missing from the package" }
elseif ($broken.Output -notmatch 'psfdx-logs') { Add-Problem "Import-Module psfdx failed without naming the missing module psfdx-logs:`n$($broken.Output)" }
Save-Module -Name psfdx -Repository $RepositoryName -Path $dir -Force -ErrorAction Stop
if (-not (Test-Path -LiteralPath (Join-Path $logs 'psfdx-logs.psd1'))) { Add-Problem "Running Save-Module psfdx again did not bring psfdx-logs back" }
$healed = Invoke-Fresh $dir $importAll
if ($healed.ExitCode -ne 0 -or -not $healed.Result) { Add-Problem "Import-Module psfdx still fails after running the install again:`n$($healed.Output)" }
else { Test-LoadedFrom $healed.Result $NewVersion 'After the repair, Import-Module psfdx' }

# ---- 3. What a user does: Install-Module, then Update-Module (CI runners only) ----
if ($AllowInstall) {
    try {
        Install-Module -Name psfdx -RequiredVersion $OldVersion -Repository $RepositoryName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        $installed = @(Get-InstalledModule -Name 'psfdx*' | ForEach-Object { $_.Name + ' ' + $_.Version })
        if ((@($installed) -join '|') -ne "psfdx $OldVersion") { Add-Problem "Install-Module psfdx -RequiredVersion $OldVersion left [$($installed -join ', ')] installed, expected only [psfdx $OldVersion]: one command, one package" }
        Update-Module -Name psfdx -ErrorAction Stop
        $versions = @(Get-InstalledModule -Name psfdx -AllVersions | ForEach-Object { [string]$_.Version })
        if ($versions -notcontains $NewVersion) { Add-Problem "Update-Module psfdx did not install $NewVersion (installed versions: $($versions -join ', '))" }
        $afterUpdate = Invoke-Fresh '' $importAll
        if ($afterUpdate.ExitCode -ne 0 -or -not $afterUpdate.Result) { Add-Problem "Import-Module psfdx failed after Update-Module:`n$($afterUpdate.Output)" }
        else { Test-LoadedFrom $afterUpdate.Result $NewVersion 'After Update-Module, Import-Module psfdx' }
        # A module folder lost from the installed package: install the same version again, with -Force, and it comes back.
        $location = (Get-InstalledModule -Name psfdx -RequiredVersion $NewVersion -ErrorAction Stop).InstalledLocation
        Remove-Item -LiteralPath (Join-Path $location 'psfdx-metadata') -Recurse -Force
        Install-Module -Name psfdx -RequiredVersion $NewVersion -Repository $RepositoryName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $location 'psfdx-metadata') 'psfdx-metadata.psd1'))) { Add-Problem "Install-Module psfdx -RequiredVersion $NewVersion -Force did not put the missing psfdx-metadata back" }
        $healedInstall = Invoke-Fresh '' $importAll
        if ($healedInstall.ExitCode -ne 0 -or -not $healedInstall.Result) { Add-Problem "Import-Module psfdx still fails after Install-Module -Force:`n$($healedInstall.Output)" }
    } finally {
        Uninstall-Module -Name psfdx -AllVersions -Force -ErrorAction SilentlyContinue
    }
}

if ($problems.Count) { throw ("Upgrading the psfdx package is not right (PowerShell $($PSVersionTable.PSVersion)):`n - " + ($problems -join "`n - ")) }
"Upgrading psfdx from $OldVersion to $NewVersion works on PowerShell $($PSVersionTable.PSVersion): the newer package brings all $($modules.Count) modules at the new version, Import-Module psfdx loads only those with no duplicate command, and a missing module is named and put back by installing again$(if ($AllowInstall) { '; Install-Module then Update-Module moved psfdx, and Install-Module -Force repaired a missing module' })."
