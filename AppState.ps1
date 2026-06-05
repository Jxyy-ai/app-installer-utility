<#
.SYNOPSIS
  In-memory state management for the app installer utility.
  Provides thread-safe access to application state shared between UI and background workers.
#>

$global:AppState = @{
    Apps                = @{}      # Package ID -> App metadata
    SelectedApps        = @()      # Array of selected package IDs
    IsInstalling        = $false   # Installation in progress flag
    OfflineMode         = $false   # Disable all package manager operations
    PreferredPM         = 'winget' # 'winget' or 'chocolatey'
    InstallLog          = @()      # Log entries from installation
    CurrentFilterText   = ''       # Active search filter
    VisibleApps         = @()      # Filtered app list for UI binding
    PMAvailable         = @{
        winget     = $false
        chocolatey = $false
    }
    LastError           = ''       # Most recent error message
}

<#
.SYNOPSIS
  Thread-safe state update function.
#>
function Update-AppState {
    param(
        [Parameter(Mandatory)]
        [string]$Property,
        
        [Parameter(Mandatory)]
        [object]$Value
    )
    
    $global:AppState[$Property] = $Value
}

<#
.SYNOPSIS
  Get current app state property.
#>
function Get-AppState {
    param([Parameter(Mandatory)][string]$Property)
    return $global:AppState[$Property]
}

<#
.SYNOPSIS
  Add log entry to installation log.
#>
function Add-InstallLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    $global:AppState.InstallLog += $logEntry
    Write-Host $logEntry -ForegroundColor $(if ($Level -eq 'ERROR') { 'Red' } elseif ($Level -eq 'SUCCESS') { 'Green' } else { 'White' })
}

<#
.SYNOPSIS
  Clear selected apps from state.
#>
function Clear-SelectedApps {
    $global:AppState.SelectedApps = @()
}

<#
.SYNOPSIS
  Toggle app selection by package ID.
#>
function Toggle-AppSelection {
    param([Parameter(Mandatory)][string]$PackageId)
    
    if ($global:AppState.SelectedApps -contains $PackageId) {
        $global:AppState.SelectedApps = @($global:AppState.SelectedApps | Where-Object { $_ -ne $PackageId })
    }
    else {
        $global:AppState.SelectedApps += $PackageId
    }
}

export-ModuleMember -Function @(
    'Update-AppState',
    'Get-AppState',
    'Add-InstallLog',
    'Clear-SelectedApps',
    'Toggle-AppSelection'
)
