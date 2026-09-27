function Get-PsfdxCommonParameterSplat {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary] $BoundParameters
    )

    if ($null -eq $BoundParameters) {
        return @{}
    }

    $forward = @{}
    foreach ($name in @('Verbose', 'Debug', 'WhatIf', 'Confirm')) {
        if ($BoundParameters.ContainsKey($name)) {
            $value = $BoundParameters[$name]
            if ($value -is [System.Management.Automation.SwitchParameter]) {
                $forward[$name] = $value.IsPresent
            } else {
                $forward[$name] = $value
            }
        }
    }

    return $forward
}

function Invoke-Salesforce {
    # Deliberately does not declare SupportsShouldProcess: callers pipe the return value
    # straight into Show-SalesforceResult, whose -Result parameter is Mandatory, so
    # suppressing the call would make every cmdlet fail on a null argument instead of
    # performing a dry run. Declare ShouldProcess on the public cmdlets instead.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Command
    )

    Write-Verbose $Command
    return Invoke-Expression -Command $Command
}
