# The command reference on each module page of the website is built from the PowerShell source by site/reference.mjs (called by site/build.mjs).
# These tests compare what it reads with what PowerShell's own parser and help reader say, so the reference cannot drift from Get-Help,
# and check that every Salesforce CLI command it shows is a real command in the parity inventory.
BeforeDiscovery {
    $script:HaveNode = [bool](Get-Command node -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:Root 'modules.ps1')
    $script:Data = $null
    if (Get-Command node -ErrorAction SilentlyContinue) {
        $json = & node (Join-Path $PSScriptRoot 'reference.mjs') --json | Out-String
        $script:Data = $json | ConvertFrom-Json
    }
    function Get-SourceFunctions([string] $Module) {
        $folder = Join-Path $script:Root $Module
        $files = if ($Module -eq 'psfdx-shared') { @(Get-ChildItem -Path $folder -Filter '*.ps1' | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object { $_.FullName }) } else { @(Join-Path $folder "$Module.psm1") }
        $result = @{}
        foreach ($file in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
            foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { $result[$f.Name] = $f }
        }
        $result
    }
}

Describe 'Website command reference' -Skip:(-not $script:HaveNode) {
    It 'has an entry for every command a module exports, once, under that module and in alphabetical order' {
        foreach ($module in Get-PsfdxModules) {
            $exports = @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root $module) "$module.psd1")).FunctionsToExport)
            $names = @($script:Data.$module | ForEach-Object { $_.name })
            ($names | Sort-Object) -join ',' | Should -Be (($exports | Sort-Object) -join ',') -Because "$module documents exactly what it exports"
            ($names -join ',') | Should -Be ((@($names | Sort-Object { $_.ToLowerInvariant() })) -join ',') -Because "$module is alphabetical"
        }
    }

    It 'agrees with the comment-based help and the parameters of every command' {
        $problems = @()
        foreach ($module in Get-PsfdxModules) {
            $functions = Get-SourceFunctions $module
            foreach ($entry in @($script:Data.$module)) {
                $fn = $functions[$entry.name]
                $help = $fn.GetHelpContent()
                if ($entry.synopsis -ne (($help.Synopsis -replace '\s+', ' ').Trim())) { $problems += "$($entry.name): synopsis differs from the help" }
                $declared = @($fn.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
                if ((@($entry.parameters | ForEach-Object { $_.name }) -join ',') -ne ($declared -join ',')) { $problems += "$($entry.name): parameters differ from the param block" }
                foreach ($p in @($entry.parameters)) {
                    $text = $help.Parameters[$p.name.ToUpperInvariant()]
                    if ($p.description -ne ((($text) -replace '\s+', ' ').Trim())) { $problems += "$($entry.name) -$($p.name): description differs from the help" }
                }
                if (@($entry.example.code).Count -eq 0) { $problems += "$($entry.name): no example" }
            }
        }
        $problems | Should -BeNullOrEmpty
    }

    It 'shows only Salesforce CLI commands that exist in the parity inventory or the compatibility list' {
        $inventory = Get-Content -Path (Join-Path (Join-Path $script:Root 'docs') 'cli-parity-inventory.json') -Raw | ConvertFrom-Json
        $known = New-Object System.Collections.Generic.HashSet[string]
        foreach ($c in $inventory.commands) { [void]$known.Add([string]$c.id); foreach ($a in @($c.aliases)) { if ($a) { [void]$known.Add([string]$a) } } }
        $compat = Get-Content -Path (Join-Path (Join-Path $script:Root 'tests') 'cli-compatibility.json') -Raw | ConvertFrom-Json
        foreach ($c in @($compat.knownCommands)) { [void]$known.Add([string]$c) }
        $unknown = @()
        foreach ($module in Get-PsfdxModules) {
            foreach ($entry in @($script:Data.$module)) {
                foreach ($cli in @($entry.cli)) {
                    $command = ([string]$cli -replace '^sf\s+', '').Trim()
                    if (-not $known.Contains($command)) { $unknown += "$($entry.name): sf $command" }
                }
            }
        }
        $unknown | Should -BeNullOrEmpty -Because 'the site must not name a command that the CLI inventory does not know'
    }

    It 'shows every sf command the parity report says psfdx runs' {
        $report = Get-Content -Path (Join-Path (Join-Path $script:Root 'docs') 'cli-parity.json') -Raw | ConvertFrom-Json
        $shown = New-Object System.Collections.Generic.HashSet[string]
        foreach ($module in Get-PsfdxModules) { foreach ($entry in @($script:Data.$module)) { foreach ($cli in @($entry.cli)) { [void]$shown.Add(([string]$cli -replace '^sf\s+', '').Trim()) } } }
        $wrapped = New-Object System.Collections.Generic.List[string]
        foreach ($capability in $report.capabilities) { foreach ($command in $capability.commands) { if (@($command.psfdx | Where-Object { $_ -and $_ -notlike '* (internal)' }).Count -gt 0) { $wrapped.Add([string]$command.id) } } }
        $missing = @($wrapped | Sort-Object -Unique | Where-Object { -not $shown.Contains($_) })
        $missing | Should -BeNullOrEmpty -Because 'every wrapped sf command should be shown on the page of the cmdlet that runs it'
    }
}
