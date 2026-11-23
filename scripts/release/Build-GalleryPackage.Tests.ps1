Describe 'Gallery bundle (one psfdx package)' {
    BeforeAll {
        $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Build = Join-Path $PSScriptRoot 'Build-GalleryPackage.ps1'
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

    It 'carries the MIT licence text and a LicenseUri that points at it' {
        $script:Manifest.PrivateData.PSData.LicenseUri | Should -Be 'https://github.com/tonygward/psfdx/blob/main/LICENSE'
        $bundled = Join-Path $script:Out 'LICENSE'
        $bundled | Should -Exist
        (Get-Content -Path $bundled -Raw) | Should -Match 'MIT License'
        (Get-Content -Path $bundled -Raw) | Should -Be (Get-Content -Path (Join-Path $script:Root 'LICENSE') -Raw)
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
        $command = "`$ErrorActionPreference = 'Stop'; Import-Module '$manifest' -WarningAction SilentlyContinue; foreach (`$name in 'psfdx-logs','psfdx-development','psfdx-sandbox','psfdx-metadata','psfdx-packages') { `$m = Get-Module `$name -All | Select-Object -First 1; if (-not (& `$m { (Get-Command Invoke-Salesforce -ErrorAction SilentlyContinue) -and (Get-Command Select-SalesforceRecords -ErrorAction SilentlyContinue) })) { throw (`$name + ' cannot see its siblings') } }; 'ok'"
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

Describe 'Gallery suite (the psfdx umbrella plus one package per module)' {
    BeforeAll {
        $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Build = Join-Path $PSScriptRoot 'Build-GalleryPackage.ps1'
        . (Join-Path $script:Root 'modules.ps1')
        $script:Version = (Get-Content -Path (Join-Path $script:Root 'VERSION') -Raw).Trim()
        $script:Out = Join-Path $TestDrive 'suite'
        $script:Packages = @(& $script:Build -Layout Suite -OutputFolder $script:Out)
        $script:Names = @($script:Packages | ForEach-Object { Split-Path -Leaf $_ })
        $script:Deps = Get-PsfdxModuleDependencies
        $script:Manifests = @{}
        foreach ($name in $script:Names) { $script:Manifests[$name] = Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Out $name) "$name.psd1") }
        # A copy of the repository's modules, for the tests that break something on purpose.
        $script:NewRepo = {
            param([string] $Name)
            $copy = Join-Path $TestDrive $Name
            New-Item -ItemType Directory -Path $copy | Out-Null
            foreach ($item in 'modules.ps1', 'VERSION', 'LICENSE') { Copy-Item -Path (Join-Path $script:Root $item) -Destination $copy }
            foreach ($module in Get-PsfdxModules) { Copy-Item -Path (Join-Path $script:Root $module) -Destination $copy -Recurse }
            return $copy
        }
        $script:Edit = {
            param([string] $Path, [scriptblock] $Change)
            $text = [System.IO.File]::ReadAllText($Path)
            [System.IO.File]::WriteAllText($Path, (& $Change $text))
        }
    }

    It 'builds the umbrella and one package per module, the umbrella last and the shared helpers first' {
        $script:Names.Count | Should -Be (@(Get-PsfdxModules).Count + 1)
        $script:Names[-1] | Should -Be 'psfdx'
        $script:Names[0] | Should -Be 'psfdx-shared'
        @($script:Names | Select-Object -Unique).Count | Should -Be $script:Names.Count
        foreach ($module in Get-PsfdxModules) { $script:Names | Should -Contain $module }
    }

    It 'publishes every package after the packages it requires' {
        foreach ($name in $script:Names) {
            $position = [array]::IndexOf($script:Names, $name)
            foreach ($required in @($script:Manifests[$name].RequiredModules | ForEach-Object { $_.ModuleName })) {
                [array]::IndexOf($script:Names, $required) | Should -BeLessThan $position -Because "$name requires $required"
            }
        }
    }

    It 'has a valid manifest for every package once the built folder is on the module path' {
        $saved = $env:PSModulePath
        try {
            $env:PSModulePath = $script:Out + [IO.Path]::PathSeparator + $env:PSModulePath
            foreach ($name in $script:Names) {
                { Test-ModuleManifest -Path (Join-Path (Join-Path $script:Out $name) "$name.psd1") -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null } | Should -Not -Throw -Because $name
            }
        } finally { $env:PSModulePath = $saved }
    }

    It 'gives every package the repository version, and the umbrella the stable Gallery identity' {
        foreach ($name in $script:Names) { $script:Manifests[$name].ModuleVersion | Should -Be $script:Version -Because $name }
        $script:Manifests['psfdx'].GUID | Should -Be '2785d2bf-775f-4f2b-9d00-ee98f0163cf0'
    }

    It 'makes the umbrella require every module at the exact version, with each module GUID, and hold no code' {
        $umbrella = $script:Manifests['psfdx']
        $umbrella.ContainsKey('RootModule') | Should -BeFalse
        @($umbrella.FunctionsToExport).Count | Should -Be 0
        @($umbrella.CmdletsToExport).Count | Should -Be 0
        @(Get-ChildItem -Path (Join-Path $script:Out 'psfdx') -File | ForEach-Object Name | Sort-Object) | Should -Be @('LICENSE', 'psfdx.psd1')
        $required = @($umbrella.RequiredModules)
        @($required | ForEach-Object { $_.ModuleName } | Sort-Object) | Should -Be @(Get-PsfdxModules | Sort-Object)
        foreach ($entry in $required) {
            $entry.RequiredVersion | Should -Be $script:Version -Because $entry.ModuleName
            $entry.GUID | Should -Be $script:Manifests[$entry.ModuleName].GUID -Because $entry.ModuleName
        }
    }

    It 'requires exactly the modules in the dependency map, at the exact version, in every module package' {
        foreach ($module in Get-PsfdxModules) {
            $required = @($script:Manifests[$module].RequiredModules | Where-Object { $_ })
            @($required | ForEach-Object { $_.ModuleName } | Sort-Object) | Should -Be @($script:Deps[$module] | Sort-Object) -Because $module
            foreach ($entry in $required) { $entry.RequiredVersion | Should -Be $script:Version -Because "$module requires $($entry.ModuleName)" }
        }
    }

    It 'lets each module export exactly what its manifest in the repository lists, so no command is exported twice' {
        $seen = @{}
        foreach ($module in Get-PsfdxModules) {
            $listed = @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root $module) "$module.psd1")).FunctionsToExport | Sort-Object)
            @($script:Manifests[$module].FunctionsToExport | Sort-Object) | Should -Be $listed -Because $module
            foreach ($function in $listed) {
                $function | Should -Not -Match '[*?]'
                $seen.ContainsKey($function) | Should -BeFalse -Because "$function is exported by $module and by $($seen[$function])"
                $seen[$function] = $module
            }
        }
    }

    It 'leaves no tests behind, ships the licence in every package and carries the Gallery metadata and no prerelease' {
        @(Get-ChildItem -Path $script:Out -Recurse -Filter '*.Tests.ps1').Count | Should -Be 0
        foreach ($name in $script:Names) {
            (Get-Content -Path (Join-Path (Join-Path $script:Out $name) 'LICENSE') -Raw) | Should -Be (Get-Content -Path (Join-Path $script:Root 'LICENSE') -Raw) -Because $name
            $data = $script:Manifests[$name].PrivateData.PSData
            $data.Tags | Should -Contain 'Salesforce' -Because $name
            $data.Tags | Should -Contain 'PSEdition_Core' -Because $name
            $data.Tags | Should -Contain 'PSEdition_Desktop' -Because $name
            $data.ProjectUri | Should -Be 'https://github.com/tonygward/psfdx' -Because $name
            $data.LicenseUri | Should -Be 'https://github.com/tonygward/psfdx/blob/main/LICENSE' -Because $name
            $data.IconUri | Should -Match 'images/psfdx-logo\.png$' -Because $name
            $data.ReleaseNotes | Should -Be "https://github.com/tonygward/psfdx/releases/tag/v$script:Version" -Because $name
            $data.ContainsKey('Prerelease') | Should -BeFalse -Because $name
            $script:Manifests[$name].Description | Should -Not -BeNullOrEmpty -Because $name
            $script:Manifests[$name].CompatiblePSEditions | Should -Contain 'Desktop' -Because $name
            $script:Manifests[$name].PowerShellVersion | Should -Be '5.1' -Because $name
        }
    }

    It 'gives every package its own GUID' {
        $guids = @($script:Names | ForEach-Object { $script:Manifests[$_].GUID })
        @($guids | Select-Object -Unique).Count | Should -Be $guids.Count
    }

    It 'refuses a dependency that loops' {
        $copy = & $script:NewRepo 'loop'
        & $script:Edit (Join-Path $copy 'modules.ps1') { param($t) $t.Replace("'psfdx-shared'      = @()", "'psfdx-shared'      = @('psfdx-logs')") }
        { & $script:Build -Layout Suite -OutputFolder (Join-Path $TestDrive 'loop-out') -Root $copy } | Should -Throw '*loop*'
    }

    It 'refuses a dependency on a module that is not in the repository' {
        $copy = & $script:NewRepo 'missing'
        & $script:Edit (Join-Path $copy 'modules.ps1') { param($t) $t.Replace("'psfdx-sandbox'     = @('psfdx-shared')", "'psfdx-sandbox'     = @('psfdx-shared', 'psfdx-nothing')") }
        { & $script:Build -Layout Suite -OutputFolder (Join-Path $TestDrive 'missing-out') -Root $copy } | Should -Throw '*psfdx-nothing*'
    }

    It 'refuses a module the dependency map does not list' {
        $copy = & $script:NewRepo 'unlisted'
        & $script:Edit (Join-Path $copy 'modules.ps1') { param($t) $t.Replace("        'psfdx-sandbox'     = @('psfdx-shared')`r`n", '').Replace("        'psfdx-sandbox'     = @('psfdx-shared')`n", '') }
        { & $script:Build -Layout Suite -OutputFolder (Join-Path $TestDrive 'unlisted-out') -Root $copy } | Should -Throw '*no entry for psfdx-sandbox*'
    }

    It 'refuses version drift between modules' {
        $copy = & $script:NewRepo 'drift'
        & $script:Edit (Join-Path (Join-Path $copy 'psfdx-sandbox') 'psfdx-sandbox.psd1') { param($t) $t -replace "ModuleVersion = '[0-9.]+'", "ModuleVersion = '9.9.9'" }
        { & $script:Build -Layout Suite -OutputFolder (Join-Path $TestDrive 'drift-out') -Root $copy } | Should -Throw '*psfdx-sandbox is 9.9.9*'
    }

    It 'refuses two modules that export the same function' {
        $copy = & $script:NewRepo 'dup'
        & $script:Edit (Join-Path (Join-Path $copy 'psfdx-logs') 'psfdx-logs.psd1') { param($t) $t -replace 'FunctionsToExport\s*=\s*@\(', "FunctionsToExport = @('Invoke-Salesforce', " }
        { & $script:Build -Layout Suite -OutputFolder (Join-Path $TestDrive 'dup-out') -Root $copy } | Should -Throw '*exported by both*'
    }

    It 'refuses a wildcard export, a prerelease, a duplicate GUID and a manifest key it would drop' {
        $cases = @(
            @{ Module = 'psfdx-sandbox'; Change = { param($t) $t -replace 'FunctionsToExport\s*=\s*@\(', "FunctionsToExport = @('Get-*', " }; Message = '*wildcard*' }
            @{ Module = 'psfdx-sandbox'; Change = { param($t) $t.TrimEnd().TrimEnd('}') + "`n    PrivateData = @{ PSData = @{ Prerelease = 'beta' } }`n}`n" }; Message = '*Prerelease*' }
            @{ Module = 'psfdx-sandbox'; Change = { param($t) $t -replace "GUID\s*=\s*'[0-9a-fA-F-]+'", "GUID = '32273e30-b48e-46a0-a566-a74261704f38'" }; Message = '*GUID*' }
            @{ Module = 'psfdx-sandbox'; Change = { param($t) $t.TrimEnd().TrimEnd('}') + "`n    ScriptsToProcess = @('x.ps1')`n}`n" }; Message = '*ScriptsToProcess*' }
            @{ Module = 'psfdx-sandbox'; Change = { param($t) $t.Replace("RootModule = 'psfdx-sandbox.psm1'", "RootModule = 'other.psm1'") }; Message = '*RootModule*' }
        )
        $n = 0
        foreach ($case in $cases) {
            $n++
            $copy = & $script:NewRepo "break$n"
            & $script:Edit (Join-Path (Join-Path $copy $case.Module) "$($case.Module).psd1") $case.Change
            { & $script:Build -Layout Suite -OutputFolder (Join-Path $TestDrive "break$n-out") -Root $copy } | Should -Throw $case.Message
        }
    }

    It 'leaves the bundle layout as the default so nothing changes until the Gallery is switched over' {
        $out = Join-Path $TestDrive 'default-bundle'
        $result = @(& $script:Build -OutputFolder $out)
        $result.Count | Should -Be 1
        (Join-Path $out 'psfdx.psd1') | Should -Exist
        (Import-PowerShellDataFile -Path (Join-Path $out 'psfdx.psd1')).NestedModules.Count | Should -Be @(Get-PsfdxModules).Count
    }
}
