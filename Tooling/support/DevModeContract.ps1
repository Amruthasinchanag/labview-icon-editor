#Requires -Version 7.0

function Resolve-DevModeContractPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $false)]
        [string]$ContractPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ContractPath)) {
        if (Test-Path -Path $ContractPath) {
            return (Resolve-Path -Path $ContractPath).Path
        }
        return [System.IO.Path]::GetFullPath($ContractPath)
    }

    return (Join-Path -Path $RepoRoot -ChildPath 'builds\status\dev-mode.json')
}

function Initialize-DevModeContractDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContractPath
    )

    $directory = Split-Path -Path $ContractPath -Parent
    if (-not (Test-Path -Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
}

function New-DevModeContract {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    return [ordered]@{
        schemaVersion = 1
        repoRoot      = $RepoRoot
        createdUtc    = (Get-Date).ToUniversalTime().ToString('o')
        updatedUtc    = (Get-Date).ToUniversalTime().ToString('o')
        entries       = @()
    }
}

function Read-DevModeContract {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContractPath,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    if (-not (Test-Path -Path $ContractPath)) {
        return (New-DevModeContract -RepoRoot $RepoRoot)
    }

    try {
        $raw = Get-Content -Path $ContractPath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return (New-DevModeContract -RepoRoot $RepoRoot)
        }
        $contract = $raw | ConvertFrom-Json -AsHashtable
        if (-not $contract) {
            return (New-DevModeContract -RepoRoot $RepoRoot)
        }
        if (-not $contract.ContainsKey('entries')) {
            $contract.entries = @()
        }
        if (-not $contract.ContainsKey('schemaVersion')) {
            $contract.schemaVersion = 1
        }
        if (-not $contract.ContainsKey('repoRoot')) {
            $contract.repoRoot = $RepoRoot
        }
        if (-not $contract.ContainsKey('createdUtc')) {
            $contract.createdUtc = (Get-Date).ToUniversalTime().ToString('o')
        }
        return $contract
    } catch {
        return (New-DevModeContract -RepoRoot $RepoRoot)
    }
}

function Update-DevModeContractEntry {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Contract,

        [Parameter(Mandatory = $true)]
        [hashtable]$Entry
    )

    if (-not $Contract.ContainsKey('entries') -or -not $Contract.entries) {
        $Contract.entries = @()
    }

    $key = $Entry.key
    $index = -1
    for ($i = 0; $i -lt $Contract.entries.Count; $i++) {
        if ($Contract.entries[$i].key -eq $key) {
            $index = $i
            break
        }
    }

    if ($index -ge 0) {
        $Contract.entries[$index] = $Entry
    } else {
        $Contract.entries += $Entry
    }

    $Contract.updatedUtc = (Get-Date).ToUniversalTime().ToString('o')
    return $Contract
}

function Write-DevModeContract {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Contract,

        [Parameter(Mandatory = $true)]
        [string]$ContractPath
    )

    Initialize-DevModeContractDirectory -ContractPath $ContractPath
    $Contract | ConvertTo-Json -Depth 8 | Set-Content -Path $ContractPath -Encoding utf8
}

function Assert-DevModeNoProcess {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$ProcessNames = @('LabVIEW', 'g-cli')
    )

    $running = Get-Process -Name $ProcessNames -ErrorAction SilentlyContinue
    if ($running) {
        $names = $running | Select-Object -ExpandProperty ProcessName -Unique
        throw ("Refusing to toggle dev mode while running: {0}. Close these processes or pass -SkipProcessCheck." -f ($names -join ', '))
    }
}


