function Invoke-Sf {
    [CmdletBinding(DefaultParameterSetName='String')]
    Param(
        [Parameter(ParameterSetName='String')][Alias('Arguments')][string] $StringCommand,
        [Parameter(ParameterSetName='Array')][Alias('Command')][string[]] $ArrayCommand
    )
    if ($PSCmdlet.ParameterSetName -eq 'Array') {
        if (-not $ArrayCommand -or $ArrayCommand.Count -eq 0) { throw 'No command specified' }
        Write-Verbose ($ArrayCommand -join ' ')
        $exe = $ArrayCommand[0]
        $args = @()
        if ($ArrayCommand.Count -gt 1) { $args = $ArrayCommand[1..($ArrayCommand.Count-1)] }
        return & $exe @args
    }
    if (-not $StringCommand) { throw 'No command specified' }
    Write-Verbose $StringCommand
    return Invoke-Expression -Command $StringCommand
}

function Show-SfResult {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][psobject] $Result)
    $result = $Result | ConvertFrom-Json
    if ($result.status -ne 0) {
        Write-Debug $result
        throw ($result.message)
    }
    return $result.result
}

Export-ModuleMember Invoke-Sf, Show-SfResult

