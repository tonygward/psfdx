function Show-SalesforceResult {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][psobject] $Result,
        [Parameter(Mandatory = $false)][switch] $ReturnRecords,
        [Parameter(Mandatory = $false)][switch] $ExcludeAttributes
    )
    $result = $Result | ConvertFrom-Json
    if ($result.status -ne 0) {
        Write-Debug $result
        throw ($result.message)
    }
    $out = $result.result
    if ($ReturnRecords) {
        $records = $out.records
        if ($null -eq $records) { return @() }
        if ($PSBoundParameters.ContainsKey('ExcludeAttributes') -and -not $ExcludeAttributes) {
            return $records
        }
        return ($records | Select-Object -ExcludeProperty attributes)
    }
    return $out
}
