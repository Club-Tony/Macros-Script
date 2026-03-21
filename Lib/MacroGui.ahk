; Lib/MacroGui.ahk -- 4-tab GUI panel for Macros-Script
;
; Tabs: Main (dashboard) | Slots | Sequences | Settings
;
; Uses named GUI "MacroGui:" to avoid conflicts with other Gui commands.
; All g-labels are bare subroutines at file scope (same pattern as TrayMenu.ahk).
;
; Called from Macros.ahk auto-execute:
;   MacroGuiCreate()   -- build once at startup (hidden)
;   SetTimer, MacroGuiStatusTick, 250
;
; Public API:
;   MacroGuiShow()     -- show the panel
;   MacroGuiHide()     -- hide the panel
;   MacroGuiToggle()   -- toggle visibility
;   MacroGuiRefresh()  -- full data refresh (call after state changes)

; ============================================================
; GLOBALS (declared in Macros.ahk, referenced here)
; ============================================================
; macroGuiVisible, macroGuiCreated
; recorder, recorderActive, recorderPlaying, recorderPaused, recorderEvents
; activeProfile, activeProfileName, debugEnabled, sequencePlaying
; vJoyReady, controllerXInputReady

; ============================================================
; CREATE -- build all controls once
; ============================================================

MacroGuiCreate()
{
    global  ; make all variables global (required for GUI control v-variables in AHK v1)

    if (macroGuiCreated)
        return

    ; Load saved position
    MacroGuiLoadPosition(guiX, guiY)

    ; -- Window shell
    Gui, MacroGui:New, +HwndMacroGuiHwnd +Resize -MaximizeBox, Macros-Script
    Gui, MacroGui:Default
    Gui, MacroGui:Margin, 8, 6

    ; -- Tab control
    Gui, Add, Tab3, vMacroGuiTab gGuiTabChanged w364 h380, Main|Slots|Sequences|Settings

    ; ================================================================
    ; TAB 1: MAIN (Dashboard)
    ; ================================================================
    Gui, Tab, 1

    ; Status line
    Gui, Add, Text, vGuiStatusText w340 h20, Status: Idle

    ; Action buttons row 1
    Gui, Add, Button, vGuiBtnRecord gGuiRecord w110 h28, Record (F5)
    Gui, Add, Button, vGuiBtnPlay gGuiPlay x+6 yp w110 h28, Play (F12)
    Gui, Add, Button, vGuiBtnStop gGuiStop x+6 yp w110 h28, Stop

    ; Action buttons row 2
    Gui, Add, Button, vGuiBtnPause gGuiPause xm+16 w110 h28, Pause

    ; Separator
    Gui, Add, Text, xm+16 w340 h1 +0x10  ; SS_ETCHEDHORZ

    ; Current Slot dropdown + Load
    Gui, Add, Text, xm+16, Current Slot:
    Gui, Add, DropDownList, vGuiSlotDDL gGuiSlotDDLChange x+6 yp-3 w180
    Gui, Add, Button, vGuiBtnLoadSlot gGuiLoadSlot x+6 yp w60 h22, Load

    ; Event count display
    Gui, Add, Text, xm+16 vGuiEventCount w200, Events: 0

    ; Separator
    Gui, Add, Text, xm+16 w340 h1 +0x10

    ; Speed radios
    Gui, Add, Text, xm+16, Speed:
    Gui, Add, Radio, vGuiSpeed05 gGuiSpeedChange x+6 yp, 0.5x
    Gui, Add, Radio, vGuiSpeed1 gGuiSpeedChange x+6 yp Checked, 1x
    Gui, Add, Radio, vGuiSpeed2 gGuiSpeedChange x+6 yp, 2x

    ; Loop mode radios
    Gui, Add, Text, xm+16, Loop:
    Gui, Add, Radio, vGuiLoopFixed gGuiLoopChange x+6 yp, Fixed
    Gui, Add, Radio, vGuiLoopInfinite gGuiLoopChange x+6 yp Checked, Infinite
    Gui, Add, Radio, vGuiLoopUntilKey gGuiLoopChange x+6 yp, Until Key

    ; Fixed count field (shown when Fixed selected)
    Gui, Add, Text, xm+16 vGuiFixedLabel, Fixed Count:
    Gui, Add, Edit, vGuiFixedCount x+6 yp-3 w50 Number, 5

    ; Until Key field (shown when Until Key selected)
    Gui, Add, Text, xm+16 vGuiUntilKeyLabel, Until Key:
    Gui, Add, Edit, vGuiUntilKeyEdit x+6 yp-3 w50,

    ; Hide conditional fields initially
    GuiControl, Hide, GuiFixedLabel
    GuiControl, Hide, GuiFixedCount
    GuiControl, Hide, GuiUntilKeyLabel
    GuiControl, Hide, GuiUntilKeyEdit

    ; Separator
    Gui, Add, Text, xm+16 w340 h1 +0x10

    ; Profile dropdown
    Gui, Add, Text, xm+16, Profile:
    Gui, Add, DropDownList, vGuiProfileDDL gGuiProfileChange x+6 yp-3 w180

    ; SendMode display
    Gui, Add, Text, xm+16 vGuiSendModeText w200, SendMode: Input

    ; ================================================================
    ; TAB 2: SLOTS
    ; ================================================================
    Gui, Tab, 2

    ; Slots ListView
    Gui, Add, ListView, vGuiSlotList gGuiSlotListAction w340 h200 +Grid, Name|Events|Date

    ; Slot action buttons
    Gui, Add, Button, vGuiBtnSlotLoad gGuiSlotListLoad w80 h26, Load
    Gui, Add, Button, vGuiBtnSlotDelete gGuiSlotListDelete x+4 yp w80 h26, Delete
    Gui, Add, Button, vGuiBtnSlotRename gGuiSlotListRename x+4 yp w80 h26, Rename

    ; Import/Export buttons
    Gui, Add, Button, vGuiBtnExport gGuiExportSlots xm+16 w100 h26, Export All
    Gui, Add, Button, vGuiBtnImport gGuiImportSlots x+4 yp w100 h26, Import
    Gui, Add, Button, vGuiBtnNewRec gGuiNewRecording x+4 yp w100 h26, New Recording

    ; ================================================================
    ; TAB 3: SEQUENCES
    ; ================================================================
    Gui, Tab, 3

    ; Sequences ListView
    Gui, Add, ListView, vGuiSeqList gGuiSeqListAction w340 h140 +Grid, Name|Steps

    ; Sequence action buttons
    Gui, Add, Button, vGuiBtnSeqPlay gGuiSeqPlay w100 h26, Play
    Gui, Add, Button, vGuiBtnSeqDelete gGuiSeqDelete x+4 yp w100 h26, Delete
    Gui, Add, Button, vGuiBtnSeqBuild gGuiSeqBuild x+4 yp w100 h26, Build New

    ; Steps preview (read-only)
    Gui, Add, Text, xm+16 w340, Steps Preview:
    Gui, Add, ListView, vGuiSeqSteps w340 h100 +Grid +ReadOnly, #|Slot|Delay (ms)

    ; ================================================================
    ; TAB 4: SETTINGS
    ; ================================================================
    Gui, Tab, 4

    ; Profile management
    Gui, Add, GroupBox, xm+16 w340 h90, Profile Management
    Gui, Add, Text, xp+10 yp+20, Active Profile:
    Gui, Add, DropDownList, vGuiSettingsProfileDDL gGuiSettingsProfileChange x+6 yp-3 w140
    Gui, Add, Button, vGuiBtnAddProfile gGuiAddProfile x+4 yp w50 h22, Add
    Gui, Add, Button, vGuiBtnDetectProfile gGuiDetectProfile x+4 yp w50 h22, Detect

    ; Debug checkbox
    Gui, Add, CheckBox, xm+26 vGuiDebugCheck gGuiDebugToggle, Debug Mode (Ctrl+Alt+D)

    ; Controller/vJoy status
    Gui, Add, Text, xm+26 vGuiXInputStatus w300, XInput: checking...
    Gui, Add, Text, xm+26 vGuiVJoyStatus w300, vJoy: checking...

    ; Separator
    Gui, Add, Text, xm+16 w340 h1 +0x10

    ; Hotkey reference
    Gui, Add, Text, xm+26 w320
        , % "Hotkeys:`n"
        . "Ctrl+Shift+Alt+Z  Open this panel`n"
        . "F1  Slash Macro    F2  Autoclicker`n"
        . "F3  Turbo Hold     F4  Pure Hold`n"
        . "F5  Record         F12  Play`n"
        . "Ctrl+Alt+P  Cycle SendMode`n"
        . "Ctrl+Alt+D  Toggle Debug`n"
        . "Ctrl+Esc  Reload Script`n"
        . "Esc  Cancel / Stop"

    ; Separator
    Gui, Add, Text, xm+16 w340 h1 +0x10

    ; Reload / Exit
    Gui, Add, Button, vGuiBtnReload gGuiReload xm+26 w100 h28, Reload Script
    Gui, Add, Button, vGuiBtnExit gGuiExit x+10 yp w100 h28, Exit

    ; ================================================================
    ; END TABS -- StatusBar
    ; ================================================================
    Gui, Tab  ; end tab scope

    Gui, Add, StatusBar
    SB_SetParts(120)
    SB_SetText("Idle", 1)
    SB_SetText("Profile: Default (SendInput)", 2)

    ; Mark as created but don't show yet
    macroGuiCreated := true
    macroGuiVisible := false

    ; Populate data
    MacroGuiRefresh()
}

