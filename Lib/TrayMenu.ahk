; Lib/TrayMenu.ahk -- System tray icon + right-click menu
;
; Tray icon states:
;   idle      -- grey  M  (default, script running)
;   recording -- red   R  (actively recording)
;   playing   -- green P  (playing back)
;   paused    -- yellow   (playback paused)
;
; Right-click menu layout:
;   ● Slot: <name>           (status header)
;   ● Profile: <name>        (status header)
;   ─────────────────────────
;   Slots ▸                  (list + New Recording + Import/Export)
;   Sequences ▸              (list + Build Sequence)
;   Profiles ▸               (list + Add Profile)
;   ─────────────────────────
;   Playback Speed ▸         [0.5x][1x*][2x]
;   Loop Mode ▸              [Fixed][Infinite*][Until Key]
;   ─────────────────────────
;   Open Macro Menu          Ctrl+Shift+Alt+Z
;   Toggle Debug             Ctrl+Alt+D
;   Reload Script            Ctrl+Esc
;   ─────────────────────────
;   Exit
;
; State variables read (all declared global in Macros.ahk):
;   recorderActive, recorderPlaying, recorderPaused
;   activeProfileName, recorder (object with .slotName, .speed, .loopMode)
;   sequencePlaying, debugEnabled

; ============================================================
; INIT -- call once at startup
; ============================================================

TrayMenuInit()
{
    ; Remove the default AHK tray menu items
    Menu, Tray, NoStandard
    Menu, Tray, Tip, Macros-Script

    ; Set initial icon (idle)
    TrayIconSet("idle")

    ; Build the full menu
    TrayMenuRebuild()

    ; Left-click tray icon toggles GUI panel
    Menu, Tray, Click, 1
    OnMessage(0x404, "TrayClickHandler")
}

; Handle left-click on tray icon to toggle GUI
TrayClickHandler(wParam, lParam)
{
    if (lParam = 0x202)  ; WM_LBUTTONUP
    {
        MacroGuiToggle()
        return 0
    }
}

; ============================================================
; ICON STATE SWITCHER
; ============================================================

TrayIconSet(state)
{
    ; state: "idle" | "recording" | "playing" | "paused"
    iconDir := A_ScriptDir "\icons\"
    if (state = "recording")
        iconFile := iconDir "recording.ico"
    else if (state = "playing")
        iconFile := iconDir "playing.ico"
    else if (state = "paused")
        iconFile := iconDir "paused.ico"
    else
        iconFile := iconDir "idle.ico"

    if (FileExist(iconFile))
        Menu, Tray, Icon, %iconFile%
    else
        Menu, Tray, Icon   ; reset to default AHK icon if missing
}

; ============================================================
; MENU REBUILD -- call after any state change that affects menu
; ============================================================

