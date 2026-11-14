Describe 'Start-MatrixPsfdx.ps1' {
    BeforeAll {
        $script:Script = Join-Path (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools') 'matrix-linux') 'Start-MatrixPsfdx.ps1'
        $script:Errors = $null
        $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Script, [ref]$null, [ref]$script:Errors)
    }

    It 'parses without errors' {
        @($script:Errors).Count | Should -Be 0
    }

    It 'offers exactly the ten actions' {
        $action = $script:Ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Action' }
        $validate = $action.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
        $values = @($validate.PositionalArguments | ForEach-Object { $_.Value })
        $values | Should -Be @('Build', 'Verify', 'Login', 'Run', 'Ensure', 'Logs', 'Pause', 'Resume', 'Stop', 'Down')
    }

    It 'only names objects that start with psfdx-matrix-' {
        $text = Get-Content -Path $script:Script -Raw
        $text | Should -Not -Match "(?<!psfdx-)matrix-(agent|egress|work|home|internal)\b"
        $text | Should -Not -Match 'agent-internal'
    }

    It 'uses Join-Path with two arguments only (Windows PowerShell 5.1)' {
        $calls = $script:Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Join-Path' }, $true)
        foreach ($call in $calls) {
            @($call.CommandElements | Where-Object { $_ -isnot [System.Management.Automation.Language.CommandParameterAst] }).Count | Should -BeLessOrEqual 3
        }
    }
}
