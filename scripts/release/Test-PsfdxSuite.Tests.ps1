# Runs scripts/release/Test-PsfdxSuite.ps1 on an install laid out the way PowerShellGet lays one out (<folder>/psfdx/<version>/...), made straight from
# the built package, so it needs no repository and no PowerShellGet. The real install from a package repository is checked by the CI - Suite install
# workflow. Here the point is that the checks pass on a good install and fail, naming the problem, on a bad one.
BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Check = Join-Path $PSScriptRoot 'Test-PsfdxSuite.ps1'
    . (Join-Path $script:Root 'modules.ps1')
    $script:Version = (Get-Content -Path (Join-Path $script:Root 'VERSION') -Raw).Trim()
    $script:Built = Join-Path $TestDrive 'built'
    & (Join-Path $PSScriptRoot 'Build-GalleryPackage.ps1') -OutputFolder (Join-Path $script:Built 'psfdx') | Out-Null
    # An install: a copy of the built package in <folder>/psfdx/<version>.
    $script:Install = {
        param([string] $Name)
        $folder = Join-Path $TestDrive $Name
        $package = Join-Path (Join-Path $folder 'psfdx') $script:Version
        New-Item -ItemType Directory -Path (Split-Path -Parent $package) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:Built 'psfdx') -Destination $package -Recurse
        return $folder
    }
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
    $script:Good = & $script:Install 'good'
}

Describe 'Test-PsfdxSuite' {
    It 'passes on a complete install of the one package, and writes the evidence' {
        $evidence = Join-Path $TestDrive 'evidence.json'
        $run = & $script:Run @('-ModulePath', $script:Good, '-EvidencePath', $evidence)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -BeLike '*one package holding 10 modules*only the * core commands*Get-Command -Module psfdx-logs shows exactly the * logs commands*no duplicate*one representative command from each of the 10 modules runs*'
        $data = Get-Content -LiteralPath $evidence -Raw | ConvertFrom-Json
        $data.package | Should -Be 'psfdx'
        $data.version | Should -Be $script:Version
        $data.duplicateCommandNames | Should -Be 0
        $data.totalCommands | Should -BeGreaterThan 250
        @($data.commandsPerModule.PSObject.Properties).Count | Should -Be 10
        @($data.representativeCommands.PSObject.Properties | Where-Object { -not $_.Value.ran }).Count | Should -Be 0
        $data.brandNewSession.note | Should -BeLike '*one package installs one folder*'
    }

    It 'fails, naming the module, when a module folder is missing from the package' {
        $folder = & $script:Install 'missing-module'
        Remove-Item -LiteralPath (Join-Path (Join-Path (Join-Path $folder 'psfdx') $script:Version) 'psfdx-metadata') -Recurse -Force
        $run = & $script:Run @('-ModulePath', $folder)
        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -BeLike '*psfdx-metadata*'
    }

    It 'fails when the core module exports a command that is not a core command, because Get-Command -Module psfdx must show only the core' {
        $folder = & $script:Install 'extra-export'
        $package = Join-Path (Join-Path $folder 'psfdx') $script:Version
        $manifest = Join-Path $package 'psfdx.psd1'
        [System.IO.File]::WriteAllText($manifest, [regex]::Replace([System.IO.File]::ReadAllText($manifest), "FunctionsToExport\s*=\s*@\(", "FunctionsToExport = @('Get-NotACoreCommand', "))
        $code = Join-Path $package 'psfdx.psm1'
        [System.IO.File]::WriteAllText($code, [System.IO.File]::ReadAllText($code) + "`nfunction Get-NotACoreCommand { 'x' }`n")
        $run = & $script:Run @('-ModulePath', $folder)
        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -BeLike '*Get-Command -Module psfdx*core*'
    }

    It 'fails when a separate psfdx-* package sits beside the one package' {
        $folder = & $script:Install 'second-package'
        New-Item -ItemType Directory -Path (Join-Path (Join-Path $folder 'psfdx-logs') $script:Version) -Force | Out-Null
        $run = & $script:Run @('-ModulePath', $folder)
        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -BeLike '*no separate psfdx-* package*'
    }

    It 'fails when the loader is missing, so the other modules never get their own identity' {
        $folder = & $script:Install 'no-loader'
        $file = Join-Path (Join-Path (Join-Path $folder 'psfdx') $script:Version) 'psfdx.psm1'
        $text = [System.IO.File]::ReadAllText($file)
        $start = $text.IndexOf('#region psfdx Gallery package: the other modules of the suite')
        $start | Should -BeGreaterThan 0
        [System.IO.File]::WriteAllText($file, $text.Substring(0, $start))
        $run = & $script:Run @('-ModulePath', $folder)
        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -BeLike '*psfdx-logs*'
    }
}
