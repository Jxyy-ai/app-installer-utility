<#
.SYNOPSIS
  WPF UI code-behind for App Installer Utility.
  Handles event binding, state updates, and user interactions.
#>

function Test-IsAdministrator {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    Write-Host "[INFO] UI running without administrator privileges. User-scope WinGet apps can be installed or removed normally." -ForegroundColor Cyan
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

# Ensure shared state/config/installer scripts are loaded when this file is run directly.
if (-not $global:AppState) {
    . "$PSScriptRoot\AppState.ps1"
}
if (-not (Get-Command Set-PreferredPackageManager -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\Config.ps1"
}
if (-not (Get-Command Install-Applications -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\Installer.ps1"
}

# Define a small AppItem class that implements INotifyPropertyChanged so WPF bindings update on selection changes
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;

namespace AppInstaller {
    public class AppItem : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        private bool _isSelected;
        public bool isSelected {
            get { return _isSelected; }
            set {
                if (_isSelected != value) {
                    _isSelected = value;
                    PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(isSelected)));
                }
            }
        }
        public string name { get; set; }
        public string description { get; set; }
        public string packageId { get; set; }
        public string wingetId { get; set; }
        public string chocoId { get; set; }
        public string category { get; set; }
        public string categoryId { get; set; }
        public string icon { get; set; }
    }
}
"@ -Language CSharp

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
$categoryFilter = $window.FindName('CategoryFilter')
$selectedCountText = $window.FindName('SelectedCountText')
$clearFiltersBtn = $window.FindName('ClearFiltersBtn')
$resultsSummary = $window.FindName('ResultsSummary')
$appGrid = $window.FindName('AppGrid')
$installButton = $window.FindName('InstallButton')
$uninstallButton = $window.FindName('UninstallButton')
$pmWinget = $window.FindName('PMWinget')
$pmChocolatey = $window.FindName('PMChocolatey')
$operationProgressPanel = $window.FindName('OperationProgressPanel')
$operationAppIcon = $window.FindName('OperationAppIcon')
$operationTitle = $window.FindName('OperationTitle')
$operationStatus = $window.FindName('OperationStatus')
$operationProgressBar = $window.FindName('OperationProgressBar')
$operationPercentage = $window.FindName('OperationPercentage')
$operationHint = $window.FindName('OperationHint')
$cancelOperationButton = $window.FindName('CancelOperationButton')

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
$operationTimer = New-Object System.Windows.Threading.DispatcherTimer
$operationTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$script:activePackageJob = $null
$script:activeOperation = $null
$appInfoPopup = $window.FindName('AppInfoPopup')
$appInfoBorder = $window.FindName('AppInfoBorder')
$appInfoName = $window.FindName('AppInfoName')
$appInfoDescription = $window.FindName('AppInfoDescription')
$appInfoCategory = $window.FindName('AppInfoCategory')
$appInfoPackage = $window.FindName('AppInfoPackage')
$appInfoCommand = $window.FindName('AppInfoCommand')

$tooltipTimer = New-Object System.Windows.Threading.DispatcherTimer
$tooltipTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$script:tooltipCard = $null

function Hide-AppInfoTooltip {
    param(
        [System.Windows.Controls.Border]$Card
    )

    if ($Card -and $script:tooltipCard -and $Card -ne $script:tooltipCard) {
        return
    }

    $tooltipTimer.Stop()
    $activeCard = $script:tooltipCard
    $script:tooltipCard = $null

    if (-not $appInfoPopup.IsOpen) {
        return
    }

    $fadeOut = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fadeOut.To = 0
    $fadeOut.Duration = [TimeSpan]::FromMilliseconds(120)
    $fadeOut.Completed += {
        if (-not $script:tooltipCard -and $activeCard -and -not $activeCard.IsMouseOver) {
            $appInfoPopup.IsOpen = $false
        }
    }.GetNewClosure()
    $appInfoBorder.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeOut)

    $slideOut = New-Object System.Windows.Media.Animation.DoubleAnimation
    $slideOut.To = 3
    $slideOut.Duration = [TimeSpan]::FromMilliseconds(120)
    $appInfoBorder.RenderTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $slideOut)
}

