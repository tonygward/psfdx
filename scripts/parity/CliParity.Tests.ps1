# Pester tests for the Salesforce CLI to psfdx parity report (issue 205). They use small fixtures built in $TestDrive and the
# committed inventory; none needs the Salesforce CLI, an org or credentials. They run on Windows PowerShell 5.1 and PowerShell 7.

BeforeAll {
    . (Join-Path $PSScriptRoot 'CliParity.ps1')
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    # Builds a tiny repository: one module with a manifest, a source file, a test file and a private helper.
    function New-ParityFixtureRepo {
        param([string] $Path)
        $module = Join-Path $Path 'psfdx-demo'
        New-Item -ItemType Directory -Path $module -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $module 'psfdx-demo.psd1') -Encoding utf8 -Value @'
@{
    ModuleVersion = '1.0.0'
    FunctionsToExport = @(
        'Get-DemoOrg',
        'Get-DemoThing',
        'Invoke-DemoDeploy',
        'Get-DemoConvenience',
        'Get-DemoViaHelper',
        'Install-DemoPlugin'
    )
    PrivateData = @{ PSData = @{ Tags = @('x') } }
}
'@
        Set-Content -LiteralPath (Join-Path $module 'psfdx-demo.psm1') -Encoding utf8 -Value @'
function Get-DemoOrg {
    [CmdletBinding()]
    Param([string] $TargetOrg)
    $arguments = @('org', 'list', '--all')
    if ($TargetOrg) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments
}
function Get-DemoThing {
    [CmdletBinding()]
    Param()
    $arguments = @('thing', 'show')
    $arguments += @('--name', 'x')
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments
}
function Invoke-DemoDeploy {
    [CmdletBinding()]
    Param([switch] $Resume)
    $arguments = @('deploy', 'start', '--wait')
    if ($Resume) { $arguments = @('deploy', 'resume', '--job-id', 'x') }
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments
}
function Get-DemoConvenience {
    [CmdletBinding()]
    Param()
    Get-DemoOrg
}
function Get-DemoViaHelper {
    [CmdletBinding()]
    Param()
    $words = Get-DemoHelperFlags
    Invoke-Salesforce -FilePath 'sf' -Arguments @('helper', 'run') + $words
}
function Get-DemoHelperFlags {
    return @('--from-helper')
}
function Install-DemoPlugin {
    [CmdletBinding()]
    Param()
    Invoke-Salesforce -FilePath 'npm' -Arguments @('install', '--global', 'thing')
    Invoke-Salesforce -FilePath 'sf' -Arguments @('plugins', '--core')
    $arguments = @('apex', 'log', 'list')
    $arguments = @('limits', 'api', 'display')
    $arguments = @('lightning', 'dev')
    $arguments = @('gone', 'command')
}
'@
        Set-Content -LiteralPath (Join-Path $module 'psfdx-demo.Tests.ps1') -Encoding utf8 -Value "`$arguments = @('should', 'be', 'ignored')"
    }

    # True when the parts appear in the text in this order (text compared as written, no wildcards).
    function Test-InOrder {
        param([string] $Text, [string[]] $Parts)
        $pattern = '(?s)' + (($Parts | ForEach-Object { [regex]::Escape($_) }) -join '.*')
        return [bool]($Text -match $pattern)
    }

    function New-ParityCommand {
        param([string] $Id, [string[]] $Flags = @(), [string] $PluginType = 'core', [string] $State = 'ga', [string[]] $Aliases = @(), [bool] $DeprecatedAliases = $false)
        [pscustomobject]@{ id = $Id; plugin = '@salesforce/plugin-demo'; pluginType = $PluginType; state = $State; hidden = $false; aliases = $Aliases; deprecatedAliases = $DeprecatedAliases
            summary = "Summary of $Id."; flags = @($Flags | ForEach-Object { [pscustomobject]@{ name = $_; required = $false } }) }
    }

    function New-ParityInventoryFixture {
        $commands = @(
            (New-ParityCommand -Id 'org list' -Flags @('all', 'target-org', 'json', 'flags-dir', 'api-version'))
            (New-ParityCommand -Id 'thing show' -Flags @('name', 'extra', 'json'))
            (New-ParityCommand -Id 'deploy start' -Flags @('wait', 'json'))
            (New-ParityCommand -Id 'deploy resume' -Flags @('job-id', 'use-most-recent'))
            (New-ParityCommand -Id 'helper run' -Flags @('from-helper'))
            (New-ParityCommand -Id 'plugins' -Flags @('core'))
            (New-ParityCommand -Id 'apex list log' -Flags @('target-org') -Aliases @())
            (New-ParityCommand -Id 'org list limits' -Flags @('target-org') -Aliases @('limits api display') -DeprecatedAliases $true)
            (New-ParityCommand -Id 'lightning dev app' -Flags @('name'))
            (New-ParityCommand -Id 'lightning dev site' -Flags @('name'))
            (New-ParityCommand -Id 'unused one' -Flags @('x'))
            (New-ParityCommand -Id 'unused two' -Flags @('x') -State 'beta')
            (New-ParityCommand -Id 'legacy thing' -Flags @())
            (New-ParityCommand -Id 'jit tool' -Flags @('x') -PluginType 'jit')
            (New-ParityCommand -Id 'excluded topic one' -Flags @())
            (New-ParityCommand -Id 'excluded topic two' -Flags @())
        )
        [pscustomobject]@{ schema = 1; cliVersion = '9.9.9'; plugins = @(); commands = $commands }
    }

    function New-ParityMappingFixture {
        param([object[]] $Rules = @())
        [pscustomobject]@{ schema = 1; scope = 'Demo scope.'; capabilities = [pscustomobject]@{ org = 'Orgs' }; rules = $Rules }
    }
}