TrayMenuRebuild()
{
    global recorder, activeProfile, activeProfileName, debugEnabled, sequencePlaying

    ; ── Destroy and recreate submenus to avoid duplicate items
    ; Submenus must be deleted before recreation in AHK v1
    TrayMenuDestroy("TraySlots")
    TrayMenuDestroy("TraySequences")
    TrayMenuDestroy("TrayProfiles")
    TrayMenuDestroy("TraySpeed")
    TrayMenuDestroy("TrayLoop")

    ; ── Build Slots submenu
    slotNames := SlotListNames()
    if (IsObject(slotNames) && slotNames.MaxIndex() > 0)
    {
        for _, name in slotNames
        {
            ; Capture name for label -- AHK v1 requires separate label per item
            ; Use dynamic hotkey label approach via bound function
            menuLabel := "TraySlotLoad_" name
            Menu, TraySlots, Add, %name%, TraySlotActivate
        }
        Menu, TraySlots, Add   ; separator
    }
    Menu, TraySlots, Add, New Recording (F5), TrayNewRecording
    Menu, TraySlots, Add, Export All Slots,   TrayExportSlots
    Menu, TraySlots, Add, Import Slots,       TrayImportSlots

    ; ── Build Sequences submenu
    seqNames := SequenceListNames()
    if (IsObject(seqNames) && seqNames.MaxIndex() > 0)
    {
        for _, name in seqNames
            Menu, TraySequences, Add, %name%, TraySequenceActivate
        Menu, TraySequences, Add   ; separator
    }
    Menu, TraySequences, Add, Build Sequence, TrayBuildSequence

    ; ── Build Profiles submenu
    Menu, TrayProfiles, Add, Default, TrayProfileActivate
    profileNames := ProfileListNames()
    if (IsObject(profileNames) && profileNames.MaxIndex() > 0)
        for _, name in profileNames
            Menu, TrayProfiles, Add, %name%, TrayProfileActivate
    Menu, TrayProfiles, Add   ; separator
    Menu, TrayProfiles, Add, Add Profile, TrayAddProfile

    ; Mark active profile with checkmark
    profName := IsObject(activeProfile) ? activeProfile.name : "Default"
    Menu, TrayProfiles, Check, %profName%

    ; ── Build Speed submenu
    Menu, TraySpeed, Add, 0.5x, TraySpeed05
    Menu, TraySpeed, Add, 1x,   TraySpeed1
    Menu, TraySpeed, Add, 2x,   TraySpeed2
    ; Mark current speed
    curSpeed := IsObject(recorder) ? recorder.speed : 1.0
    if (curSpeed = 0.5)
        Menu, TraySpeed, Check, 0.5x
    else if (curSpeed = 2.0)
        Menu, TraySpeed, Check, 2x
    else
    {
        Menu, TraySpeed, Check, 1x
    }

    ; ── Build Loop Mode submenu
    Menu, TrayLoop, Add, Fixed Count,  TrayLoopFixed
    Menu, TrayLoop, Add, Infinite,     TrayLoopInfinite
    Menu, TrayLoop, Add, Until Key,    TrayLoopUntilKey
    ; Mark current loop mode
    curLoop := IsObject(recorder) ? recorder.loopMode : "infinite"
    if (curLoop = "fixed")
        Menu, TrayLoop, Check, Fixed Count
    else if (curLoop = "untilkey")
        Menu, TrayLoop, Check, Until Key
    else
        Menu, TrayLoop, Check, Infinite

    ; ── Rebuild main Tray menu
    Menu, Tray, DeleteAll
    Menu, Tray, NoStandard

    ; Status headers
    slotDisplay := (IsObject(recorder) && recorder.slotName != "") ? recorder.slotName : "(none)"
    profileDisplay := IsObject(activeProfile) ? activeProfile.name : "Default"
    statusSlot    := "Slot: " slotDisplay
    statusProfile := "Profile: " profileDisplay " (Send" (IsObject(activeProfile) ? activeProfile.sendMode : "Input") ")"
    Menu, Tray, Add, %statusSlot%,    TrayNoOp
    Menu, Tray, Add, %statusProfile%, TrayNoOp
    Menu, Tray, Disable, %statusSlot%
    Menu, Tray, Disable, %statusProfile%

    Menu, Tray, Add   ; separator

    ; Submenus
    Menu, Tray, Add, Slots,          :TraySlots
    Menu, Tray, Add, Sequences,      :TraySequences
    Menu, Tray, Add, Profiles,       :TrayProfiles

    Menu, Tray, Add   ; separator

    Menu, Tray, Add, Playback Speed, :TraySpeed
    Menu, Tray, Add, Loop Mode,      :TrayLoop

    Menu, Tray, Add   ; separator

    Menu, Tray, Add, Open Macro Menu,  TrayOpenMenu
    dbgLabel := debugEnabled ? "Debug: ON  (Ctrl+Alt+D)" : "Debug: OFF (Ctrl+Alt+D)"
    Menu, Tray, Add, %dbgLabel%,       TrayToggleDebug
    Menu, Tray, Add, Reload Script,    TrayReload

    Menu, Tray, Add   ; separator

    Menu, Tray, Add, Exit, TrayExit

    ; Keep GUI in sync if visible
    global macroGuiVisible
    if (macroGuiVisible)
        MacroGuiRefresh()
}

