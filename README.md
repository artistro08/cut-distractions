# CutDistractions

A Windows utility that automatically turns your screen greyscale when distracting apps are visible. Greyscale makes colorful content less appealing, helping you stay focused.

## How It Works

CutDistractions monitors your open windows. When a window title matches an app in your configured list (e.g. YouTube, Reddit, Twitter), it activates the Windows built-in greyscale color filter. Minimize or close the distracting window and color returns instantly.

Title matching can be scoped to specific browser/app processes so that, for example, a YouTube tab in Chrome triggers greyscale but a YouTube-named local file in Explorer does not.

## Requirements

- Windows 10/11
- [AutoHotkey v2](https://www.autohotkey.com/) (for running the script directly)

## Quick Start

1. Clone or download the repository
2. Edit `settings.ini` to customize your app list and preferences
3. Run `CutDistractions.ahk` with AutoHotkey v2

The app runs in the system tray. Right-click the tray icon for options, or double-click it to open Settings.

## Configuration

Settings are loaded from `settings.ini`. When deployed as an executable, it checks `%USERPROFILE%\.config\cut-distractions\settings.ini` first, falling back to the file next to the script/exe.

### settings.ini

```ini
[General]
; Keep greyscale always on (1=on, 0=off), still respects schedule
AlwaysOn=0
; Password required to exit (leave empty for no password)
ExitPassword=

[Apps]
; Comma-separated window title substrings that trigger greyscale
List=YouTube,Twitter,Reddit,TikTok,Instagram,Facebook,Threads

[Processes]
; Comma-separated exe names to scope app-title matching to
; Leave empty to check all windows system-wide
List=chrome.exe,brave.exe,arc.exe,zen.exe,firefox.exe

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

### General

`AlwaysOn=1` keeps greyscale active at all times (while within the schedule window), regardless of which apps are open. Useful if you want to enforce greyscale during a focus session without relying on app detection.

`ExitPassword` requires a password to be entered before the app can be closed from the tray menu. Leave it empty to allow exiting freely. The password can also be set or changed in the Settings GUI. Note that the app can still be killed via Task Manager regardless of this setting.

### App List

The `List` value under `[Apps]` contains comma-separated substrings matched against window titles. For example, `YouTube` matches any window with "YouTube" in its title.

### Process Filtering

The `[Processes]` section scopes title matching to specific executables. When a process list is configured, a window title match only triggers greyscale if the window belongs to one of the listed processes. This prevents false positives — for example, a file named "YouTube Tutorial.mp4" open in Explorer won't trigger greyscale, but a YouTube tab in Chrome will.

Leave `List` empty (or remove the key) to check all windows system-wide, which is the original behavior.

### Hotkey

The default hotkey `Ctrl+Alt+G` temporarily pauses greyscale for the configured duration. Press it again while paused to resume monitoring immediately.

### Schedule

When scheduling is enabled, greyscale only activates during the specified time window. Outside that window, distracting apps won't trigger greyscale. Set `Enabled=0` to monitor at all times.

## Settings GUI

Double-click the tray icon (or right-click and choose **Settings**) to open the settings window. All options from `settings.ini` are editable here. Click **Save** to write the changes and reload the app. The GUI automatically adapts to Windows dark mode.

The **Reset Registry** button restores the Windows color filter registry keys to their defaults, which is useful if greyscale gets stuck or behaves unexpectedly.

## Tray Menu

- **Status** - Shows current state: Monitoring, Greyscale ON, or Paused
- **Settings** - Opens the settings GUI (also the default double-click action)
- **Exit** - Closes the app and restores color if greyscale is active

## Watchdog

When deployed, a **watchdog** runs as a Windows Scheduled Task in the background. It checks every 5 seconds whether `CutDistractions.exe` is running and restarts it automatically if it was killed (e.g. via Task Manager or a crash).

The watchdog respects an intentional exit: when you close the app via the password prompt, the app writes `HKCU\Software\CutDistractions\UserExited = 1` before exiting. The watchdog reads this flag and leaves the app closed. On the next normal startup the flag is cleared automatically.

The scheduled task is registered during deployment (`3-Deploy.ps1`) and starts immediately. It is configured to run at every logon and to auto-restart if the watchdog script itself is terminated.

To remove the watchdog entirely:

```powershell
Unregister-ScheduledTask -TaskName "CutDistractionsWatchdog" -Confirm:$false
```

## Building as a Signed Executable

The `build/` directory contains scripts to compile CutDistractions into a signed `.exe` with UIAccess support, allowing it to work with elevated windows.

### Prerequisites

- [AutoHotkey v2](https://www.autohotkey.com/) (includes the Ahk2Exe compiler)
- [PowerShell 7](https://aka.ms/powershell) (`pwsh`) — required by `BUILD.bat` and all build scripts; Windows PowerShell 5.x will not work
- [Windows SDK](https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/) (for `mt.exe`) or [Resource Hacker](http://www.angusj.com/resourcehacker/) (for manifest embedding)

### Build Steps

> **Requires PowerShell 7.** Install it from [aka.ms/powershell](https://aka.ms/powershell) if `pwsh` is not already on your PATH.

Run `build\BUILD.bat` as administrator. This executes three steps:

1. **Create Certificate** (`1-CreateCertificate.ps1`) - Generates a self-signed code signing certificate and installs it to Trusted Root
2. **Compile and Sign** (`2-CompileAndSign.ps1`) - Compiles the AHK script to an exe, embeds the UIAccess manifest, and signs it
3. **Deploy** (`3-Deploy.ps1`) - Copies the signed exe to `C:\Program Files\CutDistractions\` and settings to the user config directory

You can also run each step individually from an elevated **PowerShell 7** (`pwsh`) session:

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
    BUILD.bat                      # One-click build launcher (run as admin)
    BUILD-ALL.ps1                  # Master build script
    1-CreateCertificate.ps1
    2-CompileAndSign.ps1
    3-Deploy.ps1                   # Also registers the watchdog scheduled task
    CutDistractionsWatchdog.ps1    # Watchdog loop (copied to Program Files on deploy)
    CutDistractions.manifest
  certificates/           # Generated certificates (gitignored)
```

## License

MIT
