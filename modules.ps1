function Get-PsfdxModules {
    @(
        'psfdx',
        'psfdx-logs',
        'psfdx-development',
        'psfdx-org',
        'psfdx-metadata',
        'psfdx-devops',
        'psfdx-bulk',
        'psfdx-plugins',
        'psfdx-packages',
        'psfdx-agentforce',
        'psfdx-shared'
    )
}

# Modules that no longer exist. The install scripts remove their old folders, so a leftover copy cannot export the same commands as the module
# that replaced it, and the uninstall scripts remove them too.
function Get-PsfdxRetiredModules {
    @(
        'psfdx-sandbox'   # now psfdx-org
    )
}
