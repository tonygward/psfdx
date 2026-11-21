# Runs scripts/release/Test-PsfdxHelp.ps1 on the package built from the source, the same one that is published to the Gallery, so
# a broken help block (or a command whose help the bundle loses) fails here and not after a release. Child processes keep it
# away from the modules the other tests load.
BeforeDiscovery {
    $script:windowsHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
    $script:hasPowerShell = $script:windowsHost -and [bool](Get-Command powershell -CommandType Application -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:scripts = $PSScriptRoot
    $script:build = Join-Path $PSScriptRoot 'Build-GalleryPackage.ps1'
    $script:check = Join-Path $PSScriptRoot 'Test-PsfdxHelp.ps1'
    $script:package = Join-Path $TestDrive 'bundle'
    New-Item -ItemType Directory -Path $script:package | Out-Null
    & $script:build -OutputFolder (Join-Path $script:package 'psfdx') | Out-Null
    $script:pwsh = (Get-Process -Id $PID).Path
    # Runs a child process and returns its output and exit code. Pester sets $ErrorActionPreference to Stop, and Windows PowerShell 5.1 then turns a line
    # the child writes to stderr (which `throw` does) into a terminating error, so the preference is relaxed for the call.
    function Invoke-ChildCheck {
        param([string] $Exe, [string[]] $Arguments)
        $saved = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $text = & $Exe @Arguments 2>&1 | Out-String
            return [pscustomobject]@{ Output = $text; ExitCode = $LASTEXITCODE }
        } finally { $ErrorActionPreference = $saved }
    }
}

Describe 'Test-PsfdxHelp on the built package' {
    It 'passes in PowerShell 7 or the current host' {
        $run = Invoke-ChildCheck -Exe $script:pwsh -Arguments @('-NoProfile', '-NonInteractive', '-File', $script:check, '-Quick', '-ModulePath', $script:package)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -BeLike '*help of all*psfdx commands is complete*'
    }

    It 'passes in Windows PowerShell 5.1' -Skip:(-not $script:hasPowerShell) {
        $run = Invoke-ChildCheck -Exe 'powershell' -Arguments @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $script:check, '-Quick', '-ModulePath', $script:package)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -BeLike '*help of all*psfdx commands is complete*'
    }

    It 'fails, naming the command, when a command has no help' {
        # A copy of the bundle with the help removed from one function.
        $broken = Join-Path $TestDrive 'broken'
        Copy-Item -LiteralPath $script:package -Destination $broken -Recurse
        $file = Join-Path $broken 'psfdx/psfdx-development/psfdx-development.psm1'
        $text = [System.IO.File]::ReadAllText($file)
        $marker = 'function Debug-SalesforceJest {'
        $start = $text.IndexOf($marker)
        $helpStart = $text.IndexOf('<#', $start)
        $helpEnd = $text.IndexOf('#>', $helpStart) + 2
        [System.IO.File]::WriteAllText($file, $text.Remove($helpStart, $helpEnd - $helpStart))
        $run = Invoke-ChildCheck -Exe $script:pwsh -Arguments @('-NoProfile', '-NonInteractive', '-File', $script:check, '-Quick', '-ModulePath', $broken)
        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -BeLike '*Debug-SalesforceJest*'
    }
}
