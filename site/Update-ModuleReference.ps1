<#
.SYNOPSIS
Writes the command reference of every psfdx module into its page of the website and into docs/reference/<module>.md.
.DESCRIPTION
Imports the repository modules and renders their native Get-Help content, once, as the website command reference and as the GitHub Markdown reference.
Both show the same sections in the same order (see $referenceSections).
With -Check nothing is written; it returns the files that are out of date.
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

function Add-HelpParagraphs([System.Text.StringBuilder] $Builder, [string] $Text, [string] $Class) {
    foreach ($paragraph in ($Text.Trim() -split '\r?\n[ \t]*\r?\n')) {
        [void]$Builder.Append('<p class="' + $Class + '">' + (ConvertTo-HtmlText ($paragraph.Trim() -replace '\s+', ' ')) + '</p>')
    }
}

# The one place that decides which sections a command reference has and in which order. The website and the GitHub Markdown render the same
# sections in this order. There is no NAME section (the command name is the heading) and no Inputs or Outputs section; native Get-Help is unchanged.
# A section a command has nothing for (Parameters of a command with none) is left out.
$referenceSections = @('Synopsis', 'Syntax', 'Description', 'Parameters', 'Salesforce CLI', 'Examples', 'Remarks', 'Related Links')

function Get-CommandModel([System.Management.Automation.FunctionInfo] $Command, [string] $Module) {
    $name = $Command.Name
    $qualifiedName = $Module + '\' + $name
    $help = Get-Help -Name $qualifiedName -Full
    $description, $mapping = ($help.description.Text -join [Environment]::NewLine) -split '(?m)^[ \t]*SALESFORCE CLI[ \t]*\r?$', 2
    if (-not $mapping) { throw "$name has no SALESFORCE CLI section" }
    $cliCommands = @([regex]::Matches($mapping, '(?m)^[ \t]*Command run: (sf [^(\r\n]+)') |
        ForEach-Object { $_.Groups[1].Value.Trim() } | Select-Object -Unique)
    $syntax = @(($help.syntax | Out-String -Width 32767) -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $defaultHelp = Get-Help -Name $qualifiedName | Out-String -Width 32767
    $remarkText = [regex]::Match($defaultHelp, '(?ms)^REMARKS[ \t]*\r?\n(.*)\z').Groups[1].Value.Trim()
    if (-not $remarkText) { throw "Cannot read the native remarks for $name. Run the generator in an English PowerShell session." }
    $remarks = @(foreach ($line in ($remarkText -split '\r?\n' | Where-Object { $_.Trim() })) {
        # Windows PowerShell lowercases the help invocation and adds a period after the closing quote.
        $line.Trim() -replace '"get-help ', '"Get-Help ' -replace '-examples"\.?$', '-Examples"' -replace '-detailed"\.?$', '-Detailed"' -replace '-full"\.?$', '-Full"' -replace '-online"\.?$', '-Online"'
    })
    $parameters = @(foreach ($parameter in @($help.parameters.parameter | Where-Object { $_.name })) {
        $facts = @($Command.ParameterSets.Parameters | Where-Object { $_.Name -eq $parameter.name })
        $mandatory = @($facts | Where-Object { $_.IsMandatory }).Count
        $flag = ''
        if ($mandatory -gt 0 -and $mandatory -eq $facts.Count) { $flag = ', required' }
        elseif ($mandatory -gt 0) { $flag = ', required in some parameter sets' }
        $type = if ($parameter.type.name -eq 'SwitchParameter') { 'switch' } else { $parameter.type.name }
        [pscustomobject]@{ Name = $parameter.name; Type = $type + $flag; Description = (($parameter.description.Text -join ' ') -replace '\s+', ' ') }
    })
    # Preserve the website terminal example's multiline layout.
    $example = $null
    $sourceExample = @($Command.ScriptBlock.Ast.GetHelpContent().Examples) | Select-Object -First 1
    if ($sourceExample) {
        $split = Split-Example ([string]$sourceExample)
        if ($split.Code.Count -gt 0) { $example = $split }
    }
    $links = @(foreach ($link in $help.relatedLinks.navigationLink) { [pscustomobject]@{ Uri = [string]$link.uri; Text = [string]$link.linkText } })
    return [pscustomobject]@{
        Name = $name; Synopsis = [string]$help.Synopsis; Syntax = $syntax; Description = $description; Parameters = $parameters
        CliCommands = $cliCommands; Example = $example; Remarks = $remarks; Links = $links
    }
}

function ConvertTo-HtmlEntry([object] $Model) {
    $name = $Model.Name
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<details class="cmd" id="' + (ConvertTo-HtmlText $name) + '"><summary><span class="cmd-name">' + (ConvertTo-HtmlText $name) + '</span></summary><div class="cmd-body">')
    foreach ($section in $referenceSections) {
        switch ($section) {
            'Synopsis' {
                [void]$sb.Append('<h4>Synopsis</h4>')
                Add-HelpParagraphs $sb $Model.Synopsis 'cmd-description'
            }
            'Syntax' {
                [void]$sb.Append('<h4>Syntax</h4><pre class="cmd-syntax"><code>' + (($Model.Syntax | ForEach-Object { ConvertTo-HtmlText $_ }) -join [char]10) + '</code></pre>')
            }
            'Description' {
                [void]$sb.Append('<h4>Description</h4>')
                Add-HelpParagraphs $sb $Model.Description 'cmd-description'
            }
            'Parameters' {
                if ($Model.Parameters.Count -gt 0) {
                    [void]$sb.Append('<h4>Parameters</h4><dl class="cmd-params">')
                    foreach ($parameter in $Model.Parameters) {
                        [void]$sb.Append('<dt><code>-' + (ConvertTo-HtmlText $parameter.Name) + '</code> <span class="cmd-type">' + (ConvertTo-HtmlText $parameter.Type) + '</span></dt><dd>' + (ConvertTo-HtmlText $parameter.Description) + '</dd>')
                    }
                    [void]$sb.Append('</dl>')
                }
            }
            'Salesforce CLI' {
                [void]$sb.Append('<h4>Salesforce CLI</h4><div class="cmd-cli">')
                foreach ($cliCommand in $Model.CliCommands) { [void]$sb.Append('<p><code>' + (ConvertTo-HtmlText $cliCommand) + '</code></p>') }
                if ($Model.CliCommands.Count -eq 0) { [void]$sb.Append('<p>No direct Salesforce CLI command.</p>') }
                [void]$sb.Append('</div>')
            }
            'Examples' {
                if ($Model.Example) {
                    [void]$sb.Append('<h4>Examples</h4>' + (Format-ExampleHtml $Model.Example.Code))
                    if ($Model.Example.Description) { [void]$sb.Append('<p class="cmd-example-note">' + (ConvertTo-HtmlText $Model.Example.Description) + '</p>') }
                }
            }
            'Remarks' {
                [void]$sb.Append('<h4>Remarks</h4><ul>')
                foreach ($remark in $Model.Remarks) { [void]$sb.Append('<li>' + (ConvertTo-HtmlText $remark) + '</li>') }
                [void]$sb.Append('</ul>')
            }
            'Related Links' {
                [void]$sb.Append('<h4>Related Links</h4><ul>')
                foreach ($link in $Model.Links) {
                    $uri = ConvertTo-HtmlText $link.Uri
                    $label = if ($link.Text) { ConvertTo-HtmlText $link.Text } else { $uri }
                    if ($uri) { $label = '<a href="' + $uri + '">' + $label + '</a>' }
                    [void]$sb.Append('<li>' + $label + '</li>')
                }
                [void]$sb.Append('</ul>')
            }
        }
    }
    [void]$sb.Append('</div></details>')
    return $sb.ToString()
}

# GitHub Markdown: text that could be read as markup or HTML is escaped; the code blocks are not.
function ConvertTo-MarkdownText([string] $Text) { ($Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;') }

function Format-ExampleMarkdown([string[]] $Code) {
    $out = New-Object System.Collections.Generic.List[string]
    $continues = $false
    foreach ($line in $Code) {
        if ($continues -or $line -match '^\s') { $out.Add('    ' + $line.TrimStart()) } else { $out.Add('PS> ' + $line) }
        $continues = ($line.TrimEnd() -match '(`|\||,|\{|\()$')
    }
    return '```powershell' + "`n" + ($out -join "`n") + "`n" + '```'
}

function ConvertTo-MarkdownEntry([object] $Model) {
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('### ' + $Model.Name)
    foreach ($section in $referenceSections) {
        switch ($section) {
            'Synopsis' {
                $parts.Add('#### Synopsis')
                foreach ($paragraph in ($Model.Synopsis.Trim() -split '\r?\n[ \t]*\r?\n')) { $parts.Add((ConvertTo-MarkdownText ($paragraph.Trim() -replace '\s+', ' '))) }
            }
            'Syntax' {
                $parts.Add('#### Syntax')
                $parts.Add('```powershell' + "`n" + ($Model.Syntax -join "`n") + "`n" + '```')
            }
            'Description' {
                $parts.Add('#### Description')
                foreach ($paragraph in ($Model.Description.Trim() -split '\r?\n[ \t]*\r?\n')) { $parts.Add((ConvertTo-MarkdownText ($paragraph.Trim() -replace '\s+', ' '))) }
            }
            'Parameters' {
                if ($Model.Parameters.Count -gt 0) {
                    $parts.Add('#### Parameters')
                    $parts.Add((($Model.Parameters | ForEach-Object { '- `-' + $_.Name + '` (' + $_.Type + '): ' + (ConvertTo-MarkdownText $_.Description) }) -join "`n"))
                }
            }
            'Salesforce CLI' {
                $parts.Add('#### Salesforce CLI')
                if ($Model.CliCommands.Count -gt 0) { $parts.Add((($Model.CliCommands | ForEach-Object { '- `' + $_ + '`' }) -join "`n")) }
                else { $parts.Add('No direct Salesforce CLI command.') }
            }
            'Examples' {
                if ($Model.Example) {
                    $parts.Add('#### Examples')
                    $parts.Add((Format-ExampleMarkdown $Model.Example.Code))
                    if ($Model.Example.Description) { $parts.Add((ConvertTo-MarkdownText $Model.Example.Description)) }
                }
            }
            'Remarks' {
                $parts.Add('#### Remarks')
                $parts.Add((($Model.Remarks | ForEach-Object { '- ' + (ConvertTo-MarkdownText $_) }) -join "`n"))
            }
            'Related Links' {
                $parts.Add('#### Related Links')
                $parts.Add((($Model.Links | ForEach-Object { if ($_.Uri) { '- <' + $_.Uri + '>' } } | Where-Object { $_ }) -join "`n"))
            }
        }
    }
    return ($parts -join "`n`n")
}

function Build-Entry([System.Management.Automation.FunctionInfo] $Command, [string] $Module) {
    $model = Get-CommandModel $Command $Module
    return [pscustomobject]@{ Name = $model.Name; Html = (ConvertTo-HtmlEntry $model); Markdown = (ConvertTo-MarkdownEntry $model); WithCli = ($model.CliCommands.Count -gt 0) }
}

# Match specific command types first, then broader families. Patterns match the full cmdlet name.
$commandGroups = @{
    'psfdx' = [ordered]@{
        'Authentication and aliases' = '^(Add|Get|Remove)-SalesforceAlias|^(Connect|Disconnect|Open)-Salesforce|Salesforce(AuthenticatedUser|Authorizations|Connections)$'
        'Users and permissions' = 'Salesforce(OrgUser|Users?|UserPassword|PermissionSet(?:License)?)$'
        'SOQL helpers' = '^ConvertTo-SalesforceSoql'
        'APIs' = 'Salesforce(Api.*|LatestApiVersion|GraphQL|RestRequest)$'
        'Experience Cloud' = 'SalesforceCommunity'
        'Tools and org information' = 'Salesforce(Cli|Doctor|File|DateTime|Limits|DataStorage|OrgDetails)$'
    }
    'psfdx-data' = [ordered]@{
        'Records and queries' = 'Salesforce(Records?|RecordType|SObjectRecordCount|File)$'
        'Tree data' = 'SalesforceTreeData$'
        'Bulk API 2.0' = 'SalesforceBulk'
    }
    'psfdx-agentforce' = [ordered]@{
        'Data libraries' = 'SalesforceAgentDataLibrar'
        'MCP servers and assets' = 'SalesforceMcp'
        'Preview and traces' = 'SalesforceAgent(Preview|Trace)'
        'Tests and evaluations' = 'SalesforceAgent(Test|Evaluation)'
        'Agent setup and authoring' = 'SalesforceAgent'
    }
    'psfdx-development' = [ordered]@{
        'Apex' = 'Salesforce(Apex|CodeCoverage)'
        'Code Analyzer' = 'SalesforceCodeAnalyzer'
        'Flow and logic tests' = 'Salesforce(Flow|Logic)'
        'Jest tests' = 'SalesforceJest'
        'Local development servers' = 'Salesforce(LwcDevServer|UiBundleDevServer)'
        'Org shapes and snapshots' = 'Salesforce(OrgShape|OrgSnapshot)'
        'Project configuration' = 'Salesforce(Config|Target|SourceTracking)|^New-SalesforceProject$'
        'Component and template generation' = '^New-Salesforce'
    }
    'psfdx-org' = [ordered]@{
        'Sandboxes' = 'SalesforceSandbox'
        'Scratch Orgs' = 'SalesforceScratchOrg'
    }
    'psfdx-devops' = [ordered]@{
        'Pipelines and stages' = 'SalesforceDevOps(Pipeline|Stage)'
        'Pipeline deployments' = 'SalesforcePipeline(Quick)?Deploy'
        'Projects' = 'SalesforceDevOpsProject'
        'Work items and reviews' = 'SalesforceDevOps(WorkItem|Review)'
        'Promotions and request status' = 'SalesforceDevOps(Promotion|RequestStatus)'
    }
    'psfdx-metadata' = [ordered]@{
        'Deployments' = '^(Deploy|Resume-.*Deploy|Start-.*Deploy|Stop-.*Deploy|Test-.*Deploy|Get-.*Deploy)'
        'Retrieval' = '^Retrieve-|SalesforceRetrievePreview$'
        'Objects, fields and metadata discovery' = '^(Describe|Build)-|Salesforce(MetadataTypeCache|MetadataComponents)$'
        'Metadata generation' = '^New-Salesforce'
        'Source and tracking' = 'Salesforce(MdapiFormat|Source.*|IgnoredFiles)$'
    }
    'psfdx-packages' = [ordered]@{
        'First-generation packages' = 'SalesforceFirstGen|^Convert-SalesforcePackage$'
        'Installation and removal from orgs' = '^(Install|Uninstall)-|Salesforce(PackagesInstalled|Package(Un)?installStatus)$'
        'Push upgrades' = 'SalesforcePushUpgrade'
        'Package versions' = 'SalesforcePackageVersion'
        'Package management' = 'SalesforcePackages?$'
    }
}

function Get-CommandGroup([string] $Module, [string] $Name) {
    $groups = $commandGroups[$Module]
    if ($groups) {
        foreach ($group in $groups.Keys) {
            if ($Name -match $groups[$group]) { return $group }
        }
    }
    return 'Other commands'
}

$config = Get-Content -LiteralPath (Join-Path (Join-Path $Root 'site') 'site.config.json') -Raw | ConvertFrom-Json
$referenceFolder = Join-Path (Join-Path $Root 'docs') 'reference'
$stale = New-Object System.Collections.Generic.List[string]
$summary = @()
$moduleLines = New-Object System.Collections.Generic.List[string]

# Writes a generated text file and records it as stale when it differs. Line endings are not compared, and an existing file keeps its own.
function Write-GeneratedFile([string] $Path, [string] $Text, [string] $Label) {
    $existing = if (Test-Path -LiteralPath $Path) { [System.IO.File]::ReadAllText($Path) } else { $null }
    $crlf = ($null -ne $existing) -and $existing.Contains("`r`n")
    if (($null -eq $existing) -or ($existing.Replace("`r`n", "`n") -ne $Text)) {
        $script:stale.Add($Label)
        if (-not $Check) {
            if ($crlf) { $Text = $Text.Replace("`n", "`r`n") }
            [System.IO.File]::WriteAllText($Path, $Text, $enc)
        }
    }
}

# Internal modules have no page: they export no commands and are not part of the public command surface.
foreach ($module in @(Get-PsfdxModules | Where-Object { $_ -notin @(Get-PsfdxInternalModules) })) {
    $page = Join-Path (Join-Path (Join-Path (Join-Path $Root 'site') 'src') 'modules') (Join-Path $module 'index.html')
    if (-not (Test-Path -LiteralPath $page)) { throw "No website page for $module at $page" }
    $manifest = Join-Path (Join-Path $Root $module) "$module.psd1"
    $loaded = Import-Module -Name $manifest -Scope Local -PassThru -DisableNameChecking
    $exports = (Import-PowerShellDataFile -Path $manifest).FunctionsToExport
    $entries = @(foreach ($name in ($exports | Sort-Object { $_.ToLowerInvariant() })) {
        Build-Entry $loaded.ExportedFunctions[$name] $module
    })
    # One list of sections, shared by the page and the Markdown: command groups in order of first appearance (Group-Object does not promise that order
    # on Windows PowerShell 5.1, and the output must be identical on both editions), or one unnamed section for a short module.
    $sections = New-Object System.Collections.Generic.List[object]
    if (($entries.Count -ge 20 -or $module -eq 'psfdx-org') -and $commandGroups.ContainsKey($module)) {
        $byGroup = @{}
        foreach ($entry in $entries) {
            $groupName = Get-CommandGroup $module $entry.Name
            if (-not $byGroup.ContainsKey($groupName)) {
                $byGroup[$groupName] = New-Object System.Collections.Generic.List[object]
                $sections.Add([pscustomobject]@{ Title = $groupName; Entries = $byGroup[$groupName] })
            }
            $byGroup[$groupName].Add($entry)
        }
    } else {
        $sections.Add([pscustomobject]@{ Title = $null; Entries = $entries })
    }

    # ---- the website page
    $commandList = foreach ($section in $sections) {
        if ($section.Title) {
            '<section class="cmd-group">'
            '<h3>' + (ConvertTo-HtmlText $section.Title) + '</h3>'
            $section.Entries | ForEach-Object { $_.Html }
            '</section>'
        } else {
            $section.Entries | ForEach-Object { $_.Html }
        }
    }
    $fragment = @(
        '<!-- reference:start -->'
        ('<p><a href="/reference/' + $module + '.md" download>Download Markdown</a> &middot; <a href="%GITHUB_URL%/commits/main/docs/reference/' + $module + '.md">Source history on GitHub</a></p>')
        '<div class="cmd-list">'
        $commandList
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

    # ---- the GitHub Markdown: docs/reference/<module>.md, from the same entries in the same order
    $anchor = { param($n) '#' + $n.ToLowerInvariant() }
    $markdown = New-Object System.Collections.Generic.List[string]
    $markdown.Add('# ' + $module + ' command reference')
    $markdown.Add('Generated from the commands'' own help by `site/Update-ModuleReference.ps1`: do not edit it by hand. The same reference is on the website: <' + $config.siteUrl + '/modules/' + $module + '/>. It is part of the `psfdx` package; see the [installation guide](' + $config.githubUrl + '/blob/main/docs/install.md).')
    $markdown.Add("$($entries.Count) commands. Every command also takes the common parameters, such as ``-Verbose``.")
    $markdown.Add('## Commands')
    foreach ($section in $sections) {
        $links = ($section.Entries | ForEach-Object { '[' + $_.Name + '](' + (& $anchor $_.Name) + ')' }) -join ', '
        if ($section.Title) { $markdown.Add('**' + (ConvertTo-MarkdownText $section.Title) + '**: ' + $links) } else { $markdown.Add($links) }
    }
    foreach ($section in $sections) {
        if ($section.Title) { $markdown.Add('## ' + (ConvertTo-MarkdownText $section.Title)) }
        foreach ($entry in $section.Entries) { $markdown.Add($entry.Markdown) }
    }
    if (-not $Check) { $null = New-Item -ItemType Directory -Path $referenceFolder -Force }
    Write-GeneratedFile (Join-Path $referenceFolder "$module.md") (($markdown -join "`n`n") + "`n") "docs/reference/$module.md"

    $description = (Import-PowerShellDataFile -Path $manifest).Description
    $moduleLines.Add('| [' + $module + '](' + $module + '.md) | ' + $entries.Count + ' | ' + (ConvertTo-MarkdownText $description) + ' |')
    $summary += [pscustomobject]@{ Module = $module; Commands = $entries.Count; WithCli = @($entries | Where-Object { $_.WithCli }).Count }
}

# The index of the Markdown reference.
$index = @(
    '# psfdx command reference'
    ''
    'One page for every module, with every command in the same order as on the website (' + $config.siteUrl + '): Synopsis, Syntax, Description, Parameters, Salesforce CLI, Examples, Remarks, Related Links. Generated from the commands'' own help by `site/Update-ModuleReference.ps1`; do not edit by hand.'
    ''
    '| Module | Commands | What it is for |'
    '| :--- | ---: | :--- |'
) + $moduleLines + @('')
Write-GeneratedFile (Join-Path $referenceFolder 'README.md') ($index -join "`n") 'docs/reference/README.md'

if ($Check) { return @($stale) }
$summary | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "Updated $($stale.Count) file(s)."
