#Requires -Version 7.0
<#
.SYNOPSIS
    Validates runner environment expectations and optionally fixes Git safe.directory.

.DESCRIPTION
    Ensures work roots exist, prints context, and sets scoped Git safe.directory
    to prevent "dubious ownership" errors when the runner service account differs
    from the checkout owner.

.PARAMETER WorkRoot
    Explicit runner work root. Defaults to LVIE_RUNNER_WORK_ROOT if set.

.PARAMETER WorktreeRoot
    Explicit worktree root. Defaults to LVIE_WORKTREE_ROOT if set.

.PARAMETER FixSafeDirectory
    Attempt to add a scoped safe.directory rule when missing.

.PARAMETER SafeDirectoryScope
    Target Git config scope for safe.directory. Defaults to System.
#>

[CmdletBinding()]
param(
    [string]$WorkRoot,
    [string]$WorktreeRoot,
    [string]$RepoRoot,
    [switch]$FixSafeDirectory = $true,
    [ValidateSet('System', 'Global')]
    [string]$SafeDirectoryScope = 'System'
)

$ErrorActionPreference = 'Stop'

function Normalize-Path {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3 -and $full.EndsWith('\')) {
        $full = $full.TrimEnd('\')
    }
    return $full
}

function Resolve-RepoRoot {
    param([string]$Path)

    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -Path $Path)) {
        return (Resolve-Path -Path $Path -ErrorAction Stop).Path
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE) -and (Test-Path -Path $env:GITHUB_WORKSPACE)) {
        return (Resolve-Path -Path $env:GITHUB_WORKSPACE -ErrorAction Stop).Path
    }

    return $null
}

function Get-LabVIEWInstallRoot {
    param([string]$Version, [string]$Bitness)

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

$resolvedWorkRoot = if ($WorkRoot) { $WorkRoot } else { $env:LVIE_RUNNER_WORK_ROOT }
$resolvedWorktreeRoot = if ($WorktreeRoot) { $WorktreeRoot } else { $env:LVIE_WORKTREE_ROOT }
$resolvedWorkRoot = Normalize-Path -Path $resolvedWorkRoot
$resolvedWorktreeRoot = Normalize-Path -Path $resolvedWorktreeRoot
$resolvedRepoRoot = Resolve-RepoRoot -Path $RepoRoot

Write-Host ("Runner check: work_root={0}" -f ($resolvedWorkRoot ?? '<unset>'))
Write-Host ("Runner check: worktree_root={0}" -f ($resolvedWorktreeRoot ?? '<unset>'))
Write-Host ("Runner check: repo_root={0}" -f ($resolvedRepoRoot ?? '<unset>'))

if ($resolvedWorkRoot -and -not (Test-Path -Path $resolvedWorkRoot)) {
    Write-Warning ("Runner work root does not exist: {0}" -f $resolvedWorkRoot)
}
if ($resolvedWorktreeRoot -and -not (Test-Path -Path $resolvedWorktreeRoot)) {
    Write-Warning ("Worktree root does not exist: {0}" -f $resolvedWorktreeRoot)
}

function Get-GitSafeDirectories {
    param([string]$Scope)
    $args = @('config')
    if ($Scope -eq 'System') { $args += '--system' }
    if ($Scope -eq 'Global') { $args += '--global' }
    $args += @('--get-all', 'safe.directory')
    try {
        & git @args 2>$null | Where-Object { $_ -and $_.Trim().Length -gt 0 }
    } catch {
        @()
    }
}

function Add-GitSafeDirectory {
    param([string]$Scope, [string]$PathPattern)
    $args = @('config')
    if ($Scope -eq 'System') { $args += '--system' }
    if ($Scope -eq 'Global') { $args += '--global' }
    $args += @('--add', 'safe.directory', $PathPattern)
    & git @args
}

if ($resolvedWorkRoot) {
    $safePattern = ($resolvedWorkRoot -replace '\\', '/') + '/*'
    $safeList = Get-GitSafeDirectories -Scope $SafeDirectoryScope
    $hasSafe = $false
    if ($safeList) {
        $hasSafe = $safeList | Where-Object { $_ -eq '*' -or $_ -eq $safePattern }
    }

    if (-not $hasSafe) {
        Write-Warning ("Git safe.directory missing for {0} (scope: {1})" -f $safePattern, $SafeDirectoryScope)
        if ($FixSafeDirectory) {
            try {
                Add-GitSafeDirectory -Scope $SafeDirectoryScope -PathPattern $safePattern
                Write-Host ("Added git safe.directory: {0} ({1})" -f $safePattern, $SafeDirectoryScope)
            } catch {
                Write-Warning ("Failed to add git safe.directory: {0}" -f $_.Exception.Message)
            }
        }
    } else {
        Write-Host ("Git safe.directory OK: {0} ({1})" -f $safePattern, $SafeDirectoryScope)
    }
}

if ($resolvedRepoRoot) {
    $assertScript = Join-Path $resolvedRepoRoot 'Tooling/Assert-LabVIEWVersion.ps1'
    if (Test-Path -Path $assertScript) {
        $lvInfo = & $assertScript -RepoRoot $resolvedRepoRoot -Context 'runner sanity'
        if ($lvInfo -and -not [string]::IsNullOrWhiteSpace($lvInfo.Year)) {
            $missing = @()
            foreach ($bitness in @('64', '32')) {
                if (-not (Get-LabVIEWInstallRoot -Version $lvInfo.Year -Bitness $bitness)) {
                    $missing += $bitness
                }
            }
            if ($missing.Count -gt 0) {
                $label = ($missing | ForEach-Object { "$_-bit" }) -join ', '
                throw "LabVIEW $($lvInfo.Year) install missing for: $label."
            }
        }
    } else {
        Write-Warning ("LabVIEW version assertion script not found at {0}; skipping version checks." -f $assertScript)
    }
} else {
    Write-Warning "Runner check: repo_root not resolved; skipping LabVIEW version checks."
}
