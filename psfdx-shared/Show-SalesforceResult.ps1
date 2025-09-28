function Show-SalesforceResult {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][psobject] $Result,
        [Parameter(Mandatory = $false)][switch] $ReturnRecords,
        [Parameter(Mandatory = $false)][switch] $IncludeAttributes
    )

    $converted = $Result | ConvertFrom-Json
    if ($converted.status -ne 0) {
        $message = Get-SalesforceErrorMessage -Result $converted
        throw $message
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

function Get-SalesforceErrorMessage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][psobject] $Result
    )

    $messages = @()

    if ($Result.message) {
        $messages += $Result.message
    }

    $testFailures = Get-SalesforceTestFailure -Result $Result
    if ($testFailures) {
        $messages += $testFailures
    }

    if (-not $messages) {
        $messages += "Salesforce command failed with status $($Result.status)."
    }

    return ($messages -join [Environment]::NewLine)
}

function Get-SalesforceTestFailure {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][psobject] $Result
    )

    $resultRoot = $Result.result
    if ($null -eq $resultRoot) { return $null }

    $details = $resultRoot.details
    if ($null -eq $details) { return $null }

    $runTestResult = $details.runTestResult
    if ($null -eq $runTestResult) { return $null }

    $failures = $runTestResult.failures
    if (-not $failures) {
        return $null
    }

    return ($failures | ForEach-Object {
        $message = $_.message
        $stack = $_.stackTrace
        if ($stack) {
            "$message $stack"
        } else {
            $message
        }
    })
}
