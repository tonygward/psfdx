@{
    RootModule = 'psfdx-sandbox.psm1'
    ModuleVersion = '0.8'
    GUID = '0904d3fb-5ee3-4217-b219-559afc4f1ec1'
    Author = 'Tony Ward'
    Description = 'Salesforce Sandbox management helpers for the Salesforce CLI.'
    FunctionsToExport = @(
        'Get-SalesforceSandboxes',
        'New-SalesforceSandbox',
        'Resume-SalesforceSandbox',
        'Get-SalesforceSandboxRefreshStatus',
        'Copy-SalesforceSandbox',
        'Remove-SalesforceSandbox'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
}
