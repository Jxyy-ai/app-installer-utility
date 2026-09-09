# App Installer Utility

A Windows desktop utility for one-click and batch software installation from a curated catalog of 103 applications. Built with PowerShell 7.5, WPF, and integrated with WinGet 1.28.240 and Chocolatey 2.7.2.

## Features

✅ **Curated App Catalog**
- 8 categories with 103 hand-picked applications
- Organized as selectable tiles with checkboxes
- Real-time search and filter by name and description

✅ **Batch & Single-App Installation**
- Batch install: Select multiple apps, click install
- Single-app one-click via right-click context menu
- Silent execution with no user prompts

✅ **Intelligent Package Manager Orchestration**
- WinGet as default (WinGet 1.28.240)
- Automatic fallback to Chocolatey (2.7.2) per-app
- Auto-bootstrap WinGet/Chocolatey if missing
- User preference selection with INI persistence

✅ **Rich UI**
- Sidebar navigation (Install, Tweaks, Config, About)
- Tile grid with category grouping
- Real-time search box
- Package manager toggle buttons
- Installation progress overlay
- PM availability status display

✅ **Advanced Modes**
- **Headless Mode**: Execute from JSON config without launching UI
- **Admin Elevation**: Automatic elevation on launch

✅ **Logging & Preferences**
- INI-based config file at `%LOCALAPPDATA%\AppInstallerUtility\config.ini`
- Transcript logging to `%LOCALAPPDATA%\AppInstallerUtility\transcript.log`
- Real-time installation log display

## Requirements

- **OS**: Windows 10 (build 1809+) or Windows 11
- **PowerShell**: 7.4 LTS or 7.5.7 STS
- **WinGet**: 1.28.240 (auto-bootstrapped if missing)
- **Chocolatey**: 2.7.2 (optional, auto-bootstrapped on demand)
- **Administrator privileges** (required on launch)

## Installation

### One-line installation

Run this command in PowerShell to download the latest project files and launch the utility:

```powershell
irm https://jxyy-ai.github.io/app-installer-utility/install.ps1 | iex
```

The launcher installs the project for the current Windows user under Local Application Data. It does not require a hard-coded local path.

1. Clone or download the repository:
   ```bash
   git clone https://github.com/Jxyy-ai/app-installer-utility.git
   cd app-installer-utility
   ```

2. Ensure PowerShell 7.5+ is installed:
   ```powershell
   pwsh --version
   ```

3. Run with admin privileges:
   ```powershell
   pwsh -ExecutionPolicy Bypass -File Main.ps1
   ```

## Usage

### Interactive UI Mode (Default)

```powershell
# Launch the application
pwsh -ExecutionPolicy Bypass -File Main.ps1
```

**Install Tab** – Browse and select apps:
- Use search box to filter by name or description
- Check boxes to select multiple apps
- Choose WinGet or Chocolatey preference
- Click "Install / Upgrade Applications" to begin batch install

**Config Tab** – Manage preferences:
- Select preferred package manager (WinGet or Chocolatey)
- View PM availability status
- Save preferences (persisted to INI)

**About Tab** – View app information and features

### Headless Mode (JSON Config)

Create a JSON config file (`install-config.json`):

```json
{
  "apps": [
    "Microsoft.VisualStudioCode",
    "Git.Git",
    "Python.Python.3.12"
  ]
}
```

Run headless install:

```powershell
pwsh -ExecutionPolicy Bypass -File Main.ps1 -ConfigPath "C:\path\to\install-config.json"
```

No UI is launched; installation runs silently and logs to transcript.

## Configuration

### INI File Format

Preferences are stored at `%LOCALAPPDATA%\AppInstallerUtility\config.ini`:

```ini
PreferredPM=winget
```

### Environment Variables

- `LOCALAPPDATA`: Standard Windows path for logs and config (auto-detected)

## Supported Applications (103 Total)

### Development (22)
- Visual Studio Code
- Git
- IntelliJ IDEA Community
- Python 3.12
- Node.js LTS
- Docker Desktop
- Terraform
- GitHub CLI
- GitHub Desktop
- Visual Studio Community
- Go
- Rust
- .NET 8 SDK
- Postman
- DBeaver Community
- PyCharm Community
- VirtualBox
- Azure CLI
- kubectl
- Apache Maven
- Yarn
- JetBrains Toolbox

### Browsers (8)
- Google Chrome
- Firefox
- Microsoft Edge
- Opera
- Brave
- Vivaldi
- Tor Browser
- Chromium

### Productivity (13)
- Microsoft Office 365
- LibreOffice
- Obsidian
- Notion
- Standard Notes
- Microsoft To Do
- Todoist
- Adobe Acrobat Reader
- Foxit PDF Reader
- Power BI
- draw.io
- Evernote
- OneDrive

### Media & Design (15)
- OBS Studio
- DaVinci Resolve
- Audacity
- ImageMagick
- GIMP
- Blender
- Krita
- Spotify
- Inkscape
- Paint.NET
- ScreenToGif
- Kdenlive
- MPC-HC
- MusicBrainz Picard
- yt-dlp

