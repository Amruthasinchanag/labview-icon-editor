$ErrorActionPreference = 'Stop'

Describe 'Missing-in-project (dev mode, no LabVIEW) integration' {
    BeforeAll {
        $script:skipAll = $false
        $script:skipReason = ''
        $script:labviewVersion = $null
        $script:labviewBitness = if ([string]::IsNullOrWhiteSpace($env:LABVIEW_BITNESS)) { '64' } else { $env:LABVIEW_BITNESS }
        $script:bitnessesToTest = @()
        $script:projectFile = $null
        $script:runDevModeTests = $false

        if (-not [string]::IsNullOrWhiteSpace($env:RUN_DEV_MODE_TESTS)) {
            $flag = $env:RUN_DEV_MODE_TESTS.Trim().ToLowerInvariant()
            $script:runDevModeTests = @('1', 'true', 'yes', 'y') -contains $flag
        }

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
            $regPaths = @()
            if ($Bitness -eq '32') {
                $candidates += "C:\Program Files (x86)\National Instruments\LabVIEW $Version"
                $regPaths += "HKLM:\SOFTWARE\WOW6432Node\National Instruments\LabVIEW $Version"
            } else {
                $candidates += "C:\Program Files\National Instruments\LabVIEW $Version"
                $regPaths += "HKLM:\SOFTWARE\National Instruments\LabVIEW $Version"
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

        function script:Get-BitnessList {
            param(
                [string]$BitnessInput
            )

            if ([string]::IsNullOrWhiteSpace($BitnessInput)) {
                return @('64')
            }

            $normalized = $BitnessInput.Trim().ToLowerInvariant()
            if (@('both', 'all', 'auto') -contains $normalized) {
                return @('64', '32')
            }

            $parts = $normalized -split '[,; ]+' | Where-Object { $_ }
            $bitnesses = foreach ($part in $parts) {
                switch ($part) {
                    '32' { '32' }
                    '64' { '64' }
                }
            }

            $bitnesses = $bitnesses | Where-Object { $_ } | Select-Object -Unique
            if (-not $bitnesses) {
                return @('64')
            }

            return @($bitnesses)
        }

        function script:Invoke-Runner {
            param(
                [string]$ScriptPath,
                [string[]]$Arguments
            )

            $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
            & $pwsh -NoProfile -File $ScriptPath @Arguments | Out-Host
            return $LASTEXITCODE
        }

        $script:repoRoot = Get-RepoRoot
        $script:setScript = Join-Path $script:repoRoot 'Tooling\Set-DevelopmentMode-NoLabVIEW.ps1'
        $script:revertScript = Join-Path $script:repoRoot 'Tooling\Revert-DevelopmentMode-NoLabVIEW.ps1'
        $script:missingScript = Join-Path $script:repoRoot '.github\actions\missing-in-project\Invoke-MissingInProjectCLI.ps1'
        $script:versionHelper = Join-Path $script:repoRoot 'Tooling\support\LabVIEWVersion.ps1'

        if (Test-Path -Path $script:versionHelper) {
            . $script:versionHelper
            $versionInput = if ([string]::IsNullOrWhiteSpace($env:LABVIEW_VERSION)) { '' } else { $env:LABVIEW_VERSION }
            $versionInfo = Get-LabVIEWVersionInfo -VersionInput $versionInput -RepoRoot $script:repoRoot
            $script:labviewVersion = $versionInfo.Year
        }

        if ([string]::IsNullOrWhiteSpace($script:labviewVersion)) {
            $script:labviewVersion = if ([string]::IsNullOrWhiteSpace($env:LABVIEW_VERSION)) { '2021' } else { $env:LABVIEW_VERSION }
        }

        if (-not $script:runDevModeTests) {
            $script:skipAll = $true
            $script:skipReason = 'Set RUN_DEV_MODE_TESTS=1 to enable this integration test.'
            return
        }

        if (-not (Test-Path -Path $script:setScript)) {
            $script:skipAll = $true
            $script:skipReason = "Set-DevelopmentMode-NoLabVIEW.ps1 not found at $script:setScript"
            return
        }

        if (-not (Test-Path -Path $script:revertScript)) {
            $script:skipAll = $true
            $script:skipReason = "Revert-DevelopmentMode-NoLabVIEW.ps1 not found at $script:revertScript"
            return
        }

        if (-not (Test-Path -Path $script:missingScript)) {
            $script:skipAll = $true
            $script:skipReason = "Invoke-MissingInProjectCLI.ps1 not found at $script:missingScript"
            return
        }

        if (-not (Get-Command g-cli -ErrorAction SilentlyContinue)) {
            $script:skipAll = $true
            $script:skipReason = 'g-cli not found in PATH.'
            return
        }

        $script:projectFile = Get-ChildItem -Path $script:repoRoot -Filter *.lvproj | Select-Object -First 1 -ExpandProperty FullName
        if (-not $script:projectFile) {
            $script:skipAll = $true
            $script:skipReason = 'No .lvproj file found in repo root.'
            return
        }

        $bitnessCandidates = Get-BitnessList -BitnessInput $script:labviewBitness
        foreach ($bitness in $bitnessCandidates) {
            if (-not (Get-LabVIEWInstallRoot -Version $script:labviewVersion -Bitness $bitness)) {
                continue
            }

            $revertArgs = @(
                '-MinimumSupportedLVVersion', $script:labviewVersion,
                '-SupportedBitness', $bitness,
                '-RepoRoot', $script:repoRoot
            )

            $exitCode = Invoke-Runner -ScriptPath $script:revertScript -Arguments $revertArgs
            if ($exitCode -eq 0) {
                $script:bitnessesToTest += $bitness
                continue
            }

            Write-Warning ("Skipping {0}-bit missing-in-project; baseline revert failed with exit code {1}." -f $bitness, $exitCode)
        }

        if (-not $script:bitnessesToTest -or $script:bitnessesToTest.Count -eq 0) {
            $script:skipAll = $true
            $script:skipReason = "No LabVIEW $script:labviewVersion installs available after baseline revert."
            return
        }
    }

    It 'runs missing-in-project using no-LabVIEW dev mode' {
        if ($script:skipAll) {
            Set-ItResult -Skipped -Because $script:skipReason
            return
        }

        foreach ($bitness in $script:bitnessesToTest) {
            $setArgs = @(
                '-MinimumSupportedLVVersion', $script:labviewVersion,
                '-SupportedBitness', $bitness,
                '-RepoRoot', $script:repoRoot
            )

            $revertArgs = @(
                '-MinimumSupportedLVVersion', $script:labviewVersion,
                '-SupportedBitness', $bitness,
                '-RepoRoot', $script:repoRoot
            )

            $missingArgs = @(
                '-LVVersion', $script:labviewVersion,
                '-Arch', $bitness,
                '-ProjectFile', $script:projectFile
            )

            try {
                $exitCode = Invoke-Runner -ScriptPath $script:revertScript -Arguments $revertArgs
                $exitCode | Should -Be 0

                $exitCode = Invoke-Runner -ScriptPath $script:setScript -Arguments $setArgs
                $exitCode | Should -Be 0

                $exitCode = Invoke-Runner -ScriptPath $script:missingScript -Arguments $missingArgs
                $exitCode | Should -Be 0
            } finally {
                $null = Invoke-Runner -ScriptPath $script:revertScript -Arguments $revertArgs
            }
        }
    }
}
