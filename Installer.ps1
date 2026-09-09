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
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Add-InstallLog -Message 'Cannot bootstrap WinGet from an unelevated process.' -Level 'ERROR'
        return $false
    }

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
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Add-InstallLog -Message 'Cannot bootstrap Chocolatey from an unelevated process.' -Level 'ERROR'
        return $false
    }

    Write-Host "[INFO] Bootstrapping Chocolatey 2.7.2..." -ForegroundColor Cyan

    $chocoExe = Join-Path $env:ProgramData 'chocolatey\bin\choco.exe'
    if (Test-ChocolateyAvailable) {
        Add-InstallLog -Message "Chocolatey already available, skipping bootstrap" -Level 'INFO'
        return $true
    }
    if (Test-Path $chocoExe) {
        $chocoDir = Split-Path $chocoExe -Parent
        if (-not ($env:Path -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ieq $chocoDir })) {
            $env:Path = "$($env:Path);$chocoDir"
        }
        try {
            $null = & $chocoExe --version 2>$null
            if ($?) {
                Add-InstallLog -Message "Chocolatey executable found on disk; using existing installation" -Level 'INFO'
                return $true
            }
        }
        catch {
            Add-InstallLog -Message "Chocolatey executable exists but version check failed; proceeding with bootstrap" -Level 'WARN'
        }
    }

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
        elseif (Test-Path $chocoExe) {
            Add-InstallLog -Message "Chocolatey bootstrap script detected an existing installation; using existing Chocolatey" -Level 'INFO'
            return $true
        }
        else {
            Add-InstallLog -Message "Chocolatey bootstrap failed - package manager unavailable" -Level 'ERROR'
            return $false
        }
    }
    catch {
        Add-InstallLog -Message "Chocolatey bootstrap error: $_" -Level 'ERROR'
        if (Test-ChocolateyAvailable) {
            Add-InstallLog -Message "Chocolatey is available after bootstrap error; using existing installation" -Level 'INFO'
            return $true
        }
        elseif (Test-Path $chocoExe) {
            Add-InstallLog -Message "Chocolatey executable exists after bootstrap error; using existing installation" -Level 'INFO'
            return $true
        }
        return $false
    }
}

function Cleanup-InstallerArtifacts {
    $paths = @(
        "$env:TEMP\winget-cli.msixbundle",
        "$env:ProgramData\chocolatey\backup"
    )

    foreach ($path in $paths) {
        try {
            if (Test-Path $path) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                Add-InstallLog -Message "Removed installer artifact: $path" -Level 'INFO'
            }
        }
        catch {
            Add-InstallLog -Message "Failed to remove installer artifact ${path}: $_" -Level 'WARN'
        }
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
        $resultText = ($result | Out-String).Trim()
        
        if ($LASTEXITCODE -eq 0) {
            Add-InstallLog -Message "$PackageId installed successfully (WinGet)" -Level 'SUCCESS'
            return $true
        }
        elseif ($resultText -match 'already installed|No available upgrade found|No newer package versions are available') {
            Add-InstallLog -Message "$PackageId is already installed and up to date (WinGet)" -Level 'SUCCESS'
            return $true
        }
        else {
            Add-InstallLog -Message "WinGet install failed for $PackageId (exit code: $LASTEXITCODE)" -Level 'WARN'
            if ($resultText) {
                Add-InstallLog -Message "WinGet output for ${PackageId}: $resultText" -Level 'WARN'
            }
            return $false
        }
    }
    catch {
        Add-InstallLog -Message "WinGet install error for ${PackageId}: $_" -Level 'ERROR'
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
        Add-InstallLog -Message "Chocolatey install error for ${PackageId}: $_" -Level 'ERROR'
        return $false
    }
}

<#
.SYNOPSIS
  Uninstall single application via WinGet.
