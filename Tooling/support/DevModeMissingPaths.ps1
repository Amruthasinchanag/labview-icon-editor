#Requires -Version 7.0
<#
.SYNOPSIS
    Helper for extracting dev-mode missing paths from g-cli output.
#>

function Get-DevModeMissingPathsFromOutput {
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

    $candidates = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if ($trimmed -match '(?i)\bmissing paths?\b[:\-]?\s*(?<list>.+)$') {
            $candidates.Add($Matches.list)
            continue
        }

        if ($trimmed -match 'Error\s+-59345[01]\s+occurred at\s+(?<source>.+)$') {
            $source = $Matches.source.Trim()
            if ($source.EndsWith(':') -or [string]::IsNullOrWhiteSpace($source)) {
                for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                    $next = $lines[$j].Trim()
                    if (-not [string]::IsNullOrWhiteSpace($next)) {
                        $source = $next
                        break
                    }
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($source)) {
                $candidates.Add($source)
            }
            continue
        }
    }

    $selected = $null
    if ($candidates.Count -gt 0) {
        $selected = $candidates[$candidates.Count - 1]
    }

    if (-not $selected) {
        return @()
    }

    $selected = $selected.Trim()
    if ($selected -match '(?i)missing paths?\s*[:\-]\s*(?<list>.+)$') {
        $selected = $Matches.list.Trim()
    } elseif ($selected -match '(?i)missing\s*[:\-]\s*(?<list>.+)$') {
        $selected = $Matches.list.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($selected)) {
        return @()
    }

    $looksLikePathList = $selected -match '\.vi\b|\.vit\b|\.lvlibp\b|\.lvlib\b|lv_icon|LabVIEW Icon API|NIIconEditor'
    if (-not $looksLikePathList) {
        return @()
    }

    $parts = $selected -split '\s*,\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if (-not $parts -or $parts.Count -eq 0) {
        return @()
    }

    return $parts
}
