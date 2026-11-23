<#
.SYNOPSIS
Builds the psfdx Gallery package and publishes it to a local folder repository, for the CI install and upgrade tests.
.DESCRIPTION
Builds Build-GalleryPackage.ps1 from the repository and publishes the package with Publish-PSResource to a folder, so it is a real NuGet package that
PowerShellGet (Install-Module, Save-Module, Update-Module) and PSResourceGet install from, exactly as they install it from the PowerShell Gallery. This
is how CI checks an install of the actual packaged artifact without the Gallery and without publishing anything.
With -IncludeUpgrade it also builds and publishes a second version, one patch higher, from a temporary copy of the modules with only the version
numbers changed, so an upgrade (Update-Module) can be tested.
The folder repository is registered with PSResourceGet only while the package is published; register it for PowerShellGet yourself:
Register-PSRepository -Name <name> -SourceLocation <folder> -InstallationPolicy Trusted.
Returns an object with the folder, the repository name and the old and new versions. Needs Microsoft.PowerShell.PSResourceGet.
#>
[CmdletBinding()]
Param(
    # The folder that becomes the repository. Created if it does not exist.
    [Parameter(Mandatory = $true)][string] $RepositoryFolder,
    [Parameter(Mandatory = $false)][string] $RepositoryName = 'psfdx-local',
    [Parameter(Mandatory = $false)][switch] $IncludeUpgrade,
    [Parameter(Mandatory = $false)][string] $Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) }
$build = Join-Path (Join-Path (Join-Path $Root 'scripts') 'release') 'Build-GalleryPackage.ps1'
Import-Module Microsoft.PowerShell.PSResourceGet -ErrorAction Stop
if (-not (Test-Path -LiteralPath $RepositoryFolder)) { New-Item -ItemType Directory -Path $RepositoryFolder -Force | Out-Null }
$folder = (Resolve-Path -LiteralPath $RepositoryFolder).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('psfdx-repo-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

$oldVersion = (Get-Content -Path (Join-Path $Root 'VERSION') -Raw).Trim()
$newVersion = $null
if (Get-PSResourceRepository -Name $RepositoryName -ErrorAction SilentlyContinue) { Unregister-PSResourceRepository -Name $RepositoryName }
Register-PSResourceRepository -Name $RepositoryName -Uri $folder -Trusted
try {
    $package = & $build -Root $Root -OutputFolder (Join-Path (Join-Path $work 'old') 'psfdx')
    Publish-PSResource -Path $package -Repository $RepositoryName -ErrorAction Stop

    if ($IncludeUpgrade) {
        $parts = $oldVersion.Split('.')
        $newVersion = "$($parts[0]).$($parts[1]).$([int]$parts[2] + 1)"
        # A copy of the modules with only the version numbers changed. Nothing else about the package differs.
        $copy = Join-Path $work 'next'
        New-Item -ItemType Directory -Path $copy | Out-Null
        foreach ($item in 'modules.ps1', 'LICENSE') { Copy-Item -LiteralPath (Join-Path $Root $item) -Destination $copy }
        Set-Content -LiteralPath (Join-Path $copy 'VERSION') -Value $newVersion -NoNewline
        . (Join-Path $Root 'modules.ps1')
        foreach ($module in Get-PsfdxModules) {
            Copy-Item -LiteralPath (Join-Path $Root $module) -Destination $copy -Recurse
            $manifest = Join-Path (Join-Path $copy $module) "$module.psd1"
            $text = [IO.File]::ReadAllText($manifest)
            $changed = [regex]::Replace($text, "(ModuleVersion\s*=\s*)'$([regex]::Escape($oldVersion))'", "`$1'$newVersion'")
            if ($changed -eq $text) { throw "Could not change the version in $manifest" }
            [IO.File]::WriteAllText($manifest, $changed)
        }
        $nextPackage = & $build -Root $copy -OutputFolder (Join-Path (Join-Path $work 'new') 'psfdx')
        Publish-PSResource -Path $nextPackage -Repository $RepositoryName -ErrorAction Stop
    }
} finally {
    Unregister-PSResourceRepository -Name $RepositoryName -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
[pscustomobject]@{ Folder = $folder; Name = $RepositoryName; OldVersion = $oldVersion; NewVersion = $newVersion; Packages = @(Get-ChildItem -LiteralPath $folder -Filter '*.nupkg' | ForEach-Object Name | Sort-Object) }