#>
function Uninstall-ViaWinGet {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId
    )

    try {
        Write-Host "[INFO] Uninstalling '$PackageId' via WinGet..." -ForegroundColor Gray

        $result = & winget uninstall --id $PackageId --exact --silent --accept-source-agreements 2>&1
        $resultText = ($result | Out-String).Trim()

        if ($LASTEXITCODE -eq 0) {
            Add-InstallLog -Message "$PackageId uninstalled successfully (WinGet)" -Level 'SUCCESS'
            return $true
        }
        elseif ($resultText -match 'No installed package found|No package found|not installed') {
            Add-InstallLog -Message "$PackageId is not installed (WinGet)" -Level 'SUCCESS'
            return $true
        }
        elseif ($resultText -match 'Multiple versions of this package are installed') {
            Add-InstallLog -Message "Multiple versions found for $PackageId. Retrying uninstall with --all-versions..." -Level 'WARN'

            $retryResult = & winget uninstall --id $PackageId --exact --all-versions --silent --accept-source-agreements 2>&1
            $retryText = ($retryResult | Out-String).Trim()

            if ($LASTEXITCODE -eq 0) {
                Add-InstallLog -Message "$PackageId uninstalled successfully from all versions (WinGet)" -Level 'SUCCESS'
                return $true
            }
            elseif ($retryText -match 'No installed package found|No package found|not installed') {
                Add-InstallLog -Message "$PackageId is not installed (WinGet)" -Level 'SUCCESS'
                return $true
            }

            Add-InstallLog -Message "WinGet uninstall all-versions failed for $PackageId (exit code: $LASTEXITCODE)" -Level 'WARN'
            if ($retryText) {
                Add-InstallLog -Message "WinGet output for ${PackageId}: $retryText" -Level 'WARN'
            }
            return $false
        }
        elseif ($resultText -match 'Unknown option|unrecognized option|invalid argument|unexpected token') {
            Add-InstallLog -Message "WinGet uninstall flags not accepted for $PackageId; retrying without --silent..." -Level 'WARN'
            $result = & winget uninstall --id $PackageId --exact --accept-source-agreements 2>&1
            $resultText = ($result | Out-String).Trim()

            if ($LASTEXITCODE -eq 0) {
                Add-InstallLog -Message "$PackageId uninstalled successfully (WinGet, non-silent)" -Level 'SUCCESS'
                return $true
            }
            elseif ($resultText -match 'No installed package found|No package found|not installed') {
                Add-InstallLog -Message "$PackageId is not installed (WinGet)" -Level 'SUCCESS'
                return $true
            }
        }
        else {
            Add-InstallLog -Message "WinGet uninstall failed for $PackageId (exit code: $LASTEXITCODE)" -Level 'WARN'
            if ($resultText) {
                Add-InstallLog -Message "WinGet output for ${PackageId}: $resultText" -Level 'WARN'
            }
        }

        if ($resultText -match 'Uninstall failed with exit code: 1603|Error 1603') {
            Add-InstallLog -Message "Retrying WinGet uninstall for $PackageId with --all-versions after 1603 failure..." -Level 'WARN'
            $retryResult = & winget uninstall --id $PackageId --exact --all-versions --silent --accept-source-agreements 2>&1
            $retryText = ($retryResult | Out-String).Trim()

            if ($LASTEXITCODE -eq 0) {
                Add-InstallLog -Message "$PackageId uninstalled successfully from all versions (WinGet)" -Level 'SUCCESS'
                return $true
            }
            elseif ($retryText -match 'No installed package found|No package found|not installed') {
                Add-InstallLog -Message "$PackageId is not installed (WinGet)" -Level 'SUCCESS'
                return $true
            }

            Add-InstallLog -Message "WinGet uninstall retry failed for $PackageId (exit code: $LASTEXITCODE)" -Level 'WARN'
            if ($retryText) {
                Add-InstallLog -Message "WinGet retry output for ${PackageId}: $retryText" -Level 'WARN'
            }
        }
        return $false
    }
    catch {
        Add-InstallLog -Message "WinGet uninstall error for ${PackageId}: $_" -Level 'ERROR'
        return $false
    }
}

