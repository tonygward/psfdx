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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $Command
    )

    if (-not $PSCmdlet.ShouldProcess($Command, 'Invoke Salesforce CLI command')) {
        return
    }

    Write-Verbose $Command
    return Invoke-Expression -Command $Command
}
