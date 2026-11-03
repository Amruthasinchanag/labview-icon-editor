[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Setup', 'Test')]
    [string]$Stage,

    [string]$PublicRepositoryUrl
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$labviewRoot = 'C:\Program Files\National Instruments\LabVIEW 2026'
$labview = Join-Path $labviewRoot 'LabVIEW.exe'
$results = 'C:\workspace\lunit-results'
New-Item -ItemType Directory -Path $results -Force | Out-Null
Start-Transcript -Path (Join-Path $results "$Stage.log") -Force
$script:labviewProcess = $null
$script:desktopProcess = $null

function Start-TestLabVIEW {
    param([string]$Project)

    $arguments = @('--headless')
    if ($Project) {
        $arguments += "`"$Project`""
    }
    $process = Start-Process -FilePath $labview -ArgumentList $arguments -PassThru `
        -RedirectStandardOutput (Join-Path $results "labview-$Stage.log") `
        -RedirectStandardError (Join-Path $results "labview-$Stage.stderr.log")
    $script:labviewProcess = $process
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

# VIPM needs its own runtime application running, not just the CLI executable.
function Initialize-VipmDesktopSettings {
    param([string]$Vipm)

    $settings = 'C:\ProgramData\JKI\VIPM\Settings.ini'
    $desktopExe = Join-Path (Split-Path (Split-Path $Vipm)) 'VI Package Manager.exe'
    if (-not (Test-Path -LiteralPath $desktopExe -PathType Leaf)) {
        throw "VIPM Desktop not found at $desktopExe"
    }
    Write-Host 'Prelaunching VIPM Desktop with global headless mode disabled.'
    $script:desktopProcess = Start-Process -FilePath $desktopExe -PassThru
    $deadline = (Get-Date).AddSeconds(120)
    while (-not (Test-Path -LiteralPath $settings -PathType Leaf)) {
        if ($script:desktopProcess.HasExited) {
            throw "VIPM Desktop exited: $($script:desktopProcess.ExitCode)"
        }
        if ((Get-Date) -ge $deadline) {
            throw 'VIPM Desktop did not initialize Settings.ini within 120 seconds.'
        }
        Start-Sleep -Seconds 3
    }
    Start-Sleep -Seconds 45
    if ($script:desktopProcess.HasExited) { throw 'VIPM Desktop exited during initialization.' }
    Save-VipmSettingsCopy
}

function Stop-SetupProcesses {
    foreach ($process in @($script:desktopProcess, $script:labviewProcess)) {
        if ($process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
            $process.WaitForExit()
        }
    }
    $script:desktopProcess = $null
    $script:labviewProcess = $null
}

function Get-LUnitPackageFiles {
    # Local-file installs resolve Community Edition eligibility from the file's
    # directory, so keep packages under the verified public repository.
    $directory = 'C:\workspace\.lunit-packages'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    # Versions and publisher checksums from the public JKI repository index.
    $packages = @(
        @{ Name = 'astemes_lib_lunit'; Version = '2.0.13.6'; MD5 = '57bc42bcfdfcf898ef5e00651992a015' }
        @{ Name = 'astemes_lib_lunit_cli'; Version = '1.7.1.32'; MD5 = '1d82a4f44e0fdb257b048e80ed2de254' }
    )
    foreach ($package in $packages) {
        $filename = '{0}-{1}.vip' -f $package.Name, $package.Version
        $path = Join-Path $directory $filename
        $url = "https://www.jkisoft.com/packages/packages/$($package.Name)/$filename"
        Write-Host "Downloading required public package: $filename"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $path -TimeoutSec 120
        $header = Get-Content -LiteralPath $path -Encoding Byte -TotalCount 4
        if ($header.Count -lt 4 -or $header[0] -ne 0x50 -or $header[1] -ne 0x4b) {
            throw "Downloaded package is not a VIP/ZIP archive: $filename"
        }
        # MD5 matches publisher metadata; HTTPS provides transport security.
        $hash = (Get-FileHash -LiteralPath $path -Algorithm MD5).Hash
        if ($hash -ne $package.MD5) { throw "Publisher checksum mismatch: $filename" }
        $path
    }
}

function Install-LUnitPackages {
    param([string]$Vipm)

    $targets = @('astemes_lib_lunit', 'astemes_lib_lunit_cli')
    $usingFiles = $false
    # Resolution fallback and engine recovery each get their own bounded budget.
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        Write-Host "LUnit installation attempt $attempt/2"
        & $Vipm install -y @targets `
            --labview-version 2026 --labview-bitness 64 --timeout 240 --verbose --show-progress
        $code = $LASTEXITCODE
        if ($code -eq 3 -and -not $usingFiles) {
            Write-Warning 'VIPM name lookup failed; installing verified public VIP files instead.'
            $targets = @(Get-LUnitPackageFiles)
            if ($targets.Count -ne 2) { throw 'Expected both required LUnit package files.' }
            $usingFiles = $true
            & $Vipm install -y @targets --labview-version 2026 --labview-bitness 64 `
                --timeout 240 --verbose --show-progress
            $code = $LASTEXITCODE
        }
        if ($code -eq 0) { return }
        if ($code -ne 124 -or $attempt -eq 2) {
            throw "Required LUnit installation failed: $code (attempt $attempt/2)."
        }
        Write-Warning 'VIPM timed out; restarting the owned VIPM/LabVIEW stack once.'
        Stop-SetupProcesses
        Start-Sleep -Seconds 5
        Start-TestLabVIEW
        Initialize-VipmDesktopSettings -Vipm $Vipm
    }
}

function Refresh-VipmPackages {
    param([string]$Vipm)

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        & $Vipm refresh --timeout 120 --verbose
        $code = $LASTEXITCODE
        if ($code -eq 0) { return }
        if ($code -ne 124 -or $attempt -eq 2) {
            throw "VIPM refresh failed: $code (attempt $attempt/2)."
        }
        Write-Warning 'VIPM refresh timed out; restarting the owned stack once.'
        Stop-SetupProcesses
        Start-Sleep -Seconds 5
        Start-TestLabVIEW
        Initialize-VipmDesktopSettings -Vipm $Vipm
    }
}

# Uploaded artifacts are not secret-masked, so blank any licence-related values in the diagnostic copy.
function Save-VipmSettingsCopy {
    Get-Content -LiteralPath 'C:\ProgramData\JKI\VIPM\Settings.ini' |
        ForEach-Object { $_ -replace '^([^=]*(?i:serial|licen|activation|e-?mail|full ?name)[^=]*)=.*$', '$1="<redacted>"' } |
        Set-Content -LiteralPath (Join-Path $results 'vipm-Settings.ini') -Encoding Ascii
}

# VIPM Desktop was closed during its first launch, so mark first-run as done; otherwise the next launch
# (by `vipm install`) can wait on first-run UI that nobody can answer in a headless container.
function Set-VipmFirstLaunchDone {
    $settings = 'C:\ProgramData\JKI\VIPM\Settings.ini'
    $lines = [System.Collections.Generic.List[string]](Get-Content -LiteralPath $settings)
    $index = $lines.FindIndex([Predicate[string]] { param($line) $line -match '^IsFirstLaunch=' })
    if ($index -ge 0) {
        $lines[$index] = 'IsFirstLaunch="FALSE"'
    }
    else {
        $general = $lines.IndexOf('[General]')
        if ($general -lt 0) {
            $lines.Insert(0, '[General]')
            $general = 0
        }
        $lines.Insert($general + 1, 'IsFirstLaunch="FALSE"')
    }
    $lines | Set-Content -LiteralPath $settings -Encoding Ascii
    Save-VipmSettingsCopy
}

try {
    if (-not (Test-Path -LiteralPath $labview -PathType Leaf)) {
        throw "LabVIEW executable not found: $labview"
    }
    if ($Stage -eq 'Setup') {
        $ini = Join-Path $labviewRoot 'LabVIEW.ini'
        $lines = @(Get-Content -LiteralPath $ini)
        foreach ($setting in @('server.tcp.enabled=True', 'server.tcp.port=3363', 'server.tcp.access=+127.0.0.1', 'server.vi.access=+*')) {
            $key = $setting.Split('=')[0]
            $lines = @($lines | Where-Object { $_ -notmatch ('^\s*' + [regex]::Escape($key) + '\s*=') })
            $lines += $setting
        }
        $lines | Set-Content -LiteralPath $ini -Encoding Ascii
        # Do not bake Pro activation or user identity into a distributable image.
        if ($PublicRepositoryUrl -and -not [string]::IsNullOrWhiteSpace($env:VIPM_SERIAL_NUMBER)) {
            throw 'Dependency image builds must not receive VIPM Pro credentials.'
        }
        Remove-Item Env:LV_RTE_HEADLESS -ErrorAction SilentlyContinue
        $env:VIPM_NONINTERACTIVE = '1'
        $env:VIPM_TIMEOUT = '240'
        $env:VIPM_DESKTOP_LIVELINESS_TIMEOUT = '120'
        $env:VIPM_LABVIEW_LAUNCH_TIMEOUT = '120'
        # With the VIPM Pro secrets, activate Pro (JKI's documented container path). Without them, fall back to
        # Community Edition, which needs no serial but only applies inside a public git repository, so git must
        # be available and VIPM must run from the checkout. A fresh Windows VIPM with neither rejects `refresh`.
        $activatePro = -not [string]::IsNullOrWhiteSpace($env:VIPM_SERIAL_NUMBER)
        if (-not $activatePro) {
            $env:VIPM_COMMUNITY_EDITION = '1'
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            $gitZip = 'C:\installers\mingit.zip'
            if (-not (Test-Path -LiteralPath $gitZip)) {
                $gitZip = Join-Path $env:TEMP 'mingit.zip'
                Invoke-WebRequest -UseBasicParsing `
                    -Uri 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/MinGit-2.47.1-64-bit.zip' `
                    -OutFile $gitZip
            }
            Expand-Archive -Path $gitZip -DestinationPath 'C:\mingit' -Force
            Remove-Item -LiteralPath $gitZip -Force
            $env:PATH = "C:\mingit\cmd;$env:PATH"
        }
        # The bind-mounted checkout is owned by a different account, which git otherwise refuses to read.
        git config --global --add safe.directory C:/workspace
        if ($LASTEXITCODE -ne 0) { throw "git config failed: $LASTEXITCODE" }
        Set-Location 'C:\workspace'
        if ($PublicRepositoryUrl) {
            if ($PublicRepositoryUrl -notmatch '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?$') {
                throw 'PublicRepositoryUrl must be an HTTPS GitHub repository URL.'
            }
            git init .
            if ($LASTEXITCODE -ne 0) { throw "git init failed: $LASTEXITCODE" }
            git remote add origin $PublicRepositoryUrl
            if ($LASTEXITCODE -ne 0) { throw "git remote add failed: $LASTEXITCODE" }
        }
        git remote -v
        if ($LASTEXITCODE -ne 0) { throw "git cannot read the checkout at C:\workspace: $LASTEXITCODE" }

        $findVipm = {
            Get-ChildItem -Path $env:ProgramFiles, ${env:ProgramFiles(x86)} -Filter vipm.exe -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty FullName
        }
        $vipm = & $findVipm
        if (-not $vipm) {
            $installer = 'C:\installers\vipm-setup.exe'
            if (-not (Test-Path -LiteralPath $installer)) {
                $installer = Join-Path $env:TEMP 'vipm-setup.exe'
                Invoke-WebRequest -UseBasicParsing `
                    -Uri 'https://traffic.libsyn.com/secure/jkinc/vipm-26.3.3954-windows-setup.exe' `
                    -OutFile $installer
            }
            $install = Start-Process -FilePath $installer -ArgumentList '/exenoui', '/qn' -Wait -PassThru
            Remove-Item -LiteralPath $installer -Force
            if ($install.ExitCode -notin @(0, 3010)) {
                throw "VIPM installer failed with exit code $($install.ExitCode)."
            }
            $vipm = & $findVipm
        }
        if (-not $vipm) {
            throw 'vipm.exe not found under Program Files after installation.'
        }
        Write-Host "Using VIPM CLI at: $vipm"
        & $vipm version
        if ($LASTEXITCODE -ne 0) { throw "vipm version failed: $LASTEXITCODE" }
        if ($activatePro) {
            Write-Host 'Activating VIPM Pro from the VIPM_* secrets'
            & $vipm activate --serial-number $env:VIPM_SERIAL_NUMBER --name $env:VIPM_FULL_NAME --email $env:VIPM_EMAIL
            if ($LASTEXITCODE -ne 0) { throw "vipm activate failed: $LASTEXITCODE" }
        }
        else {
            Write-Host 'VIPM_SERIAL_NUMBER not set; using VIPM Community Edition'
        }
        & $vipm about
        Start-TestLabVIEW
        Initialize-VipmDesktopSettings -Vipm $vipm
        Stop-SetupProcesses
        Set-VipmFirstLaunchDone
        Start-TestLabVIEW
        Initialize-VipmDesktopSettings -Vipm $vipm
        Refresh-VipmPackages -Vipm $vipm
        Install-LUnitPackages -Vipm $vipm
        foreach ($relative in @('vi.lib\Astemes\LUnit', 'vi.lib\Astemes\LUnit CLI\LUnitCLI')) {
            $path = Join-Path $labviewRoot $relative
            if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                throw "LUnit installation missing: $path"
            }
            [ordered]@{
                labviewVersion = (Get-Item -LiteralPath $labview).VersionInfo.FileVersion
                frameworkPath = Join-Path $labviewRoot 'vi.lib\Astemes\LUnit'
                operationPath = Join-Path $labviewRoot 'vi.lib\Astemes\LUnit CLI\LUnitCLI'
                packages = @('astemes_lib_lunit', 'astemes_lib_lunit_cli')
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $results 'dependency-manifest.json') -Encoding UTF8
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
    Stop-SetupProcesses
    Get-ChildItem -LiteralPath $env:TEMP -Filter 'lvtemporary_*.log' -File |
        Copy-Item -Destination $results -Force
    Stop-Transcript
}
