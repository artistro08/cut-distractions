#Requires AutoHotkey v2.0
#SingleInstance Force

; ─── Global State ───
global AppList := []
global ProcessList := []
global DisableHotkey := "^!g"
global DisableDuration := 3
global ScheduleHotkey := "^#!s"
global AlwaysOn := 0
global ExitPassword := ""
global ScheduleEnabled := 0
global ScheduleStart := "09:00"
global ScheduleEnd := "17:00"
global GreyscaleActive := false
global TempDisabled := false
global CurrentStatusText := "Status: Monitoring"
global CurrentScheduleText := "Schedule: OFF"

; ─── Dark Mode Globals ───
global CD_IsDark := false
global CD_SettingsGui := ""
global CD_DarkGuis := Map()  ; tracks hwnds of all active dark-mode GUIs
global GUI_DarkBrush := DllCall("CreateSolidBrush", "uint", 0x202020, "ptr")
global GUI_CtrlBrush := DllCall("CreateSolidBrush", "uint", 0x2b2b2b, "ptr")
global GUI_BorderBrush := DllCall("CreateSolidBrush", "uint", 0x2C2C2C, "ptr")
global GUI_FocusBrush := DllCall("CreateSolidBrush", "uint", 0x555555, "ptr")
global GUI_pAllowDarkModeForWindow := 0
global GUI_ButtonTracking := Map()
global GUI_EditFocused := Map()

; ─── Load Settings ───
global settingsFile
userSettingsFile := EnvGet("USERPROFILE") "\.config\cut-distractions\settings.ini"
settingsFile := FileExist(userSettingsFile) ? userSettingsFile : A_ScriptDir "\settings.ini"

appListRaw := IniRead(settingsFile, "Apps", "List", "YouTube,Twitter,Reddit,TikTok,Instagram")
for item in StrSplit(appListRaw, ",")
    AppList.Push(Trim(item))

processListRaw := IniRead(settingsFile, "Processes", "List", "chrome.exe,brave.exe,arc.exe,zen.exe,firefox.exe")
for item in StrSplit(processListRaw, ",")
    ProcessList.Push(Trim(item))

DisableHotkey := IniRead(settingsFile, "Hotkey", "DisableHotkey", "^!g")
DisableDuration := Integer(IniRead(settingsFile, "Hotkey", "DisableDuration", "3"))
ScheduleHotkey := IniRead(settingsFile, "Hotkey", "ScheduleHotkey", "^#!s")

AlwaysOn := Integer(IniRead(settingsFile, "General", "AlwaysOn", "0"))
ExitPassword := IniRead(settingsFile, "General", "ExitPassword", "")
ScheduleEnabled := Integer(IniRead(settingsFile, "Schedule", "Enabled", "0"))
ScheduleStart := IniRead(settingsFile, "Schedule", "StartTime", "09:00")
ScheduleEnd := IniRead(settingsFile, "Schedule", "EndTime", "17:00")

