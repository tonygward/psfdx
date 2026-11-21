---
id: PSF-36
priority: medium
effort: medium
dependencies: []
conflicts: []
---

# PSF-36: Add Agentforce authoring bundle commands

**Tracking issue:** https://github.com/tonygward/psfdx/issues/190

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #229. Release: 0.8.37.

## Objective

Extend the Agentforce module so teams can script authoring and release of Agent Script agents.

## What was delivered

- `New-SalesforceAgentAuthoringBundle`, `Test-SalesforceAgentAuthoringBundle` and `Publish-SalesforceAgentAuthoringBundle` in psfdx-agentforce.
- Generate requires `-Name` and either `-Spec` or `-NoSpec` (checked before the CLI runs) and uses ShouldProcess; publish is ConfirmImpact High; validate returns Valid and Diagnostics objects, with `-ThrowOnInvalid` for CI.
- The existing plugin guard gives install guidance. The upstream commands are newer and may be beta, so a recent plugin-agent is needed.
- Not run against a real org; the validation error shape is inferred.

## Tests

Exact argv with paths containing spaces, WhatIf, diagnostics, ThrowOnInvalid, non-validation failures, missing plugin and exports.

## Changelog

psfdx-agentforce: the three authoring bundle commands.
