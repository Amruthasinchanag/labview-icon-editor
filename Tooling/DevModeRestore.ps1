#Requires -Version 7.0
<#
.SYNOPSIS
    Restores a dev-mode snapshot captured by DevModeSnapshot.ps1.

.DESCRIPTION
    Restores LabVIEW.ini, LabVIEW Icon API (folder or zip), and lv_icon.*
    for each bitness recorded in the snapshot manifest.

.PARAMETER SnapshotRoot
    Path to the snapshot root containing dev-mode-snapshot.json.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SnapshotRoot
)

$ErrorActionPreference = 'Stop'

function New-DirectoryIfMissing {
    param(
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Copy-File {
    param(
        [string]$Source,
        [string]$Destination
    )

    $destDir = Split-Path -Parent -Path $Destination
    if (-not [string]::IsNullOrWhiteSpace($destDir)) {
        New-DirectoryIfMissing -Path $destDir
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Copy-Folder {
    param(
        [string]$Source,
        [string]$Destination
    )

    $destDir = Split-Path -Parent -Path $Destination
    if (-not [string]::IsNullOrWhiteSpace($destDir)) {
        New-DirectoryIfMissing -Path $destDir
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Remove-IfPresent {
    param(
        [string]$Path
    )

    if (Test-Path -Path $Path) {
        Remove-Item -LiteralPath $Path -Force -Recurse
    }
}

$snapshotRootResolved = [System.IO.Path]::GetFullPath($SnapshotRoot)
if (-not (Test-Path -Path $snapshotRootResolved)) {
    throw "Snapshot root not found: $snapshotRootResolved"
}

$manifestPath = Join-Path -Path $snapshotRootResolved -ChildPath 'dev-mode-snapshot.json'
if (-not (Test-Path -Path $manifestPath)) {
    throw "Snapshot manifest not found at $manifestPath"
}

$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
if (-not $manifest -or -not $manifest.Items) {
    throw "Snapshot manifest is missing items: $manifestPath"
}

foreach ($item in $manifest.Items) {
    $installRoot = $item.InstallRoot
    if (-not $installRoot -or -not (Test-Path -Path $installRoot)) {
        throw "LabVIEW install root not found: $installRoot"
    }

    $iniPath = $item.IniPath
    $iniPresent = [bool]$item.IniPresent
    $iniSnapshot = $item.IniSnapshot
    if ($iniPresent) {
        if (-not $iniSnapshot -or -not (Test-Path -Path $iniSnapshot)) {
            throw "LabVIEW.ini snapshot missing at $iniSnapshot"
        }
        Copy-File -Source $iniSnapshot -Destination $iniPath
    } else {
        Write-Warning ("Snapshot had no LabVIEW.ini for {0}; leaving current file untouched." -f $installRoot)
    }

    $iconApiDir = $item.IconApiFolder
    $iconApiZip = $item.IconApiZip
    $iconApiFolderPresent = [bool]$item.IconApiFolderPresent
    $iconApiZipPresent = [bool]$item.IconApiZipPresent
    $iconApiFolderSnapshot = $item.IconApiFolderSnapshot
    $iconApiZipSnapshot = $item.IconApiZipSnapshot

    if ($iconApiFolderPresent) {
        if (-not $iconApiFolderSnapshot -or -not (Test-Path -Path $iconApiFolderSnapshot)) {
            throw "Icon API folder snapshot missing at $iconApiFolderSnapshot"
        }
        Remove-IfPresent -Path $iconApiDir
        Remove-IfPresent -Path $iconApiZip
        Copy-Folder -Source $iconApiFolderSnapshot -Destination $iconApiDir
    } else {
        Remove-IfPresent -Path $iconApiDir
    }

    if ($iconApiZipPresent) {
        if (-not $iconApiZipSnapshot -or -not (Test-Path -Path $iconApiZipSnapshot)) {
            throw "Icon API zip snapshot missing at $iconApiZipSnapshot"
        }
        Remove-IfPresent -Path $iconApiZip
        Copy-File -Source $iconApiZipSnapshot -Destination $iconApiZip
    } else {
        Remove-IfPresent -Path $iconApiZip
    }

    $lvlibpPath = $item.LvlibpPath
    $shipPath = $item.ShipPath
    $lvlibpPresent = [bool]$item.LvlibpPresent
    $shipPresent = [bool]$item.ShipPresent
    $lvlibpSnapshot = $item.LvlibpSnapshot
    $shipSnapshot = $item.ShipSnapshot

    if ($lvlibpPresent) {
        if (-not $lvlibpSnapshot -or -not (Test-Path -Path $lvlibpSnapshot)) {
            throw "lv_icon.lvlibp snapshot missing at $lvlibpSnapshot"
        }
        Remove-IfPresent -Path $lvlibpPath
        Copy-File -Source $lvlibpSnapshot -Destination $lvlibpPath
    } else {
        Remove-IfPresent -Path $lvlibpPath
    }

    if ($shipPresent) {
        if (-not $shipSnapshot -or -not (Test-Path -Path $shipSnapshot)) {
            throw "lv_icon.ship snapshot missing at $shipSnapshot"
        }
        Remove-IfPresent -Path $shipPath
        Copy-File -Source $shipSnapshot -Destination $shipPath
    } else {
        Remove-IfPresent -Path $shipPath
    }
}

$restoreRecord = [ordered]@{
    RestoredUtc  = (Get-Date).ToUniversalTime().ToString('o')
    SnapshotRoot = $snapshotRootResolved
    ItemsRestored = $manifest.Items.Count
}
$restorePath = Join-Path -Path $snapshotRootResolved -ChildPath 'dev-mode-restore.json'
$restoreRecord | ConvertTo-Json -Depth 4 | Set-Content -Path $restorePath -Encoding utf8
Write-Host ("Dev mode restore complete from {0}" -f $snapshotRootResolved)