Describe 'ConvertTo-ParityInventory' {
    It 'turns sf commands output into a sorted, compact inventory' {
        $raw = @(
            [pscustomobject]@{ id = 'org:list'; pluginName = '@salesforce/plugin-org'; pluginType = 'core'; summary = ' List orgs. '; aliases = @('force:org:list'); deprecateAliases = $true
                flags = [pscustomobject]@{
                    'target-org' = [pscustomobject]@{ required = $false }
                    'all'        = [pscustomobject]@{ required = $true }
                    'secret'     = [pscustomobject]@{ hidden = $true }
                } }
            [pscustomobject]@{ id = 'agent:activate'; pluginName = '@salesforce/plugin-agent'; pluginType = 'jit'; state = 'beta'; summary = 'Activate.'; flags = [pscustomobject]@{} }
        )
        $inventory = ConvertTo-ParityInventory -Commands $raw -CliVersion '2.0.0'
        $inventory.schema | Should -Be 1
        $inventory.cliVersion | Should -Be '2.0.0'
        @($inventory.commands | ForEach-Object { $_.id }) | Should -Be @('agent activate', 'org list')
        $org = $inventory.commands | Where-Object { $_.id -eq 'org list' }
        $org.summary | Should -Be 'List orgs.'
        $org.state | Should -Be 'ga'
        $org.deprecatedAliases | Should -BeTrue
        @($org.aliases) | Should -Be @('force org list')
        @($org.flags | ForEach-Object { $_.name }) | Should -Be @('all', 'target-org')
        ($org.flags | Where-Object { $_.name -eq 'all' }).required | Should -BeTrue
        ($inventory.commands | Where-Object { $_.id -eq 'agent activate' }).state | Should -Be 'beta'
        @($inventory.plugins | ForEach-Object { $_.name }) | Should -Be @('@salesforce/plugin-agent', '@salesforce/plugin-org')
    }
}