<#
.SYNOPSIS
  Uninstall single application via Chocolatey.
#>
function Uninstall-ViaChocolatey {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId
    )

    try {
        Write-Host "[INFO] Uninstalling '$PackageId' via Chocolatey..." -ForegroundColor Gray

        $result = & choco uninstall $PackageId -y --remove-dependencies 2>&1
        $resultText = ($result | Out-String).Trim()

        if ($LASTEXITCODE -eq 0) {
            Add-InstallLog -Message "$PackageId uninstalled successfully (Chocolatey)" -Level 'SUCCESS'
            return $true
        }
        elseif ($resultText -match 'not installed|not found') {
            Add-InstallLog -Message "$PackageId is not installed (Chocolatey)" -Level 'SUCCESS'
            return $true
        }
        else {
            Add-InstallLog -Message "Chocolatey uninstall failed for $PackageId (exit code: $LASTEXITCODE)" -Level 'WARN'
            if ($resultText) {
                Add-InstallLog -Message "Chocolatey output for ${PackageId}: $resultText" -Level 'WARN'
            }
            return $false
        }
    }
    catch {
        Add-InstallLog -Message "Chocolatey uninstall error for ${PackageId}: $_" -Level 'ERROR'
        return $false
    }
}

function Ensure-FallbackPackageManager {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('winget','chocolatey')]
        [string]$PreferredPM
    )

    if ($PreferredPM -eq 'winget') {
        if (-not $global:AppState.PMAvailable.chocolatey) {
            Add-InstallLog -Message 'Fallback package manager Chocolatey is missing; attempting bootstrap...' -Level 'WARN'
            if ((Test-IsAdministrator) -and (Install-Chocolatey)) {
                Update-PMAvailability
                return $true
            }
            elseif (-not (Test-IsAdministrator)) {
                Add-InstallLog -Message 'Cannot bootstrap Chocolatey from unelevated process during fallback.' -Level 'ERROR'
            }
        }
    }
    else {
        if (-not $global:AppState.PMAvailable.winget) {
            Add-InstallLog -Message 'Fallback package manager WinGet is missing; attempting bootstrap...' -Level 'WARN'
            if ((Test-IsAdministrator) -and (Install-WinGet)) {
                Update-PMAvailability
                return $true
            }
            elseif (-not (Test-IsAdministrator)) {
                Add-InstallLog -Message 'Cannot bootstrap WinGet from unelevated process during fallback.' -Level 'ERROR'
            }
        }
    }

    return $false
}

function Test-UsablePackageId {
    param(
        [AllowEmptyString()]
        [string]$PackageId
    )

    return -not [string]::IsNullOrWhiteSpace($PackageId)
}

<#
.SYNOPSIS
  Install application with fallback logic: try preferred PM, then fallback.
