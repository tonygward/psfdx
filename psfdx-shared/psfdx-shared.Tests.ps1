Get-Module -Name 'psfdx-shared' -All | Remove-Module -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'psfdx-shared.psd1') -Force

InModuleScope 'psfdx-shared' {
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
            Mock Get-Command { [pscustomobject]@{ Source = 'C:\sf\bin\sf.cmd' } }
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
$queries = @(Get-Content -LiteralPath $QueryFile -Raw | ConvertFrom-Json)
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
            $results = @(Get-Content -LiteralPath $outFile -Raw | ConvertFrom-Json)
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
