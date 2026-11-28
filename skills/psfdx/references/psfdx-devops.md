# psfdx-devops command reference

Generated from the commands' own help by `site/Update-ModuleReference.ps1`: do not edit it by hand. The same reference is on the website: <https://psfdx.com/modules/psfdx-devops/>. It is part of the `psfdx` package; see the [installation guide](https://github.com/tonygward/psfdx/blob/main/docs/install.md).

31 commands. Every command also takes the common parameters, such as `-Verbose`.

## Commands

**Pipelines and stages**: [Add-SalesforceDevOpsPipelineProject](#add-salesforcedevopspipelineproject), [Add-SalesforceDevOpsPipelineStage](#add-salesforcedevopspipelinestage), [Add-SalesforceDevOpsStageBranch](#add-salesforcedevopsstagebranch), [Add-SalesforceDevOpsStageEnvironment](#add-salesforcedevopsstageenvironment), [Get-SalesforceDevOpsPipeline](#get-salesforcedevopspipeline), [Get-SalesforceDevOpsPipelineDetails](#get-salesforcedevopspipelinedetails), [New-SalesforceDevOpsPipeline](#new-salesforcedevopspipeline), [Remove-SalesforceDevOpsPipelineProject](#remove-salesforcedevopspipelineproject), [Remove-SalesforceDevOpsPipelineStage](#remove-salesforcedevopspipelinestage), [Remove-SalesforceDevOpsStageBranch](#remove-salesforcedevopsstagebranch), [Remove-SalesforceDevOpsStageEnvironment](#remove-salesforcedevopsstageenvironment), [Update-SalesforceDevOpsPipeline](#update-salesforcedevopspipeline), [Update-SalesforceDevOpsPipelineStage](#update-salesforcedevopspipelinestage)

**Promotions and request status**: [Complete-SalesforceDevOpsPromotion](#complete-salesforcedevopspromotion), [Get-SalesforceDevOpsRequestStatus](#get-salesforcedevopsrequeststatus), [Start-SalesforceDevOpsPromotion](#start-salesforcedevopspromotion), [Test-SalesforceDevOpsPromotion](#test-salesforcedevopspromotion)

**Projects**: [Get-SalesforceDevOpsProject](#get-salesforcedevopsproject), [New-SalesforceDevOpsProject](#new-salesforcedevopsproject), [Update-SalesforceDevOpsProject](#update-salesforcedevopsproject)

**Work items and reviews**: [Get-SalesforceDevOpsWorkItem](#get-salesforcedevopsworkitem), [Initialize-SalesforceDevOpsWorkItem](#initialize-salesforcedevopsworkitem), [Join-SalesforceDevOpsWorkItem](#join-salesforcedevopsworkitem), [New-SalesforceDevOpsReview](#new-salesforcedevopsreview), [New-SalesforceDevOpsWorkItem](#new-salesforcedevopsworkitem), [Update-SalesforceDevOpsWorkItem](#update-salesforcedevopsworkitem)

**Pipeline deployments**: [Get-SalesforcePipelineDeployStatus](#get-salesforcepipelinedeploystatus), [Resume-SalesforcePipelineDeploy](#resume-salesforcepipelinedeploy), [Start-SalesforcePipelineDeploy](#start-salesforcepipelinedeploy), [Start-SalesforcePipelineQuickDeploy](#start-salesforcepipelinequickdeploy), [Test-SalesforcePipelineDeploy](#test-salesforcepipelinedeploy)

## Pipelines and stages

### Add-SalesforceDevOpsPipelineProject

#### Synopsis

Attaches a project to a DevOps Center pipeline.

#### Syntax

```powershell
Add-SalesforceDevOpsPipelineProject [-PipelineId] <String> [-ProjectId] <String> [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops pipeline project add. Connects the project to the pipeline. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-PipelineId` (String, required): ID of the pipeline. Passed to sf as --pipeline-id. Required.
- `-ProjectId` (String, required): ID of the project to attach. Passed to sf as --project-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops pipeline project add`

#### Examples

```powershell
PS> Add-SalesforceDevOpsPipelineProject -PipelineId 0XB000000000001 -ProjectId 0Hn000000000001 -TargetOrg devops-org -WhatIf
```

Preview attaching a project.

#### Remarks

- To see the examples, type: "Get-Help Add-SalesforceDevOpsPipelineProject -Examples"
- For more information, type: "Get-Help Add-SalesforceDevOpsPipelineProject -Detailed"
- For technical information, type: "Get-Help Add-SalesforceDevOpsPipelineProject -Full"
- For online help, type: "Get-Help Add-SalesforceDevOpsPipelineProject -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Add-SalesforceDevOpsPipelineStage

#### Synopsis

Adds a stage to a DevOps Center pipeline.

#### Syntax

```powershell
Add-SalesforceDevOpsPipelineStage [-PipelineId] <String> [-Name] <String> [-NextStageId] <String> [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops pipeline stage add. Inserts an empty stage before the stage given as -NextStageId. The new stage has no branch or environment: add them with Add-SalesforceDevOpsStageBranch and Add-SalesforceDevOpsStageEnvironment. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-PipelineId` (String, required): ID of the pipeline. Passed to sf as --pipeline-id. Required.
- `-Name` (String, required): Name of the stage, such as Integration, UAT or Staging. Passed to sf as --name. Required.
- `-NextStageId` (String, required): ID of the stage that follows the new stage. Passed to sf as --next-stage-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops pipeline stage add`

#### Examples

```powershell
PS> Add-SalesforceDevOpsPipelineStage -PipelineId 0XB000000000001 -Name QA -NextStageId 1QV000000000002 -TargetOrg devops-org -WhatIf
```

Preview adding a QA stage.

#### Remarks

- To see the examples, type: "Get-Help Add-SalesforceDevOpsPipelineStage -Examples"
- For more information, type: "Get-Help Add-SalesforceDevOpsPipelineStage -Detailed"
- For technical information, type: "Get-Help Add-SalesforceDevOpsPipelineStage -Full"
- For online help, type: "Get-Help Add-SalesforceDevOpsPipelineStage -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Add-SalesforceDevOpsStageBranch

#### Synopsis

Assigns a repository branch to a pipeline stage.

#### Syntax

```powershell
Add-SalesforceDevOpsStageBranch [-PipelineId] <String> [-StageId] <String> [-BranchName] <String> [-CreateVcsBranch] [-Force] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops stage branch add. By default the branch must already exist in the repository; -CreateVcsBranch creates it. A stage has one branch. If it already has one the command stops so the old branch is not orphaned, unless you give -Force, which replaces it. Branches are set from right to left: a stage can have a branch only after the stage to its right has one. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-PipelineId` (String, required): ID of the pipeline that holds the stage. Passed to sf as --pipeline-id. Required.
- `-StageId` (String, required): ID of the stage. Passed to sf as --stage-id. Required.
- `-BranchName` (String, required): Name of the repository branch. Passed to sf as --branch-name. Required.
- `-CreateVcsBranch` (switch): Create the branch in the remote repository if it does not exist. Adds --create-vcs-branch.
- `-Force` (switch): Replace the stage's existing branch. Adds --force.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops stage branch add`

#### Examples

```powershell
PS> Add-SalesforceDevOpsStageBranch -PipelineId 0XB000000000001 -StageId 1QV000000000002 -BranchName uat -CreateVcsBranch -TargetOrg devops-org -WhatIf
```

Preview assigning a branch, creating it if needed.

#### Remarks

- To see the examples, type: "Get-Help Add-SalesforceDevOpsStageBranch -Examples"
- For more information, type: "Get-Help Add-SalesforceDevOpsStageBranch -Detailed"
- For technical information, type: "Get-Help Add-SalesforceDevOpsStageBranch -Full"
- For online help, type: "Get-Help Add-SalesforceDevOpsStageBranch -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Add-SalesforceDevOpsStageEnvironment

#### Synopsis

Adds a Salesforce environment to a pipeline stage.

#### Syntax

```powershell
Add-SalesforceDevOpsStageEnvironment [-PipelineId] <String> [-StageId] <String> [-EnvironmentName] <String> [-OrgType] <String> [-NoBrowser] [-Force] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops stage environment add. Starts an OAuth login to connect the environment, which opens a browser window (-NoBrowser prints the URL instead) and waits until you finish. A stage has one environment. If it already has one the command stops unless you give -Force, which adds the new one first and removes the old one after the new one is connected. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-PipelineId` (String, required): ID of the pipeline that holds the stage. Passed to sf as --pipeline-id. Required.
- `-StageId` (String, required): ID of the stage. Passed to sf as --stage-id. Required.
- `-EnvironmentName` (String, required): Name of the environment. Passed to sf as --environment-name. Required.
- `-OrgType` (String, required): Type of the Salesforce org. Valid values: Production, Sandbox. Passed to sf as --org-type. Required.
- `-NoBrowser` (switch): Do not open the browser for the login; the CLI prints the URL for you to open yourself. The CLI only prints it outside JSON mode, so with this switch the command runs live in your terminal without --json (it needs a terminal, and returns nothing). Adds --no-browser.
- `-Force` (switch): Replace the stage's existing environment. Adds --force.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops stage environment add`

#### Examples

```powershell
PS> Add-SalesforceDevOpsStageEnvironment -PipelineId 0XB000000000001 -StageId 1QV000000000002 -EnvironmentName uat-sandbox -OrgType Sandbox -TargetOrg devops-org -WhatIf
```

Preview connecting a sandbox to a stage.

#### Remarks

- To see the examples, type: "Get-Help Add-SalesforceDevOpsStageEnvironment -Examples"
- For more information, type: "Get-Help Add-SalesforceDevOpsStageEnvironment -Detailed"
- For technical information, type: "Get-Help Add-SalesforceDevOpsStageEnvironment -Full"
- For online help, type: "Get-Help Add-SalesforceDevOpsStageEnvironment -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceDevOpsPipeline

#### Synopsis

Lists the DevOps Center pipelines.

#### Syntax

```powershell
Get-SalesforceDevOpsPipeline [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf devops pipeline list. Returns every pipeline with its stages, repositories and connected projects. For one pipeline in detail use Get-SalesforceDevOpsPipelineDetails. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf devops pipeline list`

#### Examples

```powershell
PS> Get-SalesforceDevOpsPipeline -TargetOrg devops-org
```

All pipelines.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceDevOpsPipeline -Examples"
- For more information, type: "Get-Help Get-SalesforceDevOpsPipeline -Detailed"
- For technical information, type: "Get-Help Get-SalesforceDevOpsPipeline -Full"
- For online help, type: "Get-Help Get-SalesforceDevOpsPipeline -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceDevOpsPipelineDetails

#### Synopsis

Shows one DevOps Center pipeline in detail.

#### Syntax

```powershell
Get-SalesforceDevOpsPipelineDetails [-PipelineId] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf devops pipeline get. Returns one pipeline: its stages in order, the repository and branch of each stage, and its connected projects. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-PipelineId` (String, required): ID of the pipeline, from Get-SalesforceDevOpsPipeline. Passed to sf as --pipeline-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf devops pipeline get`

#### Examples

```powershell
PS> Get-SalesforceDevOpsPipelineDetails -PipelineId 0XB000000000001 -TargetOrg devops-org
```

One pipeline in detail.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceDevOpsPipelineDetails -Examples"
- For more information, type: "Get-Help Get-SalesforceDevOpsPipelineDetails -Detailed"
- For technical information, type: "Get-Help Get-SalesforceDevOpsPipelineDetails -Full"
- For online help, type: "Get-Help Get-SalesforceDevOpsPipelineDetails -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceDevOpsPipeline

#### Synopsis

Creates a DevOps Center pipeline attached to a repository.

#### Syntax

```powershell
New-SalesforceDevOpsPipeline [-Name] <String> [-Repo] <String> [[-Stage] <String[]>] [[-ProjectId] <String[]>] [-CreateRepo] [[-RepoType] <String>] [[-RepoOwner] <String>] [[-BitbucketWorkspace] <String>] [[-BitbucketProjectKey] <String>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops pipeline create. Give the URL of an existing repository as -Repo, or use -CreateRepo with a repository name to create one on GitHub or Bitbucket. After you create the pipeline, add stages (unless you gave -Stage) and activate it with Update-SalesforceDevOpsPipeline -Activate. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-Name` (String, required): Name of the pipeline. Passed to sf as --name. Required.
- `-Repo` (String, required): URL of an existing repository, or the name of a repository to create with -CreateRepo. Passed to sf as --repo. Required.
- `-Stage` (String[]): Names of the pipeline stages in promotion order. Each is passed to sf as its own --stage. The CLI default is Integration, UAT, Staging and Production. Passed to sf as --stage.
- `-ProjectId` (String[]): IDs of projects to associate with the pipeline. Each is passed to sf as its own --project-id. Passed to sf as --project-id.
- `-CreateRepo` (switch): Create the repository if it does not exist. Needs -RepoType, and -RepoOwner for GitHub or -BitbucketWorkspace for Bitbucket. Adds --create-repo.
- `-RepoType` (String): Type of the repository. Valid values: github, bitbucket. Needed with -CreateRepo. Passed to sf as --repo-type.
- `-RepoOwner` (String): Owner (organization or user) of the GitHub repository. Needed to create a GitHub repository. Passed to sf as --repo-owner.
- `-BitbucketWorkspace` (String): Bitbucket workspace that will own the repository. Needed to create a Bitbucket repository. Passed to sf as --bitbucket-workspace.
- `-BitbucketProjectKey` (String): Bitbucket project key to associate with the repository. Optional when creating a Bitbucket repository. Passed to sf as --bitbucket-project-key.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops pipeline create`

#### Examples

```powershell
PS> New-SalesforceDevOpsPipeline -Name 'Release Pipeline' -Repo https://github.com/myorg/myrepo -TargetOrg devops-org -WhatIf
```

Preview creating a pipeline on an existing repository.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceDevOpsPipeline -Examples"
- For more information, type: "Get-Help New-SalesforceDevOpsPipeline -Detailed"
- For technical information, type: "Get-Help New-SalesforceDevOpsPipeline -Full"
- For online help, type: "Get-Help New-SalesforceDevOpsPipeline -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceDevOpsPipelineProject

#### Synopsis

Disconnects a project from a DevOps Center pipeline.

#### Syntax

```powershell
Remove-SalesforceDevOpsPipelineProject [-PipelineId] <String> [-ProjectId] <String> [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops pipeline project delete. Removes the connection between the project and the pipeline. The project itself is not deleted. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-PipelineId` (String, required): ID of the pipeline. Passed to sf as --pipeline-id. Required.
- `-ProjectId` (String, required): ID of the project to disconnect. Passed to sf as --project-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops pipeline project delete`

#### Examples

```powershell
PS> Remove-SalesforceDevOpsPipelineProject -PipelineId 0XB000000000001 -ProjectId 0Hn000000000001 -TargetOrg devops-org -WhatIf
```

Preview disconnecting a project.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceDevOpsPipelineProject -Examples"
- For more information, type: "Get-Help Remove-SalesforceDevOpsPipelineProject -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceDevOpsPipelineProject -Full"
- For online help, type: "Get-Help Remove-SalesforceDevOpsPipelineProject -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceDevOpsPipelineStage

#### Synopsis

Deletes a stage from a DevOps Center pipeline.

#### Syntax

```powershell
Remove-SalesforceDevOpsPipelineStage [-PipelineId] <String> [-StageId] <String> [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops pipeline stage delete. If the stage sits between two others, the stage before it is linked to the stage after it, so the chain stays whole. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-PipelineId` (String, required): ID of the pipeline that holds the stage. Passed to sf as --pipeline-id. Required.
- `-StageId` (String, required): ID of the stage to delete. Passed to sf as --stage-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops pipeline stage delete`

#### Examples

```powershell
PS> Remove-SalesforceDevOpsPipelineStage -PipelineId 0XB000000000001 -StageId 1QV000000000002 -TargetOrg devops-org -WhatIf
```

Preview deleting a stage.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceDevOpsPipelineStage -Examples"
- For more information, type: "Get-Help Remove-SalesforceDevOpsPipelineStage -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceDevOpsPipelineStage -Full"
- For online help, type: "Get-Help Remove-SalesforceDevOpsPipelineStage -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceDevOpsStageBranch

#### Synopsis

Removes the branch of a pipeline stage from the stage.

#### Syntax

```powershell
Remove-SalesforceDevOpsStageBranch [-PipelineId] <String> [-StageId] <String> [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops stage branch delete. Only the link between the stage and its branch is removed; the branch in the repository stays. Branches are set from right to left, so this also removes the branches of every stage before it (to its left). The pipeline must be inactive. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-PipelineId` (String, required): ID of the pipeline that holds the stage. The CLI uses it to check that the pipeline is inactive. Passed to sf as --pipeline-id. Required.
- `-StageId` (String, required): ID of the stage whose branch to remove. Passed to sf as --stage-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops stage branch delete`

#### Examples

```powershell
PS> Remove-SalesforceDevOpsStageBranch -PipelineId 0XB000000000001 -StageId 1QV000000000002 -TargetOrg devops-org -WhatIf
```

Preview removing a stage's branch.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceDevOpsStageBranch -Examples"
- For more information, type: "Get-Help Remove-SalesforceDevOpsStageBranch -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceDevOpsStageBranch -Full"
- For online help, type: "Get-Help Remove-SalesforceDevOpsStageBranch -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Remove-SalesforceDevOpsStageEnvironment

#### Synopsis

Removes an environment from a pipeline stage.

#### Syntax

```powershell
Remove-SalesforceDevOpsStageEnvironment [-PipelineId] <String> [-EnvironmentId] <String> [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops stage environment delete. The pipeline must be inactive. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-PipelineId` (String, required): ID of the pipeline. The CLI uses it to check that the pipeline is inactive. Passed to sf as --pipeline-id. Required.
- `-EnvironmentId` (String, required): ID of the environment to remove. Passed to sf as --environment-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops stage environment delete`

#### Examples

```powershell
PS> Remove-SalesforceDevOpsStageEnvironment -PipelineId 0XB000000000001 -EnvironmentId 0Xx000000000001 -TargetOrg devops-org -WhatIf
```

Preview removing an environment.

#### Remarks

- To see the examples, type: "Get-Help Remove-SalesforceDevOpsStageEnvironment -Examples"
- For more information, type: "Get-Help Remove-SalesforceDevOpsStageEnvironment -Detailed"
- For technical information, type: "Get-Help Remove-SalesforceDevOpsStageEnvironment -Full"
- For online help, type: "Get-Help Remove-SalesforceDevOpsStageEnvironment -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Update-SalesforceDevOpsPipeline

#### Synopsis

Renames, activates or deactivates a DevOps Center pipeline.

#### Syntax

```powershell
Update-SalesforceDevOpsPipeline [-PipelineId] <String> [[-Name] <String>] [-Activate] [-Deactivate] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops pipeline update. Give at least one of -Name, -Activate and -Deactivate. A pipeline needs at least one stage before you can activate it, and you cannot change its stages after you activate it and promote changes through it, so -Activate asks for confirmation. You can combine -Deactivate and -Name. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-PipelineId` (String, required): ID of the pipeline. Passed to sf as --pipeline-id. Required.
- `-Name` (String): New name of the pipeline. Passed to sf as --name.
- `-Activate` (switch): Activate the pipeline. Cannot be used with -Deactivate. Asks for confirmation by default. Adds --activate.
- `-Deactivate` (switch): Deactivate the pipeline. Cannot be used with -Activate. Adds --deactivate.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops pipeline update`

#### Examples

```powershell
PS> Update-SalesforceDevOpsPipeline -PipelineId 0XB000000000001 -Activate -TargetOrg devops-org -WhatIf
```

Preview activating a pipeline.

#### Remarks

- To see the examples, type: "Get-Help Update-SalesforceDevOpsPipeline -Examples"
- For more information, type: "Get-Help Update-SalesforceDevOpsPipeline -Detailed"
- For technical information, type: "Get-Help Update-SalesforceDevOpsPipeline -Full"
- For online help, type: "Get-Help Update-SalesforceDevOpsPipeline -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Update-SalesforceDevOpsPipelineStage

#### Synopsis

Renames a stage of a DevOps Center pipeline.

#### Syntax

```powershell
Update-SalesforceDevOpsPipelineStage [-StageId] <String> [-Name] <String> [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops pipeline stage update. Changes the name of the stage. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-StageId` (String, required): ID of the stage. Passed to sf as --stage-id. Required.
- `-Name` (String, required): New name of the stage. Passed to sf as --name. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops pipeline stage update`

#### Examples

```powershell
PS> Update-SalesforceDevOpsPipelineStage -StageId 1QV000000000002 -Name Staging -TargetOrg devops-org -WhatIf
```

Preview renaming a stage.

#### Remarks

- To see the examples, type: "Get-Help Update-SalesforceDevOpsPipelineStage -Examples"
- For more information, type: "Get-Help Update-SalesforceDevOpsPipelineStage -Detailed"
- For technical information, type: "Get-Help Update-SalesforceDevOpsPipelineStage -Full"
- For online help, type: "Get-Help Update-SalesforceDevOpsPipelineStage -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Promotions and request status

### Complete-SalesforceDevOpsPromotion

#### Synopsis

Deploys work items that were merged outside DevOps Center to a stage.

#### Syntax

```powershell
Complete-SalesforceDevOpsPromotion [-TargetStageId] <String> [[-WorkItemId] <String[]>] [-DeployAll] [[-TestLevel] <String>] [[-Tests] <String[]>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops promotion complete. Deploys work items that were merged into the pipeline branch outside DevOps Center (externally merged) into the target stage's org and updates the DevOps Center records. It is the "Complete Promotion" action of the DevOps Center page for a stage that is out of sync. Without -WorkItemId it deploys every undeployed work item of the stage; if there are none it does nothing and succeeds. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-TargetStageId` (String, required): ID of the out-of-sync stage to deploy to. Passed to sf as --target-stage-id. Required.
- `-WorkItemId` (String[]): IDs of specific work items to deploy. Each is passed to sf as its own --work-item-id. Leave it out to deploy all the undeployed work items of the stage; use it for the first stage of a pipeline, which has no source stage. Passed to sf as --work-item-id.
- `-DeployAll` (switch): Deploy all the metadata in the branch, not only the changes that are not yet in the stage. Adds --deploy-all.
- `-TestLevel` (String): Apex test level of the deployment. Valid values: NoTestRun, RunSpecifiedTests, RunLocalTests, RunAllTestsInOrg. NoTestRun is only for development orgs. Passed to sf as --test-level.
- `-Tests` (String[]): Apex tests to run with -TestLevel RunSpecifiedTests. Each is passed to sf as its own --tests. Passed to sf as --tests.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops promotion complete`

#### Examples

```powershell
PS> Complete-SalesforceDevOpsPromotion -TargetStageId 1QV000000000002 -TargetOrg devops-org -WhatIf
```

Preview completing the promotion of a stage.

#### Remarks

- To see the examples, type: "Get-Help Complete-SalesforceDevOpsPromotion -Examples"
- For more information, type: "Get-Help Complete-SalesforceDevOpsPromotion -Detailed"
- For technical information, type: "Get-Help Complete-SalesforceDevOpsPromotion -Full"
- For online help, type: "Get-Help Complete-SalesforceDevOpsPromotion -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Get-SalesforceDevOpsRequestStatus

#### Synopsis

Gets the status of a DevOps Center request.

#### Syntax

```powershell
Get-SalesforceDevOpsRequestStatus [-RequestToken] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf devops request status. Returns the current status of the request with the given token, such as the one Start-SalesforceDevOpsPromotion returns. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-RequestToken` (String, required): The request token from the promotion result. Passed to sf as --request-token. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf devops request status`

#### Examples

```powershell
PS> Get-SalesforceDevOpsRequestStatus -RequestToken $promotion.requestToken -TargetOrg devops-org
```

Check on a promotion.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceDevOpsRequestStatus -Examples"
- For more information, type: "Get-Help Get-SalesforceDevOpsRequestStatus -Detailed"
- For technical information, type: "Get-Help Get-SalesforceDevOpsRequestStatus -Full"
- For online help, type: "Get-Help Get-SalesforceDevOpsRequestStatus -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Start-SalesforceDevOpsPromotion

#### Synopsis

Promotes work items, or a whole stage, to a pipeline stage.

#### Syntax

```powershell
Start-SalesforceDevOpsPromotion [-TargetStageId] <String> [[-WorkItemId] <String[]>] [[-StageId] <String>] [-DeployAll] [-Force] [-SkipValidation] [[-TestLevel] <String>] [[-Tests] <String[]>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops promote. Give -WorkItemId to promote specific work items, or -StageId to promote all the approved work items of a source stage; exactly one of the two. It deploys to the org of the target stage. By default it stops if another promotion to the same stage is running (-Force overrides) and it checks first that each work item has a pull request (-SkipValidation skips that). It returns a request token that Get-SalesforceDevOpsRequestStatus takes. Asks for confirmation (use -Confirm:$false in a script) and supports -WhatIf. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-TargetStageId` (String, required): ID of the pipeline stage to promote to. Passed to sf as --target-stage-id. Required.
- `-WorkItemId` (String[]): IDs of the work items to promote. Each is passed to sf as its own --work-item-id. Use it or -StageId. Passed to sf as --work-item-id.
- `-StageId` (String): ID of the source stage whose approved work items are promoted. Use it or -WorkItemId. Passed to sf as --stage-id.
- `-DeployAll` (switch): Deploy all the metadata in the branch, not only the changes that are not yet in the target stage. Adds --deploy-all.
- `-Force` (switch): Submit the promotion even if another promotion to the same target stage is in progress. Adds --force.
- `-SkipValidation` (switch): Skip the check before the promotion that each work item has a pull request. Adds --skip-validation.
- `-TestLevel` (String): Apex test level of the deployment. Valid values: NoTestRun, RunSpecifiedTests, RunLocalTests, RunAllTestsInOrg. NoTestRun is only for development orgs. Passed to sf as --test-level.
- `-Tests` (String[]): Apex tests to run with -TestLevel RunSpecifiedTests. Each is passed to sf as its own --tests. Passed to sf as --tests.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops promote`

#### Examples

```powershell
PS> Start-SalesforceDevOpsPromotion -StageId 1QV000000000001 -TargetStageId 1QV000000000002 -TargetOrg devops-org -WhatIf
```

Preview promoting a whole stage.

#### Remarks

- To see the examples, type: "Get-Help Start-SalesforceDevOpsPromotion -Examples"
- For more information, type: "Get-Help Start-SalesforceDevOpsPromotion -Detailed"
- For technical information, type: "Get-Help Start-SalesforceDevOpsPromotion -Full"
- For online help, type: "Get-Help Start-SalesforceDevOpsPromotion -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Test-SalesforceDevOpsPromotion

#### Synopsis

Checks whether work items can be promoted to a stage.

#### Syntax

```powershell
Test-SalesforceDevOpsPromotion [-TargetStageId] <String> [-WorkItemId] <String[]> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf devops promotion validate. Validates the work items for the target stage: it looks for version control and object permission errors before a promotion is tried. It does not deploy anything. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-TargetStageId` (String, required): ID of the stage to validate the promotion to. Passed to sf as --target-stage-id. Required.
- `-WorkItemId` (String[], required): IDs of the work items to validate. Each is passed to sf as its own --work-item-id. Passed to sf as --work-item-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf devops promotion validate`

#### Examples

```powershell
PS> Test-SalesforceDevOpsPromotion -WorkItemId 1fk000000000001 -TargetStageId 1QV000000000002 -TargetOrg devops-org
PS> Can this work item be promoted?
```

#### Remarks

- To see the examples, type: "Get-Help Test-SalesforceDevOpsPromotion -Examples"
- For more information, type: "Get-Help Test-SalesforceDevOpsPromotion -Detailed"
- For technical information, type: "Get-Help Test-SalesforceDevOpsPromotion -Full"
- For online help, type: "Get-Help Test-SalesforceDevOpsPromotion -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Projects

### Get-SalesforceDevOpsProject

#### Synopsis

Lists the DevOps Center projects of an org.

#### Syntax

```powershell
Get-SalesforceDevOpsProject [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf devops project list. Returns the DevOps Center projects with their IDs, which the work item, pipeline and promotion cmdlets take. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf devops project list`

#### Examples

```powershell
PS> Get-SalesforceDevOpsProject -TargetOrg devops-org
```

List the projects.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceDevOpsProject -Examples"
- For more information, type: "Get-Help Get-SalesforceDevOpsProject -Detailed"
- For technical information, type: "Get-Help Get-SalesforceDevOpsProject -Full"
- For online help, type: "Get-Help Get-SalesforceDevOpsProject -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceDevOpsProject

#### Synopsis

Creates a DevOps Center project.

#### Syntax

```powershell
New-SalesforceDevOpsProject [-Name] <String> [[-Description] <String>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops project create. Creates a project with a name and an optional description in the DevOps Center org. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-Name` (String, required): Name of the project. Passed to sf as --name. Required.
- `-Description` (String): Description of the project. Passed to sf as --description.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops project create`

#### Examples

```powershell
PS> New-SalesforceDevOpsProject -Name 'Sales App' -Description 'Quarterly releases' -TargetOrg devops-org -WhatIf
```

Preview creating a project.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceDevOpsProject -Examples"
- For more information, type: "Get-Help New-SalesforceDevOpsProject -Detailed"
- For technical information, type: "Get-Help New-SalesforceDevOpsProject -Full"
- For online help, type: "Get-Help New-SalesforceDevOpsProject -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Update-SalesforceDevOpsProject

#### Synopsis

Renames, describes or activates or deactivates a DevOps Center project.

#### Syntax

```powershell
Update-SalesforceDevOpsProject [-ProjectId] <String> [[-Name] <String>] [[-Description] <String>] [-IsActive] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops project update. Give at least one of -Name, -Description and -IsActive. Use -IsActive to activate the project and -IsActive:$false to deactivate it. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-ProjectId` (String, required): ID of the project to update. Passed to sf as --project-id. Required.
- `-Name` (String): New name of the project. Passed to sf as --name.
- `-Description` (String): New description of the project. Passed to sf as --description.
- `-IsActive` (switch): Set whether the project is active. Adds --is-active, or --no-is-active when you write -IsActive:$false. Passed to sf as --is-active.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops project update`

#### Examples

```powershell
PS> Update-SalesforceDevOpsProject -ProjectId 0Hn000000000001 -IsActive:$false -TargetOrg devops-org -WhatIf
```

Preview deactivating a project.

#### Remarks

- To see the examples, type: "Get-Help Update-SalesforceDevOpsProject -Examples"
- For more information, type: "Get-Help Update-SalesforceDevOpsProject -Detailed"
- For technical information, type: "Get-Help Update-SalesforceDevOpsProject -Full"
- For online help, type: "Get-Help Update-SalesforceDevOpsProject -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Work items and reviews

### Get-SalesforceDevOpsWorkItem

#### Synopsis

Lists the work items of a DevOps Center project.

#### Syntax

```powershell
Get-SalesforceDevOpsWorkItem [-ProjectId] <String> [[-TargetOrg] <String>] [<CommonParameters>]
```

#### Description

Runs sf devops work-item list. Each work item shows the branch, environment and repository details needed to check it out and promote it, and its ID, which the promotion cmdlets take. It only reads. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-ProjectId` (String, required): ID of the project, from Get-SalesforceDevOpsProject. Passed to sf as --project-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.

#### Salesforce CLI

- `sf devops work-item list`

#### Examples

```powershell
PS> Get-SalesforceDevOpsWorkItem -ProjectId 1Qg000000000001 -TargetOrg devops-org
```

The work items of a project.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforceDevOpsWorkItem -Examples"
- For more information, type: "Get-Help Get-SalesforceDevOpsWorkItem -Detailed"
- For technical information, type: "Get-Help Get-SalesforceDevOpsWorkItem -Full"
- For online help, type: "Get-Help Get-SalesforceDevOpsWorkItem -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Initialize-SalesforceDevOpsWorkItem

#### Synopsis

Prepares a work item for a one-off promotion to a stage.

#### Syntax

```powershell
Initialize-SalesforceDevOpsWorkItem [-WorkItemId] <String> [-TargetStageId] <String> [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops work-item prepare. Creates the branches and pull requests in the source control repository that a one-off promotion needs. Run it before Start-SalesforceDevOpsPromotion for a one-off promotion. Get the IDs from Get-SalesforceDevOpsWorkItem. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-WorkItemId` (String, required): ID of the work item to prepare. Passed to sf as --work-item-id. Required.
- `-TargetStageId` (String, required): ID of the pipeline stage to promote the work item to. Passed to sf as --target-stage-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops work-item prepare`

#### Examples

```powershell
PS> Initialize-SalesforceDevOpsWorkItem -WorkItemId 1fk000000000001 -TargetStageId 1QV000000000001 -TargetOrg devops-org -WhatIf
```

Preview preparing a work item.

#### Remarks

- To see the examples, type: "Get-Help Initialize-SalesforceDevOpsWorkItem -Examples"
- For more information, type: "Get-Help Initialize-SalesforceDevOpsWorkItem -Detailed"
- For technical information, type: "Get-Help Initialize-SalesforceDevOpsWorkItem -Full"
- For online help, type: "Get-Help Initialize-SalesforceDevOpsWorkItem -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Join-SalesforceDevOpsWorkItem

#### Synopsis

Prepares work items to be combined and promoted together.

#### Syntax

```powershell
Join-SalesforceDevOpsWorkItem [-ParentWorkItemId] <String> [-ChildWorkItemId] <String[]> [-TargetStageId] <String> [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops work-item combine. Use it when work items in the same stage share metadata or depend on each other: DevOps Center combines the child work items into the parent so they are promoted as one unit. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-ParentWorkItemId` (String, required): ID of the parent work item. Passed to sf as --parent-work-item-id. Required.
- `-ChildWorkItemId` (String[], required): IDs of the work items to combine into the parent. Each is passed to sf as its own --child-work-item-id. Passed to sf as --child-work-item-id. Required.
- `-TargetStageId` (String, required): ID of the pipeline stage to promote the combined work item to. Passed to sf as --target-stage-id. Required.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops work-item combine`

#### Examples

```powershell
PS> Join-SalesforceDevOpsWorkItem -ParentWorkItemId 1fk000000000001 -ChildWorkItemId 1fk000000000002, 1fk000000000003 -TargetStageId 1QV000000000001 -TargetOrg devops-org -WhatIf
```

Preview combining two work items into one.

#### Remarks

- To see the examples, type: "Get-Help Join-SalesforceDevOpsWorkItem -Examples"
- For more information, type: "Get-Help Join-SalesforceDevOpsWorkItem -Detailed"
- For technical information, type: "Get-Help Join-SalesforceDevOpsWorkItem -Full"
- For online help, type: "Get-Help Join-SalesforceDevOpsWorkItem -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceDevOpsReview

#### Synopsis

Creates a pull request for a work item branch.

#### Syntax

```powershell
New-SalesforceDevOpsReview [[-WorkItemId] <String>] [[-WorkItemName] <String>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops review create. Creates the pull request through the DevOps Center API with the version control credentials stored in the org, for GitHub and Bitbucket, so no local login to the repository is needed. Identify the work item by -WorkItemId or -WorkItemName. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-WorkItemId` (String): ID of the work item. Use it or -WorkItemName. Passed to sf as --work-item-id.
- `-WorkItemName` (String): Name of the work item, such as WI-000001. Use it or -WorkItemId. Passed to sf as --work-item-name.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops review create`

#### Examples

```powershell
PS> New-SalesforceDevOpsReview -WorkItemName WI-000001 -TargetOrg devops-org -WhatIf
```

Preview opening a pull request.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceDevOpsReview -Examples"
- For more information, type: "Get-Help New-SalesforceDevOpsReview -Detailed"
- For technical information, type: "Get-Help New-SalesforceDevOpsReview -Full"
- For online help, type: "Get-Help New-SalesforceDevOpsReview -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### New-SalesforceDevOpsWorkItem

#### Synopsis

Creates a work item in a DevOps Center project.

#### Syntax

```powershell
New-SalesforceDevOpsWorkItem [-ProjectId] <String> [-Subject] <String> [[-Description] <String>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops work-item create. Creates a work item with a subject and an optional description. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-ProjectId` (String, required): ID of the project to create the work item in. Passed to sf as --project-id. Required.
- `-Subject` (String, required): Subject (title) of the work item. Passed to sf as --subject. Required.
- `-Description` (String): Description of the work item. Passed to sf as --description.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops work-item create`

#### Examples

```powershell
PS> New-SalesforceDevOpsWorkItem -ProjectId 1Qg000000000001 -Subject 'Add invoice flow' -TargetOrg devops-org
```

Create a work item.

#### Remarks

- To see the examples, type: "Get-Help New-SalesforceDevOpsWorkItem -Examples"
- For more information, type: "Get-Help New-SalesforceDevOpsWorkItem -Detailed"
- For technical information, type: "Get-Help New-SalesforceDevOpsWorkItem -Full"
- For online help, type: "Get-Help New-SalesforceDevOpsWorkItem -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Update-SalesforceDevOpsWorkItem

#### Synopsis

Changes the subject, description or status of a work item.

#### Syntax

```powershell
Update-SalesforceDevOpsWorkItem [[-WorkItemId] <String>] [[-WorkItemName] <String>] [[-Subject] <String>] [[-Description] <String>] [[-Status] <String>] [[-TargetOrg] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf devops work-item update. Identify the work item by -WorkItemId or by -WorkItemName, and give at least one of -Subject, -Description and -Status. Supports -WhatIf and -Confirm; it does not ask by default. It needs a DevOps Center org that you are logged in to (-TargetOrg, or the target-org configuration) and a user who is allowed to work with DevOps Center; the CLI reports a permission error if not. The command comes from the @salesforce/plugin-devops-center plugin, which the CLI installs the first time it needs it.

#### Parameters

- `-WorkItemId` (String): ID of the work item. Use it or -WorkItemName. Passed to sf as --work-item-id.
- `-WorkItemName` (String): Name of the work item, such as WI-000001. Use it or -WorkItemId. Passed to sf as --work-item-name.
- `-Subject` (String): New subject. Passed to sf as --subject.
- `-Description` (String): New description. Passed to sf as --description.
- `-Status` (String): New status. Valid values: In Progress, Ready to Promote. Passed to sf as --status.
- `-TargetOrg` (String): Username or alias of the target org. Not required if the `target-org` configuration variable is already set. Passed to sf as --target-org.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf devops work-item update`

#### Examples

```powershell
PS> Update-SalesforceDevOpsWorkItem -WorkItemName WI-000001 -Status 'Ready to Promote' -TargetOrg devops-org -WhatIf
```

Preview marking a work item ready.

#### Remarks

- To see the examples, type: "Get-Help Update-SalesforceDevOpsWorkItem -Examples"
- For more information, type: "Get-Help Update-SalesforceDevOpsWorkItem -Detailed"
- For technical information, type: "Get-Help Update-SalesforceDevOpsWorkItem -Full"
- For online help, type: "Get-Help Update-SalesforceDevOpsWorkItem -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

## Pipeline deployments

### Get-SalesforcePipelineDeployStatus

#### Synopsis

Reports the status of a DevOps Center pipeline deployment (beta).

#### Syntax

```powershell
Get-SalesforcePipelineDeployStatus [-DevOpsCenterUsername] <String> [[-JobId] <String>] [-UseMostRecent] [<CommonParameters>]
```

#### Description

Runs sf project deploy pipeline report, a beta command of the DevOps Center plugin, for a job ID or for the most recent deployment with -UseMostRecent. Read-only. Because the command is beta, its name, flags and result can change in a later CLI release.

#### Parameters

- `-DevOpsCenterUsername` (String, required): Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.
- `-JobId` (String): Job ID of the pipeline deployment. A 15 or 18 character ID. Passed as --job-id.
- `-UseMostRecent` (switch): Report on the deployment the CLI started most recently. Use instead of -JobId. Adds --use-most-recent.

#### Salesforce CLI

- `sf project deploy pipeline report`

#### Examples

```powershell
PS> Get-SalesforcePipelineDeployStatus -DevOpsCenterUsername doc-org -UseMostRecent
```

Status of the last pipeline deployment.

#### Remarks

- To see the examples, type: "Get-Help Get-SalesforcePipelineDeployStatus -Examples"
- For more information, type: "Get-Help Get-SalesforcePipelineDeployStatus -Detailed"
- For technical information, type: "Get-Help Get-SalesforcePipelineDeployStatus -Full"
- For online help, type: "Get-Help Get-SalesforcePipelineDeployStatus -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Resume-SalesforcePipelineDeploy

#### Synopsis

Resumes watching a DevOps Center pipeline deployment that is still running (beta).

#### Syntax

```powershell
Resume-SalesforcePipelineDeploy [-DevOpsCenterUsername] <String> [[-JobId] <String>] [-UseMostRecent] [[-Wait] <Int32>] [-ConciseResults] [-DetailedResults] [<CommonParameters>]
```

#### Description

Runs sf project deploy pipeline resume, a beta command of the DevOps Center plugin, for a job ID or for the most recent deployment with -UseMostRecent. Because the command is beta, its name, flags and result can change in a later CLI release.

#### Parameters

- `-DevOpsCenterUsername` (String, required): Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.
- `-JobId` (String): Job ID of the pipeline deployment. A 15 or 18 character ID. Passed as --job-id.
- `-UseMostRecent` (switch): Resume the deployment the CLI started most recently. Use instead of -JobId. Adds --use-most-recent.
- `-Wait` (Int32): Number of minutes to wait for the deployment to finish. Passed as --wait.
- `-ConciseResults` (switch): Show concise output of the result. Adds --concise.
- `-DetailedResults` (switch): Show verbose output of the result. Adds --verbose.

#### Salesforce CLI

- `sf project deploy pipeline resume`

#### Examples

```powershell
PS> Resume-SalesforcePipelineDeploy -DevOpsCenterUsername doc-org -UseMostRecent -Wait 10
```

Wait up to ten more minutes for the last pipeline deployment.

#### Remarks

- To see the examples, type: "Get-Help Resume-SalesforcePipelineDeploy -Examples"
- For more information, type: "Get-Help Resume-SalesforcePipelineDeploy -Detailed"
- For technical information, type: "Get-Help Resume-SalesforcePipelineDeploy -Full"
- For online help, type: "Get-Help Resume-SalesforcePipelineDeploy -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Start-SalesforcePipelineDeploy

#### Synopsis

Deploys the changes of a branch to the org of a DevOps Center pipeline stage (beta).

#### Syntax

```powershell
Start-SalesforcePipelineDeploy [-DevOpsCenterUsername] <String> [-DevOpsCenterProjectName] <String> [-BranchName] <String> [[-BundleVersionName] <String>] [-DeployAll] [[-TestLevel] <String>] [[-Tests] <String[]>] [[-Wait] <Int32>] [-Async] [-ConciseResults] [-DetailedResults] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf project deploy pipeline start, a beta command of the DevOps Center plugin. It needs a DevOps Center org that you are logged in to (-DevOpsCenterUsername) and the name of the DevOps Center project. Because the command is beta, its name, flags and result can change in a later CLI release. Asks for confirmation and supports -WhatIf. Returns the CLI result, which holds the job ID that Get-SalesforcePipelineDeployStatus, Resume-SalesforcePipelineDeploy and Start-SalesforcePipelineQuickDeploy take.

#### Parameters

- `-DevOpsCenterUsername` (String, required): Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.
- `-DevOpsCenterProjectName` (String, required): Name of the DevOps Center project. Passed as --devops-center-project-name. Required.
- `-BranchName` (String, required): Branch whose changes are deployed to the pipeline stage. Passed as --branch-name. Required.
- `-BundleVersionName` (String): Version name of the bundle to deploy. Passed as --bundle-version-name.
- `-DeployAll` (switch): Deploy all the metadata in the branch, not only the changes. Adds --deploy-all.
- `-TestLevel` (String): Apex testing level. Passed to sf as --test-level. Valid values: NoTests, SpecificTests, TestsInOrg, TestsInOrgAndPackages. Value mapping to the CLI: NoTests = NoTestRun, SpecificTests = RunSpecifiedTests, TestsInOrg = RunLocalTests, TestsInOrgAndPackages = RunAllTestsInOrg. The CLI default applies when omitted.
- `-Tests` (String[]): Apex test classes to run with -TestLevel SpecificTests. Passed as one --tests per name.
- `-Wait` (Int32): Number of minutes to wait for the deployment to finish. Passed as --wait. Cannot be used with -Async.
- `-Async` (switch): Start the deployment and return without waiting. Adds --async.
- `-ConciseResults` (switch): Show concise output of the result. Adds --concise.
- `-DetailedResults` (switch): Show verbose output of the result. Adds --verbose.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf project deploy pipeline start`

#### Examples

```powershell
PS> Start-SalesforcePipelineDeploy -DevOpsCenterUsername doc-org -DevOpsCenterProjectName "Sales App" -BranchName feature/new-flow -TestLevel TestsInOrg -WhatIf
```

Preview deploying a branch with all local tests.

#### Remarks

- To see the examples, type: "Get-Help Start-SalesforcePipelineDeploy -Examples"
- For more information, type: "Get-Help Start-SalesforcePipelineDeploy -Detailed"
- For technical information, type: "Get-Help Start-SalesforcePipelineDeploy -Full"
- For online help, type: "Get-Help Start-SalesforcePipelineDeploy -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Start-SalesforcePipelineQuickDeploy

#### Synopsis

Deploys a validated pipeline deployment without running the tests again (beta).

#### Syntax

```powershell
Start-SalesforcePipelineQuickDeploy [-DevOpsCenterUsername] <String> [[-JobId] <String>] [-UseMostRecent] [[-Wait] <Int32>] [-Async] [-ConciseResults] [-DetailedResults] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

Runs sf project deploy pipeline quick, a beta command of the DevOps Center plugin, for the job ID of a validation made with Test-SalesforcePipelineDeploy (or the most recent one with -UseMostRecent). Because the command is beta, its name, flags and result can change in a later CLI release. Asks for confirmation and supports -WhatIf.

#### Parameters

- `-DevOpsCenterUsername` (String, required): Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.
- `-JobId` (String): Job ID of the validated deployment. A 15 or 18 character ID. Passed as --job-id.
- `-UseMostRecent` (switch): Use the validation the CLI ran most recently. Use instead of -JobId. Adds --use-most-recent.
- `-Wait` (Int32): Number of minutes to wait for the deployment to finish. Passed as --wait. Cannot be used with -Async.
- `-Async` (switch): Start the deployment and return without waiting. Adds --async.
- `-ConciseResults` (switch): Show concise output of the result. Adds --concise.
- `-DetailedResults` (switch): Show verbose output of the result. Adds --verbose.
- `-WhatIf` (switch): 
- `-Confirm` (switch): 

#### Salesforce CLI

- `sf project deploy pipeline quick`

#### Examples

```powershell
PS> Start-SalesforcePipelineQuickDeploy -DevOpsCenterUsername doc-org -UseMostRecent -WhatIf
```

Preview the quick deploy of the last validation.

#### Remarks

- To see the examples, type: "Get-Help Start-SalesforcePipelineQuickDeploy -Examples"
- For more information, type: "Get-Help Start-SalesforcePipelineQuickDeploy -Detailed"
- For technical information, type: "Get-Help Start-SalesforcePipelineQuickDeploy -Full"
- For online help, type: "Get-Help Start-SalesforcePipelineQuickDeploy -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>

### Test-SalesforcePipelineDeploy

#### Synopsis

Validates a deployment of a branch to the org of a DevOps Center pipeline stage, without deploying it (beta).

#### Syntax

```powershell
Test-SalesforcePipelineDeploy [-DevOpsCenterUsername] <String> [-DevOpsCenterProjectName] <String> [-BranchName] <String> [[-BundleVersionName] <String>] [-DeployAll] [[-TestLevel] <String>] [[-Tests] <String[]>] [[-Wait] <Int32>] [-Async] [-ConciseResults] [-DetailedResults] [<CommonParameters>]
```

#### Description

Runs sf project deploy pipeline validate, a beta command of the DevOps Center plugin. Nothing is deployed; a passing validation can be released with Start-SalesforcePipelineQuickDeploy. It needs a DevOps Center org that you are logged in to. Because the command is beta, its name, flags and result can change in a later CLI release.

#### Parameters

- `-DevOpsCenterUsername` (String, required): Username or alias of the DevOps Center org. Passed as --devops-center-username. Required.
- `-DevOpsCenterProjectName` (String, required): Name of the DevOps Center project. Passed as --devops-center-project-name. Required.
- `-BranchName` (String, required): Branch whose changes are validated. Passed as --branch-name. Required.
- `-BundleVersionName` (String): Version name of the bundle to validate. Passed as --bundle-version-name.
- `-DeployAll` (switch): Validate all the metadata in the branch, not only the changes. Adds --deploy-all.
- `-TestLevel` (String): Apex testing level. Passed to sf as --test-level. Valid values: NoTests, SpecificTests, TestsInOrg, TestsInOrgAndPackages. Value mapping to the CLI: NoTests = NoTestRun, SpecificTests = RunSpecifiedTests, TestsInOrg = RunLocalTests, TestsInOrgAndPackages = RunAllTestsInOrg. The CLI default applies when omitted.
- `-Tests` (String[]): Apex test classes to run with -TestLevel SpecificTests. Passed as one --tests per name.
- `-Wait` (Int32): Number of minutes to wait for the validation to finish. Passed as --wait. Cannot be used with -Async.
- `-Async` (switch): Start the validation and return without waiting. Adds --async.
- `-ConciseResults` (switch): Show concise output of the result. Adds --concise.
- `-DetailedResults` (switch): Show verbose output of the result. Adds --verbose.

#### Salesforce CLI

- `sf project deploy pipeline validate`

#### Examples

```powershell
PS> Test-SalesforcePipelineDeploy -DevOpsCenterUsername doc-org -DevOpsCenterProjectName "Sales App" -BranchName main -TestLevel TestsInOrg -Wait 30
```

Validate a branch with all local tests.

#### Remarks

- To see the examples, type: "Get-Help Test-SalesforcePipelineDeploy -Examples"
- For more information, type: "Get-Help Test-SalesforcePipelineDeploy -Detailed"
- For technical information, type: "Get-Help Test-SalesforcePipelineDeploy -Full"
- For online help, type: "Get-Help Test-SalesforcePipelineDeploy -Online"

#### Related Links

- <https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference.html>
- <https://github.com/salesforcecli/plugin-devops-center>
- <https://github.com/tonygward/psfdx/blob/main/docs/cli-parity.md>
- <https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters>
