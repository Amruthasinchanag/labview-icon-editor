#Requires -Version 7.0
[CmdletBinding()]
param(
    [int]$RetentionDays
)

$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
$runnerRoot = Split-Path -Parent $scriptRoot
$cleanupScript = Join-Path $scriptRoot 'cleanup-runner-diag-pages.ps1'

if (-not (Test-Path -Path $cleanupScript)) {
    throw "Cleanup script not found: $cleanupScript"
}

if (-not $PSBoundParameters.ContainsKey('RetentionDays')) {
    $envRetention = $env:RUNNER_DIAG_RETENTION_DAYS
    if (-not [string]::IsNullOrWhiteSpace($envRetention)) {
        $parsed = $null
        if ([int]::TryParse($envRetention, [ref]$parsed)) {
            $RetentionDays = $parsed
        }
        else {
            Write-Warning "Invalid RUNNER_DIAG_RETENTION_DAYS value: $envRetention. Using 0."
            $RetentionDays = 0
        }
    }
    elseif (-not $PSBoundParameters.ContainsKey('RetentionDays')) {
        $RetentionDays = 0
    }
}

& $cleanupScript -RunnerRoot $runnerRoot -RetentionDays $RetentionDays
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
    exit $LASTEXITCODE
}