function Show-AppInfoTooltip {
    param(
        [System.Windows.Controls.Border]$Card,
        [AppInstaller.AppItem]$App
    )

    if (-not $Card -or -not $App -or -not $Card.IsMouseOver -or -not $appGrid.IsVisible) {
        return
    }

    $script:tooltipCard = $Card
    $appInfoName.Text = $App.name
    $appInfoDescription.Text = $App.description
    $appInfoCategory.Text = "Category: $($App.category)"
    $appInfoPackage.Text = "Package ID: $($App.packageId) | WinGet: $($App.wingetId) | Chocolatey: $($App.chocoId)"

    if ($global:AppState.PreferredPM -eq 'chocolatey' -and $App.chocoId) {
        $appInfoCommand.Text = "Install command: choco install $($App.chocoId) -y"
    }
    elseif ($App.wingetId) {
        $appInfoCommand.Text = "Install command: winget install --id $($App.wingetId) --exact"
    }
    else {
        $appInfoCommand.Text = "Install command: choco install $($App.chocoId) -y"
    }

    $appInfoPopup.PlacementTarget = $Card
    $appInfoBorder.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $appInfoBorder.RenderTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
    $appInfoBorder.Opacity = 0
    $appInfoBorder.RenderTransform.Y = 6
    $appInfoPopup.IsOpen = $true

    $fadeIn = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fadeIn.To = 1
    $fadeIn.Duration = [TimeSpan]::FromMilliseconds(160)
    $appInfoBorder.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)

    $slideIn = New-Object System.Windows.Media.Animation.DoubleAnimation
    $slideIn.To = 0
    $slideIn.Duration = [TimeSpan]::FromMilliseconds(160)
    $appInfoBorder.RenderTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $slideIn)
}

$tooltipTimer.Add_Tick({
    $tooltipTimer.Stop()
    if ($script:tooltipCard -and $script:tooltipCard.IsMouseOver -and $script:tooltipCard.IsVisible) {
        Show-AppInfoTooltip -Card $script:tooltipCard -App $script:tooltipCard.Tag
    }
})

