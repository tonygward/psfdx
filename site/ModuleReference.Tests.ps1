# The command reference on each module page of the website is generated from the commands' own help by site/Update-ModuleReference.ps1.
# These tests fail when a page is out of date (a command, its help, or the module that exports it changed and the pages were not regenerated),
# and check that every Salesforce CLI command a page shows is a real command in the parity inventory, so the site never names a command that does not exist.
BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:Generator = Join-Path $PSScriptRoot 'Update-ModuleReference.ps1'
    . (Join-Path $script:Root 'modules.ps1')
    # Internal modules export nothing and have no page: the reference covers the public modules.
    $script:PublicModules = @(Get-PsfdxModules | Where-Object { $_ -notin @(Get-PsfdxInternalModules) })
    $script:Pages = @{}
    foreach ($module in $script:PublicModules) { $script:Pages[$module] = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $script:Root 'site') 'src') 'modules') $module) 'index.html')) }
}

Describe 'Website command reference' {
    It 'is up to date with the commands and their help in every module' {
        $stale = @(& $script:Generator -Root $script:Root -Check)
        $stale.Count | Should -Be 0 -Because "these pages are stale: $($stale -join ', '). Run: pwsh ./site/Update-ModuleReference.ps1"
    }

    It 'has no page for an internal module' {
        foreach ($internal in @(Get-PsfdxInternalModules)) {
            Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path (Join-Path $script:Root 'site') 'src') 'modules') $internal) | Should -BeFalse -Because "$internal exports nothing"
            @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root $internal) "$internal.psd1")).FunctionsToExport).Count | Should -Be 0
        }
    }

    It 'documents every command a module exports, once, on that module''s page and on no other' {
        foreach ($module in $script:PublicModules) {
            $exports = @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root $module) "$module.psd1")).FunctionsToExport)
            $exports.Count | Should -BeGreaterThan 0
            foreach ($name in $exports) {
                ([regex]::Matches($script:Pages[$module], '<details class="cmd" id="' + [regex]::Escape($name) + '">')).Count | Should -Be 1 -Because "$name is exported by $module"
                foreach ($other in $script:PublicModules) { if ($other -ne $module) { $script:Pages[$other].Contains('id="' + $name + '"') | Should -BeFalse -Because "$name belongs to $module, not $other" } }
            }
            ([regex]::Matches($script:Pages[$module], '<details class="cmd"')).Count | Should -Be $exports.Count -Because "$module's page has an entry for something it does not export"
        }
    }

    It 'gives every entry a description, syntax and a practical example with the PS> prompt' {
        foreach ($module in $script:PublicModules) {
            $entries = @([regex]::Matches($script:Pages[$module], '(?s)<details class="cmd" id="([^"]+)">(.*?)</details>'))
            foreach ($entry in $entries) {
                $name = $entry.Groups[1].Value; $body = $entry.Groups[2].Value
                $body | Should -Match '(?s)</summary><div class="cmd-body"><h4>Synopsis</h4><p class="cmd-description">[^<]+</p><h4>Syntax</h4>.*?<h4>Description</h4><p class="cmd-description">[^<]+</p>.*?<h4>Salesforce CLI</h4>.*?<h4>Related links</h4>.*?<h4>Remarks</h4>' -Because "$name needs the default help sections in order"
                $body | Should -Match '<h4>Syntax</h4><pre class="cmd-syntax"><code>' -Because "$name needs syntax"
                $body | Should -Match '<h4>Example</h4>' -Because "$name needs an example"
                $body | Should -Match 'class="ps-prompt">PS&gt;</span>' -Because "$name's example needs the PS> prompt"
                $body | Should -Match ('<pre class="cmd-syntax"><code>' + [regex]::Escape($name) + '[ <\r\n]') -Because "$name's syntax starts with the command name"
            }
        }
    }

    It 'preserves the record-count help and its inline example' {
        $entry = [regex]::Match($script:Pages['psfdx-data'], '(?s)<details class="cmd" id="Get-SalesforceSObjectRecordCount">.*?</details>').Value
        $entry | Should -Match 'Shows how many records objects have in an org\.'
        $entry | Should -Match 'approximate counts.*SOQL COUNT\(\)'
        $entry | Should -Match '<code>sf org list sobject record-counts</code>'
        $entry | Should -Match 'PS&gt;</span> Get-SalesforceSObjectRecordCount -SObject Account, Contact -TargetOrg dev1'
    }

    It 'shows only Salesforce CLI commands that exist in the parity inventory or the compatibility list' {
        $inventory = Get-Content -Path (Join-Path (Join-Path $script:Root 'docs') 'cli-parity-inventory.json') -Raw | ConvertFrom-Json
        $known = New-Object System.Collections.Generic.HashSet[string]
        foreach ($c in $inventory.commands) { [void]$known.Add([string]$c.id); foreach ($a in @($c.aliases)) { if ($a) { [void]$known.Add([string]$a) } } }
        $compat = Get-Content -Path (Join-Path (Join-Path $script:Root 'tests') 'cli-compatibility.json') -Raw | ConvertFrom-Json
        foreach ($c in @($compat.knownCommands)) { [void]$known.Add([string]$c) }
        $unknown = @()
        foreach ($module in $script:PublicModules) {
            foreach ($m in [regex]::Matches($script:Pages[$module], '(?s)<h4>Salesforce CLI</h4><div class="cmd-cli">(.*?)</div>')) {
                foreach ($code in [regex]::Matches($m.Groups[1].Value, '<code>sf ([^<]+)</code>')) {
                    $command = [System.Net.WebUtility]::HtmlDecode($code.Groups[1].Value).Trim()
                    if (-not $known.Contains($command)) { $unknown += "$module : sf $command" }
                }
            }
        }
        $unknown | Should -BeNullOrEmpty -Because 'the site must not name a command that the CLI inventory does not know'
    }

    It 'covers every sf command the parity report says psfdx runs' {
        $report = Get-Content -Path (Join-Path (Join-Path $script:Root 'docs') 'cli-parity.json') -Raw | ConvertFrom-Json
        $shown = New-Object System.Collections.Generic.HashSet[string]
        foreach ($module in $script:PublicModules) { foreach ($code in [regex]::Matches($script:Pages[$module], '<code>sf ([^<]+)</code>')) { [void]$shown.Add([System.Net.WebUtility]::HtmlDecode($code.Groups[1].Value).Trim()) } }
        $wrapped = @($report.capabilities.commands | Where-Object { $_.status -eq 'wrapped' } | ForEach-Object { [string]$_.id })
        $missing = @($wrapped | Where-Object { -not $shown.Contains($_) })
        $missing | Should -BeNullOrEmpty -Because 'every wrapped sf command should be shown on the page of the cmdlet that runs it'
    }
}
