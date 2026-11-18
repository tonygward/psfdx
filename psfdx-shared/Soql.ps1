function ConvertTo-SalesforceSoqlLiteral {
    <# Turns a value into a quoted SOQL string literal that is safe to place in a generated query.

       SOQL escapes a string with a backslash, not by doubling the quote: O'Brien is 'O\'Brien'.
       Backslash, apostrophe and double quote are escaped. Line breaks, tabs, backspace and form feed
       become \n \r \t \b \f, so a value never puts a real line break into the query. Any other control
       character is refused rather than guessed at. Unicode text is kept as it is.

       With -Like, % and _ are escaped as well so they match themselves; without it they are left alone,
       because they are ordinary characters in an = comparison.

       The result is also safe inside the double-quoted --query "..." argument that psfdx builds: a double
       quote or a backtick gets the command-line escape that ConvertTo-PsfdxArgumentList understands.
       Caller-authored queries passed to Select-SalesforceRecords -Query are not touched by this. #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][AllowEmptyString()][AllowNull()][string] $Value,
        [Parameter(Mandatory = $false)][switch] $Like
    )
    process {
        $text = if ($null -eq $Value) { '' } else { $Value }
        $builder = New-Object System.Text.StringBuilder
        [void]$builder.Append("'")
        foreach ($c in $text.ToCharArray()) {
            $code = [int]$c
            # Compare character codes. A string comparison treats control characters as equal to each other.
            switch ($code) {
                0x5C { [void]$builder.Append('\\'); continue }
                0x27 { [void]$builder.Append("\'"); continue }
                0x22 { [void]$builder.Append('\`"'); continue }
                0x60 { [void]$builder.Append('``'); continue }
                0x0A { [void]$builder.Append('\n'); continue }
                0x0D { [void]$builder.Append('\r'); continue }
                0x09 { [void]$builder.Append('\t'); continue }
                0x08 { [void]$builder.Append('\b'); continue }
                0x0C { [void]$builder.Append('\f'); continue }
                default {
                    if ($code -lt 0x20 -or $code -eq 0x7F) {
                        throw ('The value contains a control character (U+{0:X4}) that cannot be written into a SOQL string.' -f $code)
                    }
                    if ($Like -and ($code -eq 0x25 -or $code -eq 0x5F)) { [void]$builder.Append('\').Append($c) }
                    else { [void]$builder.Append($c) }
                }
            }
        }
        [void]$builder.Append("'")
        return $builder.ToString()
    }
}

function ConvertTo-SalesforceSoqlIdentifier {
    <# Checks that a value is a plain Salesforce object or field API name (letters, digits and underscores, starting
       with a letter, with optional dots for relationships) and returns it. Identifiers cannot be quoted in SOQL, so
       anything else is refused instead of being placed in the query. #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][AllowEmptyString()][AllowNull()][string] $Value
    )
    process {
        if ([string]::IsNullOrEmpty($Value) -or $Value -cnotmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)*$') {
            throw "'$Value' is not a valid Salesforce object or field API name."
        }
        return $Value
    }
}
