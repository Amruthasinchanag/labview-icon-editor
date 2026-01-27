<#
.SYNOPSIS
    Helpers for translating dev-mode diagnostics bitmasks emitted by VIs.

.DESCRIPTION
    Parses g-cli output for a diagnostics U8, decodes set bits into missing
    path names, and formats a human-readable report.
#>

function Get-DevModeDiagnosticsBitmaskFromOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Output
    )

    $lines = @()
    foreach ($item in $Output) {
        if ($null -eq $item) {
            continue
        }

        $text = [string]$item
        if ($text -match "`r|`n") {
            $lines += $text -split "`r?`n"
        } else {
            $lines += $text
        }
    }

    $lastMatch = $null
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '-59345[01].*occurred at\s+(?<code>\d{1,3})\b') {
            $value = [int]$Matches.code
            if ($value -ge 0 -and $value -le 255) {
                $lastMatch = $value
            }
        }
    }

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\d{1,3}$') {
            $value = [int]$trimmed
            if ($value -ge 0 -and $value -le 255) {
                $lastMatch = $value
            }
        }
    }

    return $lastMatch
}

function Get-DevModeDiagnosticsInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 255)]
        [int]$Bitmask
    )

    $bitNames = @(
        'NIIconEditor',
        'lv_icon.lvlibp',
        'lv_IconEditor.lvlib',
        'lv_icon.vi',
        'lv_icon.vit',
        'SAMPLE_lv_icon.vi',
        'LabVIEW Icon API',
        'All non-fatal paths'
    )

    $binary = [Convert]::ToString($Bitmask, 2).PadLeft(8, '0')
    $setBits = New-Object System.Collections.Generic.List[int]
    $missingPaths = New-Object System.Collections.Generic.List[string]
    $guardBitSet = $false

    for ($i = 0; $i -lt 8; $i++) {
        if (($Bitmask -band (1 -shl $i)) -ne 0) {
            $setBits.Add($i)
            if ($i -eq 7) {
                $guardBitSet = $true
            }
        }
    }

    for ($i = 0; $i -lt 7; $i++) {
        if (($Bitmask -band (1 -shl $i)) -eq 0) {
            $missingPaths.Add($bitNames[$i])
        }
    }

    return [pscustomobject]@{
        Bitmask      = $Bitmask
        Binary       = $binary
        SetBits      = $setBits.ToArray()
        MissingPaths = $missingPaths.ToArray()
        GuardBitSet  = $guardBitSet
    }
}

function Get-DevModeDiagnosticsFromOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Output
    )

    $bitmask = Get-DevModeDiagnosticsBitmaskFromOutput -Output $Output
    if ($null -eq $bitmask) {
        return $null
    }

    return Get-DevModeDiagnosticsInfo -Bitmask $bitmask
}

function Format-DevModeDiagnosticsReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Diagnostics
    )

    $setBits = if ($Diagnostics.SetBits -and $Diagnostics.SetBits.Count -gt 0) {
        $Diagnostics.SetBits -join ', '
    } else {
        'none'
    }

    $missing = if ($Diagnostics.MissingPaths -and $Diagnostics.MissingPaths.Count -gt 0) {
        $Diagnostics.MissingPaths -join ', '
    } else {
        'none'
    }

    $guard = if ($Diagnostics.GuardBitSet) {
        'set'
    } else {
        'NOT set (unexpected)'
    }

    $lines = @(
        ("Diagnostics bitmask: {0} (0b{1})" -f $Diagnostics.Bitmask, $Diagnostics.Binary),
        ("Set bits: {0}" -f $setBits),
        ("Expected missing paths (bits not set): {0}" -f $missing),
        ("Guard bit (bit 7) is {0}." -f $guard)
    )

    return ($lines -join [Environment]::NewLine)
}

function Format-DevModeDiagnosticsSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Diagnostics
    )

    $setBits = if ($Diagnostics.SetBits -and $Diagnostics.SetBits.Count -gt 0) {
        $Diagnostics.SetBits -join ', '
    } else {
        'none'
    }

    $missing = if ($Diagnostics.MissingPaths -and $Diagnostics.MissingPaths.Count -gt 0) {
        $Diagnostics.MissingPaths -join ', '
    } else {
        'none'
    }

    $guard = if ($Diagnostics.GuardBitSet) { 'True' } else { 'False' }

    return ("Diagnostics: bitmask={0} (0b{1}), set_bits={2}, expected_missing={3}, guard_bit_set={4}." -f `
        $Diagnostics.Bitmask, $Diagnostics.Binary, $setBits, $missing, $guard)
}