# Build app tiles from catalog
$defaultAppIcons = @{
    'Visual Studio Code' = 'https://icons.duckduckgo.com/ip3/code.visualstudio.com.ico'
    'Git' = 'https://icons.duckduckgo.com/ip3/git-scm.com.ico'
    'IntelliJ IDEA Community' = 'https://icons.duckduckgo.com/ip3/www.jetbrains.com.ico'
    'Python 3.12' = 'https://icons.duckduckgo.com/ip3/python.org.ico'
    'Node.js LTS' = 'https://icons.duckduckgo.com/ip3/nodejs.org.ico'
    'Docker Desktop' = 'https://icons.duckduckgo.com/ip3/docker.com.ico'
    'Terraform' = 'https://icons.duckduckgo.com/ip3/hashicorp.com.ico'
    'GitHub CLI' = 'https://icons.duckduckgo.com/ip3/cli.github.com.ico'
    'GitHub Desktop' = 'https://icons.duckduckgo.com/ip3/desktop.github.com.ico'
    'Visual Studio Community' = 'https://icons.duckduckgo.com/ip3/visualstudio.microsoft.com.ico'
    'Go' = 'https://icons.duckduckgo.com/ip3/go.dev.ico'
    'Rust' = 'https://icons.duckduckgo.com/ip3/rust-lang.org.ico'
    '.NET 8 SDK' = 'https://icons.duckduckgo.com/ip3/dotnet.microsoft.com.ico'
    'Postman' = 'https://icons.duckduckgo.com/ip3/postman.com.ico'
    'DBeaver Community' = 'https://icons.duckduckgo.com/ip3/dbeaver.io.ico'
    'PyCharm Community' = 'https://icons.duckduckgo.com/ip3/www.jetbrains.com.ico'
    'VirtualBox' = 'https://icons.duckduckgo.com/ip3/www.virtualbox.org.ico'
    'Azure CLI' = 'https://icons.duckduckgo.com/ip3/azure.microsoft.com.ico'
    'kubectl' = 'https://icons.duckduckgo.com/ip3/kubernetes.io.ico'
    'Apache Maven' = 'https://icons.duckduckgo.com/ip3/apache.org.ico'
    'Yarn' = 'https://icons.duckduckgo.com/ip3/classic.yarnpkg.com.ico'
    'JetBrains Toolbox' = 'https://icons.duckduckgo.com/ip3/www.jetbrains.com.ico'
    'Google Chrome' = 'https://icons.duckduckgo.com/ip3/google.com.ico'
    'Firefox' = 'https://icons.duckduckgo.com/ip3/mozilla.org.ico'
    'Microsoft Edge' = 'https://icons.duckduckgo.com/ip3/microsoft.com.ico'
    'Opera' = 'https://icons.duckduckgo.com/ip3/opera.com.ico'
    'Brave' = 'https://icons.duckduckgo.com/ip3/brave.com.ico'
    'Vivaldi' = 'https://icons.duckduckgo.com/ip3/vivaldi.com.ico'
    'Tor Browser' = 'https://icons.duckduckgo.com/ip3/torproject.org.ico'
    'Chromium' = 'https://icons.duckduckgo.com/ip3/chromium.org.ico'
    'Microsoft Office 365' = 'https://icons.duckduckgo.com/ip3/microsoft.com.ico'
    'LibreOffice' = 'https://icons.duckduckgo.com/ip3/libreoffice.org.ico'
    'Obsidian' = 'https://icons.duckduckgo.com/ip3/obsidian.md.ico'
    'Notion' = 'https://icons.duckduckgo.com/ip3/notion.so.ico'
    'Standard Notes' = 'https://icons.duckduckgo.com/ip3/standardnotes.com.ico'
    'Microsoft To Do' = 'https://icons.duckduckgo.com/ip3/microsoft.com.ico'
    'Todoist' = 'https://icons.duckduckgo.com/ip3/todoist.com.ico'
    'Adobe Acrobat Reader' = 'https://icons.duckduckgo.com/ip3/acrobat.adobe.com.ico'
    'Foxit PDF Reader' = 'https://icons.duckduckgo.com/ip3/foxit.com.ico'
    'Power BI' = 'https://icons.duckduckgo.com/ip3/powerbi.microsoft.com.ico'
    'draw.io' = 'https://icons.duckduckgo.com/ip3/app.diagrams.net.ico'
    'Evernote' = 'https://icons.duckduckgo.com/ip3/evernote.com.ico'
    'OneDrive' = 'https://icons.duckduckgo.com/ip3/onedrive.live.com.ico'
    'OBS Studio' = 'https://icons.duckduckgo.com/ip3/obsproject.com.ico'
    'DaVinci Resolve' = 'https://icons.duckduckgo.com/ip3/blackmagicdesign.com.ico'
    'Audacity' = 'https://icons.duckduckgo.com/ip3/audacityteam.org.ico'
    'ImageMagick' = 'https://icons.duckduckgo.com/ip3/imagemagick.org.ico'
    'GIMP' = 'https://icons.duckduckgo.com/ip3/gimp.org.ico'
    'Blender' = 'https://icons.duckduckgo.com/ip3/blender.org.ico'
    'Krita' = 'https://icons.duckduckgo.com/ip3/krita.org.ico'
    'Spotify' = 'https://icons.duckduckgo.com/ip3/spotify.com.ico'
    'Inkscape' = 'https://icons.duckduckgo.com/ip3/inkscape.org.ico'
    'Paint.NET' = 'https://icons.duckduckgo.com/ip3/getpaint.net.ico'
    'ScreenToGif' = 'https://icons.duckduckgo.com/ip3/screenToGif.com.ico'
    'Kdenlive' = 'https://icons.duckduckgo.com/ip3/kdenlive.org.ico'
    'MPC-HC' = 'https://icons.duckduckgo.com/ip3/mpc-hc.org.ico'
    'MusicBrainz Picard' = 'https://icons.duckduckgo.com/ip3/musicbrainz.org.ico'
    'yt-dlp' = 'https://icons.duckduckgo.com/ip3/yt-dlp.org.ico'
    '7-Zip' = 'https://icons.duckduckgo.com/ip3/7-zip.org.ico'
    'WinRAR' = 'https://icons.duckduckgo.com/ip3/rarlab.com.ico'
    'Total Commander' = 'https://icons.duckduckgo.com/ip3/ghisler.com.ico'
    'Sysinternals Suite' = 'https://icons.duckduckgo.com/ip3/learn.microsoft.com.ico'
    'CCleaner' = 'https://icons.duckduckgo.com/ip3/ccleaner.com.ico'
    'Everything' = 'https://icons.duckduckgo.com/ip3/voidtools.com.ico'
    'Microsoft PowerToys' = 'https://icons.duckduckgo.com/ip3/microsoft.com.ico'
    'Rufus' = 'https://icons.duckduckgo.com/ip3/rufus.ie.ico'
    'WizTree' = 'https://icons.duckduckgo.com/ip3/wiztreefree.com.ico'
    'WinSCP' = 'https://icons.duckduckgo.com/ip3/winscp.net.ico'
    'PuTTY' = 'https://raw.githubusercontent.com/github/putty/master/windows/putty.ico'
    'FileZilla' = 'https://icons.duckduckgo.com/ip3/filezilla-project.org.ico'
    'Notepad++' = 'https://icons.duckduckgo.com/ip3/notepad-plus-plus.org.ico'
    'TreeSize Free' = 'https://icons.duckduckgo.com/ip3/jam-software.com.ico'
    'jq' = 'https://icons.duckduckgo.com/ip3/github.com.ico'
    'cURL' = 'https://icons.duckduckgo.com/ip3/curl.se.ico'
    'Discord' = 'https://icons.duckduckgo.com/ip3/discord.com.ico'
    'Slack' = 'https://icons.duckduckgo.com/ip3/slack.com.ico'
    'Telegram' = 'https://icons.duckduckgo.com/ip3/telegram.org.ico'
    'Microsoft Teams' = 'https://icons.duckduckgo.com/ip3/microsoft.com.ico'
    'Zoom' = 'https://icons.duckduckgo.com/ip3/zoom.us.ico'
    'Signal' = 'https://icons.duckduckgo.com/ip3/signal.org.ico'
    'Element' = 'https://icons.duckduckgo.com/ip3/element.io.ico'
    'WhatsApp' = 'https://icons.duckduckgo.com/ip3/whatsapp.com.ico'
    'Thunderbird' = 'https://icons.duckduckgo.com/ip3/thunderbird.net.ico'
    'Bitwarden' = 'https://icons.duckduckgo.com/ip3/bitwarden.com.ico'
    '1Password' = 'https://icons.duckduckgo.com/ip3/1password.com.ico'
    'ProtonVPN' = 'https://icons.duckduckgo.com/ip3/protonvpn.com.ico'
    'VeraCrypt' = 'https://icons.duckduckgo.com/ip3/veracrypt.fr.ico'
    'KeePass' = 'https://icons.duckduckgo.com/ip3/keepass.info.ico'
    'KeePassXC' = 'https://icons.duckduckgo.com/ip3/keepassxc.org.ico'
    'Malwarebytes' = 'https://icons.duckduckgo.com/ip3/malwarebytes.com.ico'
    'WireGuard' = 'https://icons.duckduckgo.com/ip3/wireguard.com.ico'
    'OpenVPN Connect' = 'https://icons.duckduckgo.com/ip3/openvpn.net.ico'
    'VLC Media Player' = 'https://raw.githubusercontent.com/videolan/vlc/master/modules/gui/macosx/Resources/App-Icons/VLC-Dev.icon/Assets/Untitled-1.png'
    'qBittorrent' = 'https://icons.duckduckgo.com/ip3/qbittorrent.org.ico'
    'Greenshot' = 'https://icons.duckduckgo.com/ip3/greenshot.org.ico'
    'Calibre' = 'https://icons.duckduckgo.com/ip3/calibre-ebook.com.ico'
    'HandBrake' = 'https://icons.duckduckgo.com/ip3/handbrake.fr.ico'
    'ShareX' = 'https://icons.duckduckgo.com/ip3/getsharex.com.ico'
    'Ventoy' = 'https://icons.duckduckgo.com/ip3/ventoy.net.ico'
    'Steam' = 'https://icons.duckduckgo.com/ip3/steampowered.com.ico'
    'Epic Games Launcher' = 'https://icons.duckduckgo.com/ip3/epicgames.com.ico'
    'GOG Galaxy' = 'https://icons.duckduckgo.com/ip3/gog.com.ico'
    'WinMerge' = 'https://icons.duckduckgo.com/ip3/winmerge.org.ico'
}

