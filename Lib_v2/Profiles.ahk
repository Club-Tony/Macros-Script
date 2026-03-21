; Lib_v2/Profiles.ahk — Per-game compatibility profiles (AHK v2)
; Same profiles.ini format as v1 — cross-compatible.

class ProfileManager {
    name         := "Default"
    sendMode     := "Input"
    vJoyDeviceId := 1
    vJoyPovMode  := ""

    ; ──────────────────────────────────────────────────────────────────────────
    ; DETECT & APPLY
    ; ──────────────────────────────────────────────────────────────────────────
    Detect() {
        global sendMode, vJoyDeviceId
        iniPath := A_ScriptDir "\profiles.ini"
        this.EnsureDefaults(iniPath)

        ; Get foreground process
        fgProcess := ""
        try fgProcess := WinGetProcessName("A")

        ; Read sections and find first match
        sections := IniRead(iniPath)
        for sec in StrSplit(sections, "`n", "`r") {
            sec := Trim(sec)
            if (sec = "" || sec = "Default")
                continue
            procName := IniRead(iniPath, sec, "Process", "")
            if (procName != "" && fgProcess = procName) {
                this.Apply(sec, iniPath)
                return
            }
        }
        this.Apply("Default", iniPath)
    }

    Apply(profileName, iniPath := "") {
        global sendMode, vJoyDeviceId
        if (iniPath = "")
            iniPath := A_ScriptDir "\profiles.ini"
        sm    := IniRead(iniPath, profileName, "SendMode",     "Input")
        vjId  := IniRead(iniPath, profileName, "vJoyDeviceId", "1")
        vjPov := IniRead(iniPath, profileName, "vJoyPovMode",  "")
        this.name         := profileName
        this.sendMode     := sm
        this.vJoyDeviceId := Integer(vjId)
        this.vJoyPovMode  := vjPov
        sendMode := sm
        vJoyDeviceId := Integer(vjId)
        ; Apply sendMode in AHK v2
        SendMode sm
        ShowMacroToggledTip("Profile loaded: " profileName " (Send" sm ")", 2000, false)
    }

    EnsureDefaults(iniPath) {
        if !FileExist(iniPath) {
            FileAppend "[Default]`nSendMode=Input`nvJoyDeviceId=1`nvJoyPovMode=`n`n"
                     . "; Example game profile:`n"
                     . "; [RDR2]`n; Process=RDR2.exe`n; SendMode=Play`n; vJoyDeviceId=2`n", iniPath
        } else {
            sm := IniRead(iniPath, "Default", "SendMode", "")
            if (sm = "") {
                IniWrite "Input", iniPath, "Default", "SendMode"
                IniWrite "1",     iniPath, "Default", "vJoyDeviceId"
                IniWrite "",      iniPath, "Default", "vJoyPovMode"
            }
        }
    }

    ; ──────────────────────────────────────────────────────────────────────────
    ; MANAGEMENT
    ; ──────────────────────────────────────────────────────────────────────────
    ListNames() {
        iniPath := A_ScriptDir "\profiles.ini"
        names := []
        try {
            sections := IniRead(iniPath)
            for sec in StrSplit(sections, "`n", "`r") {
                sec := Trim(sec)
                if (sec != "" && sec != "Default")
                    names.Push(sec)
            }
        }
        return names
    }

    Add() {
        iniPath := A_ScriptDir "\profiles.ini"
        r := InputBox("Profile name (e.g. RDR2):", "New Profile", "w280 h100")
        if (r.Result = "Cancel" || Trim(r.Value) = "")
            return
        profileName := Trim(r.Value)
        r2 := InputBox("Process name (e.g. RDR2.exe):", "Game Process", "w280 h100", ".exe")
        if (r2.Result = "Cancel" || Trim(r2.Value) = "")
            return
        procName := Trim(r2.Value)
        IniWrite procName, iniPath, profileName, "Process"
        IniWrite "Play",   iniPath, profileName, "SendMode"
        IniWrite "1",      iniPath, profileName, "vJoyDeviceId"
        IniWrite "",       iniPath, profileName, "vJoyPovMode"
        ShowMacroToggledTip("Profile '" profileName "' added", 2000, false)
        TrayMenuRebuild()
    }
}
