<#
Pester unit tests for the psfdx-bulk module

Run with:

pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path . -CI"
#>

# Ensure clean slate and load module locally
Get-Module -Name 'psfdx-bulk' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-bulk.psd1'
Import-Module $moduleManifest -Force | Out-Null

Describe 'Bulk API 2.0 commands' {
    InModuleScope 'psfdx-bulk' {
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
                { Resume-SalesforceBulkJob -Operation Purge -JobId $script:JobId } | Should -Throw
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
                $exports = (Import-PowerShellDataFile -Path (Join-Path (Get-Module -Name psfdx-bulk).ModuleBase 'psfdx-bulk.psd1')).FunctionsToExport
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

Describe 'psfdx-bulk sf data parity (issue 249)' {
    InModuleScope 'psfdx-bulk' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
        }

        Context 'Remove-SalesforceBulkData' {
            BeforeEach {
                $script:csv = Join-Path $TestDrive 'old accounts.csv'
                Set-Content -LiteralPath $script:csv -Value "Id`n001xx000003DGb2AAG"
                Mock Invoke-Salesforce { '{"status":0,"result":{"jobId":"750xx0000000001AAA","state":"JobComplete","processedRecords":1,"successfulRecords":1,"failedRecords":0}}' }
            }
            It 'builds the command and returns the job object' {
                $job = Remove-SalesforceBulkData -File $script:csv -Object Account -HardDelete -LineEnding LF -WaitMinutes 10 -TargetOrg me -Confirm:$false
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "data|delete|bulk|--file|$($script:csv)|--sobject|Account|--hard-delete|--line-ending|LF|--wait|10|--target-org|me|--json" }
                $job.Operation | Should -Be 'Delete'
                $job.Object | Should -Be 'Account'
                $job.SuccessfulRecords | Should -Be 1
            }
            It 'leaves --hard-delete out by default, so records go to the Recycle Bin' {
                Remove-SalesforceBulkData -File $script:csv -Object Account -Confirm:$false | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq "data|delete|bulk|--file|$($script:csv)|--sobject|Account|--json" }
            }
            It 'asks first: -WhatIf makes no CLI call, and the cmdlet is high impact' {
                Remove-SalesforceBulkData -File $script:csv -Object Account -HardDelete -WhatIf | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
                (Get-Command Remove-SalesforceBulkData).ScriptBlock.Attributes.Where({ $_ -is [System.Management.Automation.CmdletBindingAttribute] })[0].ConfirmImpact | Should -Be 'High'
            }
            It 'checks the file and the object name before running sf' {
                { Remove-SalesforceBulkData -File (Join-Path $TestDrive 'missing.csv') -Object Account -Confirm:$false } | Should -Throw -ExpectedMessage '*does not exist*'
                { Remove-SalesforceBulkData -File $script:csv -Object 'Account; drop' -Confirm:$false } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'throws PsfdxBulkJobFailed with the job ID when rows fail' {
                Mock Invoke-Salesforce { '{"status":1,"message":"Job finished being processed but 1 records failed to process. 750xx0000000001AAA","data":{"jobId":"750xx0000000001AAA","state":"JobComplete"}}' }
                $err = $null
                try { Remove-SalesforceBulkData -File $script:csv -Object Account -Confirm:$false } catch { $err = $_ }
                $err.FullyQualifiedErrorId | Should -Be 'PsfdxBulkJobFailed'
                $err.TargetObject.JobId | Should -Be '750xx0000000001AAA'
            }
        }

        Context 'Resume-SalesforceBulkJob for delete and -UseMostRecent' {
            It 'resumes a delete job by ID, with -TargetOrg and -WaitMinutes' {
                Resume-SalesforceBulkJob -Operation Delete -JobId 750xx0000000001AAA -WaitMinutes 5 -TargetOrg me | Out-Null
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'data|delete|resume|--job-id|750xx0000000001AAA|--wait|5|--target-org|me|--json' }
            }
            It 'resumes the most recent job of any operation' {
                foreach ($op in 'Export', 'Import', 'Update', 'Upsert', 'Delete') {
                    Resume-SalesforceBulkJob -Operation $op -UseMostRecent | Out-Null
                    $expected = 'data|' + $op.ToLowerInvariant() + '|resume|--use-most-recent|--json'
                    Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
                }
            }
            It 'does not accept -JobId together with -UseMostRecent' {
                { Resume-SalesforceBulkJob -Operation Delete -JobId 750xx0000000001AAA -UseMostRecent } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
        }

        Context 'Get-SalesforceBulkJobStatus' {
            It 'reads a job, and one batch of it' {
                Mock Invoke-Salesforce { '{"status":0,"result":{"id":"750xx0000000001AAA","state":"Closed","numberBatchesCompleted":2}}' }
                $job = Get-SalesforceBulkJobStatus -JobId 750xx0000000001AAA -BatchId 751xx0000000001AAA -TargetOrg me
                Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'data|resume|--job-id|750xx0000000001AAA|--batch-id|751xx0000000001AAA|--target-org|me|--json' }
                $job.state | Should -Be 'Closed'
            }
            It 'rejects malformed IDs, including a trailing line break, before running sf' {
                { Get-SalesforceBulkJobStatus -JobId "750xx0000000001AAA`n" } | Should -Throw
                { Get-SalesforceBulkJobStatus -JobId 'abc; calc' } | Should -Throw
                { Get-SalesforceBulkJobStatus -JobId 750xx0000000001AAA -BatchId 'bad id' } | Should -Throw
                Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            }
            It 'reports a CLI failure' {
                Mock Invoke-Salesforce { '{"status":1,"message":"Unable to find job 750xx0000000009AAA."}' }
                { Get-SalesforceBulkJobStatus -JobId 750xx0000000009AAA } | Should -Throw -ExpectedMessage '*Unable to find job*'
            }
        }
    }
}