#>
function Install-Application {
    param(
        [Parameter(Mandatory)]
        [object]$Package,
        
        [string]$PreferredPM = 'winget'
    )

    $displayName = if ($Package.name) { $Package.name } else { [string]$Package }
    $packageId = if ($Package -is [string]) {
        [string]$Package
    }
    elseif ($Package.PSObject.Properties['packageId'] -and $Package.packageId) {
        [string]$Package.packageId
    }
    else {
        ''
    }
    $wingetId = if ($Package.wingetId) { [string]$Package.wingetId } elseif (Test-UsablePackageId $packageId) { [string]$packageId } else { '' }
    $chocoId = if ($Package.chocoId) { [string]$Package.chocoId } elseif (Test-UsablePackageId $packageId) { [string]$packageId } else { '' }
    $hasWingetId = Test-UsablePackageId $wingetId
    $hasChocoId = Test-UsablePackageId $chocoId

    if (-not $hasWingetId -and -not $hasChocoId) {
        Add-InstallLog -Message "Cannot install $displayName - no valid WinGet or Chocolatey package ID is configured" -Level 'ERROR'
        return $false
    }
    
    # Ensure at least one PM is available
    if (-not $global:AppState.PMAvailable.winget -and -not $global:AppState.PMAvailable.chocolatey) {
        Add-InstallLog -Message "Attempting to bootstrap missing package managers..." -Level 'WARN'
        if (-not $global:AppState.PMAvailable.winget -and $hasWingetId) {
            Install-WinGet | Out-Null
            Update-PMAvailability
        }
        
        if (-not $global:AppState.PMAvailable.chocolatey -and $hasChocoId) {
            Install-Chocolatey | Out-Null
            Update-PMAvailability
        }
    }
    
    # Primary attempt
    if ($PreferredPM -eq 'winget') {
        if ($hasWingetId -and $global:AppState.PMAvailable.winget) {
            if (Install-ViaWinGet -PackageId $wingetId) {
                return $true
            }
        }
        # Fallback to Chocolatey
        if ($hasChocoId -and $global:AppState.PMAvailable.chocolatey) {
            Add-InstallLog -Message "WinGet failed, attempting fallback to Chocolatey..." -Level 'WARN'
            return Install-ViaChocolatey -PackageId $chocoId
        }
    }
    elseif ($PreferredPM -eq 'chocolatey') {
        if ($hasChocoId -and $global:AppState.PMAvailable.chocolatey) {
            if (Install-ViaChocolatey -PackageId $chocoId) {
                return $true
            }
        }
        # Fallback to WinGet
        if ($hasWingetId -and $global:AppState.PMAvailable.winget) {
            Add-InstallLog -Message "Chocolatey failed, attempting fallback to WinGet..." -Level 'WARN'
            return Install-ViaWinGet -PackageId $wingetId
        }
    }
    
    $configuredManagers = @()
    if ($hasWingetId) { $configuredManagers += "WinGet '$wingetId'" }
    if ($hasChocoId) { $configuredManagers += "Chocolatey '$chocoId'" }
    Add-InstallLog -Message "Failed to install $displayName - no available package manager for $($configuredManagers -join ' or ')" -Level 'ERROR'
    return $false
}

<#
.SYNOPSIS
  Uninstall application with fallback logic: try preferred PM, then fallback.
