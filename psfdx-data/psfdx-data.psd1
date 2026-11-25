@{
    RootModule = 'psfdx-data.psm1'
    ModuleVersion = '0.8.62'
    GUID = '04d396d0-872a-433c-878e-7dbd8e5f4f57'
    Author = 'Tony Ward'
    Description = 'Salesforce data for the Salesforce CLI: SOQL and SOSL queries, single records, files, tree data and Bulk API 2.0 jobs.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop','Core')
    FunctionsToExport = @(
        'Select-SalesforceRecords',
        'Search-SalesforceRecords',
        'New-SalesforceRecord',
        'Set-SalesforceRecord',
        'Get-SalesforceRecord',
        'Remove-SalesforceRecord',
        'Upsert-SalesforceRecord',
        'Export-SalesforceTreeData',
        'Import-SalesforceTreeData',
        'New-SalesforceFile',
        'Get-SalesforceRecordType',
        'Get-SalesforceSObjectRecordCount',
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
