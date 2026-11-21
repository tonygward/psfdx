# Library for the Salesforce CLI to psfdx parity report (issue 205). Dot-sourced by New-CliInventorySnapshot.ps1,
# New-CliParityReport.ps1 and CliParity.Tests.ps1. Plain PowerShell that also runs on Windows PowerShell 5.1. Nothing here
# talks to an org, and only ConvertTo-ParityInventory's caller needs the Salesforce CLI.

$script:ParityStatuses = @('wrapped', 'partially wrapped', 'missing', 'deliberately excluded', 'not applicable')
# Flags that nearly every command has. They are reported once, as cross-cutting, rather than making every command partially wrapped.
$script:ParityGlobalFlags = @('json', 'flags-dir', 'api-version')

function Sort-ParityObject {
    # Orders by an ordinal (culture-free) comparison, so the report is the same on every machine. Optional key script block.
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0)][scriptblock] $Property,
        [Parameter(ValueFromPipeline = $true)] $InputObject
    )
    begin { $items = New-Object System.Collections.Generic.List[object] }
    process { $items.Add($InputObject) }
    end {
        $pairs = New-Object 'System.Collections.Generic.List[object]'
        for ($i = 0; $i -lt $items.Count; $i++) {
            $key = [string]$items[$i]
            if ($Property) { $key = [string](ForEach-Object -InputObject $items[$i] -Process $Property) }
            $pairs.Add([pscustomobject]@{ Key = $key; Index = $i; Item = $items[$i] })
        }
        # The index breaks ties, so equal keys keep their input order.
        $pairs.Sort([System.Comparison[object]]{ param($x, $y) $c = [string]::CompareOrdinal($x.Key, $y.Key); if ($c -ne 0) { $c } else { $x.Index - $y.Index } })
        foreach ($pair in $pairs) { $pair.Item }
    }
}

function ConvertTo-ParityInventory {
    # Turns the JSON that `sf commands --json` prints into the compact inventory the report is built from.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]] $Commands,
        [Parameter(Mandatory = $true)][string] $CliVersion
    )

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($command in $Commands) {
        $flags = New-Object System.Collections.Generic.List[object]
        if ($null -ne $command.flags) {
            foreach ($property in $command.flags.PSObject.Properties) {
                $flag = $property.Value
                if ($flag.PSObject.Properties['hidden'] -and $flag.hidden) { continue }
                $flags.Add([pscustomobject][ordered]@{ name = [string]$property.Name; required = [bool]($flag.PSObject.Properties['required'] -and $flag.required) })
            }
        }
        $state = 'ga'
        if ($command.PSObject.Properties['state'] -and $command.state) { $state = [string]$command.state }
        $hidden = [bool]($command.PSObject.Properties['hidden'] -and $command.hidden)
        $aliases = @()
        if ($command.PSObject.Properties['aliases'] -and $command.aliases) { $aliases = @($command.aliases | ForEach-Object { ([string]$_) -replace ':', ' ' } | Sort-ParityObject) }
        $deprecatedAliases = [bool]($command.PSObject.Properties['deprecateAliases'] -and $command.deprecateAliases)
        $items.Add([pscustomobject][ordered]@{
                id         = (([string]$command.id) -replace ':', ' ')
                plugin     = [string]$command.pluginName
                pluginType = [string]$command.pluginType
                state      = $state
                hidden     = $hidden
                aliases    = $aliases
                deprecatedAliases = $deprecatedAliases
                summary    = ([string]$command.summary).Trim()
                flags      = @($flags.ToArray() | Sort-ParityObject { $_.name } )
            })
    }
    $sorted = @($items.ToArray() | Sort-ParityObject { $_.id })
    $plugins = @($sorted | Group-Object { $_.plugin + '|' + $_.pluginType } | ForEach-Object {
            [pscustomobject][ordered]@{ name = $_.Group[0].plugin; type = $_.Group[0].pluginType; commands = $_.Count }
        } | Sort-ParityObject { $_.name })
    return [pscustomobject][ordered]@{
        schema     = 1
        cliVersion = $CliVersion
        plugins    = $plugins
        commands   = $sorted
    }
}

function Get-ParityArrayElements {
    # The elements of the first array written in an expression: @('a', 'b'), a bare 'a', 'b', and a one-element @('a') (which is not an ArrayLiteralAst).
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)] $Expression
    )

    $outer = $Expression.Find({ param($n) ($n -is [System.Management.Automation.Language.ArrayExpressionAst]) -or ($n -is [System.Management.Automation.Language.ArrayLiteralAst]) }, $true)
    if ($null -eq $outer) { return $null }
    if ($outer -is [System.Management.Automation.Language.ArrayLiteralAst]) { return @($outer.Elements) }
    $statement = $outer.SubExpression.Statements | Select-Object -First 1
    if ($statement -isnot [System.Management.Automation.Language.PipelineAst]) { return $null }
    $inner = $statement.PipelineElements | Select-Object -First 1
    if ($inner -isnot [System.Management.Automation.Language.CommandExpressionAst]) { return $null }
    if ($inner.Expression -is [System.Management.Automation.Language.ArrayLiteralAst]) { return @($inner.Expression.Elements) }
    return @($inner.Expression)
}

