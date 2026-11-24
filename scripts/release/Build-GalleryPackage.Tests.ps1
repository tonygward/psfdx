Describe 'Gallery package (one psfdx package that holds every module)' {
    BeforeAll {
        $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Build = Join-Path $PSScriptRoot 'Build-GalleryPackage.ps1'
        . (Join-Path $script:Root 'modules.ps1')
        $script:Version = (Get-Content -Path (Join-Path $script:Root 'VERSION') -Raw).Trim()
        $script:Out = Join-Path $TestDrive 'psfdx'
        & $script:Build -OutputFolder $script:Out | Out-Null
        $script:Manifest = Import-PowerShellDataFile -Path (Join-Path $script:Out 'psfdx.psd1')
        $script:Others = @(Get-PsfdxModules | Where-Object { $_ -ne 'psfdx' })
        $script:Exports = @{}
        foreach ($module in Get-PsfdxModules) { $script:Exports[$module] = @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root $module) "$module.psd1")).FunctionsToExport | Sort-Object) }
        $script:Shell = (Get-Process -Id $PID).Path
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
        # Runs a script in a fresh PowerShell whose module path is the folder that holds the built package, laid out as an install is (psfdx/<version>).
        $script:Install = Join-Path $TestDrive 'installed'
        New-Item -ItemType Directory -Path (Join-Path $script:Install 'psfdx') -Force | Out-Null
        Copy-Item -LiteralPath $script:Out -Destination (Join-Path (Join-Path $script:Install 'psfdx') $script:Version) -Recurse
        $script:Fresh = {
            param([string] $Script)
            $header = "`$ErrorActionPreference = 'Stop'; `$WarningPreference = 'SilentlyContinue'; `$env:PSModulePath = `$env:PSFDX_TEST_PATH; "
            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($header + $Script))
            $previous = $env:PSFDX_TEST_PATH
            $env:PSFDX_TEST_PATH = $script:Install
            $saved = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try { $text = & $script:Shell -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1 | Out-String; $code = $LASTEXITCODE }
            finally { $env:PSFDX_TEST_PATH = $previous; $ErrorActionPreference = $saved }
            return [pscustomobject]@{ ExitCode = $code; Output = $text.Trim() }
        }
    }

    It 'builds, and Test-ModuleManifest passes on the package' {
        { Test-ModuleManifest -Path (Join-Path $script:Out 'psfdx.psd1') -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null } | Should -Not -Throw
    }

    It 'is one package: the core module is the root module, with the version in VERSION and the Gallery identity, and nothing nested or required' {
        $script:Manifest.RootModule | Should -Be 'psfdx.psm1'
        $script:Manifest.ModuleVersion | Should -Be $script:Version
        $script:Manifest.GUID | Should -Be '2785d2bf-775f-4f2b-9d00-ee98f0163cf0'
        $script:Manifest.ContainsKey('NestedModules') | Should -BeFalse
        @($script:Manifest.RequiredModules | Where-Object { $_ }).Count | Should -Be 0
        @(Get-ChildItem -Path $script:Out -File | ForEach-Object Name | Sort-Object) | Should -Be @('LICENSE', 'psfdx.psd1', 'psfdx.psm1')
    }

    It 'exports only the core commands, by explicit name, so Get-Command -Module psfdx shows the core and nothing else' {
        @($script:Manifest.FunctionsToExport | Sort-Object) | Should -Be $script:Exports['psfdx']
        @($script:Manifest.FunctionsToExport | Where-Object { $_ -match '[*?]' }).Count | Should -Be 0
        foreach ($module in $script:Others) {
            foreach ($function in $script:Exports[$module]) { $script:Manifest.FunctionsToExport | Should -Not -Contain $function -Because "$function belongs to $module" }
        }
    }

    It 'holds every other module in a folder of its own, with its own manifest and exports, and without tests' {
        foreach ($module in $script:Others) {
            $manifest = Join-Path (Join-Path $script:Out $module) "$module.psd1"
            $manifest | Should -Exist
            $data = Import-PowerShellDataFile -Path $manifest
            @($data.FunctionsToExport | Sort-Object) | Should -Be $script:Exports[$module] -Because $module
            $data.ModuleVersion | Should -Be $script:Version -Because $module
            @(@($data.RequiredModules) | Where-Object { $_ }).Count | Should -Be 0 -Because "$module must not require psfdx, which is the module loading it"
        }
        @(Get-ChildItem -Path $script:Out -Recurse -Filter '*.Tests.ps1').Count | Should -Be 0
        @(Get-ChildItem -Path $script:Out -Directory | ForEach-Object Name | Sort-Object) | Should -Be @($script:Others | Sort-Object)
    }

    It 'gives every module a different GUID, and no function is exported twice across the suite' {
        $guids = @(Get-PsfdxModules | ForEach-Object { (Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root $_) "$_.psd1")).GUID })
        @($guids | Select-Object -Unique).Count | Should -Be $guids.Count
        $all = @(Get-PsfdxModules | ForEach-Object { $script:Exports[$_] })
        @($all | Select-Object -Unique).Count | Should -Be $all.Count
    }

    It 'carries the Gallery metadata, a release notes link and the licence' {
        $data = $script:Manifest.PrivateData.PSData
        $data.Tags | Should -Contain 'Salesforce'
        $data.Tags | Should -Contain 'PSEdition_Desktop'
        $data.Tags | Should -Contain 'PSEdition_Core'
        $data.ProjectUri | Should -Be 'https://github.com/tonygward/psfdx'
        $data.LicenseUri | Should -Be 'https://github.com/tonygward/psfdx/blob/main/LICENSE'
        $data.IconUri | Should -Match 'images/psfdx-logo\.png$'
        $data.ReleaseNotes | Should -Be "https://github.com/tonygward/psfdx/releases/tag/v$script:Version"
        $data.ContainsKey('Prerelease') | Should -BeFalse
        (Get-Content -Path (Join-Path $script:Out 'LICENSE') -Raw) | Should -Be (Get-Content -Path (Join-Path $script:Root 'LICENSE') -Raw)
    }

    It 'adds only a start and a loader to the core module: the repository code is inside it unchanged' {
        $built = [System.IO.File]::ReadAllText((Join-Path $script:Out 'psfdx.psm1')).Replace("`r`n", "`n")
        $source = [System.IO.File]::ReadAllText((Join-Path (Join-Path $script:Root 'psfdx') 'psfdx.psm1')).Replace("`r`n", "`n").TrimEnd()
        $built.Contains($source) | Should -BeTrue
        $built | Should -Match '(?s)\A# psfdx Gallery package\..*?Import-Module \(Join-Path \$PSScriptRoot ''psfdx-shared\\psfdx-shared\.psd1''\) -Global'
        $built | Should -Match '#region psfdx Gallery package: the other modules of the suite'
    }

    It 'loads the shared helpers first, then the other modules in the order modules.ps1 lists them' {
        $built = [System.IO.File]::ReadAllText((Join-Path $script:Out 'psfdx.psm1'))
        $expected = @('psfdx-shared') + @($script:Others | Where-Object { $_ -ne 'psfdx-shared' })
        $match = [regex]::Match($built, '\$psfdxSuiteModules = @\((.*?)\)')
        $match.Success | Should -BeTrue
        @($match.Groups[1].Value -split ',' | ForEach-Object { $_.Trim().Trim("'") }) | Should -Be $expected
    }

    It 'gives every module its own identity once psfdx loads: Get-Command -Module psfdx stays core only, and nothing is defined twice' {
        $run = & $script:Fresh @'
Import-Module psfdx
$core = @(Get-Command -Module psfdx)
$logs = @(Get-Command -Module psfdx-logs)
$all = @(Get-Command -Module 'psfdx*' | Where-Object { $_.CommandType -eq 'Function' })
$dups = @($all | Group-Object Name | Where-Object { $_.Count -gt 1 })
"core=$($core.Count) coreSources=$(@($core | Group-Object Source | ForEach-Object Name) -join ',') logs=$($logs.Count) logsSources=$(@($logs | Group-Object Source | ForEach-Object Name) -join ',') all=$($all.Count) dups=$($dups.Count) loaded=$(@(Get-Module 'psfdx*' | ForEach-Object Name | Sort-Object) -join ',')"
'@
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $total = 0; foreach ($module in Get-PsfdxModules) { $total += $script:Exports[$module].Count }
        $run.Output | Should -BeLike "core=$($script:Exports['psfdx'].Count) coreSources=psfdx logs=$($script:Exports['psfdx-logs'].Count) logsSources=psfdx-logs all=$total dups=0 loaded=*"
    }

    It 'loads the whole suite on the first use of a core command with no import, and in one fresh session answers the three Get-Command questions in order' {
        $run = & $script:Fresh @'
$a = @(Get-Command -Module psfdx)
$b = @(Get-Command -Module psfdx-logs)
$c = @(Get-Command -Module 'psfdx*')
"$($a.Count) $($b.Count) $($c.Count)"
'@
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $total = 0; foreach ($module in Get-PsfdxModules) { $total += $script:Exports[$module].Count }
        $run.Output | Should -Be "$($script:Exports['psfdx'].Count) $($script:Exports['psfdx-logs'].Count) $total"
        $first = & $script:Fresh "`$null = Get-SalesforceDateTime; (Get-Module 'psfdx*' | ForEach-Object Name | Sort-Object) -join ','"
        $first.Output | Should -Be ((Get-PsfdxModules | Sort-Object) -join ',')
    }

    It 'removes the other modules again when psfdx is removed' {
        $run = & $script:Fresh "Import-Module psfdx; Remove-Module psfdx; @(Get-Module 'psfdx*').Count"
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Be '0'
    }

    It 'refuses two modules that export the same function' {
        $copy = & $script:NewRepo 'dup'
        & $script:Edit (Join-Path (Join-Path $copy 'psfdx-logs') 'psfdx-logs.psd1') { param($t) $t -replace 'FunctionsToExport\s*=\s*@\(', "FunctionsToExport = @('Connect-Salesforce', " }
        { & $script:Build -OutputFolder (Join-Path $TestDrive 'dup-out') -Root $copy } | Should -Throw '*exported by both*'
    }

    It 'refuses version drift, a wildcard export, a prerelease, a shared GUID, a manifest key it would drop and a wrong RootModule' {
        $cases = @(
            @{ Change = { param($t) $t -replace "ModuleVersion = '[0-9.]+'", "ModuleVersion = '9.9.9'" }; Message = '*psfdx-org is 9.9.9*' }
            @{ Change = { param($t) $t -replace 'FunctionsToExport\s*=\s*@\(', "FunctionsToExport = @('Get-*', " }; Message = '*wildcard*' }
            @{ Change = { param($t) $t.TrimEnd().TrimEnd('}') + "`n    PrivateData = @{ PSData = @{ Prerelease = 'beta' } }`n}`n" }; Message = '*Prerelease*' }
            @{ Change = { param($t) $t -replace "GUID\s*=\s*'[0-9a-fA-F-]+'", "GUID = '32273e30-b48e-46a0-a566-a74261704f38'" }; Message = '*GUID*' }
            @{ Change = { param($t) $t.TrimEnd().TrimEnd('}') + "`n    ScriptsToProcess = @('x.ps1')`n}`n" }; Message = '*ScriptsToProcess*' }
            @{ Change = { param($t) $t.Replace("RootModule = 'psfdx-org.psm1'", "RootModule = 'other.psm1'") }; Message = '*RootModule*' }
        )
        $n = 0
        foreach ($case in $cases) {
            $n++
            $copy = & $script:NewRepo "break$n"
            & $script:Edit (Join-Path (Join-Path $copy 'psfdx-org') 'psfdx-org.psd1') $case.Change
            { & $script:Build -OutputFolder (Join-Path $TestDrive "break$n-out") -Root $copy } | Should -Throw $case.Message
        }
    }

    It 'refuses a core module whose GUID is not the Gallery identity, because that GUID is what keeps the package psfdx' {
        $copy = & $script:NewRepo 'coreguid'
        & $script:Edit (Join-Path (Join-Path $copy 'psfdx') 'psfdx.psd1') { param($t) $t -replace "GUID\s*=\s*'[0-9a-fA-F-]+'", "GUID = '11111111-1111-1111-1111-111111111111'" }
        { & $script:Build -OutputFolder (Join-Path $TestDrive 'coreguid-out') -Root $copy } | Should -Throw '*Gallery identity*'
    }
}
