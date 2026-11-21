<#
.SYNOPSIS
Writes docs/cli-parity-inventory.json, the list of Salesforce CLI commands the parity report is built from.
.DESCRIPTION
The only step of the parity report that needs the Salesforce CLI. It runs `sf commands --json` (the commands of the core plugins and of the
just-in-time plugins the CLI knows about) and keeps what the report needs: each command, its plugin and plugin type, its state (beta,
preview) and its flags, with the exact CLI version. It needs no org and no credentials. Install the latest stable CLI first:
npm install --global @salesforce/cli@latest
Use -CommandsFile to build the snapshot from a saved `sf commands --json` file instead of running the CLI, and -CliVersion to name its version.
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)][string] $CommandsFile,
    [Parameter(Mandatory = $false)][string] $CliVersion,
    [Parameter(Mandatory = $false)][string] $Output
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'CliParity.ps1')
if (-not $Output) { $Output = Join-Path $root (Join-Path 'docs' 'cli-parity-inventory.json') }

if ($CommandsFile) {
    if (-not (Test-Path -LiteralPath $CommandsFile -PathType Leaf)) { throw "Commands file '$CommandsFile' does not exist." }
    if (-not $CliVersion) { throw 'Give -CliVersion with -CommandsFile, so the snapshot records the version it came from.' }
    $text = [System.IO.File]::ReadAllText($CommandsFile)
} else {
    if (-not (Get-Command sf -ErrorAction SilentlyContinue)) {
        throw "The Salesforce CLI ('sf') was not found on PATH. Install the latest stable release: npm install --global @salesforce/cli@latest"
    }
    if (-not $CliVersion) {
        $versionText = (& sf --version | Out-String).Trim()
        if ($versionText -notmatch '@salesforce/cli/([0-9]+\.[0-9]+\.[0-9]+)') { throw "Could not read the CLI version from: $versionText" }
        $CliVersion = $Matches[1]
    }
    $text = (& sf commands --json | Out-String)
}
$commands = @($text | ConvertFrom-Json)
if ($commands.Count -eq 0) { throw 'sf commands --json returned no commands.' }

$inventory = ConvertTo-ParityInventory -Commands $commands -CliVersion $CliVersion
$json = ($inventory | ConvertTo-Json -Depth 8)
[System.IO.File]::WriteAllText($Output, ($json -replace "`r`n", "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
"Wrote $Output ($($inventory.commands.Count) commands, Salesforce CLI $CliVersion)."