function Get-ParityPsfdxScan {
    # Reads every psfdx module under $Root (manifests and sources, not tests) and returns the functions each one defines,
    # whether it is exported, and the `sf` commands and flags each function builds.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Root
    )

    $functions = New-Object System.Collections.Generic.List[object]
    $references = New-Object System.Collections.Generic.List[object]
    foreach ($dir in (Get-ChildItem -LiteralPath $Root -Directory -Filter 'psfdx*' | Sort-Object Name)) {
        $manifestPath = Join-Path $dir.FullName ($dir.Name + '.psd1')
        $exported = @()
        if (Test-Path -LiteralPath $manifestPath) {
            # Read the manifest as syntax, not as code, so this works in Windows PowerShell 5.1 and 7 without evaluating it.
            $manifestAst = [System.Management.Automation.Language.Parser]::ParseFile($manifestPath, [ref]$null, [ref]$null)
            $table = $manifestAst.Find({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $false)
            if ($table) {
                foreach ($pair in $table.KeyValuePairs) {
                    if (($pair.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst]) -and ($pair.Item1.Value -eq 'FunctionsToExport')) {
                        $exported = @($pair.Item2.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value })
                    }
                }
            }
        }
        $files = @(Get-ChildItem -LiteralPath $dir.FullName -File | Where-Object { ($_.Extension -in '.psm1', '.ps1') -and ($_.Name -notlike '*.Tests.ps1') } | Sort-Object Name)
        foreach ($file in $files) {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput([System.IO.File]::ReadAllText($file.FullName), [ref]$null, [ref]$errors)
            $definitions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
            $definedHere = @($definitions | ForEach-Object { $_.Name })
            foreach ($definition in $definitions) {
                $calls = @($definition.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                        ForEach-Object { $_.GetCommandName() } | Where-Object { $_ -and ($_ -match '^[A-Za-z]+-[A-Za-z0-9]+\z') -and ($_ -ne $definition.Name) } | Sort-Object -Unique)
                $flags = New-Object System.Collections.Generic.SortedSet[string] ([System.StringComparer]::Ordinal)
                $strings = $definition.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
                foreach ($s in $strings) {
                    if ($s.Value -match '^--([a-z][a-z0-9-]*)\z') { [void]$flags.Add($Matches[1]) }
                }
                $functions.Add([pscustomobject]@{
                        Name     = $definition.Name
                        Module   = $dir.Name
                        File     = $dir.Name + '/' + $file.Name
                        Exported = ($exported -contains $definition.Name)
                        Calls    = $calls
                        Flags    = @($flags)
                    })

                # Structured argv: an array of words passed to `Invoke-Salesforce -FilePath 'sf' -Arguments ...`, inline or through a variable.
                $arrays = New-Object System.Collections.Generic.List[object]
                $variableNames = New-Object System.Collections.Generic.List[string]
                $variableNames.Add('arguments')
                $invocations = $definition.Body.FindAll({ param($n) ($n -is [System.Management.Automation.Language.CommandAst]) -and ($n.GetCommandName() -eq 'Invoke-Salesforce') }, $true)
                foreach ($invocation in $invocations) {
                    $elements = @($invocation.CommandElements)
                    $filePath = $null; $argumentValue = $null
                    for ($i = 0; $i -lt $elements.Count; $i++) {
                        if ($elements[$i] -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                        $next = $null
                        if ($elements[$i].Argument) { $next = $elements[$i].Argument } elseif (($i + 1) -lt $elements.Count) { $next = $elements[$i + 1] }
                        if ($elements[$i].ParameterName -eq 'FilePath' -and $next -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $filePath = $next.Value }
                        if ($elements[$i].ParameterName -eq 'Arguments' -and $next) { $argumentValue = $next }
                    }
                    if ($filePath -ne 'sf' -or -not $argumentValue) { continue }
                    $inline = Get-ParityArrayElements -Expression $argumentValue
                    if ($null -ne $inline) { $arrays.Add($inline) }
                    foreach ($variable in @($argumentValue.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true))) {
                        if (-not $variableNames.Contains($variable.VariablePath.UserPath)) { $variableNames.Add($variable.VariablePath.UserPath) }
                    }
                }
                $names = $variableNames.ToArray()
                $assignments = $definition.Body.FindAll({ param($n)
                        ($n -is [System.Management.Automation.Language.AssignmentStatementAst]) -and ($n.Operator -eq 'Equals') -and
                        ($n.Left -is [System.Management.Automation.Language.VariableExpressionAst]) -and ($names -contains $n.Left.VariablePath.UserPath) }, $true)
                foreach ($assignment in $assignments) {
                    $elements = Get-ParityArrayElements -Expression $assignment.Right
                    if ($null -ne $elements) { $arrays.Add($elements) }
                }
                foreach ($array in $arrays) {
                    $words = New-Object System.Collections.Generic.List[string]
                    foreach ($element in $array) {
                        if ($element -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { break }
                        if ($element.Value -like '-*') { break }
                        $words.Add($element.Value)
                    }
                    if ($words.Count -gt 0) { $references.Add([pscustomobject]@{ Function = $definition.Name; File = $dir.Name + '/' + $file.Name; Words = $words.ToArray() }) }
                }
            }
        }
    }
    return [pscustomobject]@{ Functions = $functions.ToArray(); References = $references.ToArray() }
}