; ─── Dark Mode Detection & Init ───
try {
    CD_IsDark := (RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme") = 0)
} catch {
    CD_IsDark := false
}

try {
    uxthemeMod := DllCall("GetModuleHandle", "str", "uxtheme", "ptr")
    pSetPreferredAppMode := DllCall("GetProcAddress", "ptr", uxthemeMod, "ptr", 135, "ptr")
    if (pSetPreferredAppMode)
        DllCall(pSetPreferredAppMode, "int", 1) ; AllowDark
    GUI_pAllowDarkModeForWindow := DllCall("GetProcAddress", "ptr", uxthemeMod, "ptr", 133, "ptr")
    pFlush := DllCall("GetProcAddress", "ptr", uxthemeMod, "ptr", 136, "ptr")
    if (pFlush)
        DllCall(pFlush)
}

OnMessage(0x0133, CD_WM_CTLCOLOREDIT)    ; WM_CTLCOLOREDIT
OnMessage(0x0134, CD_WM_CTLCOLOREDIT)    ; WM_CTLCOLORLISTBOX
OnMessage(0x0138, CD_WM_CTLCOLORSTATIC)  ; WM_CTLCOLORSTATIC

; ─── Clear watchdog UserExited flag (we are running normally) ───
try RegWrite(0, "REG_DWORD", "HKCU\Software\CutDistractions", "UserExited")

; ─── Ensure Color Filter is set to Greyscale (FilterType=0) and hotkey is enabled ───
try {
    RegWrite(0, "REG_DWORD", "HKCU\Software\Microsoft\ColorFiltering", "FilterType")
    RegWrite(1, "REG_DWORD", "HKCU\Software\Microsoft\ColorFiltering", "HotkeyEnabled")
}

; ─── Register Hotkeys ───
Hotkey(DisableHotkey, OnDisableHotkey)
Hotkey(ScheduleHotkey, OnToggleSchedule)

; ─── Tray Icon ───
iconFile := A_ScriptDir "\CutDistractions.ico"
if FileExist(iconFile)
    TraySetIcon(iconFile)

; ─── Tray Menu ───
A_TrayMenu.Delete()
A_TrayMenu.Add("CutDistractions", (*) => "")
A_TrayMenu.Disable("CutDistractions")
A_TrayMenu.Add()
A_TrayMenu.Add("Status: Monitoring", (*) => "")
A_TrayMenu.Disable("Status: Monitoring")
scheduleLabel := "Schedule: " (ScheduleEnabled ? "ON" : "OFF")
CurrentScheduleText := scheduleLabel
A_TrayMenu.Add(scheduleLabel, OnToggleSchedule)
A_TrayMenu.Add()
A_TrayMenu.Add("Settings", OnOpenSettings)
A_TrayMenu.Default := "Settings"
A_TrayMenu.ClickCount := 1
A_TrayMenu.Add("Exit", TrayExit)

UpdateTrayStatus()

; ─── Register Window Event Hooks ───
global WinEventCallback := CallbackCreate(OnWindowEvent, "F", 7)

; Hook EVENT_SYSTEM_FOREGROUND (0x0003) - window focus changes
global WinEventHookFG := DllCall("SetWinEventHook"
    , "UInt", 0x0003, "UInt", 0x0003
    , "Ptr", 0, "Ptr", WinEventCallback
    , "UInt", 0, "UInt", 0, "UInt", 0x0000, "Ptr")

; Hook EVENT_OBJECT_SHOW (0x8002) and EVENT_OBJECT_HIDE (0x8003) - window show/hide
global WinEventHookShowHide := DllCall("SetWinEventHook"
    , "UInt", 0x8002, "UInt", 0x8003
    , "Ptr", 0, "Ptr", WinEventCallback
    , "UInt", 0, "UInt", 0, "UInt", 0x0000, "Ptr")

; Hook EVENT_SYSTEM_MINIMIZESTART (0x0016) and EVENT_SYSTEM_MINIMIZEEND (0x0017)
global WinEventHookMinimize := DllCall("SetWinEventHook"
    , "UInt", 0x0016, "UInt", 0x0017
    , "Ptr", 0, "Ptr", WinEventCallback
    , "UInt", 0, "UInt", 0, "UInt", 0x0000, "Ptr")

; Hook EVENT_OBJECT_NAMECHANGE (0x800C) - window title changes
global WinEventHookNameChange := DllCall("SetWinEventHook"
    , "UInt", 0x800C, "UInt", 0x800C
    , "Ptr", 0, "Ptr", WinEventCallback
    , "UInt", 0, "UInt", 0, "UInt", 0x0000, "Ptr")

; Polling timer as safety net (every 2 seconds) for cases events miss
SetTimer(CheckVisibleWindows, 2000)

; ─── Clean up on exit ───
OnExit(ExitHandler)

; ─── Check current window on startup ───
CheckVisibleWindows()

; Keep script running
Persistent()

; ═══════════════════════════════════════════
; Functions
; ═══════════════════════════════════════════

OnWindowEvent(hWinEventHook, event, hwnd, idObject, idChild, idEventThread, dwmsEventTime) {
    if (idObject != 0)
        return
    ; Debounce: reset timer on each event, only fire after 100ms of quiet
    SetTimer(CheckVisibleWindows, -100)
}

CheckVisibleWindows() {
    global TempDisabled, GreyscaleActive, ProcessList

    if TempDisabled
        return

    shouldGreyscale := false

    if IsWithinSchedule() {
        if AlwaysOn {
            shouldGreyscale := true
        } else if (ProcessList.Length > 0) {
            ; Process-scoped: only check windows whose exe is in ProcessList
            for appName in AppList {
                try {
                    windows := WinGetList(appName)
                    for hwnd in windows {
                        try {
                            if (WinGetMinMax(hwnd) = -1)
                                continue
                            procName := WinGetProcessName(hwnd)
                            for procExe in ProcessList {
                                if (procName = procExe) {
                                    shouldGreyscale := true
                                    break 3
                                }
                            }
                        }
                    }
                }
            }
        } else {
            ; No process list — original system-wide title search
            for appName in AppList {
                try {
                    windows := WinGetList(appName)
                    for hwnd in windows {
                        try {
                            if (WinGetMinMax(hwnd) != -1) {
                                shouldGreyscale := true
                                break 2
                            }
                        }
                    }
                }
            }
        }
    }

    if shouldGreyscale && !GreyscaleActive {
        SetGreyscale(true)
    } else if !shouldGreyscale && GreyscaleActive {
        SetGreyscale(false)
    }
}

SetGreyscale(enable) {
    global GreyscaleActive

    desiredState := enable ? 1 : 0

    try currentState := RegRead("HKCU\Software\Microsoft\ColorFiltering", "Active")
    catch
        currentState := 0

    if (currentState != desiredState) {
        RegWrite(desiredState, "REG_DWORD", "HKCU\Software\Microsoft\ColorFiltering", "Active")
        Run('atbroker.exe /colorfiltershortcut /resettransferkeys',, "Hide")
    }

    GreyscaleActive := enable
    UpdateTrayStatus()
}

TimeToMinutes(timeStr) {
    parts := StrSplit(timeStr, ":")
    return Integer(parts[1]) * 60 + Integer(parts[2])
}

IsWithinSchedule() {
    global ScheduleEnabled, ScheduleStart, ScheduleEnd

    if !ScheduleEnabled
        return true  ; No schedule = always active

    now := Integer(A_Hour) * 60 + Integer(A_Min)
    startMin := TimeToMinutes(ScheduleStart)
    endMin := TimeToMinutes(ScheduleEnd)

    if (startMin <= endMin)
        return (now >= startMin && now <= endMin)
    else  ; Spans midnight (e.g. 20:00 - 4:30)
        return (now >= startMin || now <= endMin)
}

OnDisableHotkey(*) {
    global TempDisabled

    if TempDisabled {
        ; Re-enable immediately: cancel pending timer and resume monitoring
        SetTimer(OnReEnable, 0)
        OnReEnable()
    } else {
        ; Disable greyscale temporarily
        TempDisabled := true
        SetGreyscale(false)
        UpdateTrayStatus()

        ; Re-enable after DisableDuration minutes
        SetTimer(OnReEnable, DisableDuration * 60000 * -1)
    }
}

OnReEnable() {
    global TempDisabled
    TempDisabled := false
    UpdateTrayStatus()
    CheckVisibleWindows()
}

OnToggleSchedule(*) {
    global ScheduleEnabled, settingsFile
    ScheduleEnabled := ScheduleEnabled ? 0 : 1
    IniWrite(ScheduleEnabled, settingsFile, "Schedule", "Enabled")
    UpdateTrayStatus()
    CheckVisibleWindows()
}

UpdateTrayStatus() {
    global TempDisabled, GreyscaleActive, CurrentStatusText, CurrentScheduleText, ScheduleEnabled

    if TempDisabled
        status := "Status: Paused"
    else if GreyscaleActive
        status := "Status: Greyscale ON"
    else
        status := "Status: Monitoring"

    if status != CurrentStatusText {
        try A_TrayMenu.Rename(CurrentStatusText, status)
        CurrentStatusText := status
    }

    scheduleStatus := "Schedule: " (ScheduleEnabled ? "ON" : "OFF")
    if scheduleStatus != CurrentScheduleText {
        try A_TrayMenu.Rename(CurrentScheduleText, scheduleStatus)
        CurrentScheduleText := scheduleStatus
    }

    A_IconTip := "CutDistractions - " status
}

OnOpenSettings(*) {
    ShowSettingsGui()
}

TrayExit(*) {
    global ExitPassword
    if (ExitPassword != "") {
        ShowExitPasswordDialog()
        return
    }
    ExitApp()
}

; ─── Dark Mode Subclasses & Helpers ───

CD_WM_CTLCOLOREDIT(wParam, lParam, msg, hwnd) {
    if (!CD_IsDark || !CD_DarkGuis.Has(hwnd))
        return
    DllCall("SetTextColor", "ptr", wParam, "uint", 0xE0E0E0)
    DllCall("SetBkColor", "ptr", wParam, "uint", 0x2b2b2b)
    return GUI_CtrlBrush
}

CD_WM_CTLCOLORSTATIC(wParam, lParam, msg, hwnd) {
    if (!CD_IsDark || !CD_DarkGuis.Has(hwnd))
        return
    DllCall("SetTextColor", "ptr", wParam, "uint", 0xE0E0E0)
    DllCall("SetBkMode", "ptr", wParam, "int", 1) ; TRANSPARENT
    return GUI_DarkBrush
}

; Edit control subclass: custom NC border painting to replace white border
global GUI_EditSubclassProc := CallbackCreate(GUI_EditSubclass, , 6)

GUI_EditSubclass(hwnd, uMsg, wParam, lParam, uIdSubclass, dwRefData) {
    if (uMsg = 0x0007) { ; WM_SETFOCUS - track focus and repaint border
        GUI_EditFocused[hwnd] := true
        DllCall("SendMessageW", "ptr", hwnd, "uint", 0x0085, "ptr", 1, "ptr", 0)
        return DllCall("comctl32\DefSubclassProc", "ptr", hwnd, "uint", uMsg, "ptr", wParam, "ptr", lParam, "ptr")
    }
    if (uMsg = 0x0008) { ; WM_KILLFOCUS - clear focus and repaint border
        GUI_EditFocused[hwnd] := false
        DllCall("SendMessageW", "ptr", hwnd, "uint", 0x0085, "ptr", 1, "ptr", 0)
        return DllCall("comctl32\DefSubclassProc", "ptr", hwnd, "uint", uMsg, "ptr", wParam, "ptr", lParam, "ptr")
    }
    if (uMsg = 0x0085) { ; WM_NCPAINT
        hdc := DllCall("GetWindowDC", "ptr", hwnd, "ptr")
        rc := Buffer(16)
        DllCall("GetWindowRect", "ptr", hwnd, "ptr", rc)
        w := NumGet(rc, 8, "int") - NumGet(rc, 0, "int")
        h := NumGet(rc, 12, "int") - NumGet(rc, 4, "int")
        bw := DllCall("GetSystemMetrics", "int", 45) ; SM_CXEDGE
        bh := DllCall("GetSystemMetrics", "int", 46) ; SM_CYEDGE
        ; Exclude the client area so hover/repaint never erases text
        DllCall("ExcludeClipRect", "ptr", hdc, "int", bw, "int", bh, "int", w - bw, "int", h - bh)
        ; Paint only the border ring with focus-aware color
        fullRc := Buffer(16)
        NumPut("int", 0, fullRc, 0)
        NumPut("int", 0, fullRc, 4)
        NumPut("int", w, fullRc, 8)
        NumPut("int", h, fullRc, 12)
        isFocused := GUI_EditFocused.Has(hwnd) && GUI_EditFocused[hwnd]
        DllCall("FillRect", "ptr", hdc, "ptr", fullRc, "ptr", isFocused ? GUI_FocusBrush : GUI_BorderBrush)
        DllCall("ReleaseDC", "ptr", hwnd, "ptr", hdc)
        return 0
    }
    if (uMsg = 0x0002) { ; WM_DESTROY
        if GUI_EditFocused.Has(hwnd)
            GUI_EditFocused.Delete(hwnd)
        DllCall("comctl32\RemoveWindowSubclass", "ptr", hwnd, "ptr", GUI_EditSubclassProc, "uint", 1)
    }
    return DllCall("comctl32\DefSubclassProc", "ptr", hwnd, "uint", uMsg, "ptr", wParam, "ptr", lParam, "ptr")
}

; Button control subclass: custom dark painting with hover/press states
global GUI_ButtonSubclassProc := CallbackCreate(GUI_ButtonSubclass, , 6)

GUI_ButtonSubclass(hwnd, uMsg, wParam, lParam, uIdSubclass, dwRefData) {
    if (uMsg = 0x0200) { ; WM_MOUSEMOVE
        if (!GUI_ButtonTracking.Has(hwnd) || !GUI_ButtonTracking[hwnd]) {
            tme := Buffer(24, 0)
            NumPut("uint", 24, tme, 0)
            NumPut("uint", 0x02, tme, 4)
            NumPut("ptr", hwnd, tme, 8)
            DllCall("TrackMouseEvent", "ptr", tme)
            GUI_ButtonTracking[hwnd] := true
            DllCall("InvalidateRect", "ptr", hwnd, "ptr", 0, "int", true)
        }
    }
    if (uMsg = 0x02A3) { ; WM_MOUSELEAVE
        GUI_ButtonTracking[hwnd] := false
        DllCall("InvalidateRect", "ptr", hwnd, "ptr", 0, "int", true)
    }
    if (uMsg = 0x0201 || uMsg = 0x0202) ; WM_LBUTTONDOWN / WM_LBUTTONUP
        DllCall("InvalidateRect", "ptr", hwnd, "ptr", 0, "int", true)
    if (uMsg = 0x000F) { ; WM_PAINT
        ps := Buffer(72)
        hdc := DllCall("BeginPaint", "ptr", hwnd, "ptr", ps, "ptr")
        rc := Buffer(16)
        DllCall("GetClientRect", "ptr", hwnd, "ptr", rc)
        w := NumGet(rc, 8, "int")
        h := NumGet(rc, 12, "int")
        state := DllCall("SendMessageW", "ptr", hwnd, "uint", 0x00F2, "ptr", 0, "ptr", 0) ; BM_GETSTATE
        isPushed := state & 0x0004
        isHot := GUI_ButtonTracking.Has(hwnd) && GUI_ButtonTracking[hwnd]
        if (isPushed) {
            bgColor := 0x404040
            borderColor := 0x666666
        } else if (isHot) {
            bgColor := 0x353535
            borderColor := 0x505050
        } else {
            bgColor := 0x2D2D2D
            borderColor := 0x454545
        }
        hBgBrush := DllCall("CreateSolidBrush", "uint", bgColor, "ptr")
        DllCall("FillRect", "ptr", hdc, "ptr", rc, "ptr", hBgBrush)
        DllCall("DeleteObject", "ptr", hBgBrush)
        hPen := DllCall("CreatePen", "int", 0, "int", 1, "uint", borderColor, "ptr")
        oldPen := DllCall("SelectObject", "ptr", hdc, "ptr", hPen, "ptr")
        hNullBrush := DllCall("GetStockObject", "int", 5, "ptr")
        oldBrush := DllCall("SelectObject", "ptr", hdc, "ptr", hNullBrush, "ptr")
        DllCall("RoundRect", "ptr", hdc, "int", 0, "int", 0, "int", w - 1, "int", h - 1, "int", 4, "int", 4)
        DllCall("SelectObject", "ptr", hdc, "ptr", oldPen, "ptr")
        DllCall("SelectObject", "ptr", hdc, "ptr", oldBrush, "ptr")
        DllCall("DeleteObject", "ptr", hPen)
        textLen := DllCall("GetWindowTextLengthW", "ptr", hwnd)
        textBuf := Buffer((textLen + 1) * 2)
        DllCall("GetWindowTextW", "ptr", hwnd, "ptr", textBuf, "int", textLen + 1)
        hFont := DllCall("SendMessageW", "ptr", hwnd, "uint", 0x0031, "ptr", 0, "ptr", 0, "ptr") ; WM_GETFONT
        oldFont := DllCall("SelectObject", "ptr", hdc, "ptr", hFont, "ptr")
        DllCall("SetBkMode", "ptr", hdc, "int", 1)
        DllCall("SetTextColor", "ptr", hdc, "uint", 0xE0E0E0)
        DllCall("DrawTextW", "ptr", hdc, "ptr", textBuf, "int", textLen, "ptr", rc, "uint", 0x25) ; DT_CENTER|DT_VCENTER|DT_SINGLELINE
        DllCall("SelectObject", "ptr", hdc, "ptr", oldFont, "ptr")
        DllCall("EndPaint", "ptr", hwnd, "ptr", ps)
        return 0
    }
    if (uMsg = 0x0002) { ; WM_DESTROY
        if (GUI_ButtonTracking.Has(hwnd))
            GUI_ButtonTracking.Delete(hwnd)
        DllCall("comctl32\RemoveWindowSubclass", "ptr", hwnd, "ptr", GUI_ButtonSubclassProc, "uint", 3)
    }
    return DllCall("comctl32\DefSubclassProc", "ptr", hwnd, "uint", uMsg, "ptr", wParam, "ptr", lParam, "ptr")
}

; GroupBox control subclass: custom dark border + label painting
global GUI_GroupBoxSubclassProc := CallbackCreate(GUI_GroupBoxSubclass, , 6)

GUI_GroupBoxSubclass(hwnd, uMsg, wParam, lParam, uIdSubclass, dwRefData) {
    if (uMsg = 0x000F) { ; WM_PAINT
        ps := Buffer(72)
        hdc := DllCall("BeginPaint", "ptr", hwnd, "ptr", ps, "ptr")
        rc := Buffer(16)
        DllCall("GetClientRect", "ptr", hwnd, "ptr", rc)
        w := NumGet(rc, 8, "int")
        h := NumGet(rc, 12, "int")
        textLen := DllCall("GetWindowTextLengthW", "ptr", hwnd)
        textBuf := Buffer((textLen + 1) * 2)
        DllCall("GetWindowTextW", "ptr", hwnd, "ptr", textBuf, "int", textLen + 1)
        hFont := DllCall("SendMessageW", "ptr", hwnd, "uint", 0x0031, "ptr", 0, "ptr", 0, "ptr") ; WM_GETFONT
        oldFont := DllCall("SelectObject", "ptr", hdc, "ptr", hFont, "ptr")
        textSize := Buffer(8)
        DllCall("GetTextExtentPoint32W", "ptr", hdc, "ptr", textBuf, "int", textLen, "ptr", textSize)
        textW := NumGet(textSize, 0, "int")
        textH := NumGet(textSize, 4, "int")
        DllCall("SetBkMode", "ptr", hdc, "int", 1)
        DllCall("FillRect", "ptr", hdc, "ptr", rc, "ptr", GUI_DarkBrush)
        borderTop := textH // 2
        hPen := DllCall("CreatePen", "int", 0, "int", 1, "uint", 0x2C2C2C, "ptr")
        oldPen := DllCall("SelectObject", "ptr", hdc, "ptr", hPen, "ptr")
        hNullBrush := DllCall("GetStockObject", "int", 5, "ptr")
        oldBrush := DllCall("SelectObject", "ptr", hdc, "ptr", hNullBrush, "ptr")
        DllCall("RoundRect", "ptr", hdc, "int", 0, "int", borderTop, "int", w - 1, "int", h - 1, "int", 6, "int", 6)
        DllCall("SelectObject", "ptr", hdc, "ptr", oldPen, "ptr")
        DllCall("SelectObject", "ptr", hdc, "ptr", oldBrush, "ptr")
        DllCall("DeleteObject", "ptr", hPen)
        if (textLen > 0) {
            textLeft := 9
            clearRc := Buffer(16)
            NumPut("int", textLeft - 2, clearRc, 0)
            NumPut("int", 0, clearRc, 4)
            NumPut("int", textLeft + textW + 2, clearRc, 8)
            NumPut("int", textH, clearRc, 12)
            DllCall("FillRect", "ptr", hdc, "ptr", clearRc, "ptr", GUI_DarkBrush)
            DllCall("SetTextColor", "ptr", hdc, "uint", 0xE0E0E0)
            DllCall("TextOutW", "ptr", hdc, "int", textLeft, "int", 0, "ptr", textBuf, "int", textLen)
        }
        DllCall("SelectObject", "ptr", hdc, "ptr", oldFont, "ptr")
        DllCall("EndPaint", "ptr", hwnd, "ptr", ps)
        return 0
    }
    if (uMsg = 0x0014) ; WM_ERASEBKGND
        return 1
    if (uMsg = 0x0002) ; WM_DESTROY
        DllCall("comctl32\RemoveWindowSubclass", "ptr", hwnd, "ptr", GUI_GroupBoxSubclassProc, "uint", 2)
    return DllCall("comctl32\DefSubclassProc", "ptr", hwnd, "uint", uMsg, "ptr", wParam, "ptr", lParam, "ptr")
}

; UpDown (spinner) control subclass: fully custom dark painting
global GUI_UpDownSubclassProc := CallbackCreate(GUI_UpDownSubclass, , 6)
global GUI_UpDownHot := Map() ; 0/missing=none, 1=top(up), 2=bottom(down)

GUI_UpDownSubclass(hwnd, uMsg, wParam, lParam, uIdSubclass, dwRefData) {
    if (uMsg = 0x0200) { ; WM_MOUSEMOVE - track which half is hovered
        if (!GUI_UpDownHot.Has(hwnd) || GUI_UpDownHot[hwnd] = 0) {
            tme := Buffer(24, 0)
            NumPut("uint", 24, tme, 0)
            NumPut("uint", 0x02, tme, 4)
            NumPut("ptr", hwnd, tme, 8)
            DllCall("TrackMouseEvent", "ptr", tme)
        }
        rc := Buffer(16)
        DllCall("GetClientRect", "ptr", hwnd, "ptr", rc)
        h := NumGet(rc, 12, "int")
        cy := (lParam >> 16) & 0xFFFF
        newHot := (cy < h // 2) ? 1 : 2
        if (!GUI_UpDownHot.Has(hwnd) || GUI_UpDownHot[hwnd] != newHot) {
            GUI_UpDownHot[hwnd] := newHot
            DllCall("InvalidateRect", "ptr", hwnd, "ptr", 0, "int", true)
        }
    }
    if (uMsg = 0x02A3) { ; WM_MOUSELEAVE
        GUI_UpDownHot.Delete(hwnd)
        DllCall("InvalidateRect", "ptr", hwnd, "ptr", 0, "int", true)
    }
    if (uMsg = 0x0201 || uMsg = 0x0202) ; WM_LBUTTONDOWN / WM_LBUTTONUP
        DllCall("InvalidateRect", "ptr", hwnd, "ptr", 0, "int", true)
    if (uMsg = 0x000F) { ; WM_PAINT
        ps := Buffer(72)
        hdc := DllCall("BeginPaint", "ptr", hwnd, "ptr", ps, "ptr")
        rc := Buffer(16)
        DllCall("GetClientRect", "ptr", hwnd, "ptr", rc)
        w := NumGet(rc, 8, "int")
        h := NumGet(rc, 12, "int")
        midH := h // 2
        hotHalf := GUI_UpDownHot.Has(hwnd) ? GUI_UpDownHot[hwnd] : 0
        isLBDown := (DllCall("GetKeyState", "int", 0x01) & 0x8000) != 0
        ; Top half (up button)
        topBg := (hotHalf = 1 && isLBDown) ? 0x404040 : (hotHalf = 1) ? 0x353535 : 0x2D2D2D
        topRc := Buffer(16)
        NumPut("int", 0, topRc, 0)
        NumPut("int", 0, topRc, 4)
        NumPut("int", w, topRc, 8)
        NumPut("int", midH, topRc, 12)
        hBrush := DllCall("CreateSolidBrush", "uint", topBg, "ptr")
        DllCall("FillRect", "ptr", hdc, "ptr", topRc, "ptr", hBrush)
        DllCall("DeleteObject", "ptr", hBrush)
        ; Bottom half (down button)
        botBg := (hotHalf = 2 && isLBDown) ? 0x404040 : (hotHalf = 2) ? 0x353535 : 0x2D2D2D
        botRc := Buffer(16)
        NumPut("int", 0, botRc, 0)
        NumPut("int", midH, botRc, 4)
        NumPut("int", w, botRc, 8)
        NumPut("int", h, botRc, 12)
        hBrush := DllCall("CreateSolidBrush", "uint", botBg, "ptr")
        DllCall("FillRect", "ptr", hdc, "ptr", botRc, "ptr", hBrush)
        DllCall("DeleteObject", "ptr", hBrush)
        ; Outer border + divider line
        hPen := DllCall("CreatePen", "int", 0, "int", 1, "uint", 0x454545, "ptr")
        oldPen := DllCall("SelectObject", "ptr", hdc, "ptr", hPen, "ptr")
        hNull := DllCall("GetStockObject", "int", 5, "ptr")
        oldBrush := DllCall("SelectObject", "ptr", hdc, "ptr", hNull, "ptr")
        DllCall("Rectangle", "ptr", hdc, "int", 0, "int", 0, "int", w, "int", h)
        DllCall("MoveToEx", "ptr", hdc, "int", 0, "int", midH, "ptr", 0)
        DllCall("LineTo", "ptr", hdc, "int", w, "int", midH)
        DllCall("SelectObject", "ptr", hdc, "ptr", oldPen, "ptr")
        DllCall("SelectObject", "ptr", hdc, "ptr", oldBrush, "ptr")
        DllCall("DeleteObject", "ptr", hPen)
        ; Arrows using unicode triangles with the default GUI font
        hFont := DllCall("GetStockObject", "int", 17, "ptr") ; DEFAULT_GUI_FONT
        oldFont := DllCall("SelectObject", "ptr", hdc, "ptr", hFont, "ptr")
        DllCall("SetBkMode", "ptr", hdc, "int", 1)
        DllCall("SetTextColor", "ptr", hdc, "uint", 0xC0C0C0)
        upRc := Buffer(16)
        NumPut("int", 0, upRc, 0)
        NumPut("int", 0, upRc, 4)
        NumPut("int", w, upRc, 8)
        NumPut("int", midH, upRc, 12)
        DllCall("DrawTextW", "ptr", hdc, "wstr", "▲", "int", -1, "ptr", upRc, "uint", 0x25)
        dnRc := Buffer(16)
        NumPut("int", 0, dnRc, 0)
        NumPut("int", midH, dnRc, 4)
        NumPut("int", w, dnRc, 8)
        NumPut("int", h, dnRc, 12)
        DllCall("DrawTextW", "ptr", hdc, "wstr", "▼", "int", -1, "ptr", dnRc, "uint", 0x25)
        DllCall("SelectObject", "ptr", hdc, "ptr", oldFont, "ptr")
        DllCall("EndPaint", "ptr", hwnd, "ptr", ps)
        return 0
    }
    if (uMsg = 0x0002) { ; WM_DESTROY
        if GUI_UpDownHot.Has(hwnd)
            GUI_UpDownHot.Delete(hwnd)
        DllCall("comctl32\RemoveWindowSubclass", "ptr", hwnd, "ptr", GUI_UpDownSubclassProc, "uint", 5)
    }
    return DllCall("comctl32\DefSubclassProc", "ptr", hwnd, "uint", uMsg, "ptr", wParam, "ptr", lParam, "ptr")
}

; Exit password edit subclass: blocks all paste operations (WM_PASTE)
global ExitPwd_SubclassProc := CallbackCreate(ExitPwd_EditSubclass, , 6)

ExitPwd_EditSubclass(hwnd, uMsg, wParam, lParam, uIdSubclass, dwRefData) {
    if (uMsg = 0x0302) ; WM_PASTE - block clipboard paste
        return 0
    if (uMsg = 0x0002) ; WM_DESTROY
        DllCall("comctl32\RemoveWindowSubclass", "ptr", hwnd, "ptr", ExitPwd_SubclassProc, "uint", 10)
    return DllCall("comctl32\DefSubclassProc", "ptr", hwnd, "uint", uMsg, "ptr", wParam, "ptr", lParam, "ptr")
}

GUI_AllowDarkMode(hwnd) {
    if (GUI_pAllowDarkModeForWindow)
        DllCall(GUI_pAllowDarkModeForWindow, "ptr", hwnd, "int", true)
}

GUI_SetDarkTheme(ctrlHwnd) {
    GUI_AllowDarkMode(ctrlHwnd)
    DllCall("uxtheme\SetWindowTheme", "ptr", ctrlHwnd, "str", "DarkMode_Explorer", "ptr", 0)
}

GUI_ApplyDarkTitle(guiObj) {
    GUI_AllowDarkMode(guiObj.Hwnd)
    attr := VerCompare(A_OSVersion, "10.0.18985") >= 0 ? 20 : 19
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", guiObj.Hwnd, "int", attr, "int*", true, "int", 4)
}

; Add an Edit control, with dark theming when in dark mode
CD_DarkEdit(guiObj, opts, default := "") {
    ctrl := guiObj.Add("Edit", opts, default)
    if CD_IsDark {
        GUI_SetDarkTheme(ctrl.Hwnd)
        DllCall("comctl32\SetWindowSubclass", "ptr", ctrl.Hwnd, "ptr", GUI_EditSubclassProc, "uint", 1, "ptr", 0)
    }
    return ctrl
}

; Add a Checkbox, with dark theming when in dark mode
CD_DarkCheckbox(guiObj, opts, label) {
    ctrl := guiObj.Add("Checkbox", opts, label)
    if CD_IsDark
        GUI_SetDarkTheme(ctrl.Hwnd)
    return ctrl
}

; Add a GroupBox, with dark subclass when in dark mode
CD_DarkGroupBox(guiObj, opts, label) {
    ctrl := guiObj.Add("GroupBox", opts, label)
    if CD_IsDark {
        DllCall("uxtheme\SetWindowTheme", "ptr", ctrl.Hwnd, "ptr", 0, "str", "")
        DllCall("comctl32\SetWindowSubclass", "ptr", ctrl.Hwnd, "ptr", GUI_GroupBoxSubclassProc, "uint", 2, "ptr", 0)
    }
    return ctrl
}

; Add a UpDown spinner, with fully custom dark painting when in dark mode
CD_DarkUpDown(guiObj, opts, default := 0) {
    ctrl := guiObj.Add("UpDown", opts, default)
    if CD_IsDark {
        DllCall("uxtheme\SetWindowTheme", "ptr", ctrl.Hwnd, "ptr", 0, "str", "")
        DllCall("comctl32\SetWindowSubclass", "ptr", ctrl.Hwnd, "ptr", GUI_UpDownSubclassProc, "uint", 5, "ptr", 0)
    }
    return ctrl
}

; Add a Button, with dark subclass when in dark mode
CD_DarkButton(guiObj, opts, label) {
    ctrl := guiObj.Add("Button", opts, label)
    if CD_IsDark {
        DllCall("uxtheme\SetWindowTheme", "ptr", ctrl.Hwnd, "ptr", 0, "str", "")
        DllCall("comctl32\SetWindowSubclass", "ptr", ctrl.Hwnd, "ptr", GUI_ButtonSubclassProc, "uint", 3, "ptr", 0)
    }
    return ctrl
}

; ─── Settings GUI ───
ShowSettingsGui() {
    global settingsFile, AppList, DisableHotkey, DisableDuration, ScheduleHotkey
    global ScheduleEnabled, ScheduleStart, ScheduleEnd, AlwaysOn
    global CD_IsDark, CD_SettingsGui, ProcessList, ExitPassword

    ; Destroy existing GUI if open
    try {
        WinClose("CutDistractions Settings")
    }

    sg := Gui("+AlwaysOnTop", "CutDistractions Settings")
    sg.MarginX := 15
    sg.MarginY := 10

    if CD_IsDark {
        sg.BackColor := "0x202020"
        sg.SetFont("s9 cE0E0E0", "Segoe UI")
        GUI_ApplyDarkTitle(sg)
    }

    CD_SettingsGui := sg
    CD_DarkGuis[sg.Hwnd] := true

    ; Always On checkbox
    CD_DarkCheckbox(sg, "vAlwaysOn Section " (AlwaysOn ? "Checked" : ""), "Always On (greyscale stays active regardless of open apps)")

    ; Exit password
    sg.AddText("xs y+8", "Exit Password (leave blank for none):")
    CD_DarkEdit(sg, "vExitPassword w200", ExitPassword)

    ; Apps section
    sg.AddText("xs", "Apps (comma-separated):")
    appListStr := ""
    for i, app in AppList {
        appListStr .= (i > 1 ? "," : "") . app
    }
    CD_DarkEdit(sg, "vAppList w350 r3 -VScroll", appListStr)

    ; Active Processes section
    CD_DarkGroupBox(sg, "w350 h65 Section xs", "Active Processes")
    sg.AddText("xp+10 yp+22", "Only check these processes (comma-separated, empty = all):")
    processListStr := ""
    for i, proc in ProcessList {
        processListStr .= (i > 1 ? "," : "") . proc
    }
    CD_DarkEdit(sg, "vProcessList w310 xs+10 y+5", processListStr)

    ; Hotkey section
    CD_DarkGroupBox(sg, "w350 h110 Section xs", "Hotkey")
    sg.AddText("xp+10 yp+25", "Disable Hotkey:")
    CD_DarkEdit(sg, "vDisableHotkey w150 x+10 yp-3", DisableHotkey)
    sg.AddText("xs+10 y+10", "Duration (minutes):")
    CD_DarkEdit(sg, "vDisableDuration w60 x+10 yp-3 Number", DisableDuration)
    CD_DarkUpDown(sg, "Range1-60", DisableDuration)
    sg.AddText("xs+10 y+10", "Schedule Toggle Hotkey:")
    CD_DarkEdit(sg, "vScheduleHotkey w150 x+10 yp-3", ScheduleHotkey)

    ; Schedule section
    CD_DarkGroupBox(sg, "w350 h110 Section xs", "Schedule")
    CD_DarkCheckbox(sg, "vScheduleEnabled xp+10 yp+25 " (ScheduleEnabled ? "Checked" : ""), "Enable Schedule")
    sg.AddText("xs+10 y+10", "Start Time (HH:mm):")
    CD_DarkEdit(sg, "vScheduleStart w80 x+10 yp-3", ScheduleStart)
    sg.AddText("xs+10 y+10", "End Time (HH:mm):")
    CD_DarkEdit(sg, "vScheduleEnd w80 x+10 yp-3", ScheduleEnd)

    ; Buttons
    saveBtn := CD_DarkButton(sg, "xs w100 Section Default", "Save")
    saveBtn.OnEvent("Click", SaveSettings.Bind(sg))
    cancelBtn := CD_DarkButton(sg, "x+10 w100", "Cancel")
    cancelBtn.OnEvent("Click", (*) => sg.Destroy())
    resetBtn := CD_DarkButton(sg, "x+10 w130", "Reset Registry")
    resetBtn.OnEvent("Click", ResetRegistry)

    sg.OnEvent("Escape", (*) => (CD_DarkGuis.Delete(sg.Hwnd), sg.Destroy()))
    sg.OnEvent("Close",  (*) => (CD_DarkGuis.Delete(sg.Hwnd), sg.Destroy()))
    sg.Show()
}

ShowExitPasswordDialog() {
    global ExitPassword, ExitPwd_SubclassProc, CD_IsDark, CD_DarkGuis

    dlg := Gui("+AlwaysOnTop", "Exit CutDistractions")
    dlg.MarginX := 15
    dlg.MarginY := 12

    if CD_IsDark {
        dlg.BackColor := "0x202020"
        dlg.SetFont("s9 cE0E0E0", "Segoe UI")
        GUI_ApplyDarkTitle(dlg)
        CD_DarkGuis[dlg.Hwnd] := true
    }

    dlg.AddText("w260", "Enter password to exit CutDistractions:")
    pwdEdit := CD_DarkEdit(dlg, "vPassword w260")

    ; Block paste — subclass ID 10, distinct from dark-mode subclass ID 1
    DllCall("comctl32\SetWindowSubclass", "ptr", pwdEdit.Hwnd, "ptr", ExitPwd_SubclassProc, "uint", 10, "ptr", 0)

    okBtn  := CD_DarkButton(dlg, "w120 Default", "Exit")
    cancelBtn := CD_DarkButton(dlg, "x+10 w120", "Cancel")

    okBtn.OnEvent("Click", CheckAndExit)
    cancelBtn.OnEvent("Click", (*) => (CD_DarkGuis.Delete(dlg.Hwnd), dlg.Destroy()))
    dlg.OnEvent("Escape", (*) => (CD_DarkGuis.Delete(dlg.Hwnd), dlg.Destroy()))
    dlg.OnEvent("Close",  (*) => (CD_DarkGuis.Delete(dlg.Hwnd), dlg.Destroy()))

    CheckAndExit(*) {
        saved := dlg.Submit(false)
        if (saved.Password = ExitPassword) {
            ; Tell the watchdog this was an intentional exit — do not restart
            try RegWrite(1, "REG_DWORD", "HKCU\Software\CutDistractions", "UserExited")
            CD_DarkGuis.Delete(dlg.Hwnd)
            dlg.Destroy()
            ExitApp()
        } else {
            MsgBox("Incorrect password.", "Exit CutDistractions", "48 Owner" . dlg.Hwnd)
            pwdEdit.Value := ""
            pwdEdit.Focus()
        }
    }

    dlg.Show("AutoSize")
}

SaveSettings(sg, *) {
    global settingsFile, ProcessList, CD_DarkGuis, CD_SettingsGui

    ; Collect values WITHOUT hiding the GUI so it stays visible if validation fails
    saved := sg.Submit(false)

    ; Validate time format
    if !RegExMatch(saved.ScheduleStart, "^\d{1,2}:\d{2}$") {
        MsgBox("Invalid Start Time format. Use HH:mm (e.g. 09:00)", "Error", 48)
        return
    }
    if !RegExMatch(saved.ScheduleEnd, "^\d{1,2}:\d{2}$") {
        MsgBox("Invalid End Time format. Use HH:mm (e.g. 17:00)", "Error", 48)
        return
    }

    ; Write to settings file
    try {
        IniWrite(saved.AlwaysOn, settingsFile, "General", "AlwaysOn")
        IniWrite(saved.ExitPassword, settingsFile, "General", "ExitPassword")
        IniWrite(Trim(saved.AppList), settingsFile, "Apps", "List")
        IniWrite(Trim(saved.DisableHotkey), settingsFile, "Hotkey", "DisableHotkey")
        IniWrite(saved.DisableDuration, settingsFile, "Hotkey", "DisableDuration")
        IniWrite(Trim(saved.ScheduleHotkey), settingsFile, "Hotkey", "ScheduleHotkey")
        IniWrite(saved.ScheduleEnabled, settingsFile, "Schedule", "Enabled")
        IniWrite(saved.ScheduleStart, settingsFile, "Schedule", "StartTime")
        IniWrite(saved.ScheduleEnd, settingsFile, "Schedule", "EndTime")
        IniWrite(Trim(saved.ProcessList), settingsFile, "Processes", "List")
    } catch as err {
        MsgBox("Failed to save settings:`n" err.Message "`n`nFile: " settingsFile, "Save Error", 16)
        return
    }

    ; Reload to apply changes
    CD_DarkGuis.Delete(sg.Hwnd)
    CD_SettingsGui := ""
    sg.Destroy()
    Reload()
}

ResetRegistry(*) {
    global CD_SettingsGui
    try {
        RegDeleteKey("HKCU\Software\Microsoft\ColorFiltering")
    }
    RegWrite(0, "REG_DWORD", "HKCU\Software\Microsoft\ColorFiltering", "FilterType")
    RegWrite(1, "REG_DWORD", "HKCU\Software\Microsoft\ColorFiltering", "HotkeyEnabled")
    RegWrite(0, "REG_DWORD", "HKCU\Software\Microsoft\ColorFiltering", "Active")
    MsgBox("Registry keys reset successfully.", "CutDistractions", "64 Owner" . CD_SettingsGui.Hwnd)
}

ExitHandler(exitReason, exitCode) {
    global WinEventHookFG, WinEventHookShowHide, WinEventHookMinimize, WinEventHookNameChange, WinEventCallback, GreyscaleActive

    ; Restore color on exit
    if GreyscaleActive {
        try {
            currentState := RegRead("HKCU\Software\Microsoft\ColorFiltering", "Active")
            if (currentState = 1) {
                RegWrite(0, "REG_DWORD", "HKCU\Software\Microsoft\ColorFiltering", "Active")
                Run('atbroker.exe /colorfiltershortcut /resettransferkeys',, "Hide")
            }
        }
        GreyscaleActive := false
    }

    ; Unhook window events
    for hookVar in [WinEventHookFG, WinEventHookShowHide, WinEventHookMinimize, WinEventHookNameChange] {
        if hookVar
            DllCall("UnhookWinEvent", "Ptr", hookVar)
    }
    WinEventHookFG := 0
    WinEventHookShowHide := 0
    WinEventHookMinimize := 0
    WinEventHookNameChange := 0
    if WinEventCallback {
        CallbackFree(WinEventCallback)
        WinEventCallback := 0
    }
}
