<#
Pester unit tests for psfdx module

Run with:

pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path . -CI"
#>

$here = $PSScriptRoot
$moduleManifest = Join-Path $here 'psfdx.psd1'

# Ensure no duplicate 'psfdx' modules are loaded before importing this test instance
Get-Module -Name 'psfdx' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

$module = Import-Module $moduleManifest -Force -PassThru

Describe 'psfdx module' {
    Context 'Get-SalesforceDateTime' {
        It 'formats in sortable UTC with Z suffix' {
            $dt = Get-Date '2020-01-02T03:04:05Z'
            $out = Get-SalesforceDateTime -Datetime $dt
            $out | Should -Be '2020-01-02T03:04:05Z'
        }
        It 'does not shift a value that is already UTC' {
            $utc = [datetime]::SpecifyKind([datetime]'2026-10-21T07:47:12', [System.DateTimeKind]::Utc)
            Get-SalesforceDateTime -Datetime $utc | Should -Be '2026-10-21T07:47:12Z'
        }
        It 'converts local time to UTC before writing the Z' {
            $local = [datetime]::SpecifyKind([datetime]'2026-10-21T08:47:12', [System.DateTimeKind]::Local)
            $expected = $local.ToUniversalTime().ToString('s', [System.Globalization.CultureInfo]::InvariantCulture) + 'Z'
            Get-SalesforceDateTime -Datetime $local | Should -Be $expected
        }
        It 'defaults to the current instant in UTC' {
            $before = [datetime]::UtcNow.AddSeconds(-2)
            $out = Get-SalesforceDateTime
            $after = [datetime]::UtcNow.AddSeconds(2)
            $parsed = [datetime]::ParseExact($out, "yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            $parsed | Should -BeGreaterOrEqual $before
            $parsed | Should -BeLessOrEqual $after
        }
    }

    InModuleScope $module {
        Context 'Alias commands' {
            It 'sets alias using equals syntax' {
                Mock Invoke-Salesforce {} -ModuleName $module.Name
                Add-SalesforceAlias -Alias 'my' -TargetOrg 'user@example.com'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter { ($Arguments -join '|') -eq 'alias|set|my=user@example.com' }
            }

            It 'unsets alias without stray leading space' {
                Mock Invoke-Salesforce {} -ModuleName $module.Name
                Remove-SalesforceAlias -Alias 'my'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter { ($Arguments -join '|') -eq 'alias|unset|my' }
            }
        }

        Context 'Connect-Salesforce' {
            It 'includes --set-default-dev-hub when requested' {
                Mock Invoke-Salesforce { '{"status":0,"result":{}}' } -ModuleName $module.Name
                Connect-Salesforce -SetDefaultDevHub
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter { ($Arguments -join '|') -like '*|--set-default-dev-hub*' }
            }
        }

        Context 'Connect-SalesforceAuthUrl' {
            It 'throws when the SFDX URL file does not exist' {
                Mock Test-Path { $false }
                { Connect-SalesforceAuthUrl -SfdxUrlFile 'missing.txt' } | Should -Throw -ExpectedMessage 'File does not exist: missing.txt'
            }

            It 'stores authentication using the provided URL file and options' {
                Mock Test-Path { $true }
                Mock Invoke-Salesforce { '{"status":0,"result":{}}' } -ModuleName $module.Name
                Mock Show-SalesforceResult { [pscustomobject]@{ alias = 'my'; username = 'user'; accessToken = 'tok'; refreshToken = 'ref' } } -ModuleName $module.Name
                $result = Connect-SalesforceAuthUrl -SfdxUrlFile './auth.txt' -Alias 'my' -SetDefault -SetDefaultDevHub
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter {
                    ($Arguments -join '|') -eq 'org|login|sfdx-url|--sfdx-url-file|./auth.txt|--alias|my|--set-default|--set-default-dev-hub|--json'
                }
                $result.PSObject.Properties.Match('accessToken').Count | Should -Be 0
                $result.PSObject.Properties.Match('refreshToken').Count | Should -Be 0
                $result.alias | Should -Be 'my'
            }

            It 'returns tokens when IncludeToken is specified' {
                Mock Test-Path { $true }
                Mock Invoke-Salesforce { '{"status":0,"result":{}}' } -ModuleName $module.Name
                Mock Show-SalesforceResult { [pscustomobject]@{ alias = 'my'; accessToken = 'tok'; refreshToken = 'ref' } } -ModuleName $module.Name
                $result = Connect-SalesforceAuthUrl -SfdxUrlFile './auth.txt' -IncludeToken
                $result.PSObject.Properties.Match('accessToken').Count | Should -Be 1
                $result.PSObject.Properties.Match('refreshToken').Count | Should -Be 1
            }
        }

        Context 'Auth response shapes' {
            BeforeAll {
                Mock Test-Path { $true }
            }

            It 'handles a CLI response with no token or auth URL fields (new shape)' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"username":"u@example.com","orgId":"00D000000000001","instanceUrl":"https://x.my.salesforce.com"}}' } -ModuleName $module.Name
                $result = Connect-SalesforceAuthUrl -SfdxUrlFile './auth.txt'
                $result.username | Should -Be 'u@example.com'
                $result.PSObject.Properties.Match('accessToken').Count | Should -Be 0
            }

            It 'strips tokens and auth URLs from the real result handling by default (old shape)' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"username":"u@example.com","accessToken":"00Dtok","refreshToken":"5Aref","sfdxAuthUrl":"force://PlatformCLI::x@y.com"}}' } -ModuleName $module.Name
                $result = Connect-SalesforceAuthUrl -SfdxUrlFile './auth.txt'
                $result.username | Should -Be 'u@example.com'
                $result.PSObject.Properties.Match('accessToken').Count | Should -Be 0
                $result.PSObject.Properties.Match('refreshToken').Count | Should -Be 0
                $result.PSObject.Properties.Match('sfdxAuthUrl').Count | Should -Be 0
            }

            It 'IncludeToken passes through only what the CLI returned' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"username":"u@example.com"}}' } -ModuleName $module.Name
                $result = Connect-SalesforceAuthUrl -SfdxUrlFile './auth.txt' -IncludeToken
                $result.PSObject.Properties.Match('accessToken').Count | Should -Be 0
            }

            It 'does not leak secrets in the exception text on failure' {
                Mock Invoke-Salesforce { '{"status":1,"message":"Invalid auth URL","result":{"accessToken":"00Dleak"}}' } -ModuleName $module.Name
                $caught = $null
                try { Connect-SalesforceAuthUrl -SfdxUrlFile './auth.txt' } catch { $caught = $_.Exception.Message }
                $caught | Should -Be 'Invalid auth URL'
                $caught | Should -Not -Match '00Dleak'
            }

            It 'strips tokens from Connect-SalesforceJwt output' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"username":"u","accessToken":"00Dtok"}}' } -ModuleName $module.Name
                $result = Connect-SalesforceJwt -ConsumerKey 'ck' -TargetOrg 'u' -JwtKeyfile 'key.pem'
                $result.username | Should -Be 'u'
                $result.PSObject.Properties.Match('accessToken').Count | Should -Be 0
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter {
                    ($Arguments -join '|') -eq 'org|login|jwt|--client-id|ck|--username|u|--jwt-key-file|key.pem|--instance-url|https://login.salesforce.com|--json'
                }
            }

            It 'Get-SalesforceConnections returns only safe fields from nonScratchOrgs' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"nonScratchOrgs":[{"orgId":"00D1","instanceUrl":"https://a","username":"a@x.com","alias":"a","accessToken":"00Dtok","connectedStatus":"Connected"}],"scratchOrgs":[]}}' } -ModuleName $module.Name
                $rows = @(Get-SalesforceConnections)
                $rows.Count | Should -Be 1
                $rows[0].username | Should -Be 'a@x.com'
                $rows[0].PSObject.Properties.Match('accessToken').Count | Should -Be 0
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter { ($Arguments -join '|') -eq 'org|list|--json' }
            }

            It 'Get-SalesforceConnections falls back to grouped orgs when nonScratchOrgs is absent' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"devHubs":[{"orgId":"00D1","username":"hub@x.com"}],"sandboxes":[{"orgId":"00D2","username":"sb@x.com"}],"other":[],"scratchOrgs":[{"orgId":"00D3","username":"s@x.com"}]}}' } -ModuleName $module.Name
                $rows = @(Get-SalesforceConnections)
                $rows.Count | Should -Be 2
                $rows[1].username | Should -Be 'sb@x.com'
            }

            It 'Get-SalesforceConnections returns nothing when no org groups are present' {
                Mock Invoke-Salesforce { '{"status":0,"result":{}}' } -ModuleName $module.Name
                @(Get-SalesforceConnections).Count | Should -Be 0
            }

            It 'Get-SalesforceConnections throws the CLI message on failure' {
                Mock Invoke-Salesforce { '{"status":1,"message":"boom"}' } -ModuleName $module.Name
                { Get-SalesforceConnections } | Should -Throw -ExpectedMessage 'boom'
            }
        }

        Context 'Install-SalesforceCli' {
            It 'uses npm on macOS' {
                Mock Invoke-Salesforce {} -ModuleName $module.Name
                Mock Test-SalesforceIsMacOS { $true } -ModuleName $module.Name
                Install-SalesforceCli
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter { ($FilePath -eq 'npm') -and (($Arguments -join '|') -eq 'install|--global|@salesforce/cli') }
            }

            It 'updates with npm on macOS' {
                Mock Invoke-Salesforce {} -ModuleName $module.Name
                Mock Test-SalesforceIsMacOS { $true } -ModuleName $module.Name
                Update-SalesforceCli
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter { ($FilePath -eq 'npm') -and (($Arguments -join '|') -eq 'update|--global|@salesforce/cli') }
            }

            It 'uses npm elsewhere' {
                Mock Invoke-Salesforce {} -ModuleName $module.Name
                Mock Test-SalesforceIsMacOS { $false } -ModuleName $module.Name
                Install-SalesforceCli
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter { ($FilePath -eq 'npm') -and (($Arguments -join '|') -eq 'install|--global|@salesforce/cli') }
            }
        }

        Context 'Connect-SalesforceJwt' {
            BeforeAll {
                Mock Test-Path { $true }
            }

            It 'uses login URL for production' {
                Mock Invoke-Salesforce { '{"status":0,"result":{}}' }
                Connect-SalesforceJwt -ConsumerKey 'ck' -TargetOrg 'u' -JwtKeyfile 'key.pem'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -like '*|--instance-url|https://login.salesforce.com*' }
            }

            It 'uses test URL for sandbox' {
                Mock Invoke-Salesforce { '{"status":0,"result":{}}' }
                Connect-SalesforceJwt -ConsumerKey 'ck' -TargetOrg 'u' -JwtKeyfile 'key.pem' -Sandbox
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -like '*|--instance-url|https://test.salesforce.com*' }
            }
        }

        Context 'Select-SalesforceRecords' {
            It 'returns records from successful JSON result' {
                $json = @'
{"status":0,"result":{"records":[{"Id":"001xx0000000001"}]}}
'@
                Mock Invoke-Salesforce { $json } -ModuleName $module.Name
                $rows = Select-SalesforceRecords -Query 'SELECT Id FROM Account LIMIT 1' -TargetOrg 'me'
                @($rows).Count | Should -Be 1
                $rows[0].Id | Should -Be '001xx0000000001'
            }
        }

        Context 'Get-SalesforceUsers and Get-SalesforceRecordType escaping' {
            It 'escapes the username and the object type' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"records":[]}}' } -ModuleName $module.Name
                Get-SalesforceUsers -Username "o'brien@example.com" -Limit 1 | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter {
                    ($Arguments -join '|') -like "*WHERE Username = 'o\'brien@example.com' ORDER BY*"
                }
                Get-SalesforceRecordType -ObjectType "Acc'ount" | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter {
                    ($Arguments -join '|') -like "*FROM RecordType WHERE SobjectType = 'Acc\'ount'*"
                }
            }
        }
        Context 'Get-SalesforceUsers' {
            It 'builds SOQL with filters and returns users' {
                $json = @'
{"status":0,"result":{"records":[{"Id":"005xx0000000001","Username":"user@example.com","IsActive":true}]}}
'@
                Mock Invoke-Salesforce { $json } -ModuleName $module.Name
                $rows = Get-SalesforceUsers -Username 'user@example.com' -ActiveOnly -Limit 5 -TargetOrg 'me'
                @($rows).Count | Should -Be 1
                $rows[0].Id | Should -Be '005xx0000000001'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ModuleName $module.Name -ParameterFilter {
                    (($Arguments -join '|') -like 'data|query|--query|*FROM User*') -and
                    (($Arguments -join '|') -like "*Username = 'user@example.com'*") -and
                    (($Arguments -join '|') -like '*IsActive = true*') -and
                    (($Arguments -join '|') -like '* ORDER BY LastLoginDate DESC*') -and
                    (($Arguments -join '|') -like '* LIMIT 5*') -and
                    (($Arguments -join '|') -like '*|--target-org|me*') -and
                    (($Arguments -join '|') -like '*|--result-format|json*')
                }
            }
        }

        Context 'Object CRUD helpers' {
            It 'returns parsed result for New-SalesforceRecord' {
                $json = @'
{"status":0,"result":{"id":"001xx0000000001"}}
'@
                Mock Invoke-Salesforce { $json } -ModuleName $module.Name
                $res = New-SalesforceRecord -Type Account -FieldUpdates 'Name=Acme' -TargetOrg me
                $res.id | Should -Be '001xx0000000001'
            }

            It 'returns parsed result for Set-SalesforceRecord' {
                $json = @'
{"status":0,"result":{"success":true}}
'@
                Mock Invoke-Salesforce { $json } -ModuleName $module.Name
                $res = Set-SalesforceRecord -Id '001xx0000000001' -Type Account -FieldUpdates 'Name=Updated' -TargetOrg me
                $res.success | Should -BeTrue
            }
        }

        Context 'Invoke-SalesforceApi' {
            It 'uses Bearer token auth header' {
                Mock Invoke-RestMethod { @{ ok = $true } } -ParameterFilter { $Headers.Authorization -like 'Bearer *' }
                $out = Invoke-SalesforceApi -Url 'https://example.com' -AccessToken 'abc'
                $out.ok | Should -BeTrue
            }
        }

        Context 'Select-SalesforceRecords non-JSON result formats' {
            It 'returns csv output untouched instead of parsing it as JSON' {
                Mock Invoke-Salesforce { "Id,Name`n001,Acme" } -ModuleName $module.Name
                $out = Select-SalesforceRecords -Query 'SELECT Id FROM Account' -ResultFormat csv
                $out | Should -Match 'Acme'
            }

            It 'returns human output untouched instead of parsing it as JSON' {
                Mock Invoke-Salesforce { "ID   NAME`n001  Acme" } -ModuleName $module.Name
                $out = Select-SalesforceRecords -Query 'SELECT Id FROM Account' -ResultFormat human
                $out | Should -Match 'Acme'
            }

            It 'throws on a failed json result without first emitting the raw payload' {
                Mock Invoke-Salesforce { '{"status":1,"message":"MALFORMED_QUERY"}' } -ModuleName $module.Name
                $emitted = @()
                try { $emitted = @(Select-SalesforceRecords -Query 'bad' -ErrorAction Stop) } catch { }
                $emitted.Count | Should -Be 0
            }
        }

        Context 'Get-SalesforceLatestApiVersion' {
            It 'compares versions numerically, not as strings' {
                Mock Get-SalesforceApiVersions {
                    @(
                        [pscustomobject]@{ version = '99.0' },
                        [pscustomobject]@{ version = '100.0' },
                        [pscustomobject]@{ version = '64.0' }
                    )
                } -ModuleName $module.Name
                Get-SalesforceLatestApiVersion | Should -Be 'v100.0'
            }

            It 'returns null when no versions are reported' {
                Mock Get-SalesforceApiVersions { @() } -ModuleName $module.Name
                Get-SalesforceLatestApiVersion | Should -BeNullOrEmpty
            }
        }

        Context 'Limit helpers with unusable data' {
            It 'returns null when the DataStorageMB row is absent' {
                Mock Get-SalesforceLimits { @([pscustomobject]@{ Name = 'Other'; max = 10; remaining = 5 }) } -ModuleName $module.Name
                Get-SalesforceDataStorage | Should -BeNullOrEmpty
            }

            It 'does not divide by zero when max is 0' {
                Mock Get-SalesforceLimits { @([pscustomobject]@{ Name = 'DailyApiRequests'; max = 0; remaining = 0 }) } -ModuleName $module.Name
                { Get-SalesforceApiUsage -ErrorAction Stop } | Should -Not -Throw
            }
        }
    }
}

