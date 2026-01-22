$ErrorActionPreference = 'Stop'

Describe 'Development Mode integration (LabVIEW 2021)' {
    BeforeAll {
        $script:skipAll = $false
        $script:skipReason = ''
        $script:installRoots = @{}
        $script:bitnessesToTest = @()
        $script:labviewVersion = if ([string]::IsNullOrWhiteSpace($env:LABVIEW_VERSION)) { '2021' } else { $env:LABVIEW_VERSION }

        function script:Get-RepoRoot {
            $root = Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')
            return $root.Path
        }

        function script:Get-LabVIEWInstallRoot {
            param(
                [string]$Version,
                [string]$Bitness
            )

            $candidates = @()
            if ($Bitness -eq '32') {
                $candidates += "C:\Program Files (x86)\National Instruments\LabVIEW $Version"
                $regPaths = @("HKLM:\SOFTWARE\WOW6432Node\National Instruments\LabVIEW $Version")
            } else {
                $candidates += "C:\Program Files\National Instruments\LabVIEW $Version"
                $regPaths = @("HKLM:\SOFTWARE\National Instruments\LabVIEW $Version")
            }

            foreach ($candidate in $candidates) {
                if (Test-Path -Path $candidate) {
                    return $candidate
                }
            }

            foreach ($regPath in $regPaths) {
                try {
                    $props = Get-ItemProperty -Path $regPath -ErrorAction Stop
                    foreach ($name in @('Path', 'InstallDir', 'InstallPath')) {
                        $value = $props.$name
                        if (-not [string]::IsNullOrWhiteSpace($value) -and (Test-Path -Path $value)) {
                            return $value
                        }
                    }
                } catch {
                    continue
                }
            }

            return $null
        }

        function script:Get-LabVIEWPaths {
            param(
                [string]$InstallRoot
            )

            return @{
                IconApiFolder = Join-Path $InstallRoot 'vi.lib\LabVIEW Icon API'
                IconApiZip    = Join-Path $InstallRoot 'vi.lib\LabVIEW Icon API.zip'
                Lvlibp        = Join-Path $InstallRoot 'resource\plugins\lv_icon.lvlibp'
                Ship          = Join-Path $InstallRoot 'resource\plugins\lv_icon.ship'
            }
        }

        function script:Invoke-LabVIEWScript {
            param(
                [string]$ScriptPath,
                [string[]]$Arguments
            )

            $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
            $argList = @('-NoProfile', '-File', $ScriptPath) + $Arguments
            $process = Start-Process -FilePath $pwsh -ArgumentList $argList -NoNewWindow -Wait -PassThru
            return $process.ExitCode
        }

        function script:Get-ScriptArguments {
            param(
                [string]$LabVIEWVersion,
                [string]$RepoRoot,
                [string]$Bitness
            )

            return @(
                '-MinimumSupportedLVVersion', $LabVIEWVersion,
                '-RelativePath', $RepoRoot,
                '-SupportedBitness', $Bitness
            )
        }

        $script:repoRoot = Get-RepoRoot
        $script:actionsRoot = Join-Path $script:repoRoot '.github\actions'
        $script:setScript = Join-Path $script:actionsRoot 'set-development-mode\Set_Development_Mode.ps1'
        $script:revertScript = Join-Path $script:actionsRoot 'revert-development-mode\RevertDevelopmentMode.ps1'
        $script:diagnosticsScript = Join-Path $script:actionsRoot 'icon-editor-files-in-lv-installation\Invoke-GetPathsToIconEditorFilesInLVInstallationCLI.ps1'
        $script:validateScript = Join-Path $script:actionsRoot 'icon-editor-files-in-lv-installation\Validate-IconEditorDiagnostics.ps1'
        $script:diagnosticsRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'labview-icon-editor-diagnostics'

        if (-not (Test-Path -Path $script:diagnosticsRoot)) {
            New-Item -Path $script:diagnosticsRoot -ItemType Directory | Out-Null
        }

        function script:Get-DiagnosticsCsvPath {
            param(
                [string]$Mode,
                [string]$Bitness
            )

            $safeMode = $Mode.ToLowerInvariant()
            return (Join-Path $script:diagnosticsRoot ("icon-editor-files-{0}-{1}.csv" -f $safeMode, $Bitness))
        }

        function script:Invoke-IconEditorDiagnostics {
            param(
                [string]$Bitness,
                [string]$CsvPath
            )

            $args = @(
                '-LVVersion', $script:labviewVersion,
                '-Arch', $Bitness,
                '-RepoRoot', $script:repoRoot,
                '-CsvFileName', $CsvPath,
                '-SummaryTitle', 'Pester diagnostics'
            )

            return (Invoke-LabVIEWScript -ScriptPath $script:diagnosticsScript -Arguments $args)
        }

        function script:Invoke-IconEditorValidation {
            param(
                [string]$Mode,
                [string]$CsvPath
            )

            $args = @(
                '-Mode', $Mode,
                '-CsvPath', $CsvPath,
                '-RepoRoot', $script:repoRoot
            )

            return (Invoke-LabVIEWScript -ScriptPath $script:validateScript -Arguments $args)
        }

        if ($script:labviewVersion -ne '2021') {
            $script:skipAll = $true
            $script:skipReason = 'Only LabVIEW 2021 is supported by this test suite.'
            return
        }

        if (-not (Get-Command g-cli -ErrorAction SilentlyContinue)) {
            $script:skipAll = $true
            $script:skipReason = 'g-cli not found in PATH.'
            return
        }

        foreach ($bitness in @('32', '64')) {
            $root = Get-LabVIEWInstallRoot -Version $script:labviewVersion -Bitness $bitness
            if ($root) {
                $script:installRoots[$bitness] = $root
                $script:bitnessesToTest += $bitness
            }
        }

        if (-not $script:bitnessesToTest) {
            $script:skipAll = $true
            $script:skipReason = "LabVIEW $script:labviewVersion install not found."
            return
        }

        foreach ($bitness in $script:bitnessesToTest) {
            $args = Get-ScriptArguments -LabVIEWVersion $script:labviewVersion -RepoRoot $script:repoRoot -Bitness $bitness
            $exitCode = Invoke-LabVIEWScript -ScriptPath $script:revertScript -Arguments $args
            if ($exitCode -ne 0) {
                throw "Baseline restore failed for $bitness-bit with exit code $exitCode."
            }
        }
    }

    AfterAll {
        if (-not $script:skipAll) {
            foreach ($bitness in $script:bitnessesToTest) {
                $args = Get-ScriptArguments -LabVIEWVersion $script:labviewVersion -RepoRoot $script:repoRoot -Bitness $bitness
                $exitCode = Invoke-LabVIEWScript -ScriptPath $script:revertScript -Arguments $args
                if ($exitCode -ne 0) {
                    throw "Failed to restore LabVIEW setup for $bitness-bit; exit code $exitCode."
                }
            }
        }
    }

    It "runs Set_Development_Mode.ps1 successfully" {
        if ($script:skipAll) {
            Set-ItResult -Skipped -Because $script:skipReason
            return
        }

        foreach ($bitness in $script:bitnessesToTest) {
            $args = Get-ScriptArguments -LabVIEWVersion $script:labviewVersion -RepoRoot $script:repoRoot -Bitness $bitness
            $exitCode = Invoke-LabVIEWScript -ScriptPath $script:setScript -Arguments $args
            $exitCode | Should -Be 0
            (Get-Process -Name LabVIEW -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        }
    }

    It "applies expected PrepareIESource changes" {
        if ($script:skipAll) {
            Set-ItResult -Skipped -Because $script:skipReason
            return
        }

        foreach ($bitness in $script:bitnessesToTest) {
            $paths = Get-LabVIEWPaths -InstallRoot $script:installRoots[$bitness]
            (Test-Path -Path $paths.Ship) | Should -BeTrue
            (Test-Path -Path $paths.Lvlibp) | Should -BeFalse
            (Test-Path -Path $paths.IconApiFolder) | Should -BeFalse
            (Test-Path -Path $paths.IconApiZip) | Should -BeTrue
        }
    }

    It "validates diagnostics after enabling dev mode" {
        if ($script:skipAll) {
            Set-ItResult -Skipped -Because $script:skipReason
            return
        }

        foreach ($bitness in $script:bitnessesToTest) {
            $csvPath = Get-DiagnosticsCsvPath -Mode 'enable' -Bitness $bitness
            $exitCode = Invoke-IconEditorDiagnostics -Bitness $bitness -CsvPath $csvPath
            $exitCode | Should -Be 0
            (Test-Path -Path $csvPath) | Should -BeTrue

            $validateExit = Invoke-IconEditorValidation -Mode 'enable' -CsvPath $csvPath
            $validateExit | Should -Be 0
        }
    }

    It "runs RevertDevelopmentMode.ps1 successfully" {
        if ($script:skipAll) {
            Set-ItResult -Skipped -Because $script:skipReason
            return
        }

        foreach ($bitness in $script:bitnessesToTest) {
            $args = Get-ScriptArguments -LabVIEWVersion $script:labviewVersion -RepoRoot $script:repoRoot -Bitness $bitness
            $exitCode = Invoke-LabVIEWScript -ScriptPath $script:revertScript -Arguments $args
            $exitCode | Should -Be 0
            (Get-Process -Name LabVIEW -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        }
    }

    It "applies expected RestoreSetupLVSource changes" {
        if ($script:skipAll) {
            Set-ItResult -Skipped -Because $script:skipReason
            return
        }

        foreach ($bitness in $script:bitnessesToTest) {
            $paths = Get-LabVIEWPaths -InstallRoot $script:installRoots[$bitness]
            (Test-Path -Path $paths.Lvlibp) | Should -BeTrue
            (Test-Path -Path $paths.Ship) | Should -BeFalse
            (Test-Path -Path $paths.IconApiFolder) | Should -BeTrue
            (Test-Path -Path $paths.IconApiZip) | Should -BeFalse
        }
    }

    It "validates diagnostics after disabling dev mode" {
        if ($script:skipAll) {
            Set-ItResult -Skipped -Because $script:skipReason
            return
        }

        foreach ($bitness in $script:bitnessesToTest) {
            $csvPath = Get-DiagnosticsCsvPath -Mode 'disable' -Bitness $bitness
            $exitCode = Invoke-IconEditorDiagnostics -Bitness $bitness -CsvPath $csvPath
            $exitCode | Should -Be 0
            (Test-Path -Path $csvPath) | Should -BeTrue

            $validateExit = Invoke-IconEditorValidation -Mode 'disable' -CsvPath $csvPath
            $validateExit | Should -Be 0
        }
    }
}
