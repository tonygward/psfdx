function Import-PsfdxSharedModule {
    # Loads psfdx-shared for the module this copy sits in. Keep every copy identical.
    #
    # Contract: the modules release in lockstep, so psfdx-shared must have the same Major.Minor as the importing module and
    # a version no lower than it. A newer patch is fine; an older one, or a different minor, is not.
    #
    # Resolution is deterministic. Versions are compared as [version], never as text.
    #   1. A loaded copy that is compatible (the highest one) is used as it is.
    #   2. Otherwise the first tier that has a compatible copy wins, and the highest version within the tier:
    #      the sibling folder (source checkout, zip install, flat install, Gallery bundle), then sibling version
    #      folders (<Modules>/psfdx-shared/<version>), then PSModulePath.
    #   3. A loaded copy that is not compatible is removed and replaced. If nothing compatible exists the
    #      function throws and says what it found; it never carries on with the wrong version.
    [CmdletBinding()]
    param(
        [string] $ModuleName = 'psfdx-shared',
        [string] $ModuleRoot = $PSScriptRoot,
        [version] $OwnVersion
    )

    $readVersion = {
        param([string] $Manifest)
        try { return [version](Import-PowerShellDataFile -LiteralPath $Manifest).ModuleVersion } catch { return $null }
    }

    # The module's own version comes from its manifest next to this file: the module's version is not set yet while its .psm1 loads.
    if ((-not $PSBoundParameters.ContainsKey('OwnVersion')) -and $PSCommandPath) {
        $ownManifest = [System.IO.Path]::ChangeExtension($PSCommandPath, '.psd1')
        if (Test-Path -LiteralPath $ownManifest) { $OwnVersion = & $readVersion $ownManifest }
    }
    $versionKnown = ($null -ne $OwnVersion) -and ($OwnVersion -gt [version]'0.0')
    $isCompatible = {
        param([version] $Version)
        if (-not $versionKnown) { return $true }
        return (($Version.Major -eq $OwnVersion.Major) -and ($Version.Minor -eq $OwnVersion.Minor) -and ($Version -ge $OwnVersion))
    }

    $loaded = @(Get-Module -Name $ModuleName -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending)
    $loadedCompatible = @($loaded | Where-Object { & $isCompatible $_.Version }) | Select-Object -First 1
    if ($loadedCompatible) {
        Import-Module -ModuleInfo $loadedCompatible -ErrorAction Stop
        return
    }

    $found = @()

    # Tier 1: the sibling folder.
    $tier = @()
    $parent = Split-Path -Path $ModuleRoot -Parent
    if ($parent) {
        $manifest = Join-Path -Path $parent -ChildPath (Join-Path $ModuleName "$ModuleName.psd1")
        if (Test-Path -LiteralPath $manifest) {
            $version = & $readVersion $manifest
            if ($version) { $tier += [pscustomobject]@{ Path = $manifest; Version = $version } }
        }
    }
    $found += , $tier

    # Tier 2: sibling version folders. Only when this module itself sits in a version folder (<Modules>/<name>/<version>).
    $tier = @()
    $ownLeaf = [version] '0.0'
    if ($parent -and [version]::TryParse((Split-Path -Path $ModuleRoot -Leaf), [ref] $ownLeaf)) {
        $modulesRoot = Split-Path -Path $parent -Parent
        if ($modulesRoot) {
            $sharedBase = Join-Path -Path $modulesRoot -ChildPath $ModuleName
            if (Test-Path -LiteralPath $sharedBase) {
                foreach ($dir in @(Get-ChildItem -LiteralPath $sharedBase -Directory -ErrorAction SilentlyContinue)) {
                    $dirVersion = [version] '0.0'
                    if (-not [version]::TryParse($dir.Name, [ref] $dirVersion)) { continue }
                    $manifest = Join-Path -Path $dir.FullName -ChildPath "$ModuleName.psd1"
                    if (Test-Path -LiteralPath $manifest) {
                        $version = & $readVersion $manifest
                        if ($version) { $tier += [pscustomobject]@{ Path = $manifest; Version = $version } }
                    }
                }
            }
        }
    }
    $found += , $tier

    # Tier 3: PSModulePath.
    $tier = @()
    foreach ($item in @(Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue)) {
        if ($item.Path) { $tier += [pscustomobject]@{ Path = $item.Path; Version = $item.Version } }
    }
    $found += , $tier

    foreach ($tier in $found) {
        $match = @($tier | Where-Object { & $isCompatible $_.Version } | Sort-Object -Property Version -Descending) | Select-Object -First 1
        if ($match) {
            # Remove the stale copies first: -Force alone would leave two modules of the same name loaded.
            foreach ($stale in $loaded) { Remove-Module -ModuleInfo $stale -Force -ErrorAction SilentlyContinue }
            Import-Module -Name $match.Path -ErrorAction Stop
            return
        }
    }

    $needs = "$ModuleName $($OwnVersion.Major).$($OwnVersion.Minor).x, version $OwnVersion or newer"
    $message = "Cannot load $ModuleName for module version ${OwnVersion}: it needs $needs."
    $seen = @($loaded | ForEach-Object { "$($_.Version) (loaded)" }) + @($found | ForEach-Object { $_ } | ForEach-Object { "$($_.Version) ($($_.Path))" })
    if ($seen.Count -gt 0) {
        $message += " Found only: $($seen -join '; ')."
    } else {
        $message += " It was not found."
    }
    $message += " Install matching versions of every psfdx module (Install-Module psfdx, or reinstall from the same release)"
    if ($loaded.Count -gt 0) { $message += ", then start a new session or run Remove-Module $ModuleName -Force" }
    throw ($message + '.')
}

Import-PsfdxSharedModule

#region Authentication & Orgs

function Connect-Salesforce {
    <#
    .SYNOPSIS
    Logs in to an org in a web browser and saves the authorization.

    .DESCRIPTION
    Opens the login page of Salesforce in your browser. After you sign in, the Salesforce CLI stores the authorization on this computer so other psfdx cmdlets can use the org. Use -Sandbox for a sandbox, or -CustomUrl for a My Domain or other login URL.

    .PARAMETER Sandbox
    Log in through the sandbox login host. psfdx passes --instance-url https://test.salesforce.com. Use -CustomUrl instead for a different host.

    .PARAMETER CustomUrl
    URL of the instance that the org lives on. Passed to sf as --instance-url.

    .PARAMETER Alias
    Alias for the org. Passed to sf as --alias.

    .PARAMETER SetDefault
    Set the authenticated org as the default that all org-related commands run against. Adds --set-default.

    .PARAMETER SetDefaultDevHub
    Set the authenticated org as the default Dev Hub. Adds --set-default-dev-hub.

    .PARAMETER Browser
    Browser in which to open the org. Passed to sf as --browser. Valid values: chrome, edge, firefox.

    .PARAMETER OAuthClientId
    OAuth client ID (also called consumer key) of your custom connected app. Passed to sf as --client-id.

    .PARAMETER ClientApp
    Name that saves this login as a separate authorization for the same user, so you can log in to one org with more than one connected app. Passed to sf as --client-app. Use the same name with Disconnect-Salesforce -ClientApp to log it out.

    .PARAMETER Scopes
    OAuth scopes to request, separated by spaces, for example "api web refresh_token". Passed to sf as --scopes. Use it with your own connected app (-OAuthClientId).

    .PARAMETER Username
    User name to log in as, which pre-fills the login page. Passed to sf as --username.

    .EXAMPLE
    Connect-Salesforce -Alias prod -SetDefault
    Log in to production, give the org the alias prod and make it the default target org.

    .EXAMPLE
    Connect-Salesforce -Sandbox -Alias uat
    Log in to a sandbox.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org login web (plugin @salesforce/plugin-auth)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Sandbox = --instance-url https://test.salesforce.com; -CustomUrl = --instance-url; -Alias = --alias; -SetDefault = --set-default; -SetDefaultDevHub = --set-default-dev-hub; -Browser = --browser; -OAuthClientId = --client-id; -ClientApp = --client-app; -Scopes = --scopes; -Username = --username.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-auth

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $Sandbox,
        [Parameter(Mandatory = $false)][string] $CustomUrl,

        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][switch] $SetDefaultDevHub,

        [Parameter(Mandatory = $false)][string][ValidateSet('chrome', 'edge', 'firefox')] $Browser,
        [Parameter(Mandatory = $false)][string] $OAuthClientId,
        [Parameter(Mandatory = $false)][string] $ClientApp,
        [Parameter(Mandatory = $false)][string] $Scopes,
        [Parameter(Mandatory = $false)][string] $Username
    )

    $arguments = @('org', 'login', 'web')
    if ($Sandbox) { $arguments += @('--instance-url', 'https://test.salesforce.com') }
    if ($CustomUrl) { $arguments += @('--instance-url', $CustomUrl) }

    if ($Alias) { $arguments += @('--alias', $Alias) }
    if ($SetDefault) { $arguments += '--set-default' }
    if ($SetDefaultDevHub) { $arguments += '--set-default-dev-hub' }

    if ($Browser) { $arguments += @('--browser', $Browser) }
    if ($OAuthClientId) { $arguments += @('--client-id', $OAuthClientId) }
    if ($ClientApp) { $arguments += @('--client-app', $ClientApp) }
    if ($Scopes) { $arguments += @('--scopes', $Scopes) }
    if ($Username) { $arguments += @('--username', $Username) }

    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    Show-SalesforceResult -Result $result
}

function Connect-SalesforceAuthUrl {
    <#
    .SYNOPSIS
    Logs in to an org with a Salesforce DX authorization URL stored in a file.

    .DESCRIPTION
    Runs sf org login sfdx-url with the file you give. The result has the access token and auth URL removed unless you pass -IncludeToken. Keep the file safe: anyone who has it can log in as that user.

    .PARAMETER SfdxUrlFile
    Path to a file that contains the Salesforce DX authorization URL. Passed to sf as --sfdx-url-file. Required.

    .PARAMETER Alias
    Alias for the org. Passed to sf as --alias.

    .PARAMETER SetDefault
    Set the authenticated org as the default that all org-related commands run against. Adds --set-default.

    .PARAMETER SetDefaultDevHub
    Set the authenticated org as the default Dev Hub. Adds --set-default-dev-hub.

    .PARAMETER IncludeToken
    Return the CLI result as it is. Current CLI versions do not return tokens or auth URLs for this command, so this may change nothing. Without it psfdx removes accessToken, refreshToken, sfdxAuthUrl, password, clientSecret and privateKey from the result.

    .EXAMPLE
    Connect-SalesforceAuthUrl -SfdxUrlFile .\auth.txt -Alias ci -SetDefault
    Log in from the file and make the org the default.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org login sfdx-url (plugin @salesforce/plugin-auth)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --sfdx-url-stdin
    Parameter to flag: -SfdxUrlFile = --sfdx-url-file; -Alias = --alias; -SetDefault = --set-default; -SetDefaultDevHub = --set-default-dev-hub.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-auth

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $SfdxUrlFile,

        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][switch] $SetDefaultDevHub,
        [Parameter(Mandatory = $false)][switch] $IncludeToken
    )

    if (-not (Test-Path -LiteralPath $SfdxUrlFile)) {
        throw "File does not exist: $SfdxUrlFile"
    }

    $arguments = @('org', 'login', 'sfdx-url', '--sfdx-url-file', $SfdxUrlFile)
    if ($Alias) { $arguments += @('--alias', $Alias) }
    if ($SetDefault) { $arguments += '--set-default' }
    if ($SetDefaultDevHub) { $arguments += '--set-default-dev-hub' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $details = Show-SalesforceResult -Result $result

    # -IncludeToken only passes through what the CLI returned. Current CLI versions do not
    # return tokens or auth URLs from 'sf org login sfdx-url --json', so these may be absent.
    if ($IncludeToken) {
        return $details
    }

    return Remove-SalesforceSensitiveProperty -InputObject $details
}

function Remove-SalesforceSensitiveProperty {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][AllowNull()] $InputObject
    )

    if ($null -eq $InputObject) { return $InputObject }

    $sensitiveKeys = @('accessToken', 'refreshToken', 'sfdxAuthUrl', 'password', 'clientSecret', 'privateKey')
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        return @($InputObject | ForEach-Object {
            if ($_ -is [psobject] -and -not ($_ -is [string])) {
                $_ | Select-Object -Property * -ExcludeProperty $sensitiveKeys
            } else {
                $_
            }
        })
    }

    if ($InputObject -is [psobject] -and -not ($InputObject -is [string])) {
        return $InputObject | Select-Object -Property * -ExcludeProperty $sensitiveKeys
    }

    return $InputObject
}

function Disconnect-Salesforce {
    <#
    .SYNOPSIS
    Logs out of one org, or all orgs, and removes the saved authorization.

    .DESCRIPTION
    Runs sf org logout. The authorization is removed from this computer; scratch orgs and sandboxes are not deleted. Asks for confirmation and supports -WhatIf.

    .PARAMETER All
    Log out of every org this computer is authorized for. Use it instead of -TargetOrg. Required in the All parameter set.

    .PARAMETER TargetOrg
    Username or alias of the target org. Passed to sf as --target-org. Required in the TargetOrg parameter set.

    .PARAMETER ClientApp
    Name of the client app login to log out of, the name given to Connect-Salesforce -ClientApp. Passed to sf as --client-app. Use it with -TargetOrg.

    .PARAMETER NoPrompt
    Don't prompt for confirmation. Adds --no-prompt.

    .EXAMPLE
    Disconnect-Salesforce -TargetOrg dev1 -WhatIf
    Show what would happen without logging out.

    .EXAMPLE
    Disconnect-Salesforce -All -NoPrompt -Confirm:$false
    Log out of every org without any prompt (for example in a clean-up script).

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org logout (plugin @salesforce/plugin-auth)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -All = --all; -TargetOrg = --target-org; -ClientApp = --client-app; -NoPrompt = --no-prompt.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-auth

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(DefaultParameterSetName = 'TargetOrg', SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'All')][switch] $All,
        [Parameter(Mandatory = $true, ParameterSetName = 'TargetOrg')][string] $TargetOrg,
        [Parameter(Mandatory = $false, ParameterSetName = 'TargetOrg')][string] $ClientApp,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    $arguments = @('org', 'logout')
    if ($PSCmdlet.ParameterSetName -eq 'All') {
        $arguments += '--all'
    } else {
        $arguments += @('--target-org', $TargetOrg)
        if ($ClientApp) { $arguments += @('--client-app', $ClientApp) }
    }
    if ($NoPrompt) { $arguments += '--no-prompt' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $target = if ($PSCmdlet.ParameterSetName -eq 'All') { 'all authenticated orgs' } else { $TargetOrg }
    if ($PSCmdlet.ShouldProcess($target, 'Log out of org')) {
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        Show-SalesforceResult -Result $result
    }
}

