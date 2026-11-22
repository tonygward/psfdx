# Security findings register

The result of the security audit in [#112](https://github.com/tonygward/psfdx/issues/112) and the argument-transport review in [#184](https://github.com/tonygward/psfdx/issues/184), done on 2026-11-21 against `main` at release 0.8.38. It lists what was found, how it was reproduced and what was done about it. Add a row when you find something new, and mark a finding Fixed only with a test that fails without the fix.

Scope: the seven product modules and `psfdx-shared`. Reproducers marked "read from the code" were not run before the fix; the regression test now shows each is refused. Not covered: the release and Matrix infrastructure (workflows, `scripts/`, `tools/`), which is reviewed separately. Nothing here was run against a real org; the checks are mocks, a real Windows `.cmd` shim that records its arguments, and a fake executable on Unix.

## Findings

| ID | Severity | Where | Status |
| :--- | :--- | :--- | :--- |
| SEC-01 | High | `Connect-SalesforceApi -CustomUrl` (psfdx) | Fixed |
| SEC-02 | Medium | `Invoke-SalesforceApi -Url` (psfdx) | Fixed |
| SEC-03 | Medium | `Export-SalesforceEventFile`, `Get-SalesforceEventFile` (psfdx-logs) | Fixed |
| SEC-04 | Medium | 21 validation patterns in every module and `psfdx-shared/Soql.ps1` | Fixed |
| SEC-05 | Medium | `Promote-SalesforcePackageVersion` (psfdx-packages) | Fixed |
| SEC-06 | Low | `Deploy-SalesforceMetadata`, `Deploy-SalesforceComponent`, `Install-SalesforcePackageVersion` | Fixed |
| SEC-07 | Low | `Install-/Update-SalesforceCli`, `Install-SalesforcePlugin`, `Update-SalesforcePlugins` (psfdx) | Fixed |
| SEC-08 | Low | `New-SalesforceRecord`, `Set-SalesforceRecord` (psfdx) | Fixed |
| SEC-09 | Low | `Invoke-Salesforce` through a Windows `.cmd` shim (psfdx-shared) | Fixed |
| SEC-10 | Low | `Invoke-Salesforce`, the `PSFDX_PERCENT` environment variable (psfdx-shared) | Fixed |
| SEC-11 | Medium | `Connect-SalesforceApi` secrets as plain `[string]` (psfdx) | Fixed: [#233](https://github.com/tonygward/psfdx/issues/233) |
| SEC-12 | Info | `Out-Notepad` (psfdx-logs) | Accepted |

### SEC-01 (High): credentials sent over plain http

`Connect-SalesforceApi -CustomUrl` built the token URL from whatever it was given, so `-CustomUrl http://login.example.com` posted the user name, password plus security token, client ID and client secret in clear text.
Reproducer: `Connect-SalesforceApi -TargetOrg u@x.com -Password p -Token t -ClientId c -ClientSecret s -CustomUrl http://login.example.com` (read from the code, not run before the fix: the request went to `http://login.example.com/services/oauth2/token`).
Fix: `Assert-SalesforceHttpsUrl` refuses anything that is not an absolute `https://` URL, and a trailing slash no longer doubles. Tests: `Security regressions (issue 112)` in `psfdx.Tests.ps1`.

### SEC-02 (Medium): access token sent to any URL

`Invoke-SalesforceApi -Url` sent `Authorization: Bearer <token>` to any URL, including `http://` and any host.
Fix: the same https check. The host is not restricted, because instance and My Domain URLs vary; the caller chooses where the token goes, and the help says so.

### SEC-03 (Medium): path traversal and REST path injection in event file export

`Export-SalesforceEventFile -Id` wrote `"$Id.csv"` into the output folder and `Get-SalesforceEventFile` put `$Id` into the REST path `/sobjects/EventLogFile/$Id/Logfile`. An ID such as `..\..\x` escaped the folder, wrote a file from org data wherever the caller could write, and changed the request path.
Reproducer: `Export-SalesforceEventFile -Id '..\..\evil' -OutputFolder .\out` (read from the code, not run before the fix: it wrote `evil.csv` two folders up).
Fix: both validate a 15 or 18 character ID first. Tests: `Security regressions: event file IDs`, which also checks that nothing is written.

### SEC-04 (Medium): `$` accepts a trailing line break

Every anchored check of an ID or name ended in `$`, which in .NET also matches before a final line feed. `'0AT000000000001' + "`n"` passed as an ID, and `ConvertTo-SalesforceSoqlIdentifier "Account`n"` passed as an API name, so the "refuses anything that could change the query" guarantee had a hole, and a value with a line break could reach a file name or a command argument.
Reproducer: `Export-SalesforceEventFile -Id ("0AT000000000001" + "`n")` got as far as trying to write a file (observed, when the new test was written).
Fix: the 21 patterns end in `\z`. Tests: `Identifier checks reject a trailing line break`, `ID parameters reject a trailing line break`, and the event file test above. Rule added to `.claude/rules/cmdlets.md`.

### SEC-05 (Medium): package promotion cannot be undone and had no confirmation

`Promote-SalesforcePackageVersion` released a version, after which it can no longer be deleted, with no `-WhatIf` or confirmation.
Fix: `SupportsShouldProcess`, ConfirmImpact High. `-NoPrompt` (the caller already decided, as for the CLI) skips the confirmation so unattended scripts keep working; `-WhatIf` still makes no call. Tests: `Security regressions: package confirmation`.

### SEC-06 (Low): deployments and installs could not be previewed

`Deploy-SalesforceMetadata`, `Deploy-SalesforceComponent` and `Install-SalesforcePackageVersion` changed an org with no `-WhatIf`.
Fix: `SupportsShouldProcess`, ConfirmImpact Medium, so there is no new prompt by default. A validation-only deployment (`-DryRun`) changes nothing and still runs under `-WhatIf`.

### SEC-07 (Low): installs run third-party code with no preview, and a plugin name could be read as an option

`Install-SalesforceCli`, `Update-SalesforceCli`, `Install-SalesforcePlugin` and `Update-SalesforcePlugins` download and run code from the npm registry. `Install-SalesforcePlugin -Name '--force'` passed the value straight to `sf plugins install`.
Fix: ConfirmImpact Medium with `-WhatIf`, and `-Name` must be an npm package name or URL that does not start with a dash and has no spaces or control characters. The help says to install only plugins you trust.

### SEC-08 (Low): field values echoed to the verbose stream

`New-SalesforceRecord` and `Set-SalesforceRecord` called `Write-Verbose $FieldUpdates`, putting field values (which can be sensitive) in verbose output a second time, apart from the command line `-Verbose` already shows.
Fix: removed. Note that `-Verbose` still prints the full `sf` command, including `--values`; the values are not masked, only options that name a secret are (see Verified).

### SEC-09 (Low): over-long command lines fail silently through `.cmd`

`cmd.exe` refuses a command line over 8191 characters and says so only in its output ("The command line is too long."). `Invoke-Salesforce` without `--json` returned that text as if it were the result.
Reproducer: `Invoke-Salesforce -FilePath sf -Arguments @('--probe', ('x' * 9000))` through a `.cmd` shim.
Fix: a Windows `.cmd` shim call over 7800 characters (counted after `%` expansion) throws, telling the caller to shorten the query or pass `--file`.

### SEC-10 (Low): a process-wide environment variable shared by every call

On Windows `%` is passed through a variable named `PSFDX_PERCENT` that was set before the call and "restored" after it. Two calls running at the same time in one process (runspaces, jobs, `ForEach-Object -Parallel`) could unset it under each other, and the restore did not work: PowerShell turns `$null` into an empty string for `SetEnvironmentVariable`, so the variable stayed set (to empty) for the life of the process. The race was not reproduced in 150 parallel calls; it is a design flaw rather than a seen failure.
Fix: each call uses its own variable name and removes it with `[NullString]::Value`. Test: six parallel runspaces make 90 calls with `%` and no variable is left behind.

### SEC-11 (Medium, fixed): secrets as plain strings

`Connect-SalesforceApi` takes `-Password`, `-Token` and `-ClientSecret` as `[string]`. SEC-01 means they now go only over https, but they stay readable in history and memory. Moving to `SecureString` changes the public signature, so it is tracked in [#233](https://github.com/tonygward/psfdx/issues/233).

### SEC-12 (Info, accepted): `Out-Notepad` temp file

`Out-Notepad` writes its content (debug logs can hold sensitive data) to a temporary file that is not deleted, because Notepad has it open. The file is in the user's own temp folder and the cmdlet is a convenience for reading a log. Left as it is; delete the file after use if the content is sensitive.

## Verified, no change needed

- No `Invoke-Expression` anywhere; every program runs through `Invoke-Salesforce` with an argument array, so `;`, `|`, `&`, `$(...)` and backticks in a value are plain text.
- Argument transport through a real `sf.cmd` shim in PowerShell 7 and Windows PowerShell 5.1: metacharacters inside spaced text, trailing backslashes (including after a space), `%` (leading, trailing, literal `%NAME%`), `!`, parentheses, apostrophes, backticks, Unicode, tabs, form feed, vertical tab, no-break space and other Unicode spaces next to `&` all arrive unchanged. Double quotes, line breaks and bare `& | < > ^` are refused with a clear message. The table is in `psfdx-shared.Tests.ps1` (`Argument transport table`).
- Generated SOQL: every value goes through `ConvertTo-SalesforceSoqlLiteral`, `ConvertTo-SalesforceSoqlIdentifier` or `ConvertTo-SalesforceSoqlDateTime`; the remaining interpolations are `[int]` limits. `Get-SalesforceRecord`'s `-Where` refuses quotes and control characters.
- Secrets in output: `Show-SalesforceResult` and `Invoke-Salesforce` redact access and refresh tokens, auth URLs, passwords, client secrets and private keys from JSON, error text and previews, and `-Verbose` masks the value of options named like `--password`, `--client-secret`, `--sfdx-url` and `--jwt-key`. `Get-SalesforceOrgUser` reports `HasPassword` only.
- Authentication: `Connect-SalesforceJwt` and `Connect-SalesforceAuthUrl` take file paths, check that the file exists and never read or print its content.
- Temporary files: the single-record upsert body and the Code Analyzer report use a unique GUID name in the temp folder and are deleted in a `finally` block.
- Destructive cmdlets that already confirmed: `Remove-` (records, package versions, scratch orgs, sandboxes), `Stop-SalesforceDeploy`, `Start-SalesforceQuickDeploy`, `Disconnect-Salesforce`, `Enable-` and `Disable-SalesforceAgent`, `Publish-SalesforceAgentAuthoringBundle`.

## Reviewed and left alone

`New-SalesforceSandbox`, `Copy-SalesforceSandbox`, `New-SalesforceScratchOrg`, `New-SalesforcePackage` and `New-SalesforcePackageVersion` create things that cost licences or time but can be deleted, so they do not ask. Configuration setters (`Set-SalesforceTargetOrg` and similar) only change local CLI configuration.
