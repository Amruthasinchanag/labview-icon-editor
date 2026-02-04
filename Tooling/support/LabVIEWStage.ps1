#Requires -Version 7.0
<#
.SYNOPSIS
    Shared helpers for LabVIEW stage execution.
#>

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param(
        [string]$PathOverride
    )

    if (-not [string]::IsNullOrWhiteSpace($PathOverride)) {
        if (-not (Test-Path -Path $PathOverride)) {
            throw "RepoRoot does not exist: $PathOverride"
        }
        return (Resolve-Path -Path $PathOverride).Path
    }

    return (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Resolve-LabVIEWVersion {
    param(
        [string]$VersionInput,
        [string]$RepoRoot
    )

    $resolvedVersion = $VersionInput
    $helper = Join-Path -Path $RepoRoot -ChildPath 'Tooling\support\LabVIEWVersion.ps1'
    if (Test-Path -Path $helper) {
        . $helper
        $info = Get-LabVIEWVersionInfo -VersionInput $VersionInput -RepoRoot $RepoRoot
        if ($info -and $info.Year) {
            $resolvedVersion = $info.Year
        }
    }
    if ([string]::IsNullOrWhiteSpace($resolvedVersion)) {
        $resolvedVersion = '2021'
    }
    return $resolvedVersion
}

function Get-BitnessList {
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

function Resolve-BitnessList {
    param(
        [string[]]$Bitnesses,
        [string]$FallbackInput
    )

    if ($Bitnesses -and $Bitnesses.Count -gt 0) {
        return @($Bitnesses | Select-Object -Unique)
    }

    return Get-BitnessList -BitnessInput $FallbackInput
}

function Get-LabVIEWInstallRoot {
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

function Invoke-LabVIEWScript {
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

function Invoke-LabVIEWClose {
    param(
        [string]$RepoRoot,
        [string]$LabVIEWVersion,
        [string]$Bitness
    )

    $closeScript = Join-Path -Path $RepoRoot -ChildPath '.github\actions\close-labview\Close_LabVIEW.ps1'
    if (-not (Test-Path -Path $closeScript)) {
        throw "Close_LabVIEW.ps1 not found at $closeScript"
    }

    return Invoke-LabVIEWScript -ScriptPath $closeScript -Arguments @(
        '-MinimumSupportedLVVersion', $LabVIEWVersion,
        '-SupportedBitness', $Bitness
    )
}

function Invoke-DevModeNoLabVIEW {
    param(
        [string]$RepoRoot,
        [string]$LabVIEWVersion,
        [string]$Bitness,
        [ValidateSet('enable', 'disable')]
        [string]$Mode
    )

    $scriptPath = if ($Mode -eq 'enable') {
        Join-Path $RepoRoot 'Tooling\Set-DevelopmentMode-NoLabVIEW.ps1'
    } else {
        Join-Path $RepoRoot 'Tooling\Revert-DevelopmentMode-NoLabVIEW.ps1'
    }

    if (-not (Test-Path -Path $scriptPath)) {
        throw "Dev mode script not found at $scriptPath"
    }

    return Invoke-LabVIEWScript -ScriptPath $scriptPath -Arguments @(
        '-MinimumSupportedLVVersion', $LabVIEWVersion,
        '-SupportedBitness', $Bitness,
        '-RepoRoot', $RepoRoot
    )
}

function New-LabVIEWStageContext {
    param(
        [string]$StageName,
        [string]$RepoRoot,
        [string]$LabVIEWVersion,
        [string]$Bitness,
        [int]$ConnectTimeoutMs
    )

    return [pscustomobject]@{
        StageName        = $StageName
        RepoRoot         = $RepoRoot
        LabVIEWVersion   = $LabVIEWVersion
        Bitness          = $Bitness
        ConnectTimeoutMs = $ConnectTimeoutMs
    }
}

function Invoke-LabVIEWStage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StageName,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$LabVIEWVersion,

        [string[]]$Bitnesses,

        [int]$ConnectTimeoutMs = 120000,

        [switch]$DevModeNoLabVIEW,

        [switch]$CloseBetweenStages = $true,

        [switch]$SkipOnBaselineFailure = $true,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    $resolvedRepoRoot = Resolve-RepoRoot -PathOverride $RepoRoot
    $resolvedVersion = Resolve-LabVIEWVersion -VersionInput $LabVIEWVersion -RepoRoot $resolvedRepoRoot
    $bitnessList = Resolve-BitnessList -Bitnesses $Bitnesses -FallbackInput $env:LABVIEW_BITNESS

    $results = @()
    foreach ($bitness in $bitnessList) {
        if (-not (Get-LabVIEWInstallRoot -Version $resolvedVersion -Bitness $bitness)) {
            $results += [pscustomobject]@{
                StageName  = $StageName
                Bitness    = $bitness
                Succeeded  = $false
                Skipped    = $true
                SkipReason = "LabVIEW $resolvedVersion ($bitness-bit) install not found."
                ExitCode   = $null
                Error      = $null
            }
            continue
        }

        if ($CloseBetweenStages) {
            $null = Invoke-LabVIEWClose -RepoRoot $resolvedRepoRoot -LabVIEWVersion $resolvedVersion -Bitness $bitness
        }

        if ($DevModeNoLabVIEW) {
            $baseline = Invoke-DevModeNoLabVIEW -RepoRoot $resolvedRepoRoot -LabVIEWVersion $resolvedVersion -Bitness $bitness -Mode 'disable'
            if ($baseline.ExitCode -ne 0) {
                if ($SkipOnBaselineFailure) {
                    $results += [pscustomobject]@{
                        StageName  = $StageName
                        Bitness    = $bitness
                        Succeeded  = $false
                        Skipped    = $true
                        SkipReason = "Baseline dev mode revert failed with exit code $($baseline.ExitCode)."
                        ExitCode   = $baseline.ExitCode
                        Error      = $null
                    }
                    if ($CloseBetweenStages) {
                        $null = Invoke-LabVIEWClose -RepoRoot $resolvedRepoRoot -LabVIEWVersion $resolvedVersion -Bitness $bitness
                    }
                    continue
                }
                throw "Baseline dev mode revert failed with exit code $($baseline.ExitCode)."
            }
        }

        $exitCode = $null
        $errorMessage = $null
        $devModeEnabled = $false
        try {
            if ($DevModeNoLabVIEW) {
                $enable = Invoke-DevModeNoLabVIEW -RepoRoot $resolvedRepoRoot -LabVIEWVersion $resolvedVersion -Bitness $bitness -Mode 'enable'
                if ($enable.ExitCode -ne 0) {
                    throw "Dev mode enable failed with exit code $($enable.ExitCode)."
                }
                $devModeEnabled = $true
            }

            $context = New-LabVIEWStageContext -StageName $StageName -RepoRoot $resolvedRepoRoot -LabVIEWVersion $resolvedVersion -Bitness $bitness -ConnectTimeoutMs $ConnectTimeoutMs
            $actionResult = & $Action $context

            if ($actionResult -is [int]) {
                $exitCode = $actionResult
            } elseif ($actionResult -and $actionResult.ExitCode -ne $null) {
                $exitCode = $actionResult.ExitCode
            } elseif ($LASTEXITCODE -ne $null) {
                $exitCode = $LASTEXITCODE
            } else {
                $exitCode = 0
            }

            if ($exitCode -ne 0) {
                throw "Stage '$StageName' failed with exit code $exitCode."
            }

            $results += [pscustomobject]@{
                StageName  = $StageName
                Bitness    = $bitness
                Succeeded  = $true
                Skipped    = $false
                SkipReason = $null
                ExitCode   = $exitCode
                Error      = $null
            }
        } catch {
            $errorMessage = $_.Exception.Message
            $results += [pscustomobject]@{
                StageName  = $StageName
                Bitness    = $bitness
                Succeeded  = $false
                Skipped    = $false
                SkipReason = $null
                ExitCode   = $exitCode
                Error      = $errorMessage
            }
        } finally {
            if ($devModeEnabled) {
                $null = Invoke-DevModeNoLabVIEW -RepoRoot $resolvedRepoRoot -LabVIEWVersion $resolvedVersion -Bitness $bitness -Mode 'disable'
            }
            if ($CloseBetweenStages) {
                $null = Invoke-LabVIEWClose -RepoRoot $resolvedRepoRoot -LabVIEWVersion $resolvedVersion -Bitness $bitness
            }
        }
    }

    return $results
}
