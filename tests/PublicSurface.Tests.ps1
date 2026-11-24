# The public command surface of the psfdx suite (issue 284).
#
# Public commands belong to a feature module or to the core module psfdx. psfdx-shared is an internal module: it exports nothing, so none of its helpers is
# discoverable with Get-Command, yet every module still reaches them (each binds them as private functions, see Import-PsfdxSharedModule).
BeforeDiscovery {
    $root = Split-Path -Parent $PSScriptRoot
    . (Join-Path $root 'modules.ps1')
    $script:ModuleCases = @(Get-PsfdxModules | ForEach-Object { @{ Module = $_ } })
}

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:Root 'modules.ps1')
    Get-Module -Name 'psfdx*' -All | ForEach-Object { try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { } }
    # Import in the order a user's session would: the core module first, which loads the rest.
    foreach ($module in @('psfdx-shared') + @(Get-PsfdxModules | Where-Object { $_ -ne 'psfdx-shared' })) {
        Import-Module (Join-Path $script:Root (Join-Path $module "$module.psd1")) -Force -WarningAction SilentlyContinue
    }
    $script:Internal = @(Get-PsfdxInternalModules)
    $script:InternalNames = @()
    foreach ($internal in $script:Internal) {
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:Root $internal) -Filter '*.ps1' | Where-Object { $_.Name -notlike '*.Tests.ps1' }) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $script:InternalNames += @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) | ForEach-Object { $_.Name })
        }
    }
    $script:Exports = @{}
    foreach ($module in Get-PsfdxModules) { $script:Exports[$module] = @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root $module) "$module.psd1")).FunctionsToExport) }
    $script:PublicFromInternal = @($script:Exports['psfdx'] | Where-Object { $_ -in $script:InternalNames })
    $script:Hidden = @($script:InternalNames | Where-Object { $_ -notin $script:PublicFromInternal })
}

Describe 'Public command surface' {
    It 'psfdx-shared is an internal module that exports nothing' {
        $script:Internal | Should -Contain 'psfdx-shared'
        foreach ($internal in $script:Internal) { $script:Exports[$internal].Count | Should -Be 0 -Because "$internal is internal" }
        @(Get-Command -Module psfdx-shared -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'lists no internal helper with Get-Command -Module psfdx*, and none at all as a command by name' {
        $script:Hidden.Count | Should -BeGreaterThan 8 -Because 'the internal helpers were found'
        $listed = @(Get-Command -Module 'psfdx*' | ForEach-Object Name)
        foreach ($name in $script:Hidden) {
            $listed | Should -Not -Contain $name
            @(Get-Command -Name $name -ErrorAction SilentlyContinue).Count | Should -Be 0 -Because "$name is an internal helper"
        }
    }

    It 'shows <Module> commands with exactly the source module that exports them' -ForEach $script:ModuleCases {
        $shown = @(Get-Command -Module $Module -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Function' })
        @($shown | ForEach-Object Name | Sort-Object) -join '|' | Should -Be (@($script:Exports[$Module] | Sort-Object) -join '|')
        foreach ($command in $shown) { $command.Source | Should -Be $Module -Because "$($command.Name) is exported by $Module" }
    }

    It 'gives the public SOQL converters to the core module psfdx, with their help' {
        $script:PublicFromInternal | Should -Not -BeNullOrEmpty
        foreach ($name in 'ConvertTo-SalesforceSoqlLiteral', 'ConvertTo-SalesforceSoqlIdentifier', 'ConvertTo-SalesforceSoqlDateTime') {
            $script:PublicFromInternal | Should -Contain $name
            $command = Get-Command -Name $name
            $command.Source | Should -Be 'psfdx'
            ([string](Get-Help -Name $name).Synopsis).Trim() | Should -Not -BeNullOrEmpty
            @((Get-Help -Name $name -Examples).examples.example).Count | Should -BeGreaterThan 0
        }
        ConvertTo-SalesforceSoqlLiteral -Value "O'Brien" | Should -Be "'O\'Brien'"
    }

    It 'no command name is exported by two modules' {
        $all = @($script:Exports.Keys | ForEach-Object { $script:Exports[$_] })
        @($all | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object Name) | Should -BeNullOrEmpty
        @(Get-Command -Module 'psfdx*' | Where-Object { $_.CommandType -eq 'Function' }).Count | Should -Be $all.Count
    }
}

Describe 'Internal helpers stay usable by the modules' {
    It '<Module> reaches the internal helpers it uses without exporting them' -ForEach @(
        @{ Module = 'psfdx' }, @{ Module = 'psfdx-data' }, @{ Module = 'psfdx-development' }, @{ Module = 'psfdx-devops' }, @{ Module = 'psfdx-logs' },
        @{ Module = 'psfdx-metadata' }, @{ Module = 'psfdx-org' }, @{ Module = 'psfdx-packages' }, @{ Module = 'psfdx-plugins' }, @{ Module = 'psfdx-agentforce' }
    ) {
        $found = & (Get-Module $Module) { param($names) $names | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } } @('Invoke-Salesforce', 'Show-SalesforceResult', 'Get-PsfdxCommonParameterSplat', 'ConvertTo-SalesforceSoqlLiteral')
        @($found).Count | Should -Be 4 -Because "$Module calls these helpers"
        # the private function is the one from psfdx-shared and runs in its scope
        $source = & (Get-Module $Module) { (Get-Command Invoke-Salesforce).ScriptBlock.Module.Name }
        $source | Should -Be 'psfdx-shared'
    }

    It 'the helpers still reach each other: a command of another module runs the shared executor and result handling' {
        $json = '{"status":0,"result":{"ok":true}}'
        Mock Invoke-Salesforce { $json } -ModuleName 'psfdx-logs'
        $result = Get-SalesforceLoginHistory -ErrorAction Stop 2>$null
        Should -Invoke Invoke-Salesforce -ModuleName 'psfdx-logs' -Times 1 -Exactly -Scope It
    }

    It 'resolves the shared module when a feature module is imported on its own after the core module' {
        $manifest = Join-Path $script:Root (Join-Path 'psfdx-logs' 'psfdx-logs.psd1')
        Remove-Module psfdx-logs -Force
        Import-Module $manifest -Force -WarningAction SilentlyContinue
        @(Get-Command -Module psfdx-logs).Count | Should -BeGreaterThan 0
        (& (Get-Module psfdx-logs) { (Get-Command Show-SalesforceResult).ScriptBlock.Module.Name }) | Should -Be 'psfdx-shared'
        @(Get-Command -Name Show-SalesforceResult -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
}
