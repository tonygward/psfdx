<#
.SYNOPSIS
Writes the command reference of every psfdx module into its page of the website.
.DESCRIPTION
Reads the comment-based help and the parameter block of every command each module exports, which is exactly what Get-Help reads, and fills the part of
site/src/modules/<module>/index.html between <!-- reference:start --> and <!-- reference:end --> with an alphabetical linked index and one compact,
expandable entry per command: its synopsis, syntax (one line per parameter set), parameters, a practical example with the PS> prompt, and the Salesforce CLI
command it runs. Nothing is typed by hand and nothing is invented: a command appears under the module that exports it, with the text of its own help.
The result is the same on Windows PowerShell 5.1 and PowerShell 7 (it parses the source and does not load the modules), so a Pester test can fail when a page
is stale. With -Check nothing is written; it returns the pages that are out of date.
Run it after changing a command, its help, or which module exports it:  pwsh ./site/Update-ModuleReference.ps1
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)][string] $Root,
    [Parameter(Mandatory = $false)][switch] $Check
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
. (Join-Path $Root 'modules.ps1')
$enc = New-Object System.Text.UTF8Encoding($false)
function ConvertTo-HtmlText([string] $Text) { [System.Net.WebUtility]::HtmlEncode($Text) }

function Get-TypeText([System.Management.Automation.Language.ParameterAst] $Parameter) {
    $constraint = @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.Language.TypeConstraintAst] }) | Select-Object -First 1
    if (-not $constraint) { return 'object' }
    $name = $constraint.TypeName.FullName
    return ($name -replace '^System\.Management\.Automation\.', '' -replace '^System\.(Collections\.)?(Generic\.)?', '')
}

# What each [Parameter()] attribute of a parameter says: the set it belongs to (empty = every set) and whether it is mandatory there.
function Get-ParameterFacts([System.Management.Automation.Language.ParameterAst] $Parameter) {
    $facts = @()
    foreach ($attribute in @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.Language.AttributeAst] -and $_.TypeName.Name -eq 'Parameter' })) {
        $set = ''; $mandatory = $false
        foreach ($arg in $attribute.NamedArguments) {
            if ($arg.ArgumentName -eq 'ParameterSetName') { $set = $arg.Argument.Extent.Text.Trim("'", '"') }
            if ($arg.ArgumentName -eq 'Mandatory') { $mandatory = ($arg.Argument.Extent.Text -match '^\$true$') }
        }
        $facts += [pscustomobject]@{ Set = $set; Mandatory = $mandatory }
    }
    if ($facts.Count -eq 0) { $facts += [pscustomobject]@{ Set = ''; Mandatory = $false } }
    return $facts
}

function Format-SyntaxLine([string] $Name, [object[]] $Items) {
    $parts = @($Name)
    foreach ($item in $Items) {
        if ($item.Type -eq 'switch') { $text = "-$($item.Name)" } else { $text = "-$($item.Name) <$($item.Type)>" }
        if ($item.Mandatory) { $parts += $text } else { $parts += "[$text]" }
    }
    return ($parts -join ' ')
}

