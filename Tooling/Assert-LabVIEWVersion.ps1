#Requires -Version 7.0
<#
.SYNOPSIS
    Enforces the LabVIEW version contract against .lvversion.

.DESCRIPTION
    Reads .lvversion from the repo and compares it with any declared or expected
    LabVIEW version inputs (parameters or environment variables). Throws when
    a mismatch is detected unless AllowMismatch is specified.

.PARAMETER RepoRoot
    Repository root that contains .lvversion.

.PARAMETER ExpectedVersion
    Optional expected version (year or numeric, e.g. 2021 or 21.0) to compare
    against .lvversion.

.PARAMETER AllowMismatch
    If set, mismatches are reported as warnings instead of errors.

.PARAMETER Context
    Optional context label used in messages.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [string]$ExpectedVersion,

    [switch]$AllowMismatch,

    [Parameter(Mandatory = $false)]
    [string]$Context
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'RepoRoot is required.'
    }

    return (Resolve-Path -Path $Path -ErrorAction Stop).Path
}

function Normalize-VersionInput {
    param([string]$Year, [string]$Minor)

    if ([string]::IsNullOrWhiteSpace($Year)) {
        if (-not [string]::IsNullOrWhiteSpace($Minor)) {
            throw "LabVIEW version year is required when a minor revision is provided."
        }
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($Minor)) {
        return $Year
    }

    return "$Year.$Minor"
}

function Add-DeclaredVersion {
    param(
        [string]$Source,
        [string]$VersionInput,
        [string]$RepoRoot
    )

    if ([string]::IsNullOrWhiteSpace($VersionInput)) {
        return $null
    }

    $info = Get-LabVIEWVersionInfo -VersionInput $VersionInput -RepoRoot $RepoRoot
    return [pscustomobject]@{
        Source        = $Source
        Raw           = $info.Raw
        Year          = $info.Year
        MinorRevision = [int]$info.MinorRevision
    }
}

$repoRootResolved = Resolve-RepoRoot -Path $RepoRoot
$versionHelper = Join-Path $repoRootResolved 'Tooling/support/LabVIEWVersion.ps1'
if (-not (Test-Path -Path $versionHelper)) {
    throw "LabVIEW version helper not found at $versionHelper"
}

. $versionHelper

$repoInfo = Get-LabVIEWVersionInfo -RepoRoot $repoRootResolved
$repoYear = [string]$repoInfo.Year
$repoMinor = [int]$repoInfo.MinorRevision

$declared = @()

if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion)) {
    $declared += Add-DeclaredVersion -Source 'expected' -VersionInput $ExpectedVersion -RepoRoot $repoRootResolved
}

$requiredVersion = $env:LVIE_REQUIRED_LABVIEW_VERSION
if (-not [string]::IsNullOrWhiteSpace($requiredVersion)) {
    $declared += Add-DeclaredVersion -Source 'LVIE_REQUIRED_LABVIEW_VERSION' -VersionInput $requiredVersion -RepoRoot $repoRootResolved
}

$requiredFromParts = Normalize-VersionInput -Year $env:LVIE_REQUIRED_LABVIEW_VERSION_YEAR -Minor $env:LVIE_REQUIRED_LABVIEW_MINOR_REVISION
if ($requiredFromParts) {
    $declared += Add-DeclaredVersion -Source 'LVIE_REQUIRED_LABVIEW_VERSION_YEAR/MINOR' -VersionInput $requiredFromParts -RepoRoot $repoRootResolved
}

$envFromParts = Normalize-VersionInput -Year $env:LABVIEW_VERSION_YEAR -Minor $env:LABVIEW_MINOR_REVISION
if ($envFromParts) {
    $declared += Add-DeclaredVersion -Source 'LABVIEW_VERSION_YEAR/MINOR' -VersionInput $envFromParts -RepoRoot $repoRootResolved
}

$declared = $declared | Where-Object { $_ }

$mismatches = @()
foreach ($entry in $declared) {
    if ($entry.Year -ne $repoYear -or $entry.MinorRevision -ne $repoMinor) {
        $mismatches += ("{0}={1} (year {2}, minor {3})" -f $entry.Source, $entry.Raw, $entry.Year, $entry.MinorRevision)
    }
}

$contextLabel = if ([string]::IsNullOrWhiteSpace($Context)) { '' } else { " [$Context]" }
$baseMessage = "LabVIEW version contract${contextLabel}: .lvversion=$($repoInfo.Raw) (year $repoYear, minor $repoMinor)."

if ($mismatches.Count -gt 0) {
    $details = "Mismatched declarations: {0}" -f ($mismatches -join '; ')
    $message = "$baseMessage $details"
    if ($AllowMismatch) {
        Write-Warning $message
    } else {
        throw $message
    }
} else {
    Write-Host "$baseMessage OK."
}

Write-Output $repoInfo