function Connect-SalesforceJwt {
    <#
    .SYNOPSIS
    Logs in to an org without a browser, using a JSON web token and a private key.

    .DESCRIPTION
    Runs sf org login jwt with the connected app's consumer key, the user name and the private key file. It is meant for CI. The key file must exist; its content is never read or printed by psfdx. The login host is https://login.salesforce.com, or https://test.salesforce.com with -Sandbox.

    .PARAMETER ConsumerKey
    OAuth client ID (also called consumer key) of your custom connected app. Passed to sf as --client-id. Required.

    .PARAMETER TargetOrg
    Username of the user logging in. Passed to sf as --username. Required.

    .PARAMETER JwtKeyfile
    Path to a file containing the private key. Passed to sf as --jwt-key-file. Required.

    .PARAMETER Sandbox
    Log in at https://test.salesforce.com. psfdx always passes --instance-url: production by default, the sandbox host with this switch.

    .PARAMETER Alias
    Alias for the org. Passed to sf as --alias.

    .PARAMETER SetDefault
    Set the authenticated org as the default that all org-related commands run against. Adds --set-default.

    .PARAMETER SetDefaultDevHub
    Set the authenticated org as the default Dev Hub. Adds --set-default-dev-hub.

    .EXAMPLE
    Connect-SalesforceJwt -ConsumerKey $key -TargetOrg ci@example.com -JwtKeyfile .\server.key -Alias ci -SetDefault
    Log in a CI user and make it the default target org.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org login jwt (plugin @salesforce/plugin-auth)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ConsumerKey = --client-id; -TargetOrg = --username; -JwtKeyfile = --jwt-key-file; -Alias = --alias; -SetDefault = --set-default; -SetDefaultDevHub = --set-default-dev-hub.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-auth

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ConsumerKey,
        [Parameter(Mandatory = $true)][string] $TargetOrg,
        [Parameter(Mandatory = $true)][string] $JwtKeyfile,
        [Parameter(Mandatory = $false)][switch] $Sandbox,

        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][switch] $SetDefaultDevHub
    )
    if (-not(Test-Path $JwtKeyfile)) {
        throw "File does not exist: $JwtKeyfile"
    }

    $url = "https://login.salesforce.com"
    if ($Sandbox) { $url = "https://test.salesforce.com" }

    $arguments = @('org', 'login', 'jwt', '--client-id', $ConsumerKey, '--username', $TargetOrg, '--jwt-key-file', $JwtKeyfile, '--instance-url', $url)
    if ($Alias) { $arguments += @('--alias', $Alias) }
    if ($SetDefault) { $arguments += '--set-default' }
    if ($SetDefaultDevHub) { $arguments += '--set-default-dev-hub' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $details = Show-SalesforceResult -Result $result
    return Remove-SalesforceSensitiveProperty -InputObject $details
}

