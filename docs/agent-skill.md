# Install the PSFDX Agent Skill

The [PSFDX skill](../skills/psfdx/SKILL.md) helps agents discover PowerShell commands and safely work with authorized Salesforce orgs. Install PowerShell, the Salesforce CLI and [PSFDX](install.md) on the machine where the agent runs.

From a clone of this repository, run the following in PowerShell. Replace `<project>` with the Salesforce project's path.

```powershell
$skill = '<project>/.claude/skills/psfdx'
$references = Join-Path $skill 'references'
New-Item -ItemType Directory -Path $references -Force | Out-Null
Copy-Item -LiteralPath ./skills/psfdx/SKILL.md -Destination $skill
Copy-Item -Path ./docs/reference/*.md -Destination $references
```

For a personal Claude Code installation, use `Join-Path $HOME '.claude/skills/psfdx'` for `$skill`. For another compatible agent, use its configured skills directory and keep the `psfdx/SKILL.md` and `psfdx/references/` layout. In Claude Code, try `/psfdx` or ask for a read-only Salesforce task using PSFDX.

The references are generated from command help by the same CI step that generates the website. Website CI publishes a `psfdx-agent-skill` artifact with the same folder layout. Refresh the skill and references from the same checkout when upgrading.

See [Claude Code skills](https://code.claude.com/docs/en/skills) and the [Agent Skills specification](https://agentskills.io/specification) for loader details.

## Validation and v1.0

The [fixture tests](../skills/psfdx/AgentSkill.Tests.ps1) run the two read-only examples from the skill and compare them with PowerShell scripts that call raw `sf`, parse its JSON, and check its status explicitly.

| Workflow | PSFDX lines | Raw `sf` script lines | Result |
| --- | ---: | ---: | --- |
| Bounded account query | 1 | 3 | Same projected fields |
| Group accounts by industry | 4 | 6 | Same sorted counts |
| CLI failure | | | Both surface the supplied error |

Both approaches emit the same compact JSON for equivalent projected results. For the grouping fixture, the compact summary is smaller than the original CLI JSON envelope. This measures the returned text for that fixture and does not measure network traffic, latency, or live-org reliability.

The skill targets v1.0 after a compatible agent loads the installed skill and completes the read-only workflows against an authorized sandbox. The automated checks use synthetic data.
