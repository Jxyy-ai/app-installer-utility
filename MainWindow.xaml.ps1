<#
.SYNOPSIS
  WPF UI code-behind for App Installer Utility.
  Handles event binding, state updates, and user interactions.
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

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
$uninstallButton = $window.FindName('UninstallButton')
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
            $allApps += [pscustomobject]@{
                isSelected = $false
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
    $appCollection = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($app in $allApps) {
        [void]$appCollection.Add($app)
    }
    $appGrid.ItemsSource = $appCollection
    $appGrid.UpdateLayout()
}

function Get-SelectedAppSpecs {
    # Commit any checkbox edits before reading bound values.
    $focusedElement = [System.Windows.Input.Keyboard]::FocusedElement
    if ($focusedElement -and $focusedElement.GetType().GetMethod('GetBindingExpression')) {
        $bindingExpression = $focusedElement.GetBindingExpression([System.Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty)
        if ($bindingExpression) {
            $bindingExpression.UpdateSource()
        }
    }

    $selectedApps = @()
    foreach ($item in $appGrid.Items) {
        if ($item.isSelected) {
            $selectedApps += [pscustomobject]@{
                name = $item.name
                packageId = $item.packageId
                wingetId = if ($item.wingetId) { $item.wingetId } else { $item.packageId }
                chocoId = if ($item.chocoId) { $item.chocoId } else { $item.packageId }
            }
        }
    }

    return $selectedApps
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
    
    $selectedApps = Get-SelectedAppSpecs
    
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
        param($Packages, $PreferredPM, $StateScript, $ConfigScript, $InstallerScript)
        
        . $StateScript
        . $ConfigScript
        . $InstallerScript
        
        Install-Applications -Packages $Packages -PreferredPM $PreferredPM
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

# Uninstall button click handler
$uninstallButton.Add_Click({
    if ($global:AppState.IsInstalling) {
        [System.Windows.MessageBox]::Show('Operation already in progress', 'Info', 'OK', 'Information') | Out-Null
        return
    }

    $selectedApps = Get-SelectedAppSpecs

    if ($selectedApps.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Please select at least one app to uninstall', 'No Selection', 'OK', 'Warning') | Out-Null
        return
    }

    $appNames = ($selectedApps | ForEach-Object { $_.name }) -join "`r`n"
    $confirm = [System.Windows.MessageBox]::Show(
        "Uninstall the selected application(s)?`r`n`r`n$appNames",
        'Confirm Uninstall',
        'YesNo',
        'Warning'
    )

    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) {
        return
    }

    $busyOverlay.Visibility = [System.Windows.Visibility]::Visible
    $busyText.Text = "Uninstalling $($selectedApps.Count) application(s)..."
    $installPanel.IsEnabled = $false

    $job = Start-Job -ScriptBlock {
        param($Packages, $PreferredPM, $StateScript, $ConfigScript, $InstallerScript)

        . $StateScript
        . $ConfigScript
        . $InstallerScript

        Uninstall-Applications -Packages $Packages -PreferredPM $PreferredPM
    } -ArgumentList @($selectedApps, $global:AppState.PreferredPM, "$PSScriptRoot\AppState.ps1", "$PSScriptRoot\Config.ps1", "$PSScriptRoot\Installer.ps1")

    $job | Wait-Job | Out-Null
    $output = $job | Receive-Job
    $job | Remove-Job

    $busyOverlay.Visibility = [System.Windows.Visibility]::Collapsed
    $installPanel.IsEnabled = $true

    [System.Windows.MessageBox]::Show('Uninstall complete. Check transcript log for details.', 'Complete', 'OK', 'Information') | Out-Null
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

# Populate initial grid
Populate-AppGrid

# Show window
$window.ShowDialog() | Out-Null
