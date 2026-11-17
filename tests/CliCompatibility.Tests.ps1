# Offline Salesforce CLI compatibility checks.
#
# Default lane: reads the module source (never runs sf, never needs an org or credentials) and checks every
# 'sf ...' command string against tests/cli-compatibility.json. A finding names the file, the function, the
# command and a suggested replacement. A machine-readable report is written to $env:PSFDX_CLI_COMPAT_REPORT,
# or to $TestDrive when that is not set.
#
# Opt-in lane: set PSFDX_SF_CLI_HELP=1 on a machine with the pinned CLI installed to run 'sf <command> --help'
# for every known command. It is skipped by default and needs no org.

$script:RunHelpLane = ($env:PSFDX_SF_CLI_HELP -eq '1') -and [bool](Get-Command sf -ErrorAction SilentlyContinue)

Describe 'Salesforce CLI compatibility (offline)' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        $script:Compat = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'cli-compatibility.json') -Raw | ConvertFrom-Json

        function Get-CliCommandWords {
            param([string] $Text)
            # 'sf org create sandbox --name x' -> 'org create sandbox'. Stops at the first flag or variable.
            if ($Text -notmatch '^\s*sf((?:\s+[a-z][a-z-]*)*)') { return $null }
            return (($Matches[1] -split '\s+' | Where-Object { $_ }) -join ' ')
        }

        function Test-CliSource {
            param([string] $Text, [string] $File)
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$errors)
            $strings = $ast.FindAll({
                    param($node)
                    ($node -is [System.Management.Automation.Language.StringConstantExpressionAst]) -or
                    ($node -is [System.Management.Automation.Language.ExpandableStringExpressionAst])
                }, $true)
            $commands = New-Object System.Collections.Generic.List[object]
            $findings = New-Object System.Collections.Generic.List[object]
            foreach ($node in $strings) {
                $value = [string] $node.Value
                $owner = $node.Parent
                while ($owner -and -not ($owner -is [System.Management.Automation.Language.FunctionDefinitionAst])) { $owner = $owner.Parent }
                $function = if ($owner) { $owner.Name } else { '(script)' }

                foreach ($legacy in $script:Compat.legacyFlags.PSObject.Properties) {
                    if ($value -match ('(?<![\w-])' + [regex]::Escape($legacy.Name) + '(?![\w-])')) {
                        $findings.Add([pscustomobject]@{ File = $File; Function = $function; Command = $legacy.Name
                                Problem = "Legacy flag '$($legacy.Name)'"; Suggestion = $legacy.Value })
                    }
                }

                if ($value -match '^\s*sfdx(\s|$)') {
                    $findings.Add([pscustomobject]@{ File = $File; Function = $function; Command = 'sfdx'
                            Problem = "Legacy 'sfdx' executable"; Suggestion = "Use 'sf' with the v2 command" })
                    continue
                }
                $words = Get-CliCommandWords -Text $value
                if ([string]::IsNullOrEmpty($words)) { continue }

                $removed = $script:Compat.removedCommands | Where-Object { $words -eq $_.command -or $words.StartsWith($_.command + ' ') } | Select-Object -First 1
                if ($removed) {
                    $findings.Add([pscustomobject]@{ File = $File; Function = $function; Command = "sf $words"
                            Problem = 'Command was removed from the Salesforce CLI'; Suggestion = $removed.replacement })
                    continue
                }
                $known = $script:Compat.knownCommands | Where-Object { $words -eq $_ -or $words.StartsWith($_ + ' ') } | Sort-Object Length -Descending | Select-Object -First 1
                if ($known) {
                    $commands.Add([pscustomobject]@{ File = $File; Function = $function; Command = "sf $known" })
                } else {
                    $findings.Add([pscustomobject]@{ File = $File; Function = $function; Command = "sf $words"
                            Problem = 'Command is not in tests/cli-compatibility.json'
                            Suggestion = "Check it with 'sf $words --help'. If it is valid, add it to knownCommands; otherwise use its replacement" })
                }
            }
            return [pscustomobject]@{ Commands = $commands.ToArray(); Findings = $findings.ToArray() }
        }

        function Format-CliFindings {
            param($Findings)
            return (@($Findings | ForEach-Object { "$($_.File) $($_.Function): $($_.Problem) ($($_.Command)). Suggested: $($_.Suggestion)" }) -join [Environment]::NewLine)
        }

        $sourceFiles = @()
        foreach ($dir in Get-ChildItem -LiteralPath $script:Root -Directory -Filter 'psfdx*') {
            $sourceFiles += @(Get-ChildItem -LiteralPath $dir.FullName -File | Where-Object {
                    ($_.Extension -in '.psm1', '.ps1') -and ($_.Name -notlike '*.Tests.ps1')
                })
        }
        $script:Commands = @()
        $script:Findings = @()
        foreach ($file in $sourceFiles) {
            $relative = $file.Directory.Name + '/' + $file.Name
            $scan = Test-CliSource -Text (Get-Content -LiteralPath $file.FullName -Raw) -File $relative
            $script:Commands += @($scan.Commands)
            $script:Findings += @($scan.Findings)
        }

        $reportPath = $env:PSFDX_CLI_COMPAT_REPORT
        if ([string]::IsNullOrWhiteSpace($reportPath)) { $reportPath = Join-Path $TestDrive 'cli-compatibility-report.json' }
        $script:ReportPath = $reportPath
        [pscustomobject]@{
            pinnedCliVersion = $script:Compat.pinnedCliVersion
            lane             = 'offline'
            commandsChecked  = @($script:Commands).Count
            commands         = @($script:Commands)
            findings         = @($script:Findings)
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    }

    It 'pins a stable CLI version' {
        $script:Compat.pinnedCliVersion | Should -Match '^\d+\.\d+\.\d+$'
    }

    It 'finds the sf commands psfdx uses in every module' {
        @($script:Commands).Count | Should -BeGreaterThan 50
        $modules = @($script:Commands | ForEach-Object { ($_.File -split '/')[0] } | Sort-Object -Unique)
        foreach ($name in 'psfdx', 'psfdx-development', 'psfdx-logs', 'psfdx-metadata', 'psfdx-packages', 'psfdx-sandbox') {
            $modules | Should -Contain $name
        }
    }

    It 'uses no removed command, legacy flag or unknown command family' {
        $message = Format-CliFindings -Findings $script:Findings
        @($script:Findings).Count | Should -Be 0 -Because ($message)
    }

    It 'writes a machine-readable report with the CLI version and no command arguments' {
        Test-Path -LiteralPath $script:ReportPath | Should -BeTrue
        $report = Get-Content -LiteralPath $script:ReportPath -Raw | ConvertFrom-Json
        $report.pinnedCliVersion | Should -Be $script:Compat.pinnedCliVersion
        $report.commandsChecked | Should -BeGreaterThan 0
        (Get-Content -LiteralPath $script:ReportPath -Raw) | Should -Not -Match '--(password|sfdx-url|jwt-key-file|client-id)'
    }

    It 'every known command is listed once' {
        $names = @($script:Compat.knownCommands)
        @($names | Sort-Object -Unique).Count | Should -Be $names.Count
    }

    Context 'the checker' {
        It 'reports a command that is absent, with file, function and suggestion' {
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Text 'function Get-Thing { $c = "sf org creat sandbox --json" }'
            @($scan.Findings).Count | Should -Be 1
            $scan.Findings[0].File | Should -Be 'psfdx/fake.psm1'
            $scan.Findings[0].Function | Should -Be 'Get-Thing'
            $scan.Findings[0].Command | Should -Be 'sf org creat sandbox'
            $scan.Findings[0].Suggestion | Should -Match 'sf org creat sandbox --help'
        }

        It 'reports a removed command with its replacement' {
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Text 'function Deploy-Thing { $c = "sf deploy metadata --json" }'
            @($scan.Findings).Count | Should -Be 1
            $scan.Findings[0].Suggestion | Should -Be 'sf project deploy start'
        }

        It 'reports the sfdx executable and force commands' {
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Text 'function A { $c = "sfdx force:org:list" }; function B { $c = "sf force source deploy" }'
            @($scan.Findings).Count | Should -Be 2
        }

        It 'reports a legacy flag with its replacement' {
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Text 'function A { $c = "sf org list"; $c += " --targetusername me" }'
            @($scan.Findings).Count | Should -Be 1
            $scan.Findings[0].Suggestion | Should -Be '--target-org'
        }

        It 'accepts commands that remain valid, including ones with variables and extra words' {
            $text = 'function A { $c = "sf config set target-org $Org"; $d = "sf lightning dev $($Mode)"; $e = "sf plugins"; $f = "sf project deploy start --metadata-dir x" }'
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Text $text
            @($scan.Findings).Count | Should -Be 0
            (@($scan.Commands | ForEach-Object { $_.Command }) -join '|') | Should -Be 'sf config set|sf lightning dev|sf plugins|sf project deploy start'
        }

        It 'ignores strings that do not start with sf' {
            $scan = Test-CliSource -File 'psfdx/fake.psm1' -Text 'function A { throw "Run sf org login web first"; $x = "sfdc thing" }'
            @($scan.Findings).Count | Should -Be 0
            @($scan.Commands).Count | Should -Be 0
        }
    }
}

Describe 'Salesforce CLI compatibility (opt-in help lane)' -Skip:(-not $script:RunHelpLane) {
    It 'runs the pinned CLI version' {
        $compat = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'cli-compatibility.json') -Raw | ConvertFrom-Json
        $version = (& sf --version) -join ' '
        $version | Should -Match ([regex]::Escape($compat.pinnedCliVersion)) -Because 'refresh the pin in tests/cli-compatibility.json deliberately'
    }

    It 'every known command responds to --help' {
        $compat = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'cli-compatibility.json') -Raw | ConvertFrom-Json
        $missing = @()
        foreach ($command in $compat.knownCommands) {
            $null = & sf @($command -split ' ') --help 2>&1
            if ($LASTEXITCODE -ne 0) { $missing += "sf $command" }
        }
        $missing -join ', ' | Should -Be ''
    }
}