# Trailing lines that read as a sentence are the description of an example; everything before them is code.
function Split-Example([string] $Text) {
    $lines = @(($Text -split "`r?`n") | ForEach-Object { $_.TrimEnd() })
    while ($lines.Count -gt 0 -and -not $lines[-1].Trim()) { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
    while ($lines.Count -gt 0 -and -not $lines[0].Trim()) { $lines = @($lines | Select-Object -Skip 1) }
    $isProse = { param($l) ($l.Trim() -match '^[A-Z][a-z]+ ') -and ($l.Trim() -match '[.:)]$') -and ($l.Trim().Split(' ')[0] -notmatch '-') }
    $desc = New-Object System.Collections.Generic.List[string]
    while ($lines.Count -gt 1 -and (& $isProse $lines[-1])) { $desc.Insert(0, $lines[-1].Trim()); $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
    return [pscustomobject]@{ Code = @($lines | Where-Object { $_.Trim() }); Description = ($desc -join ' ') }
}

function Format-ExampleHtml([string[]] $Code) {
    $out = New-Object System.Collections.Generic.List[string]
    $continues = $false
    foreach ($line in $Code) {
        if ($continues -or $line -match '^\s') { $out.Add('<span class="terminal-line terminal-continuation">' + (ConvertTo-HtmlText $line.TrimStart()) + '</span>') }
        else { $out.Add('<span class="terminal-line"><span class="ps-prompt">PS&gt;</span> ' + (ConvertTo-HtmlText $line) + '</span>') }
        $continues = ($line.TrimEnd() -match '(`|\||,|\{|\()$')
    }
    return '<div class="code-box terminal-example"><pre><code>' + ($out -join "`n") + '</code></pre></div>'
}

function Get-CliCommands([string] $Notes) {
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($Notes, '(?m)^\s*Command run: (sf [^\r\n(]*?)\s*(?:\(plugin[^\r\n]*)?$')) {
        $c = $m.Groups[1].Value.Trim()
        if ($c -and -not $found.Contains($c)) { $found.Add($c) }
    }
    return @($found)
}

function Get-Commands([string] $Module) {
    $files = @()
    if ($Module -eq 'psfdx-shared') { $files = @(Get-ChildItem -LiteralPath (Join-Path $Root $Module) -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' }) }
    else { $files = @(Get-Item -LiteralPath (Join-Path (Join-Path $Root $Module) "$Module.psm1")) }
    $exports = @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $Root $Module) "$Module.psd1")).FunctionsToExport)
    $found = @{}
    foreach ($file in $files) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
        foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
            if ($f.Name -in $exports) { $found[$f.Name] = $f }
        }
    }
    foreach ($name in $exports) { if (-not $found.ContainsKey($name)) { throw "$Module exports $name but no function of that name was found" } }
    return @($exports | Sort-Object { $_.ToLowerInvariant() } | ForEach-Object { $found[$_] })
}

function Build-Entry([System.Management.Automation.Language.FunctionDefinitionAst] $Function) {
    $name = $Function.Name
    $help = $Function.GetHelpContent()
    if (-not $help -or -not $help.Synopsis) { throw "$name has no help synopsis" }
    $parameters = @()
    if ($Function.Body.ParamBlock) { $parameters = @($Function.Body.ParamBlock.Parameters) }
    $items = @()
    foreach ($p in $parameters) {
        $pname = $p.Name.VariablePath.UserPath
        $items += [pscustomobject]@{ Name = $pname; Type = (Get-TypeText $p); Facts = @(Get-ParameterFacts $p) }
    }
    # one syntax line per parameter set (parameters with no set belong to every set); a command with no sets has one line
    $sets = @($items | ForEach-Object { $_.Facts } | ForEach-Object { $_.Set } | Where-Object { $_ } | Select-Object -Unique)
    $syntax = @()
    if ($sets.Count -eq 0) { $sets = @('') }
    foreach ($set in $sets) {
        $rows = @()
        foreach ($item in $items) {
            $fact = @($item.Facts | Where-Object { $_.Set -eq $set -or $_.Set -eq '' }) | Select-Object -First 1
            if (-not $fact) { continue }
            $rows += [pscustomobject]@{ Name = $item.Name; Type = $item.Type; Mandatory = $fact.Mandatory }
        }
        # required parameters first, as Get-Command -Syntax lists them, then the optional ones in declaration order
        $rows = @(@($rows | Where-Object { $_.Mandatory }) + @($rows | Where-Object { -not $_.Mandatory }))
        $syntax += (Format-SyntaxLine $name $rows)
    }
    $syntax = @($syntax | Select-Object -Unique)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<details class="cmd" id="' + (ConvertTo-HtmlText $name) + '"><summary><span class="cmd-name">' + (ConvertTo-HtmlText $name) + '</span> <span class="cmd-synopsis">' + (ConvertTo-HtmlText ($help.Synopsis.Trim() -replace '\s+', ' ')) + '</span></summary><div class="cmd-body">')
    [void]$sb.Append('<h4>Syntax</h4><pre class="cmd-syntax"><code>' + (($syntax | ForEach-Object { ConvertTo-HtmlText $_ }) -join "`n") + '</code></pre>')
    if ($items.Count -gt 0) {
        [void]$sb.Append('<h4>Parameters</h4><dl class="cmd-params">')
        foreach ($item in $items) {
            $text = ''
            foreach ($key in $help.Parameters.Keys) { if ($key -eq $item.Name.ToUpperInvariant()) { $text = ([string]$help.Parameters[$key]).Trim() } }
            $allMandatory = (@($item.Facts | Where-Object { -not $_.Mandatory }).Count -eq 0)
            $anyMandatory = (@($item.Facts | Where-Object { $_.Mandatory }).Count -gt 0)
            $flag = ''
            if ($allMandatory) { $flag = ', required' } elseif ($anyMandatory) { $flag = ', required in some parameter sets' }
            $typeText = if ($item.Type -eq 'switch') { 'switch' } else { $item.Type }
            [void]$sb.Append('<dt><code>-' + (ConvertTo-HtmlText $item.Name) + '</code> <span class="cmd-type">' + (ConvertTo-HtmlText $typeText) + $flag + '</span></dt><dd>' + (ConvertTo-HtmlText ($text -replace '\s+', ' ')) + '</dd>')
        }
        [void]$sb.Append('</dl>')
    }
    $example = @($help.Examples) | Select-Object -First 1
    if ($example) {
        $split = Split-Example ([string]$example)
        if ($split.Code.Count -gt 0) {
            [void]$sb.Append('<h4>Example</h4>' + (Format-ExampleHtml $split.Code))
            if ($split.Description) { [void]$sb.Append('<p class="cmd-example-note">' + (ConvertTo-HtmlText $split.Description) + '</p>') }
        }
    }
    $cli = @(Get-CliCommands ([string]$help.Notes))
    if ($cli.Count -gt 0) { [void]$sb.Append('<h4>Salesforce CLI</h4><p class="cmd-cli">Runs ' + (($cli | ForEach-Object { '<code>' + (ConvertTo-HtmlText $_) + '</code>' }) -join ', ') + '.</p>') }
    [void]$sb.Append('</div></details>')
    return [pscustomobject]@{ Name = $name; Html = $sb.ToString(); Cli = $cli }
}

