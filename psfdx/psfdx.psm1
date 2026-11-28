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
    #   Whichever copy is chosen, its helpers are then bound as private functions of the importing module (see $bindHelpers below).
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

    # psfdx-shared exports nothing, so none of its helpers is a public command (Get-Command -Module psfdx* never lists them).
    # Each module binds the helpers it needs as private functions of its own: a function keeps running in psfdx-shared's own scope,
    # so the helpers still reach each other, and the importing module's manifest decides which of them it exports (the public ones
    # that belong to the core module). Nothing is copied, so a fix in psfdx-shared reaches every module.
    $bindHelpers = {
        param([System.Management.Automation.PSModuleInfo] $Shared)
        $helpers = & $Shared { param($Name) Get-ChildItem -Path function: | Where-Object { $_.ModuleName -eq $Name } } $Shared.Name
        foreach ($helper in $helpers) { Set-Item -Path ('function:script:' + $helper.Name) -Value $helper.ScriptBlock }
    }

    $loaded = @(Get-Module -Name $ModuleName -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending)
    $loadedCompatible = @($loaded | Where-Object { & $isCompatible $_.Version }) | Select-Object -First 1
    if ($loadedCompatible) {
        Import-Module -ModuleInfo $loadedCompatible -ErrorAction Stop
        & $bindHelpers $loadedCompatible
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
            $imported = Import-Module -Name $match.Path -ErrorAction Stop -PassThru
            & $bindHelpers $imported
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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org login web (plugin @salesforce/plugin-auth)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Sandbox = --instance-url https://test.salesforce.com; -CustomUrl = --instance-url; -Alias = --alias; -SetDefault = --set-default; -SetDefaultDevHub = --set-default-dev-hub; -Browser = --browser; -OAuthClientId = --client-id; -ClientApp = --client-app; -Scopes = --scopes; -Username = --username.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org login sfdx-url (plugin @salesforce/plugin-auth)
          Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --sfdx-url-stdin
        Parameter to flag: -SfdxUrlFile = --sfdx-url-file; -Alias = --alias; -SetDefault = --set-default; -SetDefaultDevHub = --set-default-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org logout (plugin @salesforce/plugin-auth)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -All = --all; -TargetOrg = --target-org; -ClientApp = --client-app; -NoPrompt = --no-prompt.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org login jwt (plugin @salesforce/plugin-auth)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -ConsumerKey = --client-id; -TargetOrg = --username; -JwtKeyfile = --jwt-key-file; -Alias = --alias; -SetDefault = --set-default; -SetDefaultDevHub = --set-default-dev-hub.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org open (plugin @salesforce/plugin-org)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetOrg = --target-org; -UrlOnly = --url-only; -Browser = --browser; -BrowserPrivateMode = --private; -Path = --path; -SourceFile = --source-file.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org list (plugin @salesforce/plugin-org)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -ShowVerboseDetails = --verbose.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER ShowVerboseDetails
    List more information about each org. Adds --verbose.

    .EXAMPLE
    Get-SalesforceConnections | Format-Table username, alias, connectedStatus
    A quick overview of connected orgs.

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org list (plugin @salesforce/plugin-org)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -NoPrompt = --no-prompt.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org display (plugin @salesforce/plugin-org)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetOrg = --target-org; -ShowVerboseDetails = --verbose.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .PARAMETER ShowVerboseDetails
    Include more details, such as the Salesforce DX authorization URL (removed again unless you pass -IncludeToken). Adds --verbose.

    .PARAMETER IncludeToken
    Return the CLI result as it is, with accessToken and sfdxAuthUrl. Without it psfdx removes accessToken, refreshToken, sfdxAuthUrl, password, clientSecret and privateKey from the result.

    .EXAMPLE
    Get-SalesforceOrgDetails -TargetOrg dev1
    Show the org ID, instance URL and status of dev1, without any token.

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org list auth (plugin @salesforce/plugin-auth)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .EXAMPLE
    Get-SalesforceAuthorizations | Format-Table username, aliases, instanceUrl
    A quick overview of the saved logins.

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

# How long Connect-SalesforceAccessToken waits for another login in the same process to finish. A login takes seconds.
$script:PsfdxAccessTokenLockTimeoutMs = 60000

function Connect-SalesforceAccessToken {
    <#
    .SYNOPSIS
    Logs in to an org with an access token you already have.

    .DESCRIPTION
    Runs sf org login access-token. Give the org's instance URL and the access token as a SecureString. The token is handed to the CLI in the SF_ACCESS_TOKEN environment variable of the sf process only, never on the command line, and the variable is put back to its earlier value afterwards. The login is saved on this computer so other psfdx cmdlets can use the org. The authorization cannot be refreshed, so it stops working when the token expires. Because the environment belongs to the whole process, logins started at the same time in one PowerShell process run one after the other. The URL must be an absolute https URL, because the token is sent to it. Tokens and authorization URLs are removed from the result.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org login access-token (plugin @salesforce/plugin-auth)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -InstanceUrl = --instance-url; -Alias = --alias; -SetDefault = --set-default; -SetDefaultDevHub = --set-default-dev-hub; -NoPrompt = --no-prompt. -AccessToken is not a flag: the CLI reads it from the SF_ACCESS_TOKEN environment variable.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

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
    # The environment is shared by every runspace in the process, so two logins at once (ForEach-Object -Parallel, jobs in
    # one process) could start sf with each other's token and log in to the wrong org. One lock, shared by all runspaces
    # because the interned string is one object per process, lets only one login set, use and restore the variable at a time.
    $variable = 'SF_ACCESS_TOKEN'
    $gate = [string]::Intern('psfdx.Connect-SalesforceAccessToken.SF_ACCESS_TOKEN')
    if (-not [System.Threading.Monitor]::TryEnter($gate, $script:PsfdxAccessTokenLockTimeoutMs)) {
        throw 'Another Connect-SalesforceAccessToken call in this process is still running. Run the logins one after the other.'
    }
    try {
        # Finish discovery before exposing the temporary token. Invoke the resolved path
        # directly so a failed launch cannot start dependency recovery with the token set.
        $cliPath = Get-PsfdxCliPath
        $previous = [Environment]::GetEnvironmentVariable($variable)
        try {
            [Environment]::SetEnvironmentVariable($variable, (ConvertTo-SalesforcePlainSecret -Value $AccessToken -Name 'AccessToken'))
            $result = Invoke-Salesforce -FilePath 'sf' -ResolvedCliPath $cliPath -Arguments $arguments @commonParams
        }
        finally {
            [Environment]::SetEnvironmentVariable($variable, $previous)
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($gate)
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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf alias list (plugin @salesforce/plugin-settings)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .EXAMPLE
    Get-SalesforceAlias
    List every alias.

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf alias set (plugin @salesforce/plugin-settings)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Alias
    The alias to create, for example prod or dev1. Setting an alias that already exists replaces it. Required.

    .PARAMETER TargetOrg
    Username, or an existing alias, that the new alias should point to. Required.

    .EXAMPLE
    Add-SalesforceAlias -Alias dev1 -TargetOrg user@example.com.dev1
    Create the alias dev1 for that username.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

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
    Removes one org alias, or all of them, from this computer.

    .DESCRIPTION
    Runs sf alias unset. Only the local aliases are removed; the orgs are not touched. Give -Alias to remove one, or -All to remove every alias, which asks for confirmation first because it cannot be undone. Supports -WhatIf. -NoPrompt skips the question so a script can run unattended; psfdx always passes --no-prompt to the CLI itself after it has asked, so the CLI never waits for an answer.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf alias unset (plugin @salesforce/plugin-settings)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -All = --all; -NoPrompt = --no-prompt.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Alias
    The alias to remove. Required unless -All is given.

    .PARAMETER All
    Remove all the aliases that are set. Cannot be used with -Alias. Adds --all.

    .PARAMETER NoPrompt
    Do not ask for confirmation when removing all the aliases. Adds --no-prompt.

    .EXAMPLE
    Remove-SalesforceAlias -Alias dev1
    Remove the alias dev1.

    .EXAMPLE
    Remove-SalesforceAlias -All -WhatIf
    Show that every alias would be removed.

    .NOTES
    Changes local files or local Salesforce CLI configuration on this computer.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-settings

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string] $Alias,
        [Parameter(Mandatory = $false)][switch] $All,
        [Parameter(Mandatory = $false)][switch] $NoPrompt
    )
    if ($Alias -and $All) { throw 'Use -Alias or -All, not both.' }
    if (-not $Alias -and -not $All) { throw 'Give the -Alias to remove, or -All to remove every alias.' }
    $arguments = @('alias', 'unset')
    if ($All) { $arguments += @('--all', '--no-prompt') } else { $arguments += $Alias }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    # One alias keeps the old behaviour (no question). Removing every alias cannot be undone, so it asks unless -NoPrompt is given.
    if ($All) {
        if ($NoPrompt) { $ConfirmPreference = 'None' }
        elseif (-not $PSBoundParameters.ContainsKey('Confirm')) { $ConfirmPreference = 'Medium' }
    }
    $target = $Alias
    if ($All) { $target = 'every local alias' }
    if (-not $PSCmdlet.ShouldProcess($target, 'Remove alias')) { return }
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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org list limits (plugin @salesforce/plugin-limits)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceLimits -TargetOrg prod | Where-Object remaining -lt 1000
    Limits that are nearly used up.

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

function Get-SalesforceDataStorage {
    <#
    .SYNOPSIS
    Shows how much data storage an org has used.

    .DESCRIPTION
    Reads the org limits with Get-SalesforceLimits and returns the DataStorageMB entry with InUse and Usage (percentage) added. Returns nothing if the org does not report that limit.

    SALESFORCE CLI
        This cmdlet does not run an sf command.
        It is built on other psfdx cmdlets: Get-SalesforceLimits. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .PARAMETER TargetOrg
    Username or alias of the org to check. If omitted, the Salesforce CLI uses the default target org (passed on to Get-SalesforceLimits).

    .EXAMPLE
    Get-SalesforceDataStorage -TargetOrg prod
    Data storage used, in MB and as a percentage.

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

    SALESFORCE CLI
        This cmdlet does not run an sf command.
        It is built on other psfdx cmdlets: Get-SalesforceLimits. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .PARAMETER TargetOrg
    Username or alias of the org to check. If omitted, the Salesforce CLI uses the default target org (passed on to Get-SalesforceLimits).

    .EXAMPLE
    Get-SalesforceApiUsage -TargetOrg prod
    See the API usage of the production org.

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

#region User queries

function Get-SalesforceUsers {
    <#
    .SYNOPSIS
    Lists users of an org, newest login first.

    .DESCRIPTION
    Queries User (Id, Name, Username, Email, IsActive, LastLoginDate) through Select-SalesforceRecords, ordered by LastLoginDate descending. Values are escaped as SOQL literals.

    SALESFORCE CLI
        This cmdlet does not run an sf command.
        It is built on other psfdx cmdlets: Select-SalesforceRecords. They run the sf commands; this cmdlet adds PowerShell logic on top.

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

#endregion

#region Data Trees

# Wraps `sf data export tree` and `sf data import tree`: copy related records (parent and child) between orgs as JSON files.
# Both use the SObject Tree API, which handles at most 200 records per import and is meant for test data, not bulk loads (see
# Import-SalesforceBulkData for those).

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

    SALESFORCE CLI
        This cmdlet does not run an sf command.
        It calls the Salesforce REST API directly with Invoke-RestMethod, with no Salesforce CLI involved.

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

    SALESFORCE CLI
        This cmdlet does not run an sf command.
        It calls the Salesforce REST API directly with Invoke-RestMethod, with no Salesforce CLI involved.

    .PARAMETER Url
    Absolute https:// URL of the REST resource. Required.

    .PARAMETER AccessToken
    Access token to send as the bearer token, for example from Connect-SalesforceApi. Required.

    .PARAMETER Method
    HTTP method: GET (default), POST, PATCH or DELETE. Default: "GET". Valid values: GET, POST, PATCH, DELETE.

    .EXAMPLE
    Invoke-SalesforceApi -Url https://example.my.salesforce.com/services/data -AccessToken $token
    List the API versions of an org.

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf api request rest (plugin @salesforce/plugin-api)
          Flags of this command that psfdx does not pass (across all psfdx cmdlets that run it): --file, --header, --include, --stream-to-file
          Values psfdx cannot pass: --method POST, PUT, HEAD, DELETE, OPTIONS, TRACE
        Parameter to flag: -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceApiVersions -TargetOrg dev1 | Select-Object -Last 1
    The newest API version of the org.

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

    SALESFORCE CLI
        This cmdlet does not run an sf command.
        It is built on other psfdx cmdlets: Get-SalesforceApiVersions. They run the sf commands; this cmdlet adds PowerShell logic on top.

    .PARAMETER TargetOrg
    Username or alias of the org to ask. If omitted, the Salesforce CLI uses the default target org (passed on to Get-SalesforceApiVersions).

    .EXAMPLE
    Get-SalesforceLatestApiVersion -TargetOrg dev1
    For example v62.0.

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org list users (plugin @salesforce/plugin-user)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceAuthenticatedUser -TargetOrg myscratch

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org display user (plugin @salesforce/plugin-user)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceOrgUser -TargetOrg myscratch

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org create user (plugin @salesforce/plugin-user)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -DefinitionFile = --definition-file; -SetAlias = --set-alias; -SetUniqueUsername = --set-unique-username; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org generate password (plugin @salesforce/plugin-user)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -OnBehalfOf = --on-behalf-of; -Length = --length; -Complexity = --complexity; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org assign permset (plugin @salesforce/plugin-user)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Name
    Passed on to Test-SalesforceAssignmentNames -Name. Required.

    .PARAMETER OnBehalfOf
    Passed on to Test-SalesforceAssignmentNames -OnBehalfOf.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Grant-SalesforcePermissionSet -Name Sales_Admin, Reports_User -OnBehalfOf qa1, qa2 -TargetOrg myscratch -Confirm:$false

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

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf org assign permsetlicense (plugin @salesforce/plugin-user)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Name
    Passed on to Test-SalesforceAssignmentNames -Name. Required.

    .PARAMETER OnBehalfOf
    Passed on to Test-SalesforceAssignmentNames -OnBehalfOf.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Grant-SalesforcePermissionSetLicense -Name SalesforceCPQ_Admin -OnBehalfOf qa1 -TargetOrg myscratch -Confirm:$false

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

    Commands that use sf check for Salesforce CLI v2 or newer when first needed. If sf is missing, set PSFDX_CLI_INSTALL to Prompt for an interactive confirmation, or Install to authorize unattended npm installation. The default is Never. Bootstrap can refresh the current session's PATH from npm and does not upgrade a CLI it finds.

    SALESFORCE CLI
        This cmdlet does not run an sf command.
        It runs npm through Invoke-Salesforce, which runs a program with an argument array. The program is found on the PATH when the cmdlet runs.

    .EXAMPLE
    Install-SalesforceCli -WhatIf
    Show what would be installed.

    .NOTES
    Installs or updates software on this computer.

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
        Invoke-Salesforce -FilePath 'npm' -Arguments @('install', '--global', '@salesforce/cli') -RequireSuccessfulExit @commonParams
    }
}

function Update-SalesforceCli {
    <#
    .SYNOPSIS
    Updates the Salesforce CLI installed with npm.

    .DESCRIPTION
    Runs npm update --global @salesforce/cli. It downloads and runs code from the npm registry. Supports -WhatIf and -Confirm.

    SALESFORCE CLI
        This cmdlet does not run an sf command.
        It runs npm through Invoke-Salesforce, which runs a program with an argument array. The program is found on the PATH when the cmdlet runs.

    .EXAMPLE
    Update-SalesforceCli -WhatIf
    Show what would be updated.

    .NOTES
    Installs or updates software on this computer.

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

#endregion

#region Utilities

function Get-SalesforceDateTime {
    <#
    .SYNOPSIS
    Formats a date and time as a SOQL datetime literal.

    .DESCRIPTION
    Returns the value in UTC as 2026-11-18T11:00:00Z, ready to use in a SOQL WHERE clause. With no value it uses the current time. A local or unspecified time is converted to UTC first. It is a thin wrapper over ConvertTo-SalesforceSoqlDateTime.

    SALESFORCE CLI
        This cmdlet does not run an sf command.
        It works locally in PowerShell and .NET.

    .PARAMETER Datetime
    The moment to format. Defaults to now. A local or unspecified kind is read as local time and converted to UTC.

    .EXAMPLE
    Get-SalesforceDateTime (Get-Date).AddDays(-1)
    Yesterday, as a literal for a CreatedDate filter.

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

#region Experience Cloud

# Wraps sf community: list the site templates, create a site and publish it. New-SalesforceExperienceSite (psfdx-development) writes site files into a project instead.

function Get-SalesforceCommunityTemplates {
    <#
    .SYNOPSIS
    Lists the Experience Cloud site templates available in an org.

    .DESCRIPTION
    Runs sf community list template and returns one object per template. Use a template name with New-SalesforceCommunity. It only reads.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf community list template (plugin @salesforce/plugin-community)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Get-SalesforceCommunityTemplates -TargetOrg dev1
    The templates the org offers.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-community

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('community', 'list', 'template')
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function New-SalesforceCommunity {
    <#
    .SYNOPSIS
    Creates an Experience Cloud site in an org from a template.

    .DESCRIPTION
    Runs sf community create. The site is created in the org, as a draft that is not live yet; make it live with Publish-SalesforceCommunity. Digital Experiences must be turned on in the org. Supports -WhatIf and -Confirm; it does not prompt by default. To write the files of a site into a project instead, use New-SalesforceExperienceSite.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf community create (plugin @salesforce/plugin-community)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Name = --name; -TemplateName = --template-name; -UrlPathPrefix = --url-path-prefix; -Description = --description; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Name
    Name of the site. Passed to sf as --name. Required.

    .PARAMETER TemplateName
    Template to build the site from, as listed by Get-SalesforceCommunityTemplates. Passed to sf as --template-name. Required.

    .PARAMETER UrlPathPrefix
    URL path prefix of the site, appended to the domain of the org. Letters and digits only. Passed to sf as --url-path-prefix.

    .PARAMETER Description
    Description of the site. Passed to sf as --description.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    New-SalesforceCommunity -Name 'Partner Portal' -TemplateName 'Customer Service' -UrlPathPrefix partners -TargetOrg dev1 -WhatIf
    Preview creating a site.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-community

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $TemplateName,
        [Parameter(Mandatory = $false)][ValidatePattern('^[A-Za-z0-9]+\z')][string] $UrlPathPrefix,
        [Parameter(Mandatory = $false)][string] $Description,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('community', 'create', '--name', $Name, '--template-name', $TemplateName)
    if ($UrlPathPrefix) { $arguments += @('--url-path-prefix', $UrlPathPrefix) }
    if ($Description) { $arguments += @('--description', $Description) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if (-not $PSCmdlet.ShouldProcess($Name, 'Create Experience Cloud site')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

function Publish-SalesforceCommunity {
    <#
    .SYNOPSIS
    Publishes an Experience Builder site to make its changes live.

    .DESCRIPTION
    Runs sf community publish. Publishing makes the current draft of the site visible to its visitors, and it cannot be taken back with one command. Asks for confirmation and supports -WhatIf; -NoPrompt skips the question. The CLI command has no prompt of its own.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf community publish (plugin @salesforce/plugin-community)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Name = --name; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Name
    Name of the site to publish. Passed to sf as --name. Required.

    .PARAMETER NoPrompt
    Do not ask for confirmation. The CLI command has no prompt flag, so this only skips the PowerShell confirmation; it does not turn off -WhatIf.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Publish-SalesforceCommunity -Name 'Partner Portal' -TargetOrg dev1 -WhatIf
    Preview publishing the site.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-community

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Name,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('community', 'publish', '--name', $Name)
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($NoPrompt) { $ConfirmPreference = 'None' }
    if (-not $PSCmdlet.ShouldProcess($Name, 'Publish Experience Cloud site (makes it live)')) { return }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion

#region GraphQL and REST requests

# Wraps sf api request graphql and rest. They call the API as the CLI's logged-in user, so no token is handled here.

function Invoke-SalesforceText {
    # Private: runs an sf command whose result is text (a response body, plugin output). Invoke-Salesforce only checks the exit code in JSON mode,
    # so a failure would otherwise come back as if it had worked. The text goes in the error's message and in its TargetObject. When the Windows
    # .cmd launcher refuses an argument, the Hint says what to do instead.
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [Parameter(Mandatory = $false)][hashtable] $CommonParams = @{},
        [Parameter(Mandatory = $false)][string] $Hint
    )
    $global:LASTEXITCODE = 0
    try { $output = Invoke-Salesforce -FilePath 'sf' -Arguments $Arguments @CommonParams }
    catch {
        if ($Hint -and $_.Exception.Message -like '*cannot be passed safely*') { throw "$Hint ($($_.Exception.Message))" }
        throw
    }
    $exitCode = $global:LASTEXITCODE
    $text = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string] $_ })).Trim()
    if ($exitCode -ne 0) {
        $shown = $text
        if ($shown.Length -gt 4000) { $shown = $shown.Substring(0, 4000) + '...' }
        $command = ($Arguments | Where-Object { $_ -and -not $_.StartsWith('-') } | Select-Object -First 3) -join ' '
        $message = "sf $command exited with code $exitCode."
        if ($shown) { $message += " $shown" }
        $record = New-Object System.Management.Automation.ErrorRecord ((New-Object System.InvalidOperationException $message), 'PsfdxRequestFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $text)
        throw $record
    }
    return $text
}

function Invoke-SalesforceGraphQL {
    <#
    .SYNOPSIS
    Runs a GraphQL statement against an org with the CLI's login.

    .DESCRIPTION
    Runs sf api request graphql, which sends a GraphQL query or mutation to the Salesforce GraphQL API as the user you are logged in as. Give the statement as -Query, or put it in a file and give -QueryFile. The response is returned as text, or as an object with -AsObject. A mutation changes data, so a statement that starts with mutation asks for confirmation and supports -WhatIf; a query does not. A response the server marks as an error makes the cmdlet throw (PsfdxRequestFailed). On Windows the CLI's .cmd launcher cannot take a statement with a double quote or a line break, so use -QueryFile there.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf api request graphql (plugin @salesforce/plugin-api)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Query = --body; -Include = --include; -StreamToFile = --stream-to-file; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Query
    The GraphQL statement. Use it or -QueryFile. Passed to sf as --body.

    .PARAMETER QueryFile
    Path of a file that holds the GraphQL statement. It must exist. Use it or -Query. Passed to sf as --body.

    .PARAMETER Include
    Include the HTTP status and headers in the output. Adds --include.

    .PARAMETER StreamToFile
    Write the response to this file instead of returning it. Cannot be used with -Include or -AsObject. Passed to sf as --stream-to-file.

    .PARAMETER AsObject
    Return the response converted from JSON instead of text. Not with -Include or -StreamToFile.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Invoke-SalesforceGraphQL -Query 'query { uiapi { query { Account { edges { node { Id Name { value } } } } } } }' -AsObject -TargetOrg dev1
    Query accounts and get an object.

    .EXAMPLE
    Invoke-SalesforceGraphQL -QueryFile .\accounts.graphql -StreamToFile .\accounts.json -TargetOrg dev1
    Run a statement from a file and save the response.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-api

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $false)][string] $Query,
        [Parameter(Mandatory = $false)][string] $QueryFile,
        [Parameter(Mandatory = $false)][switch] $Include,
        [Parameter(Mandatory = $false)][string] $StreamToFile,
        [Parameter(Mandatory = $false)][switch] $AsObject,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $given = 0
    if ($Query) { $given++ }
    if ($QueryFile) { $given++ }
    if ($given -ne 1) { throw 'Give exactly one of -Query and -QueryFile.' }
    if ($QueryFile -and -not (Test-Path -LiteralPath $QueryFile -PathType Leaf)) { throw "Query file '$QueryFile' does not exist." }
    if ($Include -and $StreamToFile) { throw 'Use -Include or -StreamToFile, not both.' }
    if ($AsObject -and ($Include -or $StreamToFile)) { throw '-AsObject needs the plain response, so it cannot be used with -Include or -StreamToFile.' }
    if ($StreamToFile) {
        $parent = Split-Path -Path $StreamToFile -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Output folder '$parent' does not exist." }
    }
    $statement = $Query
    $bodyPath = $null
    if ($QueryFile) {
        $bodyPath = (Resolve-Path -LiteralPath $QueryFile).ProviderPath
        $statement = [System.IO.File]::ReadAllText($bodyPath)
    }
    $arguments = @('api', 'request', 'graphql')
    if ($bodyPath) { $arguments += @('--body', $bodyPath) } else { $arguments += @('--body', $Query) }
    if ($Include) { $arguments += '--include' }
    if ($StreamToFile) { $arguments += @('--stream-to-file', $PSCmdlet.GetUnresolvedProviderPathFromPSPath($StreamToFile)) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($statement -match '(?im)^\s*mutation\b') {
        # A mutation asks by default. An explicit -Confirm:$false skips the question.
        if (-not $PSBoundParameters.ContainsKey('Confirm')) { $ConfirmPreference = 'Medium' }
        if (-not $PSCmdlet.ShouldProcess($(if ($TargetOrg) { $TargetOrg } else { 'the default org' }), 'Run a GraphQL mutation (changes data)')) { return }
    }
    $hint = $null
    if ($Query) { $hint = 'The statement has a double quote or a line break, which the Salesforce CLI''s Windows .cmd launcher cannot be given safely. Put it in a file and use -QueryFile instead.' }
    $text = Invoke-SalesforceText -Arguments $arguments -CommonParams $commonParams -Hint $hint
    if ($AsObject) { return ($text | ConvertFrom-Json) }
    return $text
}

function Invoke-SalesforceRestRequest {
    <#
    .SYNOPSIS
    Makes an authenticated Salesforce REST API request with the CLI's login.

    .DESCRIPTION
    Runs sf api request rest, which calls any REST endpoint as the user you are logged in as, so you need no token. The response is returned as text, or as an object with -AsObject. A request that changes data (POST, PUT, PATCH or DELETE) asks for confirmation and supports -WhatIf; a read does not. An error response makes the cmdlet throw (PsfdxRequestFailed). Give the body as -Body, as a file with -BodyFile, or give the whole request (URL, method, headers and body) in a JSON -File. On Windows the CLI's .cmd launcher cannot take a body with a double quote, which JSON always has, so use -BodyFile or -File there. For the other psfdx REST helpers see Invoke-SalesforceApi, which uses an access token instead.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf api request rest (plugin @salesforce/plugin-api)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Method = --method; -Body = --body; -File = --file; -Header = --header; -Include = --include; -StreamToFile = --stream-to-file; -TargetOrg = --target-org.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Url
    The endpoint, for example /services/data/v62.0/limits. Not needed if -File holds it. It is an argument of the command, not a flag.

    .PARAMETER Method
    HTTP method. Valid values: GET, POST, PUT, PATCH, HEAD, DELETE, OPTIONS, TRACE. The CLI default is GET. Passed to sf as --method.

    .PARAMETER Body
    The request body as text. Use one of -Body, -BodyFile and -File. Passed to sf as --body.

    .PARAMETER BodyFile
    Path of a file that holds the request body. It must exist. The cmdlet sends it as --body @path. Use one of -Body, -BodyFile and -File.

    .PARAMETER File
    Path of a JSON file that holds the URL, method, headers and body. It must exist. Use one of -Body, -BodyFile and -File. Passed to sf as --file.

    .PARAMETER Header
    HTTP headers as name and value pairs. Each is passed to sf as its own --header name:value. Names are checked and a value may not contain a line break. Passed to sf as --header.

    .PARAMETER Include
    Include the HTTP status and headers in the output. Cannot be used with -StreamToFile or -AsObject. Adds --include.

    .PARAMETER StreamToFile
    Write the response to this file instead of returning it. Cannot be used with -Include or -AsObject. Passed to sf as --stream-to-file.

    .PARAMETER AsObject
    Return the response converted from JSON instead of text.

    .PARAMETER TargetOrg
    Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

    .EXAMPLE
    Invoke-SalesforceRestRequest -Url /services/data/v62.0/limits -AsObject -TargetOrg dev1
    Read the org limits as an object.

    .EXAMPLE
    Invoke-SalesforceRestRequest -Url /services/data/v62.0/sobjects/Account -Method POST -BodyFile .\account.json -TargetOrg dev1 -WhatIf
    Preview creating an account from a file.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-api

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $false)][ValidatePattern('^[^\s]+\z')][string] $Url,
        [Parameter(Mandatory = $false)][ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'HEAD', 'DELETE', 'OPTIONS', 'TRACE')][string] $Method,
        [Parameter(Mandatory = $false)][string] $Body,
        [Parameter(Mandatory = $false)][string] $BodyFile,
        [Parameter(Mandatory = $false)][string] $File,
        [Parameter(Mandatory = $false)][System.Collections.IDictionary] $Header,
        [Parameter(Mandatory = $false)][switch] $Include,
        [Parameter(Mandatory = $false)][string] $StreamToFile,
        [Parameter(Mandatory = $false)][switch] $AsObject,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $given = 0
    if ($Body) { $given++ }
    if ($BodyFile) { $given++ }
    if ($File) { $given++ }
    if ($given -gt 1) { throw 'Use only one of -Body, -BodyFile and -File.' }
    if (-not $Url -and -not $File) { throw 'Give -Url, or a -File that holds the URL.' }
    if ($BodyFile -and -not (Test-Path -LiteralPath $BodyFile -PathType Leaf)) { throw "Body file '$BodyFile' does not exist." }
    if ($File -and -not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "Request file '$File' does not exist." }
    if ($Include -and $StreamToFile) { throw 'Use -Include or -StreamToFile, not both.' }
    if ($AsObject -and ($Include -or $StreamToFile)) { throw '-AsObject needs the plain response, so it cannot be used with -Include or -StreamToFile.' }
    if ($StreamToFile) {
        $parent = Split-Path -Path $StreamToFile -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Output folder '$parent' does not exist." }
    }
    $headerPairs = @()
    if ($null -ne $Header) {
        foreach ($key in $Header.Keys) {
            $name = [string] $key
            $value = [System.Convert]::ToString($Header[$key], [System.Globalization.CultureInfo]::InvariantCulture)
            if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*\z') { throw "'$name' is not a valid header name." }
            if ($value -match '[\r\n]') { throw "The value of header '$name' contains a line break." }
            $headerPairs += "${name}:$value"
        }
    }
    $arguments = @('api', 'request', 'rest')
    if ($Url) { $arguments += $Url }
    if ($Method) { $arguments += @('--method', $Method) }
    if ($Body) { $arguments += @('--body', $Body) }
    if ($BodyFile) { $arguments += @('--body', ('@' + (Resolve-Path -LiteralPath $BodyFile).ProviderPath)) }
    if ($File) { $arguments += @('--file', (Resolve-Path -LiteralPath $File).ProviderPath) }
    foreach ($pair in $headerPairs) { $arguments += @('--header', $pair) }
    if ($Include) { $arguments += '--include' }
    if ($StreamToFile) { $arguments += @('--stream-to-file', $PSCmdlet.GetUnresolvedProviderPathFromPSPath($StreamToFile)) }
    if ($PSBoundParameters.ContainsKey('TargetOrg') -and -not [string]::IsNullOrWhiteSpace($TargetOrg)) { $arguments += @('--target-org', $TargetOrg) }
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    # The method may be in the request file. Read it, so a write there is confirmed too; a file that cannot be read is treated as a write.
    $effectiveMethod = $Method
    if (-not $effectiveMethod -and $File) {
        $effectiveMethod = 'POST'
        try {
            $request = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $File).ProviderPath) | ConvertFrom-Json
            $effectiveMethod = 'GET'
            if ($request -and $request.method) { $effectiveMethod = ([string] $request.method).ToUpperInvariant() }
        } catch { }
    }
    if ($effectiveMethod -in 'POST', 'PUT', 'PATCH', 'DELETE') {
        # A write asks by default. An explicit -Confirm:$false skips the question.
        if (-not $PSBoundParameters.ContainsKey('Confirm')) { $ConfirmPreference = 'Medium' }
        if (-not $PSCmdlet.ShouldProcess($(if ($Url) { $Url } else { $File }), "$effectiveMethod request")) { return }
    }
    $hint = $null
    if ($Body) { $hint = 'The body has a double quote or a line break, which the Salesforce CLI''s Windows .cmd launcher cannot be given safely. Put it in a file and use -BodyFile instead.' }
    $text = Invoke-SalesforceText -Arguments $arguments -CommonParams $commonParams -Hint $hint
    if ($AsObject) { return ($text | ConvertFrom-Json) }
    return $text
}

