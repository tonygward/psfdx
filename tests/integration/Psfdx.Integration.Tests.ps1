# Opt-in smoke tests that run psfdx against a REAL scratch org. They never run in the ordinary Pester suite: without
# PSFDX_INTEGRATION=1 and PSFDX_INTEGRATION_ORG (the alias or username of a throwaway scratch org) every test is skipped.
# The Housekeeping - Scratch org integration workflow sets both after creating the org; see docs/integration-testing.md.
#
# The tests only touch the scratch org named in PSFDX_INTEGRATION_ORG. They never use a Dev Hub, a sandbox or production, and
# they clean up after themselves; deleting the scratch org (the workflow's teardown) removes anything left behind.

$script:Enabled = ($env:PSFDX_INTEGRATION -eq '1') -and (-not [string]::IsNullOrWhiteSpace($env:PSFDX_INTEGRATION_ORG))

BeforeDiscovery {
    $script:Enabled = ($env:PSFDX_INTEGRATION -eq '1') -and (-not [string]::IsNullOrWhiteSpace($env:PSFDX_INTEGRATION_ORG))
}

BeforeAll {
    $script:Root = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:Org = $env:PSFDX_INTEGRATION_ORG
    if ($env:PSFDX_INTEGRATION -eq '1') {
        foreach ($name in 'psfdx-shared', 'psfdx-core', 'psfdx-metadata', 'psfdx-development') {
            Get-Module -Name $name -All | ForEach-Object { try { Remove-Module -ModuleInfo $_ -Force -ErrorAction Stop } catch { } }
        }
        foreach ($name in 'psfdx-core', 'psfdx-metadata', 'psfdx-development') {
            Import-Module (Join-Path (Join-Path $script:Root $name) "$name.psd1") -Force -ErrorAction Stop | Out-Null
        }
    }
    $script:Suffix = [guid]::NewGuid().ToString('N').Substring(0, 10)
    $script:Created = @()
}

AfterAll {
    # Delete anything this run created, even if a test failed half way. The scratch org itself is deleted by the workflow.
    foreach ($item in $script:Created) {
        try { & sf data delete record --sobject $item.Type --record-id $item.Id --target-org $script:Org --json 2>&1 | Out-Null } catch { }
    }
}

