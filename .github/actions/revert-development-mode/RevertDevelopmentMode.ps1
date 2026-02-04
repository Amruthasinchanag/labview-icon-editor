<#
.SYNOPSIS
    Reverts the repository from development mode.

.DESCRIPTION
    Restores the packaged LabVIEW sources for both 32-bit and 64-bit
    environments using RestoreSetupLVSource.vi. LabVIEW is closed by the
    helper after each run so downstream steps load the changes.

.PARAMETER MinimumSupportedLVVersion
    LabVIEW version year (e.g., 2021) or numeric version (e.g., 21.0).

.PARAMETER SupportedBitness
    One or more bitness values ("32", "64") to run (default: both).

.PARAMETER RepoRoot
    Optional path to the repository root.

.PARAMETER ConnectTimeoutMs
    g-cli connect timeout in milliseconds (0 disables the timeout).

.PARAMETER ProcessTimeoutMs
    Maximum time to wait for g-cli to finish in milliseconds (0 disables the timeout).

.PARAMETER UseLabVIEW
    Use LabVIEW + g-cli to revert development mode. Defaults to using the
    no-LabVIEW path when omitted.

.EXAMPLE
    .\RevertDevelopmentMode.ps1 -MinimumSupportedLVVersion 2021
#>

param(
    [Parameter(Mandatory = $false)]
    [Alias('LabVIEWVersion')]
    [AllowNull()]
    [AllowEmptyString()]
    [string]$MinimumSupportedLVVersion = '',

    [Parameter(Mandatory = $false)]
    [ValidateSet('32', '64', IgnoreCase = $true)]
    [string[]]$SupportedBitness = @('32', '64'),

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 600000)]
    [int]$ConnectTimeoutMs = 120000,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 1200000)]
    [int]$ProcessTimeoutMs = 300000,

    [Parameter(Mandatory = $false)]
    [switch]$UseLabVIEW
)

# Determine the directory where this script is located
$ScriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
Write-Host "Script Directory: $ScriptDirectory"

$RestoreScript = Join-Path -Path $ScriptDirectory -ChildPath '..\restore-setup-lv-source\RestoreSetupLVSource.ps1'
$CloseScript = Join-Path -Path $ScriptDirectory -ChildPath '..\close-labview\Close_LabVIEW.ps1'
Write-Host "RestoreSetupLVSource script: $RestoreScript"
Write-Host "Close_LabVIEW script: $CloseScript"

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param(
        [string]$PathOverride
    )

    if ($PathOverride) {
        if (-not (Test-Path -Path $PathOverride)) {
            throw "RepoRoot does not exist: $PathOverride"
        }
        return (Resolve-Path -Path $PathOverride).Path
    }

    return (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

$resolvedRepoRoot = Resolve-RepoRoot -PathOverride $RepoRoot
$versionHelper = Join-Path $resolvedRepoRoot 'Tooling\support\LabVIEWVersion.ps1'
$labviewYear = $MinimumSupportedLVVersion
if (Test-Path -Path $versionHelper) {
    . $versionHelper
    $versionInfo = Get-LabVIEWVersionInfo -VersionInput $MinimumSupportedLVVersion -RepoRoot $resolvedRepoRoot
    $labviewYear = $versionInfo.Year
}
if ([string]::IsNullOrWhiteSpace($labviewYear)) {
    $labviewYear = '2021'
}

if (-not $UseLabVIEW) {
    $noLabviewScript = Join-Path $resolvedRepoRoot 'Tooling\Revert-DevelopmentMode-NoLabVIEW.ps1'
    if (-not (Test-Path -Path $noLabviewScript)) {
        throw "Revert-DevelopmentMode-NoLabVIEW.ps1 not found at $noLabviewScript"
    }

    Write-Host ("Using no-LabVIEW dev mode revert path (LV{0})..." -f $labviewYear)
    & $noLabviewScript `
        -MinimumSupportedLVVersion $labviewYear `
        -SupportedBitness $SupportedBitness `
        -RepoRoot $resolvedRepoRoot

    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
        throw "Revert-DevelopmentMode-NoLabVIEW.ps1 failed with exit code $LASTEXITCODE."
    }

    return
}

function Write-CloseMetricsHint {
    param(
        [string]$Bitness,
        [string]$Context,
        [string]$ExpectedVersion
    )

    $metricsPath = $env:LABVIEW_CLOSE_METRICS_PATH
    if ([string]::IsNullOrWhiteSpace($metricsPath)) {
        return
    }

    if (Test-Path -Path $metricsPath) {
        $lines = @()
        try {
            $lines = Get-Content -Path $metricsPath -Tail 50 | Where-Object { $_ -and $_ -notmatch '^timestamp,' }
        } catch {
            Write-Warning ("Failed to read close metrics at {0}: {1}" -f $metricsPath, $_.Exception.Message)
            return
        }

        if (-not $lines -or $lines.Count -eq 0) {
            Write-Host ("Close metrics file is empty: {0}" -f $metricsPath)
            return
        }

        $entries = foreach ($line in $lines) {
            $parts = $line -split ',', 6
            if ($parts.Length -ge 6) {
                [pscustomobject]@{
                    Line      = $line
                    Timestamp = $parts[0]
                    Version   = $parts[1]
                    Bitness   = $parts[2]
                    HadProc   = $parts[3]
                    Outcome   = $parts[4]
                    Duration  = $parts[5]
                }
            }
        }

        $match = $entries | Where-Object { $_.Version -eq $ExpectedVersion -and $_.Bitness -eq $Bitness } | Select-Object -Last 1
        if ($match) {
            Write-Host ("Close metrics ({0}) {1}-bit: version={2} outcome={3} duration_s={4} had_process={5} timestamp={6}" -f `
                    $Context, $Bitness, $match.Version, $match.Outcome, $match.Duration, $match.HadProc, $match.Timestamp)
            return
        }

        $lastEntry = $entries | Select-Object -Last 1
        if ($lastEntry) {
            Write-Warning ("Close metrics ({0}) {1}-bit: no matching entry for version {2}; last entry: {3}" -f `
                    $Context, $Bitness, $ExpectedVersion, $lastEntry.Line)
        } else {
            Write-Warning ("Close metrics ({0}) {1}-bit: no parsable entries found in {2}" -f $Context, $Bitness, $metricsPath)
        }

        return
    }

    Write-Host ("Close metrics path set but file not found: {0}" -f $metricsPath)
}

function Invoke-RestoreLabviewSource {
    param(
        [string]$Bitness
    )

    Write-Host "Restoring LabVIEW sources for $Bitness-bit."
    # RestoreSetupLVSource.ps1 closes LabVIEW after the VI runs.
    $scriptArgs = @{
        MinimumSupportedLVVersion = $labviewYear
        SupportedBitness          = $Bitness
        ConnectTimeoutMs          = $ConnectTimeoutMs
        ProcessTimeoutMs          = $ProcessTimeoutMs
    }

    if ($resolvedRepoRoot) {
        $scriptArgs.RepoRoot = $resolvedRepoRoot
    }

    & $RestoreScript @scriptArgs

    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
        throw "RestoreSetupLVSource.ps1 failed for $Bitness-bit with exit code $LASTEXITCODE."
    }

    Write-CloseMetricsHint -Bitness $Bitness -Context 'revert' -ExpectedVersion $labviewYear
}

try {
    $bitnesses = $SupportedBitness | Select-Object -Unique
    foreach ($bitness in $bitnesses) {
        Invoke-RestoreLabviewSource -Bitness $bitness
    }
} catch {
    Write-Error "An unexpected error occurred during script execution: $($_.Exception.Message)"
    exit 1
}