; ============================================================
; SHOW / HIDE / TOGGLE
; ============================================================

MacroGuiShow()
{
    global macroGuiCreated, macroGuiVisible
    if (!macroGuiCreated)
        MacroGuiCreate()
    MacroGuiRefresh()
    ; Load saved position
    MacroGuiLoadPosition(guiX, guiY)
    if (guiX != "" && guiY != "")
        Gui, MacroGui:Show, x%guiX% y%guiY% NoActivate
    else
        Gui, MacroGui:Show, NoActivate
    macroGuiVisible := true
}

MacroGuiHide()
{
    global macroGuiVisible
    MacroGuiSavePosition()
    Gui, MacroGui:Hide
    macroGuiVisible := false
}

MacroGuiToggle()
{
    global macroGuiVisible
    if (macroGuiVisible)
        MacroGuiHide()
    else
        MacroGuiShow()
}

; ============================================================
; FULL REFRESH -- repopulate all dynamic data
; ============================================================

MacroGuiRefresh()
{
    global macroGuiCreated
    if (!macroGuiCreated)
        return

    Gui, MacroGui:Default

    MacroGuiRefreshMainTab()
    MacroGuiRefreshSlotList()
    MacroGuiRefreshSequenceList()
    MacroGuiRefreshSettingsTab()
}

