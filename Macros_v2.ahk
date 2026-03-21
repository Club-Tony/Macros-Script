#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
#InputLevel 1

; Macros-Script v2 — AHK v2 parallel port
; Same feature set and data format as Macros.ahk (v1).
; Uses class-based architecture: SlotManager, ProfileManager, TrayMenuManager.
;
; Shared data: macros.ini, macros_events/, profiles.ini, icons/ (v1-compatible)

#Include "Lib_v2\Slots.ahk"
#Include "Lib_v2\Profiles.ahk"
#Include "Lib_v2\TrayMenu.ahk"

; ── Global state ─────────────────────────────────────────────────────────────
global menuActive    := false
global clickMacroOn  := false
global autoClickReady := false
global autoClickOn    := false
global autoClickInterval := 1000

global holdMacroReady    := false
global holdMacroOn       := false
global holdMacroKey      := ""
global holdMacroRepeatMs := 40
global holdMacroIsController := false
global holdMacroControllerButton := 0
global holdMacroControllerLatched := false

global holdHoldReady    := false
global holdHoldOn       := false
global holdHoldKey      := ""
global holdHoldIsController := false
global holdHoldControllerButton := 0
global holdHoldControllerLatched := false

global recorderActive   := false
global recorderPlaying  := false
global recorderPaused   := false
global recorderPlayIndex := 1
global recorderLoopTarget := -1
global recorderLoopCurrent := 1
global recorderEvents   := []
global recorderStart    := 0
global recorderLast     := 0
global recorderMouseSampleMs := 40
global recorderMouseCoordSpace := "screen"
global recorderTargetHwnd := 0
global recorderTargetExe  := ""
global recorderControllerSampleMs := 20
global recorderKbMouseEnabled := true
global recorderControllerEnabled := true
global recorderSendMode := ""
global recorderControllerPrevState := ""
global recorderHasControllerEvents := false
global recorderControllerSuppress := false
global recorderControllerSuppressUntil := 0
global recorderSuppressStopTip := false

global controllerComboTriggerThreshold := 30
global controllerComboPollMs := 50
global controllerComboLatched := false
global controllerXInputReady := false
global controllerXInputFailed := false

global vJoyDeviceId := 1
global vJoyReady    := false

global sendMode := "Input"
global debugEnabled := false

; ── Class instances ───────────────────────────────────────────────────────────
global slots    := SlotManager()
global profile  := ProfileManager()
global recorder := {slotName: "", speed: 1.0, loopMode: "infinite", loopUntilKey: ""}
global sequence := {steps: [], stepIndex: 0, playing: false}
global sequencePlaying := false
global tray     := TrayMenuManager()

; ── Startup ───────────────────────────────────────────────────────────────────
SendMode "Input"
SetWorkingDir A_ScriptDir

; Initialize XInput (reuse v1 library if available; else skip controller features)
; profile detection and tray menu
profile.Detect()
tray.Init()

; First-run tip
if !FileExist(A_ScriptDir "\macros.ini") {
    tipX := A_ScreenWidth - 320
    tipY := A_ScreenHeight - 100
    ToolTip "Macros-Script v2 ready! | Right-click tray for macros | or Ctrl+Shift+Alt+Z for menu", tipX, tipY
    SetTimer () => ToolTip(), -5000
}

; ── Hotkeys ───────────────────────────────────────────────────────────────────

; Ctrl+Shift+Alt+Z — macro menu
$^+!z:: {
    global menuActive
    if menuActive
        return
    menuActive := true
    profile.Detect()
    ToolTip MenuTooltipText()
    SetTimer () => CloseMenu("timeout"), -15000
}

; Ctrl+Alt+P — cycle SendMode (Input → Play → Event → Input)
^!p:: ToggleSendMode()

; Ctrl+Alt+D — debug toggle
^!d:: {
    global debugEnabled
    debugEnabled := !debugEnabled
    tray.Rebuild()
    ShowMacroToggledTip("Debug mode " (debugEnabled ? "ON" : "OFF"), 2000, false)
}

; Ctrl+Esc — reload
^Esc:: Reload()

; ── Context-sensitive hotkeys ─────────────────────────────────────────────────

#HotIf menuActive
    Esc:: CloseMenu("timeout")
    ^!t:: ShowHotkeyHelp()

    F1:: {
        CloseMenu("", true)
        ActivateClickMacro()
        ShowMacroToggledTip("Macro Toggled - F12 => Left click", 3000, false)
    }
    F2:: { CloseMenu("", true); StartAutoclickerSetup() }
    F3:: { CloseMenu("", true); StartHoldMacroSetup() }
    F4:: { CloseMenu("", true); StartPureHoldSetup() }
    F5:: { CloseMenu("", true); StartRecorder() }
    F6:: { CloseMenu("", true); StartRecorder("combined", false, "client") }
