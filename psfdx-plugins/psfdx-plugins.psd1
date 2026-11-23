@{
    RootModule = 'psfdx-plugins.psm1'
    ModuleVersion = '0.8.57'
    GUID = 'c48c6804-def7-438a-91d4-45ba4d5cb01a'
    Author = 'Tony Ward'
    Description = 'Salesforce CLI plugin management for PowerShell: install, list, inspect, update, uninstall, discover and reset plugins, verify plugin signatures, and manage the plugin allowlist.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop','Core')
    FunctionsToExport = @(
        'Install-SalesforcePlugin',
        'Get-SalesforcePlugins',
        'Update-SalesforcePlugins',
        'Uninstall-SalesforcePlugin',
        'Get-SalesforcePluginDetails',
        'Find-SalesforcePlugins',
        'Reset-SalesforcePlugins',
        'Test-SalesforcePluginSignature',
        'Get-SalesforcePluginAllowlist',
        'Add-SalesforcePluginAllowlist',
        'Remove-SalesforcePluginAllowlist'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
}