function Open-Salesforce {
    <#
    .SYNOPSIS
    Opens an org in your browser, or prints its login URL.

    .DESCRIPTION
    Runs sf org open. The URL contains a session token, so treat it like a password; -UrlOnly prints it instead of opening a browser.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .PARAMETER UrlOnly
    Display navigation URL, but don't launch browser. Adds --url-only.

    .PARAMETER Browser
    Browser where the org opens. Passed to sf as --browser. Valid values: chrome, edge, firefox.

    .PARAMETER BrowserPrivateMode
    Open the org in the browser's private (incognito) mode. A switch: adds --private, which takes no value.

    .PARAMETER Path
    Page to open, relative to the org, for example /lightning/setup/SetupOneHome/home. Passed to sf as --path.

    .PARAMETER SourceFile
    Path of a local file in the project. The CLI opens that component in the org, for example a Lightning page in the builder or an Apex class in the viewer. Passed to sf as --source-file. The file must exist.

    .EXAMPLE
    Open-Salesforce -TargetOrg dev1
    Open the org in the default browser.

    .EXAMPLE
    Open-Salesforce -TargetOrg dev1 -UrlOnly
    Print the login URL only.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org open (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org; -UrlOnly = --url-only; -Browser = --browser; -BrowserPrivateMode = --private; -Path = --path; -SourceFile = --source-file.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-org

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UrlOnly,
        [Parameter(Mandatory = $false)][string][ValidateSet('chrome', 'edge', 'firefox')] $Browser,
        [Parameter(Mandatory = $false)][switch] $BrowserPrivateMode,
        [Parameter(Mandatory = $false)][string] $Path,
        [Parameter(Mandatory = $false)][string] $SourceFile
    )
    if ($SourceFile -and -not (Test-Path -LiteralPath $SourceFile)) { throw "Source file '$SourceFile' does not exist." }
    $arguments = @('org', 'open')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($Browser) { $arguments += @('--browser', $Browser) }
    if ($BrowserPrivateMode) { $arguments += '--private' }
    if ($UrlOnly) { $arguments += '--url-only' }
    if ($Path) { $arguments += @('--path', $Path) }
    if ($SourceFile) { $arguments += @('--source-file', $SourceFile) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

function Get-SalesforceConnections {
    <#
    .SYNOPSIS
    Lists the orgs this computer is logged in to.

    .DESCRIPTION
    Runs sf org list and returns one object per org (orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias). Scratch orgs are not included here; use Get-SalesforceScratchOrgs for those.

    .PARAMETER ShowVerboseDetails
    List more information about each org. Adds --verbose.

    .EXAMPLE
    Get-SalesforceConnections | Format-Table username, alias, connectedStatus
    A quick overview of connected orgs.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org list (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -ShowVerboseDetails = --verbose.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-org

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $ShowVerboseDetails
    )
    $arguments = @('org', 'list')
    if ($ShowVerboseDetails) { $arguments += '--verbose' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams

    $details = Show-SalesforceResult -Result $result

    # Exclude scratch orgs. Older CLI versions return 'nonScratchOrgs'; newer ones may only
    # return the 'devHubs', 'sandboxes' and 'other' groups. Absent groups are tolerated.
    $orgs = @()
    if ($null -ne $details) {
        if ($null -ne $details.nonScratchOrgs) {
            $orgs = @($details.nonScratchOrgs)
        } else {
            foreach ($group in @('devHubs', 'sandboxes', 'other')) {
                if ($null -ne $details.$group) { $orgs += @($details.$group) }
            }
        }
    }
    # Only these fields are returned, so tokens and auth URLs are never passed on.
    return $orgs | Select-Object orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias
}

function Repair-SalesforceConnections {
    <#
    .SYNOPSIS
    Removes expired and deleted orgs from the list of connections.

    .DESCRIPTION
    Runs sf org list --clean, which checks every org and offers to remove the ones that no longer exist or whose scratch org has expired. Without -NoPrompt the CLI asks first. It returns the CLI's text output.

    .PARAMETER NoPrompt
    Don't prompt for confirmation. Adds --no-prompt.

    .EXAMPLE
    Repair-SalesforceConnections
    Interactive clean-up.

    .EXAMPLE
    Repair-SalesforceConnections -NoPrompt
    Clean up without asking.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org list (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -NoPrompt = --no-prompt.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-org

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][switch] $NoPrompt)
    $arguments = @('org', 'list', '--clean')
    if ($NoPrompt) { $arguments += '--no-prompt' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

function Get-SalesforceOrgDetails {
    <#
    .SYNOPSIS
    Shows the details of one org: its ID, instance URL, user name, status and API version.

    .DESCRIPTION
    Runs sf org display. The result has the access token and the Salesforce DX authorization URL removed, so the output is safe to log or share, unless you pass -IncludeToken. Anyone who has the token or the URL can act as that user, so only use -IncludeToken when you need it.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .PARAMETER ShowVerboseDetails
    Include more details, such as the Salesforce DX authorization URL (removed again unless you pass -IncludeToken). Adds --verbose.

    .PARAMETER IncludeToken
    Return the CLI result as it is, with accessToken and sfdxAuthUrl. Without it psfdx removes accessToken, refreshToken, sfdxAuthUrl, password, clientSecret and privateKey from the result.

    .EXAMPLE
    Get-SalesforceOrgDetails -TargetOrg dev1
    Show the org ID, instance URL and status of dev1, without any token.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org display (plugin @salesforce/plugin-org)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org; -ShowVerboseDetails = --verbose.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-org

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $ShowVerboseDetails,
        [Parameter(Mandatory = $false)][switch] $IncludeToken
    )
    $arguments = @('org', 'display')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    if ($ShowVerboseDetails) { $arguments += '--verbose' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $details = Show-SalesforceResult -Result $result
    if ($IncludeToken) { return $details }
    return Remove-SalesforceSensitiveProperty -InputObject $details
}

function Get-SalesforceAuthorizations {
    <#
    .SYNOPSIS
    Lists every authorization the Salesforce CLI has saved on this computer.

    .DESCRIPTION
    Runs sf org list auth and returns one object per saved authorization (user name, org ID, instance URL, aliases, how it was authorized and whether it has expired). Unlike Get-SalesforceConnections it does not contact the orgs, so it is quick and works offline. Tokens and authorization URLs are removed from the result.

    .EXAMPLE
    Get-SalesforceAuthorizations | Format-Table username, aliases, instanceUrl
    A quick overview of the saved logins.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org list auth (plugin @salesforce/plugin-auth)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-auth

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param()
    $arguments = @('org', 'list', 'auth', '--json')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $details = Show-SalesforceResult -Result $result
    return Remove-SalesforceSensitiveProperty -InputObject $details
}

function Connect-SalesforceAccessToken {
    <#
    .SYNOPSIS
    Logs in to an org with an access token you already have.

    .DESCRIPTION
    Runs sf org login access-token. Give the org's instance URL and the access token as a SecureString. The token is handed to the CLI in the SF_ACCESS_TOKEN environment variable of the sf process only, never on the command line, and the variable is put back to its earlier value afterwards. The login is saved on this computer so other psfdx cmdlets can use the org. The authorization cannot be refreshed, so it stops working when the token expires. The URL must be an absolute https URL, because the token is sent to it. Tokens and authorization URLs are removed from the result.

    .PARAMETER InstanceUrl
    URL of the org, for example https://mycompany.my.salesforce.com. Must be an absolute https:// URL. Passed to sf as --instance-url. Required.

    .PARAMETER AccessToken
    The access token, as a SecureString, for example (Read-Host -AsSecureString). Passed to sf in the SF_ACCESS_TOKEN environment variable. Required.

    .PARAMETER Alias
    Alias for the org. Passed to sf as --alias.

    .PARAMETER SetDefault
    Set the authenticated org as the default that all org-related commands run against. Adds --set-default.

    .PARAMETER SetDefaultDevHub
    Set the authenticated org as the default Dev Hub. Adds --set-default-dev-hub.

    .PARAMETER NoPrompt
    Don't prompt for confirmation, for example before overwriting an existing login. Adds --no-prompt.

    .EXAMPLE
    Connect-SalesforceAccessToken -InstanceUrl https://mycompany.my.salesforce.com -AccessToken (Read-Host -AsSecureString) -Alias ci -NoPrompt
    Log in with a token that you type at the prompt.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org login access-token (plugin @salesforce/plugin-auth)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -InstanceUrl = --instance-url; -Alias = --alias; -SetDefault = --set-default; -SetDefaultDevHub = --set-default-dev-hub; -NoPrompt = --no-prompt. -AccessToken is not a flag: the CLI reads it from the SF_ACCESS_TOKEN environment variable.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-auth

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $InstanceUrl,
        [Parameter(Mandatory = $true)][System.Security.SecureString] $AccessToken,
        [Parameter(Mandatory = $false)][string] $Alias,
        [Parameter(Mandatory = $false)][switch] $SetDefault,
        [Parameter(Mandatory = $false)][switch] $SetDefaultDevHub,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )

    # The token is sent to this URL, so it must be https.
    Assert-SalesforceHttpsUrl -Url $InstanceUrl -What '-InstanceUrl'

    $arguments = @('org', 'login', 'access-token', '--instance-url', $InstanceUrl)
    if ($Alias) { $arguments += @('--alias', $Alias) }
    if ($SetDefault) { $arguments += '--set-default' }
    if ($SetDefaultDevHub) { $arguments += '--set-default-dev-hub' }
    if ($NoPrompt) { $arguments += '--no-prompt' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters

    # The token goes in the environment of the sf process only, so it is not in the argument list or in -Verbose output.
    $variable = 'SF_ACCESS_TOKEN'
    $previous = [Environment]::GetEnvironmentVariable($variable)
    try {
        [Environment]::SetEnvironmentVariable($variable, (ConvertTo-SalesforcePlainSecret -Value $AccessToken -Name 'AccessToken'))
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    }
    finally {
        [Environment]::SetEnvironmentVariable($variable, $previous)
    }
    $details = Show-SalesforceResult -Result $result
    return Remove-SalesforceSensitiveProperty -InputObject $details
}

#endregion

#region Aliases & Limits

function Get-SalesforceAlias {
    <#
    .SYNOPSIS
    Lists the org aliases set on this computer.

    .DESCRIPTION
    Runs sf alias list and returns the aliases, each with the value it points to. Reads local CLI configuration only; it does not contact an org.

    .EXAMPLE
    Get-SalesforceAlias
    List every alias.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf alias list (plugin @salesforce/plugin-settings)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-settings

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param()
    $arguments = @('alias', 'list', '--json')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Add-SalesforceAlias {
    <#
    .SYNOPSIS
    Sets a local alias for an org so you can use a short name instead of its username.

    .DESCRIPTION
    Stores the alias in the Salesforce CLI configuration on this computer; nothing changes in the org. Once set, the alias works anywhere a psfdx cmdlet takes -TargetOrg.

    .PARAMETER Alias
    The alias to create, for example prod or dev1. Setting an alias that already exists replaces it. Required.

    .PARAMETER TargetOrg
    Username, or an existing alias, that the new alias should point to. Required.

    .EXAMPLE
    Add-SalesforceAlias -Alias dev1 -TargetOrg user@example.com.dev1
    Create the alias dev1 for that username.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf alias set (plugin @salesforce/plugin-settings)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-settings

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Alias,
        [Parameter(Mandatory = $true)][string] $TargetOrg
    )
    $arguments = @('alias', 'set', "$Alias=$TargetOrg")
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

function Remove-SalesforceAlias {
    <#
    .SYNOPSIS
    Removes one org alias from this computer.

    .DESCRIPTION
    Runs sf alias unset. Only the local alias is removed; the org is not touched.

    .PARAMETER Alias
    The alias to remove. Required.

    .EXAMPLE
    Remove-SalesforceAlias -Alias dev1
    Remove the alias dev1.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf alias unset (plugin @salesforce/plugin-settings)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --all, --no-prompt
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-settings

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Alias)
    $arguments = @('alias', 'unset', $Alias)
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

#endregion

#region Limits & Usage

function Get-SalesforceLimits {
    <#
    .SYNOPSIS
    Shows the org's limits and how much of each is left.

    .DESCRIPTION
    Runs sf org list limits and returns one object per limit with its name, max and remaining values.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceLimits -TargetOrg prod | Where-Object remaining -lt 1000
    Limits that are nearly used up.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org list limits (plugin @salesforce/plugin-limits)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-limits

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $arguments = @('org', 'list', 'limits')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceSObjectRecordCount {
    <#
    .SYNOPSIS
    Shows how many records objects have in an org.

    .DESCRIPTION
    Runs sf org list sobject record-counts. Without -SObject the CLI counts the standard and custom objects that it can count; with -SObject it counts only the objects you name. It reads the counts the org already keeps, so they can differ a little from a SOQL COUNT().

    .PARAMETER SObject
    API names of the objects to count, for example Account, Contact or Invoice__c. Each name is passed as its own --sobject. Names may contain only letters, digits and underscores.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceSObjectRecordCount -SObject Account, Contact -TargetOrg dev1
    Record counts of Account and Contact.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org list sobject record-counts (plugin @salesforce/plugin-limits)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -SObject = --sobject; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-limits

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*\z')][string[]] $SObject,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('org', 'list', 'sobject', 'record-counts')
    foreach ($name in @($SObject | Where-Object { $_ })) { $arguments += @('--sobject', $name) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Get-SalesforceDataStorage {
    <#
    .SYNOPSIS
    Shows how much data storage an org has used.

    .DESCRIPTION
    Reads the org limits with Get-SalesforceLimits and returns the DataStorageMB entry with InUse and Usage (percentage) added. Returns nothing if the org does not report that limit.

    .PARAMETER TargetOrg
    Username or alias of the org to check. If omitted, the Salesforce CLI uses the default target org (passed on to Get-SalesforceLimits).

    .EXAMPLE
    Get-SalesforceDataStorage -TargetOrg prod
    Data storage used, in MB and as a percentage.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Get-SalesforceLimits. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $values = Get-SalesforceLimits -TargetOrg $TargetOrg | Where-Object Name -eq "DataStorageMB"
    if ($null -eq $values) {
        Write-Verbose "No DataStorageMB limit reported for this org"
        return $null
    }
    $inUse = $values.max + ($values.remaining * -1)
    $values | Add-Member -NotePropertyName InUse -NotePropertyValue $inUse
    $values | Add-Member -NotePropertyName Usage -NotePropertyValue (Get-SalesforceUsagePercentage -InUse $inUse -Max $values.max)
    return $values
}

function Get-SalesforceApiUsage {
    <#
    .SYNOPSIS
    Shows how much of the daily API request limit an org has used.

    .DESCRIPTION
    Reads the org limits with Get-SalesforceLimits and returns the DailyApiRequests entry with a Usage percentage added (used divided by max). Returns nothing if the org does not report that limit.

    .PARAMETER TargetOrg
    Username or alias of the org to check. If omitted, the Salesforce CLI uses the default target org (passed on to Get-SalesforceLimits).

    .EXAMPLE
    Get-SalesforceApiUsage -TargetOrg prod
    See the API usage of the production org.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Get-SalesforceLimits. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][string] $TargetOrg)
    $values = Get-SalesforceLimits -TargetOrg $TargetOrg | Where-Object Name -eq "DailyApiRequests"
    if ($null -eq $values) {
        Write-Verbose "No DailyApiRequests limit reported for this org"
        return $null
    }
    $inUse = $values.max + ($values.remaining * -1)
    $values | Add-Member -NotePropertyName Usage -NotePropertyValue (Get-SalesforceUsagePercentage -InUse $inUse -Max $values.max)
    return $values
}

function Get-SalesforceUsagePercentage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowNull()][System.Nullable[double]] $InUse,
        [Parameter(Mandatory = $true)][AllowNull()][System.Nullable[double]] $Max
    )
    if ((-not $Max) -or ($Max -eq 0)) { return $null }
    return ($InUse / $Max).ToString('P')
}

#endregion

#region Data Management

function Select-SalesforceRecords {
    <#
    .SYNOPSIS
    Runs a SOQL query and returns the records as objects.

    .DESCRIPTION
    Runs sf data query with --query or --file. With the default -ResultFormat json the records are returned as objects without their attributes property; an empty result returns nothing (wrap the call in @() for an empty array). With human or csv the CLI text is returned as it is. A failing query throws the CLI message. The query text is passed as one argument, so quotes and special characters need no escaping.

    .PARAMETER Query
    SOQL query to execute. Passed to sf as --query.

    .PARAMETER File
    File that contains the SOQL query. Passed to sf as --file.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .PARAMETER UseToolingApi
    Use Tooling API so you can run queries on Tooling API objects. Adds --use-tooling-api.

    .PARAMETER IncludeDeletedRows
    Include deleted records. By default, deleted records are not returned. Adds --all-rows.

    .PARAMETER ResultFormat
    Format to display the results; the --json flag overrides this flag. Default: json. Valid values: human, json, csv.

    .PARAMETER OutputFile
    File where records are written; only CSV and JSON output formats are supported. Passed to sf as --output-file.

    .EXAMPLE
    Select-SalesforceRecords -Query 'SELECT Id, Name FROM Account LIMIT 5' -TargetOrg dev1
    Five accounts as objects.

    .EXAMPLE
    Select-SalesforceRecords -Query 'SELECT Id, Name FROM Account' -ResultFormat csv -OutputFile .\accounts.csv -TargetOrg dev1
    Save the result as CSV.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data query (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Query = --query; -File = --file; -TargetOrg = --target-org; -UseToolingApi = --use-tooling-api; -IncludeDeletedRows = --all-rows; -ResultFormat = --result-format; -OutputFile = --output-file.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-data

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Query,
        [Parameter(Mandatory = $false)][string] $File,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi,
        [Parameter(Mandatory = $false)][switch] $IncludeDeletedRows,
        [Parameter(Mandatory = $false)][string][ValidateSet('human', 'json', 'csv')] $ResultFormat = 'json',
        [Parameter(Mandatory = $false)][string] $OutputFile
    )
    $arguments = @('data', 'query')
    if ($Query) { $arguments += @('--query', $Query) }
    if ($File) { $arguments += @('--file', $File) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) {
        $trimmedTargetOrg = $TargetOrg.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmedTargetOrg)) {
            $arguments += @('--target-org', $trimmedTargetOrg)
        }
    }
    if ($UseToolingApi) { $arguments += '--use-tooling-api' }
    if ($IncludeDeletedRows) { $arguments += '--all-rows' }

    $arguments += @('--result-format', $ResultFormat)
    if ($OutputFile) { $arguments += @('--output-file', $OutputFile) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams

    # csv and human output are not JSON, so hand them back untouched
    if ($ResultFormat -ne 'json') {
        return $result
    }

    $result = $result | ConvertFrom-Json
    if ($result.status -ne 0) {
        Write-Debug ($result | ConvertTo-Json -Depth 10)
        throw $result.message
    }
    # Exclude Salesforce's built-in 'attributes' metadata from each row
    if ($null -eq $result.result -or $null -eq $result.result.records) { return }
    return ($result.result.records | Select-Object -Property * -ExcludeProperty attributes)
}

function Get-SalesforceUsers {
    <#
    .SYNOPSIS
    Lists users of an org, newest login first.

    .DESCRIPTION
    Queries User (Id, Name, Username, Email, IsActive, LastLoginDate) through Select-SalesforceRecords, ordered by LastLoginDate descending. Values are escaped as SOQL literals.

    .PARAMETER Username
    Return only the user with this exact user name.

    .PARAMETER ActiveOnly
    Return only active users.

    .PARAMETER Limit
    Maximum number of users to return. Default 200. Default: 200.

    .PARAMETER TargetOrg
    Username or alias of the org to query. If omitted, the Salesforce CLI uses the default target org.

    .EXAMPLE
    Get-SalesforceUsers -ActiveOnly -Limit 20 -TargetOrg prod
    The 20 most recently active users.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Select-SalesforceRecords. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $ActiveOnly,
        [Parameter(Mandatory = $false)][int] $Limit = 200,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )

    $fields = 'Id, Name, Username, Email, IsActive, LastLoginDate'
    $query = "SELECT $fields FROM User"
    $filters = @()
    if ($ActiveOnly) { $filters += 'IsActive = true' }
    if ($Username)   { $filters += ('Username = ' + (ConvertTo-SalesforceSoqlLiteral -Value $Username)) }
    if ($filters.Count -gt 0) { $query += ' WHERE ' + ($filters -join ' AND ') }
    $query += ' ORDER BY LastLoginDate DESC'
    $query += " LIMIT $Limit"

    return Select-SalesforceRecords -Query $query -TargetOrg $TargetOrg -ResultFormat json
}

function New-SalesforceRecord {
    <#
    .SYNOPSIS
    Creates one record (sf data create record).

    .DESCRIPTION
    -FieldUpdates is the CLI's values string, for example "Name='Acme' Industry='Energy'". Supports -WhatIf and -Confirm; it does not prompt by default.

    .PARAMETER Type
    API name of the Salesforce or Tooling API object that you're inserting a record into. Passed to sf as --sobject. Required.

    .PARAMETER FieldUpdates
    Values for the flags in the form <fieldName>=<value>, separate multiple pairs with spaces. Passed to sf as --values. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .PARAMETER UseToolingApi
    Use Tooling API so you can insert a record in a Tooling API object. Adds --use-tooling-api.

    .EXAMPLE
    New-SalesforceRecord -Type Account -FieldUpdates "Name='Acme'" -WhatIf

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data create record (plugin @salesforce/plugin-data)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --skip-assignment-rules
    Parameter to flag: -Type = --sobject; -FieldUpdates = --values; -TargetOrg = --target-org; -UseToolingApi = --use-tooling-api.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-data

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true)][string] $FieldUpdates,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    $arguments = @('data', 'create', 'record')
    $arguments += @('--sobject', $Type)
    $arguments += @('--values', $FieldUpdates)
    if ($UseToolingApi) { $arguments += '--use-tooling-api' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess("new $Type record", 'Create record')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Set-SalesforceRecord {
    <#
    .SYNOPSIS
    Updates one record by ID (sf data update record).

    .DESCRIPTION
    -Id can come from the pipeline (Id or RecordId property). -FieldUpdates is the CLI's values string, for example "Name='Acme' Active__c=true".
    Supports -WhatIf and -Confirm; it does not prompt by default.

    .PARAMETER Id
    ID of the record you're updating. Passed to sf as --record-id. Required. Alias: RecordId. Accepts input from the pipeline by property name.

    .PARAMETER Type
    API name of the Salesforce or Tooling API object that contains the record you're updating. Passed to sf as --sobject. Required.

    .PARAMETER FieldUpdates
    Fields that you're updating, in the format of <fieldName>=<value> pairs. Passed to sf as --values. Required.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .PARAMETER UseToolingApi
    Use Tooling API so you can update a record in a Tooling API object. Adds --use-tooling-api.

    .EXAMPLE
    Select-SalesforceRecords -Query "SELECT Id FROM Account WHERE Name = 'Old'" | Set-SalesforceRecord -Type Account -FieldUpdates "Name='New'" -WhatIf

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data update record (plugin @salesforce/plugin-data)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --skip-assignment-rules, --where
    Parameter to flag: -Id = --record-id; -Type = --sobject; -FieldUpdates = --values; -TargetOrg = --target-org; -UseToolingApi = --use-tooling-api.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-data

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)][Alias('RecordId')][string] $Id,
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true)][string] $FieldUpdates,
        [Parameter(Mandatory = $false)][string] $TargetOrg,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )
    process {
            $arguments = @('data', 'update', 'record')
        $arguments += @('--sobject', $Type)
        $arguments += @('--record-id', $Id)
        $arguments += @('--values', $FieldUpdates)
        if ($UseToolingApi) { $arguments += '--use-tooling-api' }
        if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
        $arguments += '--json'
        $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
        $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
        if (-not $PSCmdlet.ShouldProcess("$Type $Id", 'Update record')) { return }
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function Get-SalesforceRecord {
    <#
    .SYNOPSIS
    Gets one record, by ID or by field values (sf data get record).

    .DESCRIPTION
    Select the record with -Id, or with -Where, a hashtable of field values that identify exactly one record (the CLI reports an error for none
    or for several). They are alternatives: the CLI accepts only one. The record is returned as an object of its fields, without the internal
    attributes property. A value in -Where is passed to the CLI as Field='value'; because the CLI has no way to escape a quote inside a value, a
    value that contains a single quote, a double quote or a line break is refused. For anything more complex use Select-SalesforceRecords.
    A record that does not exist makes the cmdlet throw the CLI's message.

    .PARAMETER Type
    API name of the Salesforce or Tooling API object that you're retrieving a record from. Passed to sf as --sobject. Required.

    .PARAMETER Id
    ID of the record you're retrieving. Passed to sf as --record-id. Required in the ById parameter set. Alias: RecordId. Accepts input from the pipeline by property name.

    .PARAMETER Where
    List of <fieldName>=<value> pairs that identify the record you want to display. Passed to sf as --where. Required in the ByFields parameter set.

    .PARAMETER UseToolingApi
    Use Tooling API so you can retrieve a record from a Tooling API object. Adds --use-tooling-api.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceRecord -Type Account -Id 001xx000003DGb2AAG -TargetOrg myorg

    .EXAMPLE
    Get-SalesforceRecord -Type Account -Where @{ Name = 'Acme Corporation' } -TargetOrg myorg

    .EXAMPLE
    Select-SalesforceRecords -Query 'SELECT Id FROM Account LIMIT 5' | Get-SalesforceRecord -Type Account
    The Id of each piped record is used (a RecordId property works too). The object type is not in a query result, so -Type is always given.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data get record (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Type = --sobject; -Id = --record-id; -Where = --where; -UseToolingApi = --use-tooling-api; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-data

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    Param(
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true, ParameterSetName = 'ById', ValueFromPipelineByPropertyName = $true)][Alias('RecordId')][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $Id,
        [Parameter(Mandatory = $true, ParameterSetName = 'ByFields')][System.Collections.IDictionary] $Where,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    process {
        $objectName = ConvertTo-SalesforceSoqlIdentifier -Value $Type
        $arguments = @('data', 'get', 'record', '--sobject', $objectName)
        if ($PSCmdlet.ParameterSetName -eq 'ById') { $arguments += @('--record-id', $Id) } else { $arguments += @('--where', (ConvertTo-SalesforceRecordSelector -Where $Where)) }
        if ($UseToolingApi) { $arguments += '--use-tooling-api' }
        if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
        $arguments += '--json'
        $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        $record = Show-SalesforceResult -Result $result
        if ($null -eq $record) { throw "The Salesforce CLI returned no record for $objectName." }
        return ($record | Select-Object -Property * -ExcludeProperty attributes)
    }
}

function Remove-SalesforceRecord {
    <#
    .SYNOPSIS
    Deletes one record, by ID or by field values (sf data delete record).

    .DESCRIPTION
    Select the record as for Get-SalesforceRecord: -Id, or -Where (field values that identify exactly one record). Asks for confirmation by default,
    naming the object, the record and the org; -WhatIf makes no CLI call. Returns the CLI's result (the deleted record's Id). A record that does not
    exist, or a -Where that matches several, makes the cmdlet throw the CLI's message, so nothing is hidden. Scripts that run unattended need
    -Confirm:$false.

    .PARAMETER Type
    API name of the Salesforce or Tooling API object that you're deleting a record from. Passed to sf as --sobject. Required.

    .PARAMETER Id
    ID of the record you're deleting. Passed to sf as --record-id. Required in the ById parameter set. Alias: RecordId. Accepts input from the pipeline by property name.

    .PARAMETER Where
    List of <fieldName>=<value> pairs that identify the record you want to delete. Passed to sf as --where. Required in the ByFields parameter set.

    .PARAMETER UseToolingApi
    Use Tooling API so you can delete a record from a Tooling API object. Adds --use-tooling-api.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Remove-SalesforceRecord -Type Account -Id 001xx000003DGb2AAG -TargetOrg myorg -WhatIf

    .EXAMPLE
    Remove-SalesforceRecord -Type Account -Where @{ Name = 'Test Account 42' } -TargetOrg myorg -Confirm:$false

    .EXAMPLE
    Select-SalesforceRecords -Query "SELECT Id FROM Account WHERE Name LIKE 'Test%'" | Remove-SalesforceRecord -Type Account -WhatIf
    Each piped record is confirmed and deleted on its own, so -WhatIf previews every delete. An empty query deletes nothing.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data delete record (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Type = --sobject; -Id = --record-id; -Where = --where; -UseToolingApi = --use-tooling-api; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-data

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ById')]
    Param(
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true, ParameterSetName = 'ById', ValueFromPipelineByPropertyName = $true)][Alias('RecordId')][ValidatePattern('^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?\z')][string] $Id,
        [Parameter(Mandatory = $true, ParameterSetName = 'ByFields')][System.Collections.IDictionary] $Where,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    process {
        $objectName = ConvertTo-SalesforceSoqlIdentifier -Value $Type
        $arguments = @('data', 'delete', 'record', '--sobject', $objectName)
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $arguments += @('--record-id', $Id)
            $what = "$objectName $Id"
        } else {
            $selector = ConvertTo-SalesforceRecordSelector -Where $Where
            $arguments += @('--where', $selector)
            $what = "$objectName where $selector"
        }
        if ($UseToolingApi) { $arguments += '--use-tooling-api' }
        if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
        $arguments += '--json'
        $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
        $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
        $orgLabel = 'the default org'
        if (-not [string]::IsNullOrWhiteSpace($TargetOrg)) { $orgLabel = "org $TargetOrg" }
        if (-not $PSCmdlet.ShouldProcess("$what in $orgLabel", 'Delete record')) { return }
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
        return Show-SalesforceResult -Result $result
    }
}