Describe 'Get-SalesforceAlias' {
    It 'declares a Param block so common parameters are honoured' {
        # Without Param(), [CmdletBinding()] is inert and -Verbose is silently swallowed
        (Get-Command Get-SalesforceAlias).Parameters.Keys | Should -Contain 'Verbose'
    }
}

Describe 'Invoke-Salesforce' {
    # Resolved inside the module scope: psfdx-shared is imported there, not into the session
    InModuleScope 'psfdx' {
        It 'does not declare SupportsShouldProcess' {
            # Suppressing the call would return $null into Show-SalesforceResult -Result,
            # which is Mandatory, breaking every cmdlet under -WhatIf.
            $command = Get-Command Invoke-Salesforce -ErrorAction Stop
            $binding = @($command.ScriptBlock.Attributes | Where-Object { $_ -is [CmdletBinding] })
            $binding.Count | Should -Be 1 -Because 'the CmdletBinding attribute must be present to assert against'
            $binding[0].SupportsShouldProcess | Should -BeFalse
        }

        It 'still runs every cmdlet when $WhatIfPreference is set' {
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
            $WhatIfPreference = $true
            try {
                { Connect-Salesforce -Alias 'foo' -ErrorAction Stop } | Should -Not -Throw
            } finally {
                $WhatIfPreference = $false
            }
        }
    }
}

