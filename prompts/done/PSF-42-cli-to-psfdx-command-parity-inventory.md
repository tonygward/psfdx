---
id: PSF-42
priority: high
effort: large
dependencies: []
conflicts: []
---

# PSF-42: Build authoritative Salesforce CLI-to-psfdx command parity inventory

**Tracking issue:** https://github.com/tonygward/psfdx/issues/205

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #237. No release: infrastructure and documentation only.

## Objective

Generate a reproducible, command-by-command inventory comparing the latest stable Salesforce CLI with what psfdx actually runs, instead of cmdlet counts or README claims. The deliverable is a Markdown report in the repository, linked from the README.

## What was delivered

- `docs/cli-parity.md` (the report) and `docs/cli-parity.json` (machine-readable twin), linked from the README section "Salesforce CLI coverage".
- `scripts/parity/New-CliInventorySnapshot.ps1` writes `docs/cli-parity-inventory.json` from `sf commands --json` (the only step that needs the CLI); `New-CliParityReport.ps1` builds the report offline from that snapshot, the module manifests and sources, and the reviewed mapping `docs/cli-parity-mapping.json`.
- Statuses: wrapped, partially wrapped (with the flags no cmdlet passes), missing, deliberately excluded, not applicable. Totals per capability and per plugin set (core, just-in-time), always "of N in scope" for that set. Convenience cmdlets are not counted as coverage; one-to-many and many-to-one are shown.
- The scan follows any variable passed to `Invoke-Salesforce -Arguments`, one-element arrays, helper flags in the same file and in psfdx-shared, topic references, old command names (aliases) and reordered words. It reports deprecated aliases psfdx runs today.
- An invalid mapping fails the tests; a new unmapped command only shows as missing. A test fails when the committed report is stale, on Windows PowerShell 5.1 and 7. CLAUDE.md has a checklist step to regenerate it.
- First numbers (CLI 2.159.7): core 53 wrapped + 39 partial of 199 in scope; just-in-time 3 + 4 of 56. Which families to mark deliberately excluded is left to the owner.

- Follow-up the same day: the report also covers flag values. The inventory keeps each flag's type, whether it is required or repeatable, the values the CLI lists for it and its recorded default. The scan reads the value after each flag (a literal, a `[ValidateSet()]` parameter, a lookup table, `--name=value`, or free text) and the report lists the listed values psfdx cannot pass, with totals. A mapping rule can accept a value with `ignoreValues`.

## Tests

Fixture-based tests in `scripts/parity/CliParity.Tests.ps1` for inventory conversion, the source scan, classification, alias and word-order resolution, mapping validation, the Markdown output and the staleness check.

## Changelog

None: infrastructure and documentation changes have no changelog entry.