; ── Main Tab refresh ──────────────────────────────────────────

MacroGuiRefreshMainTab()
{
    global recorder, recorderEvents, activeProfile, activeProfileName, sendMode

    Gui, MacroGui:Default

    ; Slot DDL
    slotNames := SlotListNames()
    ddlStr := ""
    selIndex := 0
    for i, name in slotNames
    {
        if (i > 1)
            ddlStr .= "|"
        ddlStr .= name
        if (IsObject(recorder) && recorder.slotName = name)
            selIndex := i
    }
    GuiControl,, GuiSlotDDL, % "|" ddlStr  ; leading pipe clears list first
    if (selIndex > 0)
        GuiControl, Choose, GuiSlotDDL, %selIndex%

    ; Event count
    evtCount := IsObject(recorderEvents) ? recorderEvents.MaxIndex() : 0
    if (evtCount = "")
        evtCount := 0
    GuiControl,, GuiEventCount, Events: %evtCount%

    ; Speed radios
    curSpeed := IsObject(recorder) ? recorder.speed : 1.0
    if (curSpeed = 0.5)
    {
        GuiControl,, GuiSpeed05, 1
    }
    else if (curSpeed = 2.0)
    {
        GuiControl,, GuiSpeed2, 1
    }
    else
    {
        GuiControl,, GuiSpeed1, 1
    }

    ; Loop mode radios
    curLoop := IsObject(recorder) ? recorder.loopMode : "infinite"
    if (curLoop = "fixed")
    {
        GuiControl,, GuiLoopFixed, 1
        GuiControl, Show, GuiFixedLabel
        GuiControl, Show, GuiFixedCount
        GuiControl, Hide, GuiUntilKeyLabel
        GuiControl, Hide, GuiUntilKeyEdit
    }
    else if (curLoop = "untilkey")
    {
        GuiControl,, GuiLoopUntilKey, 1
        GuiControl, Hide, GuiFixedLabel
        GuiControl, Hide, GuiFixedCount
        GuiControl, Show, GuiUntilKeyLabel
        GuiControl, Show, GuiUntilKeyEdit
        ; Populate until key value
        ukVal := IsObject(recorder) ? recorder.loopUntilKey : ""
        GuiControl,, GuiUntilKeyEdit, %ukVal%
    }
    else
    {
        GuiControl,, GuiLoopInfinite, 1
        GuiControl, Hide, GuiFixedLabel
        GuiControl, Hide, GuiFixedCount
        GuiControl, Hide, GuiUntilKeyLabel
        GuiControl, Hide, GuiUntilKeyEdit
    }

    ; Profile DDL
    profNames := ProfileListNames()
    profDDL := "Default"
    profSel := 1
    curProf := IsObject(activeProfile) ? activeProfile.name : "Default"
    if (curProf = "Default")
        profSel := 1
    for i, name in profNames
    {
        profDDL .= "|" name
        if (name = curProf)
            profSel := i + 1
    }
    GuiControl,, GuiProfileDDL, % "|" profDDL
    GuiControl, Choose, GuiProfileDDL, %profSel%

    ; SendMode text
    sm := IsObject(activeProfile) ? activeProfile.sendMode : "Input"
    GuiControl,, GuiSendModeText, SendMode: %sm%
}

