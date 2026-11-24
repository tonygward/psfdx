@{
    RootModule = 'psfdx-bulk.psm1'
    ModuleVersion = '0.8.59'
    GUID = '04d396d0-872a-433c-878e-7dbd8e5f4f57'
    Author = 'Tony Ward'
    Description = 'Salesforce Bulk API 2.0 helpers for the Salesforce CLI: bulk export, import, update, upsert and delete, and bulk job status, results and resume.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop','Core')
    FunctionsToExport = @(
        'Export-SalesforceBulkData',
        'Import-SalesforceBulkData',
        'Update-SalesforceBulkData',
        'Upsert-SalesforceBulkData',
        'Remove-SalesforceBulkData',
        'Resume-SalesforceBulkJob',
        'Get-SalesforceBulkResult',
        'Get-SalesforceBulkJobStatus'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
}
