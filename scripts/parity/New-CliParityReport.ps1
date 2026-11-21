<#
.SYNOPSIS
Writes docs/cli-parity.md and docs/cli-parity.json: the Salesforce CLI to psfdx parity report.
.DESCRIPTION
Offline: it needs no Salesforce CLI, no org and no credentials. It reads the committed inventory (docs/cli-parity-inventory.json, made by
New-CliInventorySnapshot.ps1), the module manifests and sources, and the reviewed mapping (docs/cli-parity-mapping.json), and writes the
Markdown report and its JSON twin. The output is the same every time for the same inputs.
-Check writes nothing and fails if the committed files differ from what would be generated (the repository test uses the same comparison).
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)][string] $Root,
    [Parameter(Mandatory = $false)][string] $Inventory,
    [Parameter(Mandatory = $false)][string] $Mapping,
    [Parameter(Mandatory = $false)][string] $OutputDirectory,
    [Parameter(Mandatory = $false)][switch] $Check
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CliParity.ps1')
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$docs = Join-Path $Root 'docs'
if (-not $Inventory) { $Inventory = Join-Path $docs 'cli-parity-inventory.json' }
if (-not $Mapping) { $Mapping = Join-Path $docs 'cli-parity-mapping.json' }
if (-not $OutputDirectory) { $OutputDirectory = $docs }
if (-not (Test-Path -LiteralPath $Inventory -PathType Leaf)) { throw "Inventory '$Inventory' does not exist. Run New-CliInventorySnapshot.ps1 (it needs the Salesforce CLI)." }

$inventoryObject = [System.IO.File]::ReadAllText($Inventory) | ConvertFrom-Json
$mappingObject = Read-ParityMapping -Path $Mapping
$scan = Get-ParityPsfdxScan -Root $Root
$report = New-ParityReport -Inventory $inventoryObject -Scan $scan -Mapping $mappingObject
$markdown = ConvertTo-ParityMarkdown -Report $report
$json = (($report | ConvertTo-Json -Depth 12) -replace "`r`n", "`n") + "`n"

$mdPath = Join-Path $OutputDirectory 'cli-parity.md'
$jsonPath = Join-Path $OutputDirectory 'cli-parity.json'
if ($Check) {
    $stale = @()
    $currentMarkdown = $null
    if (Test-Path -LiteralPath $mdPath) { $currentMarkdown = ([System.IO.File]::ReadAllText($mdPath)) -replace "`r`n", "`n" }
    if ($currentMarkdown -ne $markdown) { $stale += (Split-Path -Leaf $mdPath) }
    # Windows PowerShell 5.1 and PowerShell 7 lay JSON out differently, so compare the content: read the committed file back and write both through this host's parser and serializer.
    $currentJson = $null
    if (Test-Path -LiteralPath $jsonPath) { $currentJson = (([System.IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json) | ConvertTo-Json -Depth 12) }
    if ($currentJson -ne (($json | ConvertFrom-Json) | ConvertTo-Json -Depth 12)) { $stale += (Split-Path -Leaf $jsonPath) }
    if ($stale.Count -gt 0) { throw ("Out of date: " + ($stale -join ', ') + ". Run ./scripts/parity/New-CliParityReport.ps1 and commit the result.") }
    'The parity report is up to date.'
    return
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($mdPath, $markdown, $utf8)
[System.IO.File]::WriteAllText($jsonPath, $json, $utf8)
"Wrote $mdPath and $jsonPath."
$t = $report.totals
"CLI $($report.cli.version): core $($t.core.wrapped) wrapped + $($t.core.partiallyWrapped) partial of $($t.core.inScope) in scope ($($t.core.coveredPercent)%); just-in-time $($t.jit.wrapped) + $($t.jit.partiallyWrapped) of $($t.jit.inScope) ($($t.jit.coveredPercent)%)."