; ── Slots Tab refresh ──────────────────────────────────────────

MacroGuiRefreshSlotList()
{
    global macroGuiCreated
    if (!macroGuiCreated)
        return

    Gui, MacroGui:Default
    Gui, MacroGui:ListView, GuiSlotList

    LV_Delete()  ; clear all rows

    slotNames := SlotListNames()
    iniPath := A_ScriptDir "\macros.ini"
    for _, name in slotNames
    {
        IniRead, evtCount, %iniPath%, %name%, event_count, 0
        IniRead, recorded, %iniPath%, %name%, recorded, --
        LV_Add("", name, evtCount, recorded)
    }

    LV_ModifyCol(1, 160)  ; Name
    LV_ModifyCol(2, 60)   ; Events
    LV_ModifyCol(3, 100)  ; Date
}

; ── Sequences Tab refresh ──────────────────────────────────────

MacroGuiRefreshSequenceList()
{
    global macroGuiCreated
    if (!macroGuiCreated)
        return

    Gui, MacroGui:Default
    Gui, MacroGui:ListView, GuiSeqList

    LV_Delete()

    seqNames := SequenceListNames()
    iniPath := A_ScriptDir "\macros.ini"
    for _, name in seqNames
    {
        IniRead, stepCount, %iniPath%, seq_%name%, step_count, 0
        LV_Add("", name, stepCount)
    }

    LV_ModifyCol(1, 200)  ; Name
    LV_ModifyCol(2, 60)   ; Steps

    ; Clear steps preview
    Gui, MacroGui:ListView, GuiSeqSteps
    LV_Delete()
}

; ── Settings Tab refresh ──────────────────────────────────────

MacroGuiRefreshSettingsTab()
{
    global debugEnabled, controllerXInputReady, vJoyReady, activeProfile

    Gui, MacroGui:Default

    ; Debug checkbox
    GuiControl,, GuiDebugCheck, % debugEnabled ? 1 : 0

    ; XInput status
    xinStat := controllerXInputReady ? "XInput: Available" : "XInput: Not available"
    GuiControl,, GuiXInputStatus, %xinStat%

    ; vJoy status
    vjStat := vJoyReady ? "vJoy: Ready" : "vJoy: Not installed"
    GuiControl,, GuiVJoyStatus, %vjStat%

    ; Settings profile DDL (same as main tab)
    profNames := ProfileListNames()
    profDDL := "Default"
    profSel := 1
    curProf := IsObject(activeProfile) ? activeProfile.name : "Default"
    if (curProf = "Default")
        profSel := 1
    for i, name in profNames
    {
        profDDL .= "|" name
        if (name = curProf)
            profSel := i + 1
    }
    GuiControl,, GuiSettingsProfileDDL, % "|" profDDL
    GuiControl, Choose, GuiSettingsProfileDDL, %profSel%
}

; ============================================================
; STATUS TIMER (250ms) -- updates status text and button states
; ============================================================

