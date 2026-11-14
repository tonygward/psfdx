Describe 'Gallery bundle (one psfdx package)' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        $script:Build = Join-Path (Join-Path (Join-Path $script:Root 'scripts') 'release') 'Build-GalleryPackage.ps1'
        $script:Out = Join-Path $TestDrive 'psfdx'
        & $script:Build -OutputFolder $script:Out | Out-Null
        $script:Version = (Get-Content -Path (Join-Path $script:Root 'VERSION') -Raw).Trim()
        . (Join-Path $script:Root 'modules.ps1')
        $script:Expected = @()
        foreach ($module in Get-PsfdxModules) {
            $script:Expected += @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root $module) "$module.psd1")).FunctionsToExport)
        }
        $script:Expected = @($script:Expected | Sort-Object)
        $script:Manifest = Import-PowerShellDataFile -Path (Join-Path $script:Out 'psfdx.psd1')
        $script:Shell = (Get-Process -Id $PID).Path
    }

    It 'builds, and Test-ModuleManifest passes on the bundle' {
        { Test-ModuleManifest -Path (Join-Path $script:Out 'psfdx.psd1') -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null } | Should -Not -Throw
    }

    It 'has the version in VERSION and the stable Gallery identity' {
        $script:Manifest.ModuleVersion | Should -Be $script:Version
        $script:Manifest.GUID | Should -Be '2785d2bf-775f-4f2b-9d00-ee98f0163cf0'
    }

    It 'exports the union of every module manifest, by explicit name' {
        @($script:Manifest.FunctionsToExport | Sort-Object) | Should -Be $script:Expected
        @($script:Manifest.FunctionsToExport | Where-Object { $_ -match '[*?]' }).Count | Should -Be 0
        @($script:Expected | Select-Object -Unique).Count | Should -Be $script:Expected.Count
    }

    It 'nests the shared helpers first, then the core module, and the core GUID differs from the bundle' {
        $names = @($script:Manifest.NestedModules)
        $names[0] | Should -Be 'psfdx-shared/psfdx-shared.psd1'
        $names[1] | Should -Be 'psfdx-core/psfdx-core.psd1'
        $names.Count | Should -Be @(Get-PsfdxModules).Count
        (Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Out 'psfdx-core') 'psfdx-core.psd1')).GUID | Should -Not -Be $script:Manifest.GUID
    }

    It 'leaves no tests behind and no cross-module RequiredModules' {
        @(Get-ChildItem -Path $script:Out -Recurse -Filter '*.Tests.ps1').Count | Should -Be 0
        foreach ($manifest in Get-ChildItem -Path $script:Out -Recurse -Filter 'psfdx-*.psd1') {
            @(@((Import-PowerShellDataFile -Path $manifest.FullName).RequiredModules) | Where-Object { $_ }).Count | Should -Be 0 -Because $manifest.Name
        }
    }

    It 'carries the Gallery metadata and a release notes link' {
        $data = $script:Manifest.PrivateData.PSData
        $data.Tags | Should -Contain 'Salesforce'
        $data.Tags | Should -Contain 'PSEdition_Desktop'
        $data.Tags | Should -Contain 'PSEdition_Core'
        $data.ProjectUri | Should -Be 'https://github.com/tonygward/psfdx'
        $data.IconUri | Should -Match 'images/psfdx-logo\.png$'
        $data.ReleaseNotes | Should -Be "https://github.com/tonygward/psfdx/releases/tag/v$script:Version"
    }

    It 'imports in a fresh session and exposes every listed function and nothing else' {
        $manifest = Join-Path $script:Out 'psfdx.psd1'
        $command = "`$ErrorActionPreference = 'Stop'; Import-Module '$manifest' -WarningAction SilentlyContinue; (Get-Command -Module psfdx | Where-Object { `$_.CommandType -eq 'Function' } | Sort-Object Name | ForEach-Object Name) -join ','"
        $output = & $script:Shell -NoProfile -NonInteractive -Command $command
        $LASTEXITCODE | Should -Be 0
        $listed = @(($output | Select-Object -Last 1) -split ',')
        $listed | Should -Be $script:Expected
    }

    It 'lets each module find the shared helpers and the core module as siblings' {
        $manifest = Join-Path $script:Out 'psfdx.psd1'
        $command = "`$ErrorActionPreference = 'Stop'; Import-Module '$manifest' -WarningAction SilentlyContinue; foreach (`$name in 'psfdx-logs','psfdx-development','psfdx-sandbox','psfdx-metadata','psfdx-packages') { `$m = Get-Module `$name -All | Select-Object -First 1; if (-not (& `$m { (Get-Command Invoke-Salesforce -ErrorAction SilentlyContinue) -and (Get-Command Select-SalesforceRecords -ErrorAction SilentlyContinue) })) { throw `"`$name cannot see its siblings`" } }; 'ok'"
        (& $script:Shell -NoProfile -NonInteractive -Command $command | Select-Object -Last 1) | Should -Be 'ok'
    }

    It 'refuses two modules that export the same function' {
        $copy = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Path $copy | Out-Null
        foreach ($item in 'modules.ps1', 'VERSION') { Copy-Item -Path (Join-Path $script:Root $item) -Destination $copy }
        foreach ($module in Get-PsfdxModules) { Copy-Item -Path (Join-Path $script:Root $module) -Destination $copy -Recurse }
        $logs = Join-Path (Join-Path $copy 'psfdx-logs') 'psfdx-logs.psd1'
        $text = Get-Content -Path $logs -Raw
        $text = $text -replace "FunctionsToExport\s*=\s*@\(", "FunctionsToExport = @('Invoke-Salesforce', "
        Set-Content -Path $logs -Value $text
        { & $script:Build -OutputFolder (Join-Path $TestDrive 'dup') -Root $copy } | Should -Throw '*exported by both*'
    }
}