function Get-ParityOrderKey {
    # The words of a command, sorted, so two orderings of the same words share a key.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string[]] $Words
    )
    $copy = [string[]]@($Words)
    [System.Array]::Sort($copy, [System.StringComparer]::Ordinal)
    return ($copy -join ' ')
}

function Test-ParityRuleMatch {
    # A rule's match is a command ('org list') or a topic prefix ('devops *', which also matches 'devops' itself).
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Match,
        [Parameter(Mandatory = $true)][string] $CommandId
    )
    if ($Match.EndsWith(' *')) {
        $prefix = $Match.Substring(0, $Match.Length - 2)
        return ($CommandId -eq $prefix) -or $CommandId.StartsWith($prefix + ' ')
    }
    return $CommandId -eq $Match
}

function Read-ParityMapping {
    # Reads and validates docs/cli-parity-mapping.json. Throws on an invalid mapping; never on a newly discovered command.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Mapping file '$Path' does not exist." }
    $mapping = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($required in 'schema', 'scope', 'capabilities', 'rules') {
        if (-not $mapping.PSObject.Properties[$required]) { $problems.Add("Missing '$required'.") }
    }
    if ($problems.Count -gt 0) { throw ("Invalid mapping: " + ($problems -join ' ')) }
    $seen = @{}
    $index = 0
    foreach ($rule in @($mapping.rules)) {
        $index++
        $label = "rule $index"
        if (-not $rule.PSObject.Properties['match'] -or [string]::IsNullOrWhiteSpace([string]$rule.match)) { $problems.Add("$label has no 'match'."); continue }
        $label = "rule '$($rule.match)'"
        foreach ($property in $rule.PSObject.Properties.Name) {
            if ($property -notin 'match', 'status', 'reason', 'issue', 'ignoreFlags') { $problems.Add("$label has an unknown field '$property'.") }
        }
        if ($seen.ContainsKey($rule.match)) { $problems.Add("$label appears twice.") }
        $seen[$rule.match] = $true
        if (-not $rule.PSObject.Properties['status'] -or $rule.status -notin $script:ParityStatuses) {
            $problems.Add("$label needs a status of: " + ($script:ParityStatuses -join ', ') + '.')
            continue
        }
        if ($rule.status -in 'deliberately excluded', 'not applicable', 'partially wrapped' -and [string]::IsNullOrWhiteSpace([string]$rule.reason)) {
            $problems.Add("$label is '$($rule.status)' and needs a reason.")
        }
        if ($rule.PSObject.Properties['issue'] -and $null -ne $rule.issue -and ([string]$rule.issue) -notmatch '^[0-9]+\z') { $problems.Add("$label has an issue that is not a number.") }
    }
    foreach ($property in $mapping.capabilities.PSObject.Properties) {
        if ([string]::IsNullOrWhiteSpace([string]$property.Value)) { $problems.Add("Capability '$($property.Name)' has no label.") }
    }
    if ($problems.Count -gt 0) { throw ("Invalid mapping: " + ($problems -join ' ')) }
    return $mapping
}