#HotIf

#HotIf clickMacroOn
    F12:: MouseClick "Left"
    Esc:: DeactivateClickMacro()
    F1::  DeactivateClickMacro()
#HotIf

#HotIf autoClickReady
    F12:: ToggleAutoclicker()
    F2::  DeactivateAutoclicker()
    Esc:: DeactivateAutoclicker()
#HotIf

#HotIf (recorderActive && !recorderPlaying)
    Esc:: FinalizeRecording()
    F5::  FinalizeRecording()
    F6::  FinalizeRecording()
#HotIf

#HotIf (recorderEvents.Length > 0 && !recorderActive)
    F12:: ToggleRecorderPlayback()
#HotIf

#HotIf (!recorderActive && !recorderPlaying && recorderEvents.Length > 0)
    Esc:: ClearRecorder()
#HotIf

#HotIf sequencePlaying
    Esc:: SequenceStop()
#HotIf

; ── Core functions ────────────────────────────────────────────────────────────

ToggleSendMode() {
    global sendMode, menuActive, holdMacroOn, holdHoldOn, activeProfile := profile
    if (holdMacroOn || holdHoldOn) {
        ShowMacroToggledTip("Cannot change SendMode while hold is active", 2000, false)
        return
    }
    sendMode := (sendMode = "Input") ? "Play" : (sendMode = "Play") ? "Event" : "Input"
    SendMode sendMode
    SetKeyDelay -1, -1
    SetMouseDelay -1
    profile.sendMode := sendMode
    tray.Rebuild()
    ShowMacroToggledTip("SendMode: " sendMode " (Ctrl+Alt+P to cycle)", 2000, false)
    if menuActive
        ToolTip MenuTooltipText()
}

ShowMacroToggledTip(text := "Macro Toggled", durationMs := 3000, earlyHide := true) {
    global sendMode
    if InStr(text, "Macro Toggled Off")
        text := "Macro Toggled Off (SendMode: " sendMode ") - Esc to exit"
    else
        text := text " (SendMode: " sendMode ")"
    tipX := A_ScreenWidth - 320
    tipY := A_ScreenHeight - 100
    ToolTip text, tipX, tipY
    SetTimer () => ToolTip(), -durationMs
}

MenuTooltipText() {
    global sendMode, profile, recorder
    slotDisplay := (recorder.slotName != "") ? recorder.slotName : "(none)"
    text := "Slot: " slotDisplay " | Profile: " profile.name " | SendMode: " sendMode "`n"
          . "────────────────────────────────`n"
          . "F1 - Stage left click with F12 key`n"
          . "F2 - Stage Autoclicker (F12 toggles)`n"
          . "F3 - Stage turbo keyhold`n"
          . "F4 - Stage pure key hold`n"
          . "F5 - Record Macro (screen coords)`n"
          . "F6 - Record Macro (client-locked mouse)`n"
          . "^!P - Cycle send mode (" sendMode ")`n"
          . "^!D - Toggle debug`n"
          . "Right-click tray for slots, profiles, sequences"
    return text
}

ShowHotkeyHelp() {
    global sendMode
    ToolTip "Macros Script Hotkeys`n"
          . "======================`n"
          . "Ctrl+Shift+Alt+Z - Open macro menu`n"
          . "Ctrl+Alt+P - Cycle SendMode (" sendMode ") Input→Play→Event`n"
          . "Ctrl+Alt+D - Toggle debug mode`n"
          . "Ctrl+Esc - Reload script`n"
          . "Right-click tray - Full menu (slots, sequences, profiles)`n"
          . "`nF1-F6 - See menu for options`n"
          . "F12 - Toggle playback / slash-macro / autoclicker`n"
          . "Esc - Cancel / stop current mode"
    SetTimer () => ToolTip(), -15000
}

ToggleRecorderPlayback() {
    global recorderPlaying, recorder
    if recorderPlaying
        StopPlayback()
    else {
        loopMode := recorder.loopMode
        if (loopMode = "fixed")
            StartPlayback("prompt")
        else if (loopMode = "untilkey")
            StartPlaybackUntilKey()
        else
            StartPlayback(-1)
    }
}

