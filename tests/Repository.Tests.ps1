Describe 'Repository rules' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        $script:Version = (Get-Content -Path (Join-Path $script:Root 'VERSION') -Raw).Trim()
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