Describe 'psfdx-bulk ID parameters reject a trailing line break (issue 112)' {
    InModuleScope 'psfdx-bulk' {
        BeforeEach { Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' } }
        It 'refuses a Bulk job ID that ends in a line feed, before any call' {
            $lf = [string][char]10
            { Get-SalesforceBulkResult -JobId ('750xx000000001AAAA' + $lf) } | Should -Throw
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
        }
    }
}

Describe 'psfdx-bulk module ownership (issue 274)' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        $script:Exports = @((Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'psfdx-bulk.psd1')).FunctionsToExport)
        $script:CoreExports = @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root 'psfdx') 'psfdx.psd1')).FunctionsToExport)
    }
    It 'exports the eight Bulk API 2.0 cmdlets' {
        @($script:Exports | Sort-Object) | Should -Be @('Export-SalesforceBulkData', 'Get-SalesforceBulkJobStatus', 'Get-SalesforceBulkResult', 'Import-SalesforceBulkData', 'Remove-SalesforceBulkData', 'Resume-SalesforceBulkJob', 'Update-SalesforceBulkData', 'Upsert-SalesforceBulkData')
    }
    It 'exports exactly those from the loaded module, and none of its helpers' {
        $loaded = (Get-Module psfdx-bulk).ExportedFunctions.Keys
        @($loaded | Sort-Object) | Should -Be @($script:Exports | Sort-Object)
        foreach ($n in 'Get-SalesforceBulkTargetLabel', 'ConvertFrom-SalesforceBulkOutput', 'ConvertTo-SalesforceBulkJobObject') { $loaded | Should -Not -Contain $n }
    }
    It 'is no longer exported by the core module, so no command is exported twice' {
        foreach ($n in $script:Exports) { $script:CoreExports | Should -Not -Contain $n -Because "$n moved to psfdx-bulk" }
    }
    It 'every cmdlet is owned by psfdx-bulk' {
        foreach ($n in $script:Exports) { (Get-Command -Name $n -Module psfdx-bulk).ModuleName | Should -Be 'psfdx-bulk' -Because $n }
    }
}