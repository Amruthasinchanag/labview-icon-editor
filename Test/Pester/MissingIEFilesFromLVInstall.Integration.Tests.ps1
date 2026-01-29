$ErrorActionPreference = 'Stop'

Describe 'Verify IE Paths integration' {
    BeforeAll {
        $script:skipAll = $false
        $script:skipReason = ''
        $script:labviewVersion = if ([string]::IsNullOrWhiteSpace($env:LABVIEW_VERSION)) { '2025' } else { $env:LABVIEW_VERSION }
        $script:labviewBitness = if ([string]::IsNullOrWhiteSpace($env:LABVIEW_BITNESS)) { '64' } else { $env:LABVIEW_BITNESS }
        $script:connectTimeoutMs = if ([string]::IsNullOrWhiteSpace($env:LABVIEW_CONNECT_TIMEOUT_MS)) { '120000' } else { $env:LABVIEW_CONNECT_TIMEOUT_MS }
        $script:processTimeoutMs = if ([string]::IsNullOrWhiteSpace($env:LABVIEW_PROCESS_TIMEOUT_MS)) { '300000' } else { $env:LABVIEW_PROCESS_TIMEOUT_MS }

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

        function script:Invoke-Runner {
            param(
                [string]$ScriptPath,
                [string[]]$Arguments
            )

            $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
            $rawOutput = & $pwsh -NoProfile -File $ScriptPath @Arguments 2>&1
            $exitCode = $LASTEXITCODE
            $lines = @()
            foreach ($entry in $rawOutput) {
                if ($null -ne $entry) {
                    $lines += [string]$entry
                }
            }
            $lines | Out-Host
            return [pscustomobject]@{
                ExitCode    = $exitCode
                OutputLines = $lines
            }
        }


        $script:repoRoot = Get-RepoRoot
        $script:scriptPath = Join-Path $script:repoRoot 'Tooling\Invoke-MissingIEFilesFromLVInstall.ps1'
        $script:revertScript = Join-Path $script:repoRoot '.github\actions\revert-development-mode\RevertDevelopmentMode.ps1'

        if (-not (Test-Path -Path $script:scriptPath)) {
            $script:skipAll = $true
            $script:skipReason = "Script not found at $script:scriptPath"
            return
        }

        if ($script:labviewVersion -ne '2025') {
            $script:skipAll = $true
            $script:skipReason = 'Only LabVIEW 2025 is supported by this test suite.'
            return
        }

        if ($script:labviewBitness -ne '64') {
            $script:skipAll = $true
            $script:skipReason = 'Only 64-bit LabVIEW is supported by this test suite.'
            return
        }

        if (-not (Get-Command g-cli -ErrorAction SilentlyContinue)) {
            $script:skipAll = $true
            $script:skipReason = 'g-cli not found in PATH.'
            return
        }

        if (-not (Get-LabVIEWInstallRoot -Version $script:labviewVersion -Bitness $script:labviewBitness)) {
            $script:skipAll = $true
            $script:skipReason = "LabVIEW $script:labviewVersion ($script:labviewBitness-bit) install not found."
            return
        }

        if (-not (Test-Path -Path $script:revertScript)) {
            $script:skipAll = $true
            $script:skipReason = "RevertDevelopmentMode.ps1 not found at $script:revertScript"
            return
        }

        $revertArgs = @(
            '-MinimumSupportedLVVersion', $script:labviewVersion,
            '-SupportedBitness', $script:labviewBitness,
            '-RelativePath', $script:repoRoot,
            '-ConnectTimeoutMs', $script:connectTimeoutMs,
            '-ProcessTimeoutMs', $script:processTimeoutMs
        )

        $revertResult = Invoke-Runner -ScriptPath $script:revertScript -Arguments $revertArgs
        if ($revertResult.ExitCode -ne 0) {
            $script:skipAll = $true
            $script:skipReason = 'Baseline restore failed; run RevertDevelopmentMode.ps1 and re-try.'
            return
        }
    }

    It 'runs VerifyIEPaths successfully' {
        if ($script:skipAll) {
            Set-ItResult -Skipped -Because $script:skipReason
            return
        }

        $args = @(
            '-MinimumSupportedLVVersion', $script:labviewVersion,
            '-SupportedBitness', $script:labviewBitness,
            '-ConnectTimeoutMs', $script:connectTimeoutMs,
            '-IgnoreStatusFailure'
        )

        $result = Invoke-Runner -ScriptPath $script:scriptPath -Arguments $args
        $result.ExitCode | Should -Be 0
    }
}
