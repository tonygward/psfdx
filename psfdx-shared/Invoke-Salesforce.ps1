function Invoke-Salesforce {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Command
    )

    Write-Verbose $Command
    return Invoke-Expression -Command $Command
}