function ConvertTo-SalesforceRecordSelector {
    # Builds the value of --where: space-separated Field='value' pairs. Field names are validated, and a value that the CLI could not
    # read back safely (a quote of either kind, or a control character) is refused rather than guessed at.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary] $Where
    )
    if ($Where.Count -eq 0) { throw '-Where needs at least one field and value.' }
    $pairs = @()
    foreach ($key in $Where.Keys) {
        $field = ConvertTo-SalesforceSoqlIdentifier -Value ([string] $key)
        $value = [string] $Where[$key]
        if ([string]::IsNullOrEmpty($value)) { throw "The -Where value for '$field' is empty." }
        if ($value -match "['`"\x00-\x1F\x7F]") { throw "The -Where value for '$field' contains a quote or control character, which the CLI cannot take safely. Use -Id, or Select-SalesforceRecords." }
        $pairs += "$field='$value'"
    }
    return ($pairs -join ' ')
}

function Upsert-SalesforceRecord {
    <#
    .SYNOPSIS
    Creates or updates one record, matched by an external ID.

    .DESCRIPTION
    The CLI has no single-record upsert command, so this sends a PATCH to /services/data/vXX.X/sobjects/<Type>/<ExternalIdField>/<value> with sf api request rest. The body is written to a temporary file that is removed afterwards. The result says whether the record was Created or Updated and gives its Id when the API returns one.

    .PARAMETER Type
    API name of the object, for example Account. Required.

    .PARAMETER ExternalIdField
    API name of the external ID field used to find the record. Required.

    .PARAMETER ExternalId
    Value of the external ID. It is URL-escaped in the request path. Required.

    .PARAMETER Fields
    Hashtable of field API names and values to set, for example @{ Name = 'Acme' }. It must not be empty. Required.

    .PARAMETER ApiVersion
    REST API version to use, for example v62.0 or 62.0. If omitted, the latest version the org supports is used.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Upsert-SalesforceRecord -Type Account -ExternalIdField Ext_Id__c -ExternalId A-100 -Fields @{ Name = 'Acme' } -TargetOrg dev1
    Create or update the account whose Ext_Id__c is A-100.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf api request rest (plugin @salesforce/plugin-api)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --file, --header, --include, --stream-to-file
      Values psfdx cannot pass: --method POST, PUT, HEAD, DELETE, OPTIONS, TRACE
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.
    Also calls these psfdx cmdlets: Get-SalesforceLatestApiVersion.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-api

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    # The Salesforce CLI has no `sf data upsert record` (only `sf data upsert bulk`, a CSV job). A single-record upsert is the REST
    # call PATCH /services/data/vXX.X/sobjects/<Type>/<ExternalIdField>/<value>, which `sf api request rest` sends with the org's login.
    # Salesforce answers 201 when it created the record (body has the new Id). When it updated one, API v46.0 and later answer 200 with
    # the Id and created=false, and older versions answer 204 with no body. Id is $null when the response does not carry one.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Type,
        [Parameter(Mandatory = $true)][string] $ExternalIdField,
        [Parameter(Mandatory = $true)][string] $ExternalId,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary] $Fields,
        [Parameter(Mandatory = $false)][string] $ApiVersion,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $objectName = ConvertTo-SalesforceSoqlIdentifier -Value $Type
    $externalIdFieldName = ConvertTo-SalesforceSoqlIdentifier -Value $ExternalIdField
    if ([string]::IsNullOrWhiteSpace($ExternalId)) { throw 'ExternalId is required: an upsert without an external ID value cannot tell a create from an update.' }
    if ($ExternalId -match '[\x00-\x1F\x7F]') { throw 'ExternalId must not contain control characters.' }
    if ($Fields.Count -eq 0) { throw 'Fields is empty: give at least one field to set.' }

    $body = [ordered]@{}
    foreach ($key in $Fields.Keys) {
        $name = ConvertTo-SalesforceSoqlIdentifier -Value ([string] $key)
        if ($name -ieq 'Id') { throw "Fields must not contain Id: an upsert identifies the record by $externalIdFieldName." }
        $value = $Fields[$key]
        if ($value -is [datetime]) { $value = $value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [System.Globalization.CultureInfo]::InvariantCulture) }
        elseif ($value -is [datetimeoffset]) { $value = $value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [System.Globalization.CultureInfo]::InvariantCulture) }
        $body[$name] = $value
    }

    if ([string]::IsNullOrWhiteSpace($ApiVersion)) {
        $latestParams = @{}
        if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $latestParams['TargetOrg'] = $TargetOrg }
        $ApiVersion = Get-SalesforceLatestApiVersion @latestParams
        if ([string]::IsNullOrWhiteSpace($ApiVersion)) { throw 'Could not work out the org API version. Pass -ApiVersion, for example v62.0.' }
    }
    if ($ApiVersion -notmatch '^v?(\d{2,3}\.\d)\z') { throw "ApiVersion '$ApiVersion' is not valid. Use a form like v62.0 or 62.0." }
    $version = 'v' + $Matches[1]

    $url = "/services/data/$version/sobjects/$objectName/$externalIdFieldName/" + [uri]::EscapeDataString($ExternalId)

    # The body goes through a file: a JSON body on the command line would carry double quotes, which the Windows .cmd shim rejects.
    $bodyFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ('psfdx-upsert-' + [guid]::NewGuid().ToString('N') + '.json'))
    try {
        [System.IO.File]::WriteAllText($bodyFile, ($body | ConvertTo-Json -Compress -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
        $arguments = @('api', 'request', 'rest', $url, '--method', 'PATCH', '--body', "@$bodyFile")
        if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
        $arguments += '--json'
        $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
        $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    } finally {
        Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
    }

    $response = Show-SalesforceResult -Result $result
    $statusCode = 0
    if ($null -ne $response -and $null -ne $response.PSObject.Properties['statusCode']) { $statusCode = [int] $response.statusCode }
    $responseBody = $null
    if ($null -ne $response) { $responseBody = $response.body }

    if ($statusCode -eq 200 -or $statusCode -eq 201 -or $statusCode -eq 204) {
        $created = ($statusCode -eq 201)
        $id = $null
        if ($null -ne $responseBody -and $responseBody -isnot [string]) {
            if ($null -ne $responseBody.PSObject.Properties['id']) { $id = $responseBody.id }
            if ($statusCode -eq 200 -and $null -ne $responseBody.PSObject.Properties['created']) { $created = [bool] $responseBody.created }
        }
        return [pscustomobject]@{
            Operation       = $(if ($created) { 'Created' } else { 'Updated' })
            Created         = $created
            Id              = $id
            Type            = $objectName
            ExternalIdField = $externalIdFieldName
            ExternalId      = $ExternalId
            StatusCode      = $statusCode
        }
    }

    $detail = ''
    if ($responseBody -is [string]) { $detail = $responseBody }
    elseif ($null -ne $responseBody) { $detail = (@($responseBody) | ForEach-Object { if ($_.PSObject.Properties['message']) { "$($_.errorCode): $($_.message)" } else { [string] $_ } }) -join '; ' }
    if ($detail.Length -gt 300) { $detail = $detail.Substring(0, 300) + '...' }
    throw "Upsert of $objectName by $externalIdFieldName failed with HTTP status $statusCode. $detail".TrimEnd()
}

function Get-SalesforceRecordType {
    <#
    .SYNOPSIS
    Lists record types, optionally for one object.

    .DESCRIPTION
    Queries the RecordType object (Id, SobjectType, Name, DeveloperName, IsActive) through Select-SalesforceRecords. The object name is escaped as a SOQL literal.

    .PARAMETER ObjectType
    API name of the object whose record types you want, for example Account. Without it, record types of every object are returned. Required.

    .PARAMETER TargetOrg
    Username or alias of the org to query. If omitted, the Salesforce CLI uses the default target org.

    .EXAMPLE
    Get-SalesforceRecordType -ObjectType Account -TargetOrg dev1
    Record types of Account.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Select-SalesforceRecords. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectType,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $query = "SELECT Id, SobjectType, Name, DeveloperName, IsActive"
    $query += " FROM RecordType"
    if ($ObjectType) { $query += (' WHERE SobjectType = ' + (ConvertTo-SalesforceSoqlLiteral -Value $ObjectType)) }
    return Select-SalesforceRecords -Query $query -TargetOrg $TargetOrg
}

#endregion

#region Data Trees

# Wraps `sf data export tree` and `sf data import tree`: copy related records (parent and child) between orgs as JSON files.
# Both use the SObject Tree API, which handles at most 200 records per import and is meant for test data, not bulk loads (see
# Import-SalesforceBulkData for those).

function Export-SalesforceTreeData {
    <#
    .SYNOPSIS
    Exports records, with their related child records, to JSON files for Import-SalesforceTreeData (sf data export tree).

    .DESCRIPTION
    Each -Query is a SOQL query; a query with a subquery exports parent and children together. The queries go to the CLI unchanged, so use
    one line and no double quotes (the Windows CLI shim rejects line breaks and double quotes in an argument).
    Without -Plan the records are returned in Records and the CLI writes one JSON file per query. With -Plan the CLI writes one file per object and
    a plan file that references them, which Import-SalesforceTreeData -Plan reads; Files and PlanFile hold their paths. The CLI creates
    -OutputDirectory if it does not exist.

    .PARAMETER Query
    One or more SOQL queries whose records, with the related records they select, are exported. Each query is passed as its own --query. A query with a parent-to-child subquery exports the children too. Required.

    .PARAMETER Plan
    Generate multiple sObject tree files and a plan definition file for aggregated import. Adds --plan.

    .PARAMETER Prefix
    Prefix of generated files. Passed to sf as --prefix.

    .PARAMETER OutputDirectory
    Directory in which to generate the JSON files; default is current directory. Passed to sf as --output-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Export-SalesforceTreeData -Query "SELECT Id, Name, (SELECT Id, LastName FROM Contacts) FROM Account WHERE Name LIKE 'Acme%'" -Plan -OutputDirectory .\data -TargetOrg source
    Import-SalesforceTreeData -Plan .\data\Account-Contact-plan.json -TargetOrg scratch

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data export tree (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Plan = --plan; -Prefix = --prefix; -OutputDirectory = --output-dir; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-data

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string[]] $Query,
        [Parameter(Mandatory = $false)][switch] $Plan,
        [Parameter(Mandatory = $false)][string] $Prefix,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $queries = @($Query | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($queries.Count -eq 0) { throw '-Query needs at least one SOQL query.' }
    if ($Prefix -and $Prefix -notmatch '^[A-Za-z0-9_.-]+\z') { throw "Prefix '$Prefix' is not valid: use letters, digits, underscore, dot and hyphen only." }
    if ($OutputDirectory -and (Test-Path -LiteralPath $OutputDirectory -PathType Leaf)) { throw "Output directory '$OutputDirectory' is a file." }

    $arguments = @('data', 'export', 'tree')
    foreach ($item in $queries) { $arguments += @('--query', $item) }
    if ($Plan) { $arguments += '--plan' }
    if ($Prefix) { $arguments += @('--prefix', $Prefix) }
    if ($OutputDirectory) { $arguments += @('--output-dir', $OutputDirectory) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceTreeOutput -Output $output -Command 'data export tree'

    $directory = $OutputDirectory
    if (-not $directory) { $directory = (Get-Location).ProviderPath }
    if ($Plan) {
        $entries = @($result)
        $files = @()
        $types = @()
        foreach ($entry in $entries) {
            if ($null -ne $entry.PSObject.Properties['sobject']) { $types += [string] $entry.sobject }
            if ($null -ne $entry.PSObject.Properties['files']) { foreach ($f in @($entry.files)) { $files += (Join-Path -Path $directory -ChildPath ([string] $f)) } }
        }
        # The CLI names the plan file plan.json (no prefix) for several queries, and after the object types (with the prefix) for one.
        if ($queries.Count -gt 1) { $planName = 'plan.json' } else {
            $planName = ($types -join '-') + '-plan.json'
            if ($Prefix) { $planName = "$Prefix-$planName" }
        }
        $planFile = Join-Path -Path $directory -ChildPath $planName
        if (-not (Test-Path -LiteralPath $planFile -PathType Leaf)) { $planFile = $null }
        return [pscustomobject]@{ Plan = $true; OutputDirectory = $directory; PlanFile = $planFile; Files = $files; Records = $null; RecordCount = $null; Result = $entries }
    }
    $records = @()
    if ($null -ne $result -and $null -ne $result.PSObject.Properties['records']) { $records = @($result.records) }
    return [pscustomobject]@{ Plan = $false; OutputDirectory = $directory; PlanFile = $null; Files = @(); Records = $records; RecordCount = $records.Count; Result = $result }
}

function Import-SalesforceTreeData {
    <#
    .SYNOPSIS
    Imports records and their related child records from JSON files into an org (sf data import tree).

    .DESCRIPTION
    Give either -Plan (a plan file from Export-SalesforceTreeData -Plan) or -File (one or more tree JSON files), not both. Asks for confirmation only when
    $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. Returns one object per record created: RefId, Type and Id. If Salesforce
    rejects records, nothing is returned and the cmdlet throws PsfdxTreeImportFailed, whose TargetObject lists each failed reference with its
    StatusCode, Message and Fields. The Tree API imports at most 200 records per call.

    .PARAMETER Plan
    Plan definition file to insert multiple data files. Passed to sf as --plan. Required in the Plan parameter set.

    .PARAMETER File
    Comma-separated and in-order JSON files that contain the records, in sObject tree format, that you want to insert. Passed to sf as --files. Required in the Files parameter set.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Import-SalesforceTreeData -Plan .\data\Account-Contact-plan.json -TargetOrg scratch

    .EXAMPLE
    Import-SalesforceTreeData -File .\data\accounts.json, .\data\contacts.json -TargetOrg scratch -WhatIf

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data import tree (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -Plan = --plan; -File = --files; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-data

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Plan')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Plan')][string] $Plan,
        [Parameter(Mandatory = $true, ParameterSetName = 'Files')][string[]] $File,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('data', 'import', 'tree')
    if ($PSCmdlet.ParameterSetName -eq 'Plan') {
        if (-not (Test-Path -LiteralPath $Plan -PathType Leaf)) { throw "Plan file '$Plan' does not exist." }
        $arguments += @('--plan', $Plan)
        $what = "the plan '$Plan'"
    } else {
        $files = @($File | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($files.Count -eq 0) { throw '-File needs at least one file.' }
        foreach ($item in $files) {
            if ($item.Contains(',')) { throw "File '$item' contains a comma, which the CLI reads as a list separator." }
            if (-not (Test-Path -LiteralPath $item -PathType Leaf)) { throw "File '$item' does not exist." }
        }
        $arguments += @('--files', ($files -join ','))
        $what = "$($files.Count) file(s)"
    }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $orgLabel = 'the default org'
    if (-not [string]::IsNullOrWhiteSpace($TargetOrg)) { $orgLabel = "org $TargetOrg" }
    if (-not $PSCmdlet.ShouldProcess("records from $what in $orgLabel", 'Import tree data')) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceTreeOutput -Output $output -Command 'data import tree'
    return @($result | ForEach-Object { [pscustomobject]@{ RefId = $_.refId; Type = $_.type; Id = $_.id } })
}

function ConvertFrom-SalesforceTreeOutput {
    # Returns the result of a tree command, or throws. A rejected import comes back as an error whose data is the list of failed
    # records; that becomes PsfdxTreeImportFailed with the list as its TargetObject. Any other failure keeps the CLI's message.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][AllowEmptyCollection()] $Output,
        [Parameter(Mandatory = $true)][string] $Command
    )
    $text = [string]::Join([Environment]::NewLine, @($Output | ForEach-Object { [string] $_ })).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { throw "sf $Command returned no output where JSON was expected." }
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop } catch {
        $preview = $text; if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
        throw "sf $Command returned output that is not valid JSON: $preview"
    }
    if ($null -eq $parsed -or $parsed -is [array] -or $null -eq $parsed.PSObject.Properties['status']) { throw "sf $Command returned JSON in an unexpected shape (no status)." }
    if ($parsed.status -eq 0) {
        if ($null -eq $parsed.PSObject.Properties['result']) { throw "sf $Command succeeded but returned no result." }
        return $parsed.result
    }
    if ($null -ne $parsed.PSObject.Properties['data'] -and $null -ne $parsed.data -and $parsed.data -is [array] -and $parsed.data.Count -gt 0) {
        $failed = @($parsed.data | ForEach-Object {
            [pscustomobject]@{ ReferenceId = $_.referenceId; StatusCode = $_.StatusCode; Message = $_.Message; Fields = $_.fields }
        })
        $summary = ($failed | ForEach-Object { "$($_.ReferenceId): $($_.StatusCode) $($_.Message)" }) -join '; '
        if ($summary.Length -gt 400) { $summary = $summary.Substring(0, 400) + '...' }
        $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException "sf $Command failed for $($failed.Count) record(s): $summary"), 'PsfdxTreeImportFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $failed)
        throw $record
    }
    Show-SalesforceResult -Result $text | Out-Null
    throw "sf $Command failed with status $($parsed.status)."
}