#>
function Uninstall-Application {
    param(
        [Parameter(Mandatory)]
        [object]$Package,

        [string]$PreferredPM = 'winget'
    )

    $displayName = if ($Package.name) { $Package.name } else { [string]$Package }
    $packageId = if ($Package -is [string]) {
        [string]$Package
    }
    elseif ($Package.PSObject.Properties['packageId'] -and $Package.packageId) {
        [string]$Package.packageId
    }
    else {
        ''
    }
    $wingetId = if ($Package.wingetId) { [string]$Package.wingetId } elseif (Test-UsablePackageId $packageId) { [string]$packageId } else { '' }
    $chocoId = if ($Package.chocoId) { [string]$Package.chocoId } elseif (Test-UsablePackageId $packageId) { [string]$packageId } else { '' }
    $hasWingetId = Test-UsablePackageId $wingetId
    $hasChocoId = Test-UsablePackageId $chocoId

    if (-not $hasWingetId -and -not $hasChocoId) {
        Add-InstallLog -Message "Cannot uninstall $displayName - no valid WinGet or Chocolatey package ID is configured" -Level 'ERROR'
        return $false
    }

    if (-not $global:AppState.PMAvailable.winget -and -not $global:AppState.PMAvailable.chocolatey) {
        Add-InstallLog -Message "Attempting to bootstrap missing package managers before uninstalling $displayName..." -Level 'WARN'
        if (-not $global:AppState.PMAvailable.winget -and $hasWingetId) {
            Install-WinGet | Out-Null
            Update-PMAvailability
        }
        if (-not $global:AppState.PMAvailable.chocolatey -and $hasChocoId) {
            Install-Chocolatey | Out-Null
            Update-PMAvailability
        }

        if (-not $global:AppState.PMAvailable.winget -and -not $global:AppState.PMAvailable.chocolatey) {
            Add-InstallLog -Message "Cannot uninstall $displayName - no available package manager for the configured package IDs" -Level 'ERROR'
            return $false
        }
    }

    if ($PreferredPM -eq 'winget') {
        if ($hasWingetId -and $global:AppState.PMAvailable.winget) {
            if (Uninstall-ViaWinGet -PackageId $wingetId) {
                return $true
            }
        }

        Ensure-FallbackPackageManager -PreferredPM $PreferredPM | Out-Null

        if ($hasChocoId -and $global:AppState.PMAvailable.chocolatey) {
            Add-InstallLog -Message "WinGet uninstall failed, attempting fallback to Chocolatey..." -Level 'WARN'
            return Uninstall-ViaChocolatey -PackageId $chocoId
        }
    }
    elseif ($PreferredPM -eq 'chocolatey') {
        if ($hasChocoId -and $global:AppState.PMAvailable.chocolatey) {
            if (Uninstall-ViaChocolatey -PackageId $chocoId) {
                return $true
            }
        }

        Ensure-FallbackPackageManager -PreferredPM $PreferredPM | Out-Null

        if ($hasWingetId -and $global:AppState.PMAvailable.winget) {
            Add-InstallLog -Message "Chocolatey uninstall failed, attempting fallback to WinGet..." -Level 'WARN'
            return Uninstall-ViaWinGet -PackageId $wingetId
        }
    }

    $configuredManagers = @()
    if ($hasWingetId) { $configuredManagers += "WinGet '$wingetId'" }
    if ($hasChocoId) { $configuredManagers += "Chocolatey '$chocoId'" }
    Add-InstallLog -Message "Failed to uninstall $displayName - no available package manager for $($configuredManagers -join ' or ')" -Level 'ERROR'
    return $false
}

<#
.SYNOPSIS
  Batch install multiple applications (called by background worker).
#>
function Install-Applications {
    param(
        [Parameter(Mandatory)]
        [array]$Packages,
        
        [string]$PreferredPM = 'winget'
    )
    
    Update-AppState -Property 'IsInstalling' -Value $true
    Add-InstallLog -Message "Starting batch installation of $($Packages.Count) app(s)" -Level 'INFO'
    
    $successCount = 0
    $failureCount = 0
    
    foreach ($package in $Packages) {
        if (Install-Application -Package $package -PreferredPM $PreferredPM) {
            $successCount++
        }
        else {
            $failureCount++
        }
        Start-Sleep -Milliseconds 500
    }
    
    Add-InstallLog -Message "Installation batch complete: $successCount successful, $failureCount failed" -Level 'INFO'
    Cleanup-InstallerArtifacts
    Update-AppState -Property 'IsInstalling' -Value $false
    return @{ Success = $successCount; Failure = $failureCount }
}

<#
.SYNOPSIS
  Batch uninstall multiple applications.
#>
function Uninstall-Applications {
    param(
        [Parameter(Mandatory)]
        [array]$Packages,

        [string]$PreferredPM = 'winget'
    )

    Update-AppState -Property 'IsInstalling' -Value $true
    Add-InstallLog -Message "Starting batch uninstall of $($Packages.Count) app(s)" -Level 'INFO'

    $successCount = 0
    $failureCount = 0

    foreach ($package in $Packages) {
        if (Uninstall-Application -Package $package -PreferredPM $PreferredPM) {
            $successCount++
        }
        else {
            $failureCount++
        }
        Start-Sleep -Milliseconds 500
    }

    Add-InstallLog -Message "Uninstall batch complete: $successCount successful, $failureCount failed" -Level 'INFO'
    Cleanup-InstallerArtifacts
    Update-AppState -Property 'IsInstalling' -Value $false
    return @{ Success = $successCount; Failure = $failureCount }
}
