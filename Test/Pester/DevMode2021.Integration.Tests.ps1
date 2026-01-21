$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    $root = Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')
    return $root.Path
}

function Get-LabVIEWInstallRoot {
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

function Get-LabVIEWPaths {
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

function Invoke-LabVIEWScript {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments
    )

    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $argList = @('-NoProfile', '-File', $ScriptPath) + $Arguments
    $process = Start-Process -FilePath $pwsh -ArgumentList $argList -NoNewWindow -Wait -PassThru
    return $process.ExitCode
}

function Get-ScriptArguments {
    param(
        [string]$LabVIEWVersion,
        [string]$RepoRoot,
        [string[]]$Bitnesses
    )

    $args = @('-MinimumSupportedLVVersion', $LabVIEWVersion, '-RelativePath', $RepoRoot)
    foreach ($bitness in $Bitnesses) {
        $args += @('-SupportedBitness', $bitness)
    }
    return $args
}

$labviewVersion = if ([string]::IsNullOrWhiteSpace($env:LABVIEW_VERSION)) { '2021' } else { $env:LABVIEW_VERSION }
$repoRoot = Get-RepoRoot
$actionsRoot = Join-Path $repoRoot '.github\actions'
$setScript = Join-Path $actionsRoot 'set-development-mode\Set_Development_Mode.ps1'
$revertScript = Join-Path $actionsRoot 'revert-development-mode\RevertDevelopmentMode.ps1'

Describe "Development Mode integration ($labviewVersion)" {
    $script:skipAll = $false
    $script:skipReason = ''
    $script:installRoots = @{}
    $script:bitnessesToTest = @()

    BeforeAll {
        if ($labviewVersion -ne '2021') {
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
            $root = Get-LabVIEWInstallRoot -Version $labviewVersion -Bitness $bitness
            if ($root) {
                $script:installRoots[$bitness] = $root
                $script:bitnessesToTest += $bitness
            }
        }

        if (-not $script:bitnessesToTest) {
            $script:skipAll = $true
            $script:skipReason = "LabVIEW $labviewVersion install not found."
            return
        }

        $args = Get-ScriptArguments -LabVIEWVersion $labviewVersion -RepoRoot $repoRoot -Bitnesses $script:bitnessesToTest
        $exitCode = Invoke-LabVIEWScript -ScriptPath $revertScript -Arguments $args
        if ($exitCode -ne 0) {
            throw "Baseline restore failed with exit code $exitCode."
        }
    }

    AfterAll {
        if (-not $script:skipAll) {
            $args = Get-ScriptArguments -LabVIEWVersion $labviewVersion -RepoRoot $repoRoot -Bitnesses $script:bitnessesToTest
            $exitCode = Invoke-LabVIEWScript -ScriptPath $revertScript -Arguments $args
            if ($exitCode -ne 0) {
                throw "Failed to restore LabVIEW setup; exit code $exitCode."
            }
        }
    }

    It "runs Set_Development_Mode.ps1 successfully" {
        if ($script:skipAll) {
            Set-ItResult -Skipped -Because $script:skipReason
            return
        }

        $args = Get-ScriptArguments -LabVIEWVersion $labviewVersion -RepoRoot $repoRoot -Bitnesses $script:bitnessesToTest
        $exitCode = Invoke-LabVIEWScript -ScriptPath $setScript -Arguments $args
        $exitCode | Should -Be 0
        (Get-Process -Name LabVIEW -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
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

    It "runs RevertDevelopmentMode.ps1 successfully" {
        if ($script:skipAll) {
            Set-ItResult -Skipped -Because $script:skipReason
            return
        }

        $args = Get-ScriptArguments -LabVIEWVersion $labviewVersion -RepoRoot $repoRoot -Bitnesses $script:bitnessesToTest
        $exitCode = Invoke-LabVIEWScript -ScriptPath $revertScript -Arguments $args
        $exitCode | Should -Be 0
        (Get-Process -Name LabVIEW -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
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
}
