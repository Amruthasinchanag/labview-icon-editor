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

.PARAMETER LabVIEWVersion
    LabVIEW version year (e.g., 2021) or numeric version (e.g., 21.0).
    Alias: MinimumSupportedLVVersion.

.PARAMETER SupportedBitness
    One or more bitness values ("32", "64") to run (default: both).

.PARAMETER RepoRoot
    Optional path to the repository root.

.PARAMETER ContractPath
    Optional path to the dev-mode contract JSON file.

.PARAMETER SkipProcessCheck
    Skip checking for running LabVIEW or g-cli processes.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [Alias('MinimumSupportedLVVersion')]
    [AllowNull()]
    [AllowEmptyString()]
    [string]$LabVIEWVersion = '',

    [Parameter(Mandatory = $false)]
    [ValidateSet('32', '64', IgnoreCase = $true)]
    [string[]]$SupportedBitness = @('32', '64'),

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [string]$ContractPath,

    [Parameter(Mandatory = $false)]
    [switch]$SkipProcessCheck
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
        if (Test-Path -LiteralPath $PathValue -ErrorAction SilentlyContinue) {
            try {
                return (Resolve-Path -LiteralPath $PathValue).Path.TrimEnd([System.IO.Path]::DirectorySeparatorChar)
            } catch {
            }
        }
    } catch {
        # Access denied or other IO errors should not break dev-mode toggling.
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
            $paths = @($raw -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
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

    $entry = [ordered]@{
        key          = ("{0}-{1}" -f $LabVIEWYear, $Bitness)
        labviewYear  = $LabVIEWYear
        bitness      = $Bitness
        desiredState = 'enabled'
        actualState  = 'unknown'
        status       = 'unknown'
        repoRoot     = $RepoRoot
        startUtc     = (Get-Date).ToUniversalTime().ToString('o')
        endUtc       = $null
        changes      = @()
        notes        = @()
        error        = $null
    }

    $installRoot = Get-LabVIEWInstallRoot -Version $LabVIEWYear -Bitness $Bitness
    if (-not $installRoot) {
        $entry.status = 'failed'
        $entry.error = "LabVIEW $LabVIEWYear ($Bitness-bit) install not found."
        $entry.endUtc = (Get-Date).ToUniversalTime().ToString('o')
        return $entry
    }

    $iconApiDir = Join-Path $installRoot 'vi.lib\LabVIEW Icon API'
    $iconApiZip = Join-Path $installRoot 'vi.lib\LabVIEW Icon API.zip'
    $lvlibpPath = Join-Path $installRoot 'resource\plugins\lv_icon.lvlibp'
    $shipPath = Join-Path $installRoot 'resource\plugins\lv_icon.ship'
    $iniPath = Join-Path $installRoot 'LabVIEW.ini'
    $entry.installRoot = $installRoot
    $entry.iniPath = $iniPath

    Write-Host ("Enable dev mode (no LabVIEW): LV{0} {1}-bit" -f $LabVIEWYear, $Bitness)
    Write-Host ("Install root: {0}" -f $installRoot)

    try {
        $preEnabled = Test-IEDevModeEnabled -LabVIEWInstallRoot $installRoot
        $preHasRepo = Test-LibraryPathContainsRepoRoot -IniPath $iniPath -RepoRoot $RepoRoot
        if ($preEnabled -and $preHasRepo) {
            $entry.actualState = 'enabled'
            $entry.status = 'skipped'
            $entry.notes += 'Dev mode already enabled.'
            return $entry
        }

        if (Test-Path -Path $iconApiDir) {
            Write-Host "Zipping LabVIEW Icon API folder."
            if (Test-Path -Path $iconApiZip) {
                Remove-Item -Path $iconApiZip -Force -ErrorAction SilentlyContinue
                $entry.changes += [ordered]@{ operation = 'remove-icon-api-zip'; status = 'changed'; path = $iconApiZip }
            }
            Compress-Archive -Path $iconApiDir -DestinationPath $iconApiZip -Force
            Remove-Item -Path $iconApiDir -Recurse -Force
            $entry.changes += [ordered]@{ operation = 'zip-icon-api'; status = 'changed'; source = $iconApiDir; destination = $iconApiZip }
        } elseif (-not (Test-Path -Path $iconApiZip)) {
            Write-Warning ("Icon API folder and zip not found under {0}." -f (Join-Path $installRoot 'vi.lib'))
            $entry.changes += [ordered]@{ operation = 'zip-icon-api'; status = 'missing'; path = $iconApiDir }
        } else {
            $entry.changes += [ordered]@{ operation = 'zip-icon-api'; status = 'skipped'; path = $iconApiZip }
        }

        if (Test-Path -Path $lvlibpPath) {
            Write-Host "Renaming lv_icon.lvlibp to lv_icon.ship."
            if (Test-Path -Path $shipPath) {
                Remove-Item -Path $shipPath -Force -ErrorAction SilentlyContinue
                $entry.changes += [ordered]@{ operation = 'remove-lv_icon.ship'; status = 'changed'; path = $shipPath }
            }
            Move-Item -Path $lvlibpPath -Destination $shipPath -Force
            $entry.changes += [ordered]@{ operation = 'rename-lvlibp'; status = 'changed'; source = $lvlibpPath; destination = $shipPath }
        } elseif (-not (Test-Path -Path $shipPath)) {
            Write-Warning ("lv_icon.lvlibp and lv_icon.ship not found under {0}." -f (Split-Path $lvlibpPath -Parent))
            $entry.changes += [ordered]@{ operation = 'rename-lvlibp'; status = 'missing'; path = $lvlibpPath }
        } else {
            $entry.changes += [ordered]@{ operation = 'rename-lvlibp'; status = 'skipped'; path = $shipPath }
        }

        Write-Host ("Updating Localhost.LibraryPaths in {0}" -f $iniPath)
        Set-IniLibraryPath -IniPath $iniPath -RepoRoot $RepoRoot
        $entry.changes += [ordered]@{ operation = 'set-library-paths'; status = 'changed'; path = $iniPath }

        $issues = @()
        $postEnabled = Test-IEDevModeEnabled -LabVIEWInstallRoot $installRoot
        $postHasRepo = Test-LibraryPathContainsRepoRoot -IniPath $iniPath -RepoRoot $RepoRoot
        if (-not $postEnabled) {
            $issues += 'Install files did not reflect dev-mode state.'
        }
        if (-not $postHasRepo) {
            $issues += 'Localhost.LibraryPaths does not include repo root.'
        }

        $entry.actualState = if ($postEnabled -and $postHasRepo) { 'enabled' } else { 'partial' }
        if ($issues.Count -gt 0) {
            $entry.status = 'failed'
            $entry.error = ("Dev mode enable (no LabVIEW) failed: {0}" -f ($issues -join ' '))
        } else {
            $entry.status = 'success'
        }
    } catch {
        if (-not $entry.error) {
            $entry.error = $_.Exception.Message
        }
        $entry.status = 'failed'
    } finally {
        if (-not $entry.actualState -or $entry.actualState -eq 'unknown') {
            $entry.actualState = if (Test-IEDevModeEnabled -LabVIEWInstallRoot $installRoot) { 'enabled' } else { 'disabled' }
        }
        $entry.endUtc = (Get-Date).ToUniversalTime().ToString('o')
    }

    return $entry
}

function Invoke-DevModeNoLabVIEWMain {
    $resolvedRepoRoot = Resolve-RepoRoot -PathOverride $RepoRoot
    $versionHelper = Join-Path $resolvedRepoRoot 'Tooling\support\LabVIEWVersion.ps1'
    $contractHelper = Join-Path $resolvedRepoRoot 'Tooling\support\DevModeContract.ps1'
    $labviewYear = $LabVIEWVersion
    if (Test-Path -Path $versionHelper) {
        . $versionHelper
        $versionInfo = Get-LabVIEWVersionInfo -VersionInput $LabVIEWVersion -RepoRoot $resolvedRepoRoot
        $labviewYear = $versionInfo.Year
    }
    if (-not (Test-Path -Path $contractHelper)) {
        throw "Dev mode contract helper not found at $contractHelper"
    }
    . $contractHelper
    if ([string]::IsNullOrWhiteSpace($labviewYear)) {
        $labviewYear = '2021'
    }

    try {
        if (-not $SkipProcessCheck) {
            Assert-DevModeNoProcesses
        }
        $contractPath = Resolve-DevModeContractPath -RepoRoot $resolvedRepoRoot -ContractPath $ContractPath
        $contract = Read-DevModeContract -ContractPath $contractPath -RepoRoot $resolvedRepoRoot
        $bitnesses = $SupportedBitness | Select-Object -Unique
        foreach ($bitness in $bitnesses) {
            $entry = Enable-DevModeNoLabVIEW -Bitness $bitness -RepoRoot $resolvedRepoRoot -LabVIEWYear $labviewYear
            $contract = Update-DevModeContractEntry -Contract $contract -Entry $entry
            Write-DevModeContract -Contract $contract -ContractPath $contractPath
            if ($entry.status -eq 'failed') {
                throw $entry.error
            }
        }
    }
    catch {
        Write-Error "An unexpected error occurred during script execution: $($_.Exception.Message)"
        exit 1
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-DevModeNoLabVIEWMain
}