Describe 'Get-ParityPsfdxScan' {
    BeforeAll {
        New-ParityFixtureRepo -Path $TestDrive
        $script:scan = Get-ParityPsfdxScan -Root $TestDrive
        $script:refs = @($script:scan.References)
    }

    It 'finds the functions of a module and which of them are exported' {
        $byName = @{}
        foreach ($f in $script:scan.Functions) { $byName[$f.Name] = $f }
        $byName['Get-DemoOrg'].Exported | Should -BeTrue
        $byName['Get-DemoOrg'].Module | Should -Be 'psfdx-demo'
        $byName['Get-DemoHelperFlags'].Exported | Should -BeFalse
    }

    It 'reads the command words of structured argv, up to the first flag or variable' {
        ($script:refs | Where-Object { $_.Function -eq 'Get-DemoOrg' }).Words -join ' ' | Should -Be 'org list'
        ($script:refs | Where-Object { $_.Function -eq 'Get-DemoThing' }).Words -join ' ' | Should -Be 'thing show'
    }

    It 'reads several commands from one function and an inline Invoke-Salesforce call' {
        @($script:refs | Where-Object { $_.Function -eq 'Invoke-DemoDeploy' } | ForEach-Object { $_.Words -join ' ' } | Sort-Object) | Should -Be @('deploy resume', 'deploy start')
        @($script:refs | Where-Object { $_.Function -eq 'Install-DemoPlugin' } | ForEach-Object { $_.Words -join ' ' }) | Should -Contain 'plugins'
    }

    It 'ignores other programs and test files' {
        @($script:refs | ForEach-Object { $_.Words -join ' ' }) | Should -Not -Contain 'install --global thing'
        @($script:refs | ForEach-Object { $_.Words -join ' ' }) | Should -Not -Contain 'should be ignored'
    }

    It 'records the flags each function passes, and the helpers it calls' {
        $byName = @{}
        foreach ($f in $script:scan.Functions) { $byName[$f.Name] = $f }
        @($byName['Get-DemoOrg'].Flags) | Should -Be @('all', 'json', 'target-org')
        @($byName['Get-DemoViaHelper'].Calls) | Should -Contain 'Get-DemoHelperFlags'
        @($byName['Get-DemoHelperFlags'].Flags) | Should -Be @('from-helper')
    }
}

