#Requires AutoHotkey v2.0
#SingleInstance Force

; ─── Global State ───
global AppList := []
global DisableHotkey := "^!g"
global DisableDuration := 3
global AlwaysOn := 0
global ScheduleEnabled := 0
global ScheduleStart := "09:00"
global ScheduleEnd := "17:00"
global GreyscaleActive := false
global TempDisabled := false
global CurrentStatusText := "Status: Monitoring"

; ─── Load Settings ───
global settingsFile
userSettingsFile := EnvGet("USERPROFILE") "\.config\cut-distractions\settings.ini"
settingsFile := FileExist(userSettingsFile) ? userSettingsFile : A_ScriptDir "\settings.ini"

appListRaw := IniRead(settingsFile, "Apps", "List", "YouTube,Twitter,Reddit,TikTok,Instagram")
for item in StrSplit(appListRaw, ",")
    AppList.Push(Trim(item))

DisableHotkey := IniRead(settingsFile, "Hotkey", "DisableHotkey", "^!g")
DisableDuration := Integer(IniRead(settingsFile, "Hotkey", "DisableDuration", "3"))

AlwaysOn := Integer(IniRead(settingsFile, "General", "AlwaysOn", "0"))
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
    global TempDisabled, GreyscaleActive

    if TempDisabled
        return

    shouldGreyscale := false

    if IsWithinSchedule() {
        if AlwaysOn {
            shouldGreyscale := true
        } else {
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

OnOpenSettings(*) {
    ShowSettingsGui()
}

TrayExit(*) {
    ExitApp()
}

; ─── Settings GUI ───
ShowSettingsGui() {
    global settingsFile, AppList, DisableHotkey, DisableDuration
    global ScheduleEnabled, ScheduleStart, ScheduleEnd, AlwaysOn

    ; Destroy existing GUI if open
    try {
        WinClose("CutDistractions Settings")
    }

    sg := Gui("+AlwaysOnTop", "CutDistractions Settings")
    sg.MarginX := 15
    sg.MarginY := 10

    ; Always On checkbox
    sg.AddCheckBox("vAlwaysOn Section " (AlwaysOn ? "Checked" : ""), "Always On (greyscale stays active regardless of open apps)")

    ; Apps section
    sg.AddText("xs", "Apps (comma-separated):")
    appListStr := ""
    for i, app in AppList {
        appListStr .= (i > 1 ? "," : "") . app
    }
    sg.AddEdit("vAppList w350 r3", appListStr)

    ; Hotkey section
    sg.AddGroupBox("w350 h80 Section xs", "Hotkey")
    sg.AddText("xp+10 yp+25", "Disable Hotkey:")
    sg.AddEdit("vDisableHotkey w150 x+10 yp-3", DisableHotkey)
    sg.AddText("xs+10 y+10", "Duration (minutes):")
    sg.AddEdit("vDisableDuration w60 x+10 yp-3 Number", DisableDuration)
    sg.AddUpDown("Range1-60", DisableDuration)

    ; Schedule section
    sg.AddGroupBox("w350 h110 Section xs", "Schedule")
    sg.AddCheckBox("vScheduleEnabled xp+10 yp+25 " (ScheduleEnabled ? "Checked" : ""), "Enable Schedule")
    sg.AddText("xs+10 y+10", "Start Time (HH:mm):")
    sg.AddEdit("vScheduleStart w80 x+10 yp-3", ScheduleStart)
    sg.AddText("xs+10 y+10", "End Time (HH:mm):")
    sg.AddEdit("vScheduleEnd w80 x+10 yp-3", ScheduleEnd)

    ; Buttons
    sg.AddButton("xs w100 Section Default", "Save").OnEvent("Click", SaveSettings.Bind(sg))
    sg.AddButton("x+10 w100", "Cancel").OnEvent("Click", (*) => sg.Destroy())

    sg.OnEvent("Escape", (*) => sg.Destroy())
    sg.OnEvent("Close", (*) => sg.Destroy())
    sg.Show()
}

SaveSettings(sg, *) {
    global settingsFile

    saved := sg.Submit()

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
    IniWrite(saved.AlwaysOn, settingsFile, "General", "AlwaysOn")
    IniWrite(Trim(saved.AppList), settingsFile, "Apps", "List")
    IniWrite(Trim(saved.DisableHotkey), settingsFile, "Hotkey", "DisableHotkey")
    IniWrite(saved.DisableDuration, settingsFile, "Hotkey", "DisableDuration")
    IniWrite(saved.ScheduleEnabled, settingsFile, "Schedule", "Enabled")
    IniWrite(saved.ScheduleStart, settingsFile, "Schedule", "StartTime")
    IniWrite(saved.ScheduleEnd, settingsFile, "Schedule", "EndTime")

    ; Reload to apply changes
    Reload()
}

ExitHandler(exitReason, exitCode) {
    global WinEventHookFG, WinEventHookShowHide, WinEventHookMinimize, WinEventCallback, GreyscaleActive

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
