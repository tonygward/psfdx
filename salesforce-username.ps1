function Get-SalesforceProjectUser {
    [CmdletBinding()]
    Param()
    $sfdxConfigPath = Join-Path -Path ".sfdx" -ChildPath "sfdx-config.json"

    if (-not(Test-Path -Path $sfdxConfigPath -PathType Leaf)) {
        Write-Warning -Message "$sfdxConfigPath not found"
        return
    }

    $sfdxConfig = Get-Content -Path $sfdxConfigPath | ConvertFrom-Json
    return $sfdxConfig.defaultusername
}

function Get-SalesforceUser {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $Username)

    if ($Username) {
        return $Username
    }

    $projectUser = Get-SalesforceProjectUser
    if ($projectUser) {
        return $projectUser
    }

    return $Username
}