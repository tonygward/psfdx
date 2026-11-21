---
id: PSF-45
priority: medium
effort: high
dependencies: []
conflicts: []
---

# PSF-45: Add Salesforce user administration and permission assignment workflows

**Tracking issue:** https://github.com/tonygward/psfdx/issues/208

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #216, released as 0.8.30.

## Objective

Allow scripted user lifecycle and permission assignment from PowerShell.

## What was delivered

- Audit of the latest plugin-user and plugin-org: `org list users`, `org display user`, `org create user`, `org generate password`, `org assign permset` and `org assign permsetlicense` are supported; the `force:user:*` forms are legacy and not used.
- `Get-SalesforceAuthenticatedUser`, `Get-SalesforceOrgUser`, `New-SalesforceUser`, `New-SalesforceUserPassword`, `Grant-SalesforcePermissionSet` and `Grant-SalesforcePermissionSetLicense`.
- Secrets: access tokens are never returned; a password is returned only as a SecureString from `New-SalesforceUserPassword`. `Get-SalesforceOrgUser` reports `HasPassword` only, because the current CLI redacts the real password in `org display user`.
- Confirmation: user creation is ConfirmImpact Medium; password generation and permission or licence assignment are High, so unattended scripts need `-Confirm:$false`. `-WhatIf` makes no CLI call.
- Idempotency: assigning a set the user already has is `AlreadyAssigned`; real failures are returned as `Failed` and then thrown as `PsfdxPermissionAssignmentFailed`. The CLI's exit status 68 for partial failure is handled.
- Limits: the CLI lists only users it has authorised on this computer; password length is 20 to 1000 and complexity 3 to 5. The required org permissions are in the help.
- Overlap with #192 (scratch org resume and permission sets, not yet built): `Grant-SalesforcePermissionSet` covers the `sf org assign permset` half, so #192 can reuse it.
- Not run against a real org.

## Tests

Exact argv for every command, no token or password in output, JSON, verbose or error text, WhatIf, confirmation level, idempotent re-assignment, partial failure, CLI errors and input validation.

## Release

Version 0.8.30. Changelog: psfdx: user administration commands.
