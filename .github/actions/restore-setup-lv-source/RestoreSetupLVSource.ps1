<#
.SYNOPSIS
    Restores the LabVIEW source setup from a packaged state.

.DESCRIPTION
    Executes RestoreSetupLVSource.vi via g-cli. The VI unzips the LabVIEW
    Icon API, restores lv_icon.ship to lv_icon.lvlibp, and removes the
    LabVIEW token. LabVIEW is closed after the VI executes so subsequent
    steps load the changes.

.PARAMETER MinimumSupportedLVVersion
    LabVIEW version used by g-cli (e.g., "2021").

.PARAMETER SupportedBitness
    Bitness of the LabVIEW environment ("32" or "64").

.PARAMETER RelativePath
    Optional path to the repository root. If omitted, resolved relative to
    this script's location.

.EXAMPLE
    .\RestoreSetupLVSource.ps1 -MinimumSupportedLVVersion "2021" -SupportedBitness "64"
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('2020', '2021', '2022', '2023', '2024', '2025')]
    [string]$MinimumSupportedLVVersion,

    [Parameter(Mandatory = $true)]
    [ValidateSet('32', '64', IgnoreCase = $true)]
    [string]$SupportedBitness,

    [Parameter(Mandatory = $false)]
    [string]$RelativePath
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param(
        [string]$PathOverride
    )

    if ($PathOverride) {
        if (-not (Test-Path -Path $PathOverride)) {
            throw "RelativePath does not exist: $PathOverride"
        }
        return (Resolve-Path -Path $PathOverride).Path
    }

    return (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

$repoRoot = Resolve-RepoRoot -PathOverride $RelativePath
$viPath = Join-Path -Path $repoRoot -ChildPath 'Tooling\RestoreSetupLVSource.vi'

if (-not (Test-Path -Path $viPath)) {
    throw "RestoreSetupLVSource.vi not found at $viPath"
}

if (-not (Get-Command g-cli -ErrorAction SilentlyContinue)) {
    throw "g-cli.exe not found in PATH."
}

$gCliArgs = @(
    '--lv-ver', $MinimumSupportedLVVersion,
    '--arch', $SupportedBitness,
    '-v', $viPath
)

Write-Host ("Executing: g-cli {0}" -f ($gCliArgs -join ' '))
$output = & g-cli @gCliArgs 2>&1
$exitCode = $LASTEXITCODE

$output | ForEach-Object { Write-Host $_ }

if ($exitCode -ne 0) {
    throw "RestoreSetupLVSource.vi failed with exit code $exitCode."
}

$closeScript = Join-Path -Path $PSScriptRoot -ChildPath '..\close-labview\Close_LabVIEW.ps1'
if (-not (Test-Path -Path $closeScript)) {
    throw "Close_LabVIEW.ps1 not found at $closeScript"
}

Write-Host "Closing LabVIEW $MinimumSupportedLVVersion ($SupportedBitness-bit)..."
& $closeScript -MinimumSupportedLVVersion $MinimumSupportedLVVersion -SupportedBitness $SupportedBitness

if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
    throw "Close_LabVIEW.ps1 failed with exit code $LASTEXITCODE."
}

Write-Host "RestoreSetupLVSource.vi completed successfully." -ForegroundColor Green
