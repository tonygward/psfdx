# CLAUDE.md

psfdx is a set of cross-platform PowerShell modules that wrap the Salesforce CLI (`sf`). Each cmdlet builds an `sf ... --json` command string, runs it, and converts the JSON result into PowerShell objects.

## Layout

| Path | Purpose |
| :--- | :--- |
| `psfdx/` | Core: auth, aliases, SOQL/records, limits, REST API, CLI/plugin install |
| `psfdx-metadata/` | Retrieve / deploy / describe metadata |
| `psfdx-development/` | Projects, config, scratch orgs, Apex tests, `Watch-SalesforceApex`, LWC/Jest |
| `psfdx-logs/` | Debug logs, flow interviews, login history, event log files |
| `psfdx-sandbox/` | Sandbox lifecycle |
| `psfdx-packages/` | Packages and package versions |
| `psfdx-shared/` | Internal helpers (`Invoke-Salesforce`, `Show-SalesforceResult`, Apex test-param helpers, `Get-PsfdxCommonParameterSplat`) |
| `modules.ps1` | Canonical module list used by the install/uninstall scripts |

**Everything above, plus `install*.ps1`, `uninstall*.ps1` and `VERSION`, is the product** (what users install). **Everything below is infrastructure** (how the product is built, tested and released). Keep the two apart:

| Path | Purpose |
| :--- | :--- |
| `.github/workflows/` | CI, gate, release and housekeeping pipelines ([docs/pipelines.md](docs/pipelines.md)) |
| `scripts/release/` | Version bump, release zip, Gallery bundle, and the shared "does this change ship / need tests" rule (`changes.mjs`) |
| `scripts/matrix/` | The merge gate and prompt archiving |
| `scripts/parity/` | The Salesforce CLI to psfdx parity report generator ([docs/cli-parity.md](docs/cli-parity.md)) |
| `site/` | The public website (psfdx.com): static HTML and CSS, built by `site/build.mjs`, deployed by Cloudflare Pages ([site/README.md](site/README.md)). Not part of the product; it never releases |
| `tools/matrix/` | Matrix, the Node orchestrator that runs board work |
| `tools/matrix-linux/` | The container, proxy and launcher Matrix runs in |
| `tests/` | Repository-wide rules only (`Repository.Tests.ps1`). Other infrastructure tests sit beside the code they test |
| `docs/`, `prompts/` | Policy, pipelines, release rules; backlog prompts. `docs/CODE-REVIEW.md` is an old review; `docs/security-findings.md` is the security findings register |

Rules that keep them apart:
- Only a change to the product releases. Workflows, scripts, tools, tests and docs never bump the version. The rule is `scripts/release/changes.mjs`; don't copy it into a workflow.
- Infrastructure tests live next to their code (`scripts/release/*.Tests.ps1`, `tools/matrix-linux/*.Tests.ps1`, `*.test.mjs`), not in the root `tests/`.
- Matrix task pull requests may change only `psfdx*/`, `prompts/`, `images/`, `README.md`, `CHANGELOG.md` and `modules.ps1`. Infrastructure and `docs/` need a person.
- Infrastructure changes get no `CHANGELOG.md` entry; the changelog is for users.

Each module has `<name>.psd1` (manifest), `<name>.psm1` (code) and `<name>.Tests.ps1` (Pester).

## Commands

```powershell
Invoke-Pester -Path . -CI                                   # full suite (what CI runs)
Invoke-Pester -Path ./psfdx-logs/psfdx-logs.Tests.ps1       # one module
./install.ps1  # or ./install-windows.ps1 — copies modules into the user module path
```

The tests mock all `sf` calls, so they need no org and no Salesforce CLI. Warnings about unapproved verbs while the tests run are expected.

## Cmdlet pattern

Follow the existing idiom exactly. Don't introduce a new style in a single function:

```powershell
function Verb-SalesforceNoun {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][switch] $NoPrompt,
        [Parameter(Mandatory = $false)][string] $TargetOrg
    )
    $arguments = @('some', 'command', '--name', $Name)
    if ($NoPrompt) { $arguments += '--no-prompt' }
    if ($TargetOrg) { $arguments += @('--target-org', $TargetOrg) }
    $arguments += '--json'
    $commonParams = Get-PsfdxCommonParameterSplat -BoundParameters $PSBoundParameters
    $result = Invoke-Salesforce -FilePath 'sf' -Arguments $arguments @commonParams
    return Show-SalesforceResult -Result $result        # add -ReturnRecords for SOQL queries
}
```

- **Every cmdlet passes an argument array to `Invoke-Salesforce -FilePath ... -Arguments ...`, never a command string.** Each element is one argv entry exactly as given, so spaces, quotes, apostrophes, backslashes and `%` in a value need no quoting. Tests assert `($Arguments -join '|')`. The older `-Command` string form still works for backwards compatibility but no product code uses it; don't add new callers.
- Always forward common parameters with `Get-PsfdxCommonParameterSplat`, so `-Verbose` shows the `sf` command.
- `Show-SalesforceResult` throws on a non-zero `status`. Don't pipe non-JSON output (`csv`/`human` result formats) into it.
- `Invoke-Salesforce` deliberately has **no** `SupportsShouldProcess` (see the comment in `psfdx-shared/Invoke-Salesforce.ps1`). Put `ShouldProcess` on the public cmdlet instead.
- **`Invoke-Salesforce` runs the executable directly with your argument array** (`-Arguments`; the legacy `-Command` string is split by `ConvertTo-PsfdxArgumentList`). It never goes through `Invoke-Expression` or a shell, so `;`, `|`, `&` and `$(...)` in a value are plain text, and no value needs quoting or escaping. Put every value that goes into generated SOQL through `ConvertTo-SalesforceSoqlLiteral` (it returns the quoted literal; SOQL escapes with a backslash, so doubling the quote is wrong) and every object or field name through `ConvertTo-SalesforceSoqlIdentifier`. Never add an `Invoke-Expression` call. On Windows, an argument containing a double quote or a line break is rejected for the `.cmd` shims (`sf`, `npm`, `yarn`); `%` is passed literally.
- The `Retrieve-`, `Describe-` and `Promote-` verbs are intentional, even though PowerShell doesn't approve them. Keep using them for consistency.
- Each `.psm1` starts with an identical copy of `Import-PsfdxSharedModule` (seven modules). If you change it, change every copy; `tests/Repository.Tests.ps1` fails if they differ. The resolution rules and the version contract are in the comment at the top of the function.
- Use `#region` / `#endregion` blocks to group cmdlets, as the existing files do.

