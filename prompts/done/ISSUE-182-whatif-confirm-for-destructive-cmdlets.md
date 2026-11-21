# PSF: Add WhatIf/Confirm safety to destructive Salesforce cmdlets

**Tracking issue:** https://github.com/tonygward/psfdx/issues/182

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #202, released as 0.8.24.

## Objective

Make the cmdlets that delete or log out of orgs and packages ask first and support `-WhatIf`.

## What was delivered

- `Disconnect-Salesforce`, `Remove-SalesforceScratchOrg`, `Remove-SalesforceScratchOrgs`, `Remove-SalesforceSandbox`, `Remove-SalesforcePackage` and `Remove-SalesforcePackageVersion` use `SupportsShouldProcess` with `ConfirmImpact = High`, and call `sf` only inside `ShouldProcess`.
- `Remove-SalesforceScratchOrgs` asks once, naming every scratch org.
- Breaking for scripts: unattended use needs `-Confirm:$false`. `-NoPrompt` still only controls the CLI prompt.
- Left unchanged on purpose: `Remove-SalesforceAlias` and the `config unset` cmdlets, which only change local settings.

## Tests

WhatIf makes no `sf` call; existing tests pass `-Confirm:$false`.

## Release

Version 0.8.24. Changelog: The six cmdlets now ask for confirmation and support `-WhatIf`.