MacroGuiUpdateStatus()
{
    global macroGuiVisible, macroGuiCreated
    global recorderActive, recorderPlaying, recorderPaused, recorderEvents
    global recorderLoopCurrent, recorderLoopTarget, sequencePlaying
    global activeProfile

    if (!macroGuiVisible || !macroGuiCreated)
        return

    Gui, MacroGui:Default

    ; Determine status text
    if (recorderActive)
    {
        evtCount := IsObject(recorderEvents) ? recorderEvents.MaxIndex() : 0
        if (evtCount = "")
            evtCount := 0
        statusText := "Status: Recording... (" evtCount " events)"
    }
    else if (recorderPlaying && recorderPaused)
    {
        statusText := "Status: Paused"
    }
    else if (recorderPlaying)
    {
        if (recorderLoopTarget > 0)
            statusText := "Status: Playing (loop " recorderLoopCurrent "/" recorderLoopTarget ")"
        else
            statusText := "Status: Playing..."
    }
    else if (sequencePlaying)
    {
        statusText := "Status: Sequence playing..."
    }
    else
    {
        statusText := "Status: Idle"
    }
    GuiControl,, GuiStatusText, %statusText%

    ; Update event count on main tab
    evtCount := IsObject(recorderEvents) ? recorderEvents.MaxIndex() : 0
    if (evtCount = "")
        evtCount := 0
    GuiControl,, GuiEventCount, Events: %evtCount%

    ; Button enable/disable
    if (recorderActive)
    {
        ; Recording: only Stop enabled
        GuiControl, Disable, GuiBtnRecord
        GuiControl, Disable, GuiBtnPlay
        GuiControl, Enable, GuiBtnStop
        GuiControl, Disable, GuiBtnPause
    }
    else if (recorderPlaying)
    {
        ; Playing: Stop + Pause enabled
        GuiControl, Disable, GuiBtnRecord
        GuiControl, Disable, GuiBtnPlay
        GuiControl, Enable, GuiBtnStop
        GuiControl, Enable, GuiBtnPause
    }
    else
    {
        ; Idle: Record + Play enabled, Stop/Pause disabled
        GuiControl, Enable, GuiBtnRecord
        hasEvents := (IsObject(recorderEvents) && recorderEvents.MaxIndex() > 0)
        if (hasEvents)
            GuiControl, Enable, GuiBtnPlay
        else
            GuiControl, Disable, GuiBtnPlay
        GuiControl, Disable, GuiBtnStop
        GuiControl, Disable, GuiBtnPause
    }

    ; StatusBar
    sm := IsObject(activeProfile) ? activeProfile.sendMode : "Input"
    profName := IsObject(activeProfile) ? activeProfile.name : "Default"
    sbStatus := recorderActive ? "Recording" : (recorderPlaying ? (recorderPaused ? "Paused" : "Playing") : "Idle")
    SB_SetText(sbStatus, 1)
    SB_SetText("Profile: " profName " (Send" sm ")", 2)
}

; ============================================================
; POSITION PERSISTENCE
; ============================================================

MacroGuiSavePosition()
{
    global macroGuiCreated
    if (!macroGuiCreated)
        return
    ; Get window position
    Gui, MacroGui:+LastFound
    WinGetPos, gx, gy
    if (gx = "" || gy = "")
        return
    iniPath := A_ScriptDir "\macros.ini"
    IniWrite, %gx%, %iniPath%, GuiState, x
    IniWrite, %gy%, %iniPath%, GuiState, y
}

MacroGuiLoadPosition(ByRef outX, ByRef outY)
{
    iniPath := A_ScriptDir "\macros.ini"
    IniRead, outX, %iniPath%, GuiState, x, ERROR
    IniRead, outY, %iniPath%, GuiState, y, ERROR
    if (outX = "ERROR")
        outX := ""
    if (outY = "ERROR")
        outY := ""
}

; ============================================================
; G-LABEL HANDLERS (bare subroutines)
; ============================================================

; ── Window events ──────────────────────────────────────────

MacroGuiClose:
MacroGuiEscape:
    MacroGuiHide()
return

; ── Tab changed ──────────────────────────────────────────

GuiTabChanged:
    ; Refresh data when switching tabs
    Gui, MacroGui:Submit, NoHide
    MacroGuiRefresh()