function New-ParityReport {
    # Builds the report object from an inventory, a scan of psfdx and a validated mapping. Pure: no I/O, no clock, so the result
    # is the same every time for the same inputs and a version bump gives a small diff.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)] $Inventory,
        [Parameter(Mandatory = $true)] $Scan,
        [Parameter(Mandatory = $true)] $Mapping
    )

    $commands = @($Inventory.commands)
    $ids = @($commands | ForEach-Object { $_.id })
    $idSet = @{}
    foreach ($id in $ids) { $idSet[$id] = $true }

    # Resolve each reference to the longest real command that its leading words spell.
    $aliasMap = @{}
    $deprecatedAlias = @{}
    foreach ($command in $commands) {
        foreach ($alias in @($command.aliases)) {
            if ($alias -and -not $idSet.ContainsKey($alias)) {
                $aliasMap[$alias] = $command.id
                $deprecatedAlias[$alias] = [bool]$command.deprecatedAliases
            }
        }
    }
    # The CLI also accepts a command's words in any order (`apex log list` runs `apex list log`).
    $orderMap = @{}
    foreach ($command in $commands) {
        $key = Get-ParityOrderKey -Words @($command.id -split ' ')
        if ($orderMap.ContainsKey($key)) { $orderMap[$key] = $null } else { $orderMap[$key] = $command.id }
    }
    $usage = @{}
    $aliasUse = New-Object System.Collections.Generic.List[object]
    $unresolved = New-Object System.Collections.Generic.List[object]
    foreach ($reference in $Scan.References) {
        $words = @($reference.Words)
        $targets = @()
        # Longest leading words that spell a command: its own name first, then an old name (alias) of a command.
        for ($n = $words.Count; $n -ge 1 -and $targets.Count -eq 0; $n--) {
            $candidate = ($words[0..($n - 1)] -join ' ')
            $reordered = $orderMap[(Get-ParityOrderKey -Words @($words[0..($n - 1)]))]
            if ($idSet.ContainsKey($candidate)) { $targets = @($candidate) }
            elseif ($reordered -and $reordered -ne $candidate -and -not $aliasMap.ContainsKey($candidate)) {
                $targets = @($reordered)
                $aliasUse.Add([pscustomobject][ordered]@{ function = $reference.Function; alias = $candidate; command = $reordered; deprecated = $false; kind = 'word order' })
            }
            elseif ($aliasMap.ContainsKey($candidate)) {
                $targets = @($aliasMap[$candidate])
                $aliasUse.Add([pscustomobject][ordered]@{ function = $reference.Function; alias = $candidate; command = $aliasMap[$candidate]; deprecated = [bool]$deprecatedAlias[$candidate]; kind = 'alias' })
            }
        }
        if ($targets.Count -eq 0) {
            $text = $words -join ' '
            # A topic such as 'lightning dev': the function picks the subcommand at run time, so it counts for every subcommand.
            $below = @($ids | Where-Object { $_.StartsWith($text + ' ') })
            if ($below.Count -gt 0) { $targets = $below }
            else {
                $unresolved.Add([pscustomobject][ordered]@{ words = $text; function = $reference.Function; file = $reference.File; reason = 'not a command, or an old name, in this CLI' })
                continue
            }
        }
        foreach ($match in $targets) {
            if (-not $usage.ContainsKey($match)) { $usage[$match] = New-Object System.Collections.Generic.List[string] }
            if (-not $usage[$match].Contains($reference.Function)) { $usage[$match].Add($reference.Function) }
        }
    }

    $functionByName = @{}
    foreach ($f in $Scan.Functions) { $functionByName[$f.Name] = $f }
    $ignored = @($script:ParityGlobalFlags)

    $warnings = New-Object System.Collections.Generic.List[string]
    $rules = @($Mapping.rules)
    foreach ($rule in $rules) {
        $hit = $false
        foreach ($id in $ids) { if (Test-ParityRuleMatch -Match $rule.match -CommandId $id) { $hit = $true; break } }
        if (-not $hit) { $warnings.Add("Mapping rule '$($rule.match)' matches no command in CLI $($Inventory.cliVersion); it may be stale.") }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($command in $commands) {
        $rule = $null
        foreach ($candidate in $rules) {
            if (Test-ParityRuleMatch -Match $candidate.match -CommandId $command.id) {
                # An exact command rule beats a topic rule that appears earlier; otherwise the first match wins.
                if ($null -eq $rule -or ((-not $candidate.match.EndsWith(' *')) -and $rule.match.EndsWith(' *'))) { $rule = $candidate }
            }
        }
        $owners = @()
        if ($usage.ContainsKey($command.id)) { $owners = @($usage[$command.id].ToArray() | Sort-ParityObject) }
        $ruleIgnored = @()
        if ($rule -and $rule.PSObject.Properties['ignoreFlags']) { $ruleIgnored = @($rule.ignoreFlags) }

        $covered = New-Object System.Collections.Generic.SortedSet[string] ([System.StringComparer]::Ordinal)
        foreach ($owner in $owners) {
            if (-not $functionByName.ContainsKey($owner)) { continue }
            foreach ($flag in $functionByName[$owner].Flags) { [void]$covered.Add($flag) }
            # Flags built by helpers the owner calls count too: helpers in the same file, and anything in psfdx-shared, followed through their own calls.
            $seen = @{}
            $pending = New-Object System.Collections.Generic.Queue[string]
            foreach ($called in $functionByName[$owner].Calls) { $pending.Enqueue($called) }
            while ($pending.Count -gt 0) {
                $called = $pending.Dequeue()
                if ($seen.ContainsKey($called) -or -not $functionByName.ContainsKey($called)) { continue }
                $helper = $functionByName[$called]
                if ($helper.File -ne $functionByName[$owner].File -and $helper.Module -ne 'psfdx-shared') { continue }
                $seen[$called] = $true
                foreach ($flag in $helper.Flags) { [void]$covered.Add($flag) }
                foreach ($next in $helper.Calls) { $pending.Enqueue($next) }
            }
        }
        $cliFlags = @($command.flags | ForEach-Object { $_.name } | Where-Object { $ignored -notcontains $_ -and $ruleIgnored -notcontains $_ })
        $uncovered = @($cliFlags | Where-Object { -not $covered.Contains($_) })

        $status = 'missing'
        $reason = $null
        $issue = $null
        if ($rule) {
            if ($rule.PSObject.Properties['reason'] -and $rule.reason) { $reason = [string]$rule.reason }
            if ($rule.PSObject.Properties['issue'] -and $null -ne $rule.issue) { $issue = [int]$rule.issue }
        }
        if ($owners.Count -gt 0) {
            if ($uncovered.Count -eq 0) { $status = 'wrapped' } else { $status = 'partially wrapped' }
            if ($rule) {
                if ($rule.status -in 'wrapped', 'partially wrapped') {
                    $status = [string]$rule.status
                } else {
                    $warnings.Add("Command '$($command.id)' is mapped '$($rule.status)' but psfdx runs it (" + ($owners -join ', ') + '); the report treats it as run by psfdx.')
                    $reason = $null
                }
            }
        } elseif ($rule) {
            $status = [string]$rule.status
            if ($status -in 'wrapped', 'partially wrapped') {
                $warnings.Add("Command '$($command.id)' is mapped '$status' but no psfdx function runs it; the report shows it as missing.")
                $status = 'missing'
                $reason = $null
            }
        }
        $topic = ($command.id -split ' ')[0]
        $rows.Add([pscustomobject][ordered]@{
                id             = $command.id
                topic          = $topic
                plugin         = $command.plugin
                pluginType     = $command.pluginType
                state          = $command.state
                summary        = $command.summary
                status         = $status
                reason         = $reason
                issue          = $issue
                psfdx          = @($owners | ForEach-Object {
                        $f = $functionByName[$_]
                        $label = $_
                        if ($f -and -not $f.Exported) { $label = $_ + ' (internal)' }
                        $label
                    })
                uncoveredFlags = $uncovered
            })
    }

    # Capabilities: one per topic, in label order. A topic without a label gets its own name.
    $capabilityNames = @{}
    foreach ($p in $Mapping.capabilities.PSObject.Properties) { $capabilityNames[$p.Name] = [string]$p.Value }
    $groups = @($rows.ToArray() | Group-Object { $_.topic } | Sort-ParityObject { $_.Name })
    $capabilities = New-Object System.Collections.Generic.List[object]
    foreach ($group in $groups) {
        $label = $group.Name
        if ($capabilityNames.ContainsKey($group.Name)) { $label = $capabilityNames[$group.Name] }
        $capabilities.Add([pscustomobject][ordered]@{
                topic    = $group.Name
                label    = $label
                totals   = Get-ParityTotals -Rows @($group.Group)
                commands = @($group.Group | Sort-ParityObject { $_.id })
            })
    }

    $allRows = $rows.ToArray()
    $coreRows = @($allRows | Where-Object { $_.pluginType -eq 'core' })
    $jitRows = @($allRows | Where-Object { $_.pluginType -ne 'core' })

    # Exported cmdlets that never run `sf` themselves (they call other psfdx cmdlets) are conveniences, not extra CLI coverage.
    $direct = @{}
    foreach ($key in $usage.Keys) { foreach ($owner in $usage[$key]) { $direct[$owner] = $true } }
    # psfdx-shared exports internal helpers (Invoke-Salesforce and friends), not cmdlets a user runs, so they are not counted here.
    $exportedFunctions = @($Scan.Functions | Where-Object { $_.Exported -and $_.Module -ne 'psfdx-shared' })
    $runs = @{}
    foreach ($f in $exportedFunctions) {
        if ($direct.ContainsKey($f.Name)) { $runs[$f.Name] = $true; continue }
        foreach ($called in $f.Calls) {
            # A private helper in the same file that runs the CLI counts; another exported cmdlet does not (that makes this one a convenience).
            if ($direct.ContainsKey($called) -and $functionByName.ContainsKey($called) -and (-not $functionByName[$called].Exported) -and $functionByName[$called].File -eq $f.File) { $runs[$f.Name] = $true }
        }
    }
    $conveniences = @($exportedFunctions | Where-Object { -not $runs.ContainsKey($_.Name) } | ForEach-Object { $_.Name } | Sort-ParityObject)

    return [pscustomobject][ordered]@{
        schema       = 1
        cli          = [pscustomobject][ordered]@{ version = $Inventory.cliVersion; commandCount = $commands.Count; plugins = @($Inventory.plugins) }
        scope        = [string]$Mapping.scope
        totals       = [pscustomobject][ordered]@{
            all  = Get-ParityTotals -Rows $allRows
            core = Get-ParityTotals -Rows $coreRows
            jit  = Get-ParityTotals -Rows $jitRows
        }
        psfdx        = [pscustomobject][ordered]@{
            exportedFunctions        = $exportedFunctions.Count
            runningTheCli            = $runs.Count
            withoutADirectCliCommand = $conveniences
        }
        capabilities = $capabilities.ToArray()
        aliasUse     = @($aliasUse.ToArray() | Sort-ParityObject { $_.alias + '|' + $_.function })
        crossCutting = [pscustomobject][ordered]@{
            flags = @($script:ParityGlobalFlags | ForEach-Object {
                    $flag = $_
                    $passed = @($Scan.Functions | Where-Object { $_.Flags -contains $flag }).Count
                    $usedWith = @($commands | Where-Object { $usage.ContainsKey($_.id) -and @($_.flags | Where-Object { $_.name -eq $flag }).Count -gt 0 }).Count
                    [pscustomobject][ordered]@{ flag = $flag; psfdxFunctionsPassingIt = $passed; commandsPsfdxRunsThatHaveIt = $usedWith }
                })
        }
        unresolved   = @($unresolved.ToArray() | Sort-ParityObject { $_.words + '|' + $_.function })
        warnings     = @($warnings.ToArray() | Sort-ParityObject)
    }
}