#endregion

#region Bulk API 2.0

# Wraps `sf data export|import|update|upsert bulk`, their `resume` commands and `sf data bulk results`. Without -WaitMinutes the CLI
# creates the job and returns at once with a job ID; with it, the CLI polls and returns the counts. Each cmdlet returns a plain object.
#
# A job that finishes with failed rows, or fails or aborts, makes the CLI exit with an error. That error is rethrown as
# PsfdxBulkJobFailed, and its TargetObject holds JobId, State and Message, so a script can fetch the row-level results with
# Get-SalesforceBulkResult. Any other CLI error (no authorisation, a bad file, a bad flag) is thrown with the CLI's message.

function Export-SalesforceBulkData {
    <#
    .SYNOPSIS
    Exports the records of a SOQL query to a file with Bulk API 2.0 (sf data export bulk).

    .DESCRIPTION
    Give the query as -Query or -QueryFile (a file avoids line breaks, which the Windows CLI shim rejects as an argument). The query is
    passed to the CLI unchanged. Without -WaitMinutes the job is created and its JobId returned; finish it later with
    Resume-SalesforceBulkJob -Operation Export. With -WaitMinutes the cmdlet waits and returns TotalSize.

    .PARAMETER OutputFile
    File where records are written. Passed to sf as --output-file. Required.

    .PARAMETER Query
    SOQL query to execute. Passed to sf as --query.

    .PARAMETER QueryFile
    File that contains the SOQL query. Passed to sf as --query-file.

    .PARAMETER ResultFormat
    Format to write the results. Passed to sf as --result-format. Default: csv. Valid values: csv, json.

    .PARAMETER AllRows
    Include records that have been soft-deleted due to a merge or delete. By default, deleted records are not returned. Adds --all-rows.

    .PARAMETER ColumnDelimiter
    Column delimiter to be used when writing CSV output. Default is COMMA. Passed to sf as --column-delimiter. Valid values: BACKQUOTE, CARET, COMMA, PIPE, SEMICOLON, TAB.

    .PARAMETER LineEnding
    Line ending to be used when writing CSV output. Default value on Windows is is `CRLF`; on macOS and Linux it's `LR`. Passed to sf as --line-ending. Valid values: LF, CRLF.

    .PARAMETER WaitMinutes
    Time to wait for the command to finish, in minutes. Passed to sf as --wait. Default: 0. Range: 0 to 1440.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Export-SalesforceBulkData -Query 'SELECT Id, Name FROM Account' -OutputFile .\accounts.csv -WaitMinutes 10 -TargetOrg myorg

    .EXAMPLE
    $job = Export-SalesforceBulkData -QueryFile .\big.soql -OutputFile .\big.csv -TargetOrg myorg; Resume-SalesforceBulkJob -Operation Export -JobId $job.JobId

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data export bulk (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -OutputFile = --output-file; -Query = --query; -QueryFile = --query-file; -ResultFormat = --result-format; -AllRows = --all-rows; -ColumnDelimiter = --column-delimiter; -LineEnding = --line-ending; -WaitMinutes = --wait; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-data

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $OutputFile,
        [Parameter(Mandatory = $false)][string] $Query,
        [Parameter(Mandatory = $false)][string] $QueryFile,
        [Parameter(Mandatory = $false)][ValidateSet('csv', 'json')][string] $ResultFormat = 'csv',
        [Parameter(Mandatory = $false)][switch] $AllRows,
        [Parameter(Mandatory = $false)][ValidateSet('BACKQUOTE', 'CARET', 'COMMA', 'PIPE', 'SEMICOLON', 'TAB')][string] $ColumnDelimiter,
        [Parameter(Mandatory = $false)][ValidateSet('LF', 'CRLF')][string] $LineEnding,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $hasQuery = -not [string]::IsNullOrWhiteSpace($Query)
    $hasQueryFile = -not [string]::IsNullOrWhiteSpace($QueryFile)
    if ($hasQuery -eq $hasQueryFile) { throw 'Give exactly one of -Query and -QueryFile.' }
    if ($hasQueryFile -and -not (Test-Path -LiteralPath $QueryFile -PathType Leaf)) { throw "Query file '$QueryFile' does not exist." }
    $outputParent = Split-Path -Path $OutputFile -Parent
    if ($outputParent -and -not (Test-Path -LiteralPath $outputParent -PathType Container)) { throw "Output directory '$outputParent' does not exist." }

    $arguments = @('data', 'export', 'bulk')
    if ($hasQuery) { $arguments += @('--query', $Query) } else { $arguments += @('--query-file', $QueryFile) }
    $arguments += @('--output-file', $OutputFile, '--result-format', $ResultFormat)
    if ($AllRows) { $arguments += '--all-rows' }
    if ($ColumnDelimiter) { $arguments += @('--column-delimiter', $ColumnDelimiter) }
    if ($LineEnding) { $arguments += @('--line-ending', $LineEnding) }
    if ($WaitMinutes -gt 0) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data export bulk'
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation 'Export'
}

function Import-SalesforceBulkData {
    <#
    .SYNOPSIS
    Inserts the rows of a CSV file with Bulk API 2.0 (sf data import bulk).

    .DESCRIPTION
    Creates records. Asks for confirmation only when $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. Without
    -WaitMinutes the job is created and its JobId returned; with it the cmdlet waits and returns the counts. A job with failed rows
    throws PsfdxBulkJobFailed (see Get-SalesforceBulkResult for the row results).

    .PARAMETER File
    CSV file that contains the Salesforce object records you want to import. Passed to sf as --file. Required.

    .PARAMETER Object
    API name of the Salesforce object, either standard or custom, into which you're importing records. Passed to sf as --sobject. Required.

    .PARAMETER ColumnDelimiter
    Column delimiter used in the CSV file. Passed to sf as --column-delimiter. Valid values: BACKQUOTE, CARET, COMMA, PIPE, SEMICOLON, TAB.

    .PARAMETER LineEnding
    Line ending used in the CSV file. Default value on Windows is `CRLF`; on macOS and Linux it's `LF`. Passed to sf as --line-ending. Valid values: LF, CRLF.

    .PARAMETER WaitMinutes
    Time to wait for the command to finish, in minutes. Passed to sf as --wait. Default: 0. Range: 0 to 1440.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Import-SalesforceBulkData -File '.\new accounts.csv' -Object Account -WaitMinutes 10 -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data import bulk (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -File = --file; -Object = --sobject; -ColumnDelimiter = --column-delimiter; -LineEnding = --line-ending; -WaitMinutes = --wait; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-data

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $File,
        [Parameter(Mandatory = $true)][string] $Object,
        [Parameter(Mandatory = $false)][ValidateSet('BACKQUOTE', 'CARET', 'COMMA', 'PIPE', 'SEMICOLON', 'TAB')][string] $ColumnDelimiter,
        [Parameter(Mandatory = $false)][ValidateSet('LF', 'CRLF')][string] $LineEnding,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $objectName = ConvertTo-SalesforceSoqlIdentifier -Value $Object
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "CSV file '$File' does not exist." }

    $arguments = @('data', 'import', 'bulk', '--file', $File, '--sobject', $objectName)
    if ($ColumnDelimiter) { $arguments += @('--column-delimiter', $ColumnDelimiter) }
    if ($LineEnding) { $arguments += @('--line-ending', $LineEnding) }
    if ($WaitMinutes -gt 0) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess((Get-SalesforceBulkTargetLabel -Object $objectName -File $File -TargetOrg $TargetOrg), 'Bulk insert')) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data import bulk'
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation 'Import' -Object $objectName
}

function Update-SalesforceBulkData {
    <#
    .SYNOPSIS
    Updates records from the rows of a CSV file with Bulk API 2.0 (sf data update bulk).

    .DESCRIPTION
    The CSV needs an Id column. Asks for confirmation only when $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call.
    Results are as for Import-SalesforceBulkData.

    .PARAMETER File
    CSV file that contains the Salesforce object records you want to update. Passed to sf as --file. Required.

    .PARAMETER Object
    API name of the Salesforce object, either standard or custom, which you are updating. Passed to sf as --sobject. Required.

    .PARAMETER ColumnDelimiter
    Column delimiter used in the CSV file. Passed to sf as --column-delimiter. Valid values: BACKQUOTE, CARET, COMMA, PIPE, SEMICOLON, TAB.

    .PARAMETER LineEnding
    Line ending used in the CSV file. Default value on Windows is `CRLF`; on macOS and Linux it's `LF`. Passed to sf as --line-ending. Valid values: LF, CRLF.

    .PARAMETER WaitMinutes
    Time to wait for the command to finish, in minutes. Passed to sf as --wait. Default: 0. Range: 0 to 1440.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Update-SalesforceBulkData -File .\changes.csv -Object Contact -WaitMinutes 10 -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data update bulk (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -File = --file; -Object = --sobject; -ColumnDelimiter = --column-delimiter; -LineEnding = --line-ending; -WaitMinutes = --wait; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-data

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $File,
        [Parameter(Mandatory = $true)][string] $Object,
        [Parameter(Mandatory = $false)][ValidateSet('BACKQUOTE', 'CARET', 'COMMA', 'PIPE', 'SEMICOLON', 'TAB')][string] $ColumnDelimiter,
        [Parameter(Mandatory = $false)][ValidateSet('LF', 'CRLF')][string] $LineEnding,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $objectName = ConvertTo-SalesforceSoqlIdentifier -Value $Object
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "CSV file '$File' does not exist." }

    $arguments = @('data', 'update', 'bulk', '--file', $File, '--sobject', $objectName)
    if ($ColumnDelimiter) { $arguments += @('--column-delimiter', $ColumnDelimiter) }
    if ($LineEnding) { $arguments += @('--line-ending', $LineEnding) }
    if ($WaitMinutes -gt 0) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess((Get-SalesforceBulkTargetLabel -Object $objectName -File $File -TargetOrg $TargetOrg), 'Bulk update')) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data update bulk'
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation 'Update' -Object $objectName
}

