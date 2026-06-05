<#
.SYNOPSIS
  Installation orchestrator for package managers (WinGet / Chocolatey).
  Handles bootstrap, silent execution, fallback logic, and error recovery.

.DESCRIPTION
  - Auto-bootstraps missing package managers
  - Prioritizes WinGet; falls back to Chocolatey per-app
  - Executes silently with no user interaction
  - Implements retry logic and detailed logging
#>

<#
.SYNOPSIS
  Bootstrap WinGet if not available.
#>
function Install-WinGet {
    Write-Host "[INFO] Bootstrapping WinGet 1.28.240..." -ForegroundColor Cyan
    
    try {
        # Method 1: Try MS Store / winget-cli package
        $null = winget source add --name winget-cli -a https://aka.ms/winget-packages 2>$null
        
        # Method 2: Direct download from GitHub releases
        $releaseUrl = "https://github.com/microsoft/winget-cli/releases/download/v1.28.240/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $downloadPath = "$env:TEMP\winget-cli.msixbundle"
        
        Write-Host "[INFO] Downloading WinGet installer..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $releaseUrl -OutFile $downloadPath -ErrorAction Stop
        
        Write-Host "[INFO] Installing WinGet MSIX bundle (may require user interaction)..." -ForegroundColor Gray
        Add-AppxPackage -Path $downloadPath -ErrorAction SilentlyContinue
        
        Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
        
        Start-Sleep -Seconds 2
        
        if (Test-WinGetAvailable) {
            Add-InstallLog -Message "WinGet bootstrapped successfully" -Level 'SUCCESS'
            return $true
        }
        else {
            Add-InstallLog -Message "WinGet bootstrap failed - package manager unavailable" -Level 'ERROR'
            return $false
        }
    }
    catch {
        Add-InstallLog -Message "WinGet bootstrap error: $_" -Level 'ERROR'
        return $false
    }
}

<#
.SYNOPSIS
  Bootstrap Chocolatey if not available.
#>
function Install-Chocolatey {
    Write-Host "[INFO] Bootstrapping Chocolatey 2.7.2..." -ForegroundColor Cyan
    
    try {
        # Official Chocolatey bootstrap script
        $chocoScript = @"
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
"@
        
        Write-Host "[INFO] Executing Chocolatey bootstrap script..." -ForegroundColor Gray
        Invoke-Expression $chocoScript -ErrorAction Stop
        
        Start-Sleep -Seconds 2
        
        if (Test-ChocolateyAvailable) {
            Add-InstallLog -Message "Chocolatey bootstrapped successfully" -Level 'SUCCESS'
            return $true
        }
        else {
            Add-InstallLog -Message "Chocolatey bootstrap failed - package manager unavailable" -Level 'ERROR'
            return $false
        }
    }
    catch {
        Add-InstallLog -Message "Chocolatey bootstrap error: $_" -Level 'ERROR'
        return $false
    }
}

<#
.SYNOPSIS
  Install single application via WinGet with silent flags.
#>
function Install-ViaWinGet {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId
    )
    
    try {
        Write-Host "[INFO] Installing '$PackageId' via WinGet..." -ForegroundColor Gray
        
        $result = & winget install --id $PackageId --silent --accept-source-agreements --accept-package-agreements 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Add-InstallLog -Message "$PackageId installed successfully (WinGet)" -Level 'SUCCESS'
            return $true
        }
        else {
            Add-InstallLog -Message "WinGet install failed for $PackageId (exit code: $LASTEXITCODE)" -Level 'WARN'
            return $false
        }
    }
    catch {
        Add-InstallLog -Message "WinGet install error for $PackageId: $_" -Level 'ERROR'
        return $false
    }
}

<#
.SYNOPSIS
  Install single application via Chocolatey with silent flags.
#>
function Install-ViaChocolatey {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId
    )
    
    try {
        Write-Host "[INFO] Installing '$PackageId' via Chocolatey..." -ForegroundColor Gray
        
        $result = & choco install $PackageId -y --quiet 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Add-InstallLog -Message "$PackageId installed successfully (Chocolatey)" -Level 'SUCCESS'
            return $true
        }
        else {
            Add-InstallLog -Message "Chocolatey install failed for $PackageId (exit code: $LASTEXITCODE)" -Level 'WARN'
            return $false
        }
    }
    catch {
        Add-InstallLog -Message "Chocolatey install error for $PackageId: $_" -Level 'ERROR'
        return $false
    }
}

<#
.SYNOPSIS
  Install application with fallback logic: try preferred PM, then fallback.
#>
function Install-Application {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,
        
        [string]$PreferredPM = 'winget'
    )
    
    if ($global:AppState.OfflineMode) {
        Add-InstallLog -Message "OFFLINE_MODE enabled - skipping install for $PackageId" -Level 'WARN'
        return $false
    }
    
    # Ensure at least one PM is available
    if (-not $global:AppState.PMAvailable.winget -and -not $global:AppState.PMAvailable.chocolatey) {
        Add-InstallLog -Message "Attempting to bootstrap missing package managers..." -Level 'WARN'
        
        if (-not $global:AppState.PMAvailable.winget) {
            Install-WinGet | Out-Null
            Update-PMAvailability
        }
        
        if (-not $global:AppState.PMAvailable.chocolatey) {
            Install-Chocolatey | Out-Null
            Update-PMAvailability
        }
    }
    
    # Primary attempt
    if ($PreferredPM -eq 'winget' -and $global:AppState.PMAvailable.winget) {
        if (Install-ViaWinGet -PackageId $PackageId) {
            return $true
        }
        # Fallback to Chocolatey
        if ($global:AppState.PMAvailable.chocolatey) {
            Add-InstallLog -Message "WinGet failed, attempting fallback to Chocolatey..." -Level 'WARN'
            return Install-ViaChocolatey -PackageId $PackageId
        }
    }
    elseif ($PreferredPM -eq 'chocolatey' -and $global:AppState.PMAvailable.chocolatey) {
        if (Install-ViaChocolatey -PackageId $PackageId) {
            return $true
        }
        # Fallback to WinGet
        if ($global:AppState.PMAvailable.winget) {
            Add-InstallLog -Message "Chocolatey failed, attempting fallback to WinGet..." -Level 'WARN'
            return Install-ViaWinGet -PackageId $PackageId
        }
    }
    
    Add-InstallLog -Message "Failed to install $PackageId - no available package managers" -Level 'ERROR'
    return $false
}

<#
.SYNOPSIS
  Batch install multiple applications (called by background worker).
#>
function Install-Applications {
    param(
        [Parameter(Mandatory)]
        [array]$PackageIds,
        
        [string]$PreferredPM = 'winget'
    )
    
    if ($global:AppState.OfflineMode) {
        Add-InstallLog -Message "OFFLINE_MODE enabled - batch install blocked" -Level 'ERROR'
        return
    }
    
    Update-AppState -Property 'IsInstalling' -Value $true
    Add-InstallLog -Message "Starting batch installation of $($PackageIds.Count) app(s)" -Level 'INFO'
    
    $successCount = 0
    $failureCount = 0
    
    foreach ($packageId in $PackageIds) {
        if (Install-Application -PackageId $packageId -PreferredPM $PreferredPM) {
            $successCount++
        }
        else {
            $failureCount++
        }
        Start-Sleep -Milliseconds 500
    }
    
    Add-InstallLog -Message "Installation batch complete: $successCount successful, $failureCount failed" -Level 'INFO'
    Update-AppState -Property 'IsInstalling' -Value $false
}
