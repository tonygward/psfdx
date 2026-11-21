---
id: PSF-27
priority: medium
effort: large
dependencies: []
conflicts: []
---

# PSF-27: Security hardening audit for psfdx CLI wrappers

**Tracking issue:** https://github.com/tonygward/psfdx/issues/112

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #234. Release: 0.8.39.

## Objective

Audit the wrappers for injection, secret exposure, destructive-operation confirmation and path and file handling, and fix what is found.

## What was delivered

- A findings register, docs/security-findings.md: 12 findings by severity with location, reproducer and status.
- Fixed: credentials sent over plain http by `Connect-SalesforceApi -CustomUrl` (High) and a token sent to any URL by `Invoke-SalesforceApi`; event file ID path traversal; 21 validation patterns that accepted a trailing line break; package promotion without confirmation; `-WhatIf` for deploys, package install and CLI or plugin install; plugin names read as options; field values echoed to the verbose stream.
- Split out: SecureString credentials for `Connect-SalesforceApi` (breaking), issue 233.
- Breaking: `-CustomUrl` and `-Url` must be https. Rules for `\z` anchors, https and ShouldProcess added to `.claude/rules/cmdlets.md`.
- Nothing was run against a real org.

## Tests

Security regression tests in psfdx, psfdx-logs, psfdx-packages, psfdx-metadata and psfdx-shared, including trailing line break checks and -WhatIf on every changed cmdlet.

## Changelog

psfdx, psfdx-logs, psfdx-packages, psfdx-metadata: the security fixes, with the https change marked Breaking.
