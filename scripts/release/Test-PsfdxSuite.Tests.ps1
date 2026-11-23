# Runs scripts/release/Test-PsfdxSuite.ps1 on an install laid out the way PowerShellGet lays one out (<folder>/<module>/<version>/...), made straight
# from the built suite packages, so it needs no repository and no PowerShellGet. The real install from a package repository is
# checked by the CI - Suite install workflow. Here the point is that the checks pass on a good install and fail, naming the problem, on a bad one.
BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Check = Join-Path $PSScriptRoot 'Test-PsfdxSuite.ps1'
    . (Join-Path $script:Root 'modules.ps1')
    $script:Version = (Get-Content -Path (Join-Path $script:Root 'VERSION') -Raw).Trim()
    $built = Join-Path $TestDrive 'built'
    $script:Packages = @(& (Join-Path $PSScriptRoot 'Build-GalleryPackage.ps1') -Layout Suite -OutputFolder $built)
    $script:Deps = Get-PsfdxModuleDependencies
    $script:Install = {
        param([string] $Folder, [string[]] $Names)
        New-Item -ItemType Directory -Path $Folder | Out-Null
        foreach ($package in $script:Packages) {
            $name = Split-Path -Leaf $package
            if ($Names -notcontains $name) { continue }
            Copy-Item -LiteralPath $package -Destination (Join-Path (Join-Path $Folder $name) $script:Version) -Recurse
        }
    }
    $script:All = @($script:Packages | ForEach-Object { Split-Path -Leaf $_ })
    $script:Good = Join-Path $TestDrive 'good'
    & $script:Install $script:Good $script:All
    $script:Alone = Join-Path $TestDrive 'alone'
    & $script:Install $script:Alone (@('psfdx-logs') + @($script:Deps['psfdx-logs']))
    $script:Shell = (Get-Process -Id $PID).Path
    # Runs the check in a child process and returns its output and exit code. Pester sets $ErrorActionPreference to Stop, and Windows PowerShell 5.1 then
    # turns a line the child writes to stderr (which `throw` does) into a terminating error, so the preference is relaxed for the call.
    $script:Run = {
        param([string[]] $Arguments)
        $saved = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $text = & $script:Shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:Check @Arguments 2>&1 | Out-String
            return [pscustomobject]@{ Output = $text; ExitCode = $LASTEXITCODE }
        } finally { $ErrorActionPreference = $saved }
    }
}

Describe 'Test-PsfdxSuite' {
    It 'passes on a complete install, with a standalone module beside it' {
        $run = & $script:Run @('-ModulePath', $script:Good, '-StandalonePath', $script:Alone)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -BeLike '*installs as 9 modules*no duplicate command*psfdx-logs works on its own with 2 dependencies*'
    }

    It 'fails, naming the module, when one module was not installed' {
        $folder = Join-Path $TestDrive 'missing-module'
        & $script:Install $folder @($script:All | Where-Object { $_ -ne 'psfdx-metadata' })
        $run = & $script:Run @('-ModulePath', $folder)
        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -BeLike '*psfdx-metadata*'
    }

    It 'fails when the umbrella exports commands itself, because the modules must own them' {
        $folder = Join-Path $TestDrive 'umbrella-exports'
        & $script:Install $folder $script:All
        $manifest = Join-Path (Join-Path (Join-Path $folder 'psfdx') $script:Version) 'psfdx.psd1'
        $text = [System.IO.File]::ReadAllText($manifest)
        [System.IO.File]::WriteAllText($manifest, [regex]::Replace($text, "FunctionsToExport\s*=\s*@\(\s*\)", "FunctionsToExport = @('Get-Nothing')"))
        $run = & $script:Run @('-ModulePath', $folder)
        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -BeLike '*umbrella*'
    }

    It 'fails when a module exports a command its manifest in the repository does not list' {
        $folder = Join-Path $TestDrive 'extra-export'
        & $script:Install $folder $script:All
        $manifest = Join-Path (Join-Path (Join-Path $folder 'psfdx-sandbox') $script:Version) 'psfdx-sandbox.psd1'
        $text = [System.IO.File]::ReadAllText($manifest)
        [System.IO.File]::WriteAllText($manifest, [regex]::Replace($text, "FunctionsToExport\s*=\s*@\(", "FunctionsToExport = @('Get-NotListed', "))
        $run = & $script:Run @('-ModulePath', $folder)
        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -BeLike '*psfdx-sandbox*'
    }

    It 'fails when a standalone install is missing a dependency' {
        $folder = Join-Path $TestDrive 'alone-broken'
        & $script:Install $folder @('psfdx-logs', 'psfdx-shared')
        $run = & $script:Run @('-ModulePath', $script:Good, '-StandalonePath', $folder)
        $run.ExitCode | Should -Not -Be 0
    }
}
