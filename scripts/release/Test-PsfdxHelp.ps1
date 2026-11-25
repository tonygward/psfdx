<#
.SYNOPSIS
Checks that the help of every command in an installed (or built) psfdx package works.
.DESCRIPTION
Imports psfdx from a module path (the bundle, or the umbrella and the modules it requires) and, for each function exported by the psfdx modules, runs Get-Help -Full, -Examples and -Parameter *.
It fails when a command has no real synopsis or description, a parameter without a description, no written example, or no
SALESFORCE CLI section. Used by the Gallery install check, after the package has been installed from the Gallery, and by the
repository tests on a package built from the source. Works on Windows PowerShell 5.1 and PowerShell 7; needs no Salesforce CLI.
#>
[CmdletBinding()]
Param(
    # A folder that contains the psfdx module folder (for example the Save-Module path, or the parent of out/psfdx).
    [Parameter(Mandatory = $true)][string] $ModulePath,
    # The version to import. Leave out for a folder without a version folder.
    [Parameter(Mandatory = $false)][string] $Version,
    # Run Get-Help -Examples and -Parameter * for every tenth command only. The checks on -Full stay complete. For the repository tests; the Gallery check runs everything.
    [Parameter(Mandatory = $false)][switch] $Quick
)

$ErrorActionPreference = 'Stop'
$env:PSModulePath = $ModulePath + [IO.Path]::PathSeparator + $env:PSModulePath
if ($Version) { Import-Module psfdx -RequiredVersion $Version -WarningAction SilentlyContinue } else { Import-Module psfdx -WarningAction SilentlyContinue }

$common = @([System.Management.Automation.PSCmdlet]::CommonParameters) + @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
$commands = @(Get-Command -Module 'psfdx*' | Where-Object { $_.CommandType -eq 'Function' } | Sort-Object Name)
if ($commands.Count -lt 100) { throw "Only $($commands.Count) functions were found in the psfdx modules; expected well over 100." }

$failures = New-Object System.Collections.Generic.List[string]
$position = 0
foreach ($command in $commands) {
    $position++
    $name = $command.Name
    $problems = @()
    $help = Get-Help -Name $name -Full
    $synopsis = ([string]$help.Synopsis).Trim()
    if (-not $synopsis -or $synopsis -like ($name + '*')) { $problems += 'no synopsis' }
    if (-not (($help.description | Out-String).Trim())) { $problems += 'no description' }
    $missing = @()
    foreach ($parameter in $command.Parameters.Keys) {
        if ($common -contains $parameter) { continue }
        $entry = @($help.parameters.parameter | Where-Object { $_.name -eq $parameter })[0]
        if (-not $entry -or -not (($entry.description | Out-String).Trim())) { $missing += $parameter }
    }
    if ($missing.Count) { $problems += 'parameters without help: ' + ($missing -join ', ') }
    $written = @($help.examples.example | Where-Object { (($_.code | Out-String).Trim()) -and (($_.code | Out-String).Trim() -notmatch '\[<CommonParameters>\]') })
    if ($written.Count -eq 0) { $problems += 'no written example' }
    if (($help.description.Text -join [Environment]::NewLine) -notmatch '(?m)^[ \t]*SALESFORCE CLI[ \t]*\r?$') { $problems += 'no SALESFORCE CLI section' }
    # The other ways a person asks for help must work too.
    if (-not $Quick -or ($position % 10) -eq 1) {
        if (@((Get-Help -Name $name -Examples).examples.example).Count -eq 0) { $problems += 'Get-Help -Examples returned nothing' }
        $parameterHelp = @(Get-Help -Name $name -Parameter '*' -ErrorAction SilentlyContinue)
        $expected = @($command.Parameters.Keys | Where-Object { $common -notcontains $_ }).Count
        if ($expected -gt 0 -and $parameterHelp.Count -lt $expected) { $problems += 'Get-Help -Parameter * returned fewer parameters than the command has' }
    }
    if ($problems.Count) { $failures.Add($name + ': ' + ($problems -join '; ')) }
}
if ($failures.Count) { throw ("Help is incomplete for $($failures.Count) of $($commands.Count) commands:`n" + ($failures -join "`n")) }
"The help of all $($commands.Count) psfdx commands is complete (PowerShell $($PSVersionTable.PSVersion))."