StartPlaybackUntilKey() {
    global recorderPlaying, recorder
    stopKey := recorder.loopUntilKey
    if (stopKey = "") {
        ShowMacroToggledTip("No stop key set — tray > Loop Mode > Until Key", 3000, false)
        return
    }
    StartPlayback(-1)
    try Hotkey "~*" stopKey, PlaybackUntilKeyStop, "On"
    ShowMacroToggledTip("Looping until '" stopKey "' pressed | Esc also stops", 3000, false)
}

PlaybackUntilKeyStop(*) {
    global recorder
    stopKey := recorder.loopUntilKey
    StopPlayback()
    if (stopKey != "")
        try Hotkey "~*" stopKey, PlaybackUntilKeyStop, "Off"
}

CloseMenu(reason := "", skipReload := false) {
    global menuActive
    SetTimer () => CloseMenu("timeout"), 0   ; cancel timeout timer
    ToolTip
    menuActive := false
    if (reason = "timeout") {
        ToolTip "Timed Out"
        SetTimer () => ToolTip(), -3000
    }
    if !skipReload
        SetTimer () => Reload(), -100
}

; Stubs — these functions are implemented in the full v1 script and would need
; porting from the existing Macros.ahk controller/recording/playback logic.
; They are declared here so the v2 file is syntactically complete and the
; #HotIf contexts compile correctly.

StartRecorder(mode := "combined", suppressCombo := false, mouseCoordSpace := "screen") {
    global recorderActive, recorderEvents, recorderStart, recorderLast
    global recorderSendMode, sendMode, recorderKbMouseEnabled, recorderControllerEnabled
    global recorderMouseCoordSpace, recorderHasControllerEvents, recorderControllerPrevState
    global recorderControllerSuppress, recorderControllerSuppressUntil
    recorderActive := true
    recorderPlaying := false
    recorderEvents := []
    recorderHasControllerEvents := false
    recorderStart := A_TickCount
    recorderLast  := recorderStart
    recorderSendMode := sendMode
    recorderKbMouseEnabled := (mode = "combined")
    recorderControllerEnabled := true
    recorderControllerPrevState := ""
    recorderMouseCoordSpace := mouseCoordSpace
    tray.SetIcon("recording")
    SetTimer RecorderSampleMouse, recorderMouseSampleMs
    ShowMacroToggledTip("Recording... F5 to stop", 3000, true)
}

FinalizeRecording() {
    global recorderActive, recorderEvents, recorder, slots
    global recorderMouseCoordSpace
    if !recorderActive
        return
    recorderActive := false
    SetTimer RecorderSampleMouse, 0
    tray.SetIcon("idle")
    totalCount := recorderEvents.Length
    if (totalCount = 0) {
        ShowMacroToggledTip("Recording stopped - no events captured", 3000, false)
        return
    }
    slotName := slots.PromptName(recorder.slotName != "" ? recorder.slotName : "untitled")
    if (slotName = "") {
        ShowMacroToggledTip("Recorded " totalCount " events (not saved) — F12 to play", 3000, false)
        return
    }
    recorder.slotName := slotName
    slots.Save(slotName, recorderEvents, recorderMouseCoordSpace)
}

StopRecorder(silent := false) {
    global recorderActive, recorderPlaying
    if !recorderActive && !recorderPlaying
        return
    StopPlayback(true)
    recorderActive  := false
    recorderPlaying := false
    SetTimer RecorderSampleMouse, 0
    tray.SetIcon("idle")
    if !silent
        ShowMacroToggledTip("Macro Toggled Off")
}

StartPlayback(loopMode := "prompt") {
    global recorderEvents, recorderPlaying, recorderPaused
    global recorderPlayIndex, recorderLoopTarget, recorderLoopCurrent
    global recorderHasControllerEvents, recorder
    if recorderPlaying
        return
    if (recorderEvents.Length = 0) {
        ShowMacroToggledTip("No recording to play")
        return
    }
    ; Resolve loop count
    loopTarget := -1
    if (loopMode = "prompt") {
        r := InputBox("Loop count (blank=infinite, Esc=cancel):", "Playback Loops", "w300 h120")
        if (r.Result = "Cancel") {
            ShowMacroToggledTip("Playback canceled", 1200, false)
            return
        }
        v := Trim(r.Value)
        if (v != "" && IsInteger(v) && Integer(v) > 0)
            loopTarget := Integer(v)
    } else if (loopMode != -1)
        loopTarget := loopMode
    recorderPlaying    := true
    recorderPaused     := false
    recorderPlayIndex  := 1
    recorderLoopTarget := loopTarget
    recorderLoopCurrent := 1
    tray.SetIcon("playing")
    loopLabel := loopTarget > 0 ? loopTarget " loops" : "infinite loops"
    ShowMacroToggledTip("Playing macro (" loopLabel ", F12 to stop)")
    SetTimer RecorderPlayNext, -1
}

