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

        Context 'Upsert-SalesforceRecord' {
            BeforeEach {
                $script:Sent = $null
                $script:SentPath = $null
                Mock Invoke-Salesforce {
                    $i = [array]::IndexOf($Arguments, '--body')
                    if ($i -ge 0) { $script:Sent = [System.IO.File]::ReadAllText($Arguments[$i + 1].Substring(1)); $script:SentPath = $Arguments[$i + 1].Substring(1) }
                    $script:Reply
                } -ModuleName $module.Name
            }

            It 'creates: HTTP 201 returns Created and the new Id' {
                $script:Reply = '{"status":0,"result":{"statusCode":201,"headers":{},"body":{"id":"001xx0000000001","success":true,"errors":[]}}}'
                $res = Upsert-SalesforceRecord -Type Account -ExternalIdField Ext_Id__c -ExternalId 'A-100' -Fields @{ Name = 'Acme' } -ApiVersion 'v62.0' -TargetOrg me
                $res.Operation | Should -Be 'Created'
                $res.Created | Should -BeTrue
                $res.Id | Should -Be '001xx0000000001'
                $res.StatusCode | Should -Be 201
                $expected = "api|request|rest|/services/data/v62.0/sobjects/Account/Ext_Id__c/A-100|--method|PATCH|--body|@$script:SentPath|--target-org|me|--json"
                Assert-MockCalled Invoke-Salesforce -ModuleName $module.Name -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
                ($script:Sent | ConvertFrom-Json).Name | Should -Be 'Acme'
            }

            It 'updates: HTTP 204 returns Updated with no Id' {
                $script:Reply = '{"status":0,"result":{"statusCode":204,"headers":{},"body":""}}'
                $res = Upsert-SalesforceRecord -Type Account -ExternalIdField Ext_Id__c -ExternalId 'A-100' -Fields @{ Name = 'Acme' } -ApiVersion '62.0'
                $res.Operation | Should -Be 'Updated'
                $res.Created | Should -BeFalse
                $res.Id | Should -BeNullOrEmpty
                $res.StatusCode | Should -Be 204
                Assert-MockCalled Invoke-Salesforce -ModuleName $module.Name -ParameterFilter { (($Arguments -join '|') -like 'api|request|rest|/services/data/v62.0/*') -and ($Arguments -notcontains '--target-org') }
            }

            It 'updates: HTTP 200 (API v46.0 and later) returns Updated with the Id' {
                $script:Reply = '{"status":0,"result":{"statusCode":200,"headers":{},"body":{"id":"001xx0000000001","success":true,"created":false,"errors":[]}}}'
                $res = Upsert-SalesforceRecord -Type Account -ExternalIdField Ext_Id__c -ExternalId 'A-100' -Fields @{ Name = 'Acme' } -ApiVersion 'v62.0'
                $res.Operation | Should -Be 'Updated'
                $res.Created | Should -BeFalse
                $res.Id | Should -Be '001xx0000000001'
                $res.StatusCode | Should -Be 200
            }

            It 'reports Created for an HTTP 200 that says created is true' {
                $script:Reply = '{"status":0,"result":{"statusCode":200,"headers":{},"body":{"id":"001xx0000000002","success":true,"created":true,"errors":[]}}}'
                $res = Upsert-SalesforceRecord -Type Account -ExternalIdField Ext_Id__c -ExternalId 'A-101' -Fields @{ Name = 'Acme' } -ApiVersion 'v62.0'
                $res.Operation | Should -Be 'Created'
                $res.Id | Should -Be '001xx0000000002'
            }
            It 'uses the latest org API version when none is given' {
                $script:Reply = '{"status":0,"result":{"statusCode":204,"headers":{},"body":""}}'
                Mock Get-SalesforceLatestApiVersion { 'v66.0' } -ModuleName $module.Name
                Upsert-SalesforceRecord -Type Account -ExternalIdField Ext_Id__c -ExternalId 'A-1' -Fields @{ Name = 'x' } -TargetOrg me | Out-Null
                Assert-MockCalled Invoke-Salesforce -ModuleName $module.Name -ParameterFilter { $Arguments[3] -eq '/services/data/v66.0/sobjects/Account/Ext_Id__c/A-1' }
            }

            It 'fails clearly when the API version cannot be found' {
                Mock Get-SalesforceLatestApiVersion { $null } -ModuleName $module.Name
                { Upsert-SalesforceRecord -Type Account -ExternalIdField Ext_Id__c -ExternalId 'A-1' -Fields @{ Name = 'x' } } | Should -Throw '*Pass -ApiVersion*'
                Assert-MockCalled Invoke-Salesforce -ModuleName $module.Name -Times 0 -Exactly
            }

            It 'rejects a missing external ID value without calling the CLI' {
                { Upsert-SalesforceRecord -Type Account -ExternalIdField Ext_Id__c -ExternalId '  ' -Fields @{ Name = 'x' } -ApiVersion 'v62.0' } | Should -Throw '*ExternalId is required*'
                Assert-MockCalled Invoke-Salesforce -ModuleName $module.Name -Times 0 -Exactly
            }

            It 'rejects malformed input (<Case>) without calling the CLI' -ForEach @(
                @{ Case = 'empty fields';          Splat = @{ Type = 'Account'; ExternalIdField = 'E__c'; ExternalId = '1'; Fields = @{} };                    Message = '*Fields is empty*' }
                @{ Case = 'Id in fields';          Splat = @{ Type = 'Account'; ExternalIdField = 'E__c'; ExternalId = '1'; Fields = @{ id = 'x' } };          Message = '*must not contain Id*' }
                @{ Case = 'bad field name';        Splat = @{ Type = 'Account'; ExternalIdField = 'E__c'; ExternalId = '1'; Fields = @{ 'Na me' = 'x' } };     Message = '*not a valid Salesforce*' }
                @{ Case = 'bad object name';       Splat = @{ Type = 'Account/../x'; ExternalIdField = 'E__c'; ExternalId = '1'; Fields = @{ Name = 'x' } };   Message = '*not a valid Salesforce*' }
                @{ Case = 'bad external ID field'; Splat = @{ Type = 'Account'; ExternalIdField = 'E__c?x=1'; ExternalId = '1'; Fields = @{ Name = 'x' } };  Message = '*not a valid Salesforce*' }
                @{ Case = 'control character';     Splat = @{ Type = 'Account'; ExternalIdField = 'E__c'; ExternalId = "a`nb"; Fields = @{ Name = 'x' } };     Message = '*control characters*' }
                @{ Case = 'bad API version';       Splat = @{ Type = 'Account'; ExternalIdField = 'E__c'; ExternalId = '1'; Fields = @{ Name = 'x' }; ApiVersion = 'latest' }; Message = '*ApiVersion*not valid*' }
            ) {
                $params = $Splat
                if (-not $params.ContainsKey('ApiVersion')) { $params['ApiVersion'] = 'v62.0' }
                { Upsert-SalesforceRecord @params } | Should -Throw -ExpectedMessage $Message
                Assert-MockCalled Invoke-Salesforce -ModuleName $module.Name -Times 0 -Exactly
            }

            It 'keeps quotes, apostrophes, backslashes and metacharacters as data, never in argv' {
                $script:Reply = '{"status":0,"result":{"statusCode":204,"headers":{},"body":""}}'
                $nasty = "O'Brien \ `"x`" ; & | `$(calc) 100%"
                Upsert-SalesforceRecord -Type Account -ExternalIdField Ext_Id__c -ExternalId 'a/b c;d' -Fields @{ Name = $nasty; Rating = $null; Amount = 12.5; Active = $true } -ApiVersion 'v62.0' | Out-Null
                $sent = $script:Sent | ConvertFrom-Json
                $sent.Name | Should -Be $nasty
                $sent.Rating | Should -BeNullOrEmpty
                $sent.Amount | Should -Be 12.5
                $sent.Active | Should -BeTrue
                Assert-MockCalled Invoke-Salesforce -ModuleName $module.Name -ParameterFilter {
                    ($Arguments[3] -eq '/services/data/v62.0/sobjects/Account/Ext_Id__c/a%2Fb%20c%3Bd') -and (($Arguments -join '|') -notmatch 'Brien|calc')
                }
            }

            It 'sends dates as UTC and removes the temporary body file' {
                $script:Reply = '{"status":0,"result":{"statusCode":204,"headers":{},"body":""}}'
                $when = [datetime]::SpecifyKind([datetime]'2026-11-18T12:00:00', [DateTimeKind]::Utc)
                Upsert-SalesforceRecord -Type Event -ExternalIdField E__c -ExternalId '1' -Fields @{ StartDateTime = $when } -ApiVersion 'v62.0' | Out-Null
                $script:Sent | Should -BeLike '*"StartDateTime":"2026-11-18T12:00:00.000Z"*'
                Test-Path -LiteralPath $script:SentPath | Should -BeFalse
            }

            It 'removes the temporary body file when the CLI fails' {
                $script:Reply = '{"status":1,"name":"Error","message":"No authorization information found for nobody."}'
                { Upsert-SalesforceRecord -Type Account -ExternalIdField Ext_Id__c -ExternalId '1' -Fields @{ Name = 'x' } -ApiVersion 'v62.0' -TargetOrg nobody } | Should -Throw '*No authorization*'
                Test-Path -LiteralPath $script:SentPath | Should -BeFalse
            }

            It 'reports a Salesforce error returned as an HTTP failure' {
                $script:Reply = '{"status":0,"result":{"statusCode":404,"headers":{},"body":[{"message":"The requested resource does not exist","errorCode":"NOT_FOUND"}]}}'
                { Upsert-SalesforceRecord -Type Nope__c -ExternalIdField Ext_Id__c -ExternalId '1' -Fields @{ Name = 'x' } -ApiVersion 'v62.0' } | Should -Throw '*HTTP status 404*NOT_FOUND*does not exist*'
            }

            It 'reports a multiple-match response (300) instead of treating it as success' {
                $script:Reply = '{"status":0,"result":{"statusCode":300,"headers":{},"body":["/services/data/v62.0/sobjects/Account/001xx0000000001","/services/data/v62.0/sobjects/Account/001xx0000000002"]}}'
                { Upsert-SalesforceRecord -Type Account -ExternalIdField Ext_Id__c -ExternalId '1' -Fields @{ Name = 'x' } -ApiVersion 'v62.0' } | Should -Throw '*HTTP status 300*'
            }

            It 'is exported by the module manifest' {
                (Import-PowerShellDataFile -Path (Join-Path (Get-Module -Name psfdx).ModuleBase 'psfdx.psd1')).FunctionsToExport | Should -Contain 'Upsert-SalesforceRecord'
                Get-Command -Module $module.Name -Name Upsert-SalesforceRecord | Should -Not -BeNullOrEmpty
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

Describe 'Bulk API 2.0 commands' {
    InModuleScope 'psfdx' {
        BeforeAll {
            $script:JobId = '750xx0000000001'
            $script:Async = '{"status":0,"result":{"jobId":"750xx0000000001AAA"}}'
            $script:Done = '{"status":0,"result":{"jobId":"750xx0000000001AAA","processedRecords":10,"successfulRecords":10,"failedRecords":0}}'
            $script:Partial = '{"status":1,"name":"failedRecordDetails","message":"Job finished being processed but 3 records failed to process.","data":{"jobId":"750xx0000000001AAA","state":"JobComplete"}}'
        }
        BeforeEach {
            $script:Reply = $script:Done
            $script:Cwd = $null
            Mock Invoke-Salesforce { $script:Cwd = (Get-Location).ProviderPath; $script:Reply }
            $script:Csv = Join-Path $TestDrive 'my accounts.csv'
            Set-Content -LiteralPath $script:Csv -Value "Id,Name`n001,A"
        }

        Context 'Import, update and upsert: arguments' {
            It 'builds the exact import command, with a path containing spaces, as one argument' {
                Import-SalesforceBulkData -File $script:Csv -Object Account -TargetOrg me | Out-Null
                $expected = "data|import|bulk|--file|$script:Csv|--sobject|Account|--target-org|me|--json"
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
            }
            It 'builds the exact update command with delimiter, line ending and wait' {
                Update-SalesforceBulkData -File $script:Csv -Object Contact -ColumnDelimiter PIPE -LineEnding CRLF -WaitMinutes 10 | Out-Null
                $expected = "data|update|bulk|--file|$script:Csv|--sobject|Contact|--column-delimiter|PIPE|--line-ending|CRLF|--wait|10|--json"
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
            }
            It 'builds the exact upsert command with the external ID field' {
                Upsert-SalesforceBulkData -File $script:Csv -Object Account -ExternalIdField Ext_Id__c -TargetOrg me | Out-Null
                $expected = "data|upsert|bulk|--file|$script:Csv|--sobject|Account|--external-id|Ext_Id__c|--target-org|me|--json"
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
            }
            It 'rejects <Case> without calling the CLI' -ForEach @(
                @{ Case = 'a missing file';           Run = { Import-SalesforceBulkData -File (Join-Path $TestDrive 'nope.csv') -Object Account };                          Message = '*does not exist*' }
                @{ Case = 'a bad object name';        Run = { Import-SalesforceBulkData -File $script:Csv -Object 'Account; DROP' };                                         Message = '*not a valid Salesforce*' }
                @{ Case = 'a bad external ID field';  Run = { Upsert-SalesforceBulkData -File $script:Csv -Object Account -ExternalIdField 'Ext Id' };                       Message = '*not a valid Salesforce*' }
                @{ Case = 'an unknown delimiter';     Run = { Update-SalesforceBulkData -File $script:Csv -Object Account -ColumnDelimiter 'TABS' };                         Message = '*TABS*' }
                @{ Case = 'a negative wait';          Run = { Import-SalesforceBulkData -File $script:Csv -Object Account -WaitMinutes -1 };                                 Message = '*-1*' }
            ) {
                { & $Run } | Should -Throw -ExpectedMessage $Message
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'makes no CLI call under -WhatIf for import, update and upsert' {
                Import-SalesforceBulkData -File $script:Csv -Object Account -WhatIf | Should -BeNullOrEmpty
                Update-SalesforceBulkData -File $script:Csv -Object Account -WhatIf | Should -BeNullOrEmpty
                Upsert-SalesforceBulkData -File $script:Csv -Object Account -ExternalIdField E__c -WhatIf | Should -BeNullOrEmpty
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'names the object, the file and the org in the confirmation target' {
                $label = Get-SalesforceBulkTargetLabel -Object Account -File 'a.csv' -TargetOrg me
                $label | Should -Be "Account records from 'a.csv' in org me"
                Get-SalesforceBulkTargetLabel -Object Account -File 'a.csv' | Should -BeLike '*the default org'
            }
            It 'does not pass -WhatIf or -Confirm on to the CLI wrapper' {
                Import-SalesforceBulkData -File $script:Csv -Object Account -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly
            }
        }

        Context 'job results' {
            It 'returns the JobId of an asynchronous job, with no counts yet' {
                $script:Reply = $script:Async
                $res = Import-SalesforceBulkData -File $script:Csv -Object Account
                $res.JobId | Should -Be '750xx0000000001AAA'
                $res.Completed | Should -BeFalse
                $res.ProcessedRecords | Should -BeNullOrEmpty
                $res.Operation | Should -Be 'Import'
                $res.Object | Should -Be 'Account'
            }
            It 'returns the counts of a finished job' {
                $res = Upsert-SalesforceBulkData -File $script:Csv -Object Account -ExternalIdField E__c -WaitMinutes 5
                $res.Completed | Should -BeTrue
                $res.ProcessedRecords | Should -Be 10
                $res.SuccessfulRecords | Should -Be 10
                $res.FailedRecords | Should -Be 0
            }
            It 'throws PsfdxBulkJobFailed with the job ID when rows failed' {
                $script:Reply = $script:Partial
                $err = $null
                try { Update-SalesforceBulkData -File $script:Csv -Object Account -WaitMinutes 5 | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxBulkJobFailed'
                $err.TargetObject.JobId | Should -Be '750xx0000000001AAA'
                $err.TargetObject.State | Should -Be 'JobComplete'
                $err.Exception.Message | Should -BeLike '*3 records failed*Get-SalesforceBulkResult -JobId 750xx0000000001AAA*'
            }
            It 'finds the job ID in the message when the CLI sends no data' {
                $script:Reply = '{"status":1,"message":"Job 750xx0000000009AAA failed: LimitExceeded"}'
                $err = $null
                try { Import-SalesforceBulkData -File $script:Csv -Object Account -WaitMinutes 5 | Out-Null } catch { $err = $_ }
                $err.TargetObject.JobId | Should -Be '750xx0000000009AAA'
            }
            It 'throws the CLI message for other failures' {
                $script:Reply = '{"status":1,"name":"NamedOrgNotFoundError","message":"No authorization information found for nobody."}'
                { Import-SalesforceBulkData -File $script:Csv -Object Account -TargetOrg nobody } | Should -Throw -ExpectedMessage '*No authorization information found*'
            }
            It 'rejects empty, non-JSON and statusless output' {
                $script:Reply = ''
                { Import-SalesforceBulkData -File $script:Csv -Object Account } | Should -Throw -ExpectedMessage '*no output*'
                $script:Reply = 'warning: odd'
                { Import-SalesforceBulkData -File $script:Csv -Object Account } | Should -Throw -ExpectedMessage '*not valid JSON*'
                $script:Reply = '{"result":{"jobId":"750xx0000000001AAA"}}'
                { Import-SalesforceBulkData -File $script:Csv -Object Account } | Should -Throw -ExpectedMessage '*no status*'
            }
        }

        Context 'upsert results use the { jobInfo, records } shape' {
            BeforeAll {
                $script:UpsertAsync = '{"status":0,"result":{"jobInfo":{"id":"750xx0000000003AAA","state":"UploadComplete","operation":"upsert","object":"Account","numberRecordsProcessed":0,"numberRecordsFailed":0},"records":{"successfulResults":[],"failedResults":[],"unprocessedRecords":[]}}}'
                $script:UpsertDone = '{"status":0,"result":{"jobInfo":{"id":"750xx0000000003AAA","state":"JobComplete","operation":"upsert","object":"Account","numberRecordsProcessed":10,"numberRecordsFailed":0},"records":{"successfulResults":[],"failedResults":[],"unprocessedRecords":[]}}}'
                $script:UpsertPartialOk = '{"status":0,"result":{"jobInfo":{"id":"750xx0000000003AAA","state":"JobComplete","operation":"upsert","object":"Account","numberRecordsProcessed":10,"numberRecordsFailed":3},"records":{"successfulResults":[],"failedResults":[{"sf__Id":"","sf__Error":"bad"}],"unprocessedRecords":[]}}}'
                $script:UpsertPartialStatus1 = $script:UpsertPartialOk.Replace('"status":0', '"status":1')
            }
            It 'returns the JobId of a newly submitted upsert, with no counts yet' {
                $script:Reply = $script:UpsertAsync
                $res = Upsert-SalesforceBulkData -File $script:Csv -Object Account -ExternalIdField E__c
                $res.JobId | Should -Be '750xx0000000003AAA'
                $res.State | Should -Be 'UploadComplete'
                $res.Completed | Should -BeFalse
                $res.ProcessedRecords | Should -BeNullOrEmpty
                $res.Operation | Should -Be 'Upsert'
            }
            It 'returns the counts of a completed upsert' {
                $script:Reply = $script:UpsertDone
                $res = Upsert-SalesforceBulkData -File $script:Csv -Object Account -ExternalIdField E__c -WaitMinutes 5
                $res.Completed | Should -BeTrue
                $res.ProcessedRecords | Should -Be 10
                $res.SuccessfulRecords | Should -Be 10
                $res.FailedRecords | Should -Be 0
                $res.State | Should -Be 'JobComplete'
            }
            It 'throws PsfdxBulkJobFailed when an upsert finishes with failed rows, whether the CLI reports success or not' -ForEach @(
                @{ Name = 'status 0'; Json = 'UpsertPartialOk' }
                @{ Name = 'status 1'; Json = 'UpsertPartialStatus1' }
            ) {
                $script:Reply = Get-Variable -Scope Script -Name $Json -ValueOnly
                $err = $null
                try { Upsert-SalesforceBulkData -File $script:Csv -Object Account -ExternalIdField E__c -WaitMinutes 5 | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxBulkJobFailed'
                $err.TargetObject.JobId | Should -Be '750xx0000000003AAA'
                $err.TargetObject.State | Should -Be 'JobComplete'
                $err.Exception.Message | Should -BeLike '*3 records failed*'
            }
            It 'applies the same check to an upsert resume' {
                $script:Reply = $script:UpsertPartialOk
                $err = $null
                try { Resume-SalesforceBulkJob -Operation Upsert -JobId $script:JobId -WaitMinutes 5 | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxBulkJobFailed'
                $script:Reply = $script:UpsertDone
                (Resume-SalesforceBulkJob -Operation Upsert -JobId $script:JobId -WaitMinutes 5).ProcessedRecords | Should -Be 10
            }
            It 'throws for a Failed or Aborted upsert job, with the job error message' {
                $script:Reply = '{"status":0,"result":{"jobInfo":{"id":"750xx0000000003AAA","state":"Failed","errorMessage":"InvalidBatch : Field name not found"},"records":{}}}'
                $err = $null
                try { Upsert-SalesforceBulkData -File $script:Csv -Object Account -ExternalIdField E__c -WaitMinutes 5 | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxBulkJobFailed'
                $err.Exception.Message | Should -BeLike '*The job is Failed*Field name not found*'
            }
        }
        Context 'Export-SalesforceBulkData' {
            It 'builds the exact command for a query, waiting' {
                $script:Reply = '{"status":0,"result":{"totalSize":5,"filePath":"out.csv"}}'
                $res = Export-SalesforceBulkData -Query "SELECT Id FROM Account WHERE Name = 'O\'Brien'" -OutputFile 'out.csv' -WaitMinutes 10 -TargetOrg me -AllRows
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "data|export|bulk|--query|SELECT Id FROM Account WHERE Name = 'O\'Brien'|--output-file|out.csv|--result-format|csv|--all-rows|--wait|10|--target-org|me|--json" }
                $res.TotalSize | Should -Be 5
                $res.FilePath | Should -Be 'out.csv'
                $res.Completed | Should -BeTrue
            }
            It 'builds the exact command for a query file and returns the JobId when asynchronous' {
                $qf = Join-Path $TestDrive 'my query.soql'
                Set-Content -LiteralPath $qf -Value 'SELECT Id FROM Account'
                $script:Reply = '{"status":0,"result":{"jobId":"750xx0000000002AAA","filePath":"o.json"}}'
                $res = Export-SalesforceBulkData -QueryFile $qf -OutputFile 'o.json' -ResultFormat json
                $expected = "data|export|bulk|--query-file|$qf|--output-file|o.json|--result-format|json|--json"
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
                $res.JobId | Should -Be '750xx0000000002AAA'
                $res.Completed | Should -BeFalse
            }
            It 'rejects <Case> without calling the CLI' -ForEach @(
                @{ Case = 'no query';               Run = { Export-SalesforceBulkData -OutputFile 'o.csv' };                                                          Message = '*exactly one*' }
                @{ Case = 'both query forms';       Run = { Export-SalesforceBulkData -Query 'SELECT Id FROM Account' -QueryFile 'q.soql' -OutputFile 'o.csv' };      Message = '*exactly one*' }
                @{ Case = 'a missing query file';   Run = { Export-SalesforceBulkData -QueryFile (Join-Path $TestDrive 'no.soql') -OutputFile 'o.csv' };              Message = '*does not exist*' }
                @{ Case = 'a missing output folder'; Run = { Export-SalesforceBulkData -Query 'SELECT Id FROM Account' -OutputFile (Join-Path (Join-Path $TestDrive 'nodir') 'o.csv') }; Message = '*Output directory*does not exist*' }
            ) {
                { & $Run } | Should -Throw -ExpectedMessage $Message
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Resume-SalesforceBulkJob' {
            It 'builds the exact command for each operation' -ForEach @(
                @{ Op = 'Export'; Expected = 'data|export|resume|--job-id|750xx0000000001|--json' }
                @{ Op = 'Import'; Expected = 'data|import|resume|--job-id|750xx0000000001|--wait|5|--json' }
                @{ Op = 'Update'; Expected = 'data|update|resume|--job-id|750xx0000000001|--wait|5|--json' }
                @{ Op = 'Upsert'; Expected = 'data|upsert|resume|--job-id|750xx0000000001|--wait|5|--target-org|me|--json' }
            ) {
                Resume-SalesforceBulkJob -Operation $Op -JobId $script:JobId -WaitMinutes 5 -TargetOrg me -WarningAction SilentlyContinue | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $Expected }
            }
            It 'warns when -TargetOrg or -WaitMinutes cannot be honoured' {
                $w = @()
                Resume-SalesforceBulkJob -Operation Import -JobId $script:JobId -TargetOrg me -WarningVariable w -WarningAction SilentlyContinue | Out-Null
                ($w -join ' ') | Should -BeLike '*TargetOrg is ignored*'
                Resume-SalesforceBulkJob -Operation Export -JobId $script:JobId -WaitMinutes 3 -WarningVariable w -WarningAction SilentlyContinue | Out-Null
                ($w -join ' ') | Should -BeLike '*WaitMinutes is ignored*'
            }
            It 'resumes a job and reports failed rows' {
                $res = Resume-SalesforceBulkJob -Operation Import -JobId $script:JobId -WaitMinutes 5
                $res.Operation | Should -Be 'Import'
                $res.ProcessedRecords | Should -Be 10
                $script:Reply = $script:Partial
                $err = $null
                try { Resume-SalesforceBulkJob -Operation Update -JobId $script:JobId | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxBulkJobFailed'
            }
            It 'rejects a malformed job ID and a bad operation without calling the CLI' {
                { Resume-SalesforceBulkJob -Operation Import -JobId '001xx0000000001' } | Should -Throw
                { Resume-SalesforceBulkJob -Operation Import -JobId '750xx0000000001; calc' } | Should -Throw
                { Resume-SalesforceBulkJob -Operation Delete -JobId $script:JobId } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Get-SalesforceBulkResult' {
            BeforeEach {
                $script:Out = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'bulk out') -Force
                $script:ResultJson = '{"status":0,"result":{"status":"JobComplete","operation":"update","object":"Account","processedRecords":10,"successfulRecords":8,"failedRecords":2,"successFilePath":"750xx0000000001-success-records.csv","failedFilePath":"750xx0000000001-failed-records.csv"}}'
            }
            It 'runs the CLI in the output directory and returns the full file paths' {
                $script:Reply = $script:ResultJson
                $before = (Get-Location).ProviderPath
                $res = Get-SalesforceBulkResult -JobId $script:JobId -OutputDirectory $script:Out.FullName -TargetOrg me -WarningAction SilentlyContinue
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'data|bulk|results|--job-id|750xx0000000001|--target-org|me|--json' }
                $script:Cwd | Should -Be $script:Out.FullName
                (Get-Location).ProviderPath | Should -Be $before
                $res.SuccessFilePath | Should -Be (Join-Path $script:Out.FullName '750xx0000000001-success-records.csv')
                $res.FailedFilePath | Should -Be (Join-Path $script:Out.FullName '750xx0000000001-failed-records.csv')
                $res.UnprocessedFilePath | Should -BeNullOrEmpty
                $res.FailedRecords | Should -Be 2
                $res.HasFailures | Should -BeTrue
            }
            It 'warns about failed rows but does not throw' {
                $script:Reply = $script:ResultJson
                $w = @()
                Get-SalesforceBulkResult -JobId $script:JobId -OutputDirectory $script:Out.FullName -WarningVariable w -WarningAction SilentlyContinue | Out-Null
                ($w -join ' ') | Should -BeLike '*2 record(s) failed*'
            }
            It 'reports no failures when every row succeeded' {
                $script:Reply = '{"status":0,"result":{"status":"JobComplete","operation":"insert","object":"Account","processedRecords":3,"successfulRecords":3,"failedRecords":0,"successFilePath":"750xx0000000001-success-records.csv"}}'
                $res = Get-SalesforceBulkResult -JobId $script:JobId -OutputDirectory $script:Out.FullName
                $res.HasFailures | Should -BeFalse
                $res.FailedFilePath | Should -BeNullOrEmpty
            }
            It 'throws the CLI message when the job is not finished or does not exist' {
                $script:Reply = '{"status":1,"name":"jobInProgress","message":"The job is still in progress."}'
                { Get-SalesforceBulkResult -JobId $script:JobId -OutputDirectory $script:Out.FullName } | Should -Throw -ExpectedMessage '*still in progress*'
            }
            It 'rejects a missing output directory and a malformed job ID without calling the CLI' {
                { Get-SalesforceBulkResult -JobId $script:JobId -OutputDirectory (Join-Path $TestDrive 'nope') } | Should -Throw -ExpectedMessage '*does not exist*'
                { Get-SalesforceBulkResult -JobId 'abc' } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'module surface' {
            It 'exports the six commands and keeps the helpers private' {
                $exports = (Import-PowerShellDataFile -Path (Join-Path (Get-Module -Name psfdx).ModuleBase 'psfdx.psd1')).FunctionsToExport
                foreach ($name in 'Export-SalesforceBulkData', 'Import-SalesforceBulkData', 'Update-SalesforceBulkData', 'Upsert-SalesforceBulkData', 'Resume-SalesforceBulkJob', 'Get-SalesforceBulkResult') {
                    $exports | Should -Contain $name
                }
                $exports | Should -Not -Contain 'ConvertFrom-SalesforceBulkOutput'
                $exports | Should -Not -Contain 'ConvertTo-SalesforceBulkJobObject'
                $exports | Should -Not -Contain 'Get-SalesforceBulkTargetLabel'
            }
            It 'has help examples' {
                foreach ($name in 'Export-SalesforceBulkData', 'Import-SalesforceBulkData', 'Update-SalesforceBulkData', 'Upsert-SalesforceBulkData', 'Resume-SalesforceBulkJob', 'Get-SalesforceBulkResult') {
                    @((Get-Help $name -Examples).examples.example).Count | Should -BeGreaterThan 0
                }
            }
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
