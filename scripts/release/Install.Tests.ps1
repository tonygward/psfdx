# The install and uninstall scripts copy the modules from a source checkout or the release zip into the user's module folder. The core module used to be
# installed as `psfdx`; that name now belongs to the Gallery umbrella and the core module is psfdx-core. These tests check that an old copy of the core
# module is removed (it would define every command twice) and that a Gallery install of psfdx, whose files sit in a version folder, is never touched.
# Each script runs in a child process with HOME, XDG_DATA_HOME and PSModulePath pointing into $TestDrive, so nothing outside it is read or written.
BeforeDiscovery {
    $script:windowsHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
}

BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:Root 'modules.ps1')
    $script:Shell = (Get-Process -Id $PID).Path
    $script:Run = {
        param([string] $Script, [string] $Home1, [string] $ModuleRoot, [string[]] $Arguments)
        $saved = @{ HOME = $env:HOME; USERPROFILE = $env:USERPROFILE; XDG = $env:XDG_DATA_HOME; PSM = $env:PSModulePath }
        $preference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $env:HOME = $Home1; $env:USERPROFILE = $Home1; $env:XDG_DATA_HOME = $Home1; $env:PSModulePath = $ModuleRoot
            $text = & $script:Shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $script:Root $Script) @Arguments 2>&1 | Out-String
            return [pscustomobject]@{ Output = $text; ExitCode = $LASTEXITCODE }
        } finally {
            $ErrorActionPreference = $preference
            $env:HOME = $saved.HOME; $env:USERPROFILE = $saved.USERPROFILE; $env:XDG_DATA_HOME = $saved.XDG; $env:PSModulePath = $saved.PSM
        }
    }
    # An old install of the core module as `psfdx`: its files sit directly in the folder.
    $script:AddLegacy = {
        param([string] $ModuleRoot)
        $old = Join-Path $ModuleRoot 'psfdx'
        New-Item -ItemType Directory -Path $old -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $old 'psfdx.psm1') -Value '# old core module'
        Set-Content -LiteralPath (Join-Path $old 'psfdx.psd1') -Value "@{ RootModule = 'psfdx.psm1'; ModuleVersion = '0.8.0' }"
    }
    # A Gallery install of psfdx: PowerShellGet keeps the files in a version folder.
    $script:AddGallery = {
        param([string] $ModuleRoot)
        $gallery = Join-Path (Join-Path $ModuleRoot 'psfdx') '0.9.0'
        New-Item -ItemType Directory -Path $gallery -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $gallery 'psfdx.psd1') -Value "@{ ModuleVersion = '0.9.0' }"
    }
}

