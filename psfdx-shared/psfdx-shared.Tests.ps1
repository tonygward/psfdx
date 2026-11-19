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
