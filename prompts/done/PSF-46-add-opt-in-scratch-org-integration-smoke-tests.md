---
id: PSF-46
priority: medium
effort: high
dependencies: []
conflicts: []
---

# PSF-46: Add opt-in scratch-org integration smoke tests for core psfdx workflows

**Tracking issue:** https://github.com/tonygward/psfdx/issues/209

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #221. Release: none (infrastructure; no product change).

## Objective

Prove representative psfdx operations work against a real org, not only mocks or `sf ... --help`.

## What was delivered

- Workflow `Housekeeping - Scratch org integration smoke tests`: manual, or weekly if the repository variable `PSFDX_INTEGRATION_SCHEDULE` is `true`; never on pull requests; protected environment `scratch-org-integration`; `contents: read`; one run at a time; 45-minute limit; latest stable `sf`.
- Separate setup, tests and teardown steps. Setup signs in to a dedicated Dev Hub with a masked secret kept off command lines and creates a one-day scratch org; teardown always deletes it.
- `tests/integration/Psfdx.Integration.Tests.ps1` runs connection, SOQL, a temporary record lifecycle, metadata deploy and retrieve, and Apex tests (one call and the start/wait/result lifecycle). All are skipped unless `PSFDX_INTEGRATION=1` and `PSFDX_INTEGRATION_ORG` are set.
- The report (`integration-report.json` and `.md`, kept 90 days) records the exact CLI, PowerShell and psfdx versions and each test outcome, and its verdict separates `setup-failed` from `tests-failed` (a psfdx regression).
- `docs/integration-testing.md` covers the owner's one-off setup, running, reading a failure, the controls, and when the lane is required (advisory only) versus not.
- NOT VERIFIED: there was no Dev Hub, so the workflow has never run and the integration tests have never executed against a real org. The report logic, the workflow rules and the test structure are covered by offline Pester tests. The owner must create the Dev Hub user, the environment and the `SF_DEVHUB_AUTH_URL` secret first, and should expect to tune the first run.

## Tests

Offline: report verdicts for each failure phase, per-test parsing, no credential text, opt-in skipping, exported-command check, fixture consistency, and workflow safety rules.

## Changelog

None: infrastructure changes have no changelog entry.