Describe 'psfdx against a real scratch org' -Skip:(-not $script:Enabled) {

    Context 'search (read only)' {
        It 'runs a SOSL search and returns objects, or nothing' {
            { @(Search-SalesforceRecords -Query 'FIND {psfdx} RETURNING Account(Id, Name)' -TargetOrg $script:Org) } | Should -Not -Throw
            { Search-SalesforceRecords -Query 'FIND {psfdx} RETURNING Account(Id, Name)' -ResultFormat csv -TargetOrg $script:Org } | Should -Not -Throw
        }
    }

    Context 'org details (read only)' {
        It 'shows the org without a token, and lists the saved authorization' {
            $org = Get-SalesforceOrgDetails -TargetOrg $script:Org
            $org.username | Should -Not -BeNullOrEmpty
            $org.PSObject.Properties.Name | Should -Not -Contain 'accessToken'
            @(Get-SalesforceAuthorizations | Where-Object { $_.username -eq $org.username }).Count | Should -BeGreaterThan 0
        }
        It 'counts Account records and lists Apex classes' {
            { Get-SalesforceSObjectRecordCount -SObject Account -TargetOrg $script:Org } | Should -Not -Throw
            { Get-SalesforceMetadataComponents -MetadataType ApexClass -TargetOrg $script:Org } | Should -Not -Throw
        }
    }

    Context 'connection' {
        It 'reads the org limits' {
            $limits = @(Get-SalesforceLimits -TargetOrg $script:Org)
            $limits.Count | Should -BeGreaterThan 0
        }
        It 'lists the user the CLI is signed in as, without a token' {
            $users = @(Get-SalesforceAuthenticatedUser -TargetOrg $script:Org)
            $users.Count | Should -BeGreaterThan 0
            ($users | ConvertTo-Json -Depth 4) | Should -Not -Match 'accessToken'
        }
    }

    Context 'SOQL' {
        It 'queries a record and returns it without the attributes property' {
            $rows = @(Select-SalesforceRecords -Query 'SELECT Id, Name FROM Organization' -TargetOrg $script:Org)
            $rows.Count | Should -Be 1
            $rows[0].Name | Should -Not -BeNullOrEmpty
            $rows[0].PSObject.Properties.Name | Should -Not -Contain 'attributes'
        }
        It 'throws a useful error for malformed SOQL' {
            { Select-SalesforceRecords -Query 'SELECT Id FORM Organization' -TargetOrg $script:Org } | Should -Throw
        }
    }

    Context 'record lifecycle' {
        It 'creates, updates and deletes a temporary Account' {
            $name = "psfdx-it-$script:Suffix"
            $created = New-SalesforceRecord -Type Account -FieldUpdates "Name=$name" -TargetOrg $script:Org
            $created.id | Should -Not -BeNullOrEmpty
            $script:Created += [pscustomobject]@{ Type = 'Account'; Id = $created.id }

            Set-SalesforceRecord -Id $created.id -Type Account -FieldUpdates "Name=$name-updated" -TargetOrg $script:Org | Out-Null
            $row = @(Select-SalesforceRecords -Query "SELECT Id, Name FROM Account WHERE Id = '$($created.id)'" -TargetOrg $script:Org)
            $row.Count | Should -Be 1
            $row[0].Name | Should -Be "$name-updated"

            & sf data delete record --sobject Account --record-id $created.id --target-org $script:Org --json 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
            $script:Created = @($script:Created | Where-Object { $_.Id -ne $created.id })
            @(Select-SalesforceRecords -Query "SELECT Id FROM Account WHERE Id = '$($created.id)'" -TargetOrg $script:Org).Count | Should -Be 0
        }
    }

    Context 'metadata and Apex tests' {
        BeforeAll {
            $script:Project = Join-Path ([System.IO.Path]::GetTempPath()) ("psfdx-it-" + $script:Suffix)
            Copy-Item -LiteralPath (Join-Path (Join-Path $script:Root 'tests') 'integration\fixtures') -Destination $script:Project -Recurse -Force
            $script:ManifestPath = Join-Path (Join-Path $script:Project 'manifest') 'package.xml'
            Push-Location -LiteralPath $script:Project
        }
        AfterAll {
            Pop-Location
            Remove-Item -LiteralPath $script:Project -Recurse -Force -ErrorAction SilentlyContinue
        }
        It 'deploys the probe classes by manifest' {
            $deploy = Deploy-SalesforceMetadata -Manifest $script:ManifestPath -TargetOrg $script:Org
            $deploy | Should -Not -BeNullOrEmpty
        }
        It 'retrieves them again by manifest' {
            $out = Join-Path $script:Project 'retrieved'
            New-Item -ItemType Directory -Path $out -Force | Out-Null
            Retrieve-SalesforceMetadata -Manifest $script:ManifestPath -OutputDir $out -Wait 10 -TargetOrg $script:Org | Out-Null
            @(Get-ChildItem -LiteralPath $out -Recurse -File).Count | Should -BeGreaterThan 0
        }
        It 'runs the Apex test in one call and returns per-test results' {
            $tests = @(Test-SalesforceApex -ClassName PsfdxItProbeTest -WaitMinutes 10 -TargetOrg $script:Org)
            $tests.Count | Should -BeGreaterThan 0
            ($tests | Select-Object -First 1).Outcome | Should -Be 'Pass'
        }
        It 'runs it through the start, wait and result lifecycle' {
            $run = Start-SalesforceApexTest -ClassName PsfdxItProbeTest -TargetOrg $script:Org
            $run.TestRunId | Should -Match '^707'
            $result = Wait-SalesforceApexTest -TestRunId $run.TestRunId -TimeoutMinutes 10 -TargetOrg $script:Org
            $result.Completed | Should -BeTrue
            $result.Summary.outcome | Should -Be 'Passed'
            (Get-SalesforceApexTestResult -TestRunId $run.TestRunId -TargetOrg $script:Org).Tests.Count | Should -BeGreaterThan 0
        }
        It 'validates a deployment, then reports on it, without deploying' {
            $validation = Test-SalesforceDeploy -Manifest $script:ManifestPath -TestLevel SpecificTests -Tests PsfdxItProbeTest -Wait 10 -TargetOrg $script:Org
            $validation | Should -Not -BeNullOrEmpty
            Get-SalesforceDeployStatus -JobId $validation.id -TargetOrg $script:Org | Should -Not -BeNullOrEmpty
        }
        It 'writes a manifest from source and lists the files .forceignore skips' {
            $out = Join-Path $script:Project 'generated'
            New-Item -ItemType Directory -Path $out -Force | Out-Null
            New-SalesforceManifest -SourceDir (Join-Path $script:Project 'force-app') -Name generated -OutputDir $out | Out-Null
            Test-Path -LiteralPath (Join-Path $out 'generated.xml') | Should -BeTrue
            { Get-SalesforceIgnoredFiles } | Should -Not -Throw
        }
        It 'converts source to metadata format and back' {
            $mdapi = Join-Path $script:Project 'mdapi'
            $back = Join-Path $script:Project 'back'
            ConvertTo-SalesforceMdapiFormat -SourceDir (Join-Path $script:Project 'force-app') -OutputDir $mdapi | Out-Null
            @(Get-ChildItem -LiteralPath $mdapi -Recurse -File -Filter 'PsfdxItProbe.cls').Count | Should -BeGreaterThan 0
            ConvertTo-SalesforceSourceFormat -RootDir $mdapi -OutputDir $back | Out-Null
            @(Get-ChildItem -LiteralPath $back -Recurse -File -Filter 'PsfdxItProbe.cls').Count | Should -BeGreaterThan 0
        }
        It 'previews a source-tracking reset without changing anything' {
            Reset-SalesforceSourceTracking -TargetOrg $script:Org -WhatIf | Out-Null
            { Get-SalesforceDeployPreview -TargetOrg $script:Org } | Should -Not -Throw
        }
    }
}
