Describe 'Repository rules' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        $script:Version = (Get-Content -Path (Join-Path $script:Root 'VERSION') -Raw).Trim()
    }

    It 'every module carries an identical copy of Import-PsfdxSharedModule' {
        $copies = @{}
        foreach ($file in Get-ChildItem -Path $script:Root -Directory -Filter 'psfdx*' | ForEach-Object { Get-ChildItem -Path $_.FullName -Filter '*.psm1' }) {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            $match = [regex]::Match($text, '(?s)function Import-PsfdxSharedModule \{.*?\r?\n\}\r?\n\r?\nImport-PsfdxSharedModule')
            if ($match.Success) { $copies[$file.Name] = $match.Value.Replace("`r`n", "`n") }
        }
        $copies.Count | Should -BeGreaterThan 6
        $reference = $copies['psfdx-core.psm1']
        $different = @($copies.Keys | Where-Object { $copies[$_] -cne $reference })
        $different | Should -BeNullOrEmpty
    }

    It 'VERSION is three numeric parts' {
        $script:Version | Should -Match '^\d+\.\d+\.\d+$'
    }

    It 'every manifest ModuleVersion matches VERSION' {
        $manifests = Get-ChildItem -Path $script:Root -Filter 'psfdx*.psd1' -Recurse
        $manifests.Count | Should -BeGreaterThan 0
        foreach ($manifest in $manifests) {
            $data = Import-PowerShellDataFile -Path $manifest.FullName
            "$($manifest.Name) $($data.ModuleVersion)" | Should -Be "$($manifest.Name) $script:Version"
        }
    }

    It 'the core manifest sets LicenseUri to the repository LICENSE file' {
        $data = Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root 'psfdx-core') 'psfdx-core.psd1')
        $data.PrivateData.PSData.LicenseUri | Should -Be 'https://github.com/tonygward/psfdx/blob/main/LICENSE'
    }

    It 'every module manifest declares PowerShell 5.1 and both editions' {
        $manifests = Get-ChildItem -Path $script:Root -Filter 'psfdx*.psd1' -Recurse
        $manifests.Count | Should -BeGreaterThan 0
        foreach ($manifest in $manifests) {
            $data = Import-PowerShellDataFile -Path $manifest.FullName
            "$($manifest.Name) $($data.PowerShellVersion)" | Should -Be "$($manifest.Name) 5.1"
            "$($manifest.Name) $((@($data.CompatiblePSEditions) | Sort-Object) -join ',')" | Should -Be "$($manifest.Name) Core,Desktop"
        }
    }

    It 'the dependency map in modules.ps1 is exactly what each module'' code calls in the other modules' {
        # The Gallery packages require what this map says (scripts/release/Build-GalleryPackage.ps1), so a module that calls another module's
        # command without listing it would install fine and then fail at run time, and a module that lists a module it never calls would drag it in.
        . (Join-Path $script:Root 'modules.ps1')
        $map = Get-PsfdxModuleDependencies
        $exports = @{}
        foreach ($module in Get-PsfdxModules) { $exports[$module] = @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root $module) "$module.psd1")).FunctionsToExport) }
        @($map.Keys | Sort-Object) | Should -Be @(Get-PsfdxModules | Sort-Object)
        foreach ($module in Get-PsfdxModules) {
            $parse = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Join-Path $script:Root $module) "$module.psm1"), [ref]$parse, [ref]$null)
            $called = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Select-Object -Unique)
            $actual = @(Get-PsfdxModules | Where-Object { $_ -ne $module -and @($exports[$_] | Where-Object { $called -contains $_ }).Count -gt 0 } | Sort-Object)
            "$module needs [$($actual -join ', ')]" | Should -Be "$module needs [$(@($map[$module] | Sort-Object) -join ', ')]"
        }
    }

    It 'no module depends on itself or on a module that depends on it' {
        . (Join-Path $script:Root 'modules.ps1')
        $map = Get-PsfdxModuleDependencies
        $reach = {
            param($start)
            $seen = New-Object System.Collections.Generic.HashSet[string]
            $queue = New-Object System.Collections.Generic.Queue[string]
            foreach ($d in @($map[$start])) { $queue.Enqueue($d) }
            while ($queue.Count -gt 0) { $n = $queue.Dequeue(); if ($seen.Add($n)) { foreach ($d in @($map[$n])) { $queue.Enqueue($d) } } }
            return @($seen)
        }
        foreach ($module in $map.Keys) { @(& $reach $module) | Should -Not -Contain $module -Because "$module would depend on itself" }
    }

    It 'no module manifest asks for a prerelease, and every module has its own GUID' {
        $guids = @{}
        foreach ($manifest in Get-ChildItem -Path $script:Root -Directory -Filter 'psfdx*' | ForEach-Object { Join-Path $_.FullName "$($_.Name).psd1" }) {
            $data = Import-PowerShellDataFile -Path $manifest
            if ($data.PrivateData -and $data.PrivateData.PSData) { $data.PrivateData.PSData.ContainsKey('Prerelease') | Should -BeFalse -Because (Split-Path -Leaf $manifest) }
            $data.GUID | Should -Match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'
            $guids.ContainsKey($data.GUID) | Should -BeFalse -Because "$(Split-Path -Leaf $manifest) shares a GUID with $($guids[$data.GUID])"
            $guids[$data.GUID] = Split-Path -Leaf $manifest
        }
        # The name psfdx now belongs to the umbrella package, whose GUID is the Gallery identity.
        $guids.ContainsKey('2785d2bf-775f-4f2b-9d00-ee98f0163cf0') | Should -BeFalse
    }

    It 'no repository folder is called psfdx: that name is the umbrella package, built for the Gallery' {
        (Join-Path $script:Root 'psfdx') | Should -Not -Exist
    }

    It 'LICENSE is the MIT licence' {
        $text = Get-Content -Path (Join-Path $script:Root 'LICENSE') -Raw
        $text | Should -Match '^MIT License'
        $text | Should -Match 'Copyright \(c\) [0-9]{4} Tony Ward'
    }

    It 'CHANGELOG.md starts with # Changelog then ## Unreleased' {
        $lines = @(Get-Content -Path (Join-Path $script:Root 'CHANGELOG.md') | Where-Object { $_.Trim() -ne '' })
        $lines[0] | Should -Be '# Changelog'
        $lines[1] | Should -Be '## Unreleased'
    }

    It 'every workflow name starts with a known prefix' {
        $workflows = Get-ChildItem -Path (Join-Path (Join-Path $script:Root '.github') 'workflows') -Filter '*.yml'
        foreach ($workflow in $workflows) {
            $nameLine = Get-Content -Path $workflow.FullName | Where-Object { $_ -match '^name:' } | Select-Object -First 1
            $nameLine | Should -Match '^name:\s*(CI|Gate|CD|Housekeeping) - ' -Because $workflow.Name
        }
    }

    It 'prompts have no status, execution or model front matter' {
        $prompts = Get-ChildItem -Path (Join-Path $script:Root 'prompts') -Filter '*.md' -File
        foreach ($prompt in $prompts) {
            $lines = @(Get-Content -Path $prompt.FullName)
            if ($lines.Count -gt 0 -and $lines[0].Trim() -eq '---') {
                for ($i = 1; $i -lt $lines.Count; $i++) {
                    if ($lines[$i].Trim() -eq '---') { break }
                    $lines[$i] | Should -Not -Match '^(status|execution|model):' -Because $prompt.Name
                }
            }
        }
    }
}
