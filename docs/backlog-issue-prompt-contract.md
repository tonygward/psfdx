# psfdx backlog: issue and prompt contract

When a task is ready to run, and when a prompt has to exist, is set by the [execution policy](execution-policy.md#1-backlog-issues-and-prompts). This page only says what an issue and a prompt contain.

## The issue

- **Title** starts with the stable ID: `PSF-14: Get-SalesforceFieldUsage`. Search for the ID and for similar work first, and update what exists instead of duplicating it.
- **Body** has enough for Matrix to build a prompt when there is no prompt file. Use these headings, each with real text:
  - `## Objective` (and the user value)
  - `## Scope` or `## Implementation`
  - `## Acceptance criteria`
  - `## Tests` (a combined `## Acceptance criteria and tests` counts for both)
- If a prompt file exists, link it near the top of the issue.

## The prompt

- **Where:** `prompts/ID-slug.md`, one flat folder.
- **Metadata** (optional, restricted subset):

  ```yaml
  ---
  id: PSF-14
  priority: medium
  effort: low
  dependencies: ["PSF-12"]
  conflicts: []
  ---
  ```

  `priority` is `high`, `medium`, `low` or a non-negative number. `effort` is `low`, `medium` or `high`. `dependencies` and `conflicts` are inline JSON arrays. Leave out `model:`, and never add a status or execution line.
- **Body**, in this order: the issue link; objective and user value; current and desired behaviour; scope; implementation guidance; acceptance criteria; tests; dependencies and risks; release expectations (which modules, and whether users will notice, so a changelog entry is needed).
- **For a public cmdlet**, the acceptance criteria include the checklist in [`CLAUDE.md`](../CLAUDE.md) (manifest export, a Pester test asserting the exact `sf` command string, README row, changelog entry, and `modules.ps1` for a new module) and Windows PowerShell 5.1 compatibility.
- Don't repeat the execution policy in a prompt. Link to it if you like.

## Writing it down is not running it

Creating an issue or a prompt does not mean Matrix queued, started, merged or delivered it. Say what actually happened: requested, running, merged, released, delivered. Never invent evidence.
