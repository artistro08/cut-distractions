# URL Detection Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix URL-based greyscale detection so it works for all five browsers (including Chromium) and keeps greyscale on when a distracting browser window is visible in the background.

**Architecture:** Two surgical edits to `CutDistractions.ahk` — rewrite `GetBrowserURL()` to use UIA for all engines (dropping the broken `ControlGetText` Chromium path), and replace the foreground-only URL scan block with an all-windows loop over `ProcessList` exes, identical in structure to the existing title scan.

**Tech Stack:** AutoHotkey v2, Descolada UIA-v2 (`Lib/UIA.ahk` — already present)

---

### Task 1: Rewrite `GetBrowserURL()` to use UIA for all browsers

**Files:**
- Modify: `CutDistractions.ahk:251-266`

The current function tries `ControlGetText("Chrome_OmniboxView1", hwnd)` for Chromium — this fails silently on all Chromium builds. Replace both paths with UIA-only, trying `AutomationId: "omnibox"` (Chromium) then `AutomationId: "urlbar-input"` (Firefox/Zen). Each attempt is in its own `try` so one engine failing does not abort the other.

**Step 1: Replace `GetBrowserURL()` in `CutDistractions.ahk`**

Find and replace the entire function (lines 251–266):

```autohotkey
GetBrowserURL(hwnd) {
    try {
        el := UIA.ElementFromHandle(hwnd)
        ; Chromium-based: Chrome, Brave, Arc
        try {
            urlBar := el.FindFirst({AutomationId: "omnibox"})
            if urlBar
                return urlBar.Value
        }
        ; Firefox-based: Firefox, Zen
        try {
            urlBar := el.FindFirst({AutomationId: "urlbar-input"})
            if urlBar
                return urlBar.Value
        }
    }
    return ""
}
```

**Step 2: Verify the edit**

Read `CutDistractions.ahk` around line 251 and confirm:
- No `ControlGetText` reference remains in `GetBrowserURL()`
- The outer `try` wraps `UIA.ElementFromHandle(hwnd)`
- Two inner `try` blocks handle each engine independently
- Function still returns `""` as the fallback

**Step 3: Commit**

```bash
git add CutDistractions.ahk
git commit -m "Fix GetBrowserURL: use UIA for all browsers, drop ControlGetText"
```

---

### Task 2: Replace foreground-only URL scan with all-windows loop

**Files:**
- Modify: `CutDistractions.ahk:212-241`

The current URL scan block calls `WinExist("A")` and checks only the foreground window. Replace it with a loop over every exe in `ProcessList` using `WinGetList("ahk_exe " procExe)`, skipping minimized windows, and calling `GetBrowserURL()` on each. Guard the whole block with `ProcessList.Length > 0` — without a process list we don't know which processes are browsers.

**Step 1: Replace the URL scan block in `CheckVisibleWindows()`**

Find and replace the block starting with `; ── URL scan via address bar (foreground browser window) ──` (lines 212–241):

```autohotkey
        ; ── URL scan via address bar (all visible browser windows) ──
        if !shouldGreyscale && (ProcessList.Length > 0) {
            for procExe in ProcessList {
                try {
                    windows := WinGetList("ahk_exe " procExe)
                    for hwnd in windows {
                        try {
                            if (WinGetMinMax(hwnd) = -1)
                                continue
                            url := GetBrowserURL(hwnd)
                            if url {
                                for appName in AppList {
                                    if InStr(url, appName) {
                                        shouldGreyscale := true
                                        break 3
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
```

**Step 2: Verify the edit**

Read `CutDistractions.ahk` around that block and confirm:
- No `WinExist("A")` remains in the URL scan section
- The outer guard is `if !shouldGreyscale && (ProcessList.Length > 0)`
- Loop structure: `for procExe → for hwnd → if minimized skip → GetBrowserURL → for appName → break 3`
- `break 3` exits all three nested loops on first match

**Step 3: Commit**

```bash
git add CutDistractions.ahk
git commit -m "Fix URL scan: check all visible browser windows, not just foreground"
```

---

### Task 3: Manual verification

Run `CutDistractions.ahk` directly in AutoHotkey v2 (double-click or right-click → Run with AutoHotkey v2). Work through each scenario below and confirm the expected result.

**Scenario 1 — Chrome/Brave/Arc URL detection (foreground)**
1. Open Chrome and navigate to `reddit.com`
2. Wait up to 2 seconds
3. Expected: screen goes greyscale

**Scenario 2 — Background browser window keeps greyscale on**
1. Open Chrome with `reddit.com` loaded
2. Alt-tab to a different app (VS Code, File Explorer, etc.)
3. Wait up to 2 seconds
4. Expected: greyscale stays on

**Scenario 3 — Non-distraction site deactivates greyscale**
1. In Chrome, navigate from `reddit.com` to `google.com`
2. Wait up to 2 seconds
3. Expected: greyscale deactivates

**Scenario 4 — Minimised browser window does NOT keep greyscale on**
1. Minimise the Chrome window that had `reddit.com` open
2. Wait up to 2 seconds
3. Expected: greyscale deactivates

**Scenario 5 — Zen / Firefox URL detection still works**
1. Open Zen or Firefox, navigate to `reddit.com`
2. Wait up to 2 seconds
3. Expected: greyscale activates

**Scenario 6 — Title-based detection still works**
1. Open Chrome with `youtube.com` (title shows "YouTube - Google Chrome")
2. Wait up to 2 seconds
3. Expected: greyscale activates (via title scan, not URL)

**Step 1: Commit if all scenarios pass**

```bash
git add CutDistractions.ahk
git commit -m "Verified: all-windows UIA URL scan working for all five browsers"
```

If any scenario fails, stop and report which scenario failed and what actually happened.
