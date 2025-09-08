function Invoke-Salesforce {
    [CmdletBinding(DefaultParameterSetName = 'Arguments')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Arguments')][string] $Arguments,
        [Parameter(Mandatory = $true, ParameterSetName = 'Command')][object] $Command
    )

    if ($PSCmdlet.ParameterSetName -eq 'Arguments') {
        $Command = "sf $Arguments"
    }

    if ($Command -is [string[]]) {
        Write-Verbose ($Command -join ' ')
        if ($Command.Length -eq 0) { throw 'No command specified' }
        $exe = $Command[0]
        $args = @()
        if ($Command.Length -gt 1) { $args = $Command[1..($Command.Length-1)] }
        return & $exe @args
    }
    elseif ($Command -is [string]) {
        Write-Verbose $Command
        return Invoke-Expression -Command $Command
    }
    else {
        throw "Unsupported -Command type: $($Command.GetType().FullName)"
    }
}
