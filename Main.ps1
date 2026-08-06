<#
.SYNOPSIS
  App Installer Utility - Windows desktop one-click batch software installation tool.
  Requires administrative elevation and uses WinGet (primary) or Chocolatey (fallback).

.DESCRIPTION
  Provides a curated app catalog with WPF UI, batch/single-app install, silent execution,
  and real-time search. Supports headless JSON config mode.

.PARAMETER ConfigPath
  Path to JSON config file for headless mode (no UI). Must contain 'apps' array of package IDs.

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
    [string]$ConfigPath
)

$HeadlessConfigPath = $ConfigPath

$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

# Ensure admin elevation
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This utility requires administrator privileges. Restarting elevated..." -ForegroundColor Red
    $launchArgs = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        "`"$PSCommandPath`""
    )

    if ($ConfigPath) {
        $launchArgs += @('-ConfigPath', "`"$ConfigPath`"")
    }

    Start-Process pwsh -ArgumentList $launchArgs -Verb RunAs
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
    PreferredPM = Get-PreferredPackageManager
    InstallLog = @()
}

Write-Host "[INFO] App Installer Utility initialized" -ForegroundColor Green

# Headless mode
if ($HeadlessConfigPath) {
    if (-not (Test-Path $HeadlessConfigPath)) {
        Write-Host "[ERROR] Config file not found: $HeadlessConfigPath" -ForegroundColor Red
        exit 1
    }

    try {
        $config = Get-Content $HeadlessConfigPath | ConvertFrom-Json
        $appsToInstall = $config.apps | Where-Object { $_ }

        if (-not $appsToInstall) {
            Write-Host "[ERROR] No apps specified in config" -ForegroundColor Red
            exit 1
        }

        Write-Host "[INFO] Running headless install for $($appsToInstall.Count) app(s)" -ForegroundColor Cyan
        
        $catalogPath = "$ScriptRoot\AppCatalog.json"
        $catalogApps = @{}
        if (Test-Path $catalogPath) {
            $catalog = Get-Content $catalogPath | ConvertFrom-Json
            foreach ($category in $catalog.categories) {
                foreach ($app in $category.apps) {
                    $catalogApps[$app.packageId] = $app
                    $catalogApps[$app.wingetId] = $app
                    $catalogApps[$app.chocoId] = $app
                }
            }
        }

        $installSpecs = foreach ($appId in $appsToInstall) {
            if ($catalogApps.ContainsKey($appId)) {
                $catalogApp = $catalogApps[$appId]
                [pscustomobject]@{
                    name = $catalogApp.name
                    packageId = $catalogApp.packageId
                    wingetId = if ($catalogApp.wingetId) { $catalogApp.wingetId } else { $catalogApp.packageId }
                    chocoId = if ($catalogApp.chocoId) { $catalogApp.chocoId } else { $catalogApp.packageId }
                }
            }
            else {
                [pscustomobject]@{
                    name = $appId
                    packageId = $appId
                    wingetId = $appId
                    chocoId = $appId
                }
            }
        }

        Install-Applications -Packages $installSpecs -PreferredPM $global:AppState.PreferredPM
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
