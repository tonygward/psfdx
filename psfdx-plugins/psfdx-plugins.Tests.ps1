<#
Pester unit tests for the psfdx-plugins module

Run with:

pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path . -CI"
#>

# Ensure clean slate and load module locally
Get-Module -Name 'psfdx-plugins' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-plugins.psd1'
Import-Module $moduleManifest -Force | Out-Null

Describe 'psfdx-plugins: plugin management (issues 257 and 273)' {
    InModuleScope 'psfdx-plugins' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
        }

        Context 'installing plugins is previewable and validated' {
            It 'makes no call under -WhatIf for plugin installs and updates' {
                Install-SalesforcePlugin -Name '@salesforce/plugin-agent' -WhatIf | Out-Null
                Update-SalesforcePlugins -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'still runs them when not asked to preview, without a prompt' {
                Install-SalesforcePlugin -Name '@salesforce/plugin-agent' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'plugins|install|@salesforce/plugin-agent' }
            }
            It 'accepts npm names with scope and version, and GitHub URLs' {
                foreach ($name in '@salesforce/plugin-agent', '@salesforce/plugin-agent@1.2.3', 'sfdx-hardis', 'https://github.com/org/repo') {
                    { Install-SalesforcePlugin -Name $name -Confirm:$false } | Should -Not -Throw
                }
            }
            It 'refuses a plugin name that could be read as an option or break the command' {
                foreach ($name in '--force', '-x', 'a b', 'a;b', 'a|b', "a$([char]10)b", 'a$(x)', '', '"x"') {
                    { Install-SalesforcePlugin -Name $name -Confirm:$false } | Should -Throw
                }
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'plugins' {
            It 'uninstalls after confirmation, -NoPrompt skips it, -WhatIf does nothing' {
                Uninstall-SalesforcePlugin -Name @('@salesforce/plugin-agent', 'sfdx-hardis') -ExtendedDetails -NoPrompt | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|uninstall|@salesforce/plugin-agent|sfdx-hardis|--verbose' }
                Uninstall-SalesforcePlugin -Name x -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1
            }
            It 'refuses a plugin name that looks like an option or has a line break' {
                { Uninstall-SalesforcePlugin -Name '--all' -NoPrompt } | Should -Throw
                { Get-SalesforcePluginDetails -Name '--json' } | Should -Throw
                { Get-SalesforcePluginDetails -Name ('a' + "`n") } | Should -Throw
                { Add-SalesforcePluginAllowlist -Name '-x' -NoPrompt } | Should -Throw
                { Test-SalesforcePluginSignature -Npm '--x' } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'throws when sf plugins uninstall fails' {
                Mock Invoke-Salesforce { $global:LASTEXITCODE = 2; 'not installed' }
                { Uninstall-SalesforcePlugin -Name nope -NoPrompt } | Should -Throw -ExpectedMessage '*exited with code 2*not installed*'
            }
            It 'inspects, discovers and verifies as read-only json commands' {
                Get-SalesforcePluginDetails -Name '@salesforce/plugin-agent' -ExtendedDetails | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|inspect|@salesforce/plugin-agent|--verbose|--json' }
                Find-SalesforcePlugins | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|discover|--json' }
                Test-SalesforcePluginSignature -Npm '@salesforce/plugin-agent@latest' -Registry https://registry.npmjs.org | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|trust|verify|--npm|@salesforce/plugin-agent@latest|--registry|https://registry.npmjs.org|--json' }
            }
            It 'reads the bare array that sf plugins inspect prints, and still reports an error result' {
                Mock Invoke-Salesforce { '[{"name":"@salesforce/plugin-agent","version":"1.2.3"}]' }
                $out = @(Get-SalesforcePluginDetails -Name '@salesforce/plugin-agent')
                $out.Count | Should -Be 1
                $out[0].version | Should -Be '1.2.3'
                Mock Invoke-Salesforce { '{"status":1,"message":"plugin not found"}' }
                { Get-SalesforcePluginDetails -Name nope } | Should -Throw -ExpectedMessage '*plugin not found*'
            }
            It 'only accepts an https registry' {
                { Test-SalesforcePluginSignature -Npm a -Registry http://registry.example.com } | Should -Throw -ExpectedMessage '*https*'
                { Test-SalesforcePluginSignature -Npm a -Registry 'registry' } | Should -Throw -ExpectedMessage '*https*'
            }
            It 'resets with its options, asks first, and does nothing under -WhatIf' {
                Reset-SalesforcePlugins -Hard -Reinstall -NoPrompt | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|reset|--hard|--reinstall' }
                Reset-SalesforcePlugins -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1
            }
            It 'lists, adds and removes allowlist entries, one --name each' {
                Get-SalesforcePluginAllowlist | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|trust|allowlist|list|--json' }
                Add-SalesforcePluginAllowlist -Name a, b -NoPrompt | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|trust|allowlist|add|--name|a|--name|b|--json' }
                Remove-SalesforcePluginAllowlist -Name a -NoPrompt | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|trust|allowlist|remove|--name|a|--json' }
                Add-SalesforcePluginAllowlist -Name c -WhatIf | Out-Null
                Remove-SalesforcePluginAllowlist -Name c -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 3
            }
            It 'the install and update cmdlets pass the new flags' {
                Install-SalesforcePlugin -Name '@salesforce/plugin-agent' -Force -Silent -ExtendedDetails -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|install|@salesforce/plugin-agent|--force|--silent|--verbose' }
                Update-SalesforcePlugins -ExtendedDetails -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|update|--verbose' }
            }
        }
    }
}

Describe 'psfdx-plugins module ownership (issue 273)' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        $script:Exports = @((Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'psfdx-plugins.psd1')).FunctionsToExport)
        $script:CoreExports = @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root 'psfdx') 'psfdx.psd1')).FunctionsToExport)
    }
    It 'exports the eleven sf plugins cmdlets' {
        @($script:Exports | Sort-Object) | Should -Be @('Add-SalesforcePluginAllowlist', 'Find-SalesforcePlugins', 'Get-SalesforcePluginAllowlist', 'Get-SalesforcePluginDetails', 'Get-SalesforcePlugins', 'Install-SalesforcePlugin', 'Remove-SalesforcePluginAllowlist', 'Reset-SalesforcePlugins', 'Test-SalesforcePluginSignature', 'Uninstall-SalesforcePlugin', 'Update-SalesforcePlugins')
    }
    It 'exports exactly those from the loaded module, and no helper' {
        $loaded = (Get-Module psfdx-plugins).ExportedFunctions.Keys
        @($loaded | Sort-Object) | Should -Be @($script:Exports | Sort-Object)
        $loaded | Should -Not -Contain 'Invoke-SalesforceText'
    }
    It 'is no longer exported by the core module, which keeps Install-SalesforceCli and Update-SalesforceCli' {
        foreach ($n in $script:Exports) { $script:CoreExports | Should -Not -Contain $n -Because "$n moved to psfdx-plugins" }
        $script:CoreExports | Should -Contain 'Install-SalesforceCli'
        $script:CoreExports | Should -Contain 'Update-SalesforceCli'
    }
    It 'every cmdlet is owned by psfdx-plugins' {
        foreach ($n in $script:Exports) { (Get-Command -Name $n -Module psfdx-plugins).ModuleName | Should -Be 'psfdx-plugins' -Because $n }
    }
}