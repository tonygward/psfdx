---
id: PSF-33
priority: medium
effort: medium
dependencies: []
conflicts: []
---

# PSF-33: Preview Salesforce metadata deploys and retrieves

**Tracking issue:** https://github.com/tonygward/psfdx/issues/187

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #226. Release: 0.8.34.

## Objective

Let developers inspect planned metadata changes and source-tracking conflicts before a deploy or retrieve.

## What was delivered

- `Get-SalesforceDeployPreview` and `Get-SalesforceRetrievePreview` in psfdx-metadata, read-only wrappers for `sf project deploy preview` and `sf project retrieve preview`.
- Return ToDeploy, ToRetrieve, ToDelete, Conflicts and Ignored as lists, with HasChanges, HasConflicts and Summary; no changes gives empty lists and the summary No changes.
- `-Manifest` is a single file because the CLI accepts only one; `-SourceDir` and `-Metadata` can repeat. Orgs without source tracking return the CLI error plus guidance.
- Not run against a real org.

## Tests

Exact argv for both commands, selectors, missing paths, empty and conflicting results, CLI errors, exports and help examples.

## Changelog

psfdx-metadata: the two preview commands.
