# Helpers for tests/CliCompatibility.Tests.ps1. Dot-sourced by both lanes. Plain PowerShell that also runs on
# Windows PowerShell 5.1, and none of it talks to an org.

function Get-CliCommandWords {
    param([string] $Text)
    # 'sf org create sandbox --name x' -> 'org create sandbox'. Stops at the first flag or variable.
    if ($Text -notmatch '^\s*sf((?:\s+[a-z][a-z0-9-]*)*)') { return $null }
    return (($Matches[1] -split '\s+' | Where-Object { $_ }) -join ' ')
}

function Test-CliSource {
    # Reads one source text. Returns the sf commands it builds, the problems found offline, and every --flag the
    # text passes to sf, tagged with the function that builds it.
    param([string] $Text, [string] $File, $Compat)
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$errors)
    $strings = $ast.FindAll({
            param($node)
            ($node -is [System.Management.Automation.Language.StringConstantExpressionAst]) -or
            ($node -is [System.Management.Automation.Language.ExpandableStringExpressionAst])
        }, $true)
    $commands = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]
    $flags = New-Object System.Collections.Generic.List[object]
    # Structured argv: `$arguments = @('package', 'list')` builds the command words as an array, so rebuild them
    # as an "sf package list" string and check that like any other command.
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($node in $strings) { $items.Add([pscustomobject]@{ Value = [string] $node.Value; Node = $node }) }
    $assignments = $ast.FindAll({
            param($node)
            ($node -is [System.Management.Automation.Language.AssignmentStatementAst]) -and
            ($node.Operator -eq 'Equals') -and
            ($node.Left -is [System.Management.Automation.Language.VariableExpressionAst]) -and
            ($node.Left.VariablePath.UserPath -eq 'arguments')
        }, $true)
    foreach ($assignment in $assignments) {
        $array = $assignment.Right.Find({ param($n) $n -is [System.Management.Automation.Language.ArrayLiteralAst] }, $true)
        if (-not $array) { continue }
        $words = New-Object System.Collections.Generic.List[string]
        foreach ($element in $array.Elements) {
            if (-not ($element -is [System.Management.Automation.Language.StringConstantExpressionAst])) { break }
            if ($element.Value -like '-*') { break }
            $words.Add($element.Value)
        }
        if ($words.Count -gt 0) { $items.Add([pscustomobject]@{ Value = 'sf ' + ($words -join ' '); Node = $assignment }) }
    }
    foreach ($item in $items) {
        $node = $item.Node
        $value = $item.Value
        $owner = $node.Parent
        while ($owner -and -not ($owner -is [System.Management.Automation.Language.FunctionDefinitionAst])) { $owner = $owner.Parent }
        $function = if ($owner) { $owner.Name } else { '(script)' }

        foreach ($legacy in $Compat.legacyFlags.PSObject.Properties) {
            if ($value -match ('(?<![\w-])' + [regex]::Escape($legacy.Name) + '(?![\w-])')) {
                $findings.Add([pscustomobject]@{ File = $File; Function = $function; Command = $legacy.Name
                        Problem = "Legacy flag '$($legacy.Name)'"; Suggestion = $legacy.Value })
            }
        }

        # A flag counts only when the string is an sf command or a fragment that starts with the flag (" --name $x"),
        # so prose in error messages is not mistaken for a flag.
        if (($value -match '^\s*sf(\s|$)') -or ($value -match '^\s*--[a-z]')) {
            foreach ($m in [regex]::Matches($value, '(?<![\w-])--[a-z][a-z0-9-]*')) {
                $flags.Add([pscustomobject]@{ File = $File; Function = $function; Flag = $m.Value })
            }
        }

        if ($value -match '^\s*sfdx(\s|$)') {
            $findings.Add([pscustomobject]@{ File = $File; Function = $function; Command = 'sfdx'
                    Problem = "Legacy 'sfdx' executable"; Suggestion = "Use 'sf' with the v2 command" })
            continue
        }
        $words = Get-CliCommandWords -Text $value
        if ([string]::IsNullOrEmpty($words)) { continue }

        $removed = $Compat.removedCommands | Where-Object { $words -eq $_.command -or $words.StartsWith($_.command + ' ') } | Select-Object -First 1
        if ($removed) {
            $findings.Add([pscustomobject]@{ File = $File; Function = $function; Command = "sf $words"
                    Problem = 'Command was removed from the Salesforce CLI'; Suggestion = $removed.replacement })
            continue
        }
        $known = $Compat.knownCommands | Where-Object { $words -eq $_ -or $words.StartsWith($_ + ' ') } | Sort-Object Length -Descending | Select-Object -First 1
        if ($known) {
            $commands.Add([pscustomobject]@{ File = $File; Function = $function; Command = "sf $known" })
        } else {
            $findings.Add([pscustomobject]@{ File = $File; Function = $function; Command = "sf $words"
                    Problem = 'Command is not in tests/cli-compatibility.json'
                    Suggestion = "Check it with 'sf $words --help'. If it is valid, add it to knownCommands; otherwise use its replacement" })
        }
    }
    return [pscustomobject]@{ Commands = $commands.ToArray(); Findings = $findings.ToArray(); Flags = $flags.ToArray() }
}

