function Show-SalesforceResult {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][psobject] $Result,
        [Parameter(Mandatory = $false)][switch] $ReturnRecords,
        [Parameter(Mandatory = $false)][switch] $IncludeAttributes
    )

    $converted = ConvertFrom-SalesforceJsonOutput -Output $Result
    if ($converted.status -ne 0) {
        Write-Debug (Get-SalesforceRedactedJson -Json ([string]::Join([Environment]::NewLine, @($Result))))
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

function ConvertFrom-SalesforceJsonOutput {
    # Turns the output of an `sf ... --json` call into an object, or throws a clear error.
    # Empty output, non-JSON text, malformed JSON and JSON without a status are all
    # failures, never successes. Error text is redacted and truncated.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][AllowEmptyCollection()] $Output
    )

    $text = [string]::Join([Environment]::NewLine, @($Output | ForEach-Object { [string]$_ })).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw 'Salesforce CLI returned no output where JSON was expected.'
    }

    $preview = Get-SalesforceRedactedJson -Json $text
    if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }

    try {
        $converted = $text | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Salesforce CLI returned output that is not valid JSON: $preview"
    }

    if ($null -eq $converted -or $converted -is [array] -or $null -eq $converted.PSObject.Properties['status']) {
        throw "Salesforce CLI returned JSON in an unexpected shape (no status): $preview"
    }
    return $converted
}

function Get-SalesforceRedactedJson {
    # Masks credential-like JSON fields and SFDX auth URLs so debug output never echoes them.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Json
    )

    $keys = 'accessToken|refreshToken|sfdxAuthUrl|authUrl|password|clientSecret|privateKey|sessionId|securityToken'
    $redacted = [regex]::Replace($Json, '(?i)("(?:' + $keys + ')"\s*:\s*)"(?:[^"\\]|\\.)*"', '$1"********"')
    $redacted = [regex]::Replace($redacted, '(?i)force://[^\s"''\\,]+', 'force://********')
    return $redacted
}

function Get-SalesforceErrorMessage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][psobject] $Result
    )

    if ($Result -is [string]) {
        Write-Debug (Get-SalesforceRedactedJson -Json $Result)
    } else {
        Write-Debug (Get-SalesforceRedactedJson -Json ($Result | ConvertTo-Json -Depth 10))
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
