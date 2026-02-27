#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Pylavi composite contract' {
    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $actionPath = Join-Path $repoRoot '.github/actions/pylavi-ci/action.yml'
        if (-not (Test-Path -LiteralPath $actionPath -PathType Leaf)) {
            throw "Composite action not found: $actionPath"
        }

        $script:content = Get-Content -LiteralPath $actionPath -Raw
    }

    It 'defines required inputs and outputs for deterministic pylavi contract' {
        foreach ($token in @(
            'config_path:',
            'labview_numeric:',
            'label:',
            'report_only:',
            'absolute_roots:',
            'baseline_path:',
            'baseline_required:',
            'fail_on_delta:'
        )) {
            $script:content | Should -Match ([regex]::Escape($token))
        }

        foreach ($outputToken in @('status:', 'exit_code:', 'log_path:', 'offenders_path:', 'summary_path:')) {
            $script:content | Should -Match ([regex]::Escape($outputToken))
        }
    }

    It 'installs pylavi directly and runs vi_validate without runner-cli dependency' {
        $script:content | Should -Match 'actions/setup-python@v5'
        $script:content | Should -Match 'python -m pip install pylavi'
        $script:content | Should -Match 'vi_validate --config'
        $script:content | Should -Not -Match 'LVIE_RUNNER_CLI_PATH'
        $script:content | Should -Not -Match 'runner-cli\.exe'
        $script:content | Should -Not -Match 'Tooling/runner-cli'
    }

    It 'supports report-only and strict failure behavior' {
        $script:content | Should -Match 'report_only'
        $script:content | Should -Match 'if \(\$status -eq ''warn''\)'
        $script:content | Should -Match 'if \(\$status -eq ''fail''\)'
    }
}