function Get-CliSourceScan {
    # Scans every module's .psm1 and .ps1 (not tests) under $Root.
    param([string] $Root, $Compat)
    $commands = @(); $findings = @(); $flags = @()
    foreach ($dir in Get-ChildItem -LiteralPath $Root -Directory -Filter 'psfdx*') {
        $files = @(Get-ChildItem -LiteralPath $dir.FullName -File | Where-Object {
                ($_.Extension -in '.psm1', '.ps1') -and ($_.Name -notlike '*.Tests.ps1')
            })
        foreach ($file in $files) {
            $relative = $dir.Name + '/' + $file.Name
            $scan = Test-CliSource -Text (Get-Content -LiteralPath $file.FullName -Raw) -File $relative -Compat $Compat
            $commands += @($scan.Commands); $findings += @($scan.Findings); $flags += @($scan.Flags)
        }
    }
    return [pscustomobject]@{ Commands = $commands; Findings = $findings; Flags = $flags }
}

function Format-CliFindings {
    param($Findings)
    return (@($Findings | ForEach-Object { "$($_.File) $($_.Function): $($_.Problem) ($($_.Command)). Suggested: $($_.Suggestion)" }) -join [Environment]::NewLine)
}

# ---- Live lane: needs the real CLI, never an org ------------------------------------------------------------

function Get-CliExecutable {
    # The real program (sf.cmd on Windows, sf on Linux and macOS), never npm's sf.ps1 shim, which mangles arguments.
    param([string] $Executable = 'sf')
    $app = Get-Command $Executable -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $app) {
        throw "Salesforce CLI ('$Executable') was not found on PATH. Install the latest stable CLI with 'npm install --global @salesforce/cli' and run again."
    }
    return $app.Source
}

function Resolve-CliVersion {
    # Returns the exact CLI version, or throws. The live lane must FAIL when the CLI is missing, never skip.
    param([string] $Executable = 'sf')
    $path = Get-CliExecutable -Executable $Executable
    $text = (& $path --version 2>&1 | Out-String).Trim()
    if ($text -notmatch '@salesforce/cli/(\d+\.\d+\.\d+)') { throw "Could not read the Salesforce CLI version from: $text" }
    return $Matches[1]
}

function Get-CliHelpKind {
    # 'command' has a FLAGS section; 'topic' (for example 'sf lightning dev') only lists subcommands.
    param([string] $Text)
    if ($Text -match '(?m)^FLAGS\s*$') { return 'command' }
    if ($Text -match '(?m)^COMMANDS\s*$') { return 'topic' }
    return 'unknown'
}

function Get-CliHelpFlags {
    # Every '--flag' the help text lists as a flag (FLAGS and GLOBAL FLAGS sections), for example
    # '  -o, --target-org=<value>' and '      --all-rows'.
    param([string] $Text)
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($Text, '(?m)^\s+(?:-[A-Za-z],\s+)?(--[a-z][a-z0-9-]*)')) { $found.Add($m.Groups[1].Value) }
    return @($found | Sort-Object -Unique)
}

function Get-CliHelp {
    # Runs 'sf <command> --help'. Output only, no org.
    param([string] $Command, [string] $Executable = 'sf')
    $path = Get-CliExecutable -Executable $Executable
    $text = (& $path @($Command -split ' ') --help 2>&1 | Out-String)
    return [pscustomobject]@{ Command = "sf $Command"; ExitCode = $LASTEXITCODE; Text = $text }
}

function Test-CliAgainstHelp {
    # $Scan: the result of Get-CliSourceScan. $Help: one Get-CliHelp result per distinct command.
    # Returns findings for commands whose --help fails and for flags a function passes that its commands' help does not list.
    param($Scan, $Help)
    $findings = New-Object System.Collections.Generic.List[object]
    $byCommand = @{}
    foreach ($h in $Help) { $byCommand[$h.Command] = $h }

    foreach ($h in $Help) {
        if ($h.ExitCode -ne 0) {
            $findings.Add([pscustomobject]@{ File = '(all modules)'; Function = '(see commands)'; Command = $h.Command
                    Problem = "'$($h.Command) --help' failed, so the command or its plugin is missing"
                    Suggestion = "Run '$($h.Command) --help' and 'sf commands' to find the replacement, or install the plugin it needs" })
        }
    }

    $skipped = New-Object System.Collections.Generic.List[string]
    $groups = @($Scan.Commands | Group-Object { $_.File + '|' + $_.Function })
    foreach ($group in $groups) {
        $first = $group.Group[0]
        $commandNames = @($group.Group | ForEach-Object { $_.Command } | Sort-Object -Unique)
        $allowed = New-Object System.Collections.Generic.HashSet[string]
        $verifiable = $true
        foreach ($name in $commandNames) {
            $h = $byCommand[$name]
            if (-not $h -or $h.ExitCode -ne 0) { $verifiable = $false; continue }
            if ((Get-CliHelpKind -Text $h.Text) -ne 'command') { $verifiable = $false; $skipped.Add($name); continue }
            foreach ($f in (Get-CliHelpFlags -Text $h.Text)) { [void]$allowed.Add($f) }
        }
        if (-not $verifiable) { continue }
        $used = @($Scan.Flags | Where-Object { $_.File -eq $first.File -and $_.Function -eq $first.Function } | ForEach-Object { $_.Flag } | Sort-Object -Unique)
        foreach ($flag in $used) {
            if (-not $allowed.Contains($flag)) {
                $findings.Add([pscustomobject]@{ File = $first.File; Function = $first.Function; Command = ($commandNames -join ' | ')
                        Problem = "Flag '$flag' is not listed by the CLI help"
                        Suggestion = "Run '$($commandNames[0]) --help' for the current flag name" })
            }
        }
    }
    return [pscustomobject]@{ Findings = $findings.ToArray(); TopicCommands = @($skipped | Sort-Object -Unique) }
}
