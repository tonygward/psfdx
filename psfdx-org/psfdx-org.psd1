@{
    RootModule = 'psfdx-org.psm1'
    ModuleVersion = '0.8.57'
    GUID = '0904d3fb-5ee3-4217-b219-559afc4f1ec1'
    Author = 'Tony Ward'
    Description = 'Salesforce org lifecycle helpers for the Salesforce CLI: sandboxes and scratch orgs.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop','Core')
    FunctionsToExport = @(
        'Get-SalesforceSandboxes',
        'New-SalesforceSandbox',
        'Resume-SalesforceSandbox',
        'Get-SalesforceSandboxRefreshStatus',
        'Copy-SalesforceSandbox',
        'Remove-SalesforceSandbox',
        'Update-SalesforceSandbox',
        'Get-SalesforceScratchOrgs',
        'New-SalesforceScratchOrg',
        'Resume-SalesforceScratchOrg',
        'Remove-SalesforceScratchOrg',
        'Remove-SalesforceScratchOrgs'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
}
