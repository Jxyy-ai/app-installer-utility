[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AppInstallerUtility')
)

$ErrorActionPreference = 'Stop'
$repositoryArchiveUrl = 'https://github.com/Jxyy-ai/app-installer-utility/archive/refs/heads/main.zip'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('AppInstallerUtility-' + [Guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $tempRoot 'app-installer-utility.zip'

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Invoke-WebRequest -Uri $repositoryArchiveUrl -OutFile $archivePath
    Expand-Archive -Path $archivePath -DestinationPath $tempRoot -Force

    $extractedRoot = Join-Path $tempRoot 'app-installer-utility-main'
    if (-not (Test-Path (Join-Path $extractedRoot 'Main.ps1'))) {
        throw 'The downloaded project archive does not contain Main.ps1.'
    }

    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $extractedRoot '*') -Destination $InstallRoot -Recurse -Force

    $mainScript = Join-Path $InstallRoot 'Main.ps1'
    Start-Process -FilePath 'pwsh' -ArgumentList @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $mainScript
    ) | Out-Null
}
catch {
    Write-Error "App Installer Utility setup failed: $($_.Exception.Message)"
    exit 1
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
