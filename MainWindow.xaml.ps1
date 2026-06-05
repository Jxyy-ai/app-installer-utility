<#
.SYNOPSIS
  WPF UI code-behind for App Installer Utility.
  Handles event binding, state updates, and user interactions.
#>

# Load XAML
[xml]$xaml = Get-Content "$PSScriptRoot\MainWindow.xaml" -Raw

$xamlReader = New-Object System.Xml.XmlNodeReader $xaml
$window = [System.Windows.Markup.XamlReader]::Load($xamlReader)

# Load app catalog
$catalogPath = "$PSScriptRoot\AppCatalog.json"
if (Test-Path $catalogPath) {
    $catalog = Get-Content $catalogPath | ConvertFrom-Json
}
else {
    Write-Host "[ERROR] AppCatalog.json not found" -ForegroundColor Red
    $window.Close()
    exit 1
}

# Get UI elements
$searchBox = $window.FindName('SearchBox')
$appGrid = $window.FindName('AppGrid')
$installButton = $window.FindName('InstallButton')
$pmWinget = $window.FindName('PMWinget')
$pmChocolatey = $window.FindName('PMChocolatey')
$busyOverlay = $window.FindName('BusyOverlay')
$busyText = $window.FindName('BusyText')

# Navigation buttons
$navInstall = $window.FindName('NavInstallBtn')
$navTweaks = $window.FindName('NavTweaksBtn')
$navConfig = $window.FindName('NavConfigBtn')
$navAbout = $window.FindName('NavAboutBtn')

# Panels
$installPanel = $window.FindName('InstallPanel')
$tweaksPanel = $window.FindName('TweaksPanel')
$configPanel = $window.FindName('ConfigPanel')
$aboutPanel = $window.FindName('AboutPanel')

$saveConfigBtn = $window.FindName('SaveConfigBtn')
$configPMWinget = $window.FindName('ConfigPMWinget')
$configPMChocolatey = $window.FindName('ConfigPMChocolatey')
$pmStatusText = $window.FindName('PMStatusText')

# Build app tiles from catalog
function Populate-AppGrid {
    param([string]$FilterText = '')
    
    $allApps = @()
    foreach ($category in $catalog.categories) {
        foreach ($app in $category.apps) {
            $allApps += @{
                name = $app.name
                description = $app.description
                packageId = $app.packageId
                wingetId = $app.wingetId
                chocoId = $app.chocoId
                category = $category.name
            }
        }
    }
    
    # Filter by search text
    if ($FilterText) {
        $allApps = $allApps | Where-Object {
            $_.name -like "*$FilterText*" -or $_.description -like "*$FilterText*"
        }
    }
    
    $global:AppState.VisibleApps = $allApps
    $appGrid.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]($allApps)
}

# Navigation click handlers
$navInstall.Add_Click({
    $installPanel.Visibility = [System.Windows.Visibility]::Visible
    $tweaksPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $configPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $aboutPanel.Visibility = [System.Windows.Visibility]::Collapsed
})

$navTweaks.Add_Click({
    $installPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $tweaksPanel.Visibility = [System.Windows.Visibility]::Visible
    $configPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $aboutPanel.Visibility = [System.Windows.Visibility]::Collapsed
})

$navConfig.Add_Click({
    $installPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $tweaksPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $configPanel.Visibility = [System.Windows.Visibility]::Visible
    $aboutPanel.Visibility = [System.Windows.Visibility]::Collapsed
    
    # Update status
    $wingetStatus = if ($global:AppState.PMAvailable.winget) { "✓ Available" } else { "✗ Not Found" }
    $chocoStatus = if ($global:AppState.PMAvailable.chocolatey) { "✓ Available" } else { "✗ Not Found" }
    $pmStatusText.Text = "WinGet: $wingetStatus`r`nChocolatey: $chocoStatus"
    
    if ($global:AppState.PreferredPM -eq 'winget') {
        $configPMWinget.IsChecked = $true
    }
    else {
        $configPMChocolatey.IsChecked = $true
    }
})