function Upsert-SalesforceBulkData {
    <#
    .SYNOPSIS
    Inserts or updates records from the rows of a CSV file by external ID with Bulk API 2.0 (sf data upsert bulk).

    .DESCRIPTION
    -ExternalIdField names the external ID field the CSV matches on, and its column must be in the file. Asks for confirmation only when
    $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. For one record use Upsert-SalesforceRecord.

    .PARAMETER File
    CSV file that contains the IDs of the records to update or delete. Passed to sf as --file. Required.

    .PARAMETER Object
    API name of the Salesforce object, either standard or custom, that you want to update or delete records from. Passed to sf as --sobject. Required.

    .PARAMETER ExternalIdField
    Name of the external ID field, or the Id field. Passed to sf as --external-id. Required.

    .PARAMETER ColumnDelimiter
    Column delimiter used in the CSV file. Passed to sf as --column-delimiter. Valid values: BACKQUOTE, CARET, COMMA, PIPE, SEMICOLON, TAB.

    .PARAMETER LineEnding
    Line ending used in the CSV file. Default value on Windows is `CRLF`; on macOS and Linux it's `LF`. Passed to sf as --line-ending. Valid values: LF, CRLF.

    .PARAMETER WaitMinutes
    Number of minutes to wait for the command to complete before displaying the results. Passed to sf as --wait. Default: 0. Range: 0 to 1440.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Upsert-SalesforceBulkData -File .\accounts.csv -Object Account -ExternalIdField Ext_Id__c -WaitMinutes 10 -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data upsert bulk (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -File = --file; -Object = --sobject; -ExternalIdField = --external-id; -ColumnDelimiter = --column-delimiter; -LineEnding = --line-ending; -WaitMinutes = --wait; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-data

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $File,
        [Parameter(Mandatory = $true)][string] $Object,
        [Parameter(Mandatory = $true)][string] $ExternalIdField,
        [Parameter(Mandatory = $false)][ValidateSet('BACKQUOTE', 'CARET', 'COMMA', 'PIPE', 'SEMICOLON', 'TAB')][string] $ColumnDelimiter,
        [Parameter(Mandatory = $false)][ValidateSet('LF', 'CRLF')][string] $LineEnding,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $objectName = ConvertTo-SalesforceSoqlIdentifier -Value $Object
    $externalIdFieldName = ConvertTo-SalesforceSoqlIdentifier -Value $ExternalIdField
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "CSV file '$File' does not exist." }

    $arguments = @('data', 'upsert', 'bulk', '--file', $File, '--sobject', $objectName, '--external-id', $externalIdFieldName)
    if ($ColumnDelimiter) { $arguments += @('--column-delimiter', $ColumnDelimiter) }
    if ($LineEnding) { $arguments += @('--line-ending', $LineEnding) }
    if ($WaitMinutes -gt 0) { $arguments += @('--wait', $WaitMinutes) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess((Get-SalesforceBulkTargetLabel -Object $objectName -File $File -TargetOrg $TargetOrg), "Bulk upsert on $externalIdFieldName")) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data upsert bulk'
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation 'Upsert' -Object $objectName
}

function Resume-SalesforceBulkJob {
    <#
    .SYNOPSIS
    Resumes a Bulk API 2.0 job started without -WaitMinutes (sf data export|import|update|upsert resume).

    .DESCRIPTION
    Pass the JobId from the earlier step and the -Operation that created it. The CLI remembers jobs it created on this computer, so import,
    update and export resumes find the org from that record; they do not take -TargetOrg (it is ignored with a warning), and a job created
    elsewhere cannot be resumed here: use Get-SalesforceBulkResult with -TargetOrg instead. Export resumes do not take -WaitMinutes.
    Resuming only continues the existing job, so it does not ask for confirmation. Errors are as for the cmdlet that created the job.

    .PARAMETER Operation
    The kind of bulk job to resume: Export, Import, Update or Upsert. It selects which command runs: sf data export, import, update or upsert resume. Required. Valid values: Export, Import, Update, Upsert.

    .PARAMETER JobId
    Job ID of the bulk export. Passed to sf as --job-id. Required.

    .PARAMETER WaitMinutes
    Time to wait for the command to finish, in minutes. Passed to sf as --wait. Default: 0. Range: 0 to 1440.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the "target-org" configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Resume-SalesforceBulkJob -Operation Upsert -JobId 750xx0000000001 -WaitMinutes 10 -TargetOrg myorg

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data export resume (plugin @salesforce/plugin-data)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --use-most-recent
    Command run: sf data import resume (plugin @salesforce/plugin-data)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --use-most-recent
    Command run: sf data update resume (plugin @salesforce/plugin-data)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --use-most-recent
    Command run: sf data upsert resume (plugin @salesforce/plugin-data)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --use-most-recent
    Parameter to flag: -JobId = --job-id; -WaitMinutes = --wait; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-data

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidateSet('Export', 'Import', 'Update', 'Upsert')][string] $Operation,
        [Parameter(Mandatory = $true)][ValidatePattern('^750[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $JobId,
        [Parameter(Mandatory = $false)][ValidateRange(0, 1440)][int] $WaitMinutes = 0,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $hasTargetOrg = $PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)
    if ($hasTargetOrg -and $Operation -ne 'Upsert') { Write-Warning "-TargetOrg is ignored for a $Operation resume: the CLI finds the org from its record of the job." }
    if ($WaitMinutes -gt 0 -and $Operation -eq 'Export') { Write-Warning '-WaitMinutes is ignored for an Export resume.' }

    switch ($Operation) {
        'Export' { $arguments = @('data', 'export', 'resume', '--job-id', $JobId); $command = 'data export resume' }
        'Import' { $arguments = @('data', 'import', 'resume', '--job-id', $JobId); $command = 'data import resume' }
        'Update' { $arguments = @('data', 'update', 'resume', '--job-id', $JobId); $command = 'data update resume' }
        'Upsert' { $arguments = @('data', 'upsert', 'resume', '--job-id', $JobId); $command = 'data upsert resume' }
    }
    if ($WaitMinutes -gt 0 -and $Operation -ne 'Export') { $arguments += @('--wait', $WaitMinutes) }
    if ($hasTargetOrg -and $Operation -eq 'Upsert') { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command $command
    return ConvertTo-SalesforceBulkJobObject -Result $result -Operation $Operation -JobId $JobId
}

function Get-SalesforceBulkResult {
    <#
    .SYNOPSIS
    Gets the outcome of a Bulk API 2.0 ingest job and saves its row results as CSV files (sf data bulk results).

    .DESCRIPTION
    The CLI writes <JobId>-success-records.csv, <JobId>-failed-records.csv and <JobId>-unprocessed-records.csv into its working directory, so
    the cmdlet runs it in -OutputDirectory (the current directory by default) and returns the full paths of the files it wrote. Records that
    failed do not make this cmdlet throw: check HasFailures or FailedRecords. A job that has not finished is an error. Works for any job in
    the org, including ones this computer did not create.

    .PARAMETER JobId
    Job ID of the bulk job. Passed to sf as --job-id. Required.

    .PARAMETER OutputDirectory
    Folder the result files are written to. It is created if it does not exist. Defaults to the current folder. The cmdlet runs the CLI there and returns the full paths of the files it wrote.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    $r = Get-SalesforceBulkResult -JobId 750xx0000000001 -OutputDirectory .\bulk -TargetOrg myorg; if ($r.HasFailures) { Import-Csv $r.FailedFilePath }

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf data bulk results (plugin @salesforce/plugin-data)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -JobId = --job-id; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-data

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][ValidatePattern('^750[A-Za-z0-9]{12}([A-Za-z0-9]{3})?\z')][string] $JobId,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $directory = (Get-Location).ProviderPath
    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw "Output directory '$OutputDirectory' does not exist." }
        $directory = (Resolve-Path -LiteralPath $OutputDirectory).ProviderPath
    }

    $arguments = @('data', 'bulk', 'results', '--job-id', $JobId)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Push-Location -LiteralPath $directory
    try {
        $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    } finally {
        Pop-Location
    }
    $result = ConvertFrom-SalesforceBulkOutput -Output $output -Command 'data bulk results' -AllowFailedRecords

    $pathOf = {
        param([string] $Name)
        if ($null -ne $result.PSObject.Properties[$Name] -and -not [string]::IsNullOrWhiteSpace([string] $result.$Name)) { return (Join-Path -Path $directory -ChildPath ([string] $result.$Name)) }
        return $null
    }
    $failed = 0
    if ($null -ne $result.PSObject.Properties['failedRecords'] -and $null -ne $result.failedRecords) { $failed = [int] $result.failedRecords }
    if ($failed -gt 0) { Write-Warning "$failed record(s) failed in job $JobId. See the failed records file in $directory." }
    return [pscustomobject]@{
        JobId               = $JobId
        Status              = $result.status
        Operation           = $result.operation
        Object              = $result.object
        ProcessedRecords    = $result.processedRecords
        SuccessfulRecords   = $result.successfulRecords
        FailedRecords       = $failed
        HasFailures         = ($failed -gt 0)
        SuccessFilePath     = & $pathOf 'successFilePath'
        FailedFilePath      = & $pathOf 'failedFilePath'
        UnprocessedFilePath = & $pathOf 'unprocessedFilePath'
    }
}

function Get-SalesforceBulkTargetLabel {
    # Names what a bulk write will touch, for the ShouldProcess prompt and -WhatIf: the object, the file and the org.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Object,
        [Parameter(Mandatory = $true)][string] $File,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $org = 'the default org'
    if (-not [string]::IsNullOrWhiteSpace($TargetOrg)) { $org = "org $TargetOrg" }
    return "$Object records from '$File' in $org"
}

function ConvertFrom-SalesforceBulkOutput {
    # Returns the result of a bulk command, or throws. A failed job (failed rows, Failed or Aborted) becomes PsfdxBulkJobFailed with the
    # job ID, so a script can fetch the row results; any other failure is thrown as the CLI described it.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][AllowEmptyCollection()] $Output,
        [Parameter(Mandatory = $true)][string] $Command,
        [Parameter(Mandatory = $false)][switch] $AllowFailedRecords
    )
    $text = [string]::Join([Environment]::NewLine, @($Output | ForEach-Object { [string] $_ })).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { throw "sf $Command returned no output where JSON was expected." }
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop } catch {
        $preview = $text; if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
        throw "sf $Command returned output that is not valid JSON: $preview"
    }
    if ($null -eq $parsed -or $parsed -is [array] -or $null -eq $parsed.PSObject.Properties['status']) {
        throw "sf $Command returned JSON in an unexpected shape (no status)."
    }
    # Upsert and its resume return { jobInfo, records } instead of the flat counts, and the CLI can send that with a failing status when rows failed.
    $hasResult = ($null -ne $parsed.PSObject.Properties['result']) -and ($null -ne $parsed.result)
    if ($hasResult -and $null -ne $parsed.result.PSObject.Properties['jobInfo'] -and $null -ne $parsed.result.jobInfo) {
        $info = $parsed.result.jobInfo
        $state = $null; if ($null -ne $info.PSObject.Properties['state']) { $state = [string] $info.state }
        $flat = [ordered]@{ jobId = [string] $info.id; state = $state }
        if ($state -eq 'JobComplete') {
            $processed = 0; if ($null -ne $info.PSObject.Properties['numberRecordsProcessed'] -and $null -ne $info.numberRecordsProcessed) { $processed = [int] $info.numberRecordsProcessed }
            $failedRows = 0; if ($null -ne $info.PSObject.Properties['numberRecordsFailed'] -and $null -ne $info.numberRecordsFailed) { $failedRows = [int] $info.numberRecordsFailed }
            $flat['processedRecords'] = $processed
            $flat['failedRecords'] = $failedRows
            $flat['successfulRecords'] = $processed - $failedRows
        }
        if (-not $AllowFailedRecords) {
            $message = ''
            if ($state -eq 'Failed' -or $state -eq 'Aborted') {
                if ($null -ne $info.PSObject.Properties['errorMessage'] -and $info.errorMessage) { $message = [string] $info.errorMessage }
                $message = "The job is $state. $message".Trim()
            } elseif ($flat.Contains('failedRecords') -and $flat['failedRecords'] -gt 0) {
                $message = "Job finished being processed but $($flat['failedRecords']) records failed to process."
            }
            if ($message) {
                $full = "sf $Command reported a problem with bulk job $($flat['jobId']): $message Get-SalesforceBulkResult -JobId $($flat['jobId']) lists the rows that failed."
                $target = [pscustomobject]@{ JobId = $flat['jobId']; State = $state; Message = $message }
                $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException $full), 'PsfdxBulkJobFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $target)
                throw $record
            }
        }
        return [pscustomobject] $flat
    }

    if ($parsed.status -eq 0) {
        if (-not $hasResult) { throw "sf $Command succeeded but returned no result." }
        return $parsed.result
    }

    $jobId = $null; $state = $null
    if ($null -ne $parsed.PSObject.Properties['data'] -and $null -ne $parsed.data) {
        if ($null -ne $parsed.data.PSObject.Properties['jobId']) { $jobId = [string] $parsed.data.jobId }
        if ($null -ne $parsed.data.PSObject.Properties['state']) { $state = [string] $parsed.data.state }
    }
    $message = ''
    if ($null -ne $parsed.PSObject.Properties['message'] -and $parsed.message) { $message = [string] $parsed.message }
    if (-not $jobId -and $message -match '\b(750[A-Za-z0-9]{12}(?:[A-Za-z0-9]{3})?)\b') { $jobId = $Matches[1] }
    if ($jobId) {
        $full = "sf $Command reported a problem with bulk job ${jobId}: $message Get-SalesforceBulkResult -JobId $jobId lists the rows that failed.".Replace('  ', ' ')
        $target = [pscustomobject]@{ JobId = $jobId; State = $state; Message = $message }
        $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException $full), 'PsfdxBulkJobFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $target)
        throw $record
    }
    # No job ID: an ordinary CLI failure, with the same message handling as every other cmdlet.
    Show-SalesforceResult -Result $text | Out-Null
    throw "sf $Command failed with status $($parsed.status). $message".Trim()
}

