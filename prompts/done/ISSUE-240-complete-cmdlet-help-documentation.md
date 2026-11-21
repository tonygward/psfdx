# PSF: Complete cmdlet Get-Help documentation with verified Salesforce CLI command mappings

**Tracking issue:** https://github.com/tonygward/psfdx/issues/240

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #242. Release: 0.8.40.

## Objective

Complete, accurate comment-based help for every exported psfdx command, including the exact sf command(s) each one runs, checked against the generated CLI parity report.

## What was delivered

- Help for all 157 exported commands (including the 12 psfdx-shared exports): synopsis, description, every parameter, written examples, notes and links.
- A "Salesforce CLI mapping" note on each: the exact sf commands it runs (from docs/cli-parity.json), the old name or reordered words it is run by, parameter to flag, flags and values it cannot pass, or a statement that it runs no sf command and how it works instead.
- tests/Help.Tests.ps1 enforces completeness and the cross-check against the parity report; scripts/release/Test-PsfdxHelp.ps1 checks Get-Help -Full, -Examples and -Parameter * on a package, in the repository tests (on the built bundle) and in the Gallery install check (on the published package, all three legs).
- docs/help-audit.md records the per-cmdlet cross-check and the decisions: psfdx-shared exports stay exported as documented internal helpers; deprecated aliases are flagged, not replaced (issue 241).
- Fixed: Open-Salesforce -BrowserPrivateMode was a string written as --private <value>; it is now a switch.

## Tests

Help.Tests.ps1 (787 checks), Test-PsfdxHelp.Tests.ps1 (built bundle on PowerShell 7 and 5.1, plus a negative case), and Open-Salesforce private mode tests.

## Changelog

All modules: complete help with CLI mapping notes. psfdx: Breaking, Open-Salesforce -BrowserPrivateMode is now a switch.
