@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'psfdx-development.psm1'

    # Version number of this module.
    ModuleVersion     = '0.5'

    # Supported PowerShell editions: Desktop = Windows PowerShell, Core = PowerShell 7+
    CompatiblePSEditions = @('Desktop','Core')

    # ID used to uniquely identify this module
    GUID              = 'c2b8e8c6-74a9-4c14-8f1c-8b7e3f2e7a54'

    # Author of this module
    Author            = 'Tony Ward'

    # Company or vendor of this module
    CompanyName       = 'psfdx'

    # Copyright statement for this module
    Copyright         = 'Copyright (c) psfdx contributors.'

    # Description of the functionality provided by this module
    Description       = 'PowerShell helpers for Salesforce DX development workflows (projects, scratch orgs, tests, deploy).'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules   = @('psfdx-metadata')

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller''s environment prior to importing this module.
    ScriptsToProcess  = @()

    # Type files (.ps1xml) to be loaded when importing this module
    TypesToProcess    = @()

    # Format files (.ps1xml) to be loaded when importing this module
    FormatsToProcess  = @()

    # Functions to export from this module. Explicitly listed to align with Export-ModuleMember.
    FunctionsToExport = @(
        'Install-SalesforceLwcDevServer',
        'Start-SalesforceLwcDevServer',
        'Set-SalesforceDefaultDevHub',
        'Remove-SalesforceDefaultDevHub',
        'Get-SalesforceConfig',
        'Get-SalesforceScratchOrgs',
        'New-SalesforceScratchOrg',
        'Remove-SalesforceScratchOrg',
        'Remove-SalesforceScratchOrgs',
        'New-SalesforceProject',
        'Set-SalesforceProject',
        'Get-SalesforceDefaultUserName',
        'Get-SalesforceProjectUser',
        'Set-SalesforceProjectUser',
        'New-SalesforceProjectAndScratchOrg',
        'Test-Salesforce',
        'Get-SalesforceCodeCoverage',
        'Install-SalesforceJest',
        'New-SalesforceJestTest',
        'Test-SalesforceJest',
        'Debug-SalesforceJest',
        'Watch-SalesforceJest',
        'Watch-SalesforceApex',
        'Invoke-SalesforceApexFile',
        'New-SalesforceApexClass',
        'New-SalesforceApexTrigger'
    )

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport   = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData       = @{
        PSData = @{
            Tags        = @('Salesforce','SFDX','Development','Apex','LWC')
            ProjectUri  = 'https://github.com/tonygward/psfdx'
            # LicenseUri = ''
            # IconUri    = ''
            ReleaseNotes = 'Initial manifest for psfdx-development.'
            Prerelease  = 'beta'
        }
    }
}
