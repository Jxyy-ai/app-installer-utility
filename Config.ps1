<#
.SYNOPSIS
  Configuration management for the app installer utility.
  Handles INI preference storage, OFFLINE_MODE detection, and package manager availability checks.
#>

$ConfigPath = "$env:LOCALAPPDATA\AppInstallerUtility\config.ini"
$LogPath = "$env:LOCALAPPDATA\AppInstallerUtility\transcript.log"

# Ensure config directory exists
if (-not (Test-Path "$env:LOCALAPPDATA\AppInstallerUtility")) {
    [void](New-Item -ItemType Directory -Path "$env:LOCALAPPDATA\AppInstallerUtility" -Force)
}

<#
.SYNOPSIS
  Initialize or read INI config file.
#>
function Get-ConfigValue {
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        
        [string]$Default = ''
    )
    
    if (-not (Test-Path $ConfigPath)) {
        return $Default
    }
    
    $content = Get-Content $ConfigPath -Raw
    if ($content -match "$Key\s*=\s*(.+)") {
        return $matches[1].Trim()
    }
    return $Default
}

<#
.SYNOPSIS
  Write configuration value to INI file.
#>
function Set-ConfigValue {
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        
        [Parameter(Mandatory)]
        [string]$Value
    )
    
    $content = @{}
    if (Test-Path $ConfigPath) {
        Get-Content $ConfigPath | ForEach-Object {
            if ($_ -match '^([^=]+)=(.+)$') {
                $content[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
    }
    
    $content[$Key] = $Value
    
    $iniContent = $content.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Sort-Object
    $iniContent | Set-Content $ConfigPath -Force
}

<#
.SYNOPSIS
  Get preferred package manager from config or detect from environment.
#>
function Get-PreferredPackageManager {
    $stored = Get-ConfigValue -Key 'PreferredPM' -Default 'winget'
    return if ($stored -in @('winget', 'chocolatey')) { $stored } else { 'winget' }
}

<#
.SYNOPSIS
  Set preferred package manager and persist to config.
#>
function Set-PreferredPackageManager {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('winget', 'chocolatey')]
        [string]$PM
    )
    
    Set-ConfigValue -Key 'PreferredPM' -Value $PM
    Update-AppState -Property 'PreferredPM' -Value $PM
}

<#
.SYNOPSIS
  Check if WinGet is available and functional.
#>
function Test-WinGetAvailable {
    try {
        $null = winget --version 2>$null
        return $?
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
  Check if Chocolatey is available and functional.
#>
function Test-ChocolateyAvailable {
    try {
        $null = choco --version 2>$null
        return $?
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
  Check if offline mode is enabled via environment variable or config.
#>
function Get-OfflineMode {
    return $env:OFFLINE_MODE -eq '1' -or (Get-ConfigValue -Key 'OfflineMode') -eq 'true'
}

<#
.SYNOPSIS
  Update PM availability state.
#>
function Update-PMAvailability {
    $global:AppState.PMAvailable.winget = Test-WinGetAvailable
    $global:AppState.PMAvailable.chocolatey = Test-ChocolateyAvailable
    
    if (-not $global:AppState.PMAvailable.winget -and -not $global:AppState.PMAvailable.chocolatey) {
        Add-InstallLog -Message "WARNING: No package managers available. Bootstrap will be attempted." -Level 'WARN'
    }
}

<#
.SYNOPSIS
  Start transcript logging to LOCALAPPDATA.
#>
function Start-TranscriptLogging {
    try {
        Start-Transcript -Path $LogPath -Append -IncludeInvocationHeader -Force -ErrorAction SilentlyContinue
    }
    catch {
        # Silently fail if transcript can't start
    }
}

Start-TranscriptLogging
Update-PMAvailability
