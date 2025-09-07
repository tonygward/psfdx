@{
    RootModule            = 'psfdx-metadata.psm1'
    ModuleVersion         = '0.1.0'
    CompatiblePSEditions  = @('Desktop','Core')
    GUID                  = 'e0c7c8c3-0f5f-4662-a9e1-2c3c5a1c7f20'
    Author                = 'Tony Ward'
    CompanyName           = 'psfdx'
    Copyright            = 'Copyright (c) psfdx contributors.'
    Description           = 'PowerShell helpers for retrieving, deploying, and describing Salesforce metadata.'
    PowerShellVersion     = '5.1'
    RequiredModules       = @(@{ ModuleName = 'psfdx-common'; ModuleVersion = '0.1.0' })
    RequiredAssemblies    = @()
    ScriptsToProcess      = @()
    TypesToProcess        = @()
    FormatsToProcess      = @()
    FunctionsToExport     = @(
        'Retrieve-SalesforceOrg',
        'Retrieve-SalesforceComponent',
        'Retrieve-SalesforceField',
        'Retrieve-SalesforceValidationRule',
        'Deploy-SalesforceComponent',
        'Describe-SalesforceObjects',
        'Describe-SalesforceObject',
        'Describe-SalesforceFields',
        'Get-SalesforceMetaTypes',
        'Get-SalesforceApexClass',
        'Build-SalesforceQuery'
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
