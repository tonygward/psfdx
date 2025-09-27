. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Invoke-Salesforce.ps1')
. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Show-SalesforceResult.ps1')

#region Projects & Config

function New-SalesforceProject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string][ValidateSet('standard', 'empty', 'analytics')] $Template = 'standard',
        [Parameter(Mandatory = $false)][string] $DefaultUserName = $null,

        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $DefaultPackageDirectory,
        [Parameter(Mandatory = $false)][string] $Namespace,
        [Parameter(Mandatory = $false)][switch] $GenerateManifest
    )
    $command = "sf project generate --name $Name"
    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) {
            throw "Output directory '$OutputDirectory' does not exist."
        }
        $command += " --output-dir $OutputDirectory"
    }
    if ($DefaultPackageDirectory) { $command += " --default-package-dir $DefaultPackageDirectory" }
    if ($Namespace) { $command += " --namespace $Namespace" }
    if ($GenerateManifest) { $command += " --manifest" }
    $command += " --template $Template"
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    $result = Show-SalesforceResult -Result $result

    if (($null -ne $DefaultUserName) -and ($DefaultUserName -ne '')) {
        $projectFolder = Join-Path -Path $result.outputDir -ChildPath $Name
        New-Item -Path $projectFolder -Name ".sfdx" -ItemType Directory | Out-Null
        Set-SalesforceTargetOrg -DefaultUserName $DefaultUserName -ProjectFolder $projectFolder
    }
    return $result
}

function Set-SalesforceTargetOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Value,
        [Parameter(Mandatory = $false)][switch] $Global
    )
    $command = "sf config set target-org=$Value"
    if ($Global) { $command += " --global" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return (Show-SalesforceResult -Result $result).successes
}

function Get-SalesforceTargetOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Global
    )
    $command = "sf config get target-org"
    if ($Global) { $command += " --global" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceTargetOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Global
    )
    $command = "sf config unset target-org"
    if ($Global) { $command += " --global" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return (Show-SalesforceResult -Result $result).successes
}

function Get-SalesforceConfig {
    [CmdletBinding()]
    Param()
    $command = "sf config list --json"
    $result = Invoke-Salesforce -Command $command
    Show-SalesforceResult -Result $result
}

function Set-SalesforceTargetDevHub {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Value,
        [Parameter(Mandatory = $false)][switch] $Global
    )

    $command = "sf config set target-dev-hub=$Value"
    if ($Global) { $command += " --global" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return (Show-SalesforceResult -Result $result).successes
}

function Get-SalesforceTargetDevHub {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Global
    )

    $command = "sf config get target-dev-hub"
    if ($Global) { $command += " --global" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Remove-SalesforceTargetDevHub {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Global
    )
    $command = "sf config unset target-dev-hub"
    if ($Global) { $command += " --global" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return (Show-SalesforceResult -Result $result).successes
}

#endregion

#region Scratch Orgs

function Get-SalesforceScratchOrgs {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $SkipConnectionStatus,
        [Parameter(Mandatory = $false)][switch] $Last
    )

    $command = "sf org list --all"
    if ($SkipConnectionStatus) {
        $command += " --skip-connection-status"
    }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command

    $result = $result | ConvertFrom-Json
    $result = $result.result.scratchOrgs
    $result = $result | Select-Object orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias
    if ($Last) {
        $result = $result | Sort-Object lastUsed -Descending | Select-Object -First 1
    }
    return $result
}

