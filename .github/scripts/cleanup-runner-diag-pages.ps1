#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RunnerRoot,
    [int]$RetentionDays = 0
)

$ErrorActionPreference = 'Stop'

function Resolve-RunnerRoot {
    param(
        [string]$PathOverride
    )

    if (-not [string]::IsNullOrWhiteSpace($PathOverride)) {
        if (-not (Test-Path -Path $PathOverride)) {
            throw "RunnerRoot does not exist: $PathOverride"
        }
        return (Resolve-Path -Path $PathOverride).Path
    }

    if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -and (Test-Path -Path $env:RUNNER_TEMP)) {
        $tempPath = (Resolve-Path -Path $env:RUNNER_TEMP).Path
        $workPath = Split-Path -Parent $tempPath
        $rootPath = Split-Path -Parent $workPath
        if (Test-Path -Path (Join-Path $rootPath '_diag\pages')) {
            return $rootPath
        }
    }

    $cursor = (Resolve-Path -Path $PSScriptRoot).Path
    while ($cursor) {
        if (Test-Path -Path (Join-Path $cursor '_diag\pages')) {
            return $cursor
        }

        $parent = Split-Path -Parent $cursor
        if ($parent -eq $cursor) {
            break
        }
        $cursor = $parent
    }

    throw "Unable to locate runner root. Provide -RunnerRoot."
}

$runnerRootResolved = Resolve-RunnerRoot -PathOverride $RunnerRoot
$diagPath = Join-Path $runnerRootResolved '_diag\pages'

if (-not (Test-Path -Path $diagPath)) {
    Write-Host "Diagnostics folder not found: $diagPath"
    return
}

if ($RetentionDays -lt 0) {
    throw "RetentionDays must be 0 or greater."
}

$files = Get-ChildItem -Path $diagPath -File -ErrorAction Stop
if ($RetentionDays -gt 0) {
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    $files = $files | Where-Object { $_.LastWriteTime -lt $cutoff }
}

if (-not $files) {
    Write-Host "No diagnostics files to remove in $diagPath"
    return
}

Remove-Item -Path $files.FullName -Force -ErrorAction Stop
Write-Host ("Removed {0} diagnostics file(s) from {1}" -f $files.Count, $diagPath)