function Get-AppIconUrl {
    param(
        [object]$App
    )

    if ($null -eq $App) { return $null }
    if ($App.icon) { return $App.icon }
    if ($defaultAppIcons.ContainsKey($App.name)) { return $defaultAppIcons[$App.name] }

    return $null
}

function Get-AppCatalogItems {
    $allApps = @()
    foreach ($category in $catalog.categories) {
        foreach ($app in $category.apps) {
            $item = New-Object AppInstaller.AppItem
            $item.isSelected = $global:AppState.SelectedApps -contains $app.packageId
            $item.name = $app.name
            $item.description = $app.description
            $item.packageId = $app.packageId
            $item.wingetId = $app.wingetId
            $item.chocoId = $app.chocoId
            $item.category = $category.name
            $item.categoryId = $category.id
            $item.icon = Get-AppIconUrl -App $app
            $allApps += $item
        }
    }

    return $allApps
}

function Find-AppCard {
    param(
        [System.Windows.DependencyObject]$Root
    )

    if ($Root -is [System.Windows.Controls.Border] -and $Root.Tag -is [AppInstaller.AppItem]) {
        return $Root
    }

    for ($index = 0; $index -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Root); $index++) {
        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Root, $index)
        $card = Find-AppCard -Root $child
        if ($card) {
            return $card
        }
    }
}

