@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'psfdx-logs.psm1'

    # Version number of this module.
    ModuleVersion     = '0.5'

    # Supported PowerShell editions: Desktop = Windows PowerShell, Core = PowerShell 7+
    CompatiblePSEditions = @('Desktop','Core')

    # ID used to uniquely identify this module
    GUID              = '3cfba2e3-1df1-4b79-95c4-7d61f1c8168b'

    # Author of this module
    Author            = 'psfdx-logs maintainers'

    # Company or vendor of this module
    CompanyName       = 'psfdx-logs'

    # Copyright statement for this module
    Copyright         = 'Copyright (c) psfdx-logs contributors.'

    # Description of the functionality provided by this module
    Description       = 'PowerShell helpers for working with Salesforce DX (sf) Apex logs.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules   = @('psfdx')

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller''s environment prior to importing this module.
    ScriptsToProcess  = @()

    # Type files (.ps1xml) to be loaded when importing this module
    TypesToProcess    = @()

    # Format files (.ps1xml) to be loaded when importing this module
    FormatsToProcess  = @()

    # Functions to export from this module. Use @() to export nothing, or '*' to export all.
    FunctionsToExport = @(
        'Watch-SalesforceDebugLogs',
        'Select-SalesforceDebugLogs',
        'Get-SalesforceDebugLogs',
        'Export-SalesforceDebugLogs',
        'Convert-SalesforceDebugLog',
        'Get-SalesforceFlowInterviews',
        'Get-SalesforceLoginHistory',
        'Get-SalesforceLoginFailures',
        'Export-SalesforceEventFiles',
        'Get-SalesforceEventFile',
        'Export-SalesforceEventFile',
        'Select-SalesforceEventFiles',
        'Out-Notepad'
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
            Tags        = @('Salesforce','SFDX','Apex','Logs')
            ProjectUri  = 'https://github.com/tonygward/psfdx-logs'
            # LicenseUri = ''
            # IconUri    = ''
            ReleaseNotes = 'Initial manifest for psfdx-logs.'
        }
    }
}
