# URL Detection Fix — Design

**Date:** 2026-02-21
**Status:** Approved

---

## Problem

Two bugs introduced by the previous URL detection plan:

1. **Greyscale turns off when switching away from browser** — the URL scan only checks the foreground window (`WinExist("A")`). When the user alt-tabs away from Chrome with reddit.com open, nothing checks Chrome's URL in the background, so greyscale deactivates.

2. **Chrome / Brave / Arc URL detection never works** — `ControlGetText("Chrome_OmniboxView1", hwnd)` fails silently for all Chromium engines. URL-based greyscale only triggers for Chromium browsers when the page title happens to contain an AppList keyword.

Firefox/Zen URL detection via UIA (`urlbar-input`) was confirmed working and is not changed.

---

## Root Causes

| Issue | Cause |
|---|---|
| Background window regression | URL scan uses `WinExist("A")` (foreground only) |
| Chromium URL detection | `ControlGetText` fails silently for all Chromium builds |

---

## Design

### Section 1 — All-windows URL scan loop

Replace the foreground-only block with a loop over every exe in `ProcessList`, mirroring the existing title scan structure:

```
for procExe in ProcessList:
    windows = WinGetList("ahk_exe " procExe)
    for each hwnd in windows:
        if minimized → skip
        url = GetBrowserURL(hwnd)
        if url matches any AppList entry → shouldGreyscale = true, break out
```

Any visible browser window with a matching URL — foreground or background — keeps greyscale on.

### Section 2 — `GetBrowserURL()` rewrite

Drop `ControlGetText` entirely. Use UIA for all five browsers:

```
GetBrowserURL(hwnd):
    el = UIA.ElementFromHandle(hwnd)

    // Chromium (Chrome, Brave, Arc)
    try: urlBar = el.FindFirst({AutomationId: "omnibox"})
         if urlBar → return urlBar.Value

    // Firefox / Zen
    try: urlBar = el.FindFirst({AutomationId: "urlbar-input"})
         if urlBar → return urlBar.Value

    return ""
```

Each `FindFirst` is in its own `try` block so failure on one engine doesn't abort the other.

### Section 3 — No other changes

- Title scan (process-scoped and system-wide) — untouched
- `Lib/UIA.ahk` — already present
- `settings.ini` — no changes
- Settings GUI, hotkeys, schedule, tray — untouched

Only `CheckVisibleWindows()` (URL scan block) and `GetBrowserURL()` change.

---

## Files Changed

| File | Change |
|---|---|
| `CutDistractions.ahk` | Replace URL scan block; rewrite `GetBrowserURL()` |

---

## Verification

1. Chrome/Brave/Arc → navigate to `reddit.com` → greyscale activates
2. Firefox/Zen → same URL → greyscale activates
3. Switch to a non-browser app while browser has distracting URL open → greyscale stays on
4. Navigate to a non-distraction site → greyscale deactivates within ~2 seconds
5. Minimise the browser → greyscale deactivates
6. Existing title-match (e.g. "YouTube - Google Chrome") still works