function Get-ParityTotals {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]] $Rows
    )

    $count = { param($s) @($Rows | Where-Object { $_.status -eq $s }).Count }
    $wrapped = & $count 'wrapped'
    $partial = & $count 'partially wrapped'
    $missing = & $count 'missing'
    $excluded = & $count 'deliberately excluded'
    $notApplicable = & $count 'not applicable'
    $inScope = $Rows.Count - $excluded - $notApplicable
    $percent = $null
    # A string with one decimal, so the JSON is the same in Windows PowerShell 5.1 and 7 (they disagree whether 100.0 is a number or a whole number).
    if ($inScope -gt 0) { $percent = ([math]::Round((($wrapped + $partial) * 100.0) / $inScope, 1, [System.MidpointRounding]::AwayFromZero)).ToString('0.0', [cultureinfo]::InvariantCulture) }
    return [pscustomobject][ordered]@{
        commands         = $Rows.Count
        wrapped          = $wrapped
        partiallyWrapped = $partial
        missing          = $missing
        excluded         = $excluded
        notApplicable    = $notApplicable
        inScope          = $inScope
        coveredPercent   = $percent
    }
}

function ConvertTo-ParityMarkdown {
    # Renders the report as the Markdown page linked from the README.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)] $Report
    )

    $nl = "`n"
    $cell = { param($t) ([string]$t) -replace '\|', '\|' -replace "[`r`n]+", ' ' }
    $pct = { param($t) if ($null -eq $t.coveredPercent) { 'n/a' } else { ($t.coveredPercent + '%') } }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('# Salesforce CLI to psfdx parity' + $nl + $nl)
    [void]$sb.Append('<!-- Generated by scripts/parity/New-CliParityReport.ps1. Do not edit by hand: change docs/cli-parity-mapping.json and regenerate. -->' + $nl + $nl)
    [void]$sb.Append("This report compares the commands of Salesforce CLI **$($Report.cli.version)** (the latest stable release when it was generated) with what psfdx actually runs. It is built from the commands the modules pass to `sf`, not from cmdlet counts or README claims. How to read it and how to regenerate it are at the end." + $nl + $nl)
    [void]$sb.Append('**Scope.** ' + $Report.scope + $nl + $nl)

    [void]$sb.Append('## Summary' + $nl + $nl)
    [void]$sb.Append('| Plugin set | Commands | Wrapped | Partially wrapped | Missing | Deliberately excluded | Not applicable | Covered of in scope |' + $nl)
    [void]$sb.Append('| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |' + $nl)
    foreach ($pair in @(@('Core plugins (bundled with the CLI)', $Report.totals.core), @('Just-in-time plugins (installed on first use)', $Report.totals.jit), @('Both', $Report.totals.all))) {
        $t = $pair[1]
        [void]$sb.Append("| $($pair[0]) | $($t.commands) | $($t.wrapped) | $($t.partiallyWrapped) | $($t.missing) | $($t.excluded) | $($t.notApplicable) | $(& $pct $t) of $($t.inScope) |" + $nl)
    }
    [void]$sb.Append($nl + '"Covered of in scope" is (wrapped + partially wrapped) out of the commands that are neither deliberately excluded nor not applicable. It is only meaningful for the plugin set on its row; a command from a plugin that is not installed is not counted anywhere else.' + $nl + $nl)
    [void]$sb.Append("psfdx exports **$($Report.psfdx.exportedFunctions)** cmdlets; **$($Report.psfdx.runningTheCli)** of them run an `sf` command themselves. The other **$($Report.psfdx.withoutADirectCliCommand.Count)** are conveniences built on those, or run other programs (npm, Jest) or call the REST API directly, and add no CLI coverage of their own." + $nl + $nl)

    [void]$sb.Append('## By capability' + $nl + $nl)
    [void]$sb.Append('| Capability | Commands | Wrapped | Partially wrapped | Missing | Excluded | Not applicable | Covered of in scope |' + $nl)
    [void]$sb.Append('| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |' + $nl)
    foreach ($cap in $Report.capabilities) {
        $t = $cap.totals
        [void]$sb.Append("| $(& $cell $cap.label) (`sf $($cap.topic)`) | $($t.commands) | $($t.wrapped) | $($t.partiallyWrapped) | $($t.missing) | $($t.excluded) | $($t.notApplicable) | $(& $pct $t) of $($t.inScope) |" + $nl)
    }
    [void]$sb.Append($nl)

    [void]$sb.Append('## Not covered' + $nl + $nl)
    [void]$sb.Append('Commands psfdx does not run, grouped by capability. A reason or an issue link means the gap was reviewed; no reason means it has not been decided.' + $nl + $nl)
    foreach ($cap in $Report.capabilities) {
        $gaps = @($cap.commands | Where-Object { $_.status -in 'missing', 'deliberately excluded', 'not applicable' })
        if ($gaps.Count -eq 0) { continue }
        [void]$sb.Append("### $(& $cell $cap.label) (``sf $($cap.topic)``)" + $nl + $nl)
        [void]$sb.Append('| Command | Plugin | Status | Why, or issue |' + $nl + '| :--- | :--- | :--- | :--- |' + $nl)
        foreach ($c in $gaps) {
            $note = ''
            if ($c.reason) { $note = & $cell $c.reason }
            if ($null -ne $c.issue) { if ($note) { $note += ' ' }; $note += "[#$($c.issue)](https://github.com/tonygward/psfdx/issues/$($c.issue))" }
            $state = ''
            if ($c.state -ne 'ga') { $state = " ($($c.state))" }
            [void]$sb.Append("| ``sf $($c.id)``$state | $(& $cell $c.plugin) | $($c.status) | $note |" + $nl)
        }
        [void]$sb.Append($nl)
    }

    [void]$sb.Append('## Covered' + $nl + $nl)
    [void]$sb.Append('Commands psfdx runs, with the cmdlets that run them. "Flags not passed" lists the command''s flags that no psfdx function passes, which is why a command is partially wrapped.' + $nl + $nl)
    foreach ($cap in $Report.capabilities) {
        $done = @($cap.commands | Where-Object { $_.status -in 'wrapped', 'partially wrapped' })
        if ($done.Count -eq 0) { continue }
        [void]$sb.Append("### $(& $cell $cap.label) (``sf $($cap.topic)``)" + $nl + $nl)
        [void]$sb.Append('| Command | Status | psfdx cmdlets | Flags not passed |' + $nl + '| :--- | :--- | :--- | :--- |' + $nl)
        foreach ($c in $done) {
            $names = (@($c.psfdx | ForEach-Object { if ($_ -like '* (internal)') { $_ } else { '`' + $_ + '`' } }) -join ', ')
            $flags = ''
            if (@($c.uncoveredFlags).Count -gt 0) { $flags = ((@($c.uncoveredFlags) | ForEach-Object { '`--' + $_ + '`' }) -join ' ') }
            $note = ''
            if ($c.status -eq 'partially wrapped' -and $c.reason) { $note = ' ' + (& $cell $c.reason) }
            [void]$sb.Append("| ``sf $($c.id)`` | $($c.status) | $names | $flags$note |" + $nl)
        }
        [void]$sb.Append($nl)
    }

    if (@($Report.aliasUse).Count -gt 0) {
        [void]$sb.Append('## Commands psfdx runs by another name' + $nl + $nl)
        [void]$sb.Append('These psfdx functions run a command by an old name (an alias) or with its words in another order. The CLI accepts both today. A deprecated alias prints a warning and may be removed, so moving to the current name is a follow-up for the module (the weekly check in issue 210 is where this is watched).' + $nl + $nl)
        [void]$sb.Append('| psfdx function | Runs | Current command | How | Deprecated |' + $nl + '| :--- | :--- | :--- | :--- | :--- |' + $nl)
        foreach ($a in $Report.aliasUse) {
            $dep = 'no'
            if ($a.deprecated) { $dep = 'yes' }
            [void]$sb.Append("| ``$($a.function)`` | ``sf $($a.alias)`` | ``sf $($a.command)`` | $($a.kind) | $dep |" + $nl)
        }
        [void]$sb.Append($nl)
    }
    if (@($Report.crossCutting.flags).Count -gt 0) {
        [void]$sb.Append('## Flags left out of the per-command view' + $nl + $nl)
        [void]$sb.Append('These flags are on almost every command, so they are not counted against each one. Each is listed once here.' + $nl + $nl)
        [void]$sb.Append('| Flag | psfdx functions that pass it | Commands psfdx runs that have it |' + $nl + '| :--- | ---: | ---: |' + $nl)
        foreach ($c in $Report.crossCutting.flags) { [void]$sb.Append("| ``--$($c.flag)`` | $($c.psfdxFunctionsPassingIt) | $($c.commandsPsfdxRunsThatHaveIt) |" + $nl) }
        [void]$sb.Append($nl)
    }
    if (@($Report.unresolved).Count -gt 0) {
        [void]$sb.Append('## psfdx references that match no CLI command' + $nl + $nl)
        [void]$sb.Append('| Words | Function | Why |' + $nl + '| :--- | :--- | :--- |' + $nl)
        foreach ($u in $Report.unresolved) { [void]$sb.Append("| ``sf $(& $cell $u.words)`` | ``$($u.function)`` | $($u.reason) |" + $nl) }
        [void]$sb.Append($nl)
    }
    if (@($Report.warnings).Count -gt 0) {
        [void]$sb.Append('## Mapping warnings' + $nl + $nl)
        foreach ($w in $Report.warnings) { [void]$sb.Append("- $(& $cell $w)" + $nl) }
        [void]$sb.Append($nl)
    }

    [void]$sb.Append('## How to read this' + $nl + $nl)
    [void]$sb.Append('- **Wrapped:** some psfdx function runs the command and passes every one of its flags (apart from `--json`, `--flags-dir` and `--api-version`, which are reported once). **Partially wrapped:** psfdx runs it but not every flag is exposed; the missing flags are listed, and a reviewed mapping rule can accept that with a reason. Flags are matched by function (the function that builds the command, and the helpers in the same file that it calls), so this is a close estimate, not a proof.' + $nl)
    [void]$sb.Append('- **Missing:** no psfdx function runs it and nobody has decided why. **Deliberately excluded:** reviewed and left out on purpose, with a reason. **Not applicable:** CLI housekeeping or interactive tooling that a PowerShell wrapper has no use for.' + $nl)
    [void]$sb.Append('- **One to many, many to one:** a cmdlet can run several commands (a bulk job and its resume), and a command can be run by several cmdlets; both are shown. A cmdlet that only calls other psfdx cmdlets is a convenience and is not counted as coverage.' + $nl)
    [void]$sb.Append('- **Scope:** the plugin set is what `sf commands` lists for this CLI: the core plugins that ship with it and the just-in-time plugins it installs on first use. Percentages are per plugin set. Plugins you install yourself are not in this report. `Beta` and `preview` commands are counted like the rest and marked.' + $nl)
    [void]$sb.Append('- **Source of truth:** the commands psfdx runs are read from the code; the reviewed classifications are in `docs/cli-parity-mapping.json`. A new CLI command shows up here as missing; it does not fail the build. A mapping that is invalid does.' + $nl + $nl)
    [void]$sb.Append('## Regenerate' + $nl + $nl)
    [void]$sb.Append('```powershell' + $nl)
    [void]$sb.Append('./scripts/parity/New-CliParityReport.ps1                      # offline: rebuilds docs/cli-parity.md and .json from the committed inventory' + $nl)
    [void]$sb.Append('npm install --global @salesforce/cli@latest                  # then, to move to the latest stable CLI:' + $nl)
    [void]$sb.Append('./scripts/parity/New-CliInventorySnapshot.ps1                # rewrites docs/cli-parity-inventory.json from sf commands --json' + $nl)
    [void]$sb.Append('./scripts/parity/New-CliParityReport.ps1' + $nl)
    [void]$sb.Append('```' + $nl + $nl)
    [void]$sb.Append('Only the snapshot step needs the CLI, and none of it needs an org or credentials. A test fails when the committed report does not match the modules, the mapping and the inventory, so regenerate it when you add or change a cmdlet that runs `sf`.' + $nl)
    return $sb.ToString()
}