### System Tools (16)
- 7-Zip
- WinRAR
- Total Commander
- Sysinternals Suite
- CCleaner
- Everything
- Microsoft PowerToys
- Rufus
- WizTree
- WinSCP
- PuTTY
- FileZilla
- Notepad++
- TreeSize Free
- jq
- cURL

### Communication (9)
- Discord
- Slack
- Telegram
- Microsoft Teams
- Zoom
- Signal
- Element
- WhatsApp
- Thunderbird

### Security & Privacy (9)
- Bitwarden
- 1Password
- ProtonVPN
- VeraCrypt
- KeePass
- KeePassXC
- Malwarebytes
- WireGuard
- OpenVPN Connect

### Utilities (11)
- VLC Media Player
- qBittorrent
- Greenshot
- Calibre
- HandBrake
- ShareX
- Ventoy
- Steam
- Epic Games Launcher
- GOG Galaxy
- WinMerge

## Architecture

### Components

| File | Purpose |
|------|----------|
| **Main.ps1** | Entry point, admin elevation, headless/UI mode dispatch |
| **AppState.ps1** | In-memory state management, thread-safe shared store |
| **Config.ps1** | INI configuration, PM availability checks, logging |
| **Installer.ps1** | Package manager orchestration, bootstrap, install logic |
| **MainWindow.xaml** | WPF UI definition with XAML markup |
| **MainWindow.xaml.ps1** | WPF code-behind, event handlers, UI logic |
| **AppCatalog.json** | Curated app definitions organized by category |

### State Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Main.ps1 (Admin Check + Init)                                          │
└─────────────────────────────────┬─────────────────────────────────────────┘
                                   │
           ┌───────────────────────┴─────────────────────┐
           │                                             │
       Headless Mode                            Interactive Mode
       (JSON Config)                            (WPF UI)
           │                                             │
           └───────────────────────┬─────────────────────┘
                                   ▼
                        AppState (Global Store)
                         ├─ Apps: {}         ← from Catalog
                         ├─ Selected: []     ← from UI
                         ├─ IsInstalling     ← background task
                         └─ PreferredPM      ← config.ini
                                   │
                                   ▼
                        Installer.ps1 (Background Worker)
                         ├─ Check PM availability
                         ├─ Bootstrap if needed
                         └─ Install in sequence
```

## Troubleshooting

### WinGet not found after bootstrap

- Ensure App Installer from Microsoft Store is up-to-date
- Try manual install: `winget --version`
- Check Windows 10 build (requires 1809+)

### Chocolatey install fails

- Requires admin privileges
- Check internet connectivity
- Review transcript log at `%LOCALAPPDATA%\AppInstallerUtility\transcript.log`

### Some apps fail to install

- Fallback mechanism will attempt the other package manager
- Check if app exists in WinGet community repo: `winget search <appname>`
- Check Chocolatey repo: `choco search <appname>`
- Review install log for errors

### UI elements not rendering

- Ensure PowerShell 7.5+ is installed
- Verify WPF assemblies are available: `[System.Reflection.Assembly]::LoadWithPartialName('PresentationFramework')`
- Try running as administrator

## Performance Notes

- Initial app load from JSON catalog: ~100ms
- Search/filter on 103 apps: <50ms
- WinGet bootstrap: ~2-3 minutes (one-time)
- Chocolatey bootstrap: ~3-5 minutes (one-time)
- Per-app install time: Varies (typically 30s-5min depending on app size)

## Logging

All operations are logged to:

```
%LOCALAPPDATA%\AppInstallerUtility\transcript.log
```

Example log entry:

```
[2026-06-05 14:23:45] [INFO] Starting batch installation of 3 app(s)
[2026-06-05 14:24:12] [SUCCESS] Microsoft.VisualStudioCode installed successfully (WinGet)
[2026-06-05 14:25:33] [SUCCESS] Git.Git installed successfully (WinGet)
[2026-06-05 14:26:01] [WARN] Python.Python.3.12 failed via WinGet, attempting fallback to Chocolatey
[2026-06-05 14:27:15] [SUCCESS] Python.Python.3.12 installed successfully (Chocolatey)
```

## Future Enhancements

- [ ] Uninstall tab with silent uninstall via WinGet/Chocolatey
- [ ] System tweaks & optimization settings in Tweaks tab
- [ ] App update checker (compare installed vs latest)
- [ ] Custom catalog import (YAML/JSON)
- [ ] Installation profiles (Dev, Designer, Office worker, Gamer)
- [ ] Scheduled batch install (task scheduler integration)
- [ ] App pinning / favorites
- [ ] Dark mode theme toggle
- [ ] Multi-language support

## License

MIT License - Feel free to modify and distribute.

## Support

For issues or feature requests, please open an issue on GitHub: https://github.com/Jxyy-ai/app-installer-utility/issues

---

**Built with ❤️ using PowerShell, WPF, and modern package management.**