function ConvertTo-SalesforceBulkJobObject {
    # One shape for every bulk command. Properties the CLI did not report (an asynchronous job has no counts yet) are $null.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)] $Result,
        [Parameter(Mandatory = $true)][string] $Operation,
        [Parameter(Mandatory = $false)][string] $Object,
        [Parameter(Mandatory = $false)][string] $JobId
    )
    $get = {
        param([string] $Name)
        if ($null -ne $Result.PSObject.Properties[$Name]) { return $Result.$Name }
        return $null
    }
    $id = & $get 'jobId'
    if (-not $id) { $id = $JobId }
    $processed = & $get 'processedRecords'
    $total = & $get 'totalSize'
    $state = & $get 'state'
    return [pscustomobject]@{
        JobId             = $id
        Operation         = $Operation
        Object            = $(if ($Object) { $Object } else { $null })
        Completed         = (($null -ne $processed) -or ($null -ne $total))
        State             = $state
        ProcessedRecords  = $processed
        SuccessfulRecords = & $get 'successfulRecords'
        FailedRecords     = & $get 'failedRecords'
        TotalSize         = $total
        FilePath          = & $get 'filePath'
    }
}

#endregion

#region Salesforce REST API

function Assert-SalesforceHttpsUrl {
    # Private: stops with a clear message unless the value is an absolute https URL.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Url,
        [Parameter(Mandatory = $true)][string] $What
    )

    $uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') {
        throw "$What must be an absolute https:// URL, because credentials or an access token are sent to it. Got '$Url'."
    }
}

function ConvertTo-SalesforcePlainSecret {
    # Private: turns a SecureString into text at the moment of the request. A plain string is returned as is, with a warning.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)] $Value,
        [Parameter(Mandatory = $true)][string] $Name
    )

    if ($Value -is [System.Security.SecureString]) {
        $bstr = [IntPtr]::Zero
        try {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
            return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        }
    }
    if ($Value -is [string]) {
        Write-Warning "-$Name was given as a plain string, which stays readable in your session history and memory. Pass a SecureString instead, for example (Read-Host -AsSecureString). Plain strings still work for now."
        return $Value
    }
    throw "-$Name must be a SecureString (or a string, which is deprecated). Got $($Value.GetType().FullName)."
}

function Connect-SalesforceApi {
    <#
    .SYNOPSIS
    Gets an access token for the Salesforce REST API with the username-password OAuth flow.

    .DESCRIPTION
    Does not use the Salesforce CLI. It posts the user name, the password plus security token, and the connected app client ID and secret to the org's /services/oauth2/token endpoint with Invoke-RestMethod and returns the response, which holds the access token and instance URL. The request is sent only over https. Pass the password, token and client secret as SecureString: they are converted to text only when the request is built and are never written to the verbose, debug or error output. Plain strings still work but write a warning, because they stay in your session history and memory.

    .PARAMETER TargetOrg
    The Salesforce user name to log in as (sent as the OAuth username). This is not an org alias. Required.

    .PARAMETER Password
    The user's password, as a SecureString (preferred) or a plain string (deprecated, writes a warning). The security token is appended to it. Required.

    .PARAMETER Token
    The user's security token, as a SecureString (preferred) or a plain string (deprecated, writes a warning). Appended to the password. Required.

    .PARAMETER ClientId
    Consumer key of the connected app used for the login. Required.

    .PARAMETER ClientSecret
    Consumer secret of the connected app, as a SecureString (preferred) or a plain string (deprecated, writes a warning). Required.

    .PARAMETER Sandbox
    Use the sandbox login host https://test.salesforce.com instead of https://login.salesforce.com.

    .PARAMETER CustomUrl
    Base URL of the login host to use instead, for example a My Domain. It must be an absolute https:// URL, otherwise the cmdlet stops before sending anything.

    .EXAMPLE
    Connect-SalesforceApi -TargetOrg user@example.com -Password $pw -Token $tok -ClientId $key -ClientSecret $secret
    Request an access token from production.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It calls the Salesforce REST API directly with Invoke-RestMethod, with no Salesforce CLI involved.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $TargetOrg,
        [Parameter(Mandatory = $true)][object] $Password,
        [Parameter(Mandatory = $true)][object] $Token,
        [Parameter(Mandatory = $true)][string] $ClientId,
        [Parameter(Mandatory = $true)][object] $ClientSecret,
        [Parameter(Mandatory = $false)][switch] $Sandbox,
        [Parameter(Mandatory = $false)][string] $CustomUrl
    )

    $loginUrl = "https://login.salesforce.com/services/oauth2/token"
    if ($Sandbox) { $loginUrl = "https://test.salesforce.com/services/oauth2/token" }
    if ($CustomUrl) {
        # The password, security token and client secret are in the request body, so never send them over plain http.
        Assert-SalesforceHttpsUrl -Url $CustomUrl -What '-CustomUrl'
        $loginUrl = $CustomUrl.TrimEnd('/') + '/services/oauth2/token'
    }

    # Convert only now, so the secrets are plain text for as short a time as possible.
    $plainPassword = ConvertTo-SalesforcePlainSecret -Value $Password -Name 'Password'
    $plainToken = ConvertTo-SalesforcePlainSecret -Value $Token -Name 'Token'
    $plainSecret = ConvertTo-SalesforcePlainSecret -Value $ClientSecret -Name 'ClientSecret'

    return Invoke-RestMethod -Uri $loginUrl `
        -Method Post `
        -Body @{
        grant_type    = "password"
        client_id     = "$ClientId"
        client_secret = $plainSecret
        username      = "$TargetOrg"
        password      = ($plainPassword + $plainToken)
    }
}

function Invoke-SalesforceApi {
    <#
    .SYNOPSIS
    Calls a Salesforce REST API URL with an access token.

    .DESCRIPTION
    Does not use the Salesforce CLI. It sends the request with Invoke-RestMethod and an Authorization: Bearer header, and returns the parsed response. The URL must be absolute and https, so the token is never sent over plain http. You choose the host; the cmdlet does not check that it is a Salesforce host.

    .PARAMETER Url
    Absolute https:// URL of the REST resource. Required.

    .PARAMETER AccessToken
    Access token to send as the bearer token, for example from Connect-SalesforceApi. Required.

    .PARAMETER Method
    HTTP method: GET (default), POST, PATCH or DELETE. Default: "GET". Valid values: GET, POST, PATCH, DELETE.

    .EXAMPLE
    Invoke-SalesforceApi -Url https://example.my.salesforce.com/services/data -AccessToken $token
    List the API versions of an org.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It calls the Salesforce REST API directly with Invoke-RestMethod, with no Salesforce CLI involved.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Url,
        [Parameter(Mandatory = $true)][string] $AccessToken,
        [Parameter(Mandatory = $false)][string][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')] $Method = "GET"
    )
    # The access token is sent in the Authorization header, so only to an https URL.
    Assert-SalesforceHttpsUrl -Url $Url -What '-Url'
    return Invoke-RestMethod -Uri $Url -Method $Method -Headers @{Authorization = "Bearer " + $AccessToken }
}

function Get-SalesforceApiVersions {
    <#
    .SYNOPSIS
    Lists the REST API versions the org supports.

    .DESCRIPTION
    Sends a GET request to /services/data with sf api request rest and returns the list of versions as objects (label, url, version).

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceApiVersions -TargetOrg dev1 | Select-Object -Last 1
    The newest API version of the org.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf api request rest (plugin @salesforce/plugin-api)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --file, --header, --include, --stream-to-file
      Values psfdx cannot pass: --method POST, PUT, HEAD, DELETE, OPTIONS, TRACE
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-api

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('api', 'request', 'rest', '/services/data')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return $result | ConvertFrom-Json
}

function Get-SalesforceLatestApiVersion {
    <#
    .SYNOPSIS
    Returns the newest REST API version the org supports, such as v62.0.

    .DESCRIPTION
    Calls Get-SalesforceApiVersions and returns the highest version prefixed with v. Returns nothing if the org reports no versions.

    .PARAMETER TargetOrg
    Username or alias of the org to ask. If omitted, the Salesforce CLI uses the default target org (passed on to Get-SalesforceApiVersions).

    .EXAMPLE
    Get-SalesforceLatestApiVersion -TargetOrg dev1
    For example v62.0.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It is built on other psfdx cmdlets: Get-SalesforceApiVersions. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $versions = Get-SalesforceApiVersions -TargetOrg $TargetOrg
    if (-not $versions -or (@($versions).Count -eq 0)) { return $null }
    # Sort numerically: a string sort ranks '99.0' above '100.0'
    $latest = @($versions) |
        Where-Object { $_.version } |
        Sort-Object -Property { [double] $_.version } -Descending |
        Select-Object -First 1
    if (-not $latest) { return $null }
    return "v$($latest.version)"
}

#endregion

#region Users and Permissions

# Wraps the Salesforce CLI `org` user commands: list users, display user, create user, generate password, assign permset and permsetlicense.
# Secrets never reach the output stream, -Verbose or error messages: access tokens are dropped from every result, and a password is returned
# only as a SecureString and only when it was asked for.
#
# Limits of the CLI: `org list users` and `org display user` read the CLI's local authorisation files, so they list the users the CLI knows
# here, not every user in the org (use Get-SalesforceUsers for a query). The caller needs the org permissions for the action (Manage Users
# to create a user or assign permission sets, and for a password the "Manage Users" and "Reset User Passwords and Unlock Users" permissions);
# Salesforce rejects the call otherwise and the cmdlet throws the CLI's message.

function Get-SalesforceAuthenticatedUser {
    <#
    .SYNOPSIS
    Lists the users of an org that the Salesforce CLI has authorised on this computer (sf org list users).

    .DESCRIPTION
    Tokens are removed from the result. To search all users in the org, use Get-SalesforceUsers.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceAuthenticatedUser -TargetOrg myscratch

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org list users (plugin @salesforce/plugin-user)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-user

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('org', 'list', 'users')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $users = Show-SalesforceResult -Result $result
    return @($users | ForEach-Object { Remove-SalesforceSecretProperty -InputObject $_ })
}

function Get-SalesforceOrgUser {
    <#
    .SYNOPSIS
    Shows the user the CLI is signed in as in an org (sf org display user).

    .DESCRIPTION
    The access token and password are never returned: current Salesforce CLI versions replace both with a redaction message in this command, so
    there is nothing real to return. HasPassword says whether the CLI holds a password for the user. To set a known password, use
    New-SalesforceUserPassword.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceOrgUser -TargetOrg myscratch

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org display user (plugin @salesforce/plugin-user)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-user

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('org', 'display', 'user')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $user = Show-SalesforceResult -Result $result
    $clean = Remove-SalesforceSecretProperty -InputObject $user
    $hasPassword = ($null -ne $user.PSObject.Properties['password']) -and -not [string]::IsNullOrEmpty([string] $user.password)
    $clean | Add-Member -NotePropertyName HasPassword -NotePropertyValue $hasPassword -Force
    return $clean
}

function New-SalesforceUser {
    <#
    .SYNOPSIS
    Creates a user in an org and authorises it in the CLI (sf org create user).

    .DESCRIPTION
    Give the user's fields in a definition file (-DefinitionFile), in -Field, or both; fields in -Field override the file. Asks for confirmation
    only when $ConfirmPreference is Medium or lower, and -WhatIf makes no CLI call. Field values go to the CLI as separate arguments, so quotes
    and spaces need no escaping, but a value with a double quote or a line break is rejected by the Windows CLI shim. Needs the Manage Users
    permission. The CLI creates users for scratch orgs and sandboxes it can sign in to.

    .PARAMETER DefinitionFile
    File path to a user definition file for customizing the new user. Passed to sf as --definition-file.

    .PARAMETER Field
    Hashtable of user field values, for example @{ username = 'qa1@example.org'; profileName = 'Standard User' }. Each key=value is passed to the CLI as a separate argument, and a value here overrides the same field in -DefinitionFile.

    .PARAMETER SetAlias
    Set an alias for the created username to reference in other CLI commands. Passed to sf as --set-alias.

    .PARAMETER SetUniqueUsername
    Force the username, if specified in the definition file or at the command line, to be unique by appending the org ID. Adds --set-unique-username.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceUser -Field @{ username = 'qa1@example.org'; profileName = 'Standard User'; lastName = 'QA' } -SetAlias qa1 -TargetOrg myscratch

    .EXAMPLE
    New-SalesforceUser -DefinitionFile .\config\user-def.json -SetUniqueUsername -TargetOrg myscratch -WhatIf

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org create user (plugin @salesforce/plugin-user)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -DefinitionFile = --definition-file; -SetAlias = --set-alias; -SetUniqueUsername = --set-unique-username; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-user

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $false)][string] $DefinitionFile,
        [Parameter(Mandatory = $false)][System.Collections.IDictionary] $Field,
        [Parameter(Mandatory = $false)][string] $SetAlias,
        [Parameter(Mandatory = $false)][switch] $SetUniqueUsername,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($DefinitionFile -and -not (Test-Path -LiteralPath $DefinitionFile -PathType Leaf)) { throw "Definition file '$DefinitionFile' does not exist." }
    $pairs = @()
    if ($null -ne $Field) {
        foreach ($key in $Field.Keys) {
            $name = [string] $key
            if ($name -cnotmatch '^[A-Za-z][A-Za-z0-9_]*\z') { throw "'$name' is not a valid user field name." }
            $value = [string] $Field[$key]
            if ($value -match '[\x00-\x1F\x7F]') { throw "The value of field '$name' must not contain control characters." }
            $pairs += "$name=$value"
        }
    }

    $arguments = @('org', 'create', 'user')
    if ($DefinitionFile) { $arguments += @('--definition-file', $DefinitionFile) }
    if ($SetAlias) { $arguments += @('--set-alias', $SetAlias) }
    if ($SetUniqueUsername) { $arguments += '--set-unique-username' }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += $pairs
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $orgLabel = 'the default org'
    if (-not [string]::IsNullOrWhiteSpace($TargetOrg)) { $orgLabel = "org $TargetOrg" }
    if (-not $PSCmdlet.ShouldProcess("a user in $orgLabel", 'Create user')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $created = Show-SalesforceResult -Result $result
    return Remove-SalesforceSecretProperty -InputObject $created
}

