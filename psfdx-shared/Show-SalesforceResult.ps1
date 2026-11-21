function Show-SalesforceResult {
    <#
    .SYNOPSIS
    Internal helper: parses the JSON an sf command printed and returns its result, or throws its error.

    .DESCRIPTION
    Shared helper used by the cmdlets that run sf --json. It parses the output, throws the CLI message (with deploy and test failure details) when the status is not 0, redacts tokens and secrets from error text, and otherwise returns the result property, or only its records with -ReturnRecords. Public because the modules import it from psfdx-shared; it may change without notice.

    .PARAMETER Result
    The text the sf command printed (a string or an array of lines). Required.

    .PARAMETER ReturnRecords
    Return result.records (without the attributes property) instead of the whole result. An empty array is returned when there are none.

    .PARAMETER IncludeAttributes
    Keep the attributes property on each record when used with -ReturnRecords.

    .EXAMPLE
    $raw = Invoke-Salesforce -FilePath sf -Arguments @('org', 'list', '--json'); Show-SalesforceResult -Result $raw
    Parse the output of a command.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It works locally in PowerShell and .NET.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
        return ($records | Select-Object -Property * -ExcludeProperty attributes)
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
    <#
    .SYNOPSIS
    Internal helper: builds the error message for a failed sf JSON result.

    .DESCRIPTION
    Shared helper used by Show-SalesforceResult. It combines the CLI message with deploy and test failure details (via Get-SalesforceDeployFailures and Get-SalesforceTestFailure) and writes a redacted copy of the result to the Debug stream. Public only because the modules import it from psfdx-shared; it may change without notice. It does not run sf.

    .PARAMETER Result
    A parsed sf JSON result with a non-zero status. Required.

    .EXAMPLE
    Get-SalesforceErrorMessage -Result $parsedFailure
    The message that would be thrown.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It works locally in PowerShell and .NET.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Internal helper: turns the component failures of a failed deploy result into text lines.

    .DESCRIPTION
    Shared helper used by Show-SalesforceResult. It reads result.details.componentFailures of a CLI deploy result and returns one readable line per failure, or nothing if there are none. Public only because the modules import it from psfdx-shared; it may change without notice. It does not run sf.

    .PARAMETER Result
    A parsed sf JSON result. Required.

    .EXAMPLE
    Get-SalesforceDeployFailures -Result $parsedDeployResult
    The failure lines.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It works locally in PowerShell and .NET.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
    <#
    .SYNOPSIS
    Internal helper: turns the failed tests of an Apex test result into text lines.

    .DESCRIPTION
    Shared helper used by Show-SalesforceResult. It reads the failures of a CLI test result and returns one readable line per failed test, or nothing if there are none. Public only because the modules import it from psfdx-shared; it may change without notice. It does not run sf.

    .PARAMETER Result
    A parsed sf JSON result. Required.

    .EXAMPLE
    Get-SalesforceTestFailure -Result $parsedTestResult
    The failure lines.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It works locally in PowerShell and .NET.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
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
