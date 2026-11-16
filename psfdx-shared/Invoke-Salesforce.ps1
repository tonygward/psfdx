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

function Test-PsfdxIsWindows {
    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
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
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][string[]] $Arguments = @()
    )

    if (-not (Test-PsfdxIsWindows)) {
        return [string[]]$Arguments
    }

    $isShim = $false
    $application = Get-Command -Name $FilePath -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($application -and $application.Source -match '(?i)\.(cmd|bat)$') { $isShim = $true }
    if (-not $application) { $isShim = $true }

    $legacy = -not (Test-Path -LiteralPath 'Variable:PSNativeCommandArgumentPassing')
    $prepared = New-Object 'System.Collections.Generic.List[string]'
    foreach ($argument in $Arguments) {
        if ($isShim) {
            if ($argument -match '[%\r\n"\x00]') {
                throw "Argument contains a character that cannot be passed safely to '$FilePath' on Windows (%, double quote or line break)."
            }
            if ($argument -notmatch '\s' -and $argument -match '[&|<>^]') {
                throw "Argument contains a shell metacharacter that cannot be passed safely to '$FilePath' on Windows."
            }
        }
        if ($legacy -and $argument -match '\s' -and $argument -match '\\+$') {
            $argument = $argument + $Matches[0]
        }
        $prepared.Add($argument)
    }
    return [string[]]$prepared.ToArray()
}

function Invoke-Salesforce {
    # Deliberately does not declare SupportsShouldProcess: callers pipe the return value
    # straight into Show-SalesforceResult, whose -Result parameter is Mandatory, so
    # suppressing the call would make every cmdlet fail on a null argument instead of
    # performing a dry run. Declare ShouldProcess on the public cmdlets instead.
    #
    # The command string is split into an executable and an argument array and run with the
    # call operator. It is never passed to Invoke-Expression or a shell, so ; | & $( ) and
    # similar characters in values are literal. Quote values with "`"$Value`"" as before.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Command
    )

    Write-Verbose (Get-PsfdxRedactedCommand -Command $Command)
    $parsed = ConvertTo-PsfdxArgumentList -Command $Command
    $nativeArguments = Resolve-PsfdxNativeArguments -FilePath $parsed.FilePath -Arguments $parsed.Arguments
    $filePath = $parsed.FilePath
    return & $filePath @nativeArguments
}