function New-SalesforceScratchOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetDevHub,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][int] $DurationDays,
        [Parameter(Mandatory = $false)][string] $DefinitionFile = 'config/project-scratch-def.json',
        [Parameter(Mandatory = $false)][int] $WaitMinutes,
        [Parameter(Mandatory = $false)][string][ValidateSet('developer', 'enterprise', 'group', 'professional', 'partner-developer', 'partner-enterprise', 'partner-group', 'partner-professional')] $Edition,
        [Parameter(Mandatory = $false)][string] $Snapshot,
        [Parameter(Mandatory = $false)][string] $AdminEmail,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string][ValidateSet('preview', 'previous')] $Release,
        [Parameter(Mandatory = $false)][string] $SourceOrgId,
        [Parameter(Mandatory = $false)][string] $AdminUsername
    )
    $command = "sf org create scratch"
    if ($TargetDevHub) { $command += " --target-dev-hub $TargetDevHub" }
    if ($SetDefault) { $command += " --set-default" }
    if ($DurationDays) { $command += " --duration-days $DurationDays" }
    $command += " --definition-file $DefinitionFile"
    if ($WaitMinutes) { $command += " --wait $WaitMinutes" }
    if ($Edition) { $command += " --edition $Edition" }
    if ($Snapshot) { $command += " --snapshot $Snapshot" }
    if ($AdminEmail) { $command += " --admin-email $AdminEmail" }
    if ($Description) { $command += " --description `"$Description`"" }
    if ($Name) { $command += " --name `"$Name`"" }
    if ($Release) { $command += " --release $Release" }
    if ($SourceOrgId) { $command += " --source-org $SourceOrgId" }
    if ($AdminUsername) { $command += " --username $AdminUsername" }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    Show-SalesforceResult -Result $result
}

function Remove-SalesforceScratchOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $TargetOrg,
        [Parameter()][switch] $NoPrompt
    )
    $command = "sf org delete scratch --target-org $TargetOrg"
    if ($NoPrompt) {
        $command += " --no-prompt"
    }
    Invoke-Salesforce -Command $command
}

function Remove-SalesforceScratchOrgs {
    [CmdletBinding()]
    Param()

    $scratchOrgs = Get-SalesforceScratchOrgs
    foreach ($scratchOrg in $scratchOrgs) {
        Remove-SalesforceScratchOrg -TargetOrg ($scratchOrg.username) -NoPrompt
    }
}

#endregion

#region Apex Testing

function Test-SalesforceApex {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $ClassName,
        [Parameter(Mandatory = $false)][string] $TestName,

        [Parameter(Mandatory = $false)][string][ValidateSet('human', 'tap', 'junit', 'json')] $ResultFormat = 'json',

        [Parameter(Mandatory = $false)][switch] $Concise,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][switch] $CodeCoverageDetailed,
        [Parameter(Mandatory = $false)][int] $WaitMinutes = 10,

        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $TestsInProject,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $command = "sf apex run test"
    $collectedTests = @()

    if ($TestsInProject.IsPresent) {
        $searchRoot = Get-Location
        $testFiles = Get-ChildItem -Path $searchRoot.Path -Recurse -Filter '*.cls' -File -ErrorAction SilentlyContinue
        $testFiles = $testFiles | Where-Object {
            Select-String -Path $_.FullName -Pattern '@isTest' -SimpleMatch -Quiet
        }
        $collectedTests = $testFiles | ForEach-Object {
            [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        } | Sort-Object -Unique

        if (-not $collectedTests) {
            throw "No Apex test classes found in '$($searchRoot.Path)'."
        }
        foreach ($testName in $collectedTests) {
            $command += " --tests $testName"
        }
    } elseif ($ClassName -and $TestName) {
        $command += " --tests $ClassName.$TestName" # Run specific Test in a Class
    } elseif ((-not $TestName) -and ($ClassName)) {
        $command += " --class-names $ClassName"     # Run Test Class
    }

    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) {
            throw "Output directory '$OutputDirectory' does not exist."
        }
        $command += " --output-dir $OutputDirectory"
    }
    if ($WaitMinutes) { $command += " --wait $WaitMinutes" }

    if ($Concise) { $command += " --concise" }
    if ($CodeCoverage) { $command += " --code-coverage" }
    if ($CodeCoverageDetailed) { $command += " --detailed-coverage" }
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    $command += " --result-format $ResultFormat"

    if ($ResultFormat -ne 'json') {
        Invoke-Salesforce -Command $command
        return
    }

    $result = Invoke-Salesforce -Command $command
    $result = $result | ConvertFrom-Json

    $result.result.tests
    if ($result.result.summary.outcome -ne 'Passed') {
        throw ($result.result.summary.failing.tostring() + " Tests Failed")
    }

    if ((-not $CodeCoverage) -and (-not $CodeCoverageDetailed)) {
        return
    }

    [int]$codeCoverage = ($result.result.summary.testRunCoverage -replace '%')
    if ($codeCoverage -lt 75) {
        $result.result.coverage.coverage
        throw "Insufficient code coverage ${codeCoverage}%"
    }
}

