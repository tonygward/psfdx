@{
    RootModule = 'psfdx-agentforce.psm1'
    ModuleVersion = '0.8.62'
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
        'Disable-SalesforceAgent',
        'New-SalesforceAgentAuthoringBundle',
        'Test-SalesforceAgentAuthoringBundle',
        'Publish-SalesforceAgentAuthoringBundle',
        'New-SalesforceAgentUser',
        'Open-SalesforceAgent',
        'New-SalesforceAgent',
        'New-SalesforceAgentSpec',
        'New-SalesforceAgentTemplate',
        'New-SalesforceAgentTestSpec',
        'New-SalesforceAgentTest',
        'Resume-SalesforceAgentTest',
        'Start-SalesforceAgentEvaluation',
        'Start-SalesforceAgentPreview',
        'Send-SalesforceAgentPreviewMessage',
        'Stop-SalesforceAgentPreview',
        'Get-SalesforceAgentPreviewSessions',
        'Invoke-SalesforceAgentPreview',
        'Get-SalesforceAgentTraces',
        'Read-SalesforceAgentTrace',
        'Remove-SalesforceAgentTrace',
        'New-SalesforceAgentDataLibrary',
        'Get-SalesforceAgentDataLibraries',
        'Get-SalesforceAgentDataLibrary',
        'Get-SalesforceAgentDataLibraryStatus',
        'Update-SalesforceAgentDataLibrary',
        'Remove-SalesforceAgentDataLibrary',
        'Get-SalesforceAgentDataLibraryFiles',
        'Add-SalesforceAgentDataLibraryFile',
        'Remove-SalesforceAgentDataLibraryFile',
        'Send-SalesforceAgentDataLibraryFile',
        'New-SalesforceMcpServer',
        'Update-SalesforceMcpServer',
        'Remove-SalesforceMcpServer',
        'Get-SalesforceMcpServer',
        'Get-SalesforceMcpServers',
        'Get-SalesforceMcpAssets',
        'Get-SalesforceMcpServerLiveAssets',
        'Set-SalesforceMcpAssets'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
}
