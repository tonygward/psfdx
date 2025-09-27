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
    if ($OutputDirectory) { $command += " --output-dir $OutputDirectory" }
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

function Get-SalesforceProjectConfig {
    [CmdletBinding()]
    Param()
    $sfdxConfigFile = ""
    $files = Get-ChildItem -Recurse -Filter "sfdx-config.json"
    foreach ($file in $files) {
        if ($file.FullName -like "*.sfdx*") {
            $sfdxConfigFile = $file
            break
        }
    }

    if (!(Test-Path -Path $sfdxConfigFile)) {
        throw "Missing Salesforce Project File (sfdx-config.json)"
    }
    Write-Verbose "Found sfdx config ($sfdxConfigFile)"
    return $sfdxConfigFile
}

function Set-SalesforceProjectUser {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $TargetOrg)
    Invoke-Salesforce -Command "sf config set target-org=$TargetOrg"
}

function New-SalesforceProjectAndScratchOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $TargetDevHub
    )
    New-SalesforceProject -Name $Name
    Push-Location -Path $Name
    Remove-SalesforceScratchOrgs
    $scratchOrg = New-SalesforceScratchOrg -TargetDevHub $TargetDevHub
    Set-SalesforceProjectUser -TargetOrg ($scratchOrg.username)
}

function Get-SalesforceConfig {
    [CmdletBinding()]
    Param()
    $command = "sf config list --json"
    $result = Invoke-Salesforce -Command $command
    Show-SalesforceResult -Result $result
}

function Set-SalesforceDefaultDevHub {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $TargetDevHub
    )
    Invoke-Salesforce -Command "sf config set target-dev-hub=$TargetDevHub --global"
}

function Remove-SalesforceDefaultDevHub {
    [CmdletBinding()]
    Param()
    Invoke-Salesforce -Command "sf config unset target-dev-hub --global"
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
        [Parameter(Mandatory = $false)][switch] $Set,
        [Parameter(Mandatory = $false)][int] $DurationDays,
        [Parameter(Mandatory = $false)][string] $DefinitionFile = 'config/project-scratch-def.json',
        [Parameter(Mandatory = $false)][int] $WaitMinutes
    )
    $command = "sf org create scratch"
    if ($TargetDevHub) {
        $command += " --target-dev-hub $TargetDevHub"
    }
    if ($DurationDays) {
        $command += " --duration-days $DurationDays"
    }
    $command += " --definition-file $DefinitionFile"
    if ($WaitMinutes) {
        $command += " --wait $WaitMinutes"
    }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    Show-SalesforceResult -Result $result

    $scratchOrgUsername = $result.username
    if ($Set) {
    Set-SalesforceProjectUser -TargetOrg $scratchOrgUsername
    }
}

function Remove-SalesforceScratchOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ScratchOrgUserName,
        [Parameter()][switch] $NoPrompt
    )
    $command = "sf org delete scratch --target-org $ScratchOrgUserName"
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
        Remove-SalesforceScratchOrg -ScratchOrgUserName ($scratchOrg.username) -NoPrompt
    }
}

#endregion

#region Apex Testing

