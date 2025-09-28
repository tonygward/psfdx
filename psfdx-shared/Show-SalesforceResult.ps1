function Show-SalesforceResult {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][psobject] $Result,
        [Parameter(Mandatory = $false)][switch] $ReturnRecords,
        [Parameter(Mandatory = $false)][switch] $IncludeAttributes
    )

    $converted = $Result | ConvertFrom-Json
    if ($converted.status -ne 0) {
        Write-Error $Result
        throw ($converted.message)
    }

    $out = $converted.result
    if ($ReturnRecords) {
        $records = $out.records
        if ($null -eq $records) { return @() }
        if ($IncludeAttributes) { return $records }
        return ($records | Select-Object -ExcludeProperty attributes)
    }
    return $out
}
