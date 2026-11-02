[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Setup', 'Test')]
    [string]$Stage
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$labviewRoot = 'C:\Program Files\National Instruments\LabVIEW 2026'
$labview = Join-Path $labviewRoot 'LabVIEW.exe'
$results = 'C:\workspace\lunit-results'
New-Item -ItemType Directory -Path $results -Force | Out-Null
Start-Transcript -Path (Join-Path $results "$Stage.log") -Force

function Start-TestLabVIEW {
    param([string]$Project)

    $arguments = @('--headless')
    if ($Project) {
        $arguments += "`"$Project`""
    }
    $process = Start-Process -FilePath $labview -ArgumentList $arguments -PassThru `
        -RedirectStandardOutput (Join-Path $results "labview-$Stage.log") `
        -RedirectStandardError (Join-Path $results "labview-$Stage.stderr.log")
    $deadline = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) {
            throw "LabVIEW exited with code $($process.ExitCode). See labview-$Stage logs."
        }
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $connection = $client.ConnectAsync('127.0.0.1', 3363)
            if ($connection.Wait(1000) -and $client.Connected) {
                return
            }
        }
        catch [System.AggregateException] {
            if ($_.Exception.GetBaseException() -isnot [System.Net.Sockets.SocketException]) {
                throw
            }
        }
        finally {
            $client.Dispose()
        }
        Start-Sleep -Seconds 2
    }
    throw 'LabVIEW VI Server did not become ready on port 3363 within 3 minutes.'
}

try {
    if (-not (Test-Path -LiteralPath $labview -PathType Leaf)) {
        throw "LabVIEW executable not found: $labview"
    }
    if ($Stage -eq 'Setup') {
        $env:VIPM_NONINTERACTIVE = '1'
        $env:VIPM_TIMEOUT = '900'
        $vipm = 'C:\Program Files\JKI\VI Package Manager\support\vipm.exe'
        if (-not (Test-Path -LiteralPath $vipm -PathType Leaf)) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $installer = Join-Path $env:TEMP 'vipm-setup.exe'
            Invoke-WebRequest -UseBasicParsing `
                -Uri 'https://packages.jki.net/vipm/preview/vipm-setup-latest-preview.exe' `
                -OutFile $installer
            $install = Start-Process -FilePath $installer -ArgumentList '/quiet', '/norestart' -Wait -PassThru
            if ($install.ExitCode -notin @(0, 3010)) {
                throw "VIPM installer failed with exit code $($install.ExitCode)."
            }
        }
        if (-not (Test-Path -LiteralPath $vipm -PathType Leaf)) {
            throw "VIPM executable not found after installation: $vipm"
        }
        & $vipm version
        if ($LASTEXITCODE -ne 0) { throw "vipm version failed: $LASTEXITCODE" }
        & $vipm refresh --verbose
        if ($LASTEXITCODE -ne 0) { throw "vipm refresh failed: $LASTEXITCODE" }
        Start-TestLabVIEW
        & $vipm install -y astemes_lib_lunit astemes_lib_lunit_cli --labview-version 2026 --labview-bitness 64
        if ($LASTEXITCODE -ne 0) { throw "LUnit installation failed: $LASTEXITCODE" }
        foreach ($relative in @('vi.lib\Astemes\LUnit', 'vi.lib\Astemes\LUnit CLI\LUnitCLI')) {
            $path = Join-Path $labviewRoot $relative
            if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                throw "LUnit installation missing: $path"
            }
        }
    }
    else {
        $project = 'C:\workspace\lv_icon_editor.lvproj'
        if (-not (Test-Path -LiteralPath $project -PathType Leaf)) {
            throw "Project not found: $project"
        }
        $cli = 'C:\Program Files (x86)\National Instruments\Shared\LabVIEW CLI\LabVIEWCLI.exe'
        if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) {
            throw "LabVIEW CLI executable not found: $cli"
        }
        $report = Join-Path $results 'lunit.xml'
        if (Test-Path -LiteralPath $report) { Remove-Item -LiteralPath $report -Force }
        Set-Location 'C:\workspace'
        Start-TestLabVIEW -Project $project
        & $cli -OperationName LUnit -LabVIEWPath $labview -PortNumber 3363 `
            -AdditionalOperationDirectory (Join-Path $labviewRoot 'vi.lib\Astemes\LUnit CLI') `
            -Path $project -ReportPath $report -LogToConsole TRUE -Headless
        if ($LASTEXITCODE -ne 0) { throw "LUnit CLI failed with exit code $LASTEXITCODE." }
    }
}
finally {
    Get-ChildItem -LiteralPath $env:TEMP -Filter 'lvtemporary_*.log' -File |
        Copy-Item -Destination $results -Force
    Stop-Transcript
}
