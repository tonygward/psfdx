<#
Pester unit tests for the psfdx-devops module

Run with:

pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path . -CI"
#>

# Ensure clean slate and load module locally
Get-Module -Name 'psfdx-devops' -All | ForEach-Object {
    try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { }
}

$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'psfdx-devops.psd1'
Import-Module $moduleManifest -Force | Out-Null

Describe 'sf project deploy pipeline commands (beta, issue 244)' {
    InModuleScope 'psfdx-devops' {
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"id":"3A0000000000001AAA"}}' }
        }
        It 'Start-SalesforcePipelineDeploy passes every flag and honours -WhatIf' {
            Start-SalesforcePipelineDeploy -DevOpsCenterUsername doc -DevOpsCenterProjectName 'Sales App' -BranchName feature/x -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            Start-SalesforcePipelineDeploy -DevOpsCenterUsername doc -DevOpsCenterProjectName 'Sales App' -BranchName feature/x -BundleVersionName v1 -DeployAll -TestLevel SpecificTests -Tests A, B -Wait 20 -ConciseResults -Confirm:$false | Out-Null
            $expected = 'project|deploy|pipeline|start|--devops-center-username|doc|--devops-center-project-name|Sales App|--branch-name|feature/x|--bundle-version-name|v1|--deploy-all|--test-level|RunSpecifiedTests|--tests|A|--tests|B|--wait|20|--concise|--json'
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq $expected }
        }
        It 'Start-SalesforcePipelineDeploy rejects -Async with -Wait, -Tests without a level, and an unsupported level' {
            { Start-SalesforcePipelineDeploy -DevOpsCenterUsername d -DevOpsCenterProjectName p -BranchName b -Async -Wait 1 -Confirm:$false } | Should -Throw -ExpectedMessage 'Specify only one of -Wait or -Async.'
            { Start-SalesforcePipelineDeploy -DevOpsCenterUsername d -DevOpsCenterProjectName p -BranchName b -Tests T -Confirm:$false } | Should -Throw -ExpectedMessage '-Tests needs -TestLevel SpecificTests.'
            { Start-SalesforcePipelineDeploy -DevOpsCenterUsername d -DevOpsCenterProjectName p -BranchName b -TestLevel RelevantTests -Confirm:$false } | Should -Throw
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
        }
        It 'Test-SalesforcePipelineDeploy runs the validate command and needs no confirmation' {
            Test-SalesforcePipelineDeploy -DevOpsCenterUsername doc -DevOpsCenterProjectName p -BranchName main -TestLevel TestsInOrg -Async -DetailedResults | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|pipeline|validate|--devops-center-username|doc|--devops-center-project-name|p|--branch-name|main|--test-level|RunLocalTests|--async|--verbose|--json' }
        }
        It 'Start-SalesforcePipelineQuickDeploy needs a job and asks first' {
            { Start-SalesforcePipelineQuickDeploy -DevOpsCenterUsername doc -Confirm:$false } | Should -Throw -ExpectedMessage 'Specify -JobId or -UseMostRecent.'
            { Start-SalesforcePipelineQuickDeploy -DevOpsCenterUsername doc -JobId '3A00000000000' -Confirm:$false } | Should -Throw -ExpectedMessage '*not a valid pipeline deploy job ID*'
            Start-SalesforcePipelineQuickDeploy -DevOpsCenterUsername doc -UseMostRecent -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
            Start-SalesforcePipelineQuickDeploy -DevOpsCenterUsername doc -JobId 3A0000000000001AAA -Wait 5 -ConciseResults -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|pipeline|quick|--devops-center-username|doc|--job-id|3A0000000000001AAA|--wait|5|--concise|--json' }
        }
        It 'Get-SalesforcePipelineDeployStatus and Resume-SalesforcePipelineDeploy build their commands' {
            Get-SalesforcePipelineDeployStatus -DevOpsCenterUsername doc -UseMostRecent | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|pipeline|report|--devops-center-username|doc|--use-most-recent|--json' }
            Resume-SalesforcePipelineDeploy -DevOpsCenterUsername doc -JobId 3A0000000000001AAA -Wait 3 -DetailedResults | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'project|deploy|pipeline|resume|--devops-center-username|doc|--job-id|3A0000000000001AAA|--wait|3|--verbose|--json' }
            { Resume-SalesforcePipelineDeploy -DevOpsCenterUsername doc -JobId 3A0000000000001AAA -UseMostRecent } | Should -Throw -ExpectedMessage 'Specify only one of -JobId or -UseMostRecent.'
        }
    }
}

