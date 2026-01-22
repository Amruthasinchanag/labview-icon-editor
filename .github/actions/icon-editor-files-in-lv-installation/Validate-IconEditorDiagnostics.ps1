#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('enable', 'disable')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [string]$CsvPath,

    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

$headers = @('File Path', 'Bytes', 'Last modified')

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

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE) -and (Test-Path -Path $env:GITHUB_WORKSPACE)) {
        return (Resolve-Path -Path $env:GITHUB_WORKSPACE).Path
    }

    $fallback = Split-Path -Parent $CsvPath
    if ($fallback -and (Test-Path -Path $fallback)) {
        return (Resolve-Path -Path $fallback).Path
    }

    throw "Unable to resolve repository root. Provide -RepoRoot."
}

function Import-IconEditorCsv {
    param(
        [string]$Path
    )

    $firstLine = Get-Content -Path $Path -TotalCount 1
    $headerLine = ($headers -join ',')
    $headerQuoted = '"' + ($headers -join '","') + '"'
    $hasHeader = ($firstLine -eq $headerLine) -or ($firstLine -eq $headerQuoted)

    if ($hasHeader) {
        return (Import-Csv -Path $Path)
    }

    return (Import-Csv -Path $Path -Header $headers)
}

function Normalize-Path {
    param(
        [string]$Path
    )

    try {
        return [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return $null
    }
}

function Test-PathUnderRoot {
    param(
        [string]$Path,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $fullPath = Normalize-Path -Path $Path
    if (-not $fullPath) {
        return $false
    }

    return $fullPath.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)
}

if (-not (Test-Path -Path $CsvPath)) {
    throw "Diagnostics CSV not found: $CsvPath"
}

$repoRootResolved = Resolve-RepoRoot -PathOverride $RepoRoot
$repoRootNormalized = Normalize-Path -Path $repoRootResolved
if (-not $repoRootNormalized) {
    throw "Unable to normalize RepoRoot: $repoRootResolved"
}

$separator = [System.IO.Path]::DirectorySeparatorChar
if (-not $repoRootNormalized.EndsWith($separator)) {
    $repoRootNormalized += $separator
}

$rows = Import-IconEditorCsv -Path $CsvPath
if (-not $rows -or $rows.Count -eq 0) {
    throw "Diagnostics CSV is empty or could not be parsed: $CsvPath"
}

$viLibRows = $rows | Where-Object { $_.'File Path' -like "*\vi.lib\LabVIEW Icon API\*" }
if (-not $viLibRows -or $viLibRows.Count -eq 0) {
    throw "No vi.lib rows found in diagnostics CSV; cannot validate dev mode."
}

$repoViLibRows = $viLibRows | Where-Object { Test-PathUnderRoot -Path $_.'File Path' -Root $repoRootNormalized }

Write-Host "Mode: $Mode"
Write-Host "Repo root: $repoRootResolved"
Write-Host ("vi.lib rows: {0}" -f $viLibRows.Count)
Write-Host ("vi.lib rows under repo root: {0}" -f $repoViLibRows.Count)

if ($Mode -eq 'enable') {
    if ($repoViLibRows.Count -eq 0) {
        throw "Dev mode validation failed: no vi.lib paths under repo root after enable."
    }
}
else {
    if ($repoViLibRows.Count -gt 0) {
        $sample = $repoViLibRows | Select-Object -First 1 -ExpandProperty 'File Path'
        throw "Dev mode validation failed: vi.lib paths still under repo root after disable. Example: $sample"
    }
}

Write-Host "Dev mode validation passed."
