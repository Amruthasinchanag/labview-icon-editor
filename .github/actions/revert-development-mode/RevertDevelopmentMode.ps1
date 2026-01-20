<#
.SYNOPSIS
    Reverts the repository from development mode.

.DESCRIPTION
    Restores the packaged LabVIEW sources for both 32-bit and 64-bit
    environments using RestoreSetupLVSource.vi. LabVIEW is closed after
    each run so downstream steps load the changes.

.PARAMETER MinimumSupportedLVVersion
    LabVIEW major version to target with g-cli (default: 2021).

.PARAMETER SupportedBitness
    One or more bitness values ("32", "64") to run (default: both).

.PARAMETER RelativePath
    Optional path to the repository root.

.EXAMPLE
    .\RevertDevelopmentMode.ps1 -MinimumSupportedLVVersion 2021
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('2020', '2021', '2022', '2023', '2024', '2025')]
    [string]$MinimumSupportedLVVersion = '2021',

    [Parameter(Mandatory = $false)]
    [ValidateSet('32', '64', IgnoreCase = $true)]
    [string[]]$SupportedBitness = @('32', '64'),

    [Parameter(Mandatory = $false)]
    [string]$RelativePath
)

# Determine the directory where this script is located
$ScriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
Write-Host "Script Directory: $ScriptDirectory"

$RestoreScript = Join-Path -Path $ScriptDirectory -ChildPath '..\restore-setup-lv-source\RestoreSetupLVSource.ps1'
Write-Host "RestoreSetupLVSource script: $RestoreScript"

$ErrorActionPreference = 'Stop'

function Invoke-RestoreLabviewSource {
    param(
        [string]$Bitness
    )

    Write-Host "Restoring LabVIEW sources for $Bitness-bit."
    $scriptArgs = @{
        MinimumSupportedLVVersion = $MinimumSupportedLVVersion
        SupportedBitness          = $Bitness
    }

    if ($RelativePath) {
        $scriptArgs.RelativePath = $RelativePath
    }

    & $RestoreScript @scriptArgs

    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
        throw "RestoreSetupLVSource.ps1 failed for $Bitness-bit with exit code $LASTEXITCODE."
    }
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

Write-Host "Development mode reverted." -ForegroundColor Green

