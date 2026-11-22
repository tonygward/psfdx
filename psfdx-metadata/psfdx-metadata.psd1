@{
    RootModule            = 'psfdx-metadata.psm1'
    ModuleVersion         = '0.8.47'
    CompatiblePSEditions  = @('Desktop','Core')
    GUID                  = 'e0c7c8c3-0f5f-4662-a9e1-2c3c5a1c7f20'
    Author                = 'Tony Ward'
    CompanyName           = 'psfdx'
    Copyright            = 'Copyright (c) psfdx contributors.'
    Description           = 'PowerShell helpers for retrieving, deploying, and describing Salesforce metadata.'
    PowerShellVersion     = '5.1'
    RequiredModules       = @()
    RequiredAssemblies    = @()
    ScriptsToProcess      = @()
    TypesToProcess        = @()
    FormatsToProcess      = @()
    FunctionsToExport     = @(
        'Retrieve-SalesforceOrg',
        'Retrieve-SalesforceComponent',
        'Retrieve-SalesforceMetadata',
        'Retrieve-SalesforcePackage',
        'Retrieve-SalesforceField',
        'Retrieve-SalesforceValidationRule',
        'Deploy-SalesforceComponent',
        'Deploy-SalesforceMetadata',
        'Test-SalesforceDeploy',
        'Start-SalesforceQuickDeploy',
        'Get-SalesforceDeployStatus',
        'Resume-SalesforceDeploy',
        'Get-SalesforceDeployPreview',
        'Get-SalesforceRetrievePreview',
        'Stop-SalesforceDeploy',
        'Describe-SalesforceObjects',
        'Describe-SalesforceObject',
        'Describe-SalesforceFields',
        'Describe-SalesforceMetadataTypes',
        'Get-SalesforceMetadataComponents',
        'New-SalesforceCustomMetadataType',
        'New-SalesforceCustomMetadataField',
        'New-SalesforceCustomMetadataRecord',
        'New-SalesforceCustomMetadataRecordsFromCsv',
        'New-SalesforceCustomMetadataTypeFromOrg',
        'Clear-SalesforceMetadataTypeCache',
        'Build-SalesforceQuery',
        'New-SalesforceManifest',
        'ConvertTo-SalesforceSourceFormat',
        'ConvertTo-SalesforceMdapiFormat',
        'Enable-SalesforceSourceBehavior',
        'Get-SalesforceIgnoredFiles',
        'Remove-SalesforceSource',
        'Remove-SalesforceSourceTracking',
        'Reset-SalesforceSourceTracking',
        'Start-SalesforcePipelineDeploy',
        'Test-SalesforcePipelineDeploy',
        'Start-SalesforcePipelineQuickDeploy',
        'Get-SalesforcePipelineDeployStatus',
        'Resume-SalesforcePipelineDeploy'
    )
    CmdletsToExport       = @()
    VariablesToExport     = @()
    AliasesToExport       = @()
    PrivateData           = @{
        PSData = @{
            Tags        = @('Salesforce','SFDX','Metadata')
            ProjectUri  = 'https://github.com/tonygward/psfdx'
            ReleaseNotes = 'Initial manifest for psfdx-metadata.'
        }
    }
}
