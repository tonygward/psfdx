# Scratch org integration tests

The Pester suite mocks every `sf` call, and the [CLI compatibility lane](cli-compatibility.md) only checks `sf <command> --help`. Neither proves psfdx works against a real org. The integration lane does: it creates a throwaway scratch org, runs a small set of psfdx operations against it, and deletes it.

It is **opt-in, expensive and advisory**. See [When it is required](#when-it-is-required).

## What it covers

`tests/integration/Psfdx.Integration.Tests.ps1`, against one scratch org:

| Area | What runs |
|---|---|
| Connection | `Get-SalesforceLimits`, `Get-SalesforceAuthenticatedUser` (no token in the result) |
| SOQL | `Select-SalesforceRecords` (one record, no `attributes`; malformed SOQL throws) |
| Records | `New-SalesforceRecord`, `Set-SalesforceRecord`, then a delete, on a temporary Account |
| Metadata | `Deploy-SalesforceMetadata` and `Retrieve-SalesforceMetadata` by manifest, using the probe classes in `tests/integration/fixtures` |
| Apex tests | `Test-SalesforceApex`, and `Start-`, `Wait-` and `Get-SalesforceApexTestResult`, on the probe test class |

Each result is a structured object, so the tests also check the response handling, not only that a command ran.

## One-off setup (the owner)

1. **A dedicated Dev Hub.** Use a Developer Edition or Dev Hub org that holds nothing else. Never use production or a shared sandbox.
2. **A least-privilege user** in that Dev Hub, with only what creating and deleting scratch orgs needs (the Dev Hub's "Create and Delete Scratch Orgs" capability; no admin rights on anything else). Use a different user for each repository.
3. **The auth URL.** Log that user in once with the CLI, then run `sf org display --target-org <devhub> --verbose --json` and copy `sfdxAuthUrl`. Treat it like a password.
4. **A GitHub environment** named `scratch-org-integration` (Settings, Environments). Add the secret `SF_DEVHUB_AUTH_URL` to **that environment**, not to the repository, and turn on **Required reviewers** so every run needs your approval. Restrict it to the `main` branch.
5. Optionally set the repository variable `PSFDX_INTEGRATION_SCHEDULE` to `true` to run weekly (Wednesday 05:41 UTC). Leave it unset to run only by hand.

## Running it

**Actions, Housekeeping - Scratch org integration smoke tests, Run workflow.** Approve the environment prompt. The run:

1. **Setup:** installs the latest stable `sf`, signs in to the Dev Hub from the secret, creates a one-day developer scratch org.
2. **Tests:** runs the integration tests against that org only.
3. **Teardown:** always deletes the scratch org, even if setup or the tests failed.
4. **Report:** writes `integration-report.json` and `.md` to the job summary and uploads them (with the Pester results) as the `integration-report` artifact, kept 90 days.

To run the tests by hand against your own scratch org: `PSFDX_INTEGRATION=1 PSFDX_INTEGRATION_ORG=<alias> pwsh -Command "Invoke-Pester ./tests/integration/Psfdx.Integration.Tests.ps1"`. Use a scratch org only.

## Reading a failure

The report's `verdict` and `failureKind` say which phase failed:

| Verdict | Meaning | Action |
|---|---|---|
| `setup-failed` | Login or scratch org creation failed; no test ran. **Not a psfdx regression.** | Check the secret, the Dev Hub's scratch org allocation, and Salesforce status |
| `tests-failed` | The org was ready and a test failed. Treat as a psfdx regression or a broken test | Read the failing test in the report; reproduce locally |
| `teardown-failed` | Tests passed but the scratch org was not deleted | Delete it by hand (`sf org delete scratch`); it also expires after one day |
| `passed` | All three phases succeeded | None |

## Controls

- **No secrets in logs or artifacts.** The auth URL is masked, written to a private temporary file that is deleted straight after login, and never put on a command line. The report holds only versions, outcomes, test names and durations, and a test checks it for credential-like text. The tests do not call `-Verbose` or print tokens.
- **Least privilege and protection.** A dedicated Dev Hub, a minimal user, the secret held in an environment that needs approval, workflow permissions `contents: read`.
- **Spend and allocation.** One-day scratch orgs, one run at a time (a concurrency group), a 45-minute limit, and the Dev Hub's own scratch org allocation as the hard cap. A scheduled run happens at most once a week and only if you enable it.
- **Deterministic cleanup.** Teardown runs `if: always()`; the tests also delete their temporary Account in `AfterAll`; and the org expires in a day regardless.
- **Never against anything but the scratch org.** The tests read `PSFDX_INTEGRATION_ORG` and pass it as `-TargetOrg` to every call.

## When it is required

- **Advisory.** It never runs on pull requests, so contributors need no org secrets, and the [merge gate](pipelines.md) never waits for it. The no-credential Pester suite and the latest-CLI compatibility lane remain the required checks.
- **Run it** before a release that changes how psfdx talks to the CLI (new or changed cmdlets that run `sf`), after a Salesforce CLI major version, and when the weekly CLI compatibility lane reports a change.
- **A failed `tests-failed` run** blocks the release it was run for until understood. A `setup-failed` run blocks nothing: fix the org and run it again.

## Limits

These tests were written and statically checked (they only call exported commands, the report logic and workflow rules have Pester tests) without access to a Dev Hub. Expect to tune the first real run: the metadata and Apex steps depend on the scratch org accepting the probe classes.
