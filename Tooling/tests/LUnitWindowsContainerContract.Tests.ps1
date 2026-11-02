#Requires -Version 7.0
#Requires -Modules Pester

Describe 'Windows LUnit container contract' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:workflow = Get-Content (Join-Path $repoRoot '.github\workflows\lunit-windows-container-tests.yml') -Raw
        $match = [regex]::Match($script:workflow, '(?ms)      - name: Validate JUnit report and test discovery\s+run: \|\r?\n(?<code>.*?)(?=      - name:)')
        if (-not $match.Success) { throw 'JUnit validation step not found.' }
        $script:validate = [scriptblock]::Create(($match.Groups['code'].Value -replace '(?m)^          ', ''))
        $script:oldWorkspace = $env:GITHUB_WORKSPACE
        $script:oldSummary = $env:GITHUB_STEP_SUMMARY
        $env:GITHUB_WORKSPACE = $TestDrive
        $env:GITHUB_STEP_SUMMARY = Join-Path $TestDrive 'summary.txt'
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'lunit-results') -Force | Out-Null
        $script:reportPath = Join-Path $TestDrive 'lunit-results\lunit.xml'
    }

    BeforeEach {
        $cases = (1..10 | ForEach-Object { "<testcase name='test$_'/>" }) -join ''
        "<testsuites><testsuite tests='10' failures='0'>$cases</testsuite></testsuites>" |
            Set-Content -LiteralPath $script:reportPath
    }

    AfterAll {
        $env:GITHUB_WORKSPACE = $script:oldWorkspace
        $env:GITHUB_STEP_SUMMARY = $script:oldSummary
    }

    It 'uses a secret-free Windows container and native LUnit CLI' {
        $script:workflow | Should -Match 'runs-on: windows-2022'
        $script:workflow | Should -Match 'nationalinstruments/labview:2026q1-windows'
        $script:workflow | Should -Not -Match 'secrets[.:]'
        $script:workflow | Should -Match '-Stage Setup'
        $script:workflow | Should -Match 'docker restart'
        $script:workflow | Should -Match '-Stage Test'
        $helper = Get-Content (Join-Path $repoRoot 'Tooling\Run-LUnitWindowsContainer.ps1') -Raw
        $helper | Should -Match "VIPM_COMMUNITY_EDITION = '1'"
        $helper | Should -Match 'vipm-26\.3\.4025-windows-setup\.exe'
        $helper | Should -Not -Match 'vipm-setup-latest-preview'
        $helper | Should -Match "safe\.directory '\*'"
        $helper | Should -Match "Set-Location 'C:\\workspace'"
        $helper | Should -Match 'Initialize-VipmDesktopSettings -Vipm \$vipm'
        $helper | Should -Match 'Set-VipmFirstLaunchDone'
        $helper | Should -Match "VIPM_DESKTOP_LIVELINESS_TIMEOUT = '900'"
        $helper | Should -Match 'C:\\ProgramData\\JKI\\VIPM\\Settings\.ini'
        $helper | Should -Not -Match 'vipm activate|\$vipm activate'
        $helper | Should -Match 'install -y astemes_lib_lunit astemes_lib_lunit_cli'
        $helper | Should -Match 'Start-TestLabVIEW -Project \$project'
        $helper | Should -Match '-OperationName LUnit'
        $helper | Should -Match '-LogToConsole TRUE -Headless'
        $helper | Should -Not -Match 'g-cli'
    }

    It 'accepts ten passing tests' {
        { & $script:validate } | Should -Not -Throw
    }

    It 'rejects fewer than ten executed tests' {
        (Get-Content $script:reportPath -Raw).Replace("<testcase name='test10'/>", '') |
            Set-Content $script:reportPath
        { & $script:validate } | Should -Throw '*expected at least 10*'
    }

    It 'does not count skipped tests as executed' {
        (Get-Content $script:reportPath -Raw).Replace("<testcase name='test10'/>", "<testcase name='test10'><skipped/></testcase>") |
            Set-Content $script:reportPath
        { & $script:validate } | Should -Throw '*expected at least 10*'
    }

    It 'rejects <Element> elements' -ForEach @(@{ Element = 'failure' }, @{ Element = 'error' }) {
        (Get-Content $script:reportPath -Raw).Replace("<testcase name='test10'/>", "<testcase name='test10'><$Element/></testcase>") |
            Set-Content $script:reportPath
        { & $script:validate } | Should -Throw '*test failures or errors*'
    }

    It 'rejects nonzero suite failure counts' {
        (Get-Content $script:reportPath -Raw).Replace("failures='0'", "failures='1'") |
            Set-Content $script:reportPath
        { & $script:validate } | Should -Throw '*failures count*'
    }

    It 'rejects a missing report' {
        Remove-Item -LiteralPath $script:reportPath
        { & $script:validate } | Should -Throw
    }

    It 'rejects invalid XML and DTDs' -ForEach @(
        @{ Xml = '<testsuites>' },
        @{ Xml = '<!DOCTYPE testsuites [<!ENTITY x "test">]><testsuites/>' }
    ) {
        $Xml | Set-Content $script:reportPath
        { & $script:validate } | Should -Throw
    }
}