Describe 'install.ps1 and uninstall.ps1 and the old psfdx core module' {
    BeforeEach {
        $script:Home1 = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:ModuleRoot = Join-Path (Join-Path $script:Home1 'powershell') 'Modules'
        New-Item -ItemType Directory -Path $script:ModuleRoot -Force | Out-Null
    }

    It 'installs every module as its own folder, with psfdx-core and without a psfdx folder' {
        $run = & $script:Run 'install.ps1' $script:Home1 $script:ModuleRoot @()
        $run.ExitCode | Should -Be 0 -Because $run.Output
        foreach ($module in Get-PsfdxModules) { (Join-Path (Join-Path $script:ModuleRoot $module) "$module.psd1") | Should -Exist }
        (Join-Path $script:ModuleRoot 'psfdx') | Should -Not -Exist
    }

    It 'removes the old core module installed as psfdx, and says so' {
        & $script:AddLegacy $script:ModuleRoot
        $run = & $script:Run 'install.ps1' $script:Home1 $script:ModuleRoot @()
        $run.ExitCode | Should -Be 0 -Because $run.Output
        (Join-Path $script:ModuleRoot 'psfdx') | Should -Not -Exist
        (Join-Path (Join-Path $script:ModuleRoot 'psfdx-core') 'psfdx-core.psd1') | Should -Exist
        $run.Output | Should -BeLike "*Removed the old 'psfdx' module*psfdx-core*"
    }

    It 'leaves a Gallery install of psfdx alone' {
        & $script:AddGallery $script:ModuleRoot
        $run = & $script:Run 'install.ps1' $script:Home1 $script:ModuleRoot @()
        $run.ExitCode | Should -Be 0 -Because $run.Output
        (Join-Path (Join-Path (Join-Path $script:ModuleRoot 'psfdx') '0.9.0') 'psfdx.psd1') | Should -Exist
        $run.Output | Should -Not -BeLike "*Removed the old*"
    }

    It 'uninstalls the modules and the old core module, and leaves a Gallery install of psfdx alone' {
        $null = & $script:Run 'install.ps1' $script:Home1 $script:ModuleRoot @()
        & $script:AddLegacy $script:ModuleRoot
        $run = & $script:Run 'uninstall.ps1' $script:Home1 $script:ModuleRoot @()
        $run.ExitCode | Should -Be 0 -Because $run.Output
        foreach ($module in Get-PsfdxModules) { (Join-Path $script:ModuleRoot $module) | Should -Not -Exist }
        (Join-Path $script:ModuleRoot 'psfdx') | Should -Not -Exist

        & $script:AddGallery $script:ModuleRoot
        $null = & $script:Run 'uninstall.ps1' $script:Home1 $script:ModuleRoot @()
        (Join-Path (Join-Path (Join-Path $script:ModuleRoot 'psfdx') '0.9.0') 'psfdx.psd1') | Should -Exist
    }
}

Describe 'install-windows.ps1 and uninstall-windows.ps1 and the old psfdx core module' -Skip:(-not $script:windowsHost) {
    BeforeEach {
        $script:Home1 = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:ModuleRoot = Join-Path (Join-Path (Join-Path $script:Home1 'Documents') 'PowerShell') 'Modules'
        New-Item -ItemType Directory -Path $script:ModuleRoot -Force | Out-Null
    }

    It 'installs psfdx-core, removes the old psfdx core module and leaves a Gallery psfdx alone' {
        & $script:AddLegacy $script:ModuleRoot
        $run = & $script:Run 'install-windows.ps1' $script:Home1 $script:ModuleRoot @()
        $run.ExitCode | Should -Be 0 -Because $run.Output
        foreach ($module in Get-PsfdxModules) { (Join-Path (Join-Path $script:ModuleRoot $module) "$module.psd1") | Should -Exist }
        (Join-Path $script:ModuleRoot 'psfdx') | Should -Not -Exist

        & $script:AddGallery $script:ModuleRoot
        $null = & $script:Run 'install-windows.ps1' $script:Home1 $script:ModuleRoot @()
        (Join-Path (Join-Path (Join-Path $script:ModuleRoot 'psfdx') '0.9.0') 'psfdx.psd1') | Should -Exist
    }

    It 'uninstalls the modules and the old core module, and leaves a Gallery psfdx alone' {
        $null = & $script:Run 'install-windows.ps1' $script:Home1 $script:ModuleRoot @()
        & $script:AddLegacy $script:ModuleRoot
        $run = & $script:Run 'uninstall-windows.ps1' $script:Home1 $script:ModuleRoot @()
        $run.ExitCode | Should -Be 0 -Because $run.Output
        foreach ($module in Get-PsfdxModules) { (Join-Path $script:ModuleRoot $module) | Should -Not -Exist }
        (Join-Path $script:ModuleRoot 'psfdx') | Should -Not -Exist
        & $script:AddGallery $script:ModuleRoot
        $null = & $script:Run 'uninstall-windows.ps1' $script:Home1 $script:ModuleRoot @()
        (Join-Path (Join-Path (Join-Path $script:ModuleRoot 'psfdx') '0.9.0') 'psfdx.psd1') | Should -Exist
    }
}
