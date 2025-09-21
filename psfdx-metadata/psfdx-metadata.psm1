. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Invoke-Salesforce.ps1')
. (Join-Path $PSScriptRoot '..' 'psfdx-shared' 'Show-SalesforceResult.ps1')

class SalesforceMetadataTypeGenerator : System.Management.Automation.IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        $types = Get-SalesforceMetaTypes
        return (@($types) + 'CustomField', 'ValidationRule') |
            Where-Object { $_ } |
            Sort-Object -Unique
    }
}

#region Retrieve

function Retrieve-SalesforceComponent {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string][ValidateSet([SalesforceMetadataTypeGenerator])] $Type,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $false)][string] $ChildName,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][string] $OutputDir,
        [Parameter(Mandatory = $false)][switch] $IgnoreConflicts
    )

    if ($ChildName -and -not $Name) {
        throw "Specify -Name when using -ChildName."
    }

    $command = "sf project retrieve start --metadata $Type"
    if ($Name) {
        $command += ":$Name"
        if ($ChildName) { $command += ".$ChildName" }
    }
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    if ($PSBoundParameters.ContainsKey('Wait')) { $command += " --wait $Wait" }
    if ($OutputDir) {
        if (-not (Test-Path -Path $OutputDir -PathType Container)) {
            throw "Output directory '$OutputDir' does not exist."
        }
        $command += " --output-dir `"$OutputDir`""
    }
    if ($IgnoreConflicts) { $command += " --ignore-conflicts" }
    Invoke-Salesforce -Command $command
}

function Retrieve-SalesforceMetadata {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Manifest,
        [Parameter(Mandatory = $true)][string] $OutputDir,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][switch] $Unzip,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if (-not (Test-Path -Path $Manifest -PathType Leaf)) {
        throw "Manifest file '$Manifest' does not exist."
    }
    if (-not (Test-Path -Path $OutputDir -PathType Container)) {
        throw "Output directory '$OutputDir' does not exist."
    }

    $command = "sf project retrieve start --manifest `"$Manifest`""
    $command += " --target-metadata-dir `"$OutputDir`""
    if ($PSBoundParameters.ContainsKey('Wait')) { $command += " --wait $Wait" }
    if ($Unzip) { $command += " --unzip" }
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }

    Invoke-Salesforce -Command $command
}

function Retrieve-SalesforcePackage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $OutputDir,
        [Parameter(Mandatory = $false)][int] $Wait,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    if (-not (Test-Path -Path $OutputDir -PathType Container)) {
        throw "Output directory '$OutputDir' does not exist."
    }

    $command = "sf project retrieve start --package-name `"$Name`""
    $command += " --output-dir `"$OutputDir`""
    if ($PSBoundParameters.ContainsKey('Wait')) { $command += " --wait $Wait" }
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }

    Invoke-Salesforce -Command $command
}

function Retrieve-SalesforceField {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,
        [Parameter(Mandatory = $true)][string] $FieldName,
        [Parameter(Mandatory = $false)][string] $TargetOrg)
    Retrieve-SalesforceComponent -Type 'CustomField' -Name $ObjectName -ChildName $FieldName -TargetOrg $TargetOrg
}

function Retrieve-SalesforceValidationRule {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,
        [Parameter(Mandatory = $true)][string] $RuleName,
        [Parameter(Mandatory = $false)][string] $TargetOrg)
    Retrieve-SalesforceComponent -Type 'ValidationRule' -Name $ObjectName -ChildName $RuleName -TargetOrg $TargetOrg
}

function Retrieve-SalesforceOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $IncludePackages
    )

    $command = "sf force source manifest create --from-org $TargetOrg"
    $command += " --name=allMetadata"
    $command += " --output-dir ."
    if ($IncludePackages) { $command += " --include-packages=unlocked" }
    Invoke-Salesforce -Command $command

    $command = "sf project retrieve start --target-org $TargetOrg"
    $command += " --manifest allMetadata.xml"
    Invoke-Salesforce -Command $command
}

#endregion

#region Deploy

function Deploy-SalesforceComponent {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string][ValidateSet([SalesforceMetadataTypeGenerator])] $Type,
        [Parameter(Mandatory = $false)][string] $Name,
        [Parameter(Mandatory = $true)][string] $TargetOrg
    )
    $command = "sf project deploy start"
    $command += " --metadata $Type"
    if ($Name) { $command += ":$Name" }
    $command += " --target-org $TargetOrg"
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

#endregion

#region Describe

function Describe-SalesforceObjects {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $TargetOrg
    )
    $command = "sf sobject list"
    $command += " --target-org $TargetOrg"
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Describe-SalesforceObject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    $command = "sf sobject describe"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    $command += " --sobject $Name"
    if ($UseToolingApi) { $command += " --use-tooling-api" }
    $command += " --json"
    $result = Invoke-Salesforce -Command $command
    return Show-SalesforceResult -Result $result
}

function Describe-SalesforceFields {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    $result = Describe-SalesforceObject -Name $ObjectName -TargetOrg $TargetOrg -UseToolingApi:$UseToolingApi
    $result = $result.fields
    $result = $result | Select-Object name, label, type, byteLength | Sort-Object name
    return $result
}

#endregion

#region Types and Utilities

function Get-SalesforceMetaTypes {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $command = "sf org list metadata-types"
    if ($TargetOrg) { $command += " --target-org $TargetOrg" }
    $command += " --json"

    $result = Invoke-Salesforce -Command $command
    $result = $result | ConvertFrom-Json
    $result = $result.result.metadataObjects
    $result = $result | Select-Object xmlName
    return $result
}

function Build-SalesforceQuery {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,
        [Parameter(Mandatory = $true)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi,

        [Parameter(Mandatory = $false)][switch] $ExcludeAuditFields,
        [Parameter(Mandatory = $false)][switch] $ExcludeNameFields,
        [Parameter(Mandatory = $false)][switch] $ExcludeContextFields
    )
    $fields = Describe-SalesforceFields -ObjectName $ObjectName -TargetOrg $TargetOrg -UseToolingApi:$UseToolingApi
    if ($null -eq $fields) {
        return ""
    }

    $fieldNames = @()
    foreach ($field in $fields) {
        $fieldNames += $field.name
    }
    if ($ExcludeAuditFields) {
        $auditFields = @(
            'CreatedById',
            'CreatedDate',
            'LastModifiedById',
            'LastModifiedDate',
            'SystemModstamp',
            'IsDeleted'
        )
        $fieldNames = $fieldNames | Where-Object { $auditFields -notcontains $_ }
    }
    if ($ExcludeNameFields) {
        $nameFields = @(
            'Name',
            'FirstName',
            'LastName',
            'Subject'
        )
        $fieldNames = $fieldNames | Where-Object { $nameFields -notcontains $_ }
    }
    if ($ExcludeContextFields) {
        $contextFields = @(
            'OwnerId',
            'RecordTypeId',
            'CurrencyIsoCode',
            'Division'
        )
        $fieldNames = $fieldNames | Where-Object { $contextFields -notcontains $_ }
    }
    $value = "SELECT "
    foreach ($fieldName in $fieldNames) {
        $value += $fieldName + ","
    }
    $value = $value.TrimEnd(",")
    $value += " FROM $ObjectName"
    return $value
}

#endregion
