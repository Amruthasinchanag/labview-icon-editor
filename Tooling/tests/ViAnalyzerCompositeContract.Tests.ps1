#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'VI Analyzer composite contract' {
    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $actionPath = Join-Path $repoRoot '.github/actions/vi-analyzer-ci/action.yml'
        if (-not (Test-Path -LiteralPath $actionPath -PathType Leaf)) {
            throw "Composite action not found: $actionPath"
        }

        $script:content = Get-Content -LiteralPath $actionPath -Raw
    }

    It 'defines required inputs and outputs for VI Analyzer runtime contract' {
        foreach ($token in @(
            'container_tag:',
            'image_repository:',
            'tasks_path:',
            'labview_year:',
            'reports_root:',
            'logs_root:',
            'status_path:'
        )) {
            $script:content | Should -Match ([regex]::Escape($token))
        }

        foreach ($outputToken in @('status:', 'container_image:', 'status_path:', 'reports_root:', 'logs_root:')) {
            $script:content | Should -Match ([regex]::Escape($outputToken))
        }
    }

    It 'pulls container image and runs Linux VI Analyzer worker with deterministic paths' {
        $script:content | Should -Match 'docker pull'
        $script:content | Should -Match 'run-vi-analyzer-linux\.sh'
        $script:content | Should -Match 'LVIE_VI_ANALYZER_TASKS_PATH'
        $script:content | Should -Match 'source-sync-manifest-vi-analyzer-linux\.json'
    }

    It 'includes ownership normalization and deterministic failure path' {
        $script:content | Should -Match 'sudo chown -R'
        $script:content | Should -Match 'if \(\$status -eq ''fail''\)'
        $script:content | Should -Match 'throw "VI Analyzer composite gate failed'
    }
}
