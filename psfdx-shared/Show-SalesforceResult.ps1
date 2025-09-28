function Show-SalesforceResult {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][psobject] $Result,
        [Parameter(Mandatory = $false)][switch] $ReturnRecords,
        [Parameter(Mandatory = $false)][switch] $IncludeAttributes
    )

    $converted = $Result | ConvertFrom-Json
    if ($converted.status -ne 0) {
        Write-Debug ($Result | ConvertTo-Json)
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

    if ($Result -is [string]) {
        Write-Debug $Result
    } else {
        Write-Debug ($Result | ConvertTo-Json -Depth 10)
    }

    $messages = @()

    if ($Result.message) {
        $messages += $Result.message
    }

    $deployFailures = Get-SalesforceDeployFailures -Result $Result
    if ($deployFailures) {
        $messages += $deployFailures
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

function Get-SalesforceDeployFailures {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][psobject] $Result
    )

    $resultRoot = $Result.result
    if ($null -eq $resultRoot) { return $null }

    $details = $resultRoot.details
    if ($null -eq $details) { return $null }

    $componentFailures = $details.componentFailures
    if (-not $componentFailures) {
        return $null
    }

    return ($componentFailures | ForEach-Object {
        $problem = $_.problem
        $line = $_.lineNumber
        $column = $_.columnNumber

        if ([string]::IsNullOrWhiteSpace($problem)) {
            return $null
        }

        if (($null -ne $line) -or ($null -ne $column)) {
            $lineValue = if ($null -ne $line) { $line } else { '?' }
            $columnValue = if ($null -ne $column) { $column } else { '?' }
            "$problem ($($lineValue):$($columnValue))"
        } else {
            $problem
        }
    }) | Where-Object { $_ }
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