$navAbout.Add_Click({
    $installPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $tweaksPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $configPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $aboutPanel.Visibility = [System.Windows.Visibility]::Visible
})

# Search functionality
$searchBox.Add_TextChanged({
    Populate-AppGrid -FilterText $searchBox.Text
})

# Install button click handler
$installButton.Add_Click({
    if ($global:AppState.IsInstalling) {
        [System.Windows.MessageBox]::Show('Installation already in progress', 'Info', 'OK', 'Information') | Out-Null
        return
    }
    
    if ($global:AppState.OfflineMode) {
        [System.Windows.MessageBox]::Show('OFFLINE_MODE is enabled. Cannot install packages.', 'Offline Mode', 'OK', 'Warning') | Out-Null
        return
    }
    
    # Collect checked apps
    $selectedApps = @()
    foreach ($item in $appGrid.Items) {
        $container = $appGrid.ItemContainerGenerator.ContainerFromItem($item)
        if ($container) {
            $cb = $container.FindName('AppCheckbox')
            if ($cb -and $cb.IsChecked) {
                $selectedApps += $item.packageId
            }
        }
    }
    
    if ($selectedApps.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Please select at least one app to install', 'No Selection', 'OK', 'Warning') | Out-Null
        return
    }
    
    # Show busy overlay
    $busyOverlay.Visibility = [System.Windows.Visibility]::Visible
    $busyText.Text = "Installing $($selectedApps.Count) application(s)..."
    $installPanel.IsEnabled = $false
    
    # Run installation in background worker
    $job = Start-Job -ScriptBlock {
        param($PackageIds, $PreferredPM, $StateScript, $ConfigScript, $InstallerScript)
        
        . $StateScript
        . $ConfigScript
        . $InstallerScript
        
        Install-Applications -PackageIds $PackageIds -PreferredPM $PreferredPM
    } -ArgumentList @($selectedApps, $global:AppState.PreferredPM, "$PSScriptRoot\AppState.ps1", "$PSScriptRoot\Config.ps1", "$PSScriptRoot\Installer.ps1")
    
    # Wait for job completion
    $job | Wait-Job | Out-Null
    $output = $job | Receive-Job
    $job | Remove-Job
    
    # Hide busy overlay
    $busyOverlay.Visibility = [System.Windows.Visibility]::Collapsed
    $installPanel.IsEnabled = $true
    
    [System.Windows.MessageBox]::Show('Installation complete. Check transcript log for details.', 'Success', 'OK', 'Information') | Out-Null
})

# Package manager radio button handlers
$pmWinget.Add_Checked({
    Set-PreferredPackageManager -PM 'winget'
})

$pmChocolatey.Add_Checked({
    Set-PreferredPackageManager -PM 'chocolatey'
})

# Set initial PM selection
if ($global:AppState.PreferredPM -eq 'winget') {
    $pmWinget.IsChecked = $true
}
else {
    $pmChocolatey.IsChecked = $true
}

# Config save button
$saveConfigBtn.Add_Click({
    $selectedPM = if ($configPMWinget.IsChecked) { 'winget' } else { 'chocolatey' }
    Set-PreferredPackageManager -PM $selectedPM
    [System.Windows.MessageBox]::Show('Preferences saved.', 'Config', 'OK', 'Information') | Out-Null
})

# Disable install controls if offline mode
if ($global:AppState.OfflineMode) {
    $installButton.IsEnabled = $false
    $pmWinget.IsEnabled = $false
    $pmChocolatey.IsEnabled = $false
    $searchBox.IsReadOnly = $true
    $searchBox.Text = "[OFFLINE MODE ENABLED - Install functionality disabled]"
}

# Populate initial grid
Populate-AppGrid

# Show window
$window.ShowDialog() | Out-Null
