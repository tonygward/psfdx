@{
    RootModule = 'psfdx.psm1'
    ModuleVersion = '0.8'
    GUID = '2785d2bf-775f-4f2b-9d00-ee98f0163cf0'
    Author = 'Tony Ward'
    Description = 'PowerShell module that wraps Salesforce SFDX command line interface'
    FunctionsToExport = @(
        'Get-SalesforceDateTime',
        'Connect-Salesforce',
        'Connect-SalesforceAuthUrl',
        'Disconnect-Salesforce',
        'Connect-SalesforceJwt',
        'Open-Salesforce',
        'Get-SalesforceConnections',
        'Repair-SalesforceConnections',
        'Get-SalesforceAlias',
        'Add-SalesforceAlias',
        'Remove-SalesforceAlias',
        'Get-SalesforceLimits',
        'Get-SalesforceDataStorage',
        'Get-SalesforceApiUsage',
        'Select-SalesforceRecords',
        'Get-SalesforceUsers',
        'New-SalesforceRecord',
        'Set-SalesforceRecord',
        'Get-SalesforceRecordType',
        'Get-SalesforceApiVersions',
        'Get-SalesforceLatestApiVersion',
        'Connect-SalesforceApi',
        'Invoke-SalesforceApi',
        'Install-SalesforceCli',
        'Update-SalesforceCli',
        'Install-SalesforcePlugin',
        'Get-SalesforcePlugins',
        'Update-SalesforcePlugins'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
}
