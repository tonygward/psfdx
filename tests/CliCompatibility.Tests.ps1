# Salesforce CLI compatibility checks. Neither lane needs an org or credentials.
#
# Offline lane (default, part of 'Invoke-Pester -Path . -CI'): reads the module source and checks every 'sf ...'
# command string against tests/cli-compatibility.json. It is fast and catches obvious breakage, but it is NOT proof that
# psfdx works with the current CLI: it compares against a list, not against the CLI.
#
# Live lane: set PSFDX_SF_CLI_HELP=1 after installing the LATEST STABLE CLI ('npm install --global @salesforce/cli').
# It runs 'sf <command> --help' for every command psfdx uses, checks that the flags psfdx passes are listed, and records
# the exact CLI version. With the variable set, a missing CLI is a failure, never a skip. No CLI version is pinned.
#
# A finding names the file, the function, the command and a suggestion. The JSON report goes to
# $env:PSFDX_CLI_COMPAT_REPORT, or to $TestDrive when that is not set.

$script:RunLiveLane = ($env:PSFDX_SF_CLI_HELP -eq '1')

Describe 'Salesforce CLI compatibility (offline)' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $PSScriptRoot 'CliCompatibility.Helpers.ps1')
        $script:Compat = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'cli-compatibility.json') -Raw | ConvertFrom-Json
        $scan = Get-CliSourceScan -Root $script:Root -Compat $script:Compat
        $script:Commands = @($scan.Commands)
        $script:Findings = @($scan.Findings)

        $reportPath = $env:PSFDX_CLI_COMPAT_REPORT
        if ([string]::IsNullOrWhiteSpace($reportPath) -or $script:RunLiveLane) { $reportPath = Join-Path $TestDrive 'cli-compatibility-report.json' }
        $script:ReportPath = $reportPath
        [pscustomobject]@{
            lane            = 'offline'
            cliVersion      = 'not checked (offline lane)'
            commandsChecked = @($script:Commands).Count
            commands        = @($script:Commands)
            findings        = @($script:Findings)
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    }

    It 'pins no Salesforce CLI version' {
        $script:Compat.PSObject.Properties.Name | Should -Not -Contain 'pinnedCliVersion'
        $text = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'cli-compatibility.json') -Raw
        $text | Should -Not -Match '(?i)pinned'
    }

    It 'finds the sf commands psfdx uses in every module' {
        @($script:Commands).Count | Should -BeGreaterThan 50
        $modules = @($script:Commands | ForEach-Object { ($_.File -split '/')[0] } | Sort-Object -Unique)
        foreach ($name in 'psfdx', 'psfdx-bulk', 'psfdx-development', 'psfdx-devops', 'psfdx-logs', 'psfdx-metadata', 'psfdx-packages', 'psfdx-sandbox') {
            $modules | Should -Contain $name
        }
    }

    It 'uses no removed command, legacy flag or unknown command family' {
        $message = Format-CliFindings -Findings $script:Findings
        @($script:Findings).Count | Should -Be 0 -Because ($message)
    }

    It 'writes a machine-readable report that says the CLI was not checked, with no command arguments' {
        Test-Path -LiteralPath $script:ReportPath | Should -BeTrue
        $report = Get-Content -LiteralPath $script:ReportPath -Raw | ConvertFrom-Json
        $report.lane | Should -Be 'offline'
        $report.cliVersion | Should -Be 'not checked (offline lane)'
        $report.commandsChecked | Should -BeGreaterThan 0
        (Get-Content -LiteralPath $script:ReportPath -Raw) | Should -Not -Match '--(password|sfdx-url|jwt-key-file|client-id)'
    }

    It 'every known command is listed once' {
        $names = @($script:Compat.knownCommands)
        @($names | Sort-Object -Unique).Count | Should -Be $names.Count
    }

    Context 'the offline checker' {
        It 'reports a command that is absent, with file, function and suggestion' {
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Compat $script:Compat -Text 'function Get-Thing { $c = "sf org creat sandbox --json" }'
            @($scan.Findings).Count | Should -Be 1
            $scan.Findings[0].File | Should -Be 'psfdx/fake.psm1'
            $scan.Findings[0].Function | Should -Be 'Get-Thing'
            $scan.Findings[0].Command | Should -Be 'sf org creat sandbox'
            $scan.Findings[0].Suggestion | Should -Match 'sf org creat sandbox --help'
        }

        It 'checks commands built as an argument array' {
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Compat $script:Compat -Text 'function Get-Thing { $arguments = @(''org'', ''creat'', ''sandbox'', ''--name'', $Name); Invoke-Salesforce -FilePath ''sf'' -Arguments $arguments }'
            @($scan.Findings).Count | Should -Be 1
            $scan.Findings[0].Command | Should -Be 'sf org creat sandbox'
        }

        It 'reports a removed command with its replacement' {
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Compat $script:Compat -Text 'function Deploy-Thing { $c = "sf deploy metadata --json" }'
            @($scan.Findings).Count | Should -Be 1
            $scan.Findings[0].Suggestion | Should -Be 'sf project deploy start'
        }

        It 'reports the sfdx executable and force commands' {
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Compat $script:Compat -Text 'function A { $c = "sfdx force:org:list" }; function B { $c = "sf force source deploy" }'
            @($scan.Findings).Count | Should -Be 2
        }

        It 'reports a legacy flag with its replacement' {
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Compat $script:Compat -Text 'function A { $c = "sf org list"; $c += " --targetusername me" }'
            @($scan.Findings).Count | Should -Be 1
            $scan.Findings[0].Suggestion | Should -Be '--target-org'
        }

        It 'accepts commands that remain valid, including ones with variables and extra words' {
            $text = 'function A { $c = "sf config set target-org $Org"; $d = "sf lightning dev $($Mode)"; $e = "sf plugins"; $f = "sf project deploy start --metadata-dir x" }'
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Compat $script:Compat -Text $text
            @($scan.Findings).Count | Should -Be 0
            (@($scan.Commands | ForEach-Object { $_.Command }) -join '|') | Should -Be 'sf config set|sf lightning dev|sf plugins|sf project deploy start'
        }

        It 'ignores strings that do not start with sf' {
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Compat $script:Compat -Text 'function A { throw "Run sf org login web first"; $x = "sfdc thing" }'
            @($scan.Findings).Count | Should -Be 0
            @($scan.Commands).Count | Should -Be 0
        }

        It 'collects the flags a function passes, but not words in error messages' {
            $text = 'function A { $c = "sf data query --query x"; $c += " --target-org me"; throw "use --not-a-flag here" }'
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Compat $script:Compat -Text $text
            (@($scan.Flags | ForEach-Object { $_.Flag } | Sort-Object) -join ',') | Should -Be '--query,--target-org'
        }
    }

    # These use help text in the shape the real CLI prints, so they show what the live lane does when upstream changes.
    Context 'the live checker, against sample help text' {
        BeforeAll {
            $script:QueryHelp = @"
Execute a SOQL query.

USAGE
  `$ sf data query -o <value> [--json]

FLAGS
  -o, --target-org=<value>      (required) Username or alias of the target org.
  -q, --query=<value>           SOQL query to execute.
      --all-rows                Include deleted records.

GLOBAL FLAGS
  --flags-dir=<value>  Import flag values from a directory.
  --json               Format output as json.
"@
            $script:TopicHelp = @"
Preview a Lightning Experience app locally.

USAGE
  `$ sf lightning dev COMMAND

COMMANDS
  lightning dev app        Preview a Lightning Experience app.
"@
            $script:OneFunction = Test-CliSource -File 'psfdx/fake.psm1' -Compat $script:Compat -Text 'function Select-Thing { $c = "sf data query"; $c += " --query x"; $c += " --target-org me"; $c += " --all-rows"; $c += " --json" }'
        }

        It 'reads the flags from the FLAGS and GLOBAL FLAGS sections' {
            (Get-CliHelpFlags -Text $script:QueryHelp) -join ',' | Should -Be '--all-rows,--flags-dir,--json,--query,--target-org'
            Get-CliHelpKind -Text $script:QueryHelp | Should -Be 'command'
            Get-CliHelpKind -Text $script:TopicHelp | Should -Be 'topic'
        }

        It 'reads a negatable flag, listed as --[no-]name, as both --name and --no-name' {
            $text = "FLAGS`n  -t, --[no-]track-source        Use source tracking.`n      --[no-]enable-app-analytics  Enable analytics.`n      --all-rows`n"
            (Get-CliHelpFlags -Text $text) -join ',' | Should -Be '--all-rows,--enable-app-analytics,--no-enable-app-analytics,--no-track-source,--track-source'
        }

        It 'passes when every command responds and every flag is listed' {
            $help = @([pscustomobject]@{ Command = 'sf data query'; ExitCode = 0; Text = $script:QueryHelp })
            $result = Test-CliAgainstHelp -Scan $script:OneFunction -Help $help
            @($result.Findings).Count | Should -Be 0 -Because (Format-CliFindings -Findings $result.Findings)
        }

        It 'fails when an upstream command disappears (its --help fails)' {
            $help = @([pscustomobject]@{ Command = 'sf data query'; ExitCode = 2; Text = 'command data:query not found' })
            $result = Test-CliAgainstHelp -Scan $script:OneFunction -Help $help
            @($result.Findings).Count | Should -Be 1
            $result.Findings[0].Command | Should -Be 'sf data query'
            $result.Findings[0].Problem | Should -Match '--help'' failed'
            $result.Findings[0].Suggestion | Should -Match 'sf commands'
        }

        It 'fails when an upstream flag disappears, naming the file, function and flag' {
            $without = $script:QueryHelp -replace '(?m)^      --all-rows.*\r?\n', ''
            $help = @([pscustomobject]@{ Command = 'sf data query'; ExitCode = 0; Text = $without })
            $result = Test-CliAgainstHelp -Scan $script:OneFunction -Help $help
            @($result.Findings).Count | Should -Be 1
            $result.Findings[0].File | Should -Be 'psfdx/fake.psm1'
            $result.Findings[0].Function | Should -Be 'Select-Thing'
            $result.Findings[0].Problem | Should -Match '--all-rows'
            $result.Findings[0].Suggestion | Should -Match 'sf data query --help'
        }

        It 'does not guess at flags for a topic command such as sf lightning dev' {
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Compat $script:Compat -Text 'function Start-Dev { $c = "sf lightning dev $Mode"; $c += " --name x" }'
            $help = @([pscustomobject]@{ Command = 'sf lightning dev'; ExitCode = 0; Text = $script:TopicHelp })
            $result = Test-CliAgainstHelp -Scan $scan -Help $help
            @($result.Findings).Count | Should -Be 0
            $result.TopicCommands | Should -Contain 'sf lightning dev'
        }

        It 'fails, rather than skipping, when the CLI is not installed' {
            { Resolve-CliVersion -Executable 'psfdx-no-such-cli' } | Should -Throw -ExpectedMessage '*was not found on PATH*npm install --global @salesforce/cli*'
        }
    }
}

