<#
.SYNOPSIS
    Gracefully closes a running LabVIEW instance.

.DESCRIPTION
    Utilizes g-cli's QuitLabVIEW command to shut down the specified LabVIEW
    version and bitness, ensuring the application exits cleanly.

.PARAMETER MinimumSupportedLVVersion
    LabVIEW version to close (e.g., "2021").

.PARAMETER SupportedBitness
    Bitness of the LabVIEW instance ("32" or "64").

.EXAMPLE
    .\Close_LabVIEW.ps1 -MinimumSupportedLVVersion "2021" -SupportedBitness "64"
#>
param(
    [string]$MinimumSupportedLVVersion,
    [string]$SupportedBitness,
    [ValidateRange(5, 600)]
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'

function Invoke-SafeQuitLabVIEW {
    param(
        [string]$Version,
        [string]$Bitness
    )

    if (-not (Get-Command g-cli -ErrorAction SilentlyContinue)) {
        throw "g-cli.exe not found in PATH."
    }

    $args = @(
        "--lv-ver", $Version,
        "--arch",   $Bitness,
        "QuitLabVIEW"
    )

    Write-Host ("Executing: g-cli {0}" -f ($args -join ' '))
    $output   = & g-cli @args 2>&1
    $exitCode = $LASTEXITCODE

    # echo all output for log visibility
    $output | ForEach-Object { Write-Host $_ }

    if ($exitCode -eq 0) { return }

    $joined = ($output -join ' ')
    if ($joined -match 'not (currently )?running' -or $joined -match 'does not appear to be running') {
        Write-Host "LabVIEW $Version ($Bitness-bit) was not running; nothing to close."
        return
    }

    throw "g-cli QuitLabVIEW failed with exit code $exitCode."
}

function Wait-ForLabVIEWExit {
    param(
        [string]$Version,
        [string]$Bitness,
        [int]$TimeoutSeconds = 30
    )

    $installRoot = $null
    if ($Bitness -eq '32') {
        $installRoot = "C:\Program Files (x86)\National Instruments\LabVIEW $Version"
    } else {
        $installRoot = "C:\Program Files\National Instruments\LabVIEW $Version"
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $running = @()
        try {
            $running = Get-CimInstance Win32_Process -Filter "Name='LabVIEW.exe'" -ErrorAction Stop
        } catch {
            $running = @()
        }

        if ($running.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($installRoot)) {
            $running = $running | Where-Object {
                $_.ExecutablePath -and $_.ExecutablePath.StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase)
            }
        }

        if (-not $running -or $running.Count -eq 0) {
            $running = Get-Process -Name LabVIEW -ErrorAction SilentlyContinue
            if ($running -and -not [string]::IsNullOrWhiteSpace($installRoot)) {
                $filtered = @()
                foreach ($process in $running) {
                    $path = $null
                    try { $path = $process.Path } catch { }
                    if ($path -and $path.StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $filtered += $process
                    }
                }
                if ($filtered.Count -gt 0) {
                    $running = $filtered
                }
            }
        }

        if (-not $running) {
            return $true
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    return $false
}

try {
    Invoke-SafeQuitLabVIEW -Version $MinimumSupportedLVVersion -Bitness $SupportedBitness
    if (-not (Wait-ForLabVIEWExit -Version $MinimumSupportedLVVersion -Bitness $SupportedBitness -TimeoutSeconds $TimeoutSeconds)) {
        throw "LabVIEW $MinimumSupportedLVVersion ($SupportedBitness-bit) did not exit within $TimeoutSeconds seconds."
    }
    Write-Host "LabVIEW $MinimumSupportedLVVersion ($SupportedBitness-bit) closed or not running."
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
