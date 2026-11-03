# escape=`
FROM nationalinstruments/labview:2026q1-windows
USER ContainerAdministrator

SHELL ["powershell", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
ARG PUBLIC_REPOSITORY_URL
COPY installers/ C:/installers/
RUN $installer = Start-Process C:\installers\vipm-setup.exe -ArgumentList '/exenoui','/qn' -PassThru; `
    if (-not $installer.WaitForExit(900000)) { Stop-Process -Id $installer.Id -Force; throw 'VIPM installer exceeded 15 minutes.' }; `
    if ($installer.ExitCode -notin @(0,3010)) { throw ('VIPM installer failed: ' + $installer.ExitCode) }; `
    Remove-Item C:\installers\vipm-setup.exe
COPY Tooling/Run-LUnitWindowsContainer.ps1 C:/workspace/Tooling/Run-LUnitWindowsContainer.ps1

RUN & C:\workspace\Tooling\Run-LUnitWindowsContainer.ps1 -Stage Setup -PublicRepositoryUrl $env:PUBLIC_REPOSITORY_URL; `
    if (-not (Test-Path C:\workspace\lunit-results\dependency-manifest.json)) { throw 'Required LUnit dependency manifest is missing.' }; `
    Copy-Item C:\workspace\lunit-results\dependency-manifest.json C:\lunit-dependency-manifest.json; `
    Remove-Item C:\workspace\Tooling\Run-LUnitWindowsContainer.ps1; `
    Remove-Item C:\workspace\lunit-results\Setup.log,C:\workspace\lunit-results\vipm-Settings.ini -Force

LABEL org.opencontainers.image.title="LabVIEW Icon Editor LUnit Windows dependencies"
