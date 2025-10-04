@{
    RootModule = 'psfdx-shared.psm1'
    ModuleVersion = '1.0.0'
    GUID = '32273e30-b48e-46a0-a566-a74261704f38'
    Author = 'Tony Ward'
    Description = 'Shared helpers for psfdx PowerShell modules'
    FunctionsToExport = @(
        'Invoke-Salesforce',
        'Show-SalesforceResult',
        'Get-SalesforceErrorMessage',
        'Get-SalesforceDeployFailures',
        'Get-SalesforceTestFailure',
        'Get-SalesforceApexCliTestParams',
        'ConvertTo-SalesforceCliApexTestParams'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
}
