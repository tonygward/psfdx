@{
    RootModule = 'psfdx-shared.psm1'
    ModuleVersion = '0.8.62'
    GUID = '32273e30-b48e-46a0-a566-a74261704f38'
    Author = 'Tony Ward'
    Description = 'Shared helpers for psfdx PowerShell modules'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop','Core')
    # Nothing is exported: every command here is an internal helper. Each psfdx module binds the helpers it needs as private functions
    # (see Import-PsfdxSharedModule), and the core psfdx module exports the three SOQL converters, which are public commands.
    FunctionsToExport = @()
    CmdletsToExport = @()
    AliasesToExport = @()
}
