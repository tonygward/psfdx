Describe 'Release zip' {
    BeforeAll {
        $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Script = Join-Path $PSScriptRoot 'New-ReleaseZip.ps1'
        $script:Zip = & $script:Script -Version '9.9.9' -OutputFolder (Join-Path $TestDrive 'out')
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($script:Zip)
        try { $script:Names = @($archive.Entries | ForEach-Object { $_.FullName }) } finally { $archive.Dispose() }
        $script:Extract = Join-Path $TestDrive 'extract'
        [System.IO.Compression.ZipFile]::ExtractToDirectory($script:Zip, $script:Extract)
    }

    It 'is named for the version' {
        (Split-Path -Leaf $script:Zip) | Should -Be 'psfdx-9.9.9.zip'
    }

    It 'contains every module manifest, the installers and the changelog' {
        . (Join-Path $script:Root 'modules.ps1')
        foreach ($module in @(Get-PsfdxModules)) {
            $script:Names | Should -Contain "$module/$module.psd1"
        }
        foreach ($file in 'install.ps1', 'install-windows.ps1', 'uninstall.ps1', 'uninstall-windows.ps1', 'modules.ps1', 'README.md', 'CHANGELOG.md') {
            $script:Names | Should -Contain $file
        }
    }

    It 'contains no tests, prompts, docs or workflows' {
        @($script:Names | Where-Object { $_ -match '\.Tests\.ps1$|^prompts/|^docs/|^\.github/|^tests/|^scripts/' }).Count | Should -Be 0
    }

    It 'has module manifests that load from the extracted folder' {
        . (Join-Path $script:Root 'modules.ps1')
        # Required modules resolve from the extracted folder, as they would once installed
        $oldPath = $env:PSModulePath
        $env:PSModulePath = $script:Extract + [System.IO.Path]::PathSeparator + $oldPath
        try {
        foreach ($module in @(Get-PsfdxModules)) {
            $manifest = Join-Path (Join-Path $script:Extract $module) "$module.psd1"
            { Test-ModuleManifest -Path $manifest -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null } | Should -Not -Throw
        }
        } finally { $env:PSModulePath = $oldPath }
    }
}
