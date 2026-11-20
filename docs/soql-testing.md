# SOQL and `sf data query` test coverage

Every cmdlet that builds SOQL, or runs a caller-authored query, has a Pester test. The tests mock `Invoke-Salesforce`, so they need no org and no Salesforce CLI.

## Inventory

| Module | Cmdlet | How the query is made |
| :--- | :--- | :--- |
| psfdx | `Get-SalesforceUsers`, `Get-SalesforceRecordType` | Generated. Values go through `ConvertTo-SalesforceSoqlLiteral` |
| psfdx | `Select-SalesforceRecords` | Caller-authored `-Query` / `-File`, passed through unchanged |
| psfdx-development | `Get-SalesforceApexClass`, `Get-SalesforceCodeCoverage` | Generated (tooling API) |
| psfdx-logs | `Get-SalesforceFlowInterviews`, `Get-SalesforceLoginHistory`, `New-SalesforceEventFileQuery` (used by `Select-` and `Export-SalesforceEventFiles`), `Enable-SalesforceDebugLogging` (name lookup) | Generated. Dates go through `ConvertTo-SalesforceSoqlDateTime` |
| psfdx-metadata | `Build-SalesforceQuery` | Generated. Object and field names go through `ConvertTo-SalesforceSoqlIdentifier` |
| psfdx-sandbox | `Get-SalesforceSandboxRefreshStatus` | Generated (two tooling API queries) |

A new cmdlet that builds SOQL adds a row here and the same kinds of test.

## What the tests check

- The exact argv sent to `sf` (`$Arguments -join '|'`). Nothing is quoted, so the same argv is correct on Windows and Unix.
- Escaping tables: apostrophes, backslashes, a trailing backslash, quote-injection text, Unicode, `%` and `_`, spaces and shell characters.
- Control characters are refused before `sf` runs (`Invoke-Salesforce` is called zero times).
- Date boundaries are sent as UTC instants.
- Results: records without `attributes`, zero records, a malformed-query failure and an authentication failure. A failure must throw the CLI's own message.
- Paths with spaces and `%` reach `--file` and `--output-file` as one argument.

The JSON fixtures in the tests are sanitised copies of real `sf data query --json` output shapes. They hold no tokens and no real org data. Keep it that way.

## Optional check against a real org

Not run in CI. These commands only read, so they are safe against a sandbox or scratch org:

```powershell
sf data query --query "SELECT Id, Username FROM User LIMIT 1" --json
sf data query --query "SELECT Id FROM User WHERE Username = 'nobody@example.invalid'" --json   # zero records
sf data query --query "SELECT Id, Nope FROM User" --json                                       # failure shape
sf data query --query "SELECT Id FROM User" --target-org not-a-real-org --json                 # auth failure shape
```

Compare each output with the fixtures in the tests. If the CLI changes shape, update the fixture and the code together.