Describe 'New-ParityReport' {
    BeforeAll {
        New-ParityFixtureRepo -Path $TestDrive
        $script:scan = Get-ParityPsfdxScan -Root $TestDrive
        $rules = @(
            [pscustomobject]@{ match = 'unused one'; status = 'deliberately excluded'; reason = 'Out of scope on purpose.'; issue = 99 }
            [pscustomobject]@{ match = 'excluded topic *'; status = 'not applicable'; reason = 'Not for a module.' }
            [pscustomobject]@{ match = 'excluded topic two'; status = 'deliberately excluded'; reason = 'Exact rule beats the topic rule.' }
            [pscustomobject]@{ match = 'thing show'; status = 'partially wrapped'; reason = 'Accepted: one flag is left out.' }
            [pscustomobject]@{ match = 'deploy start'; status = 'deliberately excluded'; reason = 'Wrongly says excluded.' }
            [pscustomobject]@{ match = 'unused two'; status = 'wrapped'; reason = 'Wrongly says wrapped.' }
            [pscustomobject]@{ match = 'gone command'; status = 'missing'; reason = 'No longer in the CLI.' }
        )
        $script:report = New-ParityReport -Inventory (New-ParityInventoryFixture) -Scan $script:scan -Mapping (New-ParityMappingFixture -Rules $rules)
        $script:rows = @{}
        foreach ($cap in $script:report.capabilities) { foreach ($c in $cap.commands) { $script:rows[$c.id] = $c } }
    }

    It 'classifies a command whose every flag is passed as wrapped, ignoring json, flags-dir and api-version' {
        $script:rows['org list'].status | Should -Be 'wrapped'
        @($script:rows['org list'].uncoveredFlags).Count | Should -Be 0
        @($script:rows['org list'].psfdx) | Should -Be @('Get-DemoOrg')
    }

    It 'counts flags built by a helper that the owner calls' {
        $script:rows['helper run'].status | Should -Be 'wrapped'
    }

    It 'classifies a command with flags left out as partially wrapped and lists them' {
        @($script:rows['deploy start'].uncoveredFlags).Count | Should -Be 0
        @($script:rows['deploy resume'].uncoveredFlags) | Should -Be @('use-most-recent')
        $script:rows['deploy resume'].status | Should -Be 'partially wrapped'
    }

    It 'lets a reviewed rule accept a command that is partial by flags' {
        @($script:rows['thing show'].uncoveredFlags) | Should -Be @('extra')
        $script:rows['thing show'].status | Should -Be 'partially wrapped'
        $script:rows['thing show'].reason | Should -Be 'Accepted: one flag is left out.'
    }

    It 'treats a command nobody runs and nobody mapped as missing, and keeps the state' {
        $script:rows['unused two'].status | Should -Be 'missing'
        $script:rows['unused two'].state | Should -Be 'beta'
        $script:rows['unused two'].reason | Should -BeNullOrEmpty
    }

    It 'uses the mapping for excluded and not applicable commands, with reason and issue' {
        $script:rows['unused one'].status | Should -Be 'deliberately excluded'
        $script:rows['unused one'].reason | Should -Be 'Out of scope on purpose.'
        $script:rows['unused one'].issue | Should -Be 99
        $script:rows['excluded topic one'].status | Should -Be 'not applicable'
    }

    It 'lets an exact rule beat a topic rule' {
        $script:rows['excluded topic two'].status | Should -Be 'deliberately excluded'
        $script:rows['excluded topic two'].reason | Should -Be 'Exact rule beats the topic rule.'
    }

    It 'resolves an old name and a different word order to the current command, and marks both' {
        @($script:rows['org list limits'].psfdx) | Should -Be @('Install-DemoPlugin')
        @($script:rows['apex list log'].psfdx) | Should -Be @('Install-DemoPlugin')
        $uses = @($script:report.aliasUse)
        ($uses | Where-Object { $_.alias -eq 'limits api display' }).kind | Should -Be 'alias'
        ($uses | Where-Object { $_.alias -eq 'limits api display' }).deprecated | Should -BeTrue
        ($uses | Where-Object { $_.alias -eq 'apex log list' }).kind | Should -Be 'word order'
        ($uses | Where-Object { $_.alias -eq 'apex log list' }).command | Should -Be 'apex list log'
    }

    It 'counts a topic reference for every subcommand under it' {
        @($script:rows['lightning dev app'].psfdx) | Should -Be @('Install-DemoPlugin')
        @($script:rows['lightning dev site'].psfdx) | Should -Be @('Install-DemoPlugin')
    }

    It 'reports a reference that matches no command' {
        $u = @($script:report.unresolved)
        $u.Count | Should -Be 1
        $u[0].words | Should -Be 'gone command'
        $u[0].function | Should -Be 'Install-DemoPlugin'
    }

    It 'shows one function running several commands, and several functions running one command' {
        @($script:rows['deploy start'].psfdx) | Should -Be @('Invoke-DemoDeploy')
        @($script:rows['deploy resume'].psfdx) | Should -Be @('Invoke-DemoDeploy')
        @($script:rows['org list'].psfdx).Count | Should -Be 1
    }

    It 'does not count a cmdlet that only calls another cmdlet as running the CLI' {
        @($script:report.psfdx.withoutADirectCliCommand) | Should -Be @('Get-DemoConvenience')
        $script:report.psfdx.exportedFunctions | Should -Be 6
        $script:report.psfdx.runningTheCli | Should -Be 5
    }

    It 'warns when the mapping contradicts what psfdx does or names a command that is gone' {
        $w = @($script:report.warnings) -join "`n"
        $w | Should -BeLike "*'deploy start' is mapped 'deliberately excluded' but psfdx runs it*"
        $w | Should -BeLike "*'unused two' is mapped 'wrapped' but no psfdx function runs it*"
        $w | Should -BeLike "*rule 'gone command' matches no command*"
    }

    It 'totals each plugin set separately and gives no unqualified percentage' {
        $core = $script:report.totals.core
        $jit = $script:report.totals.jit
        $jit.commands | Should -Be 1
        $jit.missing | Should -Be 1
        $jit.coveredPercent | Should -Be '0.0'
        ($core.commands + $jit.commands) | Should -Be $script:report.totals.all.commands
        $core.inScope | Should -Be ($core.commands - $core.excluded - $core.notApplicable)
        $script:report.scope | Should -Be 'Demo scope.'
        $script:report.cli.version | Should -Be '9.9.9'
    }

    It 'groups by capability with the label from the mapping, or the topic name' {
        $labels = @{}
        foreach ($cap in $script:report.capabilities) { $labels[$cap.topic] = $cap.label }
        $labels['org'] | Should -Be 'Orgs'
        $labels['thing'] | Should -Be 'thing'
        @($script:report.capabilities | ForEach-Object { $_.topic }) | Should -Be @($script:report.capabilities | ForEach-Object { $_.topic } | Sort-Object { $_ } -CaseSensitive)
    }

    It 'is the same every time for the same inputs' {
        $again = New-ParityReport -Inventory (New-ParityInventoryFixture) -Scan $script:scan -Mapping (New-ParityMappingFixture -Rules @(
                [pscustomobject]@{ match = 'unused one'; status = 'deliberately excluded'; reason = 'Out of scope on purpose.'; issue = 99 }))
        $first = New-ParityReport -Inventory (New-ParityInventoryFixture) -Scan $script:scan -Mapping (New-ParityMappingFixture -Rules @(
                [pscustomobject]@{ match = 'unused one'; status = 'deliberately excluded'; reason = 'Out of scope on purpose.'; issue = 99 }))
        ($again | ConvertTo-Json -Depth 12) | Should -Be ($first | ConvertTo-Json -Depth 12)
    }
}