function Find-AppCardFromSource {
    param(
        [System.Windows.DependencyObject]$Source
    )

    while ($Source -and $Source -ne $appGrid) {
        if ($Source -is [System.Windows.Controls.Border] -and $Source.Tag -is [AppInstaller.AppItem]) {
            return $Source
        }
        $Source = [System.Windows.Media.VisualTreeHelper]::GetParent($Source)
    }
}

function Register-AppGridTooltipHandlers {
    $appGrid.Add_MouseMove({
        param($sender, $eventArgs)
        $card = Find-AppCardFromSource -Source $eventArgs.OriginalSource
        if (-not $card) {
            Hide-AppInfoTooltip
            return
        }

        if ($script:tooltipCard -ne $card) {
            Hide-AppInfoTooltip
            $script:tooltipCard = $card
            $tooltipTimer.Start()
        }
    }.GetNewClosure())

    $appGrid.Add_MouseLeave({
        Hide-AppInfoTooltip
    }.GetNewClosure())
}

function Populate-AppGrid {
    param(
        [string]$FilterText = '',
        [string]$Category = '',
        [bool]$ShowSelectedOnly = $false
    )

    Hide-AppInfoTooltip
    $catalogApps = Get-AppCatalogItems
    $displayApps = @($catalogApps)

    if ($FilterText) {
        $normalizedFilter = $FilterText.ToLowerInvariant()
        $displayApps = @($displayApps | Where-Object {
            ($_.name.ToLowerInvariant() -like "*$normalizedFilter*") -or
            ($_.description.ToLowerInvariant() -like "*$normalizedFilter*") -or
            ($_.category.ToLowerInvariant() -like "*$normalizedFilter*")
        })
    }

    if ($Category) {
        $displayApps = @($displayApps | Where-Object { $_.categoryId -eq $Category -or $_.category -eq $Category })
    }

    if ($ShowSelectedOnly) {
        $displayApps = @($displayApps | Where-Object { $_.isSelected })
    }

    $global:AppState.VisibleApps = $displayApps
    $appCollection = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($app in $displayApps) {
        $app.add_PropertyChanged({
            param($sender, $e)
            if ($e.PropertyName -eq 'isSelected') {
                if ($sender.isSelected) {
                    if ($global:AppState.SelectedApps -notcontains $sender.packageId) {
                        $global:AppState.SelectedApps = @($global:AppState.SelectedApps) + $sender.packageId
                    }
                }
                else {
                    $global:AppState.SelectedApps = @($global:AppState.SelectedApps | Where-Object { $_ -ne $sender.packageId })
                }
                Update-SelectedCount
            }
        })
        [void]$appCollection.Add($app)
    }
    $appGrid.ItemsSource = $appCollection
    $appGrid.UpdateLayout()

    if ($resultsSummary) {
        $resultsSummary.Text = "Showing $($displayApps.Count) of $($catalogApps.Count) apps"
    }

    Update-SelectedCount
    $appGrid.UpdateLayout()
}

