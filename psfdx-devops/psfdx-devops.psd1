@{
    RootModule = 'psfdx-devops.psm1'
    ModuleVersion = '0.8.54'
    GUID = '730e3596-f750-4d8a-aa3a-26835fe3a8e9'
    Author = 'Tony Ward'
    Description = 'Salesforce DevOps Center helpers for the Salesforce CLI: projects, work items, pipelines, stages, branches, environments, promotion, and the beta pipeline deploy commands.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop','Core')
    FunctionsToExport = @(
        'Start-SalesforcePipelineDeploy',
        'Test-SalesforcePipelineDeploy',
        'Start-SalesforcePipelineQuickDeploy',
        'Get-SalesforcePipelineDeployStatus',
        'Resume-SalesforcePipelineDeploy',
        'Get-SalesforceDevOpsProject',
        'New-SalesforceDevOpsProject',
        'Update-SalesforceDevOpsProject',
        'Get-SalesforceDevOpsWorkItem',
        'New-SalesforceDevOpsWorkItem',
        'Update-SalesforceDevOpsWorkItem',
        'Initialize-SalesforceDevOpsWorkItem',
        'Join-SalesforceDevOpsWorkItem',
        'New-SalesforceDevOpsReview',
        'Get-SalesforceDevOpsPipeline',
        'Get-SalesforceDevOpsPipelineDetails',
        'New-SalesforceDevOpsPipeline',
        'Update-SalesforceDevOpsPipeline',
        'Add-SalesforceDevOpsPipelineProject',
        'Remove-SalesforceDevOpsPipelineProject',
        'Add-SalesforceDevOpsPipelineStage',
        'Update-SalesforceDevOpsPipelineStage',
        'Remove-SalesforceDevOpsPipelineStage',
        'Add-SalesforceDevOpsStageBranch',
        'Remove-SalesforceDevOpsStageBranch',
        'Add-SalesforceDevOpsStageEnvironment',
        'Remove-SalesforceDevOpsStageEnvironment',
        'Start-SalesforceDevOpsPromotion',
        'Complete-SalesforceDevOpsPromotion',
        'Test-SalesforceDevOpsPromotion',
        'Get-SalesforceDevOpsRequestStatus'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
}