return

; ── Main Tab: Record / Play / Pause / Stop ──────────────

GuiRecord:
    MacroGuiHide()
    StartRecorder()
return

GuiPlay:
    global recorder, recorderEvents
    Gui, MacroGui:Submit, NoHide
    if (!IsObject(recorderEvents) || recorderEvents.MaxIndex() = "" || recorderEvents.MaxIndex() = 0)
    {
        ShowMacroToggledTip("No events loaded -- record or load a slot first", 2000, false)
        return
    }

    ; Read speed from radios
    GuiControlGet, s05,, GuiSpeed05
    GuiControlGet, s2,, GuiSpeed2
    if (s05)
        recorder.speed := 0.5
    else if (s2)
        recorder.speed := 2.0
    else
        recorder.speed := 1.0

    ; Read loop mode from radios
    GuiControlGet, lFixed,, GuiLoopFixed
    GuiControlGet, lUntil,, GuiLoopUntilKey
    if (lFixed)
    {
        recorder.loopMode := "fixed"
        GuiControlGet, fixedVal,, GuiFixedCount
        fixedVal := fixedVal + 0
        if (fixedVal < 1)
            fixedVal := 1
        StartPlayback(fixedVal)
    }
    else if (lUntil)
    {
        recorder.loopMode := "untilkey"
        GuiControlGet, ukVal,, GuiUntilKeyEdit
        recorder.loopUntilKey := Trim(ukVal)
        StartPlaybackUntilKey()
    }
    else
    {
        recorder.loopMode := "infinite"
        StartPlayback(-1)
    }
    TrayMenuRebuild()
return

GuiPause:
    TogglePlaybackPause()
return

GuiStop:
    global recorderActive, recorderPlaying, sequencePlaying
    if (recorderActive)
        StopRecorder()
    else if (recorderPlaying)
        StopPlayback()
    else if (sequencePlaying)
        SequenceStop()
return

; ── Main Tab: Slot DDL / Load ──────────────────────────

GuiSlotDDLChange:
    ; No action needed on selection change -- Load button applies it
return

GuiLoadSlot:
    global recorderEvents, recorder
    Gui, MacroGui:Submit, NoHide
    GuiControlGet, selectedSlot,, GuiSlotDDL
    if (selectedSlot = "")
        return
    events := SlotLoad(selectedSlot)
    if (IsObject(events) && events.MaxIndex() > 0)
    {
        recorderEvents := events
        recorder.slotName := selectedSlot
        ShowMacroToggledTip("Slot '" selectedSlot "' loaded | F12 to play", 2000, false)
        MacroGuiRefresh()
        TrayMenuRebuild()
    }
    else
    {
        ShowMacroToggledTip("Slot '" selectedSlot "' is empty", 2000, false)
    }
return

; ── Main Tab: Speed / Loop radios ──────────────────────

GuiSpeedChange:
    global recorder
    Gui, MacroGui:Submit, NoHide
    GuiControlGet, s05,, GuiSpeed05
    GuiControlGet, s2,, GuiSpeed2
    if (s05)
        recorder.speed := 0.5
    else if (s2)
        recorder.speed := 2.0
    else
        recorder.speed := 1.0
    TrayMenuRebuild()
return

GuiLoopChange:
    global recorder
    Gui, MacroGui:Submit, NoHide
    GuiControlGet, lFixed,, GuiLoopFixed
    GuiControlGet, lUntil,, GuiLoopUntilKey
    if (lFixed)
    {
        recorder.loopMode := "fixed"
        GuiControl, Show, GuiFixedLabel
        GuiControl, Show, GuiFixedCount
        GuiControl, Hide, GuiUntilKeyLabel
        GuiControl, Hide, GuiUntilKeyEdit
    }
    else if (lUntil)
    {
        recorder.loopMode := "untilkey"
        GuiControl, Hide, GuiFixedLabel
        GuiControl, Hide, GuiFixedCount
        GuiControl, Show, GuiUntilKeyLabel
        GuiControl, Show, GuiUntilKeyEdit
    }
    else
    {
        recorder.loopMode := "infinite"
        GuiControl, Hide, GuiFixedLabel
        GuiControl, Hide, GuiFixedCount
        GuiControl, Hide, GuiUntilKeyLabel
        GuiControl, Hide, GuiUntilKeyEdit
    }
    TrayMenuRebuild()
