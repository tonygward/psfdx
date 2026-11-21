function Get-PsfdxCommonParameterSplat {
    <#
    .SYNOPSIS
    Internal helper: picks the common parameters out of $PSBoundParameters so a cmdlet can forward them to Invoke-Salesforce.

    .DESCRIPTION
    Shared helper used by every psfdx cmdlet. It returns a hashtable holding the common parameters the caller was given (such as Verbose and Debug, and WhatIf and Confirm) so they can be splatted into Invoke-Salesforce, which makes -Verbose show the sf command. It is public only because the modules import it from psfdx-shared; it may change without notice. It does not run sf.

    .PARAMETER BoundParameters
    The caller's $PSBoundParameters. Required.

    .EXAMPLE
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Inside a cmdlet.

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

function ConvertTo-PsfdxArgumentList {
    # Splits a command string into an executable and an argument array WITHOUT any shell or
    # PowerShell expression evaluation. Rules (a subset of PowerShell quoting, so existing
    # command strings keep their meaning):
    #   - whitespace separates tokens
    #   - "..." groups text; inside it a backtick escapes ", ` and $ (other backticks are literal)
    #   - '...' groups text; inside it '' is a literal apostrophe
    #   - outside quotes a backtick escapes the next character
    # Everything else, including ; | & < > $( ) and $var, is literal text.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Command
    )

    $tokens = New-Object 'System.Collections.Generic.List[string]'
    $current = New-Object System.Text.StringBuilder
    $hasToken = $false
    $mode = 'none'   # none | double | single
    $i = 0
    $length = $Command.Length

    while ($i -lt $length) {
        $c = $Command[$i]
        if ($mode -eq 'double') {
            if ($c -eq '"') {
                $mode = 'none'
            } elseif ($c -eq '`' -and ($i + 1) -lt $length -and '"`$'.IndexOf($Command[$i + 1]) -ge 0) {
                [void]$current.Append($Command[$i + 1])
                $i++
            } else {
                [void]$current.Append($c)
            }
        } elseif ($mode -eq 'single') {
            if ($c -eq "'") {
                if (($i + 1) -lt $length -and $Command[$i + 1] -eq "'") {
                    [void]$current.Append("'")
                    $i++
                } else {
                    $mode = 'none'
                }
            } else {
                [void]$current.Append($c)
            }
        } else {
            if ([char]::IsWhiteSpace($c)) {
                if ($hasToken) {
                    $tokens.Add($current.ToString())
                    [void]$current.Clear()
                    $hasToken = $false
                }
            } elseif ($c -eq '"') {
                $mode = 'double'
                $hasToken = $true
            } elseif ($c -eq "'") {
                $mode = 'single'
                $hasToken = $true
            } elseif ($c -eq '`' -and ($i + 1) -lt $length) {
                [void]$current.Append($Command[$i + 1])
                $hasToken = $true
                $i++
            } else {
                [void]$current.Append($c)
                $hasToken = $true
            }
        }
        $i++
    }

    if ($mode -ne 'none') {
        throw "Unterminated quote in command."
    }
    if ($hasToken) {
        $tokens.Add($current.ToString())
    }
    if ($tokens.Count -eq 0) {
        throw "Command is empty."
    }

    return [pscustomobject]@{
        FilePath  = $tokens[0]
        Arguments = [string[]]@($tokens | Select-Object -Skip 1)
    }
}

