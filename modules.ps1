function Get-PsfdxModules {
    @(
        'psfdx-core',
        'psfdx-logs',
        'psfdx-development',
        'psfdx-sandbox',
        'psfdx-metadata',
        'psfdx-packages',
        'psfdx-agentforce',
        'psfdx-shared'
    )
}

# The module the user installs: Install-Module psfdx. It holds no code. It only requires every module in Get-PsfdxModules, so one install
# brings the whole suite and each module keeps its own name (Get-Command -Module 'psfdx*' shows where every command really lives).
function Get-PsfdxUmbrellaModule {
    'psfdx'
}

# What each module needs installed before it can load, because its code calls that module's commands. The Gallery packages are generated from this
# (scripts/release/Build-GalleryPackage.ps1), so PowerShellGet installs the dependencies by itself. tests/Repository.Tests.ps1 checks it against the code:
# a module may call only the commands of the modules listed here, and the list must not loop.
function Get-PsfdxModuleDependencies {
    [ordered]@{
        'psfdx-shared'      = @()
        'psfdx-core'        = @('psfdx-shared')
        'psfdx-logs'        = @('psfdx-shared', 'psfdx-core')
        'psfdx-development' = @('psfdx-shared', 'psfdx-core')
        'psfdx-agentforce'  = @('psfdx-shared')
        'psfdx-sandbox'     = @('psfdx-shared')
        'psfdx-metadata'    = @('psfdx-shared')
        'psfdx-packages'    = @('psfdx-shared')
    }
}

# Modules an older psfdx installed under a name that now means something else. install.ps1 removes them so the old copy of the core module does not
# sit next to psfdx-core and define every command twice. (The core module used to be called psfdx; that name is now the umbrella.)
function Get-PsfdxLegacyModules {
    @('psfdx')
}