return

; ── Main Tab: Profile change ──────────────────────────

GuiProfileChange:
    Gui, MacroGui:Submit, NoHide
    GuiControlGet, selProf,, GuiProfileDDL
    if (selProf != "")
    {
        ProfileApply(selProf)
        MacroGuiRefresh()
        TrayMenuRebuild()
    }
return

; ── Slots Tab: ListView actions ──────────────────────

GuiSlotListAction:
    ; Double-click to load
    if (A_GuiEvent = "DoubleClick")
    {
        Gui, MacroGui:Default
        Gui, MacroGui:ListView, GuiSlotList
        selRow := LV_GetNext(0, "Focused")
        if (selRow > 0)
        {
            LV_GetText(slotName, selRow, 1)
            GoSub, GuiSlotListLoadByName
        }
    }
return

GuiSlotListLoad:
    Gui, MacroGui:Default
    Gui, MacroGui:ListView, GuiSlotList
    selRow := LV_GetNext(0, "Focused")
    if (selRow = 0)
    {
        ShowMacroToggledTip("Select a slot first", 1500, false)
        return
    }
    LV_GetText(slotName, selRow, 1)
    GoSub, GuiSlotListLoadByName
return

GuiSlotListLoadByName:
    global recorderEvents, recorder
    events := SlotLoad(slotName)
    if (IsObject(events) && events.MaxIndex() > 0)
    {
        recorderEvents := events
        recorder.slotName := slotName
        ShowMacroToggledTip("Slot '" slotName "' loaded | F12 to play", 2000, false)
        MacroGuiRefresh()
        TrayMenuRebuild()
    }
    else
    {
        ShowMacroToggledTip("Slot '" slotName "' is empty", 2000, false)
    }
return

GuiSlotListDelete:
    Gui, MacroGui:Default
    Gui, MacroGui:ListView, GuiSlotList
    selRow := LV_GetNext(0, "Focused")
    if (selRow = 0)
    {
        ShowMacroToggledTip("Select a slot first", 1500, false)
        return
    }
    LV_GetText(slotName, selRow, 1)
    MsgBox, 4, Delete Slot, Delete slot '%slotName%'? This cannot be undone.
    IfMsgBox, Yes
    {
        SlotDelete(slotName)
        MacroGuiRefreshSlotList()
        MacroGuiRefreshMainTab()
        ShowMacroToggledTip("Slot '" slotName "' deleted", 2000, false)
    }
return

GuiSlotListRename:
    Gui, MacroGui:Default
    Gui, MacroGui:ListView, GuiSlotList
    selRow := LV_GetNext(0, "Focused")
    if (selRow = 0)
    {
        ShowMacroToggledTip("Select a slot first", 1500, false)
        return
    }
    LV_GetText(oldName, selRow, 1)
    InputBox, newName, Rename Slot, New name for '%oldName%':, , 280, 100, , , , , %oldName%
    if (ErrorLevel || Trim(newName) = "" || Trim(newName) = oldName)
        return
    newName := Trim(newName)
    newName := RegExReplace(newName, "[\\/:*?""<>|]", "_")

    ; Load events, save under new name, delete old
    events := SlotLoad(oldName)
    if (!IsObject(events) || events.MaxIndex() = "" || events.MaxIndex() = 0)
    {
        ShowMacroToggledTip("Cannot rename -- slot '" oldName "' has no events", 2000, false)
        return
    }
    ; Read coord mode from ini
    iniPath := A_ScriptDir "\macros.ini"
    IniRead, coordMode, %iniPath%, %oldName%, coord_mode, screen
    SlotSave(newName, events, coordMode)
    SlotDelete(oldName)
    MacroGuiRefreshSlotList()
    MacroGuiRefreshMainTab()
    ShowMacroToggledTip("Renamed '" oldName "' -> '" newName "'", 2000, false)
return

GuiExportSlots:
    SlotExportAll()
return

GuiImportSlots:
    SlotImportAll()
    MacroGuiRefreshSlotList()
    MacroGuiRefreshMainTab()
return

GuiNewRecording:
    MacroGuiHide()
    StartRecorder()
return

; ── Sequences Tab: ListView actions ──────────────────

