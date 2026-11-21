@{
    RootModule = 'psfdx-agentforce.psm1'
    ModuleVersion = '0.8.36'
    CompatiblePSEditions = @('Desktop','Core')
    GUID = '5d0b7e0e-3c1a-4a52-9f0e-6b1f4c7a2d93'
    Author = 'Tony Ward'
    Description = 'Agentforce helpers for the Salesforce CLI agent plugin: agent tests and activation.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Test-SalesforceAgentPlugin',
        'Get-SalesforceAgentTests',
        'Start-SalesforceAgentTest',
        'Get-SalesforceAgentTestResult',
        'Enable-SalesforceAgent',
        'Disable-SalesforceAgent'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
}
