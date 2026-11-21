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
}

Describe 'Test-PsfdxHelp on the built package' {
    It 'passes in PowerShell 7 or the current host' {
        $output = & $script:pwsh -NoProfile -NonInteractive -File $script:check -Quick -ModulePath $script:package 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $output | Should -BeLike '*help of all*psfdx commands is complete*'
    }

    It 'passes in Windows PowerShell 5.1' -Skip:(-not $script:hasPowerShell) {
        $output = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:check -Quick -ModulePath $script:package 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $output | Should -BeLike '*help of all*psfdx commands is complete*'
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
        $output = & $script:pwsh -NoProfile -NonInteractive -File $script:check -Quick -ModulePath $broken 2>&1 | Out-String
        $LASTEXITCODE | Should -Not -Be 0
        $output | Should -BeLike '*Debug-SalesforceJest*'
    }
}