function New-SalesforceUserPassword {
    <#
    .SYNOPSIS
    Generates a new password for a user and returns it as a SecureString (sf org generate password).

    .DESCRIPTION
    This changes the user's password, so it asks for confirmation by default; -WhatIf makes no CLI call. The password is returned only as a
    SecureString in Password, and is never written to -Verbose, -Debug or error output by this cmdlet. Length is 20 to 1000 and complexity 3 to
    5 (higher is stronger), as the CLI allows. One user at a time (-OnBehalfOf takes a single username or alias). Needs the Manage Users and
    Reset User Passwords and Unlock Users permissions.

    .PARAMETER OnBehalfOf
    Comma-separated list of usernames or aliases to assign the password to; must have been created locally with the "org create user" command. Passed to sf as --on-behalf-of.

    .PARAMETER Length
    Number of characters in the generated password; valid values are between 20 and 1000. Default value is 20. Passed to sf as --length. Default: 20. Range: 20 to 1000.

    .PARAMETER Complexity
    Level of password complexity or strength; the higher the value, the stronger the password. Passed to sf as --complexity. Default: 5. Range: 3 to 5.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    $p = New-SalesforceUserPassword -OnBehalfOf qa1 -TargetOrg myscratch -Confirm:$false; $p.Username

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org generate password (plugin @salesforce/plugin-user)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -OnBehalfOf = --on-behalf-of; -Length = --length; -Complexity = --complexity; -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-user

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $false)][string] $OnBehalfOf,
        [Parameter(Mandatory = $false)][ValidateRange(20, 1000)][int] $Length = 20,
        [Parameter(Mandatory = $false)][ValidateRange(3, 5)][int] $Complexity = 5,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    if ($OnBehalfOf -and $OnBehalfOf.Contains(',')) { throw '-OnBehalfOf takes one username or alias, not a list.' }
    $arguments = @('org', 'generate', 'password')
    if ($OnBehalfOf) { $arguments += @('--on-behalf-of', $OnBehalfOf) }
    $arguments += @('--length', $Length, '--complexity', $Complexity)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $who = $OnBehalfOf
    if (-not $who) { $who = 'the target org user' }
    if (-not $PSCmdlet.ShouldProcess($who, 'Generate a new password')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    $data = Show-SalesforceResult -Result $result
    $out = @()
    foreach ($item in @($data)) {
        if ($null -eq $item -or $null -eq $item.PSObject.Properties['password'] -or [string]::IsNullOrEmpty([string] $item.password)) { continue }
        $username = $null
        if ($null -ne $item.PSObject.Properties['username']) { $username = [string] $item.username }
        $out += [pscustomobject]@{ Username = $username; Password = (ConvertTo-SecureString -String ([string] $item.password) -AsPlainText -Force) }
    }
    if ($out.Count -eq 0) { throw 'The Salesforce CLI did not return a password.' }
    return $out
}

function Grant-SalesforcePermissionSet {
    <#
    .SYNOPSIS
    Assigns permission sets to users (sf org assign permset).

    .DESCRIPTION
    Without -OnBehalfOf the permission sets go to the target org's own user. Returns one object per user and permission set with Status
    Assigned or AlreadyAssigned; assigning a set the user already has is not an error, so a script can run again safely. Failures (a missing
    set, no permission) are returned with Status Failed and the cmdlet then throws PsfdxPermissionAssignmentFailed, whose TargetObject lists
    them. Asks for confirmation by default; -WhatIf makes no CLI call. Needs the Assign Permission Sets permission.

    .PARAMETER Name
    Passed on to Test-SalesforceAssignmentNames -Name. Required.

    .PARAMETER OnBehalfOf
    Passed on to Test-SalesforceAssignmentNames -OnBehalfOf.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Grant-SalesforcePermissionSet -Name Sales_Admin, Reports_User -OnBehalfOf qa1, qa2 -TargetOrg myscratch -Confirm:$false

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org assign permset (plugin @salesforce/plugin-user)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-user

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string[]] $Name,
        [Parameter(Mandatory = $false)][string[]] $OnBehalfOf,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $names = Test-SalesforceAssignmentNames -Name $Name -OnBehalfOf $OnBehalfOf
    $users = @($OnBehalfOf | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $arguments = @('org', 'assign', 'permset')
    foreach ($item in $names) { $arguments += @('--name', $item) }
    foreach ($item in $users) { $arguments += @('--on-behalf-of', $item) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $who = 'the target org user'
    if ($users.Count -gt 0) { $who = $users -join ', ' }
    if (-not $PSCmdlet.ShouldProcess($who, "Assign permission set $($names -join ', ')")) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    ConvertFrom-SalesforceAssignmentOutput -Output $output -Command 'org assign permset' -Names $names
}

function Grant-SalesforcePermissionSetLicense {
    <#
    .SYNOPSIS
    Assigns permission set licenses to users (sf org assign permsetlicense).

    .DESCRIPTION
    Results, idempotency, failures and confirmation work as for Grant-SalesforcePermissionSet. The org must have the licence available.

    Supports -WhatIf and -Confirm and asks for confirmation by default.

    .PARAMETER Name
    Passed on to Test-SalesforceAssignmentNames -Name. Required.

    .PARAMETER OnBehalfOf
    Passed on to Test-SalesforceAssignmentNames -OnBehalfOf.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Grant-SalesforcePermissionSetLicense -Name SalesforceCPQ_Admin -OnBehalfOf qa1 -TargetOrg myscratch -Confirm:$false

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf org assign permsetlicense (plugin @salesforce/plugin-user)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -TargetOrg = --target-org.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-user

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][string[]] $Name,
        [Parameter(Mandatory = $false)][string[]] $OnBehalfOf,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $names = Test-SalesforceAssignmentNames -Name $Name -OnBehalfOf $OnBehalfOf
    $users = @($OnBehalfOf | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $arguments = @('org', 'assign', 'permsetlicense')
    foreach ($item in $names) { $arguments += @('--name', $item) }
    foreach ($item in $users) { $arguments += @('--on-behalf-of', $item) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    $who = 'the target org user'
    if ($users.Count -gt 0) { $who = $users -join ', ' }
    if (-not $PSCmdlet.ShouldProcess($who, "Assign permission set license $($names -join ', ')")) { return }
    $output = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    ConvertFrom-SalesforceAssignmentOutput -Output $output -Command 'org assign permsetlicense' -Names $names
}

function Test-SalesforceAssignmentNames {
    # Cleans and checks the names and users given to an assignment, and returns the names.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]] $Name,
        [Parameter(Mandatory = $false)][string[]] $OnBehalfOf
    )
    $names = @($Name | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    if ($names.Count -eq 0) { throw '-Name needs at least one name.' }
    foreach ($item in $names) { if ($item -match '[,\x00-\x1F\x7F]') { throw "'$item' is not a valid name: give one name per value, without commas." } }
    foreach ($item in @($OnBehalfOf | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if ($item -match '[,\x00-\x1F\x7F]') { throw "'$item' is not a valid username or alias: give one per value, without commas." }
    }
    return $names
}

function ConvertFrom-SalesforceAssignmentOutput {
    # Turns the result of `sf org assign permset|permsetlicense` into one object per assignment. The CLI exits with status 68 when some
    # assignments failed but still returns the successes and failures, so the result is read whatever the status is.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][AllowEmptyCollection()] $Output,
        [Parameter(Mandatory = $true)][string] $Command,
        [Parameter(Mandatory = $true)][string[]] $Names
    )
    $text = [string]::Join([Environment]::NewLine, @($Output | ForEach-Object { [string] $_ })).Trim()
    $parsed = $null
    if (-not [string]::IsNullOrWhiteSpace($text)) { try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop } catch { $parsed = $null } }
    $result = $null
    if ($null -ne $parsed -and $null -ne $parsed.PSObject.Properties['result']) { $result = $parsed.result }
    $hasLists = ($null -ne $result) -and (($null -ne $result.PSObject.Properties['successes']) -or ($null -ne $result.PSObject.Properties['failures']))
    if (-not $hasLists) {
        # Not an assignment result: an ordinary CLI failure (no authorisation, unknown flag...) or unusable output.
        Show-SalesforceResult -Result $text | Out-Null
        throw "sf $Command returned no assignment result."
    }

    $items = @()
    if ($null -ne $result.PSObject.Properties['successes']) {
        foreach ($s in @($result.successes)) {
            $items += [pscustomobject]@{ Username = [string] $s.name; PermissionSet = [string] $s.value; Status = 'Assigned'; Message = $null }
        }
    }
    $failed = @()
    if ($null -ne $result.PSObject.Properties['failures']) {
        foreach ($f in @($result.failures)) {
            $message = [string] $f.message
            $status = 'Failed'
            if ($message -match '(?i)duplicate') { $status = 'AlreadyAssigned' }
            $permSet = $null
            if ($Names.Count -eq 1) { $permSet = $Names[0] }
            $item = [pscustomobject]@{ Username = [string] $f.name; PermissionSet = $permSet; Status = $status; Message = $message }
            $items += $item
            if ($status -eq 'Failed') { $failed += $item }
        }
    }
    $items
    if ($failed.Count -gt 0) {
        $summary = ($failed | ForEach-Object { "$($_.Username): $($_.Message)" }) -join '; '
        if ($summary.Length -gt 400) { $summary = $summary.Substring(0, 400) + '...' }
        $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException "sf $Command failed for $($failed.Count) assignment(s): $summary"), 'PsfdxPermissionAssignmentFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $failed)
        throw $record
    }
}

function Remove-SalesforceSecretProperty {
    # Returns a copy of a CLI result without credential properties, so a token or password cannot leak through the pipeline.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][AllowNull()] $InputObject
    )
    if ($null -eq $InputObject) { return $null }
    return ($InputObject | Select-Object -Property * -ExcludeProperty accessToken, refreshToken, password, sfdxAuthUrl, clientSecret, privateKey)
}

#endregion

#region Plugins

function Test-SalesforceIsMacOS {
    [CmdletBinding()]
    Param()
    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
}

function Install-SalesforceCli {
    <#
    .SYNOPSIS
    Installs the Salesforce CLI globally with npm.

    .DESCRIPTION
    Runs npm install --global @salesforce/cli. This downloads and runs code from the npm registry. Node.js and npm must already be installed. Asks nothing by default, supports -WhatIf and -Confirm.

    .EXAMPLE
    Install-SalesforceCli -WhatIf
    Show what would be installed.

    .NOTES
    Installs or updates software on this computer.

    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It runs npm through Invoke-Salesforce, which runs a program with an argument array. The program is found on the PATH when the cmdlet runs.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param()
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    # npm is the Salesforce-supported install on Windows, Linux and macOS. It downloads and runs code from the npm registry.
    if ($PSCmdlet.ShouldProcess('@salesforce/cli', 'Install globally with npm')) {
        Invoke-Salesforce -FilePath 'npm' -Arguments @('install', '--global', '@salesforce/cli') @commonParams
    }
}

function Update-SalesforceCli {
    <#
    .SYNOPSIS
    Updates the Salesforce CLI installed with npm.

    .DESCRIPTION
    Runs npm update --global @salesforce/cli. It downloads and runs code from the npm registry. Supports -WhatIf and -Confirm.

    .EXAMPLE
    Update-SalesforceCli -WhatIf
    Show what would be updated.

    .NOTES
    Installs or updates software on this computer.

    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It runs npm through Invoke-Salesforce, which runs a program with an argument array. The program is found on the PATH when the cmdlet runs.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param()
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($PSCmdlet.ShouldProcess('@salesforce/cli', 'Update globally with npm')) {
        Invoke-Salesforce -FilePath 'npm' -Arguments @('update', '--global', '@salesforce/cli') @commonParams
    }
}

function Install-SalesforcePlugin {
    <#
    .SYNOPSIS
    Installs a Salesforce CLI plugin (sf plugins install).

    .DESCRIPTION
    A plugin is code that runs with your permissions, so install only plugins you trust: the CLI may ask you to confirm one that is not on its
    allow list. -Name is an npm package name (optionally scoped and with a version, such as @salesforce/plugin-agent@latest) or a GitHub URL. A
    value that starts with a dash or contains spaces or control characters is refused, so it cannot be read as a CLI option. Supports -WhatIf and -Confirm.

    .PARAMETER Name
    The plugin to install: an npm package name such as @salesforce/plugin-agent, optionally with a version, or a GitHub URL. A value that starts with a dash or contains spaces or control characters is refused, so it cannot be read as a CLI option. Required.

    .EXAMPLE
    Install-SalesforcePlugin -Name @salesforce/plugin-agent -WhatIf

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins install (plugin @oclif/plugin-plugins)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --force, --help, --silent, --verbose
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/oclif/plugin-plugins

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][string] $Name
    )
    if ($Name -notmatch '^[A-Za-z0-9@][A-Za-z0-9@._~/:+#-]*\z') {
        throw "Plugin name '$Name' is not valid. Use an npm package name such as @salesforce/plugin-agent, or a GitHub URL; it must not start with a dash or contain spaces."
    }
    $arguments = @('plugins', 'install', $Name)
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($PSCmdlet.ShouldProcess($Name, 'Install Salesforce CLI plugin')) {
        Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    }
}

function Get-SalesforcePlugins {
    <#
    .SYNOPSIS
    Lists the Salesforce CLI plugins that are installed.

    .DESCRIPTION
    Runs sf plugins and returns the CLI's own text output, one plugin per line. Add -IncludeCore to include the plugins that ship with the CLI.

    .PARAMETER IncludeCore
    Also list the plugins that ship with the Salesforce CLI. Adds --core.

    .EXAMPLE
    Get-SalesforcePlugins -IncludeCore
    Every plugin, including the bundled ones.

    .NOTES
    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins (plugin @oclif/plugin-plugins)
      Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
    Parameter to flag: -IncludeCore = --core.
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/oclif/plugin-plugins

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][switch] $IncludeCore
    )
    $arguments = @('plugins')
    if ($IncludeCore) { $arguments += '--core' }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
}

function Update-SalesforcePlugins {
    <#
    .SYNOPSIS
    Updates the installed Salesforce CLI plugins.

    .DESCRIPTION
    Runs sf plugins update. Supports -WhatIf and -Confirm.

    .EXAMPLE
    Update-SalesforcePlugins -WhatIf
    Show what would be updated.

    .NOTES
    Installs or updates software on this computer.

    Salesforce CLI mapping
    Executable: sf, found on the PATH when the cmdlet runs. psfdx does not store a path or a CLI version.
    Command run: sf plugins update (plugin @oclif/plugin-plugins)
      Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --help, --verbose
    psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/oclif/plugin-plugins

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param()
    $arguments = @('plugins', 'update')
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($PSCmdlet.ShouldProcess('installed Salesforce CLI plugins', 'Update')) {
        Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    }
}

#endregion

#region Utilities

function Get-SalesforceDateTime {
    <#
    .SYNOPSIS
    Formats a date and time as a SOQL datetime literal.

    .DESCRIPTION
    Returns the value in UTC as 2026-11-18T11:00:00Z, ready to use in a SOQL WHERE clause. With no value it uses the current time. A local or unspecified time is converted to UTC first. It is a thin wrapper over ConvertTo-SalesforceSoqlDateTime.

    .PARAMETER Datetime
    The moment to format. Defaults to now. A local or unspecified kind is read as local time and converted to UTC.

    .EXAMPLE
    Get-SalesforceDateTime (Get-Date).AddDays(-1)
    Yesterday, as a literal for a CreatedDate filter.

    .NOTES
    Salesforce CLI mapping
    This cmdlet does not run an sf command.
    It works locally in PowerShell and .NET.

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][datetime] $Datetime)
    if ($null -eq $Datetime) { $Datetime = Get-Date }
    return ConvertTo-SalesforceSoqlDateTime -Value $Datetime
}

#endregion
