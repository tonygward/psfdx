<#
.SYNOPSIS
Writes the command reference of every psfdx module into its page of the website.
.DESCRIPTION
Imports the repository modules and renders their native Get-Help content in the website command reference.
With -Check nothing is written; it returns the pages that are out of date.
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

function Build-Entry([System.Management.Automation.FunctionInfo] $Command, [string] $Module) {
    $name = $Command.Name
    $qualifiedName = $Module + '\' + $name
    $help = Get-Help -Name $qualifiedName -Full
    $description, $mapping = ($help.description.Text -join [Environment]::NewLine) -split '(?m)^[ \t]*SALESFORCE CLI[ \t]*\r?$', 2
    if (-not $mapping) { throw "$name has no SALESFORCE CLI section" }
    $syntax = @(($help.syntax | Out-String -Width 32767) -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $defaultHelp = Get-Help -Name $qualifiedName | Out-String -Width 32767
    $remarks = [regex]::Match($defaultHelp, '(?ms)^REMARKS[ \t]*\r?\n(.*)\z').Groups[1].Value.Trim()
    if (-not $remarks) { throw "Cannot read the native remarks for $name. Run the generator in an English PowerShell session." }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<details class="cmd" id="' + (ConvertTo-HtmlText $name) + '"><summary><span class="cmd-name">' + (ConvertTo-HtmlText $name) + '</span></summary><div class="cmd-body">')
    [void]$sb.Append('<h4>Synopsis</h4>')
    Add-HelpParagraphs $sb $help.Synopsis 'cmd-description'
    [void]$sb.Append('<h4>Syntax</h4><pre class="cmd-syntax"><code>' + (($syntax | ForEach-Object { ConvertTo-HtmlText $_ }) -join [char]10) + '</code></pre>')
    [void]$sb.Append('<h4>Description</h4>')
    Add-HelpParagraphs $sb $description 'cmd-description'
    [void]$sb.Append('<h4>Salesforce CLI</h4><div class="cmd-cli">')
    foreach ($line in ($mapping.Trim() -split '\r?\n' | Where-Object { $_.Trim() })) {
        $text = ConvertTo-HtmlText $line.Trim()
        if ($line.Trim() -match '^(Command run: )(sf [^(]+?)([ \t]+\(.*|$)') {
            $text = (ConvertTo-HtmlText $Matches[1]) + '<code>' + (ConvertTo-HtmlText $Matches[2]) + '</code>' + (ConvertTo-HtmlText $Matches[3])
        }
        [void]$sb.Append('<p>' + $text + '</p>')
    }
    [void]$sb.Append('</div><h4>Related links</h4><ul>')
    foreach ($link in $help.relatedLinks.navigationLink) {
        $uri = ConvertTo-HtmlText $link.uri
        $label = if ($link.linkText) { ConvertTo-HtmlText $link.linkText } else { $uri }
        if ($uri) { $label = '<a href="' + $uri + '">' + $label + '</a>' }
        [void]$sb.Append('<li>' + $label + '</li>')
    }
    [void]$sb.Append('</ul><h4>Remarks</h4><ul>')
    foreach ($line in ($remarks -split '\r?\n' | Where-Object { $_.Trim() })) {
        # Windows PowerShell lowercases the help invocation and adds a period after the closing quote.
        $remark = $line.Trim() -replace '"get-help ', '"Get-Help ' -replace '-examples"\.?$', '-Examples"' -replace '-detailed"\.?$', '-Detailed"' -replace '-full"\.?$', '-Full"' -replace '-online"\.?$', '-Online"'
        [void]$sb.Append('<li>' + (ConvertTo-HtmlText $remark) + '</li>')
    }
    [void]$sb.Append('</ul>')

    $parameters = @($help.parameters.parameter | Where-Object { $_.name })
    if ($parameters.Count -gt 0) {
        [void]$sb.Append('<h4>Parameters</h4><dl class="cmd-params">')
        foreach ($parameter in $parameters) {
            $facts = @($Command.ParameterSets.Parameters | Where-Object { $_.Name -eq $parameter.name })
            $mandatory = @($facts | Where-Object { $_.IsMandatory }).Count
            $flag = ''
            if ($mandatory -gt 0 -and $mandatory -eq $facts.Count) { $flag = ', required' }
            elseif ($mandatory -gt 0) { $flag = ', required in some parameter sets' }
            $type = if ($parameter.type.name -eq 'SwitchParameter') { 'switch' } else { $parameter.type.name }
            [void]$sb.Append('<dt><code>-' + (ConvertTo-HtmlText $parameter.name) + '</code> <span class="cmd-type">' + (ConvertTo-HtmlText $type) + $flag + '</span></dt><dd>' + (ConvertTo-HtmlText (($parameter.description.Text -join ' ') -replace '\s+', ' ')) + '</dd>')
        }
        [void]$sb.Append('</dl>')
    }
    # Preserve the website terminal example's multiline layout.
    $sourceHelp = $Command.ScriptBlock.Ast.GetHelpContent()
    $example = @($sourceHelp.Examples) | Select-Object -First 1
    if ($example) {
        $split = Split-Example ([string]$example)
        if ($split.Code.Count -gt 0) {
            [void]$sb.Append('<h4>Example</h4>' + (Format-ExampleHtml $split.Code))
            if ($split.Description) { [void]$sb.Append('<p class="cmd-example-note">' + (ConvertTo-HtmlText $split.Description) + '</p>') }
        }
    }
    [void]$sb.Append('</div></details>')
    return [pscustomobject]@{ Name = $name; Html = $sb.ToString(); WithCli = ($mapping -match '(?m)^\s*Command run: sf ') }
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

$stale = New-Object System.Collections.Generic.List[string]
$summary = @()
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
    $commandList = if (($entries.Count -ge 20 -or $module -eq 'psfdx-org') -and $commandGroups.ContainsKey($module)) {
        # Group in order of first appearance. Group-Object does not promise that order on Windows PowerShell 5.1, and the pages must be identical on both editions.
        $groupNames = New-Object System.Collections.Generic.List[string]
        $byGroup = @{}
        foreach ($entry in $entries) {
            $groupName = Get-CommandGroup $module $entry.Name
            if (-not $byGroup.ContainsKey($groupName)) { $byGroup[$groupName] = New-Object System.Collections.Generic.List[object]; $groupNames.Add($groupName) }
            $byGroup[$groupName].Add($entry)
        }
        foreach ($groupName in $groupNames) {
            '<section class="cmd-group">'
            '<h3>' + (ConvertTo-HtmlText $groupName) + '</h3>'
            $byGroup[$groupName] | ForEach-Object { $_.Html }
            '</section>'
        }
    } else {
        $entries | ForEach-Object { $_.Html }
    }
    $fragment = @(
        '<!-- reference:start -->'
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
    $summary += [pscustomobject]@{ Module = $module; Commands = $entries.Count; WithCli = @($entries | Where-Object { $_.WithCli }).Count }
}
if ($Check) { return @($stale) }
$summary | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "Updated $($stale.Count) page(s)."