function Get-SalesforceCodeCoverage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $ApexClassOrTrigger = $null,
        [Parameter(Mandatory = $true)][string] $TargetOrg
    )
    $query = "SELECT ApexTestClass.Name, TestMethodName, ApexClassOrTrigger.Name, NumLinesUncovered, NumLinesCovered, Coverage "
    $query += "FROM ApexCodeCoverage "
    if (($null -ne $ApexClassOrTrigger) -and ($ApexClassOrTrigger -ne '')) {
        $apexClass = Get-SalesforceApexClass -Name $ApexClassOrTrigger -TargetOrg $TargetOrg
        $apexClassId = $apexClass.Id
        $query += "WHERE ApexClassOrTriggerId = '$apexClassId' "
    }

    $result = Select-SalesforceRecords -Query $query -TargetOrg $TargetOrg -UseToolingApi
    $result = (Show-SalesforceResult -Result $result).records

    $values = @()
    foreach ($item in $result) {
        $value = New-Object -TypeName PSObject
        $value | Add-Member -MemberType NoteProperty -Name 'ApexClassOrTrigger' -Value $item.ApexClassOrTrigger.Name
        $value | Add-Member -MemberType NoteProperty -Name 'ApexTestClass' -Value $item.ApexTestClass.Name
        $value | Add-Member -MemberType NoteProperty -Name 'TestMethodName' -Value $item.TestMethodName

        $codeCoverage = 0
        $codeLength = $item.NumLinesCovered + $item.NumLinesUncovered
        if ($codeLength -gt 0) {
            $codeCoverage = $item.NumLinesCovered / $codeLength
        }
        $value | Add-Member -MemberType NoteProperty -Name 'CodeCoverage' -Value $codeCoverage.toString("P")
        $codeCoverageOK = $false
        if ($codeCoverage -ge 0.75) { $codeCoverageOK = $true }

        $value | Add-Member -MemberType NoteProperty -Name 'CodeCoverageOK' -Value $codeCoverageOK
        $value | Add-Member -MemberType NoteProperty -Name 'NumLinesCovered' -Value $item.NumLinesCovered
        $value | Add-Member -MemberType NoteProperty -Name 'NumLinesUncovered' -Value $item.NumLinesUncovered
        $values += $value
    }

    return $values
}

function Invoke-SalesforceApex {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ApexFile,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $command = "sf apex run --file $ApexFile"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Watch-SalesforceApex {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $FileName
    )

    $type = Get-SalesforceType -FileName $FileName
    if (($type -eq "ApexClass") -or ($type -eq "ApexTrigger")) {
        $name = Get-SalesforceName -FileName $FileName
        Deploy-SalesforceComponent -Type $type -Name $name

        $outputDir = Get-SalesforceTestResultsApexFolder -ProjectFolder $ProjectFolder
        $testClassNames = Get-SalesforceApexTestsClasses -ProjectFolder $ProjectFolder
        Test-SalesforceApex -ClassName $testClassNames -CodeCoverage:$false -OutputDirectory $outputDir
    }
}

function Get-SalesforceType {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $FileName)

    if ($FileName.EndsWith(".cls")) {
        return "ApexClass"
    }
    if ($FileName.EndsWith(".trigger")) {
        return "ApexTrigger"
    }
    return ""
}

function Get-SalesforceName {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $FileName)

    $name = (Get-Item $FileName).Basename
    Write-Verbose ("Apex Name: " + $name)
    return $name
}

function Get-SalesforceTestResultsApexFolder {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $ProjectFolder)

    $folder = Join-Path -Path (Join-Path -Path (Join-Path -Path $ProjectFolder -ChildPath ".sfdx") -ChildPath "tools") -ChildPath "testresults/apex"
    Write-Verbose ("Apex Test Results Folder: " + $folder)
    # TODO: Check Folder Exists
    return $folder
}

