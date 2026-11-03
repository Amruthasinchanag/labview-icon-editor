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

    Describe 'LUnit dependency installation recovery' {
        BeforeAll {
            $path = Join-Path $PSScriptRoot '..\Run-LUnitWindowsContainer.ps1'
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Resolve-Path $path).Path, [ref]$tokens, [ref]$errors)
            if ($errors.Count) { throw ($errors | Out-String) }
            $function = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Install-LUnitPackages'
            }, $true)
            . ([scriptblock]::Create($function.Extent.Text))
            $refresh = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Refresh-VipmPackages'
            }, $true)
            . ([scriptblock]::Create($refresh.Extent.Text))
            function Invoke-TestVipm {}
            function Stop-SetupProcesses {}
            function Start-TestLabVIEW {}
            function Initialize-VipmDesktopSettings {}
            function Get-LUnitPackageFiles {}
        }

        BeforeEach {
            $script:codes = [System.Collections.Generic.Queue[int]]::new()
            Mock Invoke-TestVipm { $global:LASTEXITCODE = $script:codes.Dequeue() }
            Mock Stop-SetupProcesses {}
            Mock Start-TestLabVIEW {}
            Mock Initialize-VipmDesktopSettings {}
            Mock Start-Sleep {}
            Mock Get-LUnitPackageFiles { @('C:\packages\lunit.vip', 'C:\packages\cli.vip') }
        }

        It 'does not restart after a successful batch install' {
            $script:codes.Enqueue(0)
            Install-LUnitPackages -Vipm Invoke-TestVipm
            Should -Invoke Invoke-TestVipm -Times 1 -Exactly
            Should -Invoke Stop-SetupProcesses -Times 0 -Exactly
        }

        It 'restarts the stack once after an engine timeout' {
            $script:codes.Enqueue(124)
            $script:codes.Enqueue(0)
            Install-LUnitPackages -Vipm Invoke-TestVipm
            Should -Invoke Invoke-TestVipm -Times 2 -Exactly
            Should -Invoke Stop-SetupProcesses -Times 1 -Exactly
            Should -Invoke Start-TestLabVIEW -Times 1 -Exactly
            Should -Invoke Initialize-VipmDesktopSettings -Times 1 -Exactly
        }

        It 'fails after two timeouts without trying packages individually' {
            $script:codes.Enqueue(124)
            $script:codes.Enqueue(124)
            { Install-LUnitPackages -Vipm Invoke-TestVipm } | Should -Throw '*attempt 2/2*'
            Should -Invoke Invoke-TestVipm -Times 2 -Exactly
            Should -Invoke Stop-SetupProcesses -Times 1 -Exactly
        }

        It 'surfaces non-timeout failures without restarting' {
            $script:codes.Enqueue(8)
            { Install-LUnitPackages -Vipm Invoke-TestVipm } | Should -Throw '*failed: 8*'
            Should -Invoke Stop-SetupProcesses -Times 0 -Exactly
        }

        It 'uses public files only for a resolution failure' {
            foreach ($code in @(3, 0)) { $script:codes.Enqueue($code) }
            Install-LUnitPackages -Vipm Invoke-TestVipm
            Should -Invoke Invoke-TestVipm -Times 2 -Exactly
            Should -Invoke Get-LUnitPackageFiles -Times 1 -Exactly
            Should -Invoke Stop-SetupProcesses -Times 0 -Exactly
        }

        It 'does not accept a failed local file installation as success' {
            foreach ($code in @(3, 3)) { $script:codes.Enqueue($code) }
            { Install-LUnitPackages -Vipm Invoke-TestVipm } | Should -Throw '*Required LUnit installation failed: 3*'
            Should -Invoke Invoke-TestVipm -Times 2 -Exactly
        }

        It 'reuses local files after a timeout without downloading again' {
            foreach ($code in @(3, 124, 0)) { $script:codes.Enqueue($code) }
            Install-LUnitPackages -Vipm Invoke-TestVipm
            Should -Invoke Invoke-TestVipm -Times 3 -Exactly
            Should -Invoke Get-LUnitPackageFiles -Times 1 -Exactly
            Should -Invoke Stop-SetupProcesses -Times 1 -Exactly
        }

        It 'surfaces download failures before attempting a local install' {
            $script:codes.Enqueue(3)
            Mock Get-LUnitPackageFiles { throw 'Publisher checksum mismatch' }
            { Install-LUnitPackages -Vipm Invoke-TestVipm } | Should -Throw '*checksum mismatch*'
            Should -Invoke Invoke-TestVipm -Times 1 -Exactly
        }

        It 'restarts once after a refresh timeout' {
            foreach ($code in @(124, 0)) { $script:codes.Enqueue($code) }
            Refresh-VipmPackages -Vipm Invoke-TestVipm
            Should -Invoke Invoke-TestVipm -Times 2 -Exactly
            Should -Invoke Stop-SetupProcesses -Times 1 -Exactly
        }

        It 'fails after two refresh timeouts' {
            foreach ($code in @(124, 124)) { $script:codes.Enqueue($code) }
            { Refresh-VipmPackages -Vipm Invoke-TestVipm } | Should -Throw '*attempt 2/2*'
            Should -Invoke Invoke-TestVipm -Times 2 -Exactly
            Should -Invoke Stop-SetupProcesses -Times 1 -Exactly
        }
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

    It 'builds and reuses required secret-free Windows dependencies and native LUnit CLI' {
        $script:workflow | Should -Match 'runs-on: windows-2022'
        $dockerfile = Get-Content (Join-Path $repoRoot 'Tooling\containers\lunit-windows.Dockerfile') -Raw
        $dockerfile | Should -Match 'FROM nationalinstruments/labview:2026q1-windows'
        $dockerfile | Should -Match '-Stage Setup -PublicRepositoryUrl'
        $dockerfile | Should -Match 'dependency-manifest.json'
        $dockerfile | Should -Not -Match 'VIPM_SERIAL_NUMBER|activate'
        $script:workflow | Should -Match 'Get-FileHash'
        $script:workflow | Should -Match 'Build-LUnitWindowsImage.ps1'
        $script:workflow | Should -Match 'docker push'
        $script:workflow | Should -Match "github.event_name != 'pull_request'"
        $script:workflow | Should -Not -Match 'secrets\.VIPM_|-Stage Setup'
        $script:workflow | Should -Match '-Stage Test'
        $helper = Get-Content (Join-Path $repoRoot 'Tooling\Run-LUnitWindowsContainer.ps1') -Raw
        $helper | Should -Match '\$activatePro = -not \[string\]::IsNullOrWhiteSpace\(\$env:VIPM_SERIAL_NUMBER\)'
        $helper | Should -Match "(?s)if \(-not \`$activatePro\) \{\s*\`$env:VIPM_COMMUNITY_EDITION = '1'"
        $helper | Should -Match '(?s)if \(\$activatePro\) \{.*?& \$vipm activate --serial-number \$env:VIPM_SERIAL_NUMBER'
        $helper | Should -Match 'Save-VipmSettingsCopy'
        $helper | Should -Not -Match "Copy-Item[^\r\n]*vipm-Settings\.ini" -Because 'the uploaded settings copy must go through redaction'
        $helper | Should -Match 'vipm-26\.3\.3954-windows-setup\.exe'
        $helper | Should -Not -Match 'vipm-setup-latest-preview'
        $helper | Should -Match 'safe\.directory C:/workspace'
        $helper | Should -Match "Set-Location 'C:\\workspace'"
        $helper | Should -Match 'Initialize-VipmDesktopSettings -Vipm \$vipm'
        $helper | Should -Match 'Set-VipmFirstLaunchDone'
        $helper | Should -Match "VIPM_DESKTOP_LIVELINESS_TIMEOUT = '120'"
        $helper | Should -Match 'Remove-Item Env:LV_RTE_HEADLESS'
        $helper | Should -Match 'attempt -le 2'
        $helper | Should -Match 'Stop-SetupProcesses'
        $helper | Should -Match 'Refresh-VipmPackages -Vipm \$vipm'
        $helper | Should -Not -Match 'Tested 0="TRUE"'
        $helper | Should -Match 'C:\\ProgramData\\JKI\\VIPM\\Settings\.ini'
        $helper | Should -Match "targets = @\('astemes_lib_lunit', 'astemes_lib_lunit_cli'\)"
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
