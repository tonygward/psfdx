Get-Module -Name 'psfdx-shared' -All | Remove-Module -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'psfdx-shared.psd1') -Force

InModuleScope 'psfdx-shared' {
    Describe 'Show-SalesforceResult secret handling' {
        It 'redacts credential fields and auth URLs from JSON' {
            $json = '{"status":1,"message":"bad","result":{"accessToken":"00Dtoken","refreshToken":"5Aep","sfdxAuthUrl":"force://PlatformCLI::abc@my.salesforce.com","username":"u@example.com"}}'
            $out = Get-SalesforceRedactedJson -Json $json
            $out | Should -Not -Match '00Dtoken'
            $out | Should -Not -Match '5Aep'
            $out | Should -Not -Match 'PlatformCLI'
            $out | Should -Match 'u@example.com'
        }

        It 'does not write secrets to the debug stream or exception text on failure' {
            $json = '{"status":1,"message":"Login failed","result":{"accessToken":"00Dsecret","sfdxAuthUrl":"force://PlatformCLI::zzz@x.salesforce.com"}}'
            { Show-SalesforceResult -Result $json } | Should -Throw -ExpectedMessage 'Login failed'
            $debugOut = & { $DebugPreference = 'Continue'; try { Show-SalesforceResult -Result $json } catch { } } 5>&1 | Out-String
            $debugOut | Should -Not -Match '00Dsecret'
            $debugOut | Should -Not -Match 'PlatformCLI'
        }

        It 'returns non-auth results unchanged' {
            $r = Show-SalesforceResult -Result '{"status":0,"result":{"records":[{"Id":"001","attributes":{"type":"Account"}}]}}' -ReturnRecords
            @($r)[0].Id | Should -Be '001'
        }
    }

    Describe 'ConvertTo-PsfdxArgumentList' {
        It 'splits on whitespace into executable and arguments' {
            $r = ConvertTo-PsfdxArgumentList -Command 'sf org list --json'
            $r.FilePath | Should -Be 'sf'
            @($r.Arguments) | Should -Be @('org', 'list', '--json')
        }

        It 'keeps a double-quoted path with spaces as one argument' {
            $r = ConvertTo-PsfdxArgumentList -Command 'sf apex run --file "C:\my dir\a b.apex" --json'
            @($r.Arguments) | Should -Be @('apex', 'run', '--file', 'C:\my dir\a b.apex', '--json')
        }

        It 'handles backtick-escaped quotes inside double quotes' {
            $r = ConvertTo-PsfdxArgumentList -Command 'sf x --description "say `"hi`" now"'
            @($r.Arguments) | Should -Be @('x', '--description', 'say "hi" now')
        }

        It 'keeps SOQL apostrophes literal inside double quotes' {
            $r = ConvertTo-PsfdxArgumentList -Command "sf data query --query `"SELECT Id FROM Account WHERE Name = 'O''Brien'`" --json"
            @($r.Arguments)[3] | Should -Be "SELECT Id FROM Account WHERE Name = 'O''Brien'"
        }

        It 'supports single-quoted tokens with doubled apostrophes' {
            $r = ConvertTo-PsfdxArgumentList -Command "sf x 'a b''c'"
            @($r.Arguments) | Should -Be @('x', "a b'c")
        }

        It 'treats injection metacharacters as literal text' {
            $r = ConvertTo-PsfdxArgumentList -Command 'sf x --name "a; Remove-Item foo | $(whoami) & $env:HOME > out"'
            @($r.Arguments).Count | Should -Be 3
            @($r.Arguments)[2] | Should -Be 'a; Remove-Item foo | $(whoami) & $env:HOME > out'
        }

        It 'keeps unquoted metacharacters inside a token literal' {
            $r = ConvertTo-PsfdxArgumentList -Command 'sf x a;b $(c)'
            @($r.Arguments) | Should -Be @('x', 'a;b', '$(c)')
        }

        It 'preserves Unicode' {
            $r = ConvertTo-PsfdxArgumentList -Command 'sf x "Zoë 日本語"'
            @($r.Arguments)[1] | Should -Be 'Zoë 日本語'
        }

        It 'keeps an empty quoted argument' {
            $r = ConvertTo-PsfdxArgumentList -Command 'sf x "" y'
            @($r.Arguments) | Should -Be @('x', '', 'y')
        }

        It 'throws on an unterminated quote' {
            { ConvertTo-PsfdxArgumentList -Command 'sf x "abc' } | Should -Throw -ExpectedMessage 'Unterminated quote*'
        }

        It 'throws on an empty command' {
            { ConvertTo-PsfdxArgumentList -Command '   ' } | Should -Throw -ExpectedMessage 'Command is empty.'
        }
    }

    Describe 'Get-PsfdxRedactedCommand' {
        It 'masks secret option values' {
            Get-PsfdxRedactedCommand -Command 'sf org login x --password hunter2 --client-secret "a b" --alias me --json' |
                Should -Be 'sf org login x --password ******** --client-secret ******** --alias me --json'
        }

        It 'masks sfdx auth urls and tokens' {
            Get-PsfdxRedactedCommand -Command 'sf x --sfdx-url force://abc@d.com --access-token=tok' |
                Should -Be 'sf x --sfdx-url ******** --access-token=********'
        }

        It 'leaves ordinary commands alone' {
            Get-PsfdxRedactedCommand -Command 'sf org list --json' | Should -Be 'sf org list --json'
        }
    }

    Describe 'Resolve-PsfdxNativeArguments for Windows .cmd shims' {
        BeforeEach {
            Mock Test-PsfdxIsWindows { $true }
            Mock Test-PsfdxIsCmdShim { $true }
        }

        It 'keeps % usable by routing it through a variable that expands to a literal %' {
            $r = @(Resolve-PsfdxNativeArguments -FilePath 'sf' -Arguments @("SELECT Id FROM Account WHERE Name LIKE 'Acme%'"))
            $r[0] | Should -Be "SELECT Id FROM Account WHERE Name LIKE 'Acme%PSFDX_PERCENT%'"
        }

        It 'handles prefix, infix and literal %NAME% arguments' {
            $r = @(Resolve-PsfdxNativeArguments -FilePath 'sf' -Arguments @('%a b', 'a%b c', '%NAME%'))
            $r[0] | Should -Be '%PSFDX_PERCENT%a b'
            $r[1] | Should -Be 'a%PSFDX_PERCENT%b c'
            $r[2] | Should -Be '%PSFDX_PERCENT%NAME%PSFDX_PERCENT%'
        }

        It 'still rejects double quotes and unsafe metacharacters' {
            { Resolve-PsfdxNativeArguments -FilePath 'sf' -Arguments @('a"b') } | Should -Throw
            { Resolve-PsfdxNativeArguments -FilePath 'sf' -Arguments @('a&b') } | Should -Throw
        }

        It 'leaves % untouched on non-Windows' {
            Mock Test-PsfdxIsWindows { $false }
            @(Resolve-PsfdxNativeArguments -FilePath 'sf' -Arguments @("x LIKE 'A%'"))[0] | Should -Be "x LIKE 'A%'"
        }
    }

    Describe 'Invoke-Salesforce' {
        It 'does not call Invoke-Expression' {
            (Get-Command Invoke-Salesforce).ScriptBlock.ToString() | Should -Not -Match 'Invoke-Expression\s+-|iex\s'
        }

        It 'does not echo secrets to the verbose stream' {
            Mock ConvertTo-PsfdxArgumentList { [pscustomobject]@{ FilePath = 'psfdx-nonexistent-exe'; Arguments = [string[]]@() } }
            Mock Resolve-PsfdxNativeArguments { [string[]]@() }
            $verbose = & {
                try { Invoke-Salesforce -Command 'sf org login x --password hunter2 --json' -Verbose 4>&1 } catch { }
            } | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($verbose | Out-String) | Should -Not -Match 'hunter2'
            ($verbose | Out-String) | Should -Match '\*\*\*\*\*\*\*\*'
        }
    }

    # A harmless fake "sf" that prints each argument it receives as <arg>, so the tests see the exact argv.
    # Linux/macOS: a shell script. Windows: a tiny console exe compiled with the .NET Framework csc that ships
    # with Windows, so this also covers native argument passing on Windows PowerShell 5.1 and PowerShell 7.
    # (Do not guard with $IsWindows: it does not exist on Windows PowerShell 5.1, which would run the shell script there.)
    Describe 'Get-SalesforceApexCliTestArguments' {
        It 'returns the test level only when there are no tests' {
            (Get-SalesforceApexCliTestArguments -TestLevel TestsInOrg) -join '|' | Should -Be '--test-level|RunLocalTests'
        }
        It 'returns one --tests pair per class, sorted and de-duplicated' {
            (Get-SalesforceApexCliTestArguments -TestLevel SpecificTests -Tests 'BTest','ATest','ATest',' ') -join '|' | Should -Be '--test-level|RunSpecifiedTests|--tests|ATest|--tests|BTest'
        }
    }

    Describe 'ConvertFrom-SalesforceJsonOutput and Show-SalesforceResult failures' {
        It 'throws for empty, null and whitespace output' {
            { Show-SalesforceResult -Result '' } | Should -Throw -ExpectedMessage '*no output*'
            { Show-SalesforceResult -Result @('', '  ') } | Should -Throw -ExpectedMessage '*no output*'
            { ConvertFrom-SalesforceJsonOutput -Output $null } | Should -Throw -ExpectedMessage '*no output*'
        }

        It 'throws for non-JSON text and shows a redacted preview' {
            { Show-SalesforceResult -Result 'Warning: sf update available' } | Should -Throw -ExpectedMessage '*not valid JSON*sf update available*'
            $message = try { Show-SalesforceResult -Result 'bad force://PlatformCLI::abc@x.salesforce.com' } catch { $_.Exception.Message }
            $message | Should -Not -Match 'PlatformCLI'
        }

        It 'throws for malformed or partial JSON' {
            { Show-SalesforceResult -Result '{"status":0,"result":{"records":[' } | Should -Throw -ExpectedMessage '*not valid JSON*'
        }

        It 'throws for JSON without a status or that is an array' {
            { Show-SalesforceResult -Result '{"result":{}}' } | Should -Throw -ExpectedMessage '*unexpected shape*'
            { Show-SalesforceResult -Result '[1,2]' } | Should -Throw -ExpectedMessage '*unexpected shape*'
            { Show-SalesforceResult -Result '"text"' } | Should -Throw -ExpectedMessage '*unexpected shape*'
        }

        It 'truncates long previews' {
            $long = 'x' * 1000
            $message = try { Show-SalesforceResult -Result $long } catch { $_.Exception.Message }
            $message.Length | Should -BeLessThan 300
        }

        It 'reads multi-line JSON passed as an array of lines' {
            $lines = @('{', '"status": 0,', '"result": {"a": 1}', '}')
            (Show-SalesforceResult -Result $lines).a | Should -Be 1
        }

        It 'reports an authentication error message and never leaks tokens' {
            $json = '{"status":1,"name":"NoAuthFound","message":"No authorization information found for me@x.com.","result":{"accessToken":"00Dleak"}}'
            $message = try { Show-SalesforceResult -Result $json } catch { $_.Exception.Message }
            $message | Should -Be 'No authorization information found for me@x.com.'
            $message | Should -Not -Match '00Dleak'
        }

        It 'ignores warnings arrays when status is 0' {
            $r = Show-SalesforceResult -Result '{"status":0,"result":{"ok":true},"warnings":["update available"]}'
            $r.ok | Should -BeTrue
        }
    }

    Describe 'Invoke-Salesforce process failures' {
        BeforeAll {
            $script:host = (Get-Process -Id $PID).Path
            $script:script = Join-Path $TestDrive 'exit.ps1'
            Set-Content -LiteralPath $script:script -Encoding ascii -Value @'
param([string]$Out, [string]$OutFile, [int]$Code)
if ($OutFile) { $Out = Get-Content -Raw -LiteralPath $OutFile }
if ($Out) { [Console]::Out.Write($Out) }
exit $Code
'@
        }

        It 'throws when the process fails with no output in JSON mode' {
            { Invoke-Salesforce -Command "`"$($script:host)`" -NoProfile -File `"$($script:script)`" -Code 3 --json" } |
                Should -Throw -ExpectedMessage '*exited with code 3*'
        }

        It 'throws with a redacted detail when the process fails with non-JSON output' {
            { Invoke-Salesforce -Command "`"$($script:host)`" -NoProfile -File `"$($script:script)`" -Out force://PlatformCLI::abc@x.com -Code 2 --json" } |
                Should -Throw -ExpectedMessage '*exited with code 2*force://*********'
        }

        It 'returns the JSON error body of a failed process so the message is reported' {
            $body = Join-Path $TestDrive 'body.json'
            Set-Content -LiteralPath $body -Value '{"status":1,"message":"boom"}'
            $out = Invoke-Salesforce -Command "`"$($script:host)`" -NoProfile -File `"$($script:script)`" -OutFile `"$body`" -Code 1 --json"
            { Show-SalesforceResult -Result $out } | Should -Throw -ExpectedMessage 'boom'
        }

        It 'does not throw for a failed process without --json' {
            { Invoke-Salesforce -Command "`"$($script:host)`" -NoProfile -File `"$($script:script)`" -Code 4" } | Should -Not -Throw
        }

        It 'does not throw when the process succeeds' {
            { Invoke-Salesforce -Command "`"$($script:host)`" -NoProfile -File `"$($script:script)`" -Out ok -Code 0 --json" } | Should -Not -Throw
        }
    }

    Describe 'Invoke-Salesforce with a fake executable' {
        BeforeAll {
            $script:onWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
            $script:fakeDir = Join-Path $TestDrive 'fake bin'
            New-Item -ItemType Directory -Path $script:fakeDir | Out-Null
            if ($script:onWindows) {
                $script:fake = Join-Path $script:fakeDir 'fakesf.exe'
                $source = Join-Path $script:fakeDir 'fakesf.cs'
                Set-Content -LiteralPath $source -Encoding ascii -Value @'
using System;
using System.IO;
using System.Text;
public static class FakeSf {
    public static int Main(string[] args) {
        var writer = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false));
        foreach (var a in args) { writer.Write("<" + a + ">\n"); }
        writer.Flush();
        return 0;
    }
}
'@
                $csc = Join-Path $env:windir (Join-Path 'Microsoft.NET' (Join-Path 'Framework64' (Join-Path 'v4.0.30319' 'csc.exe')))
                & $csc /nologo "/out:$($script:fake)" $source | Out-Null
                if (-not (Test-Path -LiteralPath $script:fake)) { throw 'Could not build the fake executable.' }
                # PowerShell decodes native output with the console encoding; the fake writes UTF-8.
                $script:savedEncoding = [Console]::OutputEncoding
                [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
            } else {
                $script:fake = Join-Path $script:fakeDir 'fakesf'
                Set-Content -LiteralPath $script:fake -Value "#!/bin/sh`nfor a in `"`$@`"; do printf '<%s>\n' `"`$a`"; done" -Encoding ascii
                & chmod +x $script:fake
            }
        }

        AfterAll {
            if ($script:onWindows -and $script:savedEncoding) { [Console]::OutputEncoding = $script:savedEncoding }
        }

        It 'passes the exact argv' {
            $out = @(Invoke-Salesforce -Command "`"$($script:fake)`" one `"two words`" three")
            $out | Should -Be @('<one>', '<two words>', '<three>')
        }

        It 'does not execute injected commands' {
            $marker = Join-Path $TestDrive 'pwned.txt'
            $payload = "x; New-Item -ItemType File -Path '$marker'; `$(New-Item -ItemType File -Path '$marker')"
            $out = @(Invoke-Salesforce -Command "`"$($script:fake)`" --name `"$payload`" --json")
            Test-Path -LiteralPath $marker | Should -BeFalse
            $out[1] | Should -Be "<$payload>"
        }

        It 'passes SOQL with apostrophes and operators intact' {
            $soql = "SELECT Id FROM Account WHERE Name = 'O''Brien' AND Rating != 'Hot' AND X > 1"
            $out = @(Invoke-Salesforce -Command "`"$($script:fake)`" data query --query `"$soql`" --json")
            $out[3] | Should -Be "<$soql>"
        }

        It 'passes file paths with spaces and Unicode' {
            $path = Join-Path $TestDrive 'dir with space/Zoë 日本.apex'
            $out = @(Invoke-Salesforce -Command "`"$($script:fake)`" --file `"$path`"")
            $out[1] | Should -Be "<$path>"
        }

        It 'passes a structured argument array exactly, with no quoting needed' {
            $values = @('two words', "O'Brien", 'say "hi"', 'C:\path with space\dir', 'Zoë 日本', '-leading-hyphen', '--json-not-a-flag x', '; Remove-Item x', '$(Get-Date)')
            # Windows .cmd shims reject double quotes by design; the fake is a real executable, so it accepts them.
            $out = @(Invoke-Salesforce -FilePath $script:fake -Arguments $values)
            $out | Should -Be @($values | ForEach-Object { "<$_>" })
        }

        It 'passes % through untouched to a real executable' {
            $out = @(Invoke-Salesforce -FilePath $script:fake -Arguments @('100%', '%PATH%'))
            $out | Should -Be @('<100%>', '<%PATH%>')
        }

        It 'accepts an empty argument list' {
            { Invoke-Salesforce -FilePath $script:fake -Arguments @() } | Should -Not -Throw
        }

        It 'does not execute injected commands from structured arguments' {
            $marker = Join-Path $TestDrive 'pwned2.txt'
            $payload = "x; New-Item -ItemType File -Path '$marker'"
            Invoke-Salesforce -FilePath $script:fake -Arguments @('--name', $payload) | Out-Null
            Test-Path -LiteralPath $marker | Should -BeFalse
        }

        It 'shows the structured command in -Verbose with secrets masked' {
            $verbose = Invoke-Salesforce -FilePath $script:fake -Arguments @('--password', 'hunter2', '--name', 'two words') -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | Out-String
            $verbose | Should -Not -Match 'hunter2'
            $verbose | Should -Match '"two words"'
        }

        It 'returns raw non-JSON output untouched (csv and human)' {
            $out = @(Invoke-Salesforce -Command "`"$($script:fake)`" data query --result-format csv")
            $out | Should -Be @('<data>', '<query>', '<--result-format>', '<csv>')
        }
    }

Describe 'Argument transport table (issue 184)' {
    $isWin = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
    $hasPwsh = [bool](Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue)
    BeforeAll {
        $script:windowsHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
        $nbsp = [string][char]0x00A0
        # Name, value, and whether the argument can reach the program unchanged ('exact') or must be refused on a Windows .cmd shim ('reject').
        $script:cases = @(
            @{ Name = 'ampersand in spaced text'; Value = 'a & b'; Windows = 'exact' }
            @{ Name = 'pipe in spaced text'; Value = 'a | b'; Windows = 'exact' }
            @{ Name = 'caret in spaced text'; Value = 'a ^ b'; Windows = 'exact' }
            @{ Name = 'redirects in spaced text'; Value = 'a > b < c'; Windows = 'exact' }
            @{ Name = 'trailing backslash'; Value = 'C:\dir\'; Windows = 'exact' }
            @{ Name = 'trailing backslash after a space'; Value = 'C:\my dir\'; Windows = 'exact' }
            @{ Name = 'two trailing backslashes after a space'; Value = 'C:\my dir\\'; Windows = 'exact' }
            @{ Name = 'LIKE with a trailing percent'; Value = "SELECT Id FROM Account WHERE Name LIKE 'Acme%'"; Windows = 'exact' }
            @{ Name = 'LIKE with a leading percent'; Value = "SELECT Id FROM Account WHERE Name LIKE '%Acme'"; Windows = 'exact' }
            @{ Name = 'literal percent name'; Value = "SELECT Id FROM Account WHERE Name = '%NAME%'"; Windows = 'exact' }
            @{ Name = 'percent environment variable'; Value = '%PATH%'; Windows = 'exact' }
            @{ Name = 'percent next to text'; Value = 'a%b c%'; Windows = 'exact' }
            @{ Name = 'exclamation mark'; Value = 'Hello!World!'; Windows = 'exact' }
            @{ Name = 'parentheses'; Value = 'a(b) (c)'; Windows = 'exact' }
            @{ Name = 'apostrophe'; Value = "O'Brien's"; Windows = 'exact' }
            @{ Name = 'backtick'; Value = 'back`tick `n'; Windows = 'exact' }
            @{ Name = 'PowerShell expressions'; Value = '$(whoami) $env:PATH ${x}'; Windows = 'exact' }
            @{ Name = 'semicolon'; Value = 'a;b;c'; Windows = 'exact' }
            @{ Name = 'unicode'; Value = ('caf' + [char]0x00E9 + ' ' + [char]0x4E16 + [char]0x754C); Windows = 'exact' }
            @{ Name = 'tab as the only whitespace with a metacharacter'; Value = "x&echo`twhoami"; Windows = 'exact' }
            @{ Name = 'vertical tab as the only whitespace with a metacharacter'; Value = ('x&echo' + [char]0x0B + 'whoami'); Windows = 'exact' }
            @{ Name = 'form feed as the only whitespace with a metacharacter'; Value = ('x&echo' + [char]0x0C + 'whoami'); Windows = 'exact' }
            @{ Name = 'no-break space as the only whitespace with a metacharacter'; Value = ('x&echo' + $nbsp + 'whoami'); Windows = 'exact' }
            @{ Name = 'em space as the only whitespace with a metacharacter'; Value = ('x&echo' + [char]0x2003 + 'whoami'); Windows = 'exact' }
            @{ Name = 'double quote'; Value = 'a"b'; Windows = 'reject' }
            @{ Name = 'line feed'; Value = "a`nb"; Windows = 'reject' }
            @{ Name = 'carriage return'; Value = "a`rb c"; Windows = 'reject' }
            @{ Name = 'bare ampersand'; Value = 'x&whoami'; Windows = 'reject' }
            @{ Name = 'bare pipe'; Value = 'x|more'; Windows = 'reject' }
            @{ Name = 'bare redirect'; Value = 'x>out.txt'; Windows = 'reject' }
            @{ Name = 'bare caret'; Value = 'a^b'; Windows = 'reject' }
            @{ Name = 'a command line over the cmd.exe limit'; Value = ('x' * 9000); Windows = 'reject' }
        )
    }

    Context 'Windows .cmd shim, in PowerShell 7 and Windows PowerShell 5.1' {
        BeforeAll {
            if ($script:windowsHost) {
                $script:shimDir = Join-Path $TestDrive 'table shim'
                New-Item -ItemType Directory -Path $script:shimDir | Out-Null
                $source = Join-Path $script:shimDir 'argvcapture.cs'
                Set-Content -LiteralPath $source -Encoding ascii -Value @'
using System;
using System.IO;
using System.Text;
public static class ArgvCapture {
    public static int Main(string[] args) {
        var writer = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false));
        foreach (var a in args) { writer.Write("<" + a + ">\n"); }
        writer.Flush();
        return 0;
    }
}
'@
                $csc = Join-Path $env:windir (Join-Path 'Microsoft.NET' (Join-Path 'Framework64' (Join-Path 'v4.0.30319' 'csc.exe')))
                & $csc /nologo "/out:$(Join-Path $script:shimDir 'argvcapture.exe')" $source | Out-Null
                Set-Content -LiteralPath (Join-Path $script:shimDir 'sf.cmd') -Encoding ascii -Value "@echo off`r`n`"%~dp0argvcapture.exe`" %*"
                $script:casesFile = Join-Path $script:shimDir 'cases.json'
                ConvertTo-Json -InputObject @($script:cases | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } }) -Depth 4 | Set-Content -LiteralPath $script:casesFile -Encoding utf8
                $script:runner = Join-Path $script:shimDir 'run.ps1'
                Set-Content -LiteralPath $script:runner -Encoding utf8 -Value @'
param([string] $ShimDir, [string] $CasesFile, [string] $Manifest, [string] $OutFile)
$env:PATH = $ShimDir + ';' + $env:PATH
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Import-Module $Manifest -Force
$cases = @(Get-Content -LiteralPath $CasesFile -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
$rows = @()
foreach ($case in $cases) {
    $failure = $null; $lines = @()
    try { $lines = @(Invoke-Salesforce -FilePath 'sf' -Arguments @('--probe', [string]$case.Value)) } catch { $failure = $_.Exception.Message }
    $rows += [pscustomobject]@{ Name = $case.Name; Error = $failure; Lines = @($lines | ForEach-Object { [string]$_ }) }
}
$leftover = @([System.Environment]::GetEnvironmentVariables().Keys | Where-Object { $_ -like 'PSFDX_PERCENT*' })
ConvertTo-Json -InputObject ([pscustomobject]@{ Rows = $rows; Leftover = $leftover }) -Depth 6 | Set-Content -LiteralPath $OutFile -Encoding utf8
'@
                $script:sharedManifest = Join-Path (Split-Path -Parent $PSScriptRoot) (Join-Path 'psfdx-shared' 'psfdx-shared.psd1')
            }
        }

        foreach ($shell in @('pwsh', 'powershell')) {
            $available = ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) -and [bool](Get-Command $shell -CommandType Application -ErrorAction SilentlyContinue)
            It "passes every table case exactly or refuses it with a clear error in $shell, and leaves no environment variable behind" -TestCases @(@{ shell = $shell }) -Skip:(-not $available) {
                param($shell)
                $outFile = Join-Path $script:shimDir "table-$shell.json"
                & $shell -NoProfile -ExecutionPolicy Bypass -File $script:runner -ShimDir $script:shimDir -CasesFile $script:casesFile -Manifest $script:sharedManifest -OutFile $outFile | Out-Null
                $parsed = Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 | ConvertFrom-Json
                $rows = @($parsed.Rows | ForEach-Object { $_ })
                $rows.Count | Should -Be $script:cases.Count
                for ($n = 0; $n -lt $script:cases.Count; $n++) {
                    $case = $script:cases[$n]
                    $row = $rows[$n]
                    $row.Name | Should -Be $case.Name
                    if ($case.Windows -eq 'exact') {
                        $row.Error | Should -BeNullOrEmpty -Because $case.Name
                        $lines = @($row.Lines | ForEach-Object { $_ })
                        $lines.Count | Should -Be 2 -Because $case.Name
                        $lines[0] | Should -Be '<--probe>'
                        $lines[1] | Should -Be ('<' + $case.Value + '>') -Because $case.Name
                    } else {
                        $row.Error | Should -Not -BeNullOrEmpty -Because $case.Name
                        if ($case.Name -like '*over the cmd.exe limit*') { $row.Error | Should -BeLike '*characters long*' } else { $row.Error | Should -BeLike '*cannot be passed safely*' -Because $case.Name }
                        @($row.Lines | ForEach-Object { $_ }).Count | Should -Be 0 -Because $case.Name
                    }
                }
                @($parsed.Leftover | ForEach-Object { $_ }).Count | Should -Be 0
            }
        }

        It 'runs concurrent calls in one process without losing a percent sign or leaving a variable' -Skip:(-not ($isWin -and $hasPwsh)) {
            $concurrent = Join-Path $script:shimDir 'concurrent.ps1'
            Set-Content -LiteralPath $concurrent -Encoding utf8 -Value @'
param([string] $ShimDir, [string] $Manifest, [string] $OutFile)
$env:PATH = $ShimDir + ';' + $env:PATH
$rows = 1..6 | ForEach-Object -Parallel {
    Import-Module $using:Manifest -Force
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $bad = 0
    for ($i = 0; $i -lt 15; $i++) {
        $out = @(Invoke-Salesforce -FilePath 'sf' -Arguments @('--probe', "Name LIKE 'Acme%' AND X = '%NAME%'"))
        if ($out.Count -lt 2 -or $out[1] -ne "<Name LIKE 'Acme%' AND X = '%NAME%'>") { $bad++ }
    }
    $bad
} -ThrottleLimit 6
$leftover = @([System.Environment]::GetEnvironmentVariables().Keys | Where-Object { $_ -like 'PSFDX_PERCENT*' })
ConvertTo-Json -InputObject ([pscustomobject]@{ Bad = ($rows | Measure-Object -Sum).Sum; Leftover = $leftover }) | Set-Content -LiteralPath $OutFile -Encoding utf8
'@
            $outFile = Join-Path $script:shimDir 'concurrent.json'
            & pwsh -NoProfile -File $concurrent -ShimDir $script:shimDir -Manifest $script:sharedManifest -OutFile $outFile | Out-Null
            $result = Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $result.Bad | Should -Be 0
            @($result.Leftover | ForEach-Object { $_ }).Count | Should -Be 0
        }
    }

    Context 'Unix executable' {
        BeforeAll {
            if (-not $script:windowsHost) {
                $script:unixDir = Join-Path $TestDrive 'unix table'
                New-Item -ItemType Directory -Path $script:unixDir | Out-Null
                $script:unixFake = Join-Path $script:unixDir 'fakesf'
                Set-Content -LiteralPath $script:unixFake -Value "#!/bin/sh`nfor a in `"`$@`"; do printf '<%s>\n' `"`$a`"; done" -Encoding ascii
                & chmod +x $script:unixFake
            }
        }

        It 'passes every table case unchanged, because no shell is involved' -Skip:$isWin {
            foreach ($case in $script:cases) {
                # Line breaks are not testable through a line-oriented fake.
                if ($case.Value -match '[\r\n]') { continue }
                $lines = @(Invoke-Salesforce -FilePath $script:unixFake -Arguments @('--probe', [string]$case.Value))
                $lines.Count | Should -Be 2 -Because $case.Name
                $lines[1] | Should -Be ('<' + $case.Value + '>') -Because $case.Name
            }
        }
    }

    Context 'Resolve-PsfdxNativeArguments' {
        BeforeEach {
            Mock Test-PsfdxIsWindows { $true }
        }

        It 'uses the percent variable it is given, so each call can have its own' {
            Mock Test-PsfdxIsCmdShim { $true }
            @(Resolve-PsfdxNativeArguments -FilePath 'sf' -Arguments @('a%b') -PercentVariable 'PSFDX_PERCENT_abc12345')[0] | Should -Be 'a%PSFDX_PERCENT_abc12345%b'
        }

        It 'refuses a command line over the limit with advice, and allows one just under it' {
            Mock Test-PsfdxIsCmdShim { $true }
            { Resolve-PsfdxNativeArguments -FilePath 'sf' -Arguments @('x' * 9000) } | Should -Throw -ExpectedMessage '*Shorten the query*--file*'
            { Resolve-PsfdxNativeArguments -FilePath 'sf' -Arguments @('x' * 7000) } | Should -Not -Throw
        }

        It 'counts the extra characters a percent sign adds' {
            Mock Test-PsfdxIsCmdShim { $true }
            { Resolve-PsfdxNativeArguments -FilePath 'sf' -Arguments @('%' * 1000) } | Should -Throw -ExpectedMessage '*characters long after preparation*'
        }

        It 'does not apply the limit to a native executable' {
            Mock Test-PsfdxIsCmdShim { $false }
            { Resolve-PsfdxNativeArguments -FilePath 'sf' -Arguments @('x' * 9000) } | Should -Not -Throw
        }
    }

    Context 'ConvertTo-PsfdxArgumentList edge cases' {
        It 'splits on any whitespace, including tabs and line breaks' {
            $r = ConvertTo-PsfdxArgumentList -Command "sf`tdata`r`nquery"
            $r.FilePath | Should -Be 'sf'
            @($r.Arguments) | Should -Be @('data', 'query')
        }
        It 'keeps a trailing backslash and a backslash before a quote as literal text' {
            @((ConvertTo-PsfdxArgumentList -Command 'sf C:\dir\ next').Arguments) | Should -Be @('C:\dir\', 'next')
            @((ConvertTo-PsfdxArgumentList -Command 'sf "C:\my dir\" next').Arguments) | Should -Be @('C:\my dir\', 'next')
        }
        It 'handles backtick and quote combinations' {
            @((ConvertTo-PsfdxArgumentList -Command 'sf "a`"b" ''c''''d'' e`f').Arguments) | Should -Be @('a"b', "c'd", 'ef')
            @((ConvertTo-PsfdxArgumentList -Command 'sf "a`xb"').Arguments) | Should -Be @('a`xb')
        }
        It 'keeps nested quotes of the other kind literal' {
            @((ConvertTo-PsfdxArgumentList -Command "sf `"it's`" 'say `"hi`"'").Arguments) | Should -Be @("it's", 'say "hi"')
        }
        It 'keeps control characters and Unicode inside a token' {
            @((ConvertTo-PsfdxArgumentList -Command ("sf `"a" + [char]0x1 + "b`" caf" + [char]0xE9)).Arguments).Count | Should -Be 2
        }
        It 'treats a lone trailing backtick as literal' {
            @((ConvertTo-PsfdxArgumentList -Command 'sf abc`').Arguments) | Should -Be @('abc`')
        }
    }
}
}

# Windows only: an offline sf.cmd shim (like the real one, it forwards %* to a program) that records argv.
# Select-SalesforceRecords is run through the real Windows invocation path in PowerShell 7 and Windows PowerShell 5.1.
Describe 'Select-SalesforceRecords through a Windows sf.cmd shim' {
    BeforeAll {
        $script:onWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
        if ($script:onWindows) {
            $script:shimDir = Join-Path $TestDrive 'shim bin'
            New-Item -ItemType Directory -Path $script:shimDir | Out-Null
            $source = Join-Path $script:shimDir 'argvcapture.cs'
            Set-Content -LiteralPath $source -Encoding ascii -Value @'
using System;
using System.IO;
using System.Text;
public static class ArgvCapture {
    public static int Main(string[] args) {
        var writer = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false));
        foreach (var a in args) { writer.Write("<" + a + ">\n"); }
        writer.Flush();
        return 0;
    }
}
'@
            $csc = Join-Path $env:windir (Join-Path 'Microsoft.NET' (Join-Path 'Framework64' (Join-Path 'v4.0.30319' 'csc.exe')))
            & $csc /nologo "/out:$(Join-Path $script:shimDir 'argvcapture.exe')" $source | Out-Null
            Set-Content -LiteralPath (Join-Path $script:shimDir 'sf.cmd') -Encoding ascii -Value "@echo off`r`n`"%~dp0argvcapture.exe`" %*"

            $script:queries = @(
                "SELECT Id FROM Account WHERE Name LIKE 'Acme%'",
                "SELECT Id FROM Account WHERE Name LIKE '%Acme'",
                "SELECT Id FROM Account WHERE Name LIKE 'Ac%me'",
                "SELECT Id FROM Account WHERE Name = '%NAME%' AND Site = '%PATH%'",
                "SELECT Id FROM Account WHERE Name = 'a&b|c^d<e>f;g' AND X > 1 AND Y = '`$(whoami)'",
                "SELECT   Id   FROM Account WHERE Name LIKE '%two  spaces%'"
            )
            $script:queryFile = Join-Path $script:shimDir 'queries.json'
            ConvertTo-Json -InputObject $script:queries | Set-Content -LiteralPath $script:queryFile -Encoding utf8
            $script:runner = Join-Path $script:shimDir 'run.ps1'
            Set-Content -LiteralPath $script:runner -Encoding utf8 -Value @'
param([string] $ShimDir, [string] $QueryFile, [string] $Manifest, [string] $OutFile)
$env:PATH = $ShimDir + ';' + $env:PATH
Import-Module $Manifest -Force
$queries = @(Get-Content -LiteralPath $QueryFile -Raw | ConvertFrom-Json | ForEach-Object { $_ })
$results = @()
foreach ($q in $queries) {
    $lines = @(Select-SalesforceRecords -Query $q -TargetOrg my-org -ResultFormat csv)
    $results += ,@($lines)
}
ConvertTo-Json -InputObject $results -Depth 5 | Set-Content -LiteralPath $OutFile -Encoding utf8
'@
            $script:manifest = Join-Path (Split-Path -Parent $PSScriptRoot) (Join-Path 'psfdx' 'psfdx.psd1')
        }
    }

    $windowsHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
    foreach ($shellCase in @(
        @{ shell = 'pwsh'; available = ($windowsHost -and [bool](Get-Command 'pwsh' -CommandType Application -ErrorAction SilentlyContinue)) },
        @{ shell = 'powershell'; available = ($windowsHost -and [bool](Get-Command 'powershell' -CommandType Application -ErrorAction SilentlyContinue)) }
    )) {
        It "passes % and metacharacters literally in $($shellCase.shell)" -TestCases @($shellCase) -Skip:(-not $shellCase.available) {
            param($shell)
            $outFile = Join-Path $script:shimDir "out-$shell.json"
            & $shell -NoProfile -ExecutionPolicy Bypass -File $script:runner -ShimDir $script:shimDir -QueryFile $script:queryFile -Manifest $script:manifest -OutFile $outFile | Out-Null
            # Windows PowerShell 5.1 returns the JSON array as one object, so iterate it with foreach (same on 5.1 and 7)
            # and keep each inner argv array whole.
            $parsed = Get-Content -LiteralPath $outFile -Raw | ConvertFrom-Json
            $results = @()
            foreach ($item in $parsed) { $results += , @($item) }
            $results.Count | Should -Be $script:queries.Count
            for ($n = 0; $n -lt $script:queries.Count; $n++) {
                $argv = @($results[$n])
                $argv.Count | Should -Be 8
                $argv[0] | Should -Be '<data>'
                $argv[1] | Should -Be '<query>'
                $argv[2] | Should -Be '<--query>'
                $argv[3] | Should -Be ('<' + $script:queries[$n] + '>')
                $argv[4] | Should -Be '<--target-org>'
                $argv[5] | Should -Be '<my-org>'
                $argv[6] | Should -Be '<--result-format>'
                $argv[7] | Should -Be '<csv>'
            }
        }
    }
}

Describe 'ConvertTo-SalesforceSoqlLiteral' {
    It 'quotes a plain value' {
        ConvertTo-SalesforceSoqlLiteral -Value 'Acme' | Should -Be "'Acme'"
        ConvertTo-SalesforceSoqlLiteral -Value '' | Should -Be "''"
        ConvertTo-SalesforceSoqlLiteral -Value $null | Should -Be "''"
    }

    It 'escapes an apostrophe with a backslash, not by doubling it' {
        ConvertTo-SalesforceSoqlLiteral -Value "O'Brien" | Should -Be "'O\'Brien'"
    }

    It 'escapes backslashes, including one at the end and one before an apostrophe' {
        ConvertTo-SalesforceSoqlLiteral -Value 'a\b' | Should -Be "'a\\b'"
        ConvertTo-SalesforceSoqlLiteral -Value 'end\' | Should -Be "'end\\'"
        ConvertTo-SalesforceSoqlLiteral -Value "\'" | Should -Be "'\\\''"
    }

    It 'keeps a malicious-looking value inside the literal' {
        ConvertTo-SalesforceSoqlLiteral -Value "x' OR Name != '" | Should -Be "'x\' OR Name != \''"
        ConvertTo-SalesforceSoqlLiteral -Value "x\' OR 1=1 --" | Should -Be "'x\\\' OR 1=1 --'"
        ConvertTo-SalesforceSoqlLiteral -Value "'); DELETE FROM Account; --" | Should -Be "'\'); DELETE FROM Account; --'"
    }

    It 'keeps unicode text as it is' {
        ConvertTo-SalesforceSoqlLiteral -Value 'Zoë 日本語' | Should -Be "'Zoë 日本語'"
    }

    It 'writes line breaks, tabs, backspace and form feed as escapes, never as real characters' {
        ConvertTo-SalesforceSoqlLiteral -Value "a`nb`r`n`tc`bd`fe" | Should -Be "'a\nb\r\n\tc\bd\fe'"
    }

    It 'refuses other control characters' {
        { ConvertTo-SalesforceSoqlLiteral -Value "a$([char]1)b" } | Should -Throw -ExpectedMessage '*control character (U+0001)*'
        { ConvertTo-SalesforceSoqlLiteral -Value "a$([char]0)b" } | Should -Throw -ExpectedMessage '*U+0000*'
        { ConvertTo-SalesforceSoqlLiteral -Value "a$([char]0x7F)b" } | Should -Throw -ExpectedMessage '*U+007F*'
    }

    It 'leaves % and _ alone for an = comparison' {
        ConvertTo-SalesforceSoqlLiteral -Value '50%_off' | Should -Be "'50%_off'"
    }

    It 'escapes % and _ with -Like so they match themselves' {
        ConvertTo-SalesforceSoqlLiteral -Value '50%_off' -Like | Should -Be "'50\%\_off'"
    }

    It 'accepts a value from the pipeline' {
        ('a', "b'c" | ConvertTo-SalesforceSoqlLiteral) -join '|' | Should -Be "'a'|'b\'c'"
    }

    It 'survives the command-line splitter as exactly the intended query' {
        InModuleScope 'psfdx-shared' {
            foreach ($value in @("O'Brien", 'a"b', 'tick`tock', 'x$(whoami)y', 'end\', "x' OR Name != '", 'a;b|c&d', '<>', 'two  spaces')) {
                $literal = ConvertTo-SalesforceSoqlLiteral -Value $value
                $parsed = ConvertTo-PsfdxArgumentList -Command ('sf data query --query "SELECT Id FROM Account WHERE Name = ' + $literal + '" --json')
                @($parsed.Arguments).Count | Should -Be 5 -Because "the value '$value' must not add or remove arguments"
                # What reaches sf is the SOQL literal with only the command-line escapes removed.
                $expected = 'SELECT Id FROM Account WHERE Name = ' + (($literal -replace '\\`"', '\"') -replace '``', '`')
                @($parsed.Arguments)[3] | Should -Be $expected
                @($parsed.Arguments)[4] | Should -Be '--json'
            }
        }
    }
}

Describe 'ConvertTo-SalesforceSoqlIdentifier' {
    It 'accepts object and field API names, custom names and relationships' {
        foreach ($name in 'Account', 'My_Object__c', 'Owner.Name', 'Account.Owner.Profile.Name', 'Field_1__r') {
            ConvertTo-SalesforceSoqlIdentifier -Value $name | Should -Be $name
        }
    }

    It 'refuses anything that could change the query' {
        foreach ($name in '', ' ', 'Account WHERE 1=1', 'Account;', "Account'", 'Acc ount', '1Account', 'Account.', '.Name', 'Name--', 'A,B', 'Account)') {
            { ConvertTo-SalesforceSoqlIdentifier -Value $name } | Should -Throw -ExpectedMessage '*not a valid Salesforce object or field API name*'
        }
        { ConvertTo-SalesforceSoqlIdentifier -Value $null } | Should -Throw
    }
}

Describe 'ConvertTo-SalesforceSoqlDateTime' {
    BeforeAll {
        function Get-TestTimeZone {
            param([string[]] $Ids)
            foreach ($id in $Ids) {
                try { return [System.TimeZoneInfo]::FindSystemTimeZoneById($id) } catch { }
            }
            return $null
        }
        # Windows and IANA ids differ, and Windows PowerShell 5.1 knows only the Windows ones.
        $script:London = Get-TestTimeZone -Ids 'GMT Standard Time', 'Europe/London'
        $script:NewYork = Get-TestTimeZone -Ids 'Eastern Standard Time', 'America/New_York'
        $script:Tokyo = Get-TestTimeZone -Ids 'Tokyo Standard Time', 'Asia/Tokyo'
    }

    It 'uses a UTC value as it is' {
        $value = [datetime]::SpecifyKind([datetime]'2026-11-18T11:00:00', [System.DateTimeKind]::Utc)
        ConvertTo-SalesforceSoqlDateTime -Value $value | Should -Be '2026-11-18T11:00:00Z'
    }

    It 'converts a Local value to UTC before writing the Z' {
        $local = [datetime]::SpecifyKind([datetime]'2026-07-01T12:00:00', [System.DateTimeKind]::Local)
        $expected = $local.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) + 'Z'
        ConvertTo-SalesforceSoqlDateTime -Value $local | Should -Be $expected
    }

    It 'treats an Unspecified value as local time, like ToUniversalTime does' {
        $unspecified = [datetime]::SpecifyKind([datetime]'2026-07-01T12:00:00', [System.DateTimeKind]::Unspecified)
        $expected = $unspecified.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) + 'Z'
        ConvertTo-SalesforceSoqlDateTime -Value $unspecified | Should -Be $expected
    }

    It 'sends the same instant for the same moment written in UTC and in local time' {
        $utc = [datetime]::SpecifyKind([datetime]'2026-03-29T00:30:00', [System.DateTimeKind]::Utc)
        ConvertTo-SalesforceSoqlDateTime -Value $utc | Should -Be (ConvertTo-SalesforceSoqlDateTime -Value $utc.ToLocalTime())
    }

    It 'drops fractions of a second and ignores the current culture' {
        $original = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('ar-SA')
            $value = [datetime]::SpecifyKind([datetime]::new(2026, 11, 18, 11, 0, 5, 987), [System.DateTimeKind]::Utc)
            ConvertTo-SalesforceSoqlDateTime -Value $value | Should -Be '2026-11-18T11:00:05Z'
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $original
        }
    }

    It 'accepts a value from the pipeline' {
        $value = [datetime]::SpecifyKind([datetime]'2026-01-02T03:04:05', [System.DateTimeKind]::Utc)
        ($value | ConvertTo-SalesforceSoqlDateTime) | Should -Be '2026-01-02T03:04:05Z'
    }

    Context 'in a named time zone' {
        It 'subtracts an hour for London in summer (BST), the case from the October review' {
            if (-not $script:London) { Set-ItResult -Skipped -Because 'the London time zone is not installed'; return }
            ConvertTo-SalesforceSoqlDateTime -Value ([datetime]'2026-10-21T08:47:12') -TimeZone $script:London | Should -Be '2026-10-21T07:47:12Z'
        }

        It 'does not shift London in winter (GMT)' {
            if (-not $script:London) { Set-ItResult -Skipped -Because 'the London time zone is not installed'; return }
            ConvertTo-SalesforceSoqlDateTime -Value ([datetime]'2026-12-21T08:47:12') -TimeZone $script:London | Should -Be '2026-12-21T08:47:12Z'
        }

        It 'follows the offset change at the clock change in March and October' {
            if (-not $script:London) { Set-ItResult -Skipped -Because 'the London time zone is not installed'; return }
            # 2026: clocks go forward Sunday 29 March at 01:00 UTC and back Sunday 25 October at 01:00 UTC.
            ConvertTo-SalesforceSoqlDateTime -Value ([datetime]'2026-03-29T00:59:59') -TimeZone $script:London | Should -Be '2026-03-29T00:59:59Z'
            ConvertTo-SalesforceSoqlDateTime -Value ([datetime]'2026-03-29T02:00:00') -TimeZone $script:London | Should -Be '2026-03-29T01:00:00Z'
            ConvertTo-SalesforceSoqlDateTime -Value ([datetime]'2026-10-25T00:59:59') -TimeZone $script:London | Should -Be '2026-10-24T23:59:59Z'
            ConvertTo-SalesforceSoqlDateTime -Value ([datetime]'2026-10-25T02:00:00') -TimeZone $script:London | Should -Be '2026-10-25T02:00:00Z'
        }

        It 'refuses the hour that does not exist when the clocks go forward' {
            if (-not $script:London) { Set-ItResult -Skipped -Because 'the London time zone is not installed'; return }
            { ConvertTo-SalesforceSoqlDateTime -Value ([datetime]'2026-03-29T01:30:00') -TimeZone $script:London } |
                Should -Throw -ExpectedMessage '*does not exist in time zone*'
        }

        It 'reads the hour that happens twice when the clocks go back as standard time' {
            if (-not $script:London) { Set-ItResult -Skipped -Because 'the London time zone is not installed'; return }
            ConvertTo-SalesforceSoqlDateTime -Value ([datetime]'2026-10-25T01:30:00') -TimeZone $script:London | Should -Be '2026-10-25T01:30:00Z'
        }

        It 'handles zones behind UTC and ahead of it, and a day boundary' {
            if (-not $script:NewYork -or -not $script:Tokyo) { Set-ItResult -Skipped -Because 'the time zones are not installed'; return }
            ConvertTo-SalesforceSoqlDateTime -Value ([datetime]'2026-07-01T22:00:00') -TimeZone $script:NewYork | Should -Be '2026-07-02T02:00:00Z'
            ConvertTo-SalesforceSoqlDateTime -Value ([datetime]'2026-07-01T01:00:00') -TimeZone $script:Tokyo | Should -Be '2026-06-30T16:00:00Z'
        }

        It 'still uses a UTC value as it is, whatever the zone' {
            if (-not $script:Tokyo) { Set-ItResult -Skipped -Because 'the Tokyo time zone is not installed'; return }
            $utc = [datetime]::SpecifyKind([datetime]'2026-07-01T01:00:00', [System.DateTimeKind]::Utc)
            ConvertTo-SalesforceSoqlDateTime -Value $utc -TimeZone $script:Tokyo | Should -Be '2026-07-01T01:00:00Z'
        }

        It 'reads a Local value in the named zone, not the machine zone' {
            if (-not $script:Tokyo) { Set-ItResult -Skipped -Because 'the Tokyo time zone is not installed'; return }
            $local = [datetime]::SpecifyKind([datetime]'2026-07-01T09:00:00', [System.DateTimeKind]::Local)
            ConvertTo-SalesforceSoqlDateTime -Value $local -TimeZone $script:Tokyo | Should -Be '2026-07-01T00:00:00Z'
        }
    }
}

Describe 'generated SOQL never labels local time as UTC' {
    It 'no module formats a datetime with ToString(''s'') plus Z' {
        $root = Split-Path -Parent $PSScriptRoot
        $offenders = foreach ($file in Get-ChildItem -Path $root -Recurse -Filter '*.psm1' | Where-Object { $_.FullName -notmatch '[\\/](tools|scripts|node_modules)[\\/]' }) {
            Select-String -LiteralPath $file.FullName -Pattern "ToString\('s'\)\s*\+\s*'Z'" | ForEach-Object { "$($file.Name):$($_.LineNumber)" }
        }
        @($offenders) | Should -BeNullOrEmpty -Because 'use ConvertTo-SalesforceSoqlDateTime, which converts to UTC first'
    }
}

# Import-PsfdxSharedModule is copied into every module .psm1 (it has to run before psfdx-shared exists), so these tests
# take the copy out of psfdx/psfdx.psm1 and run it against fake modules named psfdx-fake-shared in $TestDrive.
Describe 'Import-PsfdxSharedModule resolution' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $text = [System.IO.File]::ReadAllText((Join-Path (Join-Path $repoRoot 'psfdx') 'psfdx.psm1'))
        $match = [regex]::Match($text, '(?s)function Import-PsfdxSharedModule \{.*?\r?\n\}\r?\n\r?\nImport-PsfdxSharedModule')
        if (-not $match.Success) { throw 'Import-PsfdxSharedModule not found in psfdx.psm1' }
        $functionText = $match.Value.Substring(0, $match.Value.LastIndexOf('Import-PsfdxSharedModule')).TrimEnd()
        . ([scriptblock]::Create($functionText))

        $script:Fake = 'psfdx-fake-shared'
        $script:OriginalPsModulePath = $env:PSModulePath

        function New-FakeShared {
            param([string] $Folder, [string] $Version)
            New-Item -ItemType Directory -Path $Folder -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $Folder "$script:Fake.psm1") -Value "function Get-FakeSharedVersion { '$Version' }"
            $manifest = "@{ RootModule = '$script:Fake.psm1'; ModuleVersion = '$Version'; GUID = '8a1c5d34-0b6e-4a53-9a5e-2f7f4f3c9d10'; FunctionsToExport = @('Get-FakeSharedVersion') }"
            Set-Content -LiteralPath (Join-Path $Folder "$script:Fake.psd1") -Value $manifest
        }
        function Get-LoadedFake { @(Get-Module -Name $script:Fake) }
    }

    BeforeEach {
        Get-Module -Name $script:Fake -All | Remove-Module -Force -ErrorAction SilentlyContinue
        # An empty PSModulePath keeps a real installed psfdx-shared out of the picture.
        $env:PSModulePath = Join-Path $TestDrive 'empty-psmodulepath'
        $script:Layout = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }

    AfterEach {
        Get-Module -Name $script:Fake -All | Remove-Module -Force -ErrorAction SilentlyContinue
        $env:PSModulePath = $script:OriginalPsModulePath
    }

    It 'uses the sibling folder of a source checkout or flat install' {
        New-FakeShared -Folder (Join-Path $script:Layout $script:Fake) -Version '0.8.5'
        Import-PsfdxSharedModule -ModuleName $script:Fake -ModuleRoot (Join-Path $script:Layout 'psfdx-logs') -OwnVersion '0.8.5'
        (Get-LoadedFake).Version.ToString() | Should -Be '0.8.5'
    }

    It 'accepts a newer patch of the same minor' {
        New-FakeShared -Folder (Join-Path $script:Layout $script:Fake) -Version '0.8.9'
        Import-PsfdxSharedModule -ModuleName $script:Fake -ModuleRoot (Join-Path $script:Layout 'psfdx-logs') -OwnVersion '0.8.5'
        (Get-LoadedFake).Version.ToString() | Should -Be '0.8.9'
    }

    It 'orders version folders as versions, not as text (0.8.10 beats 0.8.9)' {
        $modules = Join-Path $script:Layout 'Modules'
        foreach ($v in '0.8.2', '0.8.9', '0.8.10', '0.7.99', '0.9.0') { New-FakeShared -Folder (Join-Path (Join-Path $modules $script:Fake) $v) -Version $v }
        Import-PsfdxSharedModule -ModuleName $script:Fake -ModuleRoot (Join-Path (Join-Path $modules 'psfdx-logs') '0.8.2') -OwnVersion '0.8.2'
        (Get-LoadedFake).Version.ToString() | Should -Be '0.8.10'
    }

    It 'ignores version folders of another minor, newer or older' {
        $modules = Join-Path $script:Layout 'Modules'
        foreach ($v in '0.7.99', '0.9.0', '1.0.0') { New-FakeShared -Folder (Join-Path (Join-Path $modules $script:Fake) $v) -Version $v }
        { Import-PsfdxSharedModule -ModuleName $script:Fake -ModuleRoot (Join-Path (Join-Path $modules 'psfdx-logs') '0.8.2') -OwnVersion '0.8.2' } |
            Should -Throw -ExpectedMessage '*needs*0.8.x*Found only*'
        Get-LoadedFake | Should -BeNullOrEmpty
    }

    It 'prefers the sibling folder over a higher version on PSModulePath (a checkout is not shadowed)' {
        New-FakeShared -Folder (Join-Path $script:Layout $script:Fake) -Version '0.8.5'
        $gallery = Join-Path $TestDrive ('gallery-' + [guid]::NewGuid().ToString('N'))
        New-FakeShared -Folder (Join-Path (Join-Path $gallery $script:Fake) '0.8.20') -Version '0.8.20'
        $env:PSModulePath = $gallery
        Import-PsfdxSharedModule -ModuleName $script:Fake -ModuleRoot (Join-Path $script:Layout 'psfdx-logs') -OwnVersion '0.8.5'
        (Get-LoadedFake).Version.ToString() | Should -Be '0.8.5'
    }

    It 'falls back to PSModulePath and picks the highest compatible version' {
        $gallery = Join-Path $TestDrive ('gallery-' + [guid]::NewGuid().ToString('N'))
        foreach ($v in '0.8.9', '0.8.10', '0.9.1') { New-FakeShared -Folder (Join-Path (Join-Path $gallery $script:Fake) $v) -Version $v }
        $env:PSModulePath = $gallery
        Import-PsfdxSharedModule -ModuleName $script:Fake -ModuleRoot (Join-Path $script:Layout 'psfdx-logs') -OwnVersion '0.8.5'
        (Get-LoadedFake).Version.ToString() | Should -Be '0.8.10'
    }

    It 'does not look in unrelated folders when the module is not in a version folder' {
        # <layout>/psfdx-shared exists two levels above the module, which only a version-folder layout may use.
        New-FakeShared -Folder (Join-Path (Join-Path $script:Layout $script:Fake) '0.8.5') -Version '0.8.5'
        $moduleRoot = Join-Path (Join-Path $script:Layout 'checkout') 'psfdx-logs'
        { Import-PsfdxSharedModule -ModuleName $script:Fake -ModuleRoot $moduleRoot -OwnVersion '0.8.5' } | Should -Throw -ExpectedMessage '*It was not found*'
    }

    It 'keeps a loaded copy that is compatible, without reloading it' {
        New-FakeShared -Folder (Join-Path $script:Layout 'loaded') -Version '0.8.7'
        Import-Module (Join-Path (Join-Path $script:Layout 'loaded') "$script:Fake.psd1") -Force
        New-FakeShared -Folder (Join-Path $script:Layout $script:Fake) -Version '0.8.5'
        Import-PsfdxSharedModule -ModuleName $script:Fake -ModuleRoot (Join-Path $script:Layout 'psfdx-logs') -OwnVersion '0.8.5'
        $loaded = Get-LoadedFake
        $loaded.Count | Should -Be 1
        $loaded[0].Version.ToString() | Should -Be '0.8.7'
    }

    It 'replaces a stale loaded copy instead of silently using it' {
        New-FakeShared -Folder (Join-Path $script:Layout 'stale') -Version '0.7.0'
        Import-Module (Join-Path (Join-Path $script:Layout 'stale') "$script:Fake.psd1") -Force
        New-FakeShared -Folder (Join-Path $script:Layout $script:Fake) -Version '0.8.5'
        Import-PsfdxSharedModule -ModuleName $script:Fake -ModuleRoot (Join-Path $script:Layout 'psfdx-logs') -OwnVersion '0.8.5'
        $loaded = Get-LoadedFake
        $loaded.Count | Should -Be 1
        $loaded[0].Version.ToString() | Should -Be '0.8.5'
        $loaded[0].ExportedFunctions.Keys | Should -Contain 'Get-FakeSharedVersion'
    }

    It 'throws, naming the stale copy and the fix, when the loaded copy is stale and nothing better exists' {
        New-FakeShared -Folder (Join-Path $script:Layout 'stale') -Version '0.7.0'
        Import-Module (Join-Path (Join-Path $script:Layout 'stale') "$script:Fake.psd1") -Force
        { Import-PsfdxSharedModule -ModuleName $script:Fake -ModuleRoot (Join-Path $script:Layout 'psfdx-logs') -OwnVersion '0.8.5' } |
            Should -Throw -ExpectedMessage "*0.7.0 (loaded)*Remove-Module $script:Fake -Force*"
        (Get-LoadedFake)[0].Version.ToString() | Should -Be '0.7.0'
    }

    It 'throws a clear, actionable error when the dependency is missing' {
        { Import-PsfdxSharedModule -ModuleName $script:Fake -ModuleRoot (Join-Path $script:Layout 'psfdx-logs') -OwnVersion '0.8.5' } |
            Should -Throw -ExpectedMessage "*Cannot load $script:Fake for module version 0.8.5*needs $script:Fake 0.8.x, version 0.8.5 or newer*It was not found*Install-Module psfdx*"
    }

    It 'rejects an older patch of the same minor' {
        New-FakeShared -Folder (Join-Path $script:Layout $script:Fake) -Version '0.8.4'
        { Import-PsfdxSharedModule -ModuleName $script:Fake -ModuleRoot (Join-Path $script:Layout 'psfdx-logs') -OwnVersion '0.8.5' } |
            Should -Throw -ExpectedMessage '*Found only: 0.8.4*'
    }

    It 'reads its own version from the importing module when -OwnVersion is not given' {
        # Loaded through a real module so $MyInvocation.MyCommand.Module is the importing module.
        New-FakeShared -Folder (Join-Path $script:Layout $script:Fake) -Version '0.8.5'
        $host1 = Join-Path $script:Layout 'host'
        New-Item -ItemType Directory -Path $host1 -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $host1 'host.psm1'), $functionText + "`nImport-PsfdxSharedModule -ModuleName '$script:Fake' -ModuleRoot '$(Join-Path $script:Layout 'psfdx-logs')'`n")
        Set-Content -LiteralPath (Join-Path $host1 'host.psd1') -Value "@{ RootModule = 'host.psm1'; ModuleVersion = '0.8.20'; GUID = '1f3a8c52-6d0e-4f8e-b2a4-5c9d7e1a3b60'; FunctionsToExport = @() }"
        { Import-Module (Join-Path $host1 'host.psd1') -Force -ErrorAction Stop } | Should -Throw -ExpectedMessage '*version 0.8.20*needs*0.8.x*Found only: 0.8.5*'
        Remove-Module host -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Identifier checks reject a trailing line break (issue 112)' {
    It 'does not let a value ending in a line feed pass as an API name' {
        foreach ($value in "Account$([char]10)", "Account$([char]13)$([char]10)", "My_Field__c$([char]10)", "Account.Owner$([char]10)") {
            { ConvertTo-SalesforceSoqlIdentifier -Value $value } | Should -Throw -ExpectedMessage '*not a valid Salesforce*'
        }
    }
}
