param(
    [string]$Repo = 'svelderrainruiz/labview-icon-editor',
    [string]$Ref = 'experimental/447-Sergio-Change-Number-1',
    [ValidateSet('2021')]
    [string]$LabVIEWVersion = '2021',
    [bool]$RunPester = $true,
    [int]$PollSeconds = 5,
    [int]$TimeoutMinutes = 60
)

$ErrorActionPreference = 'Stop'

function Assert-GhReady {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw 'GitHub CLI (gh) not found in PATH.'
    }

    $null = & gh auth status 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'gh auth status failed. Please authenticate with GitHub.'
    }
}

function Start-DevModeRun {
    param(
        [string]$Mode,
        [bool]$IncludePester
    )

    $startedAt = (Get-Date).ToUniversalTime()
    $args = @(
        'workflow', 'run', 'Toggle Development Mode',
        '--repo', $Repo,
        '--ref', $Ref,
        '-f', "mode=$Mode",
        '-f', "minimum_supported_lv_version=$LabVIEWVersion"
    )

    if ($IncludePester) {
        $args += @('-f', 'run_pester=true')
    }

    Write-Host ("Starting workflow: mode={0}, run_pester={1}" -f $Mode, $IncludePester)
    & gh @args | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to dispatch workflow for mode=$Mode."
    }

    return $startedAt
}

function Get-LatestRun {
    param(
        [datetime]$AfterUtc
    )

    $runs = & gh run list `
        --repo $Repo `
        --workflow 'Toggle Development Mode' `
        --branch $Ref `
        --event workflow_dispatch `
        --limit 10 `
        --json databaseId,createdAt,status,conclusion,displayTitle,htmlUrl 2>$null | ConvertFrom-Json

    $filtered = $runs | Where-Object {
        $_.createdAt -and ([datetime]$_.createdAt).ToUniversalTime() -ge $AfterUtc
    } | Sort-Object { [datetime]$_.createdAt } -Descending

    return $filtered | Select-Object -First 1
}

function Wait-ForRun {
    param(
        [datetime]$AfterUtc,
        [string]$Mode
    )

    $deadline = (Get-Date).ToUniversalTime().AddMinutes($TimeoutMinutes)
    do {
        $run = Get-LatestRun -AfterUtc $AfterUtc
        if ($run) {
            Write-Host ("Workflow run found: {0} ({1})" -f $run.databaseId, $run.htmlUrl)
            & gh run watch --repo $Repo $run.databaseId --exit-status
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                Write-Host "Run failed; fetching logs..."
                & gh run view --repo $Repo $run.databaseId --log
                throw "Workflow run failed for mode=$Mode (run id $($run.databaseId))."
            }
            return
        }

        Start-Sleep -Seconds $PollSeconds
    } while ((Get-Date).ToUniversalTime() -lt $deadline)

    throw "Timed out waiting for workflow run (mode=$Mode)."
}

Assert-GhReady

$disableStart = Start-DevModeRun -Mode 'disable' -IncludePester $false
Wait-ForRun -AfterUtc $disableStart -Mode 'disable'

$enableStart = Start-DevModeRun -Mode 'enable' -IncludePester $RunPester
Wait-ForRun -AfterUtc $enableStart -Mode 'enable'

Write-Host 'Dev mode cycle completed successfully.'
