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

# `vipm install` reads the LabVIEW target list from VIPM Desktop's Settings.ini, which only exists after
# VIPM Desktop has run once. A silent install never runs it, so start it once to create the file and,
# if it still does not appear, write a minimal one that targets this container's LabVIEW.
function Initialize-VipmDesktopSettings {
    param([string]$Vipm)

    $settings = 'C:\ProgramData\JKI\VIPM\Settings.ini'
    if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) {
        $desktopExe = Join-Path (Split-Path (Split-Path $Vipm)) 'VI Package Manager.exe'
        if (Test-Path -LiteralPath $desktopExe -PathType Leaf) {
            Write-Host "Starting VIPM Desktop once to create $settings"
            $desktop = Start-Process -FilePath $desktopExe -PassThru
            $deadline = (Get-Date).AddMinutes(3)
            while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $settings -PathType Leaf) -and -not $desktop.HasExited) {
                Start-Sleep -Seconds 5
            }
            Start-Sleep -Seconds 5
            if (-not $desktop.HasExited) {
                Stop-Process -Id $desktop.Id -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            Write-Warning "VIPM Desktop not found at $desktopExe"
        }
    }

    $version = (Get-Item -LiteralPath $labview).VersionInfo
    $target = '{0}.{1} (64-bit)' -f $version.FileMajorPart, $version.FileMinorPart
    if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) {
        Write-Warning "VIPM Desktop did not create $settings; writing a minimal one for LabVIEW $target."
        New-Item -ItemType Directory -Path (Split-Path $settings) -Force | Out-Null
        $location = '/' + ($labview -replace '\\', '/' -replace '^([A-Za-z]):', '$1')
        @(
            '[General]'
            'IsFirstLaunch="FALSE"'
            ''
            '[Targets]'
            'Names.<size(s)>="1"'
            'Names 0="LabVIEW"'
            'Versions.<size(s)>="1"'
            "Versions 0=`"$target`""
            'Locations.<size(s)>="1"'
            "Locations 0=`"$location`""
            'Ports="<size(s)=1> 3363"'
            'Tested.<size(s)>="1"'
            'Tested 0="TRUE"'
            'Disabled.<size(s)>="1"'
            'Disabled 0="FALSE"'
            'Connection Timeout="120"'
            'Active Target.Name="LabVIEW"'
            "Active Target.Version=`"$target`""
            'CommunityEdition.<size(s)>="1"'
            'CommunityEdition 0="FALSE"'
        ) | Set-Content -LiteralPath $settings -Encoding Ascii
    }
    Copy-Item -LiteralPath $settings -Destination (Join-Path $results 'vipm-Settings.ini') -Force
}

try {
    if (-not (Test-Path -LiteralPath $labview -PathType Leaf)) {
        throw "LabVIEW executable not found: $labview"
    }
    if ($Stage -eq 'Setup') {
        $env:VIPM_NONINTERACTIVE = '1'
        $env:VIPM_TIMEOUT = '900'
        # Without an edition, a fresh Windows VIPM rejects `refresh` as unactivated. Community Edition needs
        # no serial number, but only applies inside a public git repository, so git must be available and
        # VIPM must run from the checkout.
        $env:VIPM_COMMUNITY_EDITION = '1'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            $gitZip = Join-Path $env:TEMP 'mingit.zip'
            Invoke-WebRequest -UseBasicParsing `
                -Uri 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/MinGit-2.47.1-64-bit.zip' `
                -OutFile $gitZip
            Expand-Archive -Path $gitZip -DestinationPath 'C:\mingit' -Force
            Remove-Item -LiteralPath $gitZip -Force
            $env:PATH = "C:\mingit\cmd;$env:PATH"
        }
        # The bind-mounted checkout is owned by a different account, which git otherwise refuses to read.
        git config --global --add safe.directory '*'
        if ($LASTEXITCODE -ne 0) { throw "git config failed: $LASTEXITCODE" }
        Set-Location 'C:\workspace'
        git remote -v
        if ($LASTEXITCODE -ne 0) { throw "git cannot read the checkout at C:\workspace: $LASTEXITCODE" }

        $findVipm = {
            Get-ChildItem -Path $env:ProgramFiles, ${env:ProgramFiles(x86)} -Filter vipm.exe -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty FullName
        }
        $vipm = & $findVipm
        if (-not $vipm) {
            $installer = Join-Path $env:TEMP 'vipm-setup.exe'
            Invoke-WebRequest -UseBasicParsing `
                -Uri 'https://traffic.libsyn.com/secure/jkinc/vipm-26.3.4025-windows-setup.exe' `
                -OutFile $installer
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
        & $vipm about
        & $vipm refresh --verbose
        if ($LASTEXITCODE -ne 0) { throw "vipm refresh failed: $LASTEXITCODE" }
        Start-TestLabVIEW
        Initialize-VipmDesktopSettings -Vipm $vipm
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