function Update-SelectedCount {
    $selectedCount = @($global:AppState.SelectedApps).Count

    if ($selectedCountText) {
        $selectedCountText.Text = "Selected: $selectedCount"
    }
}

function Apply-UIFilters {
    $selectedCategory = ''
    if ($categoryFilter -and $categoryFilter.SelectedValue) {
        $selectedCategory = [string]$categoryFilter.SelectedValue
    }

    $global:AppState.CurrentFilterText = if ($searchBox) { [string]$searchBox.Text } else { '' }
    Populate-AppGrid -FilterText $searchBox.Text -Category $selectedCategory -ShowSelectedOnly $false
    Update-SelectedCount
}

function Clear-All {
    $global:AppState.SelectedApps = @()

    if ($searchBox) {
        $searchBox.Clear()
    }

    if ($categoryFilter) {
        $categoryFilter.SelectedValue = ''
        $categoryFilter.SelectedIndex = 0
    }

    $global:AppState.CurrentFilterText = ''
    Populate-AppGrid -FilterText '' -Category '' -ShowSelectedOnly $false
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
    $selectedPackageIds = @($global:AppState.SelectedApps)
    foreach ($item in (Get-AppCatalogItems)) {
        if ($selectedPackageIds -contains $item.packageId) {
            $selectedApps += [pscustomobject]@{
                name = $item.name
                packageId = $item.packageId
                wingetId = if ($item.wingetId) { $item.wingetId } else { $item.packageId }
                chocoId = if ($item.chocoId) { $item.chocoId } else { $item.packageId }
                icon = $item.icon
            }
        }
    }

    Update-SelectedCount
    return $selectedApps
}

function Set-OperationUiState {
    param(
        [bool]$Running,
        [string]$StatusText = ''
    )

    $global:AppState.IsInstalling = $Running
    $installButton.IsEnabled = -not $Running
    $uninstallButton.IsEnabled = -not $Running
    $cancelOperationButton.IsEnabled = $Running
    $operationProgressPanel.Visibility = if ($Running) {
        [System.Windows.Visibility]::Visible
    }
    else {
        [System.Windows.Visibility]::Collapsed
    }
}

function Complete-PackageOperation {
    param(
        [object[]]$Output,
        [string]$Operation
    )

    $result = $Output | Where-Object {
        $_.PSObject.Properties['Success'] -and $_.PSObject.Properties['Failure']
    } | Select-Object -First 1

    Set-OperationUiState -Running $false
    $script:activePackageJob = $null
    $script:activeOperation = $null

    if ($result) {
        if ($result.Failure -gt 0) {
            [System.Windows.MessageBox]::Show(
                "$Operation complete with $($result.Success) successful and $($result.Failure) failed. Check the transcript log for details.",
                "Partial $Operation",
                'OK',
                'Warning'
            ) | Out-Null
        }
        else {
            [System.Windows.MessageBox]::Show(
                "$Operation complete. $($result.Success) application(s) $($Operation.ToLowerInvariant()) successfully.",
                'Complete',
                'OK',
                'Information'
            ) | Out-Null
        }
    }
    else {
        [System.Windows.MessageBox]::Show(
            "$Operation complete. Check transcript log for details.",
            'Complete',
            'OK',
            'Information'
        ) | Out-Null
    }
}