function Get-PsfdxRedactedCommand {
    # Masks the value of secret-bearing options so -Verbose never echoes them.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Command
    )

    $secretOption = '(?i)(--(?:password|client-secret|client-secret-stdin|access-token|refresh-token|sfdx-url|sfdx-auth-url|jwt-key|token|secret)[\w-]*)(\s+|=)("(?:[^"`]|`.)*"|''(?:[^'']|'''')*''|\S+)'
    return [regex]::Replace($Command, $secretOption, '$1$2********')
}

$script:PsfdxPercentVariable = 'PSFDX_PERCENT'
# cmd.exe allows 8191 characters in all; leave room for the shim path and the cmd.exe wrapper.
$script:PsfdxMaxShimCommandLength = 7800

function Test-PsfdxIsWindows {
    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
}

function Test-PsfdxIsCmdShim {
    # True when the executable resolves to a .cmd/.bat shim (or cannot be resolved, so the safe path applies).
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $FilePath
    )
    $application = Get-Command -Name $FilePath -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $application) { return $true }
    return [bool]($application.Source -match '(?i)\.(cmd|bat)$')
}

function Resolve-PsfdxNativeArguments {
    # Prepares arguments for native execution. On non-Windows the argv is passed untouched.
    # On Windows, tools such as sf, npm and yarn are .cmd shims run through cmd.exe, so
    # characters cmd.exe would interpret are rejected rather than escaped. Windows PowerShell
    # 5.1 (and PowerShell < 7.3) also builds the command line itself, so trailing backslashes
    # in arguments containing whitespace are doubled to survive CommandLineToArgvW.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][string[]] $Arguments = @(),
        [Parameter(Mandatory = $false)][string] $PercentVariable = $script:PsfdxPercentVariable
    )

    if (-not (Test-PsfdxIsWindows)) {
        return [string[]]$Arguments
    }

    $isShim = Test-PsfdxIsCmdShim -FilePath $FilePath

    $legacy = -not (Test-Path -LiteralPath 'Variable:PSNativeCommandArgumentPassing')
    $prepared = New-Object 'System.Collections.Generic.List[string]'
    foreach ($argument in $Arguments) {
        if ($isShim) {
            if ($argument -match '[\r\n"\x00]') {
                throw "Argument contains a character that cannot be passed safely to '$FilePath' on Windows (double quote or line break)."
            }
            if ($argument -notmatch '\s' -and $argument -match '[&|<>^]') {
                throw "Argument contains a shell metacharacter that cannot be passed safely to '$FilePath' on Windows."
            }
            # cmd.exe expands %NAME% in the command line, in a single pass. Each % becomes a
            # reference to a variable whose value is a literal %, so it reaches the tool unchanged
            # (e.g. LIKE 'Acme%' or a literal %NAME%). Invoke-Salesforce defines the variable.
            if ($argument.Contains('%')) {
                $argument = $argument.Replace('%', '%' + $PercentVariable + '%')
            }
        }
        if ($legacy -and -not $isShim -and $argument.Contains('"')) {
            # Windows PowerShell 5.1 does not escape embedded double quotes when it builds the
            # command line, so they would be lost. Use the CommandLineToArgvW rules: double the
            # backslashes before a quote and escape the quote itself.
            $argument = [regex]::Replace($argument, '(\\*)"', '$1$1\"')
        }
        if ($legacy -and $argument -match '\s' -and $argument -match '\\+$') {
            $argument = $argument + $Matches[0]
        }
        $prepared.Add($argument)
    }
    if ($isShim) {
        # cmd.exe refuses a command line over 8191 characters and says so only in its output ("The command line is too long."), which
        # a non-JSON call would return as if it were a result. Stay well under the limit (the shim path and cmd.exe add to it) and say what to do.
        $total = $FilePath.Length
        foreach ($p in $prepared) { $total += $p.Length + 1 }
        if ($total -gt $script:PsfdxMaxShimCommandLength) {
            throw "The arguments for '$FilePath' are $total characters long after preparation; Windows cannot run a command line over about $($script:PsfdxMaxShimCommandLength) characters through a .cmd shim. Shorten the query, or put it in a file and pass --file."
        }
    }
    return [string[]]$prepared.ToArray()
}

function ConvertTo-PsfdxDisplayCommand {
    # Renders an executable and argv as one line for -Verbose only. Never executed.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][string[]] $Arguments = @()
    )
    $parts = @($FilePath)
    foreach ($argument in $Arguments) {
        if ($argument -eq '' -or $argument -match '[\s"'']') {
            $parts += '"' + ($argument -replace '([`"$])', '`$1') + '"'
        } else {
            $parts += $argument
        }
    }
    return ($parts -join ' ')
}
function Invoke-Salesforce {
    <#
    .SYNOPSIS
    Internal helper: runs the sf executable (or another program) with an argument array.

    .DESCRIPTION
    Shared helper that every psfdx cmdlet uses to run a program. It runs -FilePath directly with the -Arguments array (never through Invoke-Expression or a shell), so ; | & and $(...) in a value are plain text. With -Verbose it prints the command with secret option values masked. In JSON mode a failed process without a JSON body throws; a failed process with a JSON body is returned so Show-SalesforceResult can report its message. The older -Command string form is still accepted. The executable is found on the PATH at run time. Public because the modules import it from psfdx-shared; it may change without notice.

    .PARAMETER Command
    Legacy form: one command string that is split into the program and its arguments. Do not use it in new code. Required in the Command parameter set.

    .PARAMETER FilePath
    The program to run, usually sf. It is looked up on the PATH. Required in the Arguments parameter set.

    .PARAMETER Arguments
    The arguments, one array element each, exactly as the program should receive them. On Windows, a .cmd shim (sf, npm, yarn) refuses an argument with a double quote or line break, or bare shell metacharacters, and a command line over about 7800 characters. Belongs to the Arguments parameter set. Default: @().

    .EXAMPLE
    Invoke-Salesforce -FilePath sf -Arguments @('org', 'list', '--json')
    Run sf org list and return its output.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It works locally in PowerShell and .NET.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    # Deliberately does not declare SupportsShouldProcess: callers pipe the return value
    # straight into Show-SalesforceResult, whose -Result parameter is Mandatory, so
    # suppressing the call would make every cmdlet fail on a null argument instead of
    # performing a dry run. Declare ShouldProcess on the public cmdlets instead.
    #
    # Preferred form for new code: -FilePath sf -Arguments @('package','create','--name',$Name,...).
    # The argument array is passed as the process argv exactly as given, so spaces, quotes,
    # apostrophes and backslashes in a value need no quoting at all. Build it with
    # Add-PsfdxArgument or a plain list.
    #
    # Legacy form: -Command. The command string is split into an executable and an argument
    # array and run with the call operator. It is never passed to Invoke-Expression or a shell,
    # so ; | & $( ) and similar characters in values are literal. Quote values with
    # "`"$Value`"" as before.
    [CmdletBinding(DefaultParameterSetName = 'Command')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Command')][string] $Command,
        [Parameter(Mandatory = $true, ParameterSetName = 'Arguments')][ValidateNotNullOrEmpty()][string] $FilePath,
        [Parameter(Mandatory = $false, ParameterSetName = 'Arguments')][AllowEmptyCollection()][AllowEmptyString()][string[]] $Arguments = @()
    )

    if ($PSCmdlet.ParameterSetName -eq 'Arguments') {
        $filePath = $FilePath
        $rawArguments = [string[]]@($Arguments | ForEach-Object { [string]$_ })
        $displayCommand = ConvertTo-PsfdxDisplayCommand -FilePath $filePath -Arguments $rawArguments
        $isJsonMode = $rawArguments -contains '--json'
    } else {
        $parsed = ConvertTo-PsfdxArgumentList -Command $Command
        $filePath = $parsed.FilePath
        $rawArguments = $parsed.Arguments
        $displayCommand = $Command
        $isJsonMode = $Command -match '(^|\s)--json(\s|$)'
    }

    Write-Verbose (Get-PsfdxRedactedCommand -Command $displayCommand)
    # Wrap in @() so an empty result is an empty array, not $null (Windows PowerShell 5.1 runs a foreach once over $null).
    # The variable that stands for a literal % is named per call, so concurrent calls (other runspaces, jobs or threads in the same process)
    # never share it: one call cannot remove or overwrite another's variable while its child process starts.
    $percentName = $script:PsfdxPercentVariable + '_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $nativeArguments = @(Resolve-PsfdxNativeArguments -FilePath $filePath -Arguments $rawArguments -PercentVariable $percentName)
    $percentToken = '%' + $percentName + '%'
    $needsPercent = $false
    foreach ($nativeArgument in $nativeArguments) {
        if ($null -ne $nativeArgument -and $nativeArgument.Contains($percentToken)) { $needsPercent = $true; break }
    }

    if ($needsPercent) {
        [System.Environment]::SetEnvironmentVariable($percentName, '%')
    }
    try {
        $global:LASTEXITCODE = 0
        $output = & $filePath @nativeArguments
        $exitCode = $global:LASTEXITCODE
    } finally {
        if ($needsPercent) {
            # [NullString]::Value, not $null: PowerShell turns $null into an empty string for this call, which leaves the variable set.
            [System.Environment]::SetEnvironmentVariable($percentName, [NullString]::Value)
        }
    }

    # In JSON mode the CLI prints a JSON error body on failure, which Show-SalesforceResult
    # reports. A failed process with no JSON body would otherwise look like success or like
    # a parsing problem, so say what happened here. Plain-text commands are returned as is.
    if ($exitCode -ne 0 -and $isJsonMode) {
        $text = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ })).Trim()
        $isJson = $false
        if ($text) {
            try { $null = $text | ConvertFrom-Json -ErrorAction Stop; $isJson = $true } catch { $isJson = $false }
        }
        if (-not $isJson) {
            $detail = Get-SalesforceRedactedJson -Json $text
            if ($detail.Length -gt 500) { $detail = $detail.Substring(0, 500) + '...' }
            if ($detail) { $detail = ": $detail" }
            throw "Salesforce CLI exited with code $exitCode and returned no JSON result$detail"
        }
    }
    return $output
}
