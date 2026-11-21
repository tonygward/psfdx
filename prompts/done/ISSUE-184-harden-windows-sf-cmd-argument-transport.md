# PSF: Harden Windows sf.cmd argument transport and parser edge cases

**Tracking issue:** https://github.com/tonygward/psfdx/issues/184

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #234. Release: 0.8.39.

## Objective

Test and harden the command-line parser and the Windows .cmd argument handling in Invoke-Salesforce.

## What was delivered

- Probed a real sf.cmd shim in PowerShell 7 and Windows PowerShell 5.1 with metacharacters, percent signs, trailing backslashes, Unicode and unusual whitespace: no injection found.
- A command line over the cmd.exe limit (about 7800 characters after percent expansion) now stops with advice instead of returning cmd.exe error text as a result.
- The shared `PSFDX_PERCENT` variable is now named per call and removed with `[NullString]::Value`; the old restore left an empty variable set for the life of the process.
- Table-driven tests on both Windows shells, six parallel runspaces, a Unix fake-executable table and parser edge cases.

## Tests

Argument transport table (issue 184) in psfdx-shared.Tests.ps1.

## Changelog

Covered by the security entry for all modules in 0.8.39.
