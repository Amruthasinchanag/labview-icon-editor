[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Image,

    [Parameter(Mandatory)]
    [ValidatePattern('^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?$')]
    [string]$PublicRepositoryUrl,

    [string]$Network = 'nat'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$context = Join-Path ([IO.Path]::GetTempPath()) ('lvie-lunit-image-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $context 'Tooling'), (Join-Path $context 'installers') -Force | Out-Null
try {
    # Stage only public tooling/installers, never the worktree's .git or credentials.
    Copy-Item (Join-Path $PSScriptRoot 'Run-LUnitWindowsContainer.ps1') (Join-Path $context 'Tooling')
    Copy-Item (Join-Path $PSScriptRoot 'containers\lunit-windows.Dockerfile') (Join-Path $context 'Dockerfile')
    Invoke-WebRequest -UseBasicParsing `
        -Uri 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/MinGit-2.47.1-64-bit.zip' `
        -OutFile (Join-Path $context 'installers\mingit.zip')
    Invoke-WebRequest -UseBasicParsing `
        -Uri 'https://traffic.libsyn.com/secure/jkinc/vipm-26.3.3954-windows-setup.exe' `
        -OutFile (Join-Path $context 'installers\vipm-setup.exe')
    docker build --network $Network --build-arg "PUBLIC_REPOSITORY_URL=$PublicRepositoryUrl" --tag $Image $context
    if ($LASTEXITCODE -ne 0) { throw "Required LUnit image build failed: $LASTEXITCODE" }
}
finally {
    Remove-Item -LiteralPath $context -Recurse -Force
}
