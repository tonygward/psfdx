@{
    RootModule            = 'psfdx-packages.psm1'
    ModuleVersion         = '0.1.0'
    CompatiblePSEditions  = @('Desktop','Core')
    GUID                  = '0d7f0c6c-8f1b-4eb6-9f6a-55f7a7c3f2b1'
    Author                = 'Tony Ward'
    CompanyName           = 'psfdx'
    Copyright            = 'Copyright (c) psfdx contributors.'
    Description           = 'PowerShell helpers for Salesforce packages: list, create, version, promote, install.'
    PowerShellVersion     = '5.1'
    RequiredModules       = @(@{ ModuleName = 'psfdx-common'; ModuleVersion = '0.1.0' })
    RequiredAssemblies    = @()
    ScriptsToProcess      = @()
    TypesToProcess        = @()
    FormatsToProcess      = @()
    FunctionsToExport     = @(
        'Get-SalesforcePackages',
        'Get-SalesforcePackage',
        'New-SalesforcePackage',
        'Remove-SalesforcePackage',
        'Get-SalesforcePackageVersions',
        'New-SalesforcePackageVersion',
        'Promote-SalesforcePackageVersion',
        'Remove-SalesforcePackageVersion',
        'Install-SalesforcePackageVersion'
    )
    CmdletsToExport       = @()
    VariablesToExport     = @()
    AliasesToExport       = @()
    PrivateData           = @{
        PSData = @{
            Tags        = @('Salesforce','SFDX','Packages')
            ProjectUri  = 'https://github.com/tonygward/psfdx'
            ReleaseNotes = 'Initial manifest for psfdx-packages.'
        }
    }
}