# Needs the real CLI (the latest stable). PSFDX_SF_CLI_HELP=1 turns it on; the CLI being absent then fails the run.
Describe 'Salesforce CLI compatibility (live, latest stable CLI)' -Skip:(-not $script:RunLiveLane) {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $PSScriptRoot 'CliCompatibility.Helpers.ps1')
        $script:Compat = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'cli-compatibility.json') -Raw | ConvertFrom-Json

        $script:CliVersion = Resolve-CliVersion
        Write-Host "Salesforce CLI version under test: $script:CliVersion"

        $scan = Get-CliSourceScan -Root $script:Root -Compat $script:Compat
        $commandNames = @($scan.Commands | ForEach-Object { $_.Command } | Sort-Object -Unique)
        $script:Help = @()
        foreach ($name in $commandNames) { $script:Help += Get-CliHelp -Command ($name -replace '^sf ', '') }
        $script:Result = Test-CliAgainstHelp -Scan $scan -Help $script:Help
        $script:HelpFailures = @($script:Help | Where-Object { $_.ExitCode -ne 0 })

        $reportPath = $env:PSFDX_CLI_COMPAT_REPORT
        if ([string]::IsNullOrWhiteSpace($reportPath)) { $reportPath = Join-Path $TestDrive 'cli-compatibility-report.json' }
        $script:ReportPath = $reportPath
        [pscustomobject]@{
            lane            = 'live-help'
            cliVersion      = $script:CliVersion
            commandsChecked = @($commandNames).Count
            commands        = @($commandNames)
            topicCommands   = @($script:Result.TopicCommands)
            findings        = @($script:Result.Findings)
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    }

    It 'records the exact CLI version it ran against' {
        $script:CliVersion | Should -Match '^\d+\.\d+\.\d+$'
        $report = Get-Content -LiteralPath $script:ReportPath -Raw | ConvertFrom-Json
        $report.lane | Should -Be 'live-help'
        $report.cliVersion | Should -Be $script:CliVersion
    }

    It 'every command psfdx runs responds to --help' {
        $message = Format-CliFindings -Findings @($script:Result.Findings | Where-Object { $_.Problem -match '--help' })
        @($script:HelpFailures).Count | Should -Be 0 -Because ($message)
    }

    It 'every flag psfdx passes is listed by the CLI help' {
        $flagFindings = @($script:Result.Findings | Where-Object { $_.Problem -match '^Flag ' })
        @($flagFindings).Count | Should -Be 0 -Because (Format-CliFindings -Findings $flagFindings)
    }
}
