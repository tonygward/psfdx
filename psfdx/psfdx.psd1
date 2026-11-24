@{
    RootModule = 'psfdx.psm1'
    ModuleVersion = '0.8.60'
    GUID = '2785d2bf-775f-4f2b-9d00-ee98f0163cf0'
    Author = 'Tony Ward'
    Description = 'PowerShell module that wraps Salesforce SFDX command line interface'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop','Core')
    FunctionsToExport = @(
        'Get-SalesforceDateTime',
        # The SOQL converters are public commands. Their code lives in psfdx-shared, which the other modules use too, and the core module exports them.
        'ConvertTo-SalesforceSoqlLiteral',
        'ConvertTo-SalesforceSoqlIdentifier',
        'ConvertTo-SalesforceSoqlDateTime',
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
        'Get-SalesforceDataStorage',
        'Get-SalesforceApiUsage',
        'Get-SalesforceUsers',
        'Get-SalesforceAuthenticatedUser',
        'Get-SalesforceOrgUser',
        'New-SalesforceUser',
        'New-SalesforceUserPassword',
        'Grant-SalesforcePermissionSet',
        'Grant-SalesforcePermissionSetLicense',
        'Get-SalesforceApiVersions',
        'Get-SalesforceLatestApiVersion',
        'Connect-SalesforceApi',
        'Invoke-SalesforceApi',
        'Install-SalesforceCli',
        'Update-SalesforceCli',
        'Get-SalesforceCommunityTemplates',
        'New-SalesforceCommunity',
        'Publish-SalesforceCommunity',
        'Invoke-SalesforceGraphQL',
        'Invoke-SalesforceRestRequest',
        'Invoke-SalesforceDoctor'
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