## Compatibility

Manifests declare `PowerShellVersion = '5.1'` and `CompatiblePSEditions = @('Desktop','Core')`, so code must run on Windows PowerShell 5.1:
- Don't use ternary `?:`, `??`, `?.` or `&&`/`||` in module code.
- Use `Join-Path` with two arguments only (nest it for deeper paths).
- `$IsWindows`/`$IsMacOS` are `$null` on 5.1. Use the existing `Test-SalesforceIsWindows` (`psfdx-logs`) and `Test-SalesforceIsMacOS` (`psfdx`) helpers instead.
- Parse dates and numbers with the invariant culture.

## Tests

- Load the module from its manifest after removing any copies already loaded (see the top of each `.Tests.ps1`), then test inside `InModuleScope`.
- Mock `Invoke-Salesforce` (and `Show-SalesforceResult` where needed). Assert the exact `-Command` string with `Assert-MockCalled ... -ParameterFilter { $Command -eq '...' }` or `-like`. That string is the contract, and checking it is what catches bugs like malformed SOQL.
- Never call a real org. Write any files to `$TestDrive`, not the repo.
- Every bug fix or new cmdlet needs a test.

## Checklist for adding or changing a public cmdlet

1. Implement it in the module `.psm1`.
2. Add it to `FunctionsToExport` in the module `.psd1`. Exports come from the manifest; there is no `Export-ModuleMember`.
3. Add a Pester test.
4. Add or update its row in the module's table in `README.md`.
5. Add an entry under `## Unreleased` in `CHANGELOG.md`, prefixed with the module name (`- psfdx-logs: ...`). Mark renames and moves as `Breaking:`.
6. A new module also needs adding to `modules.ps1`.
7. Write its help (see `.claude/rules/cmdlets.md`): `tests/Help.Tests.ps1` fails for a missing synopsis, description, parameter, example, or "Salesforce CLI mapping" note, or a mapping that does not name the `sf` command the parity report says it runs.
8. If it runs a new `sf` command, or passes a flag no cmdlet passed before, regenerate the parity report with `./scripts/parity/New-CliParityReport.ps1` and commit `docs/cli-parity.md` and `docs/cli-parity.json`. A test fails if you forget.

## How work runs

Work is chosen from a GitHub Project board: Todo and Doing cards run, Backlog and Blocked wait. Matrix, the orchestrator, builds and tests each change in a container, opens a pull request, merges it once CI passes, then releases a patch version and finishes the issue. The full rules are in [docs/execution-policy.md](docs/execution-policy.md).

## Backlog

Every task is a GitHub issue titled with a stable ID (`PSF-##` for modules, `AUTO-##` for automation). Prompts live in `prompts/` and move to `prompts/done/` when merged. See [docs/backlog-issue-prompt-contract.md](docs/backlog-issue-prompt-contract.md).

## Release notes

Any change users will notice adds plain-language bullets under `## Unreleased` in `CHANGELOG.md`, prefixed with the module name. No commit hashes, pull request titles or prompt IDs. See [docs/release.md](docs/release.md).

## Commits and pull requests

Start every commit and PR title with its area so the history separates product from infrastructure: a module name (`psfdx-logs: ...`) for product changes, `infra: ...` for workflows, scripts and tools (`infra(matrix): ...` for Matrix), `docs: ...` for documentation. The title must describe what the change does. Automated `[release]` and `[archive]` commits keep their own prefixes.

## Git

- **Merging is the AI's job (standing rule from the owner, 2026-11-18).** Every pull request is merged by the AI, not by the owner, and the AI does not ask first. Open the PR, wait for every check to pass on the exact head commit, address review findings, then squash-merge it (`gh pr merge <n> --squash --delete-branch`), whatever it changes: product, infrastructure, workflows, docs or policy. Where the merge gate's lanes allow it (`docs/pipelines.md`), the gate merges it automatically. Otherwise the AI merges it after CI. Never merge with a failing, cancelled or still-running check, never bypass branch protection or use admin overrides, and never merge a PR the AI did not open or review. After a product merge, confirm the release and Gallery publish; Gallery versions are permanent, so a product change needs the same care it always did.
- PRs target `main`. `master` is stale (many commits behind); don't use it. CI (`.github/workflows/ci.yml`) runs Pester on `ubuntu-latest` for pull requests only.
- `docs/CODE-REVIEW.md` is a review from 2026-09-09. Many of its findings have since been fixed (see `CHANGELOG.md`), so check the current code before acting on it. The `Invoke-Expression` finding (#3) is fixed.
