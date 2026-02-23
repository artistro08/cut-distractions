# Real-Time URL Bar Detection Design

**Date:** 2026-02-23
**Status:** Implemented

## Problem

When a user types a distracting URL (e.g. `reddit.com`) in the browser address bar and switches tabs before pressing Enter, greyscale never activates. The existing hooks only fire on window-level events (`idObject = 0`), which excludes URL bar value changes. The 2-second polling safety net is too slow — the tab switch happens before the poll runs, and by then the URL bar shows a different URL.

## Solution

Hook `EVENT_OBJECT_VALUECHANGE` (0x800E) using the existing `WinEventCallback`. In the callback, allow this event through (despite `idObject != 0`) but filter to browser processes only. This fires on every URL bar keystroke, triggering the existing 100ms-debounced `CheckVisibleWindows()` in real time.

## Changes (all in `CutDistractions.ahk`)

### 1. New hook registration
```ahk
global WinEventHookValueChange := DllCall("SetWinEventHook"
    , "UInt", 0x800E, "UInt", 0x800E
    , "Ptr", 0, "Ptr", WinEventCallback
    , "UInt", 0, "UInt", 0, "UInt", 0x0000, "Ptr")
```

### 2. Modified `OnWindowEvent`
Split the idObject filter: VALUE_CHANGE events bypass the `idObject = 0` gate and instead check if the HWND belongs to a browser process from `ProcessList`. All other events keep the existing filter.

### 3. Updated `ExitHandler`
`WinEventHookValueChange` added to the unhook loop and reset to 0 on exit.

## Trade-offs

- `EVENT_OBJECT_VALUECHANGE` fires system-wide for any accessible value change (sliders, spinners, text fields). Filtered to browser processes only — no overhead from non-browser apps.
- No polling rate increase, no keyboard hooks, no changes to `CheckVisibleWindows` or `GetBrowserURL`.
