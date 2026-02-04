#Requires -Version 7.0
<#
.SYNOPSIS
    Enables LabVIEW Icon Editor development mode without launching LabVIEW.

.DESCRIPTION
    Performs file-system and INI edits to mirror the dev-mode state:
    - zips vi.lib\LabVIEW Icon API to LabVIEW Icon API.zip
    - renames resource\plugins\lv_icon.lvlibp to lv_icon.ship
    - adds RepoRoot to Localhost.LibraryPaths in LabVIEW.ini
    This is intended for local testing; revert should use the LabVIEW-based workflow.

.PARAMETER MinimumSupportedLVVersion
    LabVIEW version year (e.g., 2021) or numeric version (e.g., 21.0).

.PARAMETER SupportedBitness
    One or more bitness values ("32", "64") to run (default: both).

.PARAMETER RepoRoot
    Optional path to the repository root.
#>

[CmdletBinding()]
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
    [string]$RepoRoot
)

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

    return (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
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

function Normalize-PathValue {
    param(
        [string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    try {
        return [System.IO.Path]::GetFullPath($PathValue).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    } catch {
        return $PathValue.TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    }
}

function Get-IniLibraryPaths {
    param(
        [string]$IniPath
    )

    if (-not (Test-Path -Path $IniPath)) {
        return @()
    }

    $line = Get-Content -Path $IniPath | Where-Object { $_ -match '(?i)^\s*localhost\.librarypaths\s*=' } | Select-Object -First 1
    if (-not $line) {
        return @()
    }

    $value = $line -replace '(?i)^\s*localhost\.librarypaths\s*=\s*', ''
    if ([string]::IsNullOrWhiteSpace($value)) {
        return @()
    }

    return ($value -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Format-IniPath {
    param(
        [string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    if ($PathValue -match '\s') {
        return '"' + $PathValue + '"'
    }

    return $PathValue
}

function Set-IniLibraryPath {
    param(
        [string]$IniPath,
        [string]$RepoRoot
    )

    $lines = @()
    if (Test-Path -Path $IniPath) {
        $lines = Get-Content -Path $IniPath
    }

    $lineIndex = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '(?i)^\s*localhost\.librarypaths\s*=') {
            $lineIndex = $i
            break
        }
    }

    $paths = @()
    if ($lineIndex -ne $null) {
        $raw = $lines[$lineIndex] -replace '(?i)^\s*localhost\.librarypaths\s*=\s*', ''
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $paths = $raw -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        }
    }

    $repoRootNormalized = Normalize-PathValue -PathValue $RepoRoot
    $existingNormalized = @{}
    foreach ($pathValue in $paths) {
        $normalized = Normalize-PathValue -PathValue $pathValue
        if ($normalized) {
            $existingNormalized[$normalized.ToLowerInvariant()] = $pathValue
        }
    }

    if ($repoRootNormalized) {
        $key = $repoRootNormalized.ToLowerInvariant()
        if (-not $existingNormalized.ContainsKey($key)) {
            $paths += $repoRootNormalized
        }
    }

    $formatted = $paths | ForEach-Object { Format-IniPath -PathValue $_ } | Where-Object { $_ }
    $newLine = if ($formatted.Count -gt 0) {
        "Localhost.LibraryPaths={0}" -f ($formatted -join ';')
    } else {
        "Localhost.LibraryPaths=$RepoRoot"
    }

    if ($lineIndex -ne $null) {
        $lines[$lineIndex] = $newLine
    } else {
        $lines += $newLine
    }

    $targetDir = Split-Path -Path $IniPath -Parent
    if (-not (Test-Path -Path $targetDir)) {
        throw "LabVIEW install root not found for INI path: $IniPath"
    }

    Set-Content -Path $IniPath -Value $lines -Encoding ascii
}

function Test-LibraryPathContainsRepoRoot {
    param(
        [string]$IniPath,
        [string]$RepoRoot
    )

    $repoRootNormalized = Normalize-PathValue -PathValue $RepoRoot
    if (-not $repoRootNormalized) {
        return $false
    }
    $repoKey = $repoRootNormalized.ToLowerInvariant()

    foreach ($pathValue in (Get-IniLibraryPaths -IniPath $IniPath)) {
        $candidate = Normalize-PathValue -PathValue $pathValue
        if ($candidate -and $candidate.ToLowerInvariant() -eq $repoKey) {
            return $true
        }
    }

    return $false
}

function Test-IEDevModeEnabled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LabVIEWInstallRoot
    )

    $installPaths = @{
        IconApiFolder = Join-Path $LabVIEWInstallRoot 'vi.lib\LabVIEW Icon API'
        IconApiZip    = Join-Path $LabVIEWInstallRoot 'vi.lib\LabVIEW Icon API.zip'
        Lvlibp        = Join-Path $LabVIEWInstallRoot 'resource\plugins\lv_icon.lvlibp'
        Ship          = Join-Path $LabVIEWInstallRoot 'resource\plugins\lv_icon.ship'
    }

    $hasLvlibp = Test-Path -Path $installPaths.Lvlibp
    $hasShip = Test-Path -Path $installPaths.Ship
    $hasIconFolder = Test-Path -Path $installPaths.IconApiFolder
    $hasIconZip = Test-Path -Path $installPaths.IconApiZip

    return ($hasShip -and (-not $hasLvlibp) -and (-not $hasIconFolder) -and $hasIconZip)
}

function Enable-DevModeNoLabVIEW {
    param(
        [string]$Bitness,
        [string]$RepoRoot,
        [string]$LabVIEWYear
    )

    $installRoot = Get-LabVIEWInstallRoot -Version $LabVIEWYear -Bitness $Bitness
    if (-not $installRoot) {
        throw "LabVIEW $LabVIEWYear ($Bitness-bit) install not found."
    }

    $iconApiDir = Join-Path $installRoot 'vi.lib\LabVIEW Icon API'
    $iconApiZip = Join-Path $installRoot 'vi.lib\LabVIEW Icon API.zip'
    $lvlibpPath = Join-Path $installRoot 'resource\plugins\lv_icon.lvlibp'
    $shipPath = Join-Path $installRoot 'resource\plugins\lv_icon.ship'
    $iniPath = Join-Path $installRoot 'LabVIEW.ini'

    Write-Host ("Enable dev mode (no LabVIEW): LV{0} {1}-bit" -f $LabVIEWYear, $Bitness)
    Write-Host ("Install root: {0}" -f $installRoot)

    if (Test-Path -Path $iconApiDir) {
        Write-Host "Zipping LabVIEW Icon API folder."
        if (Test-Path -Path $iconApiZip) {
            Remove-Item -Path $iconApiZip -Force -ErrorAction SilentlyContinue
        }
        Compress-Archive -Path $iconApiDir -DestinationPath $iconApiZip -Force
        Remove-Item -Path $iconApiDir -Recurse -Force
    } elseif (-not (Test-Path -Path $iconApiZip)) {
        Write-Warning ("Icon API folder and zip not found under {0}." -f (Join-Path $installRoot 'vi.lib'))
    }

    if (Test-Path -Path $lvlibpPath) {
        Write-Host "Renaming lv_icon.lvlibp to lv_icon.ship."
        if (Test-Path -Path $shipPath) {
            Remove-Item -Path $shipPath -Force -ErrorAction SilentlyContinue
        }
        Move-Item -Path $lvlibpPath -Destination $shipPath -Force
    } elseif (-not (Test-Path -Path $shipPath)) {
        Write-Warning ("lv_icon.lvlibp and lv_icon.ship not found under {0}." -f (Split-Path $lvlibpPath -Parent))
    }

    Write-Host ("Updating Localhost.LibraryPaths in {0}" -f $iniPath)
    Set-IniLibraryPath -IniPath $iniPath -RepoRoot $RepoRoot

    $issues = @()
    if (-not (Test-IEDevModeEnabled -LabVIEWInstallRoot $installRoot)) {
        $issues += 'Install files did not reflect dev-mode state.'
    }
    if (-not (Test-LibraryPathContainsRepoRoot -IniPath $iniPath -RepoRoot $RepoRoot)) {
        $issues += 'Localhost.LibraryPaths does not include repo root.'
    }

    if ($issues.Count -gt 0) {
        throw ("Dev mode enable (no LabVIEW) failed: {0}" -f ($issues -join ' '))
    }
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

try {
    $bitnesses = $SupportedBitness | Select-Object -Unique
    foreach ($bitness in $bitnesses) {
        Enable-DevModeNoLabVIEW -Bitness $bitness -RepoRoot $resolvedRepoRoot -LabVIEWYear $labviewYear
    }
}
catch {
    Write-Error "An unexpected error occurred during script execution: $($_.Exception.Message)"
    exit 1
}
