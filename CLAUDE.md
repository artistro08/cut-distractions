# CutDistractions — Claude Instructions

## Project Overview

AutoHotkey v2 script that turns the screen greyscale when distracting apps are visible. Runs in the system tray. See `README.md` for full feature documentation.

## Key Files

| File | Purpose |
|------|---------|
| `CutDistractions.ahk` | Main script — all logic lives here |
| `settings.ini` | Default config shipped with releases |
| `build/CutDistractionsWatchdog.ps1` | Watchdog loop script (copied to Program Files on deploy) |
| `build/3-Deploy.ps1` | Deploys exe + registers watchdog scheduled task |
| `build/2-CompileAndSign.ps1` | UIAccess build (sign + manifest) |

## Architecture Notes

- **Settings** are read at startup via `IniRead` from `%USERPROFILE%\.config\cut-distractions\settings.ini` (deployed) or `A_ScriptDir\settings.ini` (dev). `IniWrite` + `Reload()` applies changes live.
- **Dark mode** is detected at startup via registry. All GUI controls use custom subclasses for dark painting. Active dark GUI hwnds are tracked in the global `CD_DarkGuis` Map — always declare it `global` in any function that touches it.
- **Watchdog** uses registry flag `HKCU\Software\CutDistractions\UserExited`: `0` = restart allowed, `1` = intentional exit (set before `ExitApp()` on password-confirmed exit, cleared on startup).
- **Exit password** field blocks paste via a `WM_PASTE` (0x0302) subclass on the edit control. The field is plain text (not masked).
- **AHK v2 scoping**: In assume-local mode, any simple assignment (`x := ...`) makes the variable local. Always declare globals explicitly in functions that assign to them — especially `CD_DarkGuis`, `CD_SettingsGui`, `ExitPassword`.

## Release Process

Versioning follows semver: `vMAJOR.MINOR.PATCH`
- New features → bump MINOR, reset PATCH (`v1.2.0` → `v1.3.0`)
- Bug fixes / config changes → bump PATCH (`v1.2.0` → `v1.2.1`)

### 1. Commit & push changes

```bash
git add <files>
git commit -m "Description of changes"
git push origin main
```

### 2. Compile the release exe

Use Ahk2Exe directly — **no UIAccess manifest, no signing** (the UIAccess build is for local deployment only and won't run on other machines):

```powershell
$compiler = 'C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe'
$ahk      = 'C:\Users\artistro08\CutDistractions\CutDistractions.ahk'
$icon     = 'C:\Users\artistro08\CutDistractions\CutDistractions.ico'
$tmp      = "$env:TEMP\CutDistractionsRelease"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$out      = "$tmp\CutDistractions.exe"
if (Test-Path $out) { Remove-Item $out -Force }
Start-Process -FilePath $compiler -ArgumentList "/in `"$ahk`" /out `"$out`" /icon `"$icon`"" -Wait -NoNewWindow
```

The exe must be in its own temp folder so the filename is exactly `CutDistractions.exe` when uploaded (gh CLI uses the filename from the path).

### 3. Create the git tag

```bash
git tag -a vX.Y.Z -m "vX.Y.Z - Short description"
git push origin vX.Y.Z
```

### 4. Create the GitHub release

```bash
gh release create vX.Y.Z \
  --title "vX.Y.Z" \
  --notes "## Changes
- bullet points here" \
  "/tmp/CutDistractionsRelease/CutDistractions.exe" \
  "settings.ini"
```

Always attach both `CutDistractions.exe` (compiled, no UIAccess) and `settings.ini`.

### 5. Verify assets

```bash
gh release view vX.Y.Z --json assets --jq '.assets[].name'
```

Expected output:
```
CutDistractions.exe
settings.ini
```

## Common Tasks

### Replacing a release asset

```bash
gh release delete-asset vX.Y.Z <asset-name> --yes
gh release upload vX.Y.Z /path/to/CutDistractions.exe
```

The upload path must end in `CutDistractions.exe` — the filename in the release matches the filename on disk.

### Removing the watchdog (for testing)

```powershell
Unregister-ScheduledTask -TaskName "CutDistractionsWatchdog" -Confirm:$false
```

### Resetting greyscale registry

```powershell
reg delete "HKCU\Software\Microsoft\ColorFiltering" /f
reg add "HKCU\Software\Microsoft\ColorFiltering" /v FilterType /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\ColorFiltering" /v HotkeyEnabled /t REG_DWORD /d 1 /f
reg add "HKCU\Software\Microsoft\ColorFiltering" /v Active /t REG_DWORD /d 0 /f
```