#endregion

#region Diagnostics

# Wraps sf doctor.

function Invoke-SalesforceDoctor {
    <#
    .SYNOPSIS
    Runs the Salesforce CLI diagnostics and writes a report of its setup and problems.

    .DESCRIPTION
    Runs sf doctor, which gathers the CLI's configuration and runs checks to find problems in your environment. The results are written to files in the output folder. With -Command it also runs that command in debug mode and logs it. -CreateIssue goes further: it opens a new issue on the Salesforce CLI's GitHub repository with the diagnostic results attached, which shares information about your machine outside it, so it asks for confirmation first. Supports -WhatIf and -Confirm.

    SALESFORCE CLI
        Executable: sf. PSFDX checks for Salesforce CLI v2 or newer and caches the executable path in the current session.
        Command run: sf doctor (plugin @salesforce/plugin-info)
          Every flag of this command is passed by some psfdx cmdlet (apart from --flags-dir and --api-version).
        Parameter to flag: -Command = --command; -Plugin = --plugin; -OutputDirectory = --output-dir; -CreateIssue = --create-issue.
        psfdx adds --json when it needs to read the result. It does not pass --api-version or --flags-dir.

    .PARAMETER Command
    A CLI command to run in debug mode, for example 'org list'. Its results go to a log file. Passed to sf as --command.

    .PARAMETER Plugin
    Only run the diagnostics of this plugin. Passed to sf as --plugin.

    .PARAMETER OutputDirectory
    Folder to save the created files in, instead of the current folder. It must exist. Passed to sf as --output-dir.

    .PARAMETER CreateIssue
    Create a new issue on the Salesforce CLI's GitHub repository with the diagnostic results attached. Asks for confirmation first. Adds --create-issue.

    .EXAMPLE
    Invoke-SalesforceDoctor -OutputDirectory .\doctor
    Run the diagnostics and keep the files in a folder.

    .NOTES
    Changes data or settings in the org. Try it with -WhatIf first where the cmdlet supports it.

    .LINK
    https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html

    .LINK
    https://github.com/salesforcecli/plugin-info

    .LINK
    https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md

    .LINK
    https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $false)][string] $Command,
        [Parameter(Mandatory = $false)][string] $Plugin,
        [Parameter(Mandatory = $false)][string] $OutputDirectory,
        [Parameter(Mandatory = $false)][switch] $CreateIssue
    )
    if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw "Output folder '$OutputDirectory' does not exist." }
    $arguments = @('doctor')
    if ($Command) { $arguments += @('--command', $Command) }
    if ($Plugin) { $arguments += @('--plugin', $Plugin) }
    if ($OutputDirectory) { $arguments += @('--output-dir', (Resolve-Path -LiteralPath $OutputDirectory).ProviderPath) }
    if ($CreateIssue) { $arguments += '--create-issue' }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $commonParams.Remove('WhatIf'); $commonParams.Remove('Confirm')
    if ($CreateIssue) {
        # Sharing diagnostics outside this computer asks by default. An explicit -Confirm:$false skips the question.
        if (-not $PSBoundParameters.ContainsKey('Confirm')) { $ConfirmPreference = 'Medium' }
        if (-not $PSCmdlet.ShouldProcess('the Salesforce CLI GitHub repository', 'Create an issue with your diagnostic results attached')) { return }
    } else {
        if (-not $PSBoundParameters.ContainsKey('Confirm')) { $ConfirmPreference = 'None' }
        if (-not $PSCmdlet.ShouldProcess('this computer', 'Run the Salesforce CLI diagnostics and write their files')) { return }
    }
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result
}

#endregion
