<#
.SYNOPSIS
  App Installer Utility - Windows desktop one-click batch software installation tool.
  Requires administrative elevation and uses WinGet (primary) or Chocolatey (fallback).

.DESCRIPTION
  Provides a curated app catalog with WPF UI, batch/single-app install, silent execution,
  real-time search, and offline mode support. Supports headless JSON config mode.

.PARAMETER ConfigPath
  Path to JSON config file for headless mode (no UI). Must contain 'apps' array of package IDs.

.PARAMETER OfflineMode
  Disables all package manager operations and install tab.

.EXAMPLE
  .\Main.ps1
  # Launch interactive UI with admin check

.EXAMPLE
  .\Main.ps1 -ConfigPath "C:\Users\user\install-config.json"
  # Headless install from config, no UI launched

.REQUIRES
  PowerShell 7.4+ (LTS) or 7.5.7+ (STS)
  Windows 10 / Windows 11
  Administrator privileges
#>

param(
    [string]$ConfigPath,
    [switch]$OfflineMode
)

$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

# Ensure admin elevation
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This utility requires administrator privileges. Restarting elevated..." -ForegroundColor Red
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"& {Set-Location '$PWD'; & '$PSCommandPath' -ConfigPath '$ConfigPath' -OfflineMode:`$$OfflineMode}`"" -Verb RunAs
    exit
}

# Load modules and functions
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptRoot\AppState.ps1"
. "$ScriptRoot\Config.ps1"
. "$ScriptRoot\Installer.ps1"

# Initialize state
$global:AppState = @{
    Apps = @{}
    SelectedApps = @()
    IsInstalling = $false
    OfflineMode = $OfflineMode -or $env:OFFLINE_MODE -eq '1'
    PreferredPM = Get-PreferredPackageManager
    InstallLog = @()
}

Write-Host "[INFO] App Installer Utility initialized" -ForegroundColor Green

# Headless mode
if ($ConfigPath) {
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "[ERROR] Config file not found: $ConfigPath" -ForegroundColor Red
        exit 1
    }

    try {
        $config = Get-Content $ConfigPath | ConvertFrom-Json
        $appsToInstall = $config.apps | Where-Object { $_ }

        if (-not $appsToInstall) {
            Write-Host "[ERROR] No apps specified in config" -ForegroundColor Red
            exit 1
        }

        Write-Host "[INFO] Running headless install for $($appsToInstall.Count) app(s)" -ForegroundColor Cyan
        
        if ($global:AppState.OfflineMode) {
            Write-Host "[ERROR] OFFLINE_MODE enabled. Cannot install packages." -ForegroundColor Red
            exit 1
        }

        Install-Applications -PackageIds $appsToInstall -PreferredPM $global:AppState.PreferredPM
        Write-Host "[SUCCESS] Headless install completed" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Headless mode failed: $_" -ForegroundColor Red
        exit 1
    }
    exit 0
}

# Interactive UI mode
Write-Host "[INFO] Launching WPF UI..." -ForegroundColor Cyan
. "$ScriptRoot\MainWindow.xaml.ps1"
