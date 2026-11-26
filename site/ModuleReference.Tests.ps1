# The command reference on each module page of the website is generated from the commands' own help by site/Update-ModuleReference.ps1.
# These tests fail when a page is out of date (a command, its help, or the module that exports it changed and the pages were not regenerated),
# and check that every Salesforce CLI command a page shows is a real command in the parity inventory, so the site never names a command that does not exist.
BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:Generator = Join-Path $PSScriptRoot 'Update-ModuleReference.ps1'
    . (Join-Path $script:Root 'modules.ps1')
    # Internal modules export nothing and have no page: the reference covers the public modules.
    $script:PublicModules = @(Get-PsfdxModules | Where-Object { $_ -notin @(Get-PsfdxInternalModules) })
    # The order of the sections of every command reference, on the website and in the GitHub Markdown (issue 306). Parameters is left out for a command with none.
    $script:SectionOrder = @('Synopsis', 'Syntax', 'Description', 'Parameters', 'Salesforce CLI', 'Examples', 'Remarks', 'Related Links')
    $script:Markdown = @{}
    foreach ($module in $script:PublicModules) { $script:Markdown[$module] = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $script:Root 'docs') 'reference') "$module.md")).Replace("`r`n", "`n") }
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
                $headings = [regex]::Matches($body, '<h4>([^<]+)</h4>') | ForEach-Object { $_.Groups[1].Value }
                $hasParameters = $body.Contains('<dl class="cmd-params">')
                $expected = @($script:SectionOrder | Where-Object { $hasParameters -or $_ -ne 'Parameters' })
                ($headings -join ', ') | Should -BeExactly ($expected -join ', ') -Because "$name needs the reference sections in the standard order"
                $body | Should -Match '<h4>Syntax</h4><pre class="cmd-syntax"><code>' -Because "$name needs syntax"
                $body | Should -Match '<h4>Examples</h4>' -Because "$name needs an example"
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

    It 'shows just the command name for the alias mapping' {
        $entry = [regex]::Match($script:Pages['psfdx'], '(?s)<details class="cmd" id="Add-SalesforceAlias">.*?</details>').Value
        $entry | Should -Match '<h4>Salesforce CLI</h4><div class="cmd-cli"><p><code>sf alias set</code></p></div>'
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

Describe 'GitHub Markdown command reference' {
    BeforeAll {
        # The entries of one module's Markdown: name -> the text of its sections, in order.
        $script:ParseMarkdown = {
            param([string] $Text)
            $result = [ordered]@{}
            foreach ($m in [regex]::Matches($Text, '(?ms)^### (?<name>\S+)\n(?<body>.*?)(?=^### |^## |\z)')) {
                $sections = [ordered]@{}
                foreach ($s in [regex]::Matches($m.Groups['body'].Value, '(?ms)^#### (?<title>[^\n]+)\n(?<text>.*?)(?=^#### |\z)')) { $sections[$s.Groups['title'].Value] = $s.Groups['text'].Value.Trim() }
                $result[$m.Groups['name'].Value] = $sections
            }
            return $result
        }
        $script:Decode = { param([string] $Html) [System.Net.WebUtility]::HtmlDecode(([regex]::Replace($Html, '<[^>]+>', ''))).Trim() }
    }

    It 'has a page for every public module and an index that links to each of them' {
        $index = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $script:Root 'docs') 'reference') 'README.md'))
        foreach ($module in $script:PublicModules) {
            Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $script:Root 'docs') 'reference') "$module.md") | Should -BeTrue
            $index | Should -Match ([regex]::Escape("[$module]($module.md)")) -Because "the index links $module"
        }
        foreach ($internal in @(Get-PsfdxInternalModules)) { $index | Should -Not -Match ([regex]::Escape($internal)) -Because "$internal is internal" }
    }

    It 'documents every command a module exports once, in the same order as the website' {
        foreach ($module in $script:PublicModules) {
            $names = @((& $script:ParseMarkdown $script:Markdown[$module]).Keys)
            $siteNames = @([regex]::Matches($script:Pages[$module], '<details class="cmd" id="([^"]+)">') | ForEach-Object { $_.Groups[1].Value })
            ($names -join ',') | Should -BeExactly ($siteNames -join ',') -Because "$module's Markdown and website list the same commands in the same order"
            $exports = @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root $module) "$module.psd1")).FunctionsToExport)
            @($names | Sort-Object) -join ',' | Should -BeExactly (@($exports | Sort-Object) -join ',')
        }
    }

    It 'uses exactly the standard section order for every command, with no NAME, Inputs or Outputs' {
        foreach ($module in $script:PublicModules) {
            foreach ($entry in (& $script:ParseMarkdown $script:Markdown[$module]).GetEnumerator()) {
                $titles = @($entry.Value.Keys)
                $expected = @($script:SectionOrder | Where-Object { $titles -contains 'Parameters' -or $_ -ne 'Parameters' })
                ($titles -join ', ') | Should -BeExactly ($expected -join ', ') -Because "$($entry.Key) in $module"
                foreach ($banned in 'Name', 'NAME', 'Inputs', 'INPUTS', 'Outputs', 'OUTPUTS') { $titles | Should -Not -Contain $banned }
            }
            $script:Markdown[$module] | Should -Not -Match '(?m)^#{1,6} (NAME|INPUTS|OUTPUTS|Inputs|Outputs)\s*$'
        }
    }

    It 'has the same content as the website: synopsis, parameters, Salesforce CLI command, example and links' {
        foreach ($module in $script:PublicModules) {
            $markdown = & $script:ParseMarkdown $script:Markdown[$module]
            foreach ($m in [regex]::Matches($script:Pages[$module], '(?s)<details class="cmd" id="([^"]+)">(.*?)</details>')) {
                $name = $m.Groups[1].Value; $html = $m.Groups[2].Value
                $md = $markdown[$name]
                $md | Should -Not -BeNullOrEmpty -Because "$name is in the Markdown of $module"
                # synopsis
                $siteSynopsis = & $script:Decode ([regex]::Match($html, '(?s)<h4>Synopsis</h4>(.*?)<h4>').Groups[1].Value)
                ($md['Synopsis'] -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&') | Should -BeExactly $siteSynopsis -Because "$name synopsis"
                # parameters
                $siteParameters = @([regex]::Matches($html, '<dt><code>(-[^<]+)</code>') | ForEach-Object { $_.Groups[1].Value })
                $mdParameters = @(if ($md.Contains('Parameters')) { [regex]::Matches($md['Parameters'], '(?m)^- `(-[^`]+)`') | ForEach-Object { $_.Groups[1].Value } })
                ($mdParameters -join ',') | Should -BeExactly ($siteParameters -join ',') -Because "$name parameters"
                # Salesforce CLI
                $siteCli = @([regex]::Matches(([regex]::Match($html, '(?s)<h4>Salesforce CLI</h4>(.*?)</div>').Groups[1].Value), '<code>([^<]+)</code>') | ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value) })
                $mdCli = @([regex]::Matches($md['Salesforce CLI'], '(?m)^- `([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
                ($mdCli -join ',') | Should -BeExactly ($siteCli -join ',') -Because "$name Salesforce CLI command"
                # example: the same lines
                $siteExample = @([regex]::Matches($html, '<span class="terminal-line(?: terminal-continuation)?">(.*?)</span>(?=\s*(?:<span class="terminal-line|</code>))', 'Singleline') | ForEach-Object { (& $script:Decode $_.Groups[1].Value) })
                $mdExample = @(($md['Examples'] -split '\n') | Where-Object { $_ -and $_ -notmatch '^```' } | Select-Object -First $siteExample.Count | ForEach-Object { $_.Trim() })
                ($mdExample -join "`n") | Should -BeExactly ($siteExample -join "`n") -Because "$name example"
                # related links
                $siteLinks = @([regex]::Matches(([regex]::Match($html, '(?s)<h4>Related Links</h4>(.*)$').Groups[1].Value), 'href="([^"]+)"') | ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value) })
                $mdLinks = @([regex]::Matches($md['Related Links'], '(?m)^- <([^>]+)>') | ForEach-Object { $_.Groups[1].Value })
                ($mdLinks -join ',') | Should -BeExactly ($siteLinks -join ',') -Because "$name related links"
            }
        }
    }
}