function Cancel-PackageOperation {
    if (-not $script:activePackageJob) {
        return
    }

    $operationTimer.Stop()
    $job = $script:activePackageJob
    $operation = $script:activeOperation
    Stop-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    $script:activePackageJob = $null
    $script:activeOperation = $null
    Set-OperationUiState -Running $false
    [System.Windows.MessageBox]::Show("$operation was canceled. Any package-manager process already started may finish independently.", 'Operation Canceled', 'OK', 'Information') | Out-Null
}

function Start-PackageOperation {
    param(
        [Parameter(Mandatory)]
        [array]$Packages,

        [Parameter(Mandatory)]
        [ValidateSet('Install', 'Uninstall')]
        [string]$Operation,

        [Parameter(Mandatory)]
        [string]$StatusText
    )

    $operationCommand = if ($Operation -eq 'Install') { 'Install-Applications' } else { 'Uninstall-Applications' }
    $stateScript = "$PSScriptRoot\AppState.ps1"
    $configScript = "$PSScriptRoot\Config.ps1"
    $installerScript = "$PSScriptRoot\Installer.ps1"

    $script:activePackageJob = Start-Job -ScriptBlock {
        param($Packages, $PreferredPM, $StateScript, $ConfigScript, $InstallerScript, $OperationCommand)

        . $StateScript
        . $ConfigScript
        . $InstallerScript

        & $OperationCommand -Packages $Packages -PreferredPM $PreferredPM
    } -ArgumentList @(
        $Packages,
        $global:AppState.PreferredPM,
        $stateScript,
        $configScript,
        $installerScript,
        $operationCommand
    )
    $script:activeOperation = $Operation
    $firstPackage = $Packages | Select-Object -First 1
    $operationTitle.Text = if ($Packages.Count -gt 1) {
        "$Operation $($firstPackage.name) (+$($Packages.Count - 1) more)"
    }
    else {
        "$Operation $($firstPackage.name)"
    }
    $operationStatus.Text = if ($Operation -eq 'Install') { 'Downloading and installing...' } else { 'Removing application...' }
    $operationAppIcon.Source = $firstPackage.icon
    $operationProgressBar.IsIndeterminate = $true
    $operationProgressBar.Value = 0
    $operationPercentage.Text = ''
    $operationPercentage.Visibility = [System.Windows.Visibility]::Collapsed
    $operationHint.Text = 'This may take a few minutes...'
    Set-OperationUiState -Running $true -StatusText $StatusText
    $operationTimer.Start()
}

$operationTimer.Add_Tick({
    if (-not $script:activePackageJob) {
        $operationTimer.Stop()
        return
    }

    $jobState = $script:activePackageJob.State
    if ($jobState -in @('Completed', 'Failed', 'Stopped')) {
        $operationTimer.Stop()
        $output = @(Receive-Job -Job $script:activePackageJob -ErrorAction SilentlyContinue)
        $operation = $script:activeOperation
        Remove-Job -Job $script:activePackageJob -Force -ErrorAction SilentlyContinue
        Complete-PackageOperation -Output $output -Operation $operation
    }
})

$cancelOperationButton.Add_Click({
    Cancel-PackageOperation
})

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

# Filter functionality
$categoryItems = @([pscustomobject]@{ Display = 'All categories'; Value = '' })
foreach ($category in $catalog.categories) {
    $categoryItems += [pscustomobject]@{ Display = $category.name; Value = $category.id }
}
$categoryFilter.ItemsSource = $categoryItems
$categoryFilter.DisplayMemberPath = 'Display'
$categoryFilter.SelectedValuePath = 'Value'
$categoryFilter.SelectedIndex = 0

$searchBox.Add_TextChanged({
    Apply-UIFilters
})

$categoryFilter.Add_SelectionChanged({
    Apply-UIFilters
})

$clearFiltersBtn.Add_Click({
    Clear-All
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
    
    Start-PackageOperation -Packages $selectedApps -Operation 'Install' -StatusText "Installing $($selectedApps.Count) application(s)..."
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

    Start-PackageOperation -Packages $selectedApps -Operation 'Uninstall' -StatusText "Uninstalling $($selectedApps.Count) application(s)..."
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

# Register once; the handler also covers cards created by filtering and refreshes.
Register-AppGridTooltipHandlers

# Populate initial grid
Populate-AppGrid

# Show window
$window.ShowDialog() | Out-Null
