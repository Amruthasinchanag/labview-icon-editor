$ErrorActionPreference = 'Stop'

Describe 'Dev Mode Diagnostics Helpers' {
    BeforeAll {
        $script:repoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')
        $script:diagnosticsScript = Join-Path $script:repoRoot 'Tooling\DevModeDiagnostics.ps1'
        if (-not (Test-Path -Path $script:diagnosticsScript)) {
            throw "Diagnostics helper not found at $script:diagnosticsScript"
        }
        . $script:diagnosticsScript
    }

    It 'extracts the last U8 bitmask from output lines' {
        $output = @(
            'Executing: g-cli ...',
            '300',
            ' 42 ',
            'Preparing...',
            '255'
        )

        $result = Get-DevModeDiagnosticsBitmaskFromOutput -Output $output
        $result | Should -Be 255
    }

    It 'extracts the diagnostics bitmask from the error source line' {
        $output = @(
            '18:49:31.055 [DEBUG] Process launched with PID 41280',
            'Error -593450 occurred at 189',
            'Other output'
        )

        $result = Get-DevModeDiagnosticsBitmaskFromOutput -Output $output
        $result | Should -Be 189
    }

    It 'returns null when no U8 is present' {
        $output = @(
            'LabVIEW 2021',
            '300',
            '256',
            'Not a number'
        )

        $result = Get-DevModeDiagnosticsBitmaskFromOutput -Output $output
        $result | Should -BeNullOrEmpty
    }

    It 'decodes missing paths and guard bit' {
        $info = Get-DevModeDiagnosticsInfo -Bitmask 197

        $info.GuardBitSet | Should -BeTrue
        $info.Binary | Should -Be '11000101'
        $info.SetBits | Should -Be @(0, 2, 6, 7)
        $info.MissingPaths | Should -Be @(
            'lv_icon.lvlibp',
            'lv_icon.vi',
            'lv_icon.vit',
            'SAMPLE_lv_icon.vi'
        )
    }

    It 'formats a summary string' {
        $info = Get-DevModeDiagnosticsInfo -Bitmask 5
        $summary = Format-DevModeDiagnosticsSummary -Diagnostics $info

        $summary | Should -Match 'bitmask=5'
        $summary | Should -Match 'expected_missing=lv_icon\.lvlibp'
        $summary | Should -Match 'guard_bit_set=False'
    }
}
