# Repository-wide checks on the comment-based help of every exported psfdx command (issue 240).
#
# For each command exported by a module manifest, Get-Help -Full must give a real synopsis and description, a description of every parameter, at least
# one example, a visible SALESFORCE CLI section and a link. A command that the CLI parity report says runs `sf` must name every command it runs (and the
# old name or word order it is invoked by); a command the report does not list must say it does not run sf. The checks look for the command names and
# for the headings, not for exact wording. They run on Windows PowerShell 5.1 and PowerShell 7 and need no Salesforce CLI.

BeforeDiscovery {
    $root = Split-Path -Parent $PSScriptRoot
    $moduleNames = 'psfdx', 'psfdx-metadata', 'psfdx-devops', 'psfdx-data', 'psfdx-plugins', 'psfdx-development', 'psfdx-logs', 'psfdx-org', 'psfdx-packages', 'psfdx-agentforce'
    $parity = [System.IO.File]::ReadAllText((Join-Path $root 'docs/cli-parity.json')) | ConvertFrom-Json
    $runs = @{}
    foreach ($capability in $parity.capabilities) {
        foreach ($command in $capability.commands) {
            foreach ($owner in @($command.psfdx)) {
                if ($owner -like '* (internal)') { continue }
                if (-not $runs.ContainsKey($owner)) { $runs[$owner] = @() }
                $runs[$owner] += $command.id
            }
        }
    }
    $aliases = @{}
    foreach ($use in @($parity.aliasUse)) {
        if (-not $aliases.ContainsKey($use.function)) { $aliases[$use.function] = @() }
        $aliases[$use.function] += $use.alias
    }
    $cases = New-Object System.Collections.Generic.List[object]
    foreach ($module in $moduleNames) {
        $manifest = Join-Path $root (Join-Path $module ($module + '.psd1'))
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($manifest, [ref]$null, [ref]$null)
        $table = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $false)
        $exported = @()
        foreach ($pair in $table.KeyValuePairs) {
            if ($pair.Item1.Value -eq 'FunctionsToExport') { $exported = @($pair.Item2.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value }) }
        }
        foreach ($name in $exported) {
            $commands = @()
            if ($runs.ContainsKey($name)) { $commands = @($runs[$name] | Sort-Object -Unique) }
            $names = @()
            if ($aliases.ContainsKey($name)) { $names = @($aliases[$name] | Sort-Object -Unique) }
            $cases.Add(@{ Module = $module; Name = $name; CliCommands = $commands; InvokedAs = $names })
        }
    }
    # Reading no exports would turn every check below into nothing, so fail loudly.
    if ($cases.Count -lt 100) { throw "The help tests found only $($cases.Count) exported commands; the manifests were not read correctly." }
    $script:helpCases = $cases.ToArray()
}

BeforeAll {
    $script:root = Split-Path -Parent $PSScriptRoot
    Get-Module -Name 'psfdx*' -All | ForEach-Object { try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { } }
    foreach ($module in 'psfdx-shared', 'psfdx', 'psfdx-metadata', 'psfdx-devops', 'psfdx-data', 'psfdx-plugins', 'psfdx-development', 'psfdx-logs', 'psfdx-org', 'psfdx-packages', 'psfdx-agentforce') {
        Import-Module (Join-Path $script:root (Join-Path $module ($module + '.psd1'))) -Force -WarningAction SilentlyContinue
    }
    $script:common = @([System.Management.Automation.PSCmdlet]::CommonParameters) + @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
}

Describe 'Help of <Name> (<Module>)' -ForEach $script:helpCases {
    BeforeAll {
        $script:help = Get-Help -Name $Name -Full
        $script:defaultHelp = Get-Help -Name $Name | Out-String -Width 32767
        $script:mapping = (($script:help.description.Text -join [Environment]::NewLine) -split '(?m)^[ \t]*SALESFORCE CLI[ \t]*\r?$', 2)[1]
    }

    It 'has a real synopsis and a description' {
        $synopsis = ([string]$script:help.Synopsis).Trim()
        $synopsis | Should -Not -BeNullOrEmpty
        $synopsis | Should -Not -BeLike ($Name + '*') -Because 'PowerShell fills the synopsis with the syntax when a command has no help'
        (($script:help.description | Out-String).Trim()) | Should -Not -BeNullOrEmpty
    }

    It 'describes every parameter' {
        $command = Get-Command -Name $Name -Module $Module
        $missing = @()
        foreach ($parameter in $command.Parameters.Keys) {
            if ($script:common -contains $parameter) { continue }
            $entry = @($script:help.parameters.parameter | Where-Object { $_.name -eq $parameter })[0]
            if (-not $entry -or -not (($entry.description | Out-String).Trim())) { $missing += $parameter }
        }
        $missing | Should -BeNullOrEmpty -Because ('these parameters have no help: ' + ($missing -join ', '))
    }

    It 'has at least one example that is written out, not generated' {
        $written = @($script:help.examples.example | Where-Object { (($_.code | Out-String).Trim()) -and (($_.code | Out-String).Trim() -notmatch '\[<CommonParameters>\]') })
        $written.Count | Should -BeGreaterThan 0
    }

    It 'shows the Salesforce CLI section in default help and retains native help views' {
        $script:defaultHelp | Should -Match '(?ms)^NAME\s+.*?^SYNOPSIS\s+.*?^SYNTAX\s+.*?^DESCRIPTION\s+.*?^[ \t]+SALESFORCE CLI\s+.*?^RELATED LINKS\s+.*?^REMARKS\s+'
        $script:defaultHelp | Should -Not -Match '(?m)^EXAMPLES?\s*$'
        (Get-Help -Name $Name -Examples).examples.example | Should -Not -BeNullOrEmpty
        (Get-Help -Name $Name -Detailed).examples.example | Should -Not -BeNullOrEmpty
        $script:help.relatedLinks.navigationLink[0].uri | Should -Match '^https://'
    }

    It 'says which sf commands it runs, or that it runs none' {
        if ($CliCommands.Count -gt 0) {
            foreach ($command in $CliCommands) {
                $script:mapping | Should -BeLike ('*sf ' + $command + '*') -Because ('the parity report says it runs sf ' + $command)
            }
            foreach ($alias in $InvokedAs) {
                $script:mapping | Should -BeLike ('*sf ' + $alias + '*') -Because ('it is invoked as sf ' + $alias)
            }
        } else {
            $script:mapping | Should -BeLike '*does not run an sf command*'
        }
    }
}

Describe 'Help for helpers that do not run sf' {
    It 'Test-SalesforceApexTestReference says it only reads local files' {
        # An internal helper now (psfdx-shared exports nothing), so Get-Help cannot see it: read the help comment from the source.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:root (Join-Path 'psfdx-shared' 'SalesforceApexTests.ps1')), [ref]$null, [ref]$null)
        $function = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-SalesforceApexTestReference' }, $true)
        $notes = $function.GetHelpContent().Notes
        $notes | Should -BeLike '*does not run an sf command*'
        $notes | Should -Not -BeLike '*Command run: sf*'
    }

    It 'the REST and npm cmdlets say how they work instead of naming a fake sf command' {
        foreach ($name in 'Invoke-SalesforceApi', 'Connect-SalesforceApi') {
            ((Get-Help -Name $name -Full).description.Text -join " ") | Should -BeLike '*Invoke-RestMethod*'
        }
        foreach ($name in 'Install-SalesforceCli', 'Update-SalesforceCli') {
            ((Get-Help -Name $name -Full).description.Text -join " ") | Should -BeLike '*npm*'
        }
    }
}