function Test-SalesforceApex {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $ClassName,
        [Parameter(Mandatory = $false)][string] $TestName,
        [Parameter(Mandatory = $false)][string] $TargetOrg,

        [Parameter(Mandatory = $false)][string][ValidateSet('human', 'tap', 'junit', 'json')] $ResultFormat = 'json',

        [Parameter(Mandatory = $false)][switch] $RunAsynchronously,
        [Parameter(Mandatory = $false)][switch] $CodeCoverage,
        [Parameter(Mandatory = $false)][int] $WaitMinutes = 10,

        [Parameter(Mandatory = $false)][string] $OutputDirectory
    )

    $command = "sf apex run test"
    if ($ClassName -and $TestName) {
        # Run specific Test in a Class
        $command += " --tests $ClassName.$TestName"
        if ($RunAsynchronously) { $command += "" }
        else { $command += " --synchronous" }

    } elseif ((-not $TestName) -and ($ClassName)) {
        # Run Test Class
        $command += " --class-names $ClassName"
        if ($RunAsynchronously) { $command += "" }
        else { $command += " --synchronous" }
    } else {
        $command += " --test-level RunLocalTests" # Run all Tests
    }

    if ($OutputDirectory) {
        $command += " --output-dir $OutputDirectory"
    } else {
        $command += " --output-dir $PSScriptRoot"
    }

    if ($WaitMinutes) { $command += " --wait $WaitMinutes" }

    if ($CodeCoverage) { $command += " --detailed-coverage" }
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    $command += " --result-format $ResultFormat"

    $result = Invoke-Salesforce -Command $command
    $result = $result | ConvertFrom-Json

    Write-Verbose $result

    $result.result.tests
    if ($result.result.summary.outcome -ne 'Passed') {
        throw ($result.result.summary.failing.tostring() + " Tests Failed")
    }

    if (-not $CodeCoverage) {
        return
    }

    [int]$codeCoverage = ($result.result.summary.testRunCoverage -replace '%')
    if ($codeCoverage -lt 75) {
        $result.result.coverage.coverage
        throw 'Insufficient code coverage'
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

    $result = Invoke-Salesforce -Command "sf data query --query `"$query`" --use-tooling-api --target-org $TargetOrg --json"
    $result = $result | ConvertFrom-Json
    if ($result.status -ne 0) {
        throw ($result.message)
    }
    $result = $result.result.records

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
        [Parameter(Mandatory = $true)][string] $ProjectFolder,
        [Parameter(Mandatory = $true)][string] $FileName
    )

    if ((Get-IsSalesforceProject -ProjectFolder $ProjectFolder) -eq $false) {
        Write-Verbose "Not a Salesforce Project"
        return
    }
    $username = Get-SalesforceTargetOrg -ProjectFolder $ProjectFolder

    $type = Get-SalesforceType -FileName $FileName
    if (($type -eq "ApexClass") -or ($type -eq "ApexTrigger")) {
        $name = Get-SalesforceName -FileName $FileName
        Deploy-SalesforceComponent -Type $type -Name $name -TargetOrg $username

        $outputDir = Get-SalesforceTestResultsApexFolder -ProjectFolder $ProjectFolder
        $testClassNames = Get-SalesforceApexTestsClasses -ProjectFolder $ProjectFolder
        Test-SalesforceApex -TargetOrg $username -ClassName $testClassNames -CodeCoverage:$false -OutputDirectory $outputDir
    }
}

function Get-IsSalesforceProject {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $ProjectFolder)

    $sfdxProjectFile = Join-Path -Path $ProjectFolder -ChildPath "sfdx-project.json"
    if (Test-Path -Path $sfdxProjectFile) {
        return $true
    }
    return $false
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
        [Parameter(Mandatory = $false)][string] $OutputDirectory = 'ForceAppDefault'
    )

    $command = "sf apex generate class"
    $command += " --name $Name"
    $command += " --template $Template"

    if ($OutputDirectory = 'ForceAppDefault') {
        $OutputDirectory = "force-app/main/default/classes"
    }
    if ($OutputDirectory) {
        $command += " --output-dir $OutputDirectory"
    }
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
        [Parameter(Mandatory = $false)][string] $OutputDirectory = 'ForceAppDefault'
    )

    $command = "sf apex generate trigger"
    $command += " --name $Name"
    $command += " --event $Event"
    if ($SObject) {
        $command += " --sobject $SObject"
    }
    if ($OutputDirectory = 'ForceAppDefault') {
        $OutputDirectory = "force-app/main/default/triggers"
    }
    if ($OutputDirectory) {
        $command += " --output-dir $OutputDirectory"
    }
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