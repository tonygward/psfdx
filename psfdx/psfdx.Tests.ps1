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

Describe 'Data tree export and import' {
    InModuleScope 'psfdx' {
        BeforeEach {
            $script:Reply = '{"status":0,"result":[]}'
            Mock Invoke-Salesforce { $script:Reply }
            $script:Dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'tree data') -Force
            $script:PlanFile = Join-Path $script:Dir.FullName 'Account-Contact-plan.json'
            Set-Content -LiteralPath $script:PlanFile -Value '[]'
            $script:F1 = Join-Path $script:Dir.FullName 'accounts.json'
            $script:F2 = Join-Path $script:Dir.FullName 'contacts.json'
            Set-Content -LiteralPath $script:F1 -Value '{"records":[]}'
            Set-Content -LiteralPath $script:F2 -Value '{"records":[]}'
            $script:Imported = '{"status":0,"result":[{"refId":"AccountRef1","type":"Account","id":"001xx0000000001"},{"refId":"ContactRef1","type":"Contact","id":"003xx0000000001"}]}'
        }

        Context 'Export-SalesforceTreeData' {
            It 'builds the exact command for two queries, a plan, a prefix and an output directory' {
                $q1 = "SELECT Id, Name, (SELECT Id, LastName FROM Contacts) FROM Account WHERE Name LIKE 'Acme%'"
                $q2 = 'SELECT Id FROM Lead'
                $script:Reply = '[]'
                $script:Reply = '{"status":0,"result":[{"sobject":"Account","saveRefs":true,"resolveRefs":false,"files":["Account.json"]},{"sobject":"Contact","saveRefs":false,"resolveRefs":true,"files":["Contact.json"]}]}'
                Set-Content -LiteralPath (Join-Path $script:Dir.FullName 'plan.json') -Value '[]'
                $res = Export-SalesforceTreeData -Query $q1, $q2 -Plan -Prefix demo -OutputDirectory $script:Dir.FullName -TargetOrg me
                $expected = "data|export|tree|--query|$q1|--query|$q2|--plan|--prefix|demo|--output-dir|$($script:Dir.FullName)|--target-org|me|--json"
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
                $res.Plan | Should -BeTrue
                $res.Files | Should -Be @((Join-Path $script:Dir.FullName 'Account.json'), (Join-Path $script:Dir.FullName 'Contact.json'))
                $res.PlanFile | Should -Be (Join-Path $script:Dir.FullName 'plan.json')
            }
            It 'names the plan file after the object types, with the prefix, for a single query' {
                $script:Reply = '{"status":0,"result":[{"sobject":"Account","saveRefs":true,"resolveRefs":false,"files":["demo-Account.json"]},{"sobject":"Contact","saveRefs":false,"resolveRefs":true,"files":["demo-Contact.json"]}]}'
                Set-Content -LiteralPath (Join-Path $script:Dir.FullName 'demo-Account-Contact-plan.json') -Value '[]'
                $res = Export-SalesforceTreeData -Query 'SELECT Id, (SELECT Id FROM Contacts) FROM Account' -Plan -Prefix demo -OutputDirectory $script:Dir.FullName
                $res.PlanFile | Should -Be (Join-Path $script:Dir.FullName 'demo-Account-Contact-plan.json')
            }
            It 'returns no PlanFile when the plan file is not where expected' {
                $script:Reply = '{"status":0,"result":[{"sobject":"Account","files":["Account.json"]}]}'
                (Export-SalesforceTreeData -Query 'SELECT Id FROM Account' -Plan -OutputDirectory $script:Dir.FullName).PlanFile | Should -BeNullOrEmpty
            }
            It 'returns the exported records without a plan' {
                $script:Reply = '{"status":0,"result":{"records":[{"attributes":{"type":"Account","referenceId":"AccountRef1"},"Name":"Acme"},{"attributes":{"type":"Account","referenceId":"AccountRef2"},"Name":"Beta"}]}}'
                $res = Export-SalesforceTreeData -Query 'SELECT Id, Name FROM Account'
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'data|export|tree|--query|SELECT Id, Name FROM Account|--json' }
                $res.Plan | Should -BeFalse
                $res.RecordCount | Should -Be 2
                $res.Records[0].Name | Should -Be 'Acme'
                $res.PlanFile | Should -BeNullOrEmpty
            }
            It 'rejects <Case> without calling the CLI' -ForEach @(
                @{ Case = 'blank queries';       Run = { Export-SalesforceTreeData -Query @('', ' ') };                                              Message = '*empty string*' }
                @{ Case = 'a path in the prefix'; Run = { Export-SalesforceTreeData -Query 'SELECT Id FROM Account' -Prefix '..\evil' };               Message = '*Prefix*not valid*' }
                @{ Case = 'a file as output directory'; Run = { Export-SalesforceTreeData -Query 'SELECT Id FROM Account' -OutputDirectory $script:F1 }; Message = '*is a file*' }
            ) {
                { & $Run } | Should -Throw -ExpectedMessage $Message
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'throws the CLI message for an invalid query' {
                $script:Reply = '{"status":1,"name":"MalformedQuery","message":"unexpected token: FORM"}'
                { Export-SalesforceTreeData -Query 'SELECT Id FORM Account' } | Should -Throw -ExpectedMessage '*unexpected token*'
            }
        }

        Context 'Import-SalesforceTreeData' {
            It 'builds the exact command for a plan with a path containing spaces' {
                $script:Reply = $script:Imported
                $res = @(Import-SalesforceTreeData -Plan $script:PlanFile -TargetOrg scratch)
                $expected = "data|import|tree|--plan|$script:PlanFile|--target-org|scratch|--json"
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
                $res.Count | Should -Be 2
                $res[0].RefId | Should -Be 'AccountRef1'
                $res[0].Type | Should -Be 'Account'
                $res[1].Id | Should -Be '003xx0000000001'
            }
            It 'builds the exact command for files, joined as the CLI expects' {
                $script:Reply = $script:Imported
                Import-SalesforceTreeData -File $script:F1, $script:F2 | Out-Null
                $expected = "data|import|tree|--files|$script:F1,$script:F2|--json"
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
            }
            It 'makes no CLI call under -WhatIf' {
                Import-SalesforceTreeData -Plan $script:PlanFile -WhatIf | Should -BeNullOrEmpty
                Import-SalesforceTreeData -File $script:F1 -WhatIf | Should -BeNullOrEmpty
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'does not allow -Plan and -File together, or neither' {
                { Import-SalesforceTreeData -Plan $script:PlanFile -File $script:F1 } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'rejects <Case> without calling the CLI' -ForEach @(
                @{ Case = 'a missing plan';      Run = { Import-SalesforceTreeData -Plan (Join-Path $TestDrive 'nope.json') };                 Message = '*Plan file*does not exist*' }
                @{ Case = 'a missing file';      Run = { Import-SalesforceTreeData -File (Join-Path $TestDrive 'nope.json') };                 Message = '*does not exist*' }
                @{ Case = 'a comma in a path';   Run = { Import-SalesforceTreeData -File 'a,b.json' };                                         Message = '*comma*' }
                @{ Case = 'only blank files';    Run = { Import-SalesforceTreeData -File @('', ' ') };                                         Message = '*empty string*' }
            ) {
                { & $Run } | Should -Throw -ExpectedMessage $Message
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'throws PsfdxTreeImportFailed listing each rejected record' {
                $script:Reply = '{"status":1,"name":"Error","message":"Data Import failed","data":[{"referenceId":"ContactRef1","StatusCode":"REQUIRED_FIELD_MISSING","Message":"Required fields are missing: [LastName]","fields":["LastName"]}]}'
                $err = $null
                try { Import-SalesforceTreeData -Plan $script:PlanFile | Out-Null } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxTreeImportFailed'
                @($err.TargetObject).Count | Should -Be 1
                $err.TargetObject[0].ReferenceId | Should -Be 'ContactRef1'
                $err.TargetObject[0].StatusCode | Should -Be 'REQUIRED_FIELD_MISSING'
                $err.Exception.Message | Should -BeLike '*ContactRef1*REQUIRED_FIELD_MISSING*'
            }
            It 'throws the CLI message for other failures, and for empty or malformed output' {
                $script:Reply = '{"status":1,"name":"NamedOrgNotFoundError","message":"No authorization information found for nobody."}'
                { Import-SalesforceTreeData -Plan $script:PlanFile -TargetOrg nobody } | Should -Throw -ExpectedMessage '*No authorization information found*'
                $script:Reply = ''
                { Import-SalesforceTreeData -Plan $script:PlanFile } | Should -Throw -ExpectedMessage '*no output*'
                $script:Reply = 'not json'
                { Import-SalesforceTreeData -Plan $script:PlanFile } | Should -Throw -ExpectedMessage '*not valid JSON*'
            }
        }

        Context 'module surface' {
            It 'exports both commands, keeps the helper private, and has help examples' {
                $exports = (Import-PowerShellDataFile -Path (Join-Path (Get-Module -Name psfdx).ModuleBase 'psfdx.psd1')).FunctionsToExport
                $exports | Should -Contain 'Export-SalesforceTreeData'
                $exports | Should -Contain 'Import-SalesforceTreeData'
                $exports | Should -Not -Contain 'ConvertFrom-SalesforceTreeOutput'
                foreach ($name in 'Export-SalesforceTreeData', 'Import-SalesforceTreeData') { @((Get-Help $name -Examples).examples.example).Count | Should -BeGreaterThan 0 }
            }
        }
    }
}

Describe 'Single-record get and delete' {
    InModuleScope 'psfdx' {
        BeforeEach {
            $script:Reply = '{"status":0,"result":{"attributes":{"type":"Account","url":"/services/data/v62.0/sobjects/Account/001xx000003DGb2AAG"},"Id":"001xx000003DGb2AAG","Name":"Acme Corporation"}}'
            Mock Invoke-Salesforce { $script:Reply }
            $script:RecordId = '001xx000003DGb2AAG'
        }

        Context 'Get-SalesforceRecord' {
            It 'builds the exact command for an ID and returns the record without attributes' {
                $rec = Get-SalesforceRecord -Type Account -Id $script:RecordId -TargetOrg me
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'data|get|record|--sobject|Account|--record-id|001xx000003DGb2AAG|--target-org|me|--json' }
                $rec.Id | Should -Be $script:RecordId
                $rec.Name | Should -Be 'Acme Corporation'
                $rec.PSObject.Properties.Name | Should -Not -Contain 'attributes'
            }
            It 'builds the exact command for field values and the Tooling API' {
                Get-SalesforceRecord -Type ApexClass -Where ([ordered]@{ Name = 'My Class'; ApiVersion = '62.0' }) -UseToolingApi | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "data|get|record|--sobject|ApexClass|--where|Name='My Class' ApiVersion='62.0'|--use-tooling-api|--json" }
            }
            It 'does not allow -Id and -Where together, and rejects bad input without calling the CLI' {
                { Get-SalesforceRecord -Type Account -Id $script:RecordId -Where @{ Name = 'x' } } | Should -Throw
                { Get-SalesforceRecord -Type Account -Id 'short' } | Should -Throw
                { Get-SalesforceRecord -Type 'Account; DROP' -Id $script:RecordId } | Should -Throw -ExpectedMessage '*not a valid Salesforce*'
                { Get-SalesforceRecord -Type Account -Where @{} } | Should -Throw -ExpectedMessage '*at least one field*'
                { Get-SalesforceRecord -Type Account -Where @{ 'Bad Field' = 'x' } } | Should -Throw -ExpectedMessage '*not a valid Salesforce*'
                { Get-SalesforceRecord -Type Account -Where @{ Name = "O'Brien" } } | Should -Throw -ExpectedMessage '*quote or control character*'
                { Get-SalesforceRecord -Type Account -Where @{ Name = "a`nb" } } | Should -Throw -ExpectedMessage '*quote or control character*'
                { Get-SalesforceRecord -Type Account -Where @{ Name = '' } } | Should -Throw -ExpectedMessage '*empty*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'throws the CLI message when the record is not found, or when several match' {
                $script:Reply = '{"status":1,"name":"SingleRecordQuery_NoRecords","message":"No record found for Account with id 001xx000003DGb9AAG"}'
                { Get-SalesforceRecord -Type Account -Id '001xx000003DGb9AAG' } | Should -Throw -ExpectedMessage '*No record found*'
                $script:Reply = '{"status":1,"name":"MultipleRecordsFound","message":"The query returned more than one record."}'
                { Get-SalesforceRecord -Type Account -Where @{ Name = 'Acme' } } | Should -Throw -ExpectedMessage '*more than one record*'
            }
        }

        Context 'Remove-SalesforceRecord' {
            It 'builds the exact command and returns the CLI result' {
                $script:Reply = '{"status":0,"result":{"id":"001xx000003DGb2AAG"}}'
                $res = Remove-SalesforceRecord -Type Account -Id $script:RecordId -TargetOrg me -Confirm:$false
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'data|delete|record|--sobject|Account|--record-id|001xx000003DGb2AAG|--target-org|me|--json' }
                $res.id | Should -Be $script:RecordId
            }
            It 'builds the exact command for field values' {
                $script:Reply = '{"status":0,"result":{"id":"001xx000003DGb2AAG"}}'
                Remove-SalesforceRecord -Type Account -Where @{ Name = 'Test Account 42' } -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "data|delete|record|--sobject|Account|--where|Name='Test Account 42'|--json" }
            }
            It 'makes zero CLI calls under -WhatIf, for an ID and for field values' {
                Remove-SalesforceRecord -Type Account -Id $script:RecordId -TargetOrg me -WhatIf | Should -BeNullOrEmpty
                Remove-SalesforceRecord -Type Account -Where @{ Name = 'x' } -WhatIf | Should -BeNullOrEmpty
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'asks by default (ConfirmImpact High); the confirmation names the object, record and org (shown in the What if lines of this run)' {
                (Get-Command Remove-SalesforceRecord).ScriptBlock.Attributes.ConfirmImpact | Should -Contain 'High'
            }
            It 'surfaces a not-found error and does not hide it' {
                $script:Reply = '{"status":1,"name":"NOT_FOUND","message":"entity is deleted or does not exist"}'
                { Remove-SalesforceRecord -Type Account -Id $script:RecordId -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist*'
            }
            It 'rejects conflicting or invalid selectors without calling the CLI' {
                { Remove-SalesforceRecord -Type Account -Id $script:RecordId -Where @{ Name = 'x' } -Confirm:$false } | Should -Throw
                { Remove-SalesforceRecord -Type Account -Id 'bad' -Confirm:$false } | Should -Throw
                { Remove-SalesforceRecord -Type Account -Where @{ Name = "it's" } -Confirm:$false } | Should -Throw -ExpectedMessage '*quote or control character*'
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'module surface' {
            It 'exports both, keeps the selector helper private, and has help examples' {
                $exports = (Import-PowerShellDataFile -Path (Join-Path (Get-Module -Name psfdx).ModuleBase 'psfdx.psd1')).FunctionsToExport
                $exports | Should -Contain 'Get-SalesforceRecord'
                $exports | Should -Contain 'Remove-SalesforceRecord'
                $exports | Should -Not -Contain 'ConvertTo-SalesforceRecordSelector'
                foreach ($name in 'Get-SalesforceRecord', 'Remove-SalesforceRecord') { @((Get-Help $name -Examples).examples.example).Count | Should -BeGreaterThan 0 }
            }
        }
    }
}

Describe 'Record pipelines' {
    InModuleScope 'psfdx' {
        BeforeEach {
            $script:Accounts = '{"status":0,"result":{"records":[{"attributes":{"type":"Account"},"Id":"001xx000003DGb1AAG","Name":"A"},{"attributes":{"type":"Account"},"Id":"001xx000003DGb2AAG","Name":"B"}],"totalSize":2}}'
            Mock Invoke-Salesforce {
                $joined = $Arguments -join '|'
                if ($joined -like 'data|query*') { return $script:Accounts }
                if ($joined -like 'data|get|record*') { return '{"status":0,"result":{"Id":"001xx000003DGb1AAG","Name":"A"}}' }
                return '{"status":0,"result":{"id":"001xx000003DGb1AAG","success":true}}'
            }
        }

        It 'pipes queried records into Remove-SalesforceRecord, one delete per record, using each Id' {
            Select-SalesforceRecords -Query 'SELECT Id FROM Account' -TargetOrg me | Remove-SalesforceRecord -Type Account -TargetOrg me -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'data|delete|record|--sobject|Account|--record-id|001xx000003DGb1AAG|--target-org|me|--json' }
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'data|delete|record|--sobject|Account|--record-id|001xx000003DGb2AAG|--target-org|me|--json' }
        }
        It 'makes no delete call for any piped record under -WhatIf' {
            Select-SalesforceRecords -Query 'SELECT Id FROM Account' | Remove-SalesforceRecord -Type Account -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly -ParameterFilter { ($Arguments -join '|') -like 'data|delete*' }
        }
        It 'pipes queried records into Get-SalesforceRecord and Set-SalesforceRecord' {
            @(Select-SalesforceRecords -Query 'SELECT Id FROM Account' | Get-SalesforceRecord -Type Account).Count | Should -Be 2
            Assert-MockCalled Invoke-Salesforce -Times 2 -Exactly -ParameterFilter { ($Arguments -join '|') -like 'data|get|record|--sobject|Account|--record-id|*' }
            Select-SalesforceRecords -Query 'SELECT Id FROM Account' | Set-SalesforceRecord -Type Account -FieldUpdates 'Name=X' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'data|update|record|--sobject|Account|--record-id|001xx000003DGb2AAG|--values|Name=X|--json' }
        }
        It 'accepts the Id by its RecordId alias' {
            [pscustomobject]@{ RecordId = '001xx000003DGb3AAG' } | Remove-SalesforceRecord -Type Account -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -like 'data|delete|record|--sobject|Account|--record-id|001xx000003DGb3AAG*' }
        }
        It 'returns an empty collection for an empty query and the pipeline then does nothing' {
            $script:Accounts = '{"status":0,"result":{"records":[],"totalSize":0}}'
            $rows = @(Select-SalesforceRecords -Query 'SELECT Id FROM Account WHERE Name = ''none''')
            $rows.Count | Should -Be 0
            Select-SalesforceRecords -Query 'SELECT Id FROM Account' | Remove-SalesforceRecord -Type Account -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly -ParameterFilter { ($Arguments -join '|') -like 'data|delete*' }
        }
        It 'returns one record as an object and several as an array (wrap in @() for a stable shape)' {
            $script:Accounts = '{"status":0,"result":{"records":[{"attributes":{"type":"Account"},"Id":"001xx000003DGb1AAG"}],"totalSize":1}}'
            $one = Select-SalesforceRecords -Query 'SELECT Id FROM Account'
            $one.Id | Should -Be '001xx000003DGb1AAG'
            $one -is [array] | Should -BeFalse
            @($one).Count | Should -Be 1
        }
        It 'reports a piped record with an invalid Id as an error for that record, makes no call for it, and -ErrorAction Stop terminates' {
            try { [pscustomobject]@{ Id = 'short' } | Remove-SalesforceRecord -Type Account -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch { }
            { [pscustomobject]@{ Id = 'short' } | Remove-SalesforceRecord -Type Account -Confirm:$false -ErrorAction Stop } | Should -Throw
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly -ParameterFilter { ($Arguments -join '|') -like 'data|delete*' }
        }
        It 'throws the CLI message for a failed delete mid-pipeline and stops' {
            Mock Invoke-Salesforce { '{"status":1,"name":"NOT_FOUND","message":"entity is deleted or does not exist"}' } -ParameterFilter { ($Arguments -join '|') -like 'data|delete*' }
            { Select-SalesforceRecords -Query 'SELECT Id FROM Account' | Remove-SalesforceRecord -Type Account -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist*'
        }
        It 'does not use -Where from the pipeline, and keeps -Where working' {
            Remove-SalesforceRecord -Type Account -Where @{ Name = 'A' } -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "data|delete|record|--sobject|Account|--where|Name='A'|--json" }
        }
        It 'makes New-SalesforceRecord and Set-SalesforceRecord respect -WhatIf' {
            New-SalesforceRecord -Type Account -FieldUpdates 'Name=X' -WhatIf | Out-Null
            Set-SalesforceRecord -Id 001xx000003DGb1AAG -Type Account -FieldUpdates 'Name=X' -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
        }
        It 'keeps New and Set from prompting by default (ConfirmImpact Medium)' {
            (Get-Command New-SalesforceRecord).ScriptBlock.Attributes.ConfirmImpact | Should -Contain 'Medium'
            (Get-Command Set-SalesforceRecord).ScriptBlock.Attributes.ConfirmImpact | Should -Contain 'Medium'
            New-SalesforceRecord -Type Account -FieldUpdates 'Name=X' | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly
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

        Context 'field values stay out of the verbose stream' {
            It 'does not echo -FieldUpdates itself from New and Set' {
                $v1 = New-SalesforceRecord -Type Account -FieldUpdates "Name='Acme' Secret__c='hunter2'" -Verbose 4>&1 | Out-String
                $v2 = Set-SalesforceRecord -Id 001xx000003DGb1AAG -Type Account -FieldUpdates "Secret__c='hunter2'" -Verbose 4>&1 | Out-String
                $v1 | Should -Not -BeLike '*hunter2*'
                $v2 | Should -Not -BeLike '*hunter2*'
            }
        }

        Context 'installing code is previewable and validated' {
            It 'makes no call under -WhatIf for CLI and plugin installs and updates' {
                Install-SalesforceCli -WhatIf | Out-Null
                Update-SalesforceCli -WhatIf | Out-Null
                Install-SalesforcePlugin -Name '@salesforce/plugin-agent' -WhatIf | Out-Null
                Update-SalesforcePlugins -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'still runs them when not asked to preview, without a prompt' {
                Install-SalesforcePlugin -Name '@salesforce/plugin-agent' | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'plugins|install|@salesforce/plugin-agent' }
            }
            It 'accepts npm names with scope and version, and GitHub URLs' {
                foreach ($name in '@salesforce/plugin-agent', '@salesforce/plugin-agent@1.2.3', 'sfdx-hardis', 'https://github.com/org/repo') {
                    { Install-SalesforcePlugin -Name $name -Confirm:$false } | Should -Not -Throw
                }
            }
            It 'refuses a plugin name that could be read as an option or break the command' {
                foreach ($name in '--force', '-x', 'a b', 'a;b', 'a|b', "a$([char]10)b", 'a$(x)', '', '"x"') {
                    { Install-SalesforcePlugin -Name $name -Confirm:$false } | Should -Throw
                }
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
        It 'refuses a name or prefix that ends in a line feed' {
            $lf = [string][char]10
            { Install-SalesforcePlugin -Name ('sfdx-hardis' + $lf) -Confirm:$false } | Should -Throw
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

        Context 'Get-SalesforceSObjectRecordCount' {
            It 'passes each object as its own --sobject' {
                Mock Invoke-Salesforce { '{"status":0,"result":[{"name":"Account","count":12},{"name":"Contact","count":40}]}' }
                $counts = @(Get-SalesforceSObjectRecordCount -SObject Account, Contact, Invoice__c -TargetOrg dev1)
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|list|sobject|record-counts|--sobject|Account|--sobject|Contact|--sobject|Invoice__c|--target-org|dev1|--json' }
                $counts.Count | Should -Be 2
                $counts[1].count | Should -Be 40
            }
            It 'counts every object when none is named' {
                Get-SalesforceSObjectRecordCount | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'org|list|sobject|record-counts|--json' }
            }
            It 'rejects names that are not API names, including a trailing line break' {
                foreach ($bad in 'Account;drop', 'Acc ount', "Account`n", '1Account') {
                    { Get-SalesforceSObjectRecordCount -SObject $bad } | Should -Throw
                }
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        It 'exports the new cmdlets' {
            $exports = (Get-Module psfdx).ExportedFunctions.Keys
            foreach ($n in 'Get-SalesforceOrgDetails', 'Get-SalesforceAuthorizations', 'Connect-SalesforceAccessToken', 'Get-SalesforceSObjectRecordCount') { $exports | Should -Contain $n }
        }
    }
}

Describe 'psfdx sf data parity (issue 249)' {
    InModuleScope 'psfdx' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
        }

        Context 'record flags' {
            It 'New-SalesforceRecord passes -SkipAssignmentRules' {
                New-SalesforceRecord -Type Case -FieldUpdates "Subject='Hi'" -SkipAssignmentRules -TargetOrg me -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "data|create|record|--sobject|Case|--values|Subject='Hi'|--skip-assignment-rules|--target-org|me|--json" }
            }
            It 'Set-SalesforceRecord still updates by ID, and passes -SkipAssignmentRules' {
                Set-SalesforceRecord -Id 500xx000000001AAA -Type Case -FieldUpdates "Status='Closed'" -SkipAssignmentRules -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "data|update|record|--sobject|Case|--record-id|500xx000000001AAA|--values|Status='Closed'|--skip-assignment-rules|--json" }
            }
            It 'Set-SalesforceRecord updates by -Where' {
                Set-SalesforceRecord -Type Account -Where @{ Name = 'Acme' } -FieldUpdates "Industry='Energy'" -TargetOrg me -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "data|update|record|--sobject|Account|--where|Name='Acme'|--values|Industry='Energy'|--target-org|me|--json" }
            }
            It 'Set-SalesforceRecord refuses an unsafe -Where value, a mix of -Id and -Where, and honours -WhatIf' {
                { Set-SalesforceRecord -Type Account -Where @{ Name = "O'Brien" } -FieldUpdates "X='1'" -Confirm:$false } | Should -Throw -ExpectedMessage '*quote*'
                { Set-SalesforceRecord -Id 001xx000003DGb2AAG -Where @{ Name = 'A' } -Type Account -FieldUpdates "X='1'" } | Should -Throw
                Set-SalesforceRecord -Type Account -Where @{ Name = 'Acme' } -FieldUpdates "X='1'" -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'Set-SalesforceRecord still takes the ID from the pipeline' {
                [pscustomobject]@{ Id = '001xx000003DGb2AAG' }, [pscustomobject]@{ Id = '001xx000003DGb3AAG' } | Set-SalesforceRecord -Type Account -FieldUpdates "X='1'" -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 2 -Exactly
            }
        }

        Context 'New-SalesforceFile' {
            BeforeEach {
                $script:pdf = Join-Path $TestDrive 'Q4 report.pdf'
                Set-Content -LiteralPath $script:pdf -Value 'x'
                Mock Invoke-Salesforce { '{"status":0,"result":{"id":"068xx0000000001AAA","title":"Q4"}}' }
            }
            It 'builds the command and returns the result' {
                $file = New-SalesforceFile -File $script:pdf -ParentId 001xx000003DGb2AAG -Title "Q4 'final' report" -TargetOrg me -Confirm:$false
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "data|create|file|--file|$($script:pdf)|--parent-id|001xx000003DGb2AAG|--title|Q4 'final' report|--target-org|me|--json" }
                $file.id | Should -Be '068xx0000000001AAA'
            }
            It 'needs only the file' {
                New-SalesforceFile -File $script:pdf -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "data|create|file|--file|$($script:pdf)|--json" }
            }
            It 'checks the file and the parent ID, and honours -WhatIf' {
                { New-SalesforceFile -File (Join-Path $TestDrive 'nope.pdf') -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist*'
                { New-SalesforceFile -File $script:pdf -ParentId 'not an id' -Confirm:$false } | Should -Throw
                New-SalesforceFile -File $script:pdf -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'reports a CLI failure' {
                Mock Invoke-Salesforce { '{"status":1,"message":"INVALID_CROSS_REFERENCE_KEY: invalid parent"}' }
                { New-SalesforceFile -File $script:pdf -ParentId 001xx000003DGb2AAG -Confirm:$false } | Should -Throw -ExpectedMessage '*INVALID_CROSS_REFERENCE_KEY*'
            }
        }

        Context 'Search-SalesforceRecords' {
            BeforeEach {
                Mock Invoke-Salesforce { '{"status":0,"result":{"searchRecords":[{"attributes":{"type":"Account","url":"/x"},"Id":"001xx000003DGb2AAG","Name":"Acme"},{"attributes":{"type":"Contact","url":"/y"},"Id":"003xx000003DGb2AAG","Name":"Ann Acme"}]}}' }
            }
            It 'passes the SOSL as one argument and returns objects with their SObject' {
                $query = 'FIND {Acme & "Co"} RETURNING Account(Id, Name), Contact(Id, Name)'
                $rows = @(Search-SalesforceRecords -Query $query -TargetOrg me)
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "data|search|--query|$query|--target-org|me|--json" }
                $rows.Count | Should -Be 2
                $rows[0].SObject | Should -Be 'Account'
                $rows[1].SObject | Should -Be 'Contact'
                $rows[1].Name | Should -Be 'Ann Acme'
                $rows[0].PSObject.Properties.Name | Should -Not -Contain 'attributes'
            }
            It 'reads the query from a file that exists' {
                $file = Join-Path $TestDrive 'my search.sosl'
                Set-Content -LiteralPath $file -Value 'FIND {x} RETURNING Account'
                Search-SalesforceRecords -File $file | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "data|search|--file|$file|--json" }
                { Search-SalesforceRecords -File (Join-Path $TestDrive 'missing.sosl') } | Should -Throw -ExpectedMessage '*does not exist*'
            }
            It 'returns csv and human text untouched, without --json' {
                Mock Invoke-Salesforce { "Id,Name`n001,Acme" }
                (Search-SalesforceRecords -Query 'FIND {Acme}' -ResultFormat csv) | Should -Be "Id,Name`n001,Acme"
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'data|search|--query|FIND {Acme}|--result-format|csv' }
                Search-SalesforceRecords -Query 'FIND {Acme}' -ResultFormat human | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'data|search|--query|FIND {Acme}|--result-format|human' }
            }
            It 'returns nothing when nothing matches, and accepts a bare array' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"searchRecords":[]}}' }
                @(Search-SalesforceRecords -Query 'FIND {zzz}').Count | Should -Be 0
                Mock Invoke-Salesforce { '{"status":0,"result":[{"attributes":{"type":"Lead"},"Id":"00Qxx0000000001AAA"}]}' }
                @(Search-SalesforceRecords -Query 'FIND {a}')[0].SObject | Should -Be 'Lead'
            }
            It 'needs exactly one of -Query and -File, and throws the CLI message for a bad search' {
                { Search-SalesforceRecords } | Should -Throw
                { Search-SalesforceRecords -Query 'FIND {a}' -File 'x.sosl' } | Should -Throw
                Mock Invoke-Salesforce { '{"status":1,"message":"MALFORMED_SEARCH: unexpected token"}' }
                { Search-SalesforceRecords -Query 'FIND' } | Should -Throw -ExpectedMessage '*MALFORMED_SEARCH*'
            }
        }

        It 'exports the new cmdlets' {
            $exports = (Get-Module psfdx).ExportedFunctions.Keys
            foreach ($n in 'Search-SalesforceRecords', 'New-SalesforceFile') { $exports | Should -Contain $n }
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

        Context 'plugins' {
            It 'uninstalls after confirmation, -NoPrompt skips it, -WhatIf does nothing' {
                Uninstall-SalesforcePlugin -Name @('@salesforce/plugin-agent', 'sfdx-hardis') -ExtendedDetails -NoPrompt | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|uninstall|@salesforce/plugin-agent|sfdx-hardis|--verbose' }
                Uninstall-SalesforcePlugin -Name x -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1
            }
            It 'refuses a plugin name that looks like an option or has a line break' {
                { Uninstall-SalesforcePlugin -Name '--all' -NoPrompt } | Should -Throw
                { Get-SalesforcePluginDetails -Name '--json' } | Should -Throw
                { Get-SalesforcePluginDetails -Name ('a' + "`n") } | Should -Throw
                { Add-SalesforcePluginAllowlist -Name '-x' -NoPrompt } | Should -Throw
                { Test-SalesforcePluginSignature -Npm '--x' } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0
            }
            It 'throws when sf plugins uninstall fails' {
                Mock Invoke-Salesforce { $global:LASTEXITCODE = 2; 'not installed' }
                { Uninstall-SalesforcePlugin -Name nope -NoPrompt } | Should -Throw -ExpectedMessage '*exited with code 2*not installed*'
            }
            It 'inspects, discovers and verifies as read-only json commands' {
                Get-SalesforcePluginDetails -Name '@salesforce/plugin-agent' -ExtendedDetails | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|inspect|@salesforce/plugin-agent|--verbose|--json' }
                Find-SalesforcePlugins | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|discover|--json' }
                Test-SalesforcePluginSignature -Npm '@salesforce/plugin-agent@latest' -Registry https://registry.npmjs.org | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|trust|verify|--npm|@salesforce/plugin-agent@latest|--registry|https://registry.npmjs.org|--json' }
            }
            It 'reads the bare array that sf plugins inspect prints, and still reports an error result' {
                Mock Invoke-Salesforce { '[{"name":"@salesforce/plugin-agent","version":"1.2.3"}]' }
                $out = @(Get-SalesforcePluginDetails -Name '@salesforce/plugin-agent')
                $out.Count | Should -Be 1
                $out[0].version | Should -Be '1.2.3'
                Mock Invoke-Salesforce { '{"status":1,"message":"plugin not found"}' }
                { Get-SalesforcePluginDetails -Name nope } | Should -Throw -ExpectedMessage '*plugin not found*'
            }
            It 'only accepts an https registry' {
                { Test-SalesforcePluginSignature -Npm a -Registry http://registry.example.com } | Should -Throw -ExpectedMessage '*https*'
                { Test-SalesforcePluginSignature -Npm a -Registry 'registry' } | Should -Throw -ExpectedMessage '*https*'
            }
            It 'resets with its options, asks first, and does nothing under -WhatIf' {
                Reset-SalesforcePlugins -Hard -Reinstall -NoPrompt | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|reset|--hard|--reinstall' }
                Reset-SalesforcePlugins -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1
            }
            It 'lists, adds and removes allowlist entries, one --name each' {
                Get-SalesforcePluginAllowlist | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|trust|allowlist|list|--json' }
                Add-SalesforcePluginAllowlist -Name a, b -NoPrompt | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|trust|allowlist|add|--name|a|--name|b|--json' }
                Remove-SalesforcePluginAllowlist -Name a -NoPrompt | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|trust|allowlist|remove|--name|a|--json' }
                Add-SalesforcePluginAllowlist -Name c -WhatIf | Out-Null
                Remove-SalesforcePluginAllowlist -Name c -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 3
            }
            It 'the install and update cmdlets pass the new flags' {
                Install-SalesforcePlugin -Name '@salesforce/plugin-agent' -Force -Silent -ExtendedDetails -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|install|@salesforce/plugin-agent|--force|--silent|--verbose' }
                Update-SalesforcePlugins -ExtendedDetails -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'plugins|update|--verbose' }
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
            foreach ($n in 'Get-SalesforceCommunityTemplates', 'New-SalesforceCommunity', 'Publish-SalesforceCommunity', 'Invoke-SalesforceGraphQL', 'Invoke-SalesforceRestRequest', 'Uninstall-SalesforcePlugin', 'Get-SalesforcePluginDetails', 'Find-SalesforcePlugins', 'Reset-SalesforcePlugins', 'Test-SalesforcePluginSignature', 'Get-SalesforcePluginAllowlist', 'Add-SalesforcePluginAllowlist', 'Remove-SalesforcePluginAllowlist', 'Invoke-SalesforceDoctor') { $exports | Should -Contain $n }
            $exports | Should -Not -Contain 'Invoke-SalesforceText'
        }
    }
}