Describe 'Read-ParityMapping' {
    BeforeAll {
        function Write-Mapping { param([string] $Json) $p = Join-Path $TestDrive ('m-' + [guid]::NewGuid().ToString('N') + '.json'); Set-Content -LiteralPath $p -Value $Json -Encoding utf8; $p }
        $script:header = '"schema": 1, "scope": "s", "capabilities": { "org": "Orgs" }'
    }

    It 'accepts a valid mapping' {
        $path = Write-Mapping -Json ('{ ' + $script:header + ', "rules": [ { "match": "a *", "status": "not applicable", "reason": "r" }, { "match": "b", "status": "missing", "issue": 12 } ] }')
        (Read-ParityMapping -Path $path).rules.Count | Should -Be 2
    }

    It 'rejects an unknown status, a missing reason, a duplicate, an unknown field, a bad issue and missing parts' {
        $bad = @(
            @{ json = '{ ' + $script:header + ', "rules": [ { "match": "a", "status": "done" } ] }'; message = '*needs a status of*' }
            @{ json = '{ ' + $script:header + ', "rules": [ { "match": "a", "status": "deliberately excluded" } ] }'; message = '*needs a reason*' }
            @{ json = '{ ' + $script:header + ', "rules": [ { "match": "a", "status": "partially wrapped" } ] }'; message = '*needs a reason*' }
            @{ json = '{ ' + $script:header + ', "rules": [ { "match": "a", "status": "missing" }, { "match": "a", "status": "missing" } ] }'; message = '*appears twice*' }
            @{ json = '{ ' + $script:header + ', "rules": [ { "match": "a", "status": "missing", "colour": "red" } ] }'; message = "*unknown field 'colour'*" }
            @{ json = '{ ' + $script:header + ', "rules": [ { "match": "a", "status": "missing", "issue": "abc" } ] }'; message = '*not a number*' }
            @{ json = '{ ' + $script:header + ', "rules": [ { "status": "missing" } ] }'; message = "*has no 'match'*" }
            @{ json = '{ "schema": 1, "scope": "s", "rules": [] }'; message = "*Missing 'capabilities'*" }
            @{ json = '{ "schema": 1, "scope": "s", "capabilities": { "org": "" }, "rules": [] }'; message = '*has no label*' }
        )
        foreach ($case in $bad) {
            { Read-ParityMapping -Path (Write-Mapping -Json $case.json) } | Should -Throw -ExpectedMessage $case.message
        }
    }

    It 'fails for a file that does not exist' {
        { Read-ParityMapping -Path (Join-Path $TestDrive 'nope.json') } | Should -Throw -ExpectedMessage '*does not exist*'
    }

    It 'matches a topic rule on the topic itself and everything under it, and an exact rule only on itself' {
        Test-ParityRuleMatch -Match 'devops *' -CommandId 'devops' | Should -BeTrue
        Test-ParityRuleMatch -Match 'devops *' -CommandId 'devops pipeline list' | Should -BeTrue
        Test-ParityRuleMatch -Match 'devops *' -CommandId 'devopsx' | Should -BeFalse
        Test-ParityRuleMatch -Match 'plugins link' -CommandId 'plugins link' | Should -BeTrue
        Test-ParityRuleMatch -Match 'plugins link' -CommandId 'plugins link more' | Should -BeFalse
    }
}

