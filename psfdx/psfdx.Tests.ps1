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

# Core's Get-SalesforceUsers runs its query through Select-SalesforceRecords, which lives in psfdx-data.
Get-Module -Name 'psfdx-data' -All | ForEach-Object { try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { } }
Import-Module (Join-Path $here '../psfdx-data/psfdx-data.psd1') -Force -Global | Out-Null

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

        Context 'Invoke-SalesforceApi' {
            It 'uses Bearer token auth header' {
                Mock Invoke-RestMethod { @{ ok = $true } } -ParameterFilter { $Headers.Authorization -like 'Bearer *' }
                $out = Invoke-SalesforceApi -Url 'https://example.com' -AccessToken 'abc'
                $out.ok | Should -BeTrue
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

Describe 'Get-SalesforceLimits' {
    InModuleScope 'psfdx' {
        It 'runs the current sf org list limits command' {
            Mock Invoke-Salesforce { '{"status":0,"result":[{"name":"DailyApiRequests","max":10,"remaining":5}]}' }
            $r = @(Get-SalesforceLimits -TargetOrg me)
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'org|list|limits|--target-org|me|--json' }
            $r[0].name | Should -Be 'DailyApiRequests'
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

# Get-SalesforceUsers builds a SOQL query and runs it with Select-SalesforceRecords, which lives in psfdx-data (issue 294).
# These tests mock Select-SalesforceRecords and check the query it is given, so they do not depend on which module instances are loaded.
Describe 'Get-SalesforceUsers queries' {
    InModuleScope 'psfdx' {
        BeforeAll {
            $script:Head = 'SELECT Id, Name, Username, Email, IsActive, LastLoginDate FROM User'
            # Mock needs a command to replace. In a package, psfdx-data provides it; here a stub stands in so the test needs no other module.
            if (-not (Get-Command Select-SalesforceRecords -ErrorAction SilentlyContinue)) { Set-Item -Path function:global:Select-SalesforceRecords -Value { param($Query, $TargetOrg, $ResultFormat) } }
        }
        BeforeEach { Mock Select-SalesforceRecords { } }

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
            $expected = "$script:Head WHERE Username = $Literal ORDER BY LastLoginDate DESC LIMIT 200"
            Assert-MockCalled Select-SalesforceRecords -Times 1 -Exactly -ParameterFilter { $Query -eq $expected -and $ResultFormat -eq 'json' }
        }

        It 'refuses <Name> and never runs a query' -ForEach @(
            @{ Name = 'NUL'; Value = "a$([char]0)b" }
            @{ Name = 'SOH'; Value = "a$([char]1)b" }
            @{ Name = 'DEL'; Value = "a$([char]0x7F)b" }
        ) {
            { Get-SalesforceUsers -Username $Value } | Should -Throw -ExpectedMessage '*control character*'
            Assert-MockCalled Select-SalesforceRecords -Times 0 -Exactly
        }

        It 'combines ActiveOnly, Username and Limit in a fixed order and passes the target org' {
            Get-SalesforceUsers -ActiveOnly -Username 'a@x.com' -Limit 5 -TargetOrg 'me' | Out-Null
            $expected = "$script:Head WHERE IsActive = true AND Username = 'a@x.com' ORDER BY LastLoginDate DESC LIMIT 5"
            Assert-MockCalled Select-SalesforceRecords -Times 1 -Exactly -ParameterFilter { $Query -eq $expected -and $TargetOrg -eq 'me' }
        }

        It 'returns what the query returns' {
            Mock Select-SalesforceRecords { [pscustomobject]@{ Id = '005xx0000000001'; Username = 'user@example.com'; IsActive = $true } }
            $rows = @(Get-SalesforceUsers -Username 'user@example.com' -ActiveOnly -Limit 5 -TargetOrg 'me')
            $rows.Count | Should -Be 1
            $rows[0].Id | Should -Be '005xx0000000001'
        }
    }
}

Describe 'User administration commands' {
    InModuleScope 'psfdx' {
        BeforeAll {
            $script:Secret = 'S3cr3t-Pa55word-Value'
            $script:Token = '00Dxx!AQEAQtokenvalue'
        }
        BeforeEach {
            $script:Reply = '{"status":0,"result":[]}'
            Mock Invoke-Salesforce { $script:Reply }
        }

        Context 'Get-SalesforceAuthenticatedUser and Get-SalesforceOrgUser' {
            It 'lists users with the exact command and drops tokens' {
                $script:Reply = '{"status":0,"result":[{"username":"a@x.org","alias":"a","orgId":"00Dxx","accessToken":"' + $script:Token + '"},{"username":"b@x.org","orgId":"00Dxx"}]}'
                $users = @(Get-SalesforceAuthenticatedUser -TargetOrg me)
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|list|users|--target-org|me|--json' }
                $users.Count | Should -Be 2
                $users[0].username | Should -Be 'a@x.org'
                ($users | ConvertTo-Json -Depth 3) | Should -Not -BeLike "*$script:Token*"
                $users[0].PSObject.Properties.Name | Should -Not -Contain 'accessToken'
            }
            It 'returns an empty list when the CLI knows no users' {
                @(Get-SalesforceAuthenticatedUser).Count | Should -Be 0
            }
            It 'shows the user without the token or password by default' {
                $script:Reply = '{"status":0,"result":{"username":"a@x.org","id":"005xx","orgId":"00Dxx","profileName":"Admin","accessToken":"' + $script:Token + '","password":"' + $script:Secret + '"}}'
                $u = Get-SalesforceOrgUser -TargetOrg me
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|display|user|--target-org|me|--json' }
                $u.username | Should -Be 'a@x.org'
                $u.PSObject.Properties.Name | Should -Not -Contain 'accessToken'
                $u.PSObject.Properties.Name | Should -Not -Contain 'password'
                $u.PSObject.Properties.Name | Should -Not -Contain 'Password'
            }
            It 'handles the redacted password and token the current CLI returns, and says whether a password exists' {
                $script:Reply = '{"status":0,"result":{"username":"a@x.org","id":"005xx","accessToken":"[redacted: use the sf org auth show-user-password command]","password":"[redacted]"}}'
                $u = Get-SalesforceOrgUser
                $u.HasPassword | Should -BeTrue
                $u.PSObject.Properties.Name | Should -Not -Contain 'password'
                $u.PSObject.Properties.Name | Should -Not -Contain 'accessToken'
                ($u | ConvertTo-Json) | Should -Not -BeLike '*redacted*'
                $script:Reply = '{"status":0,"result":{"username":"b@x.org","id":"005yy"}}'
                (Get-SalesforceOrgUser).HasPassword | Should -BeFalse
            }
            It 'no longer offers -IncludePassword, which the CLI cannot honour' {
                (Get-Command Get-SalesforceOrgUser).Parameters.Keys | Should -Not -Contain 'IncludePassword'
            }
            It 'throws the CLI message on failure, without echoing a token' {
                $script:Reply = '{"status":1,"name":"NamedOrgNotFoundError","message":"No authorization information found for nobody."}'
                { Get-SalesforceOrgUser -TargetOrg nobody } | Should -Throw -ExpectedMessage '*No authorization information found*'
            }
        }

        Context 'New-SalesforceUser' {
            It 'builds the exact command from a definition file, fields and options' {
                $file = Join-Path $TestDrive 'user def.json'
                Set-Content -LiteralPath $file -Value '{}'
                $script:Reply = '{"status":0,"result":{"orgId":"00Dxx","fields":{"username":"qa1@x.org"}}}'
                $res = New-SalesforceUser -DefinitionFile $file -Field ([ordered]@{ username = 'qa1@x.org'; lastName = "O'Brien Smith" }) -SetAlias qa1 -SetUniqueUsername -TargetOrg me
                $expected = "org|create|user|--definition-file|$file|--set-alias|qa1|--set-unique-username|--target-org|me|username=qa1@x.org|lastName=O'Brien Smith|--json"
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
                $res.orgId | Should -Be '00Dxx'
            }
            It 'makes no CLI call under -WhatIf' {
                New-SalesforceUser -Field @{ username = 'a@x.org' } -WhatIf | Should -BeNullOrEmpty
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'rejects <Case> without calling the CLI' -ForEach @(
                @{ Case = 'a missing definition file'; Run = { New-SalesforceUser -DefinitionFile (Join-Path $TestDrive 'nope.json') }; Message = '*does not exist*' }
                @{ Case = 'a bad field name';          Run = { New-SalesforceUser -Field @{ 'user name' = 'x' } };                         Message = '*not a valid user field name*' }
                @{ Case = 'a field name with =';       Run = { New-SalesforceUser -Field @{ 'a=b' = 'x' } };                                Message = '*not a valid user field name*' }
                @{ Case = 'a control character';       Run = { New-SalesforceUser -Field @{ lastName = "a`nb" } };                          Message = '*control characters*' }
            ) {
                { & $Run } | Should -Throw -ExpectedMessage $Message
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'reports a CLI error such as missing permissions' {
                $script:Reply = '{"status":1,"name":"INSUFFICIENT_ACCESS","message":"insufficient access rights on object id"}'
                { New-SalesforceUser -Field @{ lastName = 'x' } -Confirm:$false } | Should -Throw -ExpectedMessage '*insufficient access*'
            }
        }

        Context 'New-SalesforceUserPassword' {
            It 'builds the exact command and returns the password only as a SecureString' {
                $script:Reply = '{"status":0,"result":{"username":"qa1@x.org","password":"' + $script:Secret + '"}}'
                $res = New-SalesforceUserPassword -OnBehalfOf qa1 -Length 30 -Complexity 4 -TargetOrg me -Confirm:$false
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|generate|password|--on-behalf-of|qa1|--length|30|--complexity|4|--target-org|me|--json' }
                $res.Username | Should -Be 'qa1@x.org'
                $res.Password | Should -BeOfType [System.Security.SecureString]
                ($res | Out-String) | Should -Not -BeLike "*$script:Secret*"
                ($res | ConvertTo-Json -Depth 2) | Should -Not -BeLike "*$script:Secret*"
            }
            It 'does not put the password in verbose output' {
                $script:Reply = '{"status":0,"result":{"username":"qa1@x.org","password":"' + $script:Secret + '"}}'
                $verbose = New-SalesforceUserPassword -OnBehalfOf qa1 -Confirm:$false -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message }
                ($verbose -join ' ') | Should -Not -BeLike "*$script:Secret*"
            }
            It 'does not put the password in an error message' {
                $script:Reply = '{"status":1,"message":"Cannot generate"}'
                $err = $null
                try { New-SalesforceUserPassword -Confirm:$false } catch { $err = $_ }
                $err.Exception.Message | Should -Not -BeLike "*$script:Secret*"
            }
            It 'makes no CLI call under -WhatIf, and asks by default (ConfirmImpact High)' {
                New-SalesforceUserPassword -OnBehalfOf qa1 -WhatIf | Should -BeNullOrEmpty
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
                (Get-Command New-SalesforceUserPassword).ScriptBlock.Attributes.ConfirmImpact | Should -Contain 'High'
            }
            It 'rejects <Case> without calling the CLI' -ForEach @(
                @{ Case = 'a list of users';       Run = { New-SalesforceUserPassword -OnBehalfOf 'a,b' -Confirm:$false } }
                @{ Case = 'a length below 20';     Run = { New-SalesforceUserPassword -Length 19 -Confirm:$false } }
                @{ Case = 'a complexity above 5';  Run = { New-SalesforceUserPassword -Complexity 6 -Confirm:$false } }
            ) {
                { & $Run } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'fails clearly when the CLI returns no password' {
                $script:Reply = '{"status":0,"result":{"username":"qa1@x.org"}}'
                { New-SalesforceUserPassword -Confirm:$false } | Should -Throw -ExpectedMessage '*did not return a password*'
            }
        }

        Context 'permission set assignment' {
            It 'builds the exact permset command for several sets and users' {
                $script:Reply = '{"status":0,"result":{"successes":[{"name":"qa1","value":"Sales_Admin"},{"name":"qa1","value":"Reports_User"}],"failures":[]}}'
                $res = @(Grant-SalesforcePermissionSet -Name Sales_Admin, Reports_User -OnBehalfOf qa1 -TargetOrg me -Confirm:$false)
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|assign|permset|--name|Sales_Admin|--name|Reports_User|--on-behalf-of|qa1|--target-org|me|--json' }
                $res.Count | Should -Be 2
                $res[0].Status | Should -Be 'Assigned'
                $res[0].PermissionSet | Should -Be 'Sales_Admin'
                $res[0].Username | Should -Be 'qa1'
            }
            It 'builds the exact permset licence command' {
                $script:Reply = '{"status":0,"result":{"successes":[{"name":"qa1","value":"CPQ_Admin"}],"failures":[]}}'
                Grant-SalesforcePermissionSetLicense -Name CPQ_Admin -OnBehalfOf qa1, qa2 -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|assign|permsetlicense|--name|CPQ_Admin|--on-behalf-of|qa1|--on-behalf-of|qa2|--json' }
            }
            It 'is idempotent: a set the user already has is AlreadyAssigned, not an error' {
                $script:Reply = '{"status":68,"result":{"successes":[],"failures":[{"name":"qa1","message":"duplicate value found: PermissionSetAssignment duplicates value on record with id: 0Pa000000000001"}]}}'
                $res = @(Grant-SalesforcePermissionSet -Name Sales_Admin -OnBehalfOf qa1 -Confirm:$false)
                $res.Count | Should -Be 1
                $res[0].Status | Should -Be 'AlreadyAssigned'
                $res[0].PermissionSet | Should -Be 'Sales_Admin'
            }
            It 'writes every result, then throws PsfdxPermissionAssignmentFailed for real failures' {
                $script:Reply = '{"status":68,"result":{"successes":[{"name":"qa1","value":"Sales_Admin"}],"failures":[{"name":"qa2","message":"Insufficient access rights on cross-reference id"}]}}'
                $err = $null
                try { Grant-SalesforcePermissionSet -Name Sales_Admin -OnBehalfOf qa1, qa2 -Confirm:$false | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxPermissionAssignmentFailed'
                @($err.TargetObject).Count | Should -Be 1
                $err.TargetObject[0].Username | Should -Be 'qa2'
                $err.Exception.Message | Should -BeLike '*qa2*Insufficient access*'
            }
            It 'throws the CLI message when there is no assignment result at all' {
                $script:Reply = '{"status":1,"name":"NamedOrgNotFoundError","message":"No authorization information found for nobody."}'
                { Grant-SalesforcePermissionSet -Name X -TargetOrg nobody -Confirm:$false } | Should -Throw -ExpectedMessage '*No authorization information found*'
            }
            It 'makes no CLI call under -WhatIf, and asks by default' {
                Grant-SalesforcePermissionSet -Name X -OnBehalfOf qa1 -WhatIf | Should -BeNullOrEmpty
                Grant-SalesforcePermissionSetLicense -Name X -OnBehalfOf qa1 -WhatIf | Should -BeNullOrEmpty
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
                (Get-Command Grant-SalesforcePermissionSet).ScriptBlock.Attributes.ConfirmImpact | Should -Contain 'High'
            }
            It 'rejects <Case> without calling the CLI' -ForEach @(
                @{ Case = 'an empty name list';   Run = { Grant-SalesforcePermissionSet -Name @('', ' ') -Confirm:$false } }
                @{ Case = 'a comma in a name';    Run = { Grant-SalesforcePermissionSet -Name 'A,B' -Confirm:$false } }
                @{ Case = 'a comma in a user';    Run = { Grant-SalesforcePermissionSet -Name 'A' -OnBehalfOf 'u1,u2' -Confirm:$false } }
                @{ Case = 'a missing name';       Run = { Grant-SalesforcePermissionSetLicense -Name @() -Confirm:$false } }
            ) {
                { & $Run } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'module surface' {
            It 'exports the six commands and keeps the helpers private' {
                $exports = (Import-PowerShellDataFile -Path (Join-Path (Get-Module -Name psfdx).ModuleBase 'psfdx.psd1')).FunctionsToExport
                foreach ($name in 'Get-SalesforceAuthenticatedUser', 'Get-SalesforceOrgUser', 'New-SalesforceUser', 'New-SalesforceUserPassword', 'Grant-SalesforcePermissionSet', 'Grant-SalesforcePermissionSetLicense') {
                    $exports | Should -Contain $name
                }
                foreach ($name in 'Remove-SalesforceSecretProperty', 'ConvertFrom-SalesforceAssignmentOutput', 'Test-SalesforceAssignmentNames') { $exports | Should -Not -Contain $name }
            }
            It 'has help examples' {
                foreach ($name in 'Get-SalesforceAuthenticatedUser', 'Get-SalesforceOrgUser', 'New-SalesforceUser', 'New-SalesforceUserPassword', 'Grant-SalesforcePermissionSet', 'Grant-SalesforcePermissionSetLicense') {
                    @((Get-Help $name -Examples).examples.example).Count | Should -BeGreaterThan 0
                }
            }
        }
    }
}

Describe 'Security regressions (issue 112)' {
    InModuleScope 'psfdx' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
            Mock Invoke-RestMethod { [pscustomobject]@{ access_token = 'x' } }
        }

        Context 'credentials and tokens only travel over https' {
            It 'refuses a plain http or malformed -CustomUrl before sending the password' {
                foreach ($url in 'http://login.example.com', 'ftp://x', 'login.example.com', '//login.example.com', 'file:///etc/passwd') {
                    { Connect-SalesforceApi -TargetOrg u@x.com -Password p -Token t -ClientId c -ClientSecret s -CustomUrl $url } | Should -Throw -ExpectedMessage '*absolute https://*'
                }
                Assert-MockCalled Invoke-RestMethod -Times 0 -Exactly
            }
            It 'sends the login to an https -CustomUrl, with no doubled slash' {
                Connect-SalesforceApi -TargetOrg u@x.com -Password p -Token t -ClientId c -ClientSecret s -CustomUrl 'https://example.my.salesforce.com/' | Out-Null
                Assert-MockCalled Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://example.my.salesforce.com/services/oauth2/token' }
            }
            It 'keeps the default and sandbox login hosts' {
                Connect-SalesforceApi -TargetOrg u@x.com -Password p -Token t -ClientId c -ClientSecret s | Out-Null
                Connect-SalesforceApi -TargetOrg u@x.com -Password p -Token t -ClientId c -ClientSecret s -Sandbox | Out-Null
                Assert-MockCalled Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://login.salesforce.com/services/oauth2/token' }
                Assert-MockCalled Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://test.salesforce.com/services/oauth2/token' }
            }
            It 'refuses to send an access token to a non-https or relative URL' {
                foreach ($url in 'http://x.my.salesforce.com/services/data', '/services/data', 'ftp://x/y') {
                    { Invoke-SalesforceApi -Url $url -AccessToken 'tok' } | Should -Throw -ExpectedMessage '*absolute https://*'
                }
                Assert-MockCalled Invoke-RestMethod -Times 0 -Exactly
                Invoke-SalesforceApi -Url 'https://x.my.salesforce.com/services/data' -AccessToken 'tok' | Out-Null
                Assert-MockCalled Invoke-RestMethod -Times 1 -Exactly
            }
            It 'does not put the access token in the error text' {
                $err = $null
                try { Invoke-SalesforceApi -Url 'http://x/y' -AccessToken 'SECRETTOKEN123' } catch { $err = $_.Exception.Message }
                $err | Should -Not -BeLike '*SECRETTOKEN123*'
            }
        }

        Context 'Connect-SalesforceApi secrets as SecureString (issue 233)' {
            BeforeAll {
                $script:ss = { param($v) ConvertTo-SecureString $v -AsPlainText -Force }
            }
            It 'sends the plain text of SecureString values in the request body, with no warning' {
                $pw = & $script:ss 'PW1'; $tok = & $script:ss 'TK2'; $sec = & $script:ss 'CS3'
                Connect-SalesforceApi -TargetOrg u@x.com -Password $pw -Token $tok -ClientId c -ClientSecret $sec -WarningVariable w -WarningAction SilentlyContinue | Out-Null
                Assert-MockCalled Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Body.password -eq 'PW1TK2' -and $Body.client_secret -eq 'CS3' }
                $w | Should -BeNullOrEmpty
            }
            It 'still accepts plain strings but warns once per secret, without echoing the value' {
                Connect-SalesforceApi -TargetOrg u@x.com -Password 'PLAINPW' -Token 't' -ClientId c -ClientSecret 's' -WarningVariable w -WarningAction SilentlyContinue | Out-Null
                Assert-MockCalled Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Body.password -eq 'PLAINPWt' }
                @($w).Count | Should -Be 3
                ($w -join ' ') | Should -Not -BeLike '*PLAINPW*'
            }
            It 'never writes SecureString values to verbose, debug, warning or error output' {
                $pw = & $script:ss 'TOPSECRETPW'; $tok = & $script:ss 'TOPSECRETTK'; $sec = & $script:ss 'TOPSECRETCS'
                $out = Connect-SalesforceApi -TargetOrg u@x.com -Password $pw -Token $tok -ClientId c -ClientSecret $sec -Verbose 4>&1 3>&1 | Out-String
                $out | Should -Not -BeLike '*TOPSECRET*'
                Mock Invoke-RestMethod { throw 'request failed' }
                $msg = $null
                try { Connect-SalesforceApi -TargetOrg u@x.com -Password $pw -Token $tok -ClientId c -ClientSecret $sec } catch { $msg = ($_ | Out-String) }
                $msg | Should -Not -BeNullOrEmpty
                $msg | Should -Not -BeLike '*TOPSECRET*'
            }
            It 'rejects a value that is neither SecureString nor string, before sending' {
                { Connect-SalesforceApi -TargetOrg u@x.com -Password 5 -Token 't' -ClientId c -ClientSecret 's' -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage '*must be a SecureString*'
                Assert-MockCalled Invoke-RestMethod -Times 0 -Exactly
            }
        }

        Context 'installing the CLI is previewable' {
            It 'makes no call under -WhatIf for CLI installs and updates' {
                Install-SalesforceCli -WhatIf | Out-Null
                Update-SalesforceCli -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }
    }
}

Describe 'ID parameters reject a trailing line break (issue 112)' {
    InModuleScope 'psfdx' {
        BeforeEach { Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' } }
        It 'refuses a record ID that ends in a line feed, before any call' {
            $lf = [string][char]10
            { Get-SalesforceRecord -Type Account -Id ('001xx000003DGb1AAG' + $lf) } | Should -Throw
            { Remove-SalesforceRecord -Type Account -Id ('001xx000003DGb1AAG' + $lf) -Confirm:$false } | Should -Throw
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
        }
    }
}

Describe 'Open-Salesforce private mode' {
    InModuleScope 'psfdx' {
        BeforeEach { Mock Invoke-Salesforce { 'https://example.my.salesforce.com' } }
        It 'passes --private as a flag with no value' {
            Open-Salesforce -TargetOrg me -BrowserPrivateMode -UrlOnly | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|open|--target-org|me|--private|--url-only' }
        }
        It 'leaves --private out by default, and BrowserPrivateMode is a switch' {
            Open-Salesforce -TargetOrg me | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|open|--target-org|me' }
            (Get-Command Open-Salesforce).Parameters['BrowserPrivateMode'].SwitchParameter | Should -BeTrue
        }
    }
}

Describe 'psfdx sf org parity (issue 248)' {
    InModuleScope 'psfdx' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
        }

        Context 'new flags on existing cmdlets' {
            It 'Connect-Salesforce passes -ClientApp, -Scopes and -Username' {
                Connect-Salesforce -ClientApp mine -Scopes 'api web refresh_token' -Username me@example.com -OAuthClientId abc | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|login|web|--client-id|abc|--client-app|mine|--scopes|api web refresh_token|--username|me@example.com|--json' }
            }
            It 'Disconnect-Salesforce passes -ClientApp with -TargetOrg only' {
                Disconnect-Salesforce -TargetOrg dev1 -ClientApp mine -NoPrompt -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|logout|--target-org|dev1|--client-app|mine|--no-prompt|--json' }
                { Disconnect-Salesforce -All -ClientApp mine -Confirm:$false } | Should -Throw
            }
            It 'Open-Salesforce passes -Path and an existing -SourceFile' {
                $file = Join-Path $TestDrive 'My Page.flexipage-meta.xml'
                Set-Content -LiteralPath $file -Value '<x/>'
                Mock Invoke-Salesforce { 'https://example.my.salesforce.com' }
                Open-Salesforce -TargetOrg me -Path '/lightning/setup/SetupOneHome/home' -UrlOnly | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|open|--target-org|me|--url-only|--path|/lightning/setup/SetupOneHome/home' }
                Open-Salesforce -TargetOrg me -SourceFile $file -UrlOnly | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "org|open|--target-org|me|--url-only|--source-file|$file" }
            }
            It 'Open-Salesforce stops before running sf when the source file is missing' {
                { Open-Salesforce -SourceFile (Join-Path $TestDrive 'nope.cls') } | Should -Throw -ExpectedMessage '*does not exist*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Get-SalesforceOrgDetails' {
            BeforeEach {
                Mock Invoke-Salesforce { '{"status":0,"result":{"id":"00D000000000001","username":"me@example.com","instanceUrl":"https://x.my.salesforce.com","accessToken":"TOKEN123","sfdxAuthUrl":"force://PlatformCLI::REFRESH@x.my.salesforce.com"}}' }
            }
            It 'builds the command and removes tokens by default' {
                $org = Get-SalesforceOrgDetails -TargetOrg dev1 -ShowVerboseDetails
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|display|--target-org|dev1|--verbose|--json' }
                $org.username | Should -Be 'me@example.com'
                $org.PSObject.Properties.Name | Should -Not -Contain 'accessToken'
                $org.PSObject.Properties.Name | Should -Not -Contain 'sfdxAuthUrl'
            }
            It 'returns the token only with -IncludeToken' {
                (Get-SalesforceOrgDetails -IncludeToken).accessToken | Should -Be 'TOKEN123'
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|display|--json' }
            }
            It 'throws the CLI message when the org is unknown' {
                Mock Invoke-Salesforce { '{"status":1,"message":"No authorization information found for ghost."}' }
                { Get-SalesforceOrgDetails -TargetOrg ghost } | Should -Throw -ExpectedMessage '*No authorization information found*'
            }
        }

        Context 'Get-SalesforceAuthorizations' {
            It 'lists the saved logins without tokens' {
                Mock Invoke-Salesforce { '{"status":0,"result":[{"username":"a@example.com","orgId":"00D000000000001","aliases":["a"],"instanceUrl":"https://a.my.salesforce.com","isExpired":false,"accessToken":"T1"},{"username":"b@example.com","orgId":"00D000000000002","aliases":[],"isExpired":true}]}' }
                $auths = @(Get-SalesforceAuthorizations)
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|list|auth|--json' }
                $auths.Count | Should -Be 2
                $auths[0].username | Should -Be 'a@example.com'
                $auths[0].PSObject.Properties.Name | Should -Not -Contain 'accessToken'
                $auths[1].isExpired | Should -BeTrue
            }
        }

        Context 'Connect-SalesforceAccessToken' {
            BeforeEach {
                $script:bootstrapToken = $null
                Mock Get-PsfdxCliPath {
                    $script:bootstrapToken = [Environment]::GetEnvironmentVariable('SF_ACCESS_TOKEN')
                    'resolved-sf'
                }
                $script:seenToken = $null
                $script:seenArgs = $null
                Mock Invoke-Salesforce {
                    $script:seenToken = [Environment]::GetEnvironmentVariable('SF_ACCESS_TOKEN')
                    $script:seenArgs = $Arguments -join '|'
                    '{"status":0,"result":{"username":"me@example.com","accessToken":"LEAK","instanceUrl":"https://x.my.salesforce.com"}}'
                }
                $script:secure = ConvertTo-SecureString 'TOPSECRETTOKEN' -AsPlainText -Force
            }
            AfterEach { [Environment]::SetEnvironmentVariable('SF_ACCESS_TOKEN', $null) }

            It 'hands the token to sf in the environment, not the arguments, and removes it afterwards' {
                $r = Connect-SalesforceAccessToken -InstanceUrl 'https://x.my.salesforce.com' -AccessToken $script:secure -Alias ci -SetDefault -SetDefaultDevHub -NoPrompt
                $script:seenToken | Should -Be 'TOPSECRETTOKEN'
                $script:seenArgs | Should -Be 'org|login|access-token|--instance-url|https://x.my.salesforce.com|--alias|ci|--set-default|--set-default-dev-hub|--no-prompt|--json'
                $script:seenArgs | Should -Not -BeLike '*TOPSECRET*'
                [Environment]::GetEnvironmentVariable('SF_ACCESS_TOKEN') | Should -BeNullOrEmpty
                $r.username | Should -Be 'me@example.com'
                $r.PSObject.Properties.Name | Should -Not -Contain 'accessToken'
            }
            It 'restores an earlier SF_ACCESS_TOKEN value, also when sf fails' {
                [Environment]::SetEnvironmentVariable('SF_ACCESS_TOKEN', 'EARLIER')
                Mock Invoke-Salesforce { throw 'sf exploded' }
                { Connect-SalesforceAccessToken -InstanceUrl 'https://x.my.salesforce.com' -AccessToken $script:secure } | Should -Throw -ExpectedMessage '*sf exploded*'
                [Environment]::GetEnvironmentVariable('SF_ACCESS_TOKEN') | Should -Be 'EARLIER'
            }
            It 'resolves the dependency before making the temporary access token available' {
                [Environment]::SetEnvironmentVariable('SF_ACCESS_TOKEN', 'EARLIER')
                Connect-SalesforceAccessToken -InstanceUrl 'https://x.my.salesforce.com' -AccessToken $script:secure | Out-Null
                $script:bootstrapToken | Should -Be 'EARLIER'
                $script:seenToken | Should -Be 'TOPSECRETTOKEN'
                Should -Invoke Invoke-Salesforce -Exactly -Times 1 -ParameterFilter {
                    $FilePath -eq 'sf' -and $ResolvedCliPath -eq 'resolved-sf'
                }
            }
            It 'refuses a non-https or relative instance URL before sending the token' {
                foreach ($url in 'http://x.my.salesforce.com', 'x.my.salesforce.com', 'ftp://x') {
                    { Connect-SalesforceAccessToken -InstanceUrl $url -AccessToken $script:secure } | Should -Throw -ExpectedMessage '*absolute https://*'
                }
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'lets only one login in the process use SF_ACCESS_TOKEN at a time, so tokens are never mixed' {
                # A second runspace holds the process-wide lock, as a parallel login would while it runs sf.
                $gate = [string]::Intern('psfdx.Connect-SalesforceAccessToken.SF_ACCESS_TOKEN')
                $held = New-Object System.Threading.ManualResetEventSlim($false)
                $release = New-Object System.Threading.ManualResetEventSlim($false)
                $other = [powershell]::Create()
                [void]$other.AddScript({
                        param($g, $h, $r)
                        [System.Threading.Monitor]::Enter($g)
                        try { $h.Set(); [void]$r.Wait(15000) } finally { [System.Threading.Monitor]::Exit($g) }
                    }).AddArgument($gate).AddArgument($held).AddArgument($release)
                $pending = $other.BeginInvoke()
                try {
                    $held.Wait(10000) | Should -BeTrue
                    $script:PsfdxAccessTokenLockTimeoutMs = 200
                    { Connect-SalesforceAccessToken -InstanceUrl 'https://x.my.salesforce.com' -AccessToken $script:secure } | Should -Throw -ExpectedMessage '*still running*'
                    Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
                    [Environment]::GetEnvironmentVariable('SF_ACCESS_TOKEN') | Should -BeNullOrEmpty
                }
                finally {
                    $script:PsfdxAccessTokenLockTimeoutMs = 60000
                    $release.Set()
                    [void]$other.EndInvoke($pending)
                    $other.Dispose()
                }
                # The lock is free again, so the next login runs.
                Connect-SalesforceAccessToken -InstanceUrl 'https://x.my.salesforce.com' -AccessToken $script:secure | Out-Null
                $script:seenToken | Should -Be 'TOPSECRETTOKEN'
            }
            It 'takes only a SecureString and never writes the token to verbose, warning or error output' {
                (Get-Command Connect-SalesforceAccessToken).Parameters['AccessToken'].ParameterType | Should -Be ([System.Security.SecureString])
                $out = Connect-SalesforceAccessToken -InstanceUrl 'https://x.my.salesforce.com' -AccessToken $script:secure -Verbose 4>&1 3>&1 | Out-String
                $out | Should -Not -BeLike '*TOPSECRET*'
                $out | Should -Not -BeLike '*LEAK*'
            }
        }

        It 'exports the new cmdlets' {
            $exports = (Get-Module psfdx).ExportedFunctions.Keys
            foreach ($n in 'Get-SalesforceOrgDetails', 'Get-SalesforceAuthorizations', 'Connect-SalesforceAccessToken') { $exports | Should -Contain $n }
        }
    }
}

Describe 'psfdx: Experience Cloud, requests, plugins and diagnostics (issue 257)' {
    InModuleScope 'psfdx' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
        }

        Context 'Experience Cloud' {
            It 'lists templates' {
                Get-SalesforceCommunityTemplates -TargetOrg me | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'community|list|template|--target-org|me|--json' }
            }
            It 'creates a site with every option and does not prompt' {
                New-SalesforceCommunity -Name 'Partner Portal' -TemplateName 'Customer Service' -UrlPathPrefix partners -Description 'For partners' -TargetOrg me | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'community|create|--name|Partner Portal|--template-name|Customer Service|--url-path-prefix|partners|--description|For partners|--target-org|me|--json' }
            }
            It 'checks the path prefix and the mandatory parameters' {
                { New-SalesforceCommunity -Name n -TemplateName t -UrlPathPrefix 'a b' } | Should -Throw
                { New-SalesforceCommunity -Name n -TemplateName t -UrlPathPrefix ('abc' + "`n") } | Should -Throw
                foreach ($p in 'Name', 'TemplateName') { (Get-Command New-SalesforceCommunity).Parameters[$p].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue }
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'does nothing under -WhatIf for a create and a publish' {
                New-SalesforceCommunity -Name n -TemplateName t -WhatIf | Out-Null
                Publish-SalesforceCommunity -Name n -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'publishes, and -NoPrompt skips the confirmation without turning WhatIf off' {
                Publish-SalesforceCommunity -Name 'Partner Portal' -NoPrompt -TargetOrg me | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'community|publish|--name|Partner Portal|--target-org|me|--json' }
                Publish-SalesforceCommunity -Name n -NoPrompt -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1
            }
            It 'publish is a High impact cmdlet and the creation is Medium' {
                (Get-Command Publish-SalesforceCommunity).ScriptBlock.Attributes.Where({ $_ -is [System.Management.Automation.CmdletBindingAttribute] }).ConfirmImpact | Should -Be 'High'
                (Get-Command New-SalesforceCommunity).ScriptBlock.Attributes.Where({ $_ -is [System.Management.Automation.CmdletBindingAttribute] }).ConfirmImpact | Should -Be 'Medium'
            }
        }

        Context 'Invoke-SalesforceGraphQL' {
            BeforeEach {
                $script:gql = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $script:gql | Out-Null
                Set-Content -LiteralPath (Join-Path $script:gql 'q.graphql') -Value 'query { uiapi { query { Account { edges { node { Id } } } } } }'
                Set-Content -LiteralPath (Join-Path $script:gql 'm.graphql') -Value 'mutation { uiapi { AccountCreate(input: { Account: { Name: "x" } }) { Record { Id } } } }'
                Mock Invoke-Salesforce { '{"data":{"uiapi":{}}}' }
            }
            It 'sends a query as text and returns the response text' {
                $out = Invoke-SalesforceGraphQL -Query 'query { a }' -TargetOrg me
                $out | Should -Be '{"data":{"uiapi":{}}}'
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'api|request|graphql|--body|query { a }|--target-org|me' }
            }
            It 'returns an object with -AsObject' {
                (Invoke-SalesforceGraphQL -Query 'query { a }' -AsObject).data | Should -Not -BeNullOrEmpty
            }
            It 'passes a file by its full path' {
                $file = Join-Path $script:gql 'q.graphql'
                $out = Join-Path $script:gql 'out.json'
                Invoke-SalesforceGraphQL -QueryFile $file -StreamToFile $out | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "api|request|graphql|--body|$file|--stream-to-file|$out" }
                Invoke-SalesforceGraphQL -QueryFile $file -Include | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "api|request|graphql|--body|$file|--include" }
            }
            It 'runs a query without confirmation but asks before a mutation and honours -WhatIf' {
                Invoke-SalesforceGraphQL -Query 'query { a }' -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1
                Invoke-SalesforceGraphQL -QueryFile (Join-Path $script:gql 'm.graphql') -WhatIf | Out-Null
                Invoke-SalesforceGraphQL -Query 'mutation { a }' -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1
                Invoke-SalesforceGraphQL -Query 'mutation { a }' -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 2
            }
            It 'checks its inputs' {
                { Invoke-SalesforceGraphQL } | Should -Throw -ExpectedMessage '*exactly one of -Query and -QueryFile*'
                { Invoke-SalesforceGraphQL -Query a -QueryFile (Join-Path $script:gql 'q.graphql') } | Should -Throw -ExpectedMessage '*exactly one*'
                { Invoke-SalesforceGraphQL -QueryFile (Join-Path $script:gql 'missing.graphql') } | Should -Throw -ExpectedMessage '*does not exist*'
                { Invoke-SalesforceGraphQL -Query a -Include -StreamToFile (Join-Path $script:gql 'o') } | Should -Throw -ExpectedMessage '*not both*'
                { Invoke-SalesforceGraphQL -Query a -AsObject -Include } | Should -Throw -ExpectedMessage '*-AsObject*'
                { Invoke-SalesforceGraphQL -Query a -StreamToFile (Join-Path $script:gql 'nofolder/o.json') } | Should -Throw -ExpectedMessage '*Output folder*'
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'throws with the response text when sf exits with an error' {
                Mock Invoke-Salesforce { $global:LASTEXITCODE = 1; '{"errors":[{"message":"bad field"}]}' }
                $err = $null
                try { Invoke-SalesforceGraphQL -Query 'query { a }' } catch { $err = $_ }
                $err.Exception.Message | Should -BeLike '*exited with code 1*bad field*'
                $err.FullyQualifiedErrorId | Should -BeLike 'PsfdxRequestFailed*'
                $err.TargetObject | Should -BeLike '*bad field*'
            }
            It 'says to use -QueryFile when the Windows launcher refuses the statement' {
                Mock Invoke-Salesforce { throw "Argument contains a character that cannot be passed safely to 'sf' on Windows (double quote or line break)." }
                { Invoke-SalesforceGraphQL -Query 'query { a(x: "1") }' } | Should -Throw -ExpectedMessage '*use -QueryFile instead*'
            }
        }

        Context 'Invoke-SalesforceRestRequest' {
            BeforeEach {
                $script:rest = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $script:rest | Out-Null
                Set-Content -LiteralPath (Join-Path $script:rest 'body.json') -Value '{"Name":"x"}'
                Mock Invoke-Salesforce { '{"limits":1}' }
            }
            It 'reads an endpoint without a method or confirmation' {
                (Invoke-SalesforceRestRequest -Url /services/data/v62.0/limits -AsObject -TargetOrg me).limits | Should -Be 1
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'api|request|rest|/services/data/v62.0/limits|--target-org|me' }
            }
            It 'passes the method, the body and each header as its own argument' {
                Invoke-SalesforceRestRequest -Url /services/data/v62.0/sobjects/Account -Method POST -Body 'a=b' -Header ([ordered]@{ 'Content-Type' = 'text/plain'; 'X-Trace' = 'a:b' }) -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'api|request|rest|/services/data/v62.0/sobjects/Account|--method|POST|--body|a=b|--header|Content-Type:text/plain|--header|X-Trace:a:b' }
            }
            It 'sends a body file with an at sign and a full path, and a request file as --file' {
                $b = Join-Path $script:rest 'body.json'
                Invoke-SalesforceRestRequest -Url /x -Method PATCH -BodyFile $b -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "api|request|rest|/x|--method|PATCH|--body|@$b" }
                Invoke-SalesforceRestRequest -File $b -Include | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "api|request|rest|--file|$b|--include" }
            }
            It 'asks before a write and does nothing under -WhatIf, but a read runs' {
                foreach ($m in 'POST', 'PUT', 'PATCH', 'DELETE') { Invoke-SalesforceRestRequest -Url /x -Method $m -WhatIf | Out-Null }
                Assert-MockCalled Invoke-Salesforce -Times 0
                foreach ($m in 'GET', 'HEAD', 'OPTIONS') { Invoke-SalesforceRestRequest -Url /x -Method $m -WhatIf | Out-Null }
                Assert-MockCalled Invoke-Salesforce -Times 3
            }
            It 'checks its inputs' {
                { Invoke-SalesforceRestRequest } | Should -Throw -ExpectedMessage '*Give -Url*'
                { Invoke-SalesforceRestRequest -Url /x -Body a -BodyFile (Join-Path $script:rest 'body.json') } | Should -Throw -ExpectedMessage '*only one of*'
                { Invoke-SalesforceRestRequest -Url /x -BodyFile (Join-Path $script:rest 'nope.json') } | Should -Throw -ExpectedMessage '*does not exist*'
                { Invoke-SalesforceRestRequest -Url /x -File (Join-Path $script:rest 'nope.json') } | Should -Throw -ExpectedMessage '*does not exist*'
                { Invoke-SalesforceRestRequest -Url /x -Method FETCH } | Should -Throw
                { Invoke-SalesforceRestRequest -Url '/x --json' } | Should -Throw
                { Invoke-SalesforceRestRequest -Url /x -Header @{ 'Bad Name' = 'v' } } | Should -Throw -ExpectedMessage '*not a valid header name*'
                { Invoke-SalesforceRestRequest -Url /x -Header @{ 'X-A' = "a`nb" } } | Should -Throw -ExpectedMessage '*line break*'
                { Invoke-SalesforceRestRequest -Url /x -Include -AsObject } | Should -Throw -ExpectedMessage '*-AsObject*'
                { Invoke-SalesforceRestRequest -Url /x -Include -StreamToFile (Join-Path $script:rest 'o') } | Should -Throw -ExpectedMessage '*not both*'
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'throws with the response text on an error and names -BodyFile when the launcher refuses a quote' {
                Mock Invoke-Salesforce { $global:LASTEXITCODE = 1; '[{"errorCode":"NOT_FOUND"}]' }
                { Invoke-SalesforceRestRequest -Url /x } | Should -Throw -ExpectedMessage '*NOT_FOUND*'
                Mock Invoke-Salesforce { throw "Argument contains a character that cannot be passed safely to 'sf' on Windows (double quote or line break)." }
                { Invoke-SalesforceRestRequest -Url /x -Method POST -Body '{"a":1}' -Confirm:$false } | Should -Throw -ExpectedMessage '*use -BodyFile instead*'
            }
        }

        Context 'what asks at the default confirmation level' {
            # A prompt cannot be seen from a mock, so this runs the cmdlets in a child PowerShell with no terminal: a cmdlet that would ask fails there,
            # and one that does not runs. The child replaces Invoke-Salesforce inside the module and counts its calls.
            BeforeAll {
                $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $dir | Out-Null
                Set-Content -LiteralPath (Join-Path $dir 'delete.json') -Value '{"url":"/services/data/v62.0/sobjects/Account/001","method":"DELETE"}'
                Set-Content -LiteralPath (Join-Path $dir 'get.json') -Value '{"url":"/services/data/v62.0/limits","method":"GET"}'
                Set-Content -LiteralPath (Join-Path $dir 'nomethod.json') -Value '{"url":"/services/data/v62.0/limits"}'
                Set-Content -LiteralPath (Join-Path $dir 'broken.json') -Value 'not json'
                $manifest = (Get-Module psfdx).Path -replace '\.psm1$', '.psd1'
                $script = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$manifest' -Force 3>`$null
& (Get-Module psfdx) { function script:Invoke-Salesforce { `$global:psfdxCalls++; '{"status":0,"result":{}}' } }
`$cases = [ordered]@{
  'rest-post'      = { Invoke-SalesforceRestRequest -Url /x -Method POST }
  'rest-post-no'   = { Invoke-SalesforceRestRequest -Url /x -Method POST -Confirm:`$false }
  'rest-get'       = { Invoke-SalesforceRestRequest -Url /x }
  'file-delete'    = { Invoke-SalesforceRestRequest -File '$dir\delete.json' }
  'file-delete-no' = { Invoke-SalesforceRestRequest -File '$dir\delete.json' -Confirm:`$false }
  'file-get'       = { Invoke-SalesforceRestRequest -File '$dir\get.json' }
  'file-nomethod'  = { Invoke-SalesforceRestRequest -File '$dir\nomethod.json' }
  'file-broken'    = { Invoke-SalesforceRestRequest -File '$dir\broken.json' }
  'gql-mutation'   = { Invoke-SalesforceGraphQL -Query 'mutation { a }' }
  'gql-mutation-no'= { Invoke-SalesforceGraphQL -Query 'mutation { a }' -Confirm:`$false }
  'gql-query'      = { Invoke-SalesforceGraphQL -Query 'query { a }' }
  'doctor-issue'   = { Invoke-SalesforceDoctor -CreateIssue }
  'doctor-issue-no'= { Invoke-SalesforceDoctor -CreateIssue -Confirm:`$false }
  'doctor'         = { Invoke-SalesforceDoctor }
  'alias-all'      = { Remove-SalesforceAlias -All }
  'alias-all-no'   = { Remove-SalesforceAlias -All -Confirm:`$false }
  'alias-one'      = { Remove-SalesforceAlias -Alias dev1 }
}
`$out = [ordered]@{}
foreach (`$k in `$cases.Keys) {
  `$global:psfdxCalls = 0
  try { & `$cases[`$k] | Out-Null } catch { }
  `$out[`$k] = `$global:psfdxCalls
}
`$out | ConvertTo-Json -Compress
"@
                $file = Join-Path $dir 'child.ps1'
                Set-Content -LiteralPath $file -Value $script
                $exe = (Get-Process -Id $PID).Path
                $raw = & $exe -NoProfile -NonInteractive -File $file 2>&1 | Where-Object { $_ -is [string] -and $_.StartsWith('{') } | Select-Object -Last 1
                $script:calls = $raw | ConvertFrom-Json
            }
            It 'a REST write asks, a read does not, and -Confirm:$false skips the question' {
                $script:calls.'rest-post' | Should -Be 0
                $script:calls.'rest-post-no' | Should -Be 1
                $script:calls.'rest-get' | Should -Be 1
            }
            It 'reads the method from the request file, and treats a file it cannot read as a write' {
                $script:calls.'file-delete' | Should -Be 0
                $script:calls.'file-delete-no' | Should -Be 1
                $script:calls.'file-get' | Should -Be 1
                $script:calls.'file-nomethod' | Should -Be 1
                $script:calls.'file-broken' | Should -Be 0
            }
            It 'a GraphQL mutation asks and a query does not' {
                $script:calls.'gql-mutation' | Should -Be 0
                $script:calls.'gql-mutation-no' | Should -Be 1
                $script:calls.'gql-query' | Should -Be 1
            }
            It 'sharing diagnostics asks, running them does not' {
                $script:calls.'doctor-issue' | Should -Be 0
                $script:calls.'doctor-issue-no' | Should -Be 1
                $script:calls.'doctor' | Should -Be 1
            }
            It 'removing all aliases asks, one alias does not, and -Confirm:$false is respected' {
                $script:calls.'alias-all' | Should -Be 0
                $script:calls.'alias-all-no' | Should -Be 1
                $script:calls.'alias-one' | Should -Be 1
            }
        }

        Context 'Invoke-SalesforceDoctor' {
            It 'runs the diagnostics, with its options, without a question when nothing leaves the machine' {
                $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $dir | Out-Null
                Invoke-SalesforceDoctor -Command 'org list' -Plugin '@salesforce/plugin-org' -OutputDirectory $dir | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "doctor|--command|org list|--plugin|@salesforce/plugin-org|--output-dir|$dir|--json" }
            }
            It 'asks before it creates a GitHub issue, and -WhatIf does nothing' {
                Invoke-SalesforceDoctor -CreateIssue -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0
                Invoke-SalesforceDoctor -CreateIssue -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'doctor|--create-issue|--json' }
                Invoke-SalesforceDoctor -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1
            }
            It 'needs an existing output folder' {
                { Invoke-SalesforceDoctor -OutputDirectory (Join-Path $TestDrive 'nope') } | Should -Throw -ExpectedMessage '*does not exist*'
            }
        }

        Context 'Remove-SalesforceAlias' {
            It 'keeps one alias working without a question' {
                Remove-SalesforceAlias -Alias dev1 | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'alias|unset|dev1' }
            }
            It 'removes all aliases after confirmation, always telling the CLI not to ask' {
                Remove-SalesforceAlias -All -NoPrompt | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'alias|unset|--all|--no-prompt' }
                Remove-SalesforceAlias -All -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 2
                Remove-SalesforceAlias -All -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 2
            }
            It 'needs exactly one of -Alias and -All' {
                { Remove-SalesforceAlias } | Should -Throw -ExpectedMessage '*-Alias*-All*'
                { Remove-SalesforceAlias -Alias a -All } | Should -Throw -ExpectedMessage '*not both*'
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
        }

        It 'exports the new cmdlets and none of the private helper' {
            $exports = (Get-Module psfdx).ExportedFunctions.Keys
            foreach ($n in 'Get-SalesforceCommunityTemplates', 'New-SalesforceCommunity', 'Publish-SalesforceCommunity', 'Invoke-SalesforceGraphQL', 'Invoke-SalesforceRestRequest', 'Invoke-SalesforceDoctor') { $exports | Should -Contain $n }
            $exports | Should -Not -Contain 'Invoke-SalesforceText'
        }
    }
}
