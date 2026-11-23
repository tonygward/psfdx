<#
.SYNOPSIS
Publishes the suite packages built by Build-GalleryPackage.ps1 -Layout Suite to a package repository, in dependency order.
.DESCRIPTION
Used by the release (CD - Publish to PowerShell Gallery, repository PSGallery) and by the CI install test (a folder repository), so
both run the same code. For each package, in the order given (every package after the packages it requires, the umbrella last):
  - it skips the package when that exact version is already in the repository, so a run that stopped half way can be run again.
    Gallery versions are permanent and are never replaced;
  - it publishes it with Publish-PSResource (Microsoft.PowerShell.PSResourceGet);
  - it waits until the repository lists the new version, because the next package requires it and the Gallery can take a few minutes to
    list a new upload.
While publishing, the folder that holds the built packages is on PSModulePath: Test-ModuleManifest, which Publish-PSResource runs, has to
find each required module to accept a manifest that requires it.
With -DryRun nothing is uploaded: Publish-PSResource runs with -WhatIf and -SkipDependenciesCheck.
Needs PowerShell 7 or Windows PowerShell 5.1 with Microsoft.PowerShell.PSResourceGet installed.
#>
[CmdletBinding()]
Param(
    # The package folders, in the order to publish them (what Build-GalleryPackage.ps1 -Layout Suite returns).
    [Parameter(Mandatory = $true)][string[]] $Packages,
    # A repository registered with PSResourceGet (PSGallery, or one made with Register-PSResourceRepository).
    [Parameter(Mandatory = $true)][string] $Repository,
    [Parameter(Mandatory = $false)][string] $ApiKey,
    # How long to wait for a published package to be listed. Use 0 for a folder repository, which lists it at once.
    [Parameter(Mandatory = $false)][int] $WaitSeconds = 900,
    [Parameter(Mandatory = $false)][switch] $DryRun
)

$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.PSResourceGet -ErrorAction Stop
$separator = [IO.Path]::PathSeparator
$buildRoots = @($Packages | ForEach-Object { Split-Path -Parent (Resolve-Path -LiteralPath $_).Path } | Select-Object -Unique)
$env:PSModulePath = (($buildRoots -join $separator) + $separator + $env:PSModulePath)

function Test-Listed([string] $Name, [string] $Version) {
    $found = @(Find-PSResource -Name $Name -Version $Version -Repository $Repository -ErrorAction SilentlyContinue)
    return ($found.Count -gt 0)
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($package in $Packages) {
    $path = (Resolve-Path -LiteralPath $package).Path
    $name = Split-Path -Leaf $path
    $manifest = Import-PowerShellDataFile -Path (Join-Path $path "$name.psd1")
    $version = [string]$manifest.ModuleVersion

    if (Test-Listed $name $version) {
        Write-Host "$name $version is already in $Repository; skipping (versions can't be replaced)."
        $results.Add([pscustomobject]@{ Name = $name; Version = $version; Action = 'already published' })
        continue
    }
    if ($DryRun) {
        Write-Host "Dry run: would publish $name $version to $Repository."
        Publish-PSResource -Path $path -Repository $Repository -ApiKey 'dry-run' -SkipDependenciesCheck -WhatIf
        $results.Add([pscustomobject]@{ Name = $name; Version = $version; Action = 'dry run' })
        continue
    }

    Write-Host "Publishing $name $version to $Repository..."
    $publishArguments = @{ Path = $path; Repository = $Repository; ErrorAction = 'Stop' }
    if ($ApiKey) { $publishArguments['ApiKey'] = $ApiKey }
    Publish-PSResource @publishArguments

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $listed = Test-Listed $name $version
    while (-not $listed -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 15
        $listed = Test-Listed $name $version
    }
    if (-not $listed) { throw "$name $version was published but $Repository does not list it after $WaitSeconds seconds. Publishing stopped so nothing that requires it is published before it is available; run the publish again to continue." }
    Write-Host "$name $version is listed."
    $results.Add([pscustomobject]@{ Name = $name; Version = $version; Action = 'published' })
}
$results