Describe 'Disconnect-Salesforce safety' {
    InModuleScope 'psfdx' {
        BeforeEach { Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' } }

        It 'runs nothing under -WhatIf' {
            Disconnect-Salesforce -All -WhatIf
            Assert-MockCalled Invoke-Salesforce -Times 0
        }

        It 'logs out one org with -Confirm:$false and keeps --no-prompt' {
            Disconnect-Salesforce -TargetOrg 'me@example.com' -NoPrompt -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'org|logout|--target-org|me@example.com|--no-prompt|--json'
            }
        }

        It 'logs out all orgs with -Confirm:$false' {
            Disconnect-Salesforce -All -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                ($Arguments -join '|') -eq 'org|logout|--all|--json'
            }
        }
    }
}

# SOQL builder and `sf data query --json` regression coverage (#172).
# Fixtures are sanitised copies of real `sf data query --json` output shapes: no tokens, no real org data.
Describe 'SOQL query regression' {
    InModuleScope 'psfdx' {
        BeforeAll {
            $script:Success = '{"status":0,"result":{"records":[{"attributes":{"type":"User","url":"/services/data/v62.0/sobjects/User/005000000000001AAA"},"Id":"005000000000001AAA","Username":"a@example.com"}],"totalSize":1,"done":true},"warnings":[]}'
            $script:Empty = '{"status":0,"result":{"records":[],"totalSize":0,"done":true},"warnings":[]}'
            $script:Malformed = '{"name":"INVALID_FIELD","message":"\nSELECT Id, Nope FROM User\n            ^\nERROR at Row:1:Column:12\nNo such column ''Nope'' on entity ''User''.","exitCode":1,"status":1,"warnings":[]}'
            $script:NoAuth = '{"name":"NoAuthFoundError","message":"No authorization information found for nobody@example.com.","exitCode":1,"status":1,"warnings":[]}'
            $script:Head = 'SELECT Id, Name, Username, Email, IsActive, LastLoginDate FROM User'
        }

        Context 'Get-SalesforceUsers escaping' {
            BeforeEach { Mock Invoke-Salesforce { $script:Empty } }

            It 'sends <Name> as <Literal>' -ForEach @(
                @{ Name = 'plain';        Value = 'a@example.com';          Literal = "'a@example.com'" }
                @{ Name = 'apostrophe';   Value = "o'brien@example.com";    Literal = "'o\'brien@example.com'" }
                @{ Name = 'backslash';    Value = 'a\b@example.com';        Literal = "'a\\b@example.com'" }
                @{ Name = 'trailing \';   Value = 'end\';                   Literal = "'end\\'" }
                @{ Name = 'injection';    Value = "x' OR Name != '";        Literal = "'x\' OR Name != \''" }
                @{ Name = 'unicode';      Value = 'Zoë 日本語@example.com';   Literal = "'Zoë 日本語@example.com'" }
                @{ Name = 'percent';      Value = '50%_off';                Literal = "'50%_off'" }
                @{ Name = 'spaces';       Value = 'a b  c';                 Literal = "'a b  c'" }
                @{ Name = 'shell chars';  Value = 'a&b|c;$(x)';             Literal = "'a&b|c;`$(x)'" }
            ) {
                Get-SalesforceUsers -Username $Value | Out-Null
                $expected = "data|query|--query|$script:Head WHERE Username = $Literal ORDER BY LastLoginDate DESC LIMIT 200|--result-format|json"
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq $expected }
            }

            It 'refuses <Name> and never calls sf' -ForEach @(
                @{ Name = 'NUL'; Value = "a$([char]0)b" }
                @{ Name = 'SOH'; Value = "a$([char]1)b" }
                @{ Name = 'DEL'; Value = "a$([char]0x7F)b" }
            ) {
                { Get-SalesforceUsers -Username $Value } | Should -Throw -ExpectedMessage '*control character*'
                Assert-MockCalled Invoke-Salesforce -Times 0
            }

            It 'combines ActiveOnly, Username and Limit in a fixed order' {
                Get-SalesforceUsers -ActiveOnly -Username 'a@x.com' -Limit 5 -TargetOrg 'me' | Out-Null
                $expected = "data|query|--query|$script:Head WHERE IsActive = true AND Username = 'a@x.com' ORDER BY LastLoginDate DESC LIMIT 5|--target-org|me|--result-format|json"
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq $expected }
            }
        }

        Context 'Get-SalesforceRecordType escaping' {
            BeforeEach { Mock Invoke-Salesforce { $script:Empty } }

            It 'escapes the object type' {
                Get-SalesforceRecordType -ObjectType "Acc'ount\" | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                    ($Arguments -join '|') -eq "data|query|--query|SELECT Id, SobjectType, Name, DeveloperName, IsActive FROM RecordType WHERE SobjectType = 'Acc\'ount\\'|--result-format|json"
                }
            }

            It 'refuses control characters and never calls sf' {
                { Get-SalesforceRecordType -ObjectType "A$([char]1)B" } | Should -Throw -ExpectedMessage '*control character*'
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
        }

        Context 'Select-SalesforceRecords result handling' {
            It 'returns records without attributes' {
                Mock Invoke-Salesforce { $script:Success }
                $r = @(Select-SalesforceRecords -Query 'SELECT Id FROM User')
                $r.Count | Should -Be 1
                $r[0].Id | Should -Be '005000000000001AAA'
                $r[0].PSObject.Properties.Name | Should -Not -Contain 'attributes'
            }

            It 'returns nothing for zero records' {
                Mock Invoke-Salesforce { $script:Empty }
                @(Select-SalesforceRecords -Query 'SELECT Id FROM User').Count | Should -Be 0
            }

            It 'throws the CLI message for a malformed query' {
                Mock Invoke-Salesforce { $script:Malformed }
                { Select-SalesforceRecords -Query 'SELECT Id, Nope FROM User' } | Should -Throw -ExpectedMessage "*No such column 'Nope'*"
            }

            It 'throws the CLI message for an authentication error' {
                Mock Invoke-Salesforce { $script:NoAuth }
                { Select-SalesforceRecords -Query 'SELECT Id FROM User' -TargetOrg 'nobody@example.com' } | Should -Throw -ExpectedMessage '*No authorization information found for nobody@example.com*'
            }
        }

        Context 'Select-SalesforceRecords argv' {
            BeforeEach { Mock Invoke-Salesforce { $script:Empty } }

            It 'passes caller-authored queries through unchanged, including % and quotes' {
                $q = "SELECT Id FROM Account WHERE Name LIKE 'Acme%' AND Site = 'O\'Brien' AND X = '%PATH%'"
                Select-SalesforceRecords -Query $q | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { $Arguments[3] -ceq $q }
            }

            It 'passes file and output paths containing spaces and percent signs as single arguments' {
                Select-SalesforceRecords -File 'C:\my queries\50%\q.soql' -OutputFile 'C:\out dir\r 100%.csv' -ResultFormat csv | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                    ($Arguments -join '|') -eq 'data|query|--file|C:\my queries\50%\q.soql|--result-format|csv|--output-file|C:\out dir\r 100%.csv'
                }
            }

            It 'adds tooling, all-rows and a trimmed target org' {
                Select-SalesforceRecords -Query 'SELECT Id FROM ApexClass' -UseToolingApi -IncludeDeletedRows -TargetOrg ' me ' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter {
                    ($Arguments -join '|') -eq 'data|query|--query|SELECT Id FROM ApexClass|--target-org|me|--use-tooling-api|--all-rows|--result-format|json'
                }
            }
        }
    }
}
