# PSF: Make shared module import/version resolution deterministic

**Tracking issue:** https://github.com/tonygward/psfdx/issues/185

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #204, released as 0.8.26.

## Objective

Load `psfdx-shared` predictably: compare versions as versions, reject incompatible copies, and fail with a useful message.

## What was delivered

- All seven identical copies of `Import-PsfdxSharedModule` follow a contract: shared must have the importing module's Major.Minor and be no older than it.
- Order: a compatible loaded copy, the sibling folder, sibling version folders, then PSModulePath; highest `[version]` within the first tier that fits. A stale loaded copy is replaced; if nothing fits the function throws with what it found.
- A repository test fails if the copies differ.
- Not tested: a real side-by-side `Install-Module` layout with separate module versions.

## Tests

14 resolver tests against fake modules in `$TestDrive`.

## Release

Version 0.8.26. Changelog: All modules: loading the shared helpers is now predictable.
