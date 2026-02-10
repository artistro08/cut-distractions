#Requires AutoHotkey v2.0
#SingleInstance Force

; ─── Global State ───
global AppList := []
global DisableHotkey := "^!g"
global DisableDuration := 3
global ScheduleEnabled := 0
global ScheduleStart := "09:00"
global ScheduleEnd := "17:00"
global GreyscaleActive := false
global TempDisabled := false
global CurrentStatusText := "Status: Monitoring"

; ─── Load Settings ───
userSettingsFile := EnvGet("USERPROFILE") "\.config\cut-distractions\settings.ini"
settingsFile := FileExist(userSettingsFile) ? userSettingsFile : A_ScriptDir "\settings.ini"

appListRaw := IniRead(settingsFile, "Apps", "List", "YouTube,Twitter,Reddit,TikTok,Instagram")
for item in StrSplit(appListRaw, ",")
    AppList.Push(Trim(item))

DisableHotkey := IniRead(settingsFile, "Hotkey", "DisableHotkey", "^!g")
DisableDuration := Integer(IniRead(settingsFile, "Hotkey", "DisableDuration", "3"))

ScheduleEnabled := Integer(IniRead(settingsFile, "Schedule", "Enabled", "0"))
ScheduleStart := IniRead(settingsFile, "Schedule", "StartTime", "09:00")
ScheduleEnd := IniRead(settingsFile, "Schedule", "EndTime", "17:00")

; ─── Ensure Color Filter is set to Greyscale (FilterType=0) and hotkey is enabled ───
try {
    RegWrite(0, "REG_DWORD", "HKCU\Software\Microsoft\ColorFiltering", "FilterType")
    RegWrite(1, "REG_DWORD", "HKCU\Software\Microsoft\ColorFiltering", "HotkeyEnabled")
}

; ─── Register Hotkey ───
Hotkey(DisableHotkey, OnDisableHotkey)

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
A_TrayMenu.Add()
A_TrayMenu.Add("Reload Settings", OnReloadSettings)
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
    CheckVisibleWindows()
}

CheckVisibleWindows() {
    global TempDisabled, GreyscaleActive

    if TempDisabled
        return

    shouldGreyscale := false

    if IsWithinSchedule() {
        ; Check all visible (non-minimized) windows against the app list
        for appName in AppList {
            try {
                windows := WinGetList(appName)
                for hwnd in windows {
                    try {
                        minMax := WinGetMinMax(hwnd)
                        ; minMax: -1=minimized, 0=normal, 1=maximized
                        if (minMax != -1) {
                            shouldGreyscale := true
                            break 2
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

    ; Read current state from registry
    try currentState := RegRead("HKCU\Software\Microsoft\ColorFiltering", "Active")
    catch
        currentState := 0

    desiredState := enable ? 1 : 0

    ; Only toggle if current state differs from desired
    if (currentState != desiredState) {
        ; Win+Ctrl+C is the OS-native color filter toggle
        Send("#^c")
        Sleep(50)
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

UpdateTrayStatus() {
    global TempDisabled, GreyscaleActive, CurrentStatusText

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

    A_IconTip := "CutDistractions - " status
}

OnReloadSettings(*) {
    Reload()
}

TrayExit(*) {
    ExitApp()
}

ExitHandler(exitReason, exitCode) {
    global WinEventHookFG, WinEventHookShowHide, WinEventHookMinimize, WinEventCallback, GreyscaleActive

    ; Restore color on exit
    if GreyscaleActive {
        try {
            currentState := RegRead("HKCU\Software\Microsoft\ColorFiltering", "Active")
            if (currentState = 1)
                Send("#^c")
        }
        GreyscaleActive := false
    }

    ; Unhook window events
    for hookVar in [WinEventHookFG, WinEventHookShowHide, WinEventHookMinimize] {
        if hookVar
            DllCall("UnhookWinEvent", "Ptr", hookVar)
    }
    WinEventHookFG := 0
    WinEventHookShowHide := 0
    WinEventHookMinimize := 0
    if WinEventCallback {
        CallbackFree(WinEventCallback)
        WinEventCallback := 0
    }
}