$stale = New-Object System.Collections.Generic.List[string]
$summary = @()
foreach ($module in Get-PsfdxModules) {
    $page = Join-Path (Join-Path (Join-Path (Join-Path $Root 'site') 'src') 'modules') (Join-Path $module 'index.html')
    if (-not (Test-Path -LiteralPath $page)) { throw "No website page for $module at $page" }
    $entries = @(Get-Commands $module | ForEach-Object { Build-Entry $_ })
    $index = ($entries | ForEach-Object { '<li><a href="#' + (ConvertTo-HtmlText $_.Name) + '">' + (ConvertTo-HtmlText $_.Name) + '</a></li>' }) -join "`n"
    $fragment = @(
        '<!-- reference:start -->'
        "<p class=""ref-note"">$($entries.Count) commands, in alphabetical order. Each entry is generated from the command's own help, so it matches <code>Get-Help &lt;command&gt; -Full</code>. Every command also takes the common parameters, such as <code>-Verbose</code>.</p>"
        '<nav aria-label="Command index"><ul class="cmd-index">'
        $index
        '</ul></nav>'
        '<div class="cmd-list">'
        (($entries | ForEach-Object { $_.Html }) -join "`n")
        '</div>'
        '<!-- reference:end -->'
    ) -join "`n"

    $raw = [System.IO.File]::ReadAllText($page)
    $crlf = $raw.Contains("`r`n")
    $text = $raw.Replace("`r`n", "`n")
    $start = $text.IndexOf('<!-- reference:start -->')
    $end = $text.IndexOf('<!-- reference:end -->')
    if ($start -lt 0 -or $end -lt $start) { throw "$page has no reference:start / reference:end markers" }
    $new = $text.Substring(0, $start) + $fragment + $text.Substring($end + '<!-- reference:end -->'.Length)
    if ($new -ne $text) {
        $stale.Add($module)
        if (-not $Check) {
            if ($crlf) { $new = $new.Replace("`n", "`r`n") }
            [System.IO.File]::WriteAllText($page, $new, $enc)
        }
    }
    $summary += [pscustomobject]@{ Module = $module; Commands = $entries.Count; WithCli = @($entries | Where-Object { $_.Cli.Count -gt 0 }).Count }
}
if ($Check) { return @($stale) }
$summary | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "Updated $($stale.Count) page(s)."