Describe 'psfdx-devops DevOps Center commands (issue 256)' {
    InModuleScope 'psfdx-devops' {
        $cases = @(
            @{ N = 'Get-SalesforceDevOpsProject'; Level = 'Read'; Call = { Get-SalesforceDevOpsProject -TargetOrg o }; Argv = 'devops|project|list|--target-org|o|--json' }
            @{ N = 'New-SalesforceDevOpsProject'; Level = 'Medium'; Call = { New-SalesforceDevOpsProject -Name 'Sales App' -Description 'd e' -TargetOrg o -Confirm:$false }; Argv = 'devops|project|create|--name|Sales App|--description|d e|--target-org|o|--json'; WhatIf = { New-SalesforceDevOpsProject -Name n -WhatIf } }
            @{ N = 'Update-SalesforceDevOpsProject'; Level = 'Medium'; Call = { Update-SalesforceDevOpsProject -ProjectId '0Hn000000000001' -Name n -Description d -IsActive -TargetOrg o }; Argv = "devops|project|update|--project-id|0Hn000000000001|--name|n|--description|d|--is-active|--target-org|o|--json"; WhatIf = { Update-SalesforceDevOpsProject -ProjectId '0Hn000000000001' -Name n -WhatIf } }
            @{ N = 'Get-SalesforceDevOpsWorkItem'; Level = 'Read'; Call = { Get-SalesforceDevOpsWorkItem -ProjectId '0Hn000000000001' -TargetOrg o }; Argv = "devops|work-item|list|--project-id|0Hn000000000001|--target-org|o|--json" }
            @{ N = 'New-SalesforceDevOpsWorkItem'; Level = 'Medium'; Call = { New-SalesforceDevOpsWorkItem -ProjectId '0Hn000000000001' -Subject 'Add flow' -Description d -TargetOrg o }; Argv = "devops|work-item|create|--project-id|0Hn000000000001|--subject|Add flow|--description|d|--target-org|o|--json"; WhatIf = { New-SalesforceDevOpsWorkItem -ProjectId '0Hn000000000001' -Subject s -WhatIf } }
            @{ N = 'Update-SalesforceDevOpsWorkItem'; Level = 'Medium'; Call = { Update-SalesforceDevOpsWorkItem -WorkItemName WI-000001 -Subject s -Description d -Status 'ready to promote' -TargetOrg o }; Argv = 'devops|work-item|update|--work-item-name|WI-000001|--subject|s|--description|d|--status|Ready to Promote|--target-org|o|--json'; WhatIf = { Update-SalesforceDevOpsWorkItem -WorkItemId '1fk000000000001' -Subject s -WhatIf } }
            @{ N = 'Initialize-SalesforceDevOpsWorkItem'; Level = 'Medium'; Call = { Initialize-SalesforceDevOpsWorkItem -WorkItemId '1fk000000000001' -TargetStageId '1QV000000000001' -TargetOrg o }; Argv = "devops|work-item|prepare|--work-item-id|1fk000000000001|--target-stage-id|1QV000000000001|--target-org|o|--json"; WhatIf = { Initialize-SalesforceDevOpsWorkItem -WorkItemId '1fk000000000001' -TargetStageId '1QV000000000001' -WhatIf } }
            @{ N = 'Join-SalesforceDevOpsWorkItem'; Level = 'Medium'; Call = { Join-SalesforceDevOpsWorkItem -ParentWorkItemId '1fk000000000001' -ChildWorkItemId '1fk000000000002', '1QV000000000002' -TargetStageId '1QV000000000001' -TargetOrg o }; Argv = "devops|work-item|combine|--parent-work-item-id|1fk000000000001|--target-stage-id|1QV000000000001|--child-work-item-id|1fk000000000002|--child-work-item-id|1QV000000000002|--target-org|o|--json"; WhatIf = { Join-SalesforceDevOpsWorkItem -ParentWorkItemId '1fk000000000001' -ChildWorkItemId '1fk000000000002' -TargetStageId '1QV000000000001' -WhatIf } }
            @{ N = 'New-SalesforceDevOpsReview'; Level = 'Medium'; Call = { New-SalesforceDevOpsReview -WorkItemId '1fk000000000001' -TargetOrg o }; Argv = "devops|review|create|--work-item-id|1fk000000000001|--target-org|o|--json"; WhatIf = { New-SalesforceDevOpsReview -WorkItemName WI-000001 -WhatIf } }
            @{ N = 'Get-SalesforceDevOpsPipeline'; Level = 'Read'; Call = { Get-SalesforceDevOpsPipeline -TargetOrg o }; Argv = 'devops|pipeline|list|--target-org|o|--json' }
            @{ N = 'Get-SalesforceDevOpsPipelineDetails'; Level = 'Read'; Call = { Get-SalesforceDevOpsPipelineDetails -PipelineId '0XB000000000001' -TargetOrg o }; Argv = "devops|pipeline|get|--pipeline-id|0XB000000000001|--target-org|o|--json" }
            @{ N = 'New-SalesforceDevOpsPipeline'; Level = 'Medium'; Call = { New-SalesforceDevOpsPipeline -Name 'Release Pipeline' -Repo my-repo -Stage Dev, QA -ProjectId '0Hn000000000001' -CreateRepo -RepoType GitHub -RepoOwner acme -TargetOrg o }; Argv = "devops|pipeline|create|--name|Release Pipeline|--repo|my-repo|--stage|Dev|--stage|QA|--project-id|0Hn000000000001|--create-repo|--repo-type|github|--repo-owner|acme|--target-org|o|--json"; WhatIf = { New-SalesforceDevOpsPipeline -Name n -Repo https://github.com/a/b -WhatIf } }
            @{ N = 'Update-SalesforceDevOpsPipeline'; Level = 'Medium'; Call = { Update-SalesforceDevOpsPipeline -PipelineId '0XB000000000001' -Name n -Deactivate -TargetOrg o }; Argv = "devops|pipeline|update|--pipeline-id|0XB000000000001|--name|n|--deactivate|--target-org|o|--json"; WhatIf = { Update-SalesforceDevOpsPipeline -PipelineId '0XB000000000001' -Name n -WhatIf } }
            @{ N = 'Add-SalesforceDevOpsPipelineProject'; Level = 'Medium'; Call = { Add-SalesforceDevOpsPipelineProject -PipelineId '0XB000000000001' -ProjectId '0Hn000000000001' -TargetOrg o }; Argv = "devops|pipeline|project|add|--pipeline-id|0XB000000000001|--project-id|0Hn000000000001|--target-org|o|--json"; WhatIf = { Add-SalesforceDevOpsPipelineProject -PipelineId '0XB000000000001' -ProjectId '0Hn000000000001' -WhatIf } }
            @{ N = 'Remove-SalesforceDevOpsPipelineProject'; Level = 'High'; Call = { Remove-SalesforceDevOpsPipelineProject -PipelineId '0XB000000000001' -ProjectId '0Hn000000000001' -TargetOrg o -Confirm:$false }; Argv = "devops|pipeline|project|delete|--pipeline-id|0XB000000000001|--project-id|0Hn000000000001|--target-org|o|--json"; WhatIf = { Remove-SalesforceDevOpsPipelineProject -PipelineId '0XB000000000001' -ProjectId '0Hn000000000001' -WhatIf } }
            @{ N = 'Add-SalesforceDevOpsPipelineStage'; Level = 'Medium'; Call = { Add-SalesforceDevOpsPipelineStage -PipelineId '0XB000000000001' -Name QA -NextStageId '1QV000000000002' -TargetOrg o }; Argv = "devops|pipeline|stage|add|--pipeline-id|0XB000000000001|--name|QA|--next-stage-id|1QV000000000002|--target-org|o|--json"; WhatIf = { Add-SalesforceDevOpsPipelineStage -PipelineId '0XB000000000001' -Name QA -NextStageId '1QV000000000002' -WhatIf } }
            @{ N = 'Update-SalesforceDevOpsPipelineStage'; Level = 'Medium'; Call = { Update-SalesforceDevOpsPipelineStage -StageId '1QV000000000001' -Name Staging -TargetOrg o }; Argv = "devops|pipeline|stage|update|--stage-id|1QV000000000001|--name|Staging|--target-org|o|--json"; WhatIf = { Update-SalesforceDevOpsPipelineStage -StageId '1QV000000000001' -Name x -WhatIf } }
            @{ N = 'Remove-SalesforceDevOpsPipelineStage'; Level = 'High'; Call = { Remove-SalesforceDevOpsPipelineStage -PipelineId '0XB000000000001' -StageId '1QV000000000001' -TargetOrg o -Confirm:$false }; Argv = "devops|pipeline|stage|delete|--pipeline-id|0XB000000000001|--stage-id|1QV000000000001|--target-org|o|--json"; WhatIf = { Remove-SalesforceDevOpsPipelineStage -PipelineId '0XB000000000001' -StageId '1QV000000000001' -WhatIf } }
            @{ N = 'Add-SalesforceDevOpsStageBranch'; Level = 'Medium'; Call = { Add-SalesforceDevOpsStageBranch -PipelineId '0XB000000000001' -StageId '1QV000000000001' -BranchName uat -CreateVcsBranch -Force -TargetOrg o }; Argv = "devops|stage|branch|add|--pipeline-id|0XB000000000001|--stage-id|1QV000000000001|--branch-name|uat|--create-vcs-branch|--force|--target-org|o|--json"; WhatIf = { Add-SalesforceDevOpsStageBranch -PipelineId '0XB000000000001' -StageId '1QV000000000001' -BranchName uat -WhatIf } }
            @{ N = 'Remove-SalesforceDevOpsStageBranch'; Level = 'High'; Call = { Remove-SalesforceDevOpsStageBranch -PipelineId '0XB000000000001' -StageId '1QV000000000001' -TargetOrg o -Confirm:$false }; Argv = "devops|stage|branch|delete|--pipeline-id|0XB000000000001|--stage-id|1QV000000000001|--target-org|o|--json"; WhatIf = { Remove-SalesforceDevOpsStageBranch -PipelineId '0XB000000000001' -StageId '1QV000000000001' -WhatIf } }
            @{ N = 'Add-SalesforceDevOpsStageEnvironment'; Level = 'Medium'; Call = { Add-SalesforceDevOpsStageEnvironment -PipelineId '0XB000000000001' -StageId '1QV000000000001' -EnvironmentName uat -OrgType sandbox -Force -TargetOrg o }; Argv = "devops|stage|environment|add|--pipeline-id|0XB000000000001|--stage-id|1QV000000000001|--environment-name|uat|--org-type|Sandbox|--force|--target-org|o|--json"; WhatIf = { Add-SalesforceDevOpsStageEnvironment -PipelineId '0XB000000000001' -StageId '1QV000000000001' -EnvironmentName uat -OrgType Sandbox -WhatIf } }
            @{ N = 'Remove-SalesforceDevOpsStageEnvironment'; Level = 'High'; Call = { Remove-SalesforceDevOpsStageEnvironment -PipelineId '0XB000000000001' -EnvironmentId 0Xx000000000001 -TargetOrg o -Confirm:$false }; Argv = "devops|stage|environment|delete|--pipeline-id|0XB000000000001|--environment-id|0Xx000000000001|--target-org|o|--json"; WhatIf = { Remove-SalesforceDevOpsStageEnvironment -PipelineId '0XB000000000001' -EnvironmentId 0Xx000000000001 -WhatIf } }
            @{ N = 'Start-SalesforceDevOpsPromotion'; Level = 'High'; Call = { Start-SalesforceDevOpsPromotion -TargetStageId '1QV000000000002' -WorkItemId '1fk000000000001', '1fk000000000002' -DeployAll -Force -SkipValidation -TestLevel runspecifiedtests -Tests A, B -TargetOrg o -Confirm:$false }; Argv = "devops|promote|--target-stage-id|1QV000000000002|--work-item-id|1fk000000000001|--work-item-id|1fk000000000002|--deploy-all|--force|--skip-validation|--test-level|RunSpecifiedTests|--tests|A|--tests|B|--target-org|o|--json"; WhatIf = { Start-SalesforceDevOpsPromotion -TargetStageId '1QV000000000002' -StageId '1QV000000000001' -WhatIf } }
            @{ N = 'Complete-SalesforceDevOpsPromotion'; Level = 'High'; Call = { Complete-SalesforceDevOpsPromotion -TargetStageId '1QV000000000002' -WorkItemId '1fk000000000001' -DeployAll -TestLevel RunLocalTests -TargetOrg o -Confirm:$false }; Argv = "devops|promotion|complete|--target-stage-id|1QV000000000002|--work-item-id|1fk000000000001|--deploy-all|--test-level|RunLocalTests|--target-org|o|--json"; WhatIf = { Complete-SalesforceDevOpsPromotion -TargetStageId '1QV000000000002' -WhatIf } }
            @{ N = 'Test-SalesforceDevOpsPromotion'; Level = 'Read'; Call = { Test-SalesforceDevOpsPromotion -TargetStageId '1QV000000000002' -WorkItemId '1fk000000000001', '1fk000000000002' -TargetOrg o }; Argv = "devops|promotion|validate|--target-stage-id|1QV000000000002|--work-item-id|1fk000000000001|--work-item-id|1fk000000000002|--target-org|o|--json" }
            @{ N = 'Get-SalesforceDevOpsRequestStatus'; Level = 'Read'; Call = { Get-SalesforceDevOpsRequestStatus -RequestToken abc123-DEF -TargetOrg o }; Argv = 'devops|request|status|--request-token|abc123-DEF|--target-org|o|--json' }
        )
        BeforeAll {
            $script:p = '0Hn000000000001'; $script:pl = '0XB000000000001'; $script:s1 = '1QV000000000001'; $script:s2 = '1QV000000000002'
            $script:w1 = '1fk000000000001'; $script:w2 = '1fk000000000002'
            # cmdlet, how to call it with every option, the exact sf arguments, and whether it changes anything (and how hard it asks)

        }
        BeforeEach {
            Mock Invoke-Salesforce { '{"status":0,"result":{"ok":true}}' }
        }

        It 'has one exported cmdlet for each of the 26 sf devops commands' -TestCases @(@{ Names = @($cases | ForEach-Object { $_.N }) }) {
            param($Names)
            $Names.Count | Should -Be 26
            $exports = (Get-Module psfdx-devops).ExportedFunctions.Keys
            foreach ($n in $Names) { $exports | Should -Contain $n }
        }
        It 'passes the exact sf arguments (<N>)' -TestCases $cases {
            param($N, $Level, $Call, $Argv, $WhatIf)
            $out = & $Call
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq $Argv }
            $out.ok | Should -BeTrue
        }
        It 'does nothing under -WhatIf (<N>)' -TestCases @($cases | Where-Object { $_.Level -ne 'Read' }) {
            param($N, $Level, $Call, $Argv, $WhatIf)
            & $WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
        It 'asks at the right strength (<N>)' -TestCases $cases {
            param($N, $Level, $Call, $Argv, $WhatIf)
            $binding = (Get-Command $N).ScriptBlock.Attributes.Where({ $_ -is [System.Management.Automation.CmdletBindingAttribute] })[0]
            if ($Level -eq 'Read') { $binding.SupportsShouldProcess | Should -BeFalse }
            else { $binding.SupportsShouldProcess | Should -BeTrue; "$($binding.ConfirmImpact)" | Should -Be $Level }
        }
        It 'ids are checked, including a trailing line feed' {
            { Get-SalesforceDevOpsWorkItem -ProjectId 'abc' } | Should -Throw
            { Get-SalesforceDevOpsWorkItem -ProjectId ($script:p + "`n") } | Should -Throw
            { Get-SalesforceDevOpsPipelineDetails -PipelineId '--json' } | Should -Throw
            { Get-SalesforceDevOpsRequestStatus -RequestToken '-x' } | Should -Throw
            { Update-SalesforceDevOpsWorkItem -WorkItemName 'WI 1' -Subject s } | Should -Throw
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
        It 'the work item and review cmdlets need exactly one of the id and the name' {
            { Update-SalesforceDevOpsWorkItem -Subject s } | Should -Throw -ExpectedMessage '*-WorkItemId or -WorkItemName*'
            { Update-SalesforceDevOpsWorkItem -WorkItemId $script:w1 -WorkItemName WI-1 -Subject s } | Should -Throw -ExpectedMessage '*not both*'
            { Update-SalesforceDevOpsWorkItem -WorkItemId $script:w1 } | Should -Throw -ExpectedMessage '*at least one of -Subject*'
            { New-SalesforceDevOpsReview } | Should -Throw -ExpectedMessage '*-WorkItemId or -WorkItemName*'
            { New-SalesforceDevOpsReview -WorkItemId $script:w1 -WorkItemName WI-1 } | Should -Throw -ExpectedMessage '*not both*'
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
        It 'with -NoBrowser the environment login runs live and without --json, so the CLI can print the URL (review finding)' {
            Mock Assert-SalesforceInteractiveSession { }
            Mock Invoke-Salesforce { $null }
            $out = Add-SalesforceDevOpsStageEnvironment -PipelineId '0XB000000000001' -StageId '1QV000000000001' -EnvironmentName uat -OrgType production -NoBrowser -TargetOrg o
            $out | Should -BeNullOrEmpty
            Assert-MockCalled Assert-SalesforceInteractiveSession -Times 1 -Exactly -ParameterFilter { $Command -eq 'sf devops stage environment add --no-browser' }
            Assert-MockCalled Invoke-Salesforce -Times 1 -Exactly -ParameterFilter { $Interactive -and ($Arguments -join '|') -eq 'devops|stage|environment|add|--pipeline-id|0XB000000000001|--stage-id|1QV000000000001|--environment-name|uat|--org-type|Production|--no-browser|--target-org|o' }
        }
        It 'with -NoBrowser it refuses to run where there is no terminal, and -WhatIf runs nothing' {
            Mock Assert-SalesforceInteractiveSession { throw 'needs a terminal' }
            Mock Invoke-Salesforce { $null }
            { Add-SalesforceDevOpsStageEnvironment -PipelineId '0XB000000000001' -StageId '1QV000000000001' -EnvironmentName uat -OrgType Sandbox -NoBrowser } | Should -Throw -ExpectedMessage '*needs a terminal*'
            Add-SalesforceDevOpsStageEnvironment -PipelineId '0XB000000000001' -StageId '1QV000000000001' -EnvironmentName uat -OrgType Sandbox -NoBrowser -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 0 -Exactly
        }
        It 'a project update needs something to change and can switch the project off' {
            { Update-SalesforceDevOpsProject -ProjectId $script:p } | Should -Throw -ExpectedMessage '*at least one*'
            Update-SalesforceDevOpsProject -ProjectId $script:p -IsActive:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "devops|project|update|--project-id|$($script:p)|--no-is-active|--json" }
        }
        It 'a pipeline update needs something to change, cannot activate and deactivate, and activating asks by default' {
            { Update-SalesforceDevOpsPipeline -PipelineId $script:pl } | Should -Throw -ExpectedMessage '*at least one*'
            { Update-SalesforceDevOpsPipeline -PipelineId $script:pl -Activate -Deactivate } | Should -Throw -ExpectedMessage '*not both*'
            Update-SalesforceDevOpsPipeline -PipelineId $script:pl -Activate -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "devops|pipeline|update|--pipeline-id|$($script:pl)|--activate|--json" }
            Update-SalesforceDevOpsPipeline -PipelineId $script:pl -Activate -WhatIf | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1
        }
        It 'creating a repository needs its type and owner' {
            { New-SalesforceDevOpsPipeline -Name n -Repo r -CreateRepo } | Should -Throw -ExpectedMessage '*-RepoType*'
            { New-SalesforceDevOpsPipeline -Name n -Repo r -CreateRepo -RepoType github } | Should -Throw -ExpectedMessage '*-RepoOwner*'
            { New-SalesforceDevOpsPipeline -Name n -Repo r -CreateRepo -RepoType bitbucket } | Should -Throw -ExpectedMessage '*-BitbucketWorkspace*'
            { New-SalesforceDevOpsPipeline -Name n -Repo '--json' } | Should -Throw
            New-SalesforceDevOpsPipeline -Name n -Repo r -CreateRepo -RepoType bitbucket -BitbucketWorkspace ws -BitbucketProjectKey PROJ | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq 'devops|pipeline|create|--name|n|--repo|r|--create-repo|--repo-type|bitbucket|--bitbucket-workspace|ws|--bitbucket-project-key|PROJ|--json' }
        }
        It 'promotion needs exactly one of -WorkItemId and -StageId, and tests only with RunSpecifiedTests' {
            { Start-SalesforceDevOpsPromotion -TargetStageId $script:s2 } | Should -Throw -ExpectedMessage '*-WorkItemId*-StageId*'
            { Start-SalesforceDevOpsPromotion -TargetStageId $script:s2 -StageId $script:s1 -WorkItemId $script:w1 } | Should -Throw -ExpectedMessage '*not both*'
            { Start-SalesforceDevOpsPromotion -TargetStageId $script:s2 -StageId $script:s1 -Tests A } | Should -Throw -ExpectedMessage '*only used with -TestLevel RunSpecifiedTests*'
            { Start-SalesforceDevOpsPromotion -TargetStageId $script:s2 -StageId $script:s1 -TestLevel RunSpecifiedTests } | Should -Throw -ExpectedMessage '*needs the tests*'
            { Complete-SalesforceDevOpsPromotion -TargetStageId $script:s2 -Tests A } | Should -Throw -ExpectedMessage '*only used with*'
            { Start-SalesforceDevOpsPromotion -TargetStageId $script:s2 -StageId $script:s1 -TestLevel Bogus } | Should -Throw
            Assert-MockCalled Invoke-Salesforce -Times 0
            Start-SalesforceDevOpsPromotion -TargetStageId $script:s2 -StageId $script:s1 -Confirm:$false | Out-Null
            Assert-MockCalled Invoke-Salesforce -Times 1 -ParameterFilter { ($Arguments -join '|') -eq "devops|promote|--target-stage-id|$($script:s2)|--stage-id|$($script:s1)|--json" }
        }
        It 'combine and validate need at least one work item' {
            { Join-SalesforceDevOpsWorkItem -ParentWorkItemId $script:w1 -ChildWorkItemId @() -TargetStageId $script:s1 } | Should -Throw
            { Test-SalesforceDevOpsPromotion -TargetStageId $script:s1 -WorkItemId @() } | Should -Throw
            Assert-MockCalled Invoke-Salesforce -Times 0
        }
        It 'throws with the CLI message when the command fails' {
            Mock Invoke-Salesforce { '{"status":1,"message":"Pipeline is active"}' }
            { Remove-SalesforceDevOpsPipelineStage -PipelineId $script:pl -StageId $script:s1 -Confirm:$false } | Should -Throw -ExpectedMessage '*Pipeline is active*'
        }
    }
}

Describe 'psfdx-devops module ownership (issue 272)' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        $script:Exports = @((Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'psfdx-devops.psd1')).FunctionsToExport)
        $script:MetadataExports = @((Import-PowerShellDataFile -Path (Join-Path (Join-Path $script:Root 'psfdx-metadata') 'psfdx-metadata.psd1')).FunctionsToExport)
    }
    It 'exports the 26 sf devops cmdlets and the 5 beta sf project deploy pipeline cmdlets, 31 in all' {
        $script:Exports.Count | Should -Be 31
        @($script:Exports | Where-Object { $_ -like '*SalesforceDevOps*' }).Count | Should -Be 26
        @($script:Exports | Where-Object { $_ -like '*SalesforcePipeline*' }).Count | Should -Be 5
    }
    It 'exports each of them from the module itself, and no helper' {
        $loaded = (Get-Module psfdx-devops).ExportedFunctions.Keys
        @($loaded | Sort-Object) | Should -Be @($script:Exports | Sort-Object)
        foreach ($n in 'Get-SalesforcePipelineJobArguments', 'Get-SalesforcePipelineStartArguments', 'Test-SalesforceDeployWaitParams', 'Test-SalesforceDeployResultOptions', 'Test-SalesforceValidDeployWait', 'Assert-SalesforceInteractiveSession') {
            $loaded | Should -Not -Contain $n
        }
    }
    It 'is no longer exported by psfdx-metadata, so no command is exported twice' {
        foreach ($n in $script:Exports) { $script:MetadataExports | Should -Not -Contain $n -Because "$n moved to psfdx-devops" }
    }
    It 'every cmdlet is owned by psfdx-devops' {
        foreach ($n in $script:Exports) { (Get-Command -Name $n -Module psfdx-devops).ModuleName | Should -Be 'psfdx-devops' -Because $n }
    }
}