StopPlayback(silent := false) {
    global recorderPlaying, recorderPaused, recorderPlayIndex
    global recorderLoopTarget, recorderLoopCurrent
    if !recorderPlaying
        return
    recorderPlaying := false
    recorderPaused  := false
    SetTimer RecorderPlayNext, 0
    recorderPlayIndex   := 1
    recorderLoopTarget  := -1
    recorderLoopCurrent := 1
    tray.SetIcon("idle")
    if !silent
        ShowMacroToggledTip("Macro Toggled Off")
}

ClearRecorder() {
    global recorderEvents, recorderActive, recorderPlaying, recorderPaused
    global recorderPlayIndex, recorderLoopTarget, recorderLoopCurrent
    global recorderHasControllerEvents, recorder
    StopPlayback(true)
    StopRecorder(true)
    recorderEvents          := []
    recorderHasControllerEvents := false
    recorderPlayIndex       := 1
    recorderPaused          := false
    recorderLoopTarget      := -1
    recorderLoopCurrent     := 1
    recorder.slotName       := ""
    ShowMacroToggledTip("Macro Toggled Off")
}

; Playback timer: plays each event with scaled delay
RecorderPlayNext(*) {
    global recorderEvents, recorderPlaying, recorderPaused, recorderPlayIndex
    global recorderLoopTarget, recorderLoopCurrent, recorder
    if !recorderPlaying
        return
    maxIndex := recorderEvents.Length
    if (maxIndex = 0)
        return
    speedFactor := (recorder.speed > 0) ? recorder.speed : 1.0
    idx := recorderPlayIndex
    while (idx <= maxIndex) {
        if !recorderPlaying
            return
        if recorderPaused {
            recorderPlayIndex := idx
            return
        }
        evt := recorderEvents[idx]
        scaledDelay := Max(0, Round(evt.delay / speedFactor))
        Sleep scaledDelay
        if recorderPaused {
            recorderPlayIndex := idx
            return
        }
        if (evt.type = "key" || evt.type = "mousebtn") {
            SendEventOrInput("{" evt.code " " evt.state "}")
        } else if (evt.type = "mousemove") {
            CoordMode "Mouse", "Screen"
            MouseMove evt.x, evt.y, 0
        }
        idx++
    }
    if recorderPlaying {
        if (recorderLoopTarget > 0 && recorderLoopCurrent >= recorderLoopTarget) {
            completedLoops := recorderLoopCurrent
            StopPlayback(true)
            ShowMacroToggledTip("Playback complete (" completedLoops " loops)", 2000, false)
            return
        }
        recorderLoopCurrent++
        recorderPlayIndex := 1
        SetTimer RecorderPlayNext, -1
    }
}

; Sample mouse position during recording
RecorderSampleMouse(*) {
    global recorderActive
    if !recorderActive
        return
    CoordMode "Mouse", "Screen"
    MouseGetPos &mx, &my
    RecorderAddEvent("mousemove", , , mx, my)
}

RecorderAddEvent(type, code := "", state := "", x := "", y := "", payload := "") {
    global recorderEvents, recorderLast, recorderActive
    if !recorderActive
        return
    now := A_TickCount
    delay := now - recorderLast
    recorderLast := now
    evt := {type: type, delay: delay}
    if (type = "key" || type = "mousebtn") {
        evt.code  := code
        evt.state := state
    } else if (type = "mousemove") {
        evt.x := x
        evt.y := y
    } else if (type = "controller") {
        evt.state := payload
    }
    recorderEvents.Push(evt)
}

SendEventOrInput(seq) {
    global recorderSendMode, sendMode
    modeToUse := (recorderSendMode != "") ? recorderSendMode : sendMode
    if (modeToUse = "Play")
        SendPlay seq
    else if (modeToUse = "Event")
        SendEvent seq
    else
        SendInput seq
}

; ── Sequence playback ─────────────────────────────────────────────────────────

SequenceStart(seqName) {
    global sequence, sequencePlaying, slots
    sm := SequenceManager()
    steps := sm.Load(seqName)
    if (!IsObject(steps) || steps.Length = 0) {
        ShowMacroToggledTip("Sequence '" seqName "' is empty or missing", 2000, false)
        return
    }
    sequence           := {steps: steps, stepIndex: 1, playing: true}
    sequencePlaying    := true
    SetTimer SequencePlayStep, -1
}

SequenceStop() {
    global sequence, sequencePlaying
    SetTimer SequencePlayStep, 0
    sequence        := {steps: [], stepIndex: 0, playing: false}
    sequencePlaying := false
    StopPlayback()
    ShowMacroToggledTip("Sequence stopped", 1500, false)
}

SequencePlayStep(*) {
    global sequence, sequencePlaying, recorder, slots, debugEnabled
    if (!sequence.playing || sequence.steps.Length = 0) {
        SequenceStop()
        return
    }
    stepIdx    := sequence.stepIndex
    totalSteps := sequence.steps.Length
    if (stepIdx > totalSteps) {
        SequenceStop()
        ShowMacroToggledTip("Sequence complete", 2000, false)
        return
    }
    step     := sequence.steps[stepIdx]
    slotName := step.slotName
    ShowMacroToggledTip("Sequence step " stepIdx " of " totalSteps ": '" slotName "' | Esc to stop", 0, false)
    events := slots.Load(slotName)
    if (!IsObject(events) || events.Length = 0) {
        if debugEnabled
            ShowMacroToggledTip("DEBUG: Skipping empty step " stepIdx ": '" slotName "'", 1500, false)
        sequence.stepIndex := stepIdx + 1
        SetTimer SequencePlayStep, -10
        return
    }
    speedFactor := (recorder.speed > 0) ? recorder.speed : 1.0
    CoordMode "Mouse", "Screen"
    for evt in events {
        if !sequence.playing
            break
        Sleep Max(0, Round(evt.delay / speedFactor))
        if !sequence.playing
            break
        if (evt.type = "key" || evt.type = "mousebtn")
            SendEventOrInput("{" evt.code " " evt.state "}")
        else if (evt.type = "mousemove")
            MouseMove evt.x, evt.y, 0
    }
    if sequence.playing {
        sequence.stepIndex := stepIdx + 1
        if (step.delayAfter > 0)
            Sleep step.delayAfter
        SetTimer SequencePlayStep, -1
    }
}

; ── Stubs for features needing full port (autoclicker, hold macros, etc.) ─────

ActivateClickMacro() {
    global clickMacroOn
    clickMacroOn := true
}
DeactivateClickMacro(silent := false) {
    global clickMacroOn
    clickMacroOn := false
    if !silent
        ShowMacroToggledTip("Macro Toggled Off")
}
ToggleAutoclicker() {
    global autoClickOn, autoClickInterval
    autoClickOn := !autoClickOn
    if autoClickOn
        SetTimer AutoClick, autoClickInterval
    else
        SetTimer AutoClick, 0
}
AutoClick(*) {
    MouseClick "Left"
}
DeactivateAutoclicker(silent := false) {
    global autoClickOn, autoClickReady
    autoClickOn := false
    autoClickReady := false
    SetTimer AutoClick, 0
    if !silent
        ShowMacroToggledTip("Macro Toggled Off")
}
StartAutoclickerSetup() {
    global autoClickInterval, autoClickReady, autoClickOn
    r := InputBox("Enter click interval in ms (default 50):", "Autoclicker", "w280 h120", "50")
    if (r.Result = "Cancel") {
        ShowMacroToggledTip("Autoclicker canceled")
        return
    }
    v := Trim(r.Value)
    if (!IsInteger(v) || Integer(v) < 10) {
        ShowMacroToggledTip("Autoclicker canceled (invalid number)")
        return
    }
    autoClickInterval := Clamp(Integer(v), 10, 10000)
    autoClickOn    := false
    autoClickReady := true
    ShowMacroToggledTip("Macro ready - F12 toggles autoclicker (" autoClickInterval " ms)")
}
StartHoldMacroSetup()  { ShowMacroToggledTip("Turbo hold: not yet ported to v2", 2000, false) }
StartPureHoldSetup()   { ShowMacroToggledTip("Pure hold: not yet ported to v2",  2000, false) }
DeactivateHoldMacro(silent := false)  { global holdMacroOn, holdMacroReady; holdMacroOn := false; holdMacroReady := false }
DeactivatePureHold(silent := false)   { global holdHoldOn, holdHoldReady;   holdHoldOn  := false; holdHoldReady  := false }

TrayMenuRebuild() {
    global tray
    tray.Rebuild()
}
DetectActiveProfile() {
    global profile
    profile.Detect()
}
