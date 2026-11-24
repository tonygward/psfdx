function Get-PsfdxModules {
    @(
        'psfdx',
        'psfdx-logs',
        'psfdx-development',
        'psfdx-org',
        'psfdx-metadata',
        'psfdx-devops',
        'psfdx-data',
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
        'psfdx-sandbox',  # now psfdx-org
        'psfdx-bulk'      # now psfdx-data
    )
}

# Modules that hold only implementation helpers. They ship in the package and the other modules use them, but they export no commands,
# so they are not part of the public command surface, the website or the command reference.
function Get-PsfdxInternalModules {
    @(
        'psfdx-shared'
    )
}
