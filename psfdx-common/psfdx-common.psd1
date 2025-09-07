@{
    RootModule            = 'psfdx-common.psm1'
    ModuleVersion         = '0.1.0'
    CompatiblePSEditions  = @('Desktop','Core')
    GUID                  = 'f2c7e6e3-6a3c-4e0d-9f5a-4d3e2a1b9c01'
    Author                = 'psfdx maintainers'
    CompanyName           = 'psfdx'
    Description           = 'Shared helpers for psfdx modules (Invoke-Sf, Show-SfResult).'
    PowerShellVersion     = '5.1'
    FunctionsToExport     = @('Invoke-Sf','Show-SfResult')
    CmdletsToExport       = @()
    VariablesToExport     = @()
    AliasesToExport       = @()
    PrivateData           = @{
        PSData = @{
            Tags        = @('Salesforce','SFDX','Common')
            ProjectUri  = 'https://github.com/tonygward/psfdx'
            ReleaseNotes = 'Initial shared helpers.'
        }
    }
}

