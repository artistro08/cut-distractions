# CutDistractions

A Windows utility that automatically turns your screen greyscale when distracting apps are visible. Greyscale makes colorful content less appealing, helping you stay focused.

## How It Works

CutDistractions monitors your open windows. When a window title matches an app in your configured list (e.g. YouTube, Reddit, Twitter), it activates the Windows built-in greyscale color filter. Minimize or close the distracting window and color returns instantly.

## Requirements

- Windows 10/11
- [AutoHotkey v2](https://www.autohotkey.com/) (for running the script directly)

## Quick Start

1. Clone or download the repository
2. Edit `settings.ini` to customize your app list and preferences
3. Run `CutDistractions.ahk` with AutoHotkey v2

The app runs in the system tray. Right-click the tray icon for options.

## Configuration

Settings are loaded from `settings.ini`. When deployed as an executable, it checks `%USERPROFILE%\.config\cut-distractions\settings.ini` first, falling back to the file next to the script/exe.

### settings.ini

```ini
[Apps]
; Comma-separated window title substrings that trigger greyscale
List=YouTube,Twitter,Reddit,TikTok,Instagram,Facebook,Threads

[Hotkey]
; AHK v2 hotkey format to temporarily disable greyscale
; ^ = Ctrl, ! = Alt, # = Win, + = Shift
DisableHotkey=^!g
; Minutes before greyscale re-enables after hotkey press
DisableDuration=3

[Schedule]
; Enable time-based scheduling (1=on, 0=off)
; When off, monitoring is always active
Enabled=1
; 24h format HH:mm - greyscale only triggers during this window
; Supports spanning midnight (e.g. 21:00 to 4:00)
StartTime=21:00
EndTime=4:00
```

### App List

The `List` value contains comma-separated substrings matched against window titles. For example, `YouTube` matches any window with "YouTube" in its title (browser tabs, the desktop app, etc.).

### Hotkey

The default hotkey `Ctrl+Alt+G` temporarily pauses greyscale for the configured duration. Press it again while paused to resume monitoring immediately.

### Schedule

When scheduling is enabled, greyscale only activates during the specified time window. Outside that window, distracting apps won't trigger greyscale. Set `Enabled=0` to monitor at all times.

## Tray Menu

- **Status** - Shows current state: Monitoring, Greyscale ON, or Paused
- **Reload Settings** - Reloads `settings.ini` without restarting
- **Exit** - Closes the app and restores color if greyscale is active

## Building as a Signed Executable

The `build/` directory contains scripts to compile CutDistractions into a signed `.exe` with UIAccess support, allowing it to work with elevated windows.

### Prerequisites

- [AutoHotkey v2](https://www.autohotkey.com/) (includes the Ahk2Exe compiler)
- Windows SDK (for `mt.exe`) or [Resource Hacker](http://www.angusj.com/resourcehacker/) (for manifest embedding)

### Build Steps

Run `build\BUILD.bat` as administrator. This executes three steps:

1. **Create Certificate** (`1-CreateCertificate.ps1`) - Generates a self-signed code signing certificate and installs it to Trusted Root
2. **Compile and Sign** (`2-CompileAndSign.ps1`) - Compiles the AHK script to an exe, embeds the UIAccess manifest, and signs it
3. **Deploy** (`3-Deploy.ps1`) - Copies the signed exe to `C:\Program Files\CutDistractions\` and settings to the user config directory

You can also run each step individually from an elevated PowerShell:

```powershell
cd build
.\1-CreateCertificate.ps1
.\2-CompileAndSign.ps1
.\3-Deploy.ps1
```

### Why Sign and Deploy to Program Files?

The UIAccess manifest flag allows the app to interact with elevated (admin) windows. Windows requires UIAccess executables to be:

1. Digitally signed
2. Located in a trusted directory (e.g. `C:\Program Files\`)

Without this, greyscale won't activate when an elevated window is in the foreground.

## Project Structure

```
CutDistractions/
  CutDistractions.ahk    # Main script
  CutDistractions.ico     # Application icon
  settings.ini            # Configuration file
  build/
    BUILD.bat             # One-click build launcher (run as admin)
    BUILD-ALL.ps1         # Master build script
    1-CreateCertificate.ps1
    2-CompileAndSign.ps1
    3-Deploy.ps1
    CutDistractions.manifest
  certificates/           # Generated certificates (gitignored)
```

## License

MIT