function Get-SalesforceApexTestsClasses {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $ProjectFolder)

    $classesFolder = Join-Path -Path $ProjectFolder -ChildPath "force-app\main\default\classes"
    $classes = Get-ChildItem -Path $classesFolder -Filter *.cls
    $testClasses = @()
    foreach ($class in $classes) {
        if (Select-String -Path $class -Pattern "@isTest") {
            Write-Verbose ("Found Apex Test Class: " + $class)
            $testClasses += Get-SalesforceName -FileName $class
        }
    }
    $testClassNames = $testClasses -join ","
    Write-Verbose ("Apex Test Class Names: " + $testClassNames)
    return $testClassNames
}

function Get-SalesforceApexClass {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $TargetOrg
    )
    $query = "SELECT Id, Name FROM ApexClass WHERE Name = '$Name' LIMIT 1"
    $result = Invoke-Salesforce -Command "sf data query --query `"$query`" --use-tooling-api --target-org $TargetOrg --json"
    $parsed = $result | ConvertFrom-Json
    if ($parsed.status -ne 0) {
        throw ($parsed.message)
    }
    return $parsed.result.records | Select-Object -First 1
}

#endregion

#region Apex Scaffolding

function New-SalesforceApexClass {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string]
            [ValidateSet('DefaultApexClass', 'ApexUnitTest', 'ApexUnitTest', 'InboundEmailService')]
            $Template = 'DefaultApexClass',
        [Parameter(Mandatory = $false)][string] $OutputDirectory = 'force-app/main/default/classes'
    )
    $command = "sf apex generate class"
    $command += " --name $Name"
    $command += " --template $Template"
    $command += " --output-dir $OutputDirectory"
    Invoke-Salesforce -Command $command
}

function New-SalesforceApexTrigger {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string]
            [ValidateSet('before insert', 'before update', 'before delete', 'after insert', 'after update', 'after delete', 'after undelete')]
            $Event = 'before insert',
        [Parameter(Mandatory = $false)][string] $SObject,
        [Parameter(Mandatory = $false)][string] $OutputDirectory = 'force-app/main/default/triggers'
    )
    $command = "sf apex generate trigger"
    $command += " --name $Name"
    $command += " --event $Event"
    if ($SObject) { $command += " --sobject $SObject" }
    $command += " --output-dir $OutputDirectory"
    Invoke-Salesforce -Command $command
}

#endregion

#region LWC Dev Server

function Install-SalesforceLwcDevServer {
    [CmdletBinding()]
    Param()
    Invoke-Salesforce -Command "npm install -g node-gyp"
    Invoke-Salesforce -Command "sf plugins install @salesforce/lwc-dev-server"
    Invoke-Salesforce -Command "sf plugins update"
}

function Start-SalesforceLwcDevServer {
    [CmdletBinding()]
    Param()
    Invoke-Salesforce -Command "sf lightning lwc start"
}

#endregion

#region LWC / Jest Testing

function Install-SalesforceJest {
    [CmdletBinding()]
    Param()
    if (Get-Command yarn -ErrorAction SilentlyContinue) {
        Invoke-Salesforce -Command "yarn add -D @salesforce/sfdx-lwc-jest"
    } else {
        Invoke-Salesforce -Command "npm install -D @salesforce/sfdx-lwc-jest"
    }
}

function New-SalesforceJestTest {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $LwcName)
    $filePath = "force-app/main/default/lwc/$LwcName/$LwcName.js"
    $command = "sf force lightning lwc test create --filepath $filePath --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Test-SalesforceJest {
    [CmdletBinding()]
    Param()
    Invoke-Salesforce -Command "npm run test:unit"
}

function Debug-SalesforceJest {
    [CmdletBinding()]
    Param()
    Invoke-Salesforce -Command "npm run test:unit:debug"
}

function Watch-SalesforceJest {
    [CmdletBinding()]
    Param()
    Invoke-Salesforce -Command "npm run test:unit:watch"
}

#endregion