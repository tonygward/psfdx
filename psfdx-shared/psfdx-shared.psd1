@{
    RootModule = 'psfdx-shared.psm1'
    ModuleVersion = '0.8.16'
    GUID = '32273e30-b48e-46a0-a566-a74261704f38'
    Author = 'Tony Ward'
    Description = 'Shared helpers for psfdx PowerShell modules'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop','Core')
    FunctionsToExport = @(
        'Invoke-Salesforce',
        'Show-SalesforceResult',
        'Get-SalesforceErrorMessage',
        'Get-SalesforceDeployFailures',
        'Get-SalesforceTestFailure',
        'Get-SalesforceApexCliTestParams',
        'Get-SalesforceApexTestClassNamesFromPath',
        'Test-SalesforceApexTestReference',
        'ConvertTo-SalesforceCliApexTestParams',
        'Get-PsfdxCommonParameterSplat',
        'ConvertTo-SalesforceSoqlLiteral',
        'ConvertTo-SalesforceSoqlDateTime',
        'ConvertTo-SalesforceSoqlIdentifier'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
}