; Safely destroy a submenu if it exists (ignore error if not).
TrayMenuDestroy(menuName)
{
    try
        Menu, %menuName%, DeleteAll
}

; ============================================================
; TRAY MENU ACTION HANDLERS
; ============================================================

TrayNoOp:
return

TrayNewRecording:
    StartRecorder()
return

TrayExportSlots:
    SlotExportAll()
return

TrayImportSlots:
    SlotImportAll()
    TrayMenuRebuild()
return

TraySlotActivate:
    ; A_ThisMenuItem contains the slot name that was clicked
    slotName := A_ThisMenuItem
    events := SlotLoad(slotName)
    if (IsObject(events) && events.MaxIndex() > 0)
    {
        global recorderEvents, recorder
        recorderEvents := events
        recorder.slotName := slotName
        ShowMacroToggledTip("Slot '" slotName "' loaded | F12 to play", 2000, false)
        TrayMenuRebuild()
    }
    else
        ShowMacroToggledTip("Slot '" slotName "' is empty", 2000, false)
return

TraySequenceActivate:
    seqName := A_ThisMenuItem
    SequenceStart(seqName)
return

TrayBuildSequence:
    steps := SequenceBuild()
    if (IsObject(steps) && steps.MaxIndex() > 0)
    {
        InputBox, seqName, Save Sequence, Name this sequence:, , 280, 100, , , , , sequence1
        if (!ErrorLevel && Trim(seqName) != "")
            SequenceSave(Trim(seqName), steps)
    }
return

TrayProfileActivate:
    profName := A_ThisMenuItem
    ProfileApply(profName)
    TrayMenuRebuild()
return

TrayAddProfile:
    ProfileAdd()
return

TraySpeed05:
    global recorder
    if (IsObject(recorder))
        recorder.speed := 0.5
    TrayMenuRebuild()
    ShowMacroToggledTip("Playback speed: 0.5x", 1500, false)
return

TraySpeed1:
    global recorder
    if (IsObject(recorder))
        recorder.speed := 1.0
    TrayMenuRebuild()
    ShowMacroToggledTip("Playback speed: 1x", 1500, false)
return

TraySpeed2:
    global recorder
    if (IsObject(recorder))
        recorder.speed := 2.0
    TrayMenuRebuild()
    ShowMacroToggledTip("Playback speed: 2x", 1500, false)
return

TrayLoopFixed:
    global recorder
    if (IsObject(recorder))
        recorder.loopMode := "fixed"
    TrayMenuRebuild()
    ShowMacroToggledTip("Loop mode: Fixed Count (F12 -> enter count)", 2000, false)
return

TrayLoopInfinite:
    global recorder
    if (IsObject(recorder))
        recorder.loopMode := "infinite"
    TrayMenuRebuild()
    ShowMacroToggledTip("Loop mode: Infinite (Esc or F12 to stop)", 2000, false)
return

TrayLoopUntilKey:
    global recorder
    if (!IsObject(recorder))
        return
    ; Prompt for stop key
    ShowMacroToggledTip("Press any key to set as loop stop trigger...", 3000, false)
    Input, stopKey, L1 T15
    if (stopKey = "" || ErrorLevel = "Timeout")
    {
        ShowMacroToggledTip("Loop key not set (timeout)", 1500, false)
        return
    }
    recorder.loopMode    := "untilkey"
    recorder.loopUntilKey := stopKey
    TrayMenuRebuild()
    ShowMacroToggledTip("Loop mode: Until '" stopKey "' pressed", 2000, false)
return

TrayOpenMenu:
    MacroGuiShow()
return

TrayToggleDebug:
    global debugEnabled
    debugEnabled := !debugEnabled
    TrayMenuRebuild()
    ShowMacroToggledTip("Debug mode " (debugEnabled ? "ON" : "OFF"), 2000, false)
return

TrayReload:
    Reload
return

TrayExit:
    ExitApp
return