GuiSeqListAction:
    if (A_GuiEvent = "Normal" || A_GuiEvent = "DoubleClick")
    {
        ; Show steps preview for selected sequence
        Gui, MacroGui:Default
        Gui, MacroGui:ListView, GuiSeqList
        selRow := LV_GetNext(0, "Focused")
        if (selRow > 0)
        {
            LV_GetText(seqName, selRow, 1)
            ; Load and display steps
            steps := SequenceLoad(seqName)
            Gui, MacroGui:ListView, GuiSeqSteps
            LV_Delete()
            if (IsObject(steps))
            {
                for i, step in steps
                    LV_Add("", i, step.slotName, step.delayAfter)
            }
            LV_ModifyCol(1, 30)
            LV_ModifyCol(2, 200)
            LV_ModifyCol(3, 80)
        }
    }
return

GuiSeqPlay:
    Gui, MacroGui:Default
    Gui, MacroGui:ListView, GuiSeqList
    selRow := LV_GetNext(0, "Focused")
    if (selRow = 0)
    {
        ShowMacroToggledTip("Select a sequence first", 1500, false)
        return
    }
    LV_GetText(seqName, selRow, 1)
    SequenceStart(seqName)
return

GuiSeqDelete:
    Gui, MacroGui:Default
    Gui, MacroGui:ListView, GuiSeqList
    selRow := LV_GetNext(0, "Focused")
    if (selRow = 0)
    {
        ShowMacroToggledTip("Select a sequence first", 1500, false)
        return
    }
    LV_GetText(seqName, selRow, 1)
    MsgBox, 4, Delete Sequence, Delete sequence '%seqName%'?
    IfMsgBox, Yes
    {
        ; Remove from ini
        iniPath := A_ScriptDir "\macros.ini"
        IniDelete, %iniPath%, seq_%seqName%
        ; Rebuild sequence index
        IniRead, count, %iniPath%, Sequences, count, 0
        newIdx := 0
        loop % count
        {
            IniRead, nm, %iniPath%, Sequences, seq_%A_Index%, ""
            if (nm != "" && nm != seqName)
            {
                newIdx++
                IniWrite, %nm%, %iniPath%, Sequences, seq_%newIdx%
            }
        }
        loop % count
        {
            if (A_Index > newIdx)
                IniDelete, %iniPath%, Sequences, seq_%A_Index%
        }
        IniWrite, %newIdx%, %iniPath%, Sequences, count
        MacroGuiRefreshSequenceList()
        TrayMenuRebuild()
        ShowMacroToggledTip("Sequence '" seqName "' deleted", 2000, false)
    }
return

GuiSeqBuild:
    steps := SequenceBuild()
    if (IsObject(steps) && steps.MaxIndex() > 0)
    {
        InputBox, seqName, Save Sequence, Name this sequence:, , 280, 100, , , , , sequence1
        if (!ErrorLevel && Trim(seqName) != "")
        {
            SequenceSave(Trim(seqName), steps)
            MacroGuiRefreshSequenceList()
        }
    }
return

; ── Settings Tab ──────────────────────────────────────

GuiSettingsProfileChange:
    Gui, MacroGui:Submit, NoHide
    GuiControlGet, selProf,, GuiSettingsProfileDDL
    if (selProf != "")
    {
        ProfileApply(selProf)
        MacroGuiRefresh()
        TrayMenuRebuild()
    }
return

GuiAddProfile:
    ProfileAdd()
    MacroGuiRefreshSettingsTab()
    MacroGuiRefreshMainTab()
return

GuiDetectProfile:
    DetectActiveProfile()
    MacroGuiRefresh()
    TrayMenuRebuild()
return

GuiDebugToggle:
    global debugEnabled
    Gui, MacroGui:Submit, NoHide
    GuiControlGet, dbgVal,, GuiDebugCheck
    debugEnabled := dbgVal ? true : false
    TrayMenuRebuild()
    ShowMacroToggledTip("Debug mode " (debugEnabled ? "ON" : "OFF"), 1500, false)
return

GuiReload:
    MacroGuiSavePosition()
    Reload
return

GuiExit:
    MacroGuiSavePosition()
    ExitApp
return

; ── Status timer label ──────────────────────────────────

MacroGuiStatusTick:
    MacroGuiUpdateStatus()
return
