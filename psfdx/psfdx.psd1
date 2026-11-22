@{
    RootModule = 'psfdx.psm1'
    ModuleVersion = '0.8.47'
    GUID = '2785d2bf-775f-4f2b-9d00-ee98f0163cf0'
    Author = 'Tony Ward'
    Description = 'PowerShell module that wraps Salesforce SFDX command line interface'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop','Core')
    FunctionsToExport = @(
        'Get-SalesforceDateTime',
        'Connect-Salesforce',
        'Connect-SalesforceAuthUrl',
        'Disconnect-Salesforce',
        'Connect-SalesforceJwt',
        'Open-Salesforce',
        'Get-SalesforceConnections',
        'Repair-SalesforceConnections',
        'Get-SalesforceOrgDetails',
        'Get-SalesforceAuthorizations',
        'Connect-SalesforceAccessToken',
        'Get-SalesforceAlias',
        'Add-SalesforceAlias',
        'Remove-SalesforceAlias',
        'Get-SalesforceLimits',
        'Get-SalesforceSObjectRecordCount',
        'Get-SalesforceDataStorage',
        'Get-SalesforceApiUsage',
        'Select-SalesforceRecords',
        'Get-SalesforceUsers',
        'Get-SalesforceAuthenticatedUser',
        'Get-SalesforceOrgUser',
        'New-SalesforceUser',
        'New-SalesforceUserPassword',
        'Grant-SalesforcePermissionSet',
        'Grant-SalesforcePermissionSetLicense',
        'New-SalesforceRecord',
        'Set-SalesforceRecord',
        'Get-SalesforceRecord',
        'Remove-SalesforceRecord',
        'Upsert-SalesforceRecord',
        'Export-SalesforceTreeData',
        'Import-SalesforceTreeData',
        'Export-SalesforceBulkData',
        'Import-SalesforceBulkData',
        'Update-SalesforceBulkData',
        'Upsert-SalesforceBulkData',
        'Resume-SalesforceBulkJob',
        'Get-SalesforceBulkResult',
        'Get-SalesforceRecordType',
        'Search-SalesforceRecords',
        'New-SalesforceFile',
        'Remove-SalesforceBulkData',
        'Get-SalesforceBulkJobStatus',
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
    PrivateData = @{
        PSData = @{
            Tags = @('Salesforce', 'SalesforceDX', 'sf', 'CLI', 'PSEdition_Desktop', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            ProjectUri = 'https://github.com/tonygward/psfdx'
            LicenseUri = 'https://github.com/tonygward/psfdx/blob/main/LICENSE'
            IconUri = 'https://raw.githubusercontent.com/tonygward/psfdx/main/images/psfdx-logo.png'
        }
    }
}
