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
        $reference = $copies['psfdx.psm1']
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
        $data = Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root 'psfdx') 'psfdx.psd1')
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

    It 'no module manifest asks for a prerelease, and every module has its own GUID' {
        # The package is published at one exact version; a prerelease string in any manifest would make the Gallery list it as a prerelease.
        $guids = @{}
        foreach ($manifest in Get-ChildItem -Path $script:Root -Directory -Filter 'psfdx*' | ForEach-Object { Join-Path $_.FullName "$($_.Name).psd1" }) {
            $data = Import-PowerShellDataFile -Path $manifest
            if ($data.PrivateData -and $data.PrivateData.PSData) { $data.PrivateData.PSData.ContainsKey('Prerelease') | Should -BeFalse -Because (Split-Path -Leaf $manifest) }
            $data.GUID | Should -Match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'
            $guids.ContainsKey($data.GUID) | Should -BeFalse -Because "$(Split-Path -Leaf $manifest) shares a GUID with $($guids[$data.GUID])"
            $guids[$data.GUID] = Split-Path -Leaf $manifest
        }
        # The core module's GUID is the Gallery identity of the package psfdx.
        $guids['2785d2bf-775f-4f2b-9d00-ee98f0163cf0'] | Should -Be 'psfdx.psd1'
    }

    It 'no workflow puts an expression in a step-level shell: (GitHub rejects the whole file; the matrix shell belongs in defaults.run)' {
        # A workflow file GitHub cannot parse starts no jobs and shows up as a failed run named after its path, so catch it here.
        foreach ($file in Get-ChildItem -Path (Join-Path (Join-Path $script:Root '.github') 'workflows') -Filter '*.yml') {
            $lines = @([System.IO.File]::ReadAllText($file.FullName) -split "`r?`n")
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\s+shell:\s*\$\{\{') {
                    $previous = if ($i -gt 0) { $lines[$i - 1] } else { '' }
                    $previous | Should -Match '^\s+run:\s*$' -Because "$($file.Name) line $($i + 1) uses an expression in a step's shell:, which GitHub does not allow; use defaults.run.shell at the job level"
                }
            }
        }
    }

    It 'the private helpers psfdx-devops copies from psfdx-metadata are identical, so the two copies cannot drift apart' {
        $text = {
            param([string] $Module)
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Join-Path $script:Root $Module) "$Module.psm1"), [ref]$null, [ref]$null)
            $found = @{}
            foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { $found[$f.Name] = $f.Extent.Text.Replace("`r`n", "`n") }
            return $found
        }
        $meta = & $text 'psfdx-metadata'
        $devops = & $text 'psfdx-devops'
        foreach ($name in 'Test-SalesforceDeployWaitParams', 'Test-SalesforceDeployResultOptions', 'Test-SalesforceValidDeployWait', 'Assert-SalesforceInteractiveSession') {
            $meta.ContainsKey($name) | Should -BeTrue -Because "psfdx-metadata defines $name"
            $devops.ContainsKey($name) | Should -BeTrue -Because "psfdx-devops copies $name"
            $devops[$name] | Should -BeExactly $meta[$name] -Because "the copy of $name in psfdx-devops must match psfdx-metadata"
        }
    }

    It 'the private helper psfdx-plugins copies from psfdx is identical, so the two copies cannot drift apart' {
        $text = {
            param([string] $Module)
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Join-Path $script:Root $Module) "$Module.psm1"), [ref]$null, [ref]$null)
            $found = @{}
            foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { $found[$f.Name] = $f.Extent.Text.Replace("`r`n", "`n") }
            return $found
        }
        $core = & $text 'psfdx'
        $plugins = & $text 'psfdx-plugins'
        foreach ($name in 'Invoke-SalesforceText') {
            $core.ContainsKey($name) | Should -BeTrue -Because "psfdx defines $name"
            $plugins.ContainsKey($name) | Should -BeTrue -Because "psfdx-plugins copies $name"
            $plugins[$name] | Should -BeExactly $core[$name] -Because "the copy of $name in psfdx-plugins must match psfdx"
        }
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

Describe 'Retired modules' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:Root 'modules.ps1')
    }

    It 'are not in the module list, have no folder and are removed by the install and uninstall scripts' {
        $retired = @(Get-PsfdxRetiredModules)
        $retired | Should -Contain 'psfdx-sandbox'
        foreach ($name in $retired) {
            @(Get-PsfdxModules) | Should -Not -Contain $name
            Test-Path -LiteralPath (Join-Path $script:Root $name) | Should -BeFalse -Because "$name was retired, so nothing may ship it"
        }
        foreach ($script in 'install.ps1', 'install-windows.ps1', 'uninstall.ps1', 'uninstall-windows.ps1') {
            [System.IO.File]::ReadAllText((Join-Path $script:Root $script)) | Should -Match 'Get-PsfdxRetiredModules' -Because "$script must clean up retired modules"
        }
    }
}