Describe 'ConvertTo-ParityMarkdown' {
    BeforeAll {
        New-ParityFixtureRepo -Path $TestDrive
        $rules = @([pscustomobject]@{ match = 'unused one'; status = 'deliberately excluded'; reason = 'Has a | pipe in it.'; issue = 99 })
        $script:report = New-ParityReport -Inventory (New-ParityInventoryFixture) -Scan (Get-ParityPsfdxScan -Root $TestDrive) -Mapping (New-ParityMappingFixture -Rules $rules)
        $script:markdown = ConvertTo-ParityMarkdown -Report $script:report
    }

    It 'states the CLI version and the scope, and gives per-plugin-set totals' {
        $script:markdown.Contains('Salesforce CLI **9.9.9**') | Should -BeTrue
        $script:markdown.Contains('**Scope.** Demo scope.') | Should -BeTrue
        $script:markdown.Contains('| Core plugins (bundled with the CLI) |') | Should -BeTrue
        $script:markdown.Contains('| Just-in-time plugins (installed on first use) |') | Should -BeTrue
    }

    It 'lists uncovered commands with the reason and a link to the issue, and escapes table characters' {
        Test-InOrder -Text $script:markdown -Parts @('`sf unused one`', 'deliberately excluded', 'Has a \| pipe in it.', '[#99](https://github.com/tonygward/psfdx/issues/99)') | Should -BeTrue
        $script:markdown.Contains('`sf unused two` (beta)') | Should -BeTrue
    }

    It 'lists covered commands with their cmdlets and the flags not passed' {
        Test-InOrder -Text $script:markdown -Parts @('`sf deploy resume`', 'partially wrapped', '`Invoke-DemoDeploy`', '`--use-most-recent`') | Should -BeTrue
    }

    It 'has the sections that explain how to read and regenerate it' {
        $script:markdown.Contains('## Commands psfdx runs by another name') | Should -BeTrue
        $script:markdown.Contains('## Flags left out of the per-command view') | Should -BeTrue
        $script:markdown.Contains('## How to read this') | Should -BeTrue
        $script:markdown.Contains('New-CliParityReport.ps1') | Should -BeTrue
        $script:markdown.Contains([string][char]13) | Should -BeFalse
    }
}

Describe 'The committed parity report' {
    It 'matches the modules, the mapping and the committed inventory (regenerate with scripts/parity/New-CliParityReport.ps1)' {
        $output = & (Join-Path $PSScriptRoot 'New-CliParityReport.ps1') -Check
        $output | Should -Be 'The parity report is up to date.'
    }

    It 'comes from a real CLI inventory and a valid mapping' {
        $inventory = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot 'docs/cli-parity-inventory.json')) | ConvertFrom-Json
        $inventory.cliVersion | Should -Match '^[0-9]+\.[0-9]+\.[0-9]+\z'
        @($inventory.commands).Count | Should -BeGreaterThan 100
        { Read-ParityMapping -Path (Join-Path $script:repoRoot 'docs/cli-parity-mapping.json') } | Should -Not -Throw
    }

    It 'maps every command psfdx runs that the CLI knows to a status, and leaves none unresolved' {
        $report = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot 'docs/cli-parity.json')) | ConvertFrom-Json
        @($report.unresolved).Count | Should -Be 0
        @($report.warnings).Count | Should -Be 0
    }
}
