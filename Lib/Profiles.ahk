; Lib/Profiles.ahk -- Per-game compatibility profiles
; Stored in profiles.ini with one section per profile.
; Default profile always present; game profiles matched by foreground process name.
;
; profiles.ini format:
;   [Default]
;   SendMode=Input
;   vJoyDeviceId=1
;   vJoyPovMode=
;
;   [RDR2]
;   Process=RDR2.exe
;   SendMode=Play
;   vJoyDeviceId=2
;   vJoyPovMode=Continuous
;
; State variables (declared global in Macros.ahk):
;   activeProfile       -- object {name, sendMode, vJoyDeviceId, vJoyPovMode}
;   activeProfileName   -- thin string alias for menu display

; ============================================================
; PROFILE DETECTION
; ============================================================

; Detect the active game profile based on the foreground window's process name.
; Called on menu open and script startup.
; Applies sendMode, vJoyDeviceId, vJoyPovMode from the matching profile.
DetectActiveProfile()
{
    global activeProfile, activeProfileName, sendMode, debugEnabled
    global vJoyDeviceId
    iniPath := A_ScriptDir "\profiles.ini"

    ; Ensure Default profile exists
    ProfileEnsureDefaults(iniPath)

    ; Get foreground process name
    WinGet, fgProcess, ProcessName, A
    fgProcess := Trim(fgProcess)

    ; Read all profile sections
    IniRead, sections, %iniPath%
    if (sections = "ERROR" || sections = "")
    {
        ; No profiles.ini or empty -- use Default
        ProfileApplyDefault()
        return
    }

    ; First pass: try to match a game profile
    loop, parse, sections, `n, `r
    {
        section := Trim(A_LoopField)
        if (section = "" || section = "Default")
            continue
        IniRead, procName, %iniPath%, %section%, Process, ""
        if (procName = "")
            continue
        if (fgProcess = procName || fgProcess = "" && false)  ; exact match only
        {
            ProfileApply(section, iniPath)
            if (debugEnabled)
                ShowMacroToggledTip("DEBUG: Profile matched '" section "' for " fgProcess, 2000, false)
            return
        }
    }

    ; No match -- apply Default
    ProfileApply("Default", iniPath)
    if (fgProcess != "" && debugEnabled)
        ShowMacroToggledTip("No game profile matched -- using Default", 2000, false)
}

; Apply a specific profile by name, reading from profiles.ini.
ProfileApply(profileName, iniPath := "")
{
    global activeProfile, activeProfileName, sendMode, vJoyDeviceId, debugEnabled
    if (iniPath = "")
        iniPath := A_ScriptDir "\profiles.ini"

    IniRead, sm,    %iniPath%, %profileName%, SendMode,     Input
    IniRead, vjId,  %iniPath%, %profileName%, vJoyDeviceId, 1
    IniRead, vjPov, %iniPath%, %profileName%, vJoyPovMode,  ""

    activeProfile := {}
    activeProfile.name        := profileName
    activeProfile.sendMode    := sm
    activeProfile.vJoyDeviceId := vjId + 0
    activeProfile.vJoyPovMode  := vjPov
    activeProfileName := profileName

    ; Apply sendMode globally
    sendMode := sm
    ApplySendMode()

    ; Apply vJoyDeviceId if vJoy is loaded
    vJoyDeviceId := vjId + 0

    ShowMacroToggledTip("Profile loaded: " profileName " (Send" sm ")", 2000, false)
}

; Apply default settings without reading .ini (fallback).
ProfileApplyDefault()
{
    global activeProfile, activeProfileName, sendMode, vJoyDeviceId
    activeProfile := {}
    activeProfile.name         := "Default"
    activeProfile.sendMode     := "Input"
    activeProfile.vJoyDeviceId := 1
    activeProfile.vJoyPovMode  := ""
    activeProfileName := "Default"
    sendMode := "Input"
    ApplySendMode()
    vJoyDeviceId := 1
}

; Ensure profiles.ini exists with a Default section.
ProfileEnsureDefaults(iniPath)
{
    if (!FileExist(iniPath))
    {
        ; Create with Default section
        FileAppend,
(
[Default]
SendMode=Input
vJoyDeviceId=1
vJoyPovMode=

; Add game profiles below. Example:
; [RDR2]
; Process=RDR2.exe
; SendMode=Play
; vJoyDeviceId=2
; vJoyPovMode=Continuous
), %iniPath%
    }
    else
    {
        ; Check Default section exists
        IniRead, sm, %iniPath%, Default, SendMode, ""
        if (sm = "")
        {
            IniWrite, Input, %iniPath%, Default, SendMode
            IniWrite, 1,     %iniPath%, Default, vJoyDeviceId
            IniWrite, %A_Space%, %iniPath%, Default, vJoyPovMode
        }
    }
}

; ============================================================
; PROFILE MANAGEMENT (add/list from tray menu)
; ============================================================

; List all profile names from profiles.ini (excluding Default).
ProfileListNames()
{
    iniPath := A_ScriptDir "\profiles.ini"
    IniRead, sections, %iniPath%
    names := []
    if (sections = "ERROR" || sections = "")
        return names
    loop, parse, sections, `n, `r
    {
        section := Trim(A_LoopField)
        if (section = "" || section = "Default")
            continue
        names.Push(section)
    }
    return names
}

; Interactive prompt to add a new game profile.
ProfileAdd()
{
    iniPath := A_ScriptDir "\profiles.ini"
    InputBox, profileName, New Profile, Profile name (e.g. RDR2):, , 280, 100
    if (ErrorLevel || Trim(profileName) = "")
        return
    profileName := Trim(profileName)

    InputBox, procName, Game Process, Process name (e.g. RDR2.exe):, , 280, 100, , , , , .exe
    if (ErrorLevel || Trim(procName) = "")
        return
    procName := Trim(procName)

    ; Default SendMode to Play for new game profiles (most common need)
    IniWrite, %procName%, %iniPath%, %profileName%, Process
    IniWrite, Play,       %iniPath%, %profileName%, SendMode
    IniWrite, 1,          %iniPath%, %profileName%, vJoyDeviceId
    IniWrite, %A_Space%, %iniPath%, %profileName%, vJoyPovMode

    ShowMacroToggledTip("Profile '" profileName "' added", 2000, false)
    TrayMenuRebuild()
}
