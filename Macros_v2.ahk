#Requires AutoHotkey v2.0
#SingleInstance Force
#Include "Lib_v2\ScriptSingleton.ahk"
EnsureScriptSingleton()
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
#Include "Lib_v2\XInput.ahk"
#Include "Lib_v2\VJoy_lib.ahk"
#Include "Lib_v2\Debug.ahk"
#Include "Lib_v2\MacroGui.ahk"

; ── Global state ─────────────────────────────────────────────────────────────
global menuActive    := false
global clickMacroOn  := false
global autoClickReady := false
global autoClickOn    := false
global autoClickInterval := 1000

global holdMacroReady    := false
global holdMacroOn       := false
global holdMacroKey      := ""
global holdMacroBoundKey := ""
global holdMacroRepeatMs := 40
global holdMacroIsController := false
global holdMacroControllerButton := 0
global holdMacroControllerLatched := false

global holdHoldReady    := false
global holdHoldOn       := false
global holdHoldKey      := ""
global holdHoldBoundKey := ""
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
global recorderTargetClientW := 0
global recorderTargetClientH := 0
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
global controllerBackLatched := false
global controllerCancelLatched := false
global controllerTurboLatched := false
global controllerPureHoldLatched := false
global controllerXInputReady := false
global controllerXInputFailed := false
global controllerUserIndex := 0
global controllerThumbDeadzone := 2500
global controllerTriggerDeadzone := 5
global controllerThumbStep := 256
global controllerTriggerStep := 4

global vJoyDeviceId := 1
global vJoyReady    := false
global vJoyUseContPov := false
global vJoyPovMode := ""
global vJoyAxisMax := {}
global vJoyAxisExists := {}
global vJoyButtonCount := 0

global currentSendMode := "Input"
global debugEnabled := false
global promptHoldKeyXInputButton := 0
global promptHoldKeyIsController := false
global macroGui := ""
global macroGuiControls := Map()
global macroGuiCreated := false
global macroGuiVisible := false
global macroGuiRefreshing := false

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
EnsureXInputReady()
SetTimer ControllerComboPoll, controllerComboPollMs

; profile detection and tray menu
profile.Detect()
tray.Init()
MacroGuiCreate()
SetTimer MacroGuiUpdateStatus, 250

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
    global menuActive, profile
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
    global debugEnabled, tray
    debugEnabled := !debugEnabled
    tray.Rebuild()
    ShowMacroToggledTip("Debug mode " (debugEnabled ? "ON" : "OFF"), 2000, false)
    if debugEnabled
        ShowControllerDebugState()
}

; Ctrl+Esc — reload
; Ctrl+Shift+Alt+G - control panel
^+!g:: MacroGuiToggle()

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
    F2:: {
        CloseMenu("", true)
        StartAutoclickerSetup()
    }
    F3:: {
        CloseMenu("", true)
        StartHoldMacroSetup()
    }
    F4:: {
        CloseMenu("", true)
        StartPureHoldSetup()
    }
    F5:: {
        CloseMenu("", true)
        StartRecorder()
    }
    F6:: {
        CloseMenu("", true)
        StartRecorder("combined", false, "client")
    }
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

#HotIf holdMacroReady
    F3:: DeactivateHoldMacro()
    Esc:: DeactivateHoldMacro()
#HotIf

#HotIf holdHoldReady
    F4:: DeactivatePureHold()
    Esc:: DeactivatePureHold()
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

#Include "Lib_v2\Recorder_Keys.ahk"

; ── Core functions ────────────────────────────────────────────────────────────

ToggleSendMode() {
    global currentSendMode, menuActive, holdMacroOn, holdHoldOn, profile, tray
    if (holdMacroOn || holdHoldOn) {
        ShowMacroToggledTip("Cannot change SendMode while hold is active", 2000, false)
        return
    }
    currentSendMode := (currentSendMode = "Input") ? "Play" : (currentSendMode = "Play") ? "Event" : "Input"
    SendMode currentSendMode
    SetKeyDelay -1, -1
    SetMouseDelay -1
    profile.sendMode := currentSendMode
    tray.Rebuild()
    ShowMacroToggledTip("SendMode: " currentSendMode " (Ctrl+Alt+P to cycle)", 2000, false)
    if menuActive
        ToolTip MenuTooltipText()
}

ShowMacroToggledTip(text := "Macro Toggled", durationMs := 3000, earlyHide := true) {
    global currentSendMode
    if InStr(text, "Macro Toggled Off")
        text := "Macro Toggled Off (SendMode: " currentSendMode ") - Esc to exit"
    else
        text := text " (SendMode: " currentSendMode ")"
    tipX := A_ScreenWidth - 320
    tipY := A_ScreenHeight - 100
    ToolTip text, tipX, tipY
    SetTimer () => ToolTip(), -durationMs
}

MenuTooltipText() {
    global currentSendMode, profile, recorder
    slotDisplay := (recorder.slotName != "") ? recorder.slotName : "(none)"
    text := "Slot: " slotDisplay " | Profile: " profile.name " | SendMode: " currentSendMode "`n"
          . "────────────────────────────────`n"
          . "F1 - Stage left click with F12 key`n"
          . "F2 - Stage Autoclicker (F12 toggles)`n"
          . "F3 - Stage turbo keyhold`n"
          . "F4 - Stage pure key hold`n"
          . "F5 - Record Macro (screen coords)`n"
          . "F6 - Record Macro (client-locked mouse)`n"
          . "^!P - Cycle send mode (" currentSendMode ")`n"
          . "^!D - Toggle debug`n"
          . "^+!G - Open control panel`n"
          . "Right-click tray for slots, profiles, sequences"
    return text
}

ShowHotkeyHelp() {
    global currentSendMode
    ToolTip "Macros Script Hotkeys`n"
          . "======================`n"
          . "Ctrl+Shift+Alt+Z - Open macro menu`n"
          . "Ctrl+Shift+Alt+G - Open control panel`n"
          . "Ctrl+Alt+P - Cycle SendMode (" currentSendMode ") Input→Play→Event`n"
          . "Ctrl+Alt+D - Toggle debug mode`n"
          . "Ctrl+Esc - Reload script`n"
          . "Right-click tray - Full menu (slots, sequences, profiles)`n"
          . "`nF1-F6 - See menu for options`n"
          . "F12 - Toggle playback / slash-macro / autoclicker`n"
          . "Esc - Cancel / stop current mode"
    SetTimer () => ToolTip(), -15000
}

Clamp(value, minValue, maxValue) {
    return value < minValue ? minValue : value > maxValue ? maxValue : value
}

EnsureXInputReady() {
    global controllerXInputReady, controllerXInputFailed, _XInput_hm
    if controllerXInputReady
        return true
    if controllerXInputFailed
        return false

    dlls := GetXInputDllPaths()
    if (!IsObject(dlls) || dlls.Length = 0) {
        controllerXInputFailed := true
        return false
    }

    for dll in dlls {
        if XInput_Init(dll, true) {
            controllerXInputReady := (_XInput_hm != 0)
            if controllerXInputReady
                return true
        }
    }

    controllerXInputFailed := true
    return false
}

ControllerGetState() {
    global controllerUserIndex
    if !EnsureXInputReady()
        return ""

    padState := XInput_GetState(controllerUserIndex)
    if padState
        return padState

    Loop 4 {
        idx := A_Index - 1
        if (idx = controllerUserIndex)
            continue

        padState := XInput_GetState(idx)
        if padState {
            controllerUserIndex := idx
            return padState
        }
    }

    return ""
}

GetXInputDllPaths() {
    candidates := ["xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll"]
    dirs := []
    if (A_PtrSize = 8)
        dirs.Push(A_WinDir "\System32")
    else {
        dirs.Push(A_WinDir "\SysWOW64")
        dirs.Push(A_WinDir "\System32")
    }
    dirs.Push(A_ScriptDir)

    paths := []
    for dir in dirs {
        for dll in candidates {
            path := dir "\" dll
            if FileExist(path)
                paths.Push(path)
        }
    }

    return paths
}

ShowControllerDebugState(durationMs := 3500) {
    state := ControllerGetState()
    if !IsObject(state) {
        DebugTip("XInput ready: " (EnsureXInputReady() ? "yes" : "no") "; controller state unavailable", durationMs)
        return
    }

    DebugTip("XInput pad " state.UserIndex
        . " buttons=0x" Format("{:04X}", state.Buttons)
        . " LT=" state.LeftTrigger
        . " RT=" state.RightTrigger
        . " LX=" state.ThumbLX
        . " LY=" state.ThumbLY
        . " RX=" state.ThumbRX
        . " RY=" state.ThumbRY, durationMs)
}

NormalizeControllerState(state) {
    global controllerThumbDeadzone, controllerTriggerDeadzone
    global controllerThumbStep, controllerTriggerStep
    return {
        Buttons: state.Buttons,
        LeftTrigger: NormalizeTrigger(state.LeftTrigger, controllerTriggerDeadzone, controllerTriggerStep),
        RightTrigger: NormalizeTrigger(state.RightTrigger, controllerTriggerDeadzone, controllerTriggerStep),
        ThumbLX: NormalizeThumb(state.ThumbLX, controllerThumbDeadzone, controllerThumbStep),
        ThumbLY: NormalizeThumb(state.ThumbLY, controllerThumbDeadzone, controllerThumbStep),
        ThumbRX: NormalizeThumb(state.ThumbRX, controllerThumbDeadzone, controllerThumbStep),
        ThumbRY: NormalizeThumb(state.ThumbRY, controllerThumbDeadzone, controllerThumbStep)
    }
}

NormalizeThumb(value, deadzone, step) {
    if (Abs(value) < deadzone)
        value := 0
    return Round(value / step) * step
}

NormalizeTrigger(value, deadzone, step) {
    if (value < deadzone)
        value := 0
    return Round(value / step) * step
}

ControllerStatesEqual(a, b) {
    if (!IsObject(a) || !IsObject(b))
        return false
    return (a.Buttons = b.Buttons
        && a.LeftTrigger = b.LeftTrigger
        && a.RightTrigger = b.RightTrigger
        && a.ThumbLX = b.ThumbLX
        && a.ThumbLY = b.ThumbLY
        && a.ThumbRX = b.ThumbRX
        && a.ThumbRY = b.ThumbRY)
}

ControllerStateIsNeutral(state) {
    if !IsObject(state)
        return true
    return (state.Buttons = 0
        && state.LeftTrigger = 0
        && state.RightTrigger = 0
        && state.ThumbLX = 0
        && state.ThumbLY = 0
        && state.ThumbRX = 0
        && state.ThumbRY = 0)
}

IsControllerComboPressed(state) {
    global XINPUT_GAMEPAD_LEFT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER
    global XINPUT_GAMEPAD_A, controllerComboTriggerThreshold
    return IsObject(state)
        && (state.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_A)
        && (state.LeftTrigger >= controllerComboTriggerThreshold)
        && (state.RightTrigger >= controllerComboTriggerThreshold)
}

IsControllerTurboComboPressed(state) {
    global XINPUT_GAMEPAD_LEFT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER
    global XINPUT_GAMEPAD_B, controllerComboTriggerThreshold
    return IsObject(state)
        && (state.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_B)
        && (state.LeftTrigger >= controllerComboTriggerThreshold)
        && (state.RightTrigger >= controllerComboTriggerThreshold)
}

IsControllerPureHoldComboPressed(state) {
    global XINPUT_GAMEPAD_LEFT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER
    global XINPUT_GAMEPAD_Y, controllerComboTriggerThreshold
    return IsObject(state)
        && (state.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_Y)
        && (state.LeftTrigger >= controllerComboTriggerThreshold)
        && (state.RightTrigger >= controllerComboTriggerThreshold)
}

IsControllerCancelComboPressed(state) {
    global XINPUT_GAMEPAD_LEFT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER
    global XINPUT_GAMEPAD_X, XINPUT_KEYSTROKE_KEYDOWN, VK_PAD_X
    global controllerComboTriggerThreshold
    if !IsObject(state)
        return false
    facePressed := (state.Buttons & XINPUT_GAMEPAD_X)
    if (!facePressed && EnsureXInputReady()) {
        keystroke := XInput_GetKeystroke()
        if (keystroke && (keystroke.Flags & XINPUT_KEYSTROKE_KEYDOWN))
            facePressed := (keystroke.VirtualKey = VK_PAD_X)
    }
    return (state.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER)
        && facePressed
        && (state.LeftTrigger >= controllerComboTriggerThreshold)
        && (state.RightTrigger >= controllerComboTriggerThreshold)
}

IsControllerBackComboPressed(state) {
    global XINPUT_GAMEPAD_LEFT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER
    global XINPUT_GAMEPAD_BACK, controllerComboTriggerThreshold
    return IsObject(state)
        && (state.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_BACK)
        && (state.LeftTrigger >= controllerComboTriggerThreshold)
        && (state.RightTrigger >= controllerComboTriggerThreshold)
}

ControllerComboPoll(*) {
    global controllerComboLatched, controllerBackLatched, controllerCancelLatched
    global controllerTurboLatched, controllerPureHoldLatched
    global recorderActive, recorderPlaying, menuActive

    comboState := ControllerGetState()
    if !IsObject(comboState) {
        controllerComboLatched := false
        controllerBackLatched := false
        controllerCancelLatched := false
        controllerTurboLatched := false
        controllerPureHoldLatched := false
        return
    }

    if IsControllerCancelComboPressed(comboState) {
        if !controllerCancelLatched {
            controllerCancelLatched := true
            if recorderActive {
                FinalizeRecording()
                ShowMacroToggledTip("Recording stopped - F12 toggles playback", 1500, false)
            } else {
                DeactivateClickMacro(true)
                DeactivateHoldMacro(true)
                DeactivatePureHold(true)
                DeactivateAutoclicker(true)
                StopPlayback(true)
                StopRecorder(true)
                ClearRecorder()
                if menuActive
                    CloseMenu("", true)
                ShowMacroToggledTip("All macros stopped and cleared", 1500, false)
            }
        }
        return
    }
    controllerCancelLatched := false

    if (recorderActive && IsControllerBackComboPressed(comboState)) {
        if !controllerBackLatched {
            controllerBackLatched := true
            FinalizeRecording()
        }
        return
    }
    controllerBackLatched := false

    if IsControllerTurboComboPressed(comboState) {
        if !controllerTurboLatched {
            controllerTurboLatched := true
            if menuActive
                CloseMenu("", true)
            if (!recorderActive && !recorderPlaying)
                StartHoldMacroSetup()
        }
        return
    }
    controllerTurboLatched := false

    if IsControllerPureHoldComboPressed(comboState) {
        if !controllerPureHoldLatched {
            controllerPureHoldLatched := true
            if menuActive
                CloseMenu("", true)
            if (!recorderActive && !recorderPlaying)
                StartPureHoldSetup()
        }
        return
    }
    controllerPureHoldLatched := false

    if IsControllerComboPressed(comboState) {
        if !controllerComboLatched {
            controllerComboLatched := true
            if recorderActive {
                FinalizeRecording()
                SetTimer AutoStartControllerPlayback, -500
                return
            }
            if recorderPlaying {
                StopPlayback()
                return
            }
            if menuActive
                CloseMenu("", true)
            StartRecorder("combined", true, "client")
        }
    } else {
        controllerComboLatched := false
    }
}

AutoStartControllerPlayback(*) {
    global recorderEvents, recorderPlaying, recorderMouseCoordSpace, recorderTargetExe
    if (recorderEvents.Length = 0 || recorderPlaying)
        return
    StartPlayback(-1)
    if (recorderMouseCoordSpace = "client")
        ShowMacroToggledTip("Auto-started playback (client-locked: " recorderTargetExe ") - combo+A stop, X clear", 3000, true)
    else
        ShowMacroToggledTip("Auto-started playback (L1+L2+R1+R2+A to stop, X to clear)", 3000, true)
}

EnsureVJoyReady() {
    global vJoyDeviceId, vJoyReady, vJoyUseContPov, vJoyPovMode, vJoyAxisMax, vJoyAxisExists
    global vJoyButtonCount
    if vJoyReady
        return true
    if !VJoyAvailable() {
        ShowMacroToggledTip("vJoy not installed")
        return false
    }
    VJoy_init(vJoyDeviceId)
    if !VJoy_Ready(vJoyDeviceId) {
        ShowMacroToggledTip("vJoy not ready")
        return false
    }
    vJoyReady := true
    vJoyUseContPov := (VJoy_GetContPovNumber(vJoyDeviceId) > 0)
    if vJoyUseContPov
        vJoyPovMode := "cont"
    else if (VJoy_GetDiscPovNumber(vJoyDeviceId) > 0)
        vJoyPovMode := "disc"
    else
        vJoyPovMode := ""
    vJoyAxisExists := {}
    vJoyAxisMax := {}
    vJoyButtonCount := VJoy_GetVJDButtonNumber(vJoyDeviceId)
    vJoyAxisExists.X := VJoy_GetAxisExist_X(vJoyDeviceId)
    vJoyAxisExists.Y := VJoy_GetAxisExist_Y(vJoyDeviceId)
    vJoyAxisExists.Z := VJoy_GetAxisExist_Z(vJoyDeviceId)
    vJoyAxisExists.RX := VJoy_GetAxisExist_RX(vJoyDeviceId)
    vJoyAxisExists.RY := VJoy_GetAxisExist_RY(vJoyDeviceId)
    vJoyAxisExists.RZ := VJoy_GetAxisExist_RZ(vJoyDeviceId)
    vJoyAxisExists.SL0 := VJoy_GetAxisExist_SL0(vJoyDeviceId)
    vJoyAxisExists.SL1 := VJoy_GetAxisExist_SL1(vJoyDeviceId)
    vJoyAxisMax.X := VJoy_GetAxisMax_X(vJoyDeviceId)
    vJoyAxisMax.Y := VJoy_GetAxisMax_Y(vJoyDeviceId)
    vJoyAxisMax.Z := VJoy_GetAxisMax_Z(vJoyDeviceId)
    vJoyAxisMax.RX := VJoy_GetAxisMax_RX(vJoyDeviceId)
    vJoyAxisMax.RY := VJoy_GetAxisMax_RY(vJoyDeviceId)
    vJoyAxisMax.RZ := VJoy_GetAxisMax_RZ(vJoyDeviceId)
    vJoyAxisMax.SL0 := VJoy_GetAxisMax_SL0(vJoyDeviceId)
    vJoyAxisMax.SL1 := VJoy_GetAxisMax_SL1(vJoyDeviceId)
    return true
}

VJoyAvailable() {
    if VJoyRegistryPresent()
        return true
    return VJoy_LoadLibrary() != 0
}

VJoyRegistryPresent() {
    install := RegRead64("HKEY_LOCAL_MACHINE", "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{8E31F76F-74C3-47F1-9550-E041EEDC5FBB}_is1", "InstallLocation")
    return install != ""
}

ControllerSupportAvailable() {
    return EnsureXInputReady() && VJoyAvailable()
}

ControllerApplyStateToVJoy(state) {
    global vJoyDeviceId, vJoyAxisMax, vJoyAxisExists, vJoyPovMode
    global XINPUT_GAMEPAD_A, XINPUT_GAMEPAD_B, XINPUT_GAMEPAD_X, XINPUT_GAMEPAD_Y
    global XINPUT_GAMEPAD_LEFT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER
    global XINPUT_GAMEPAD_BACK, XINPUT_GAMEPAD_START
    global XINPUT_GAMEPAD_LEFT_THUMB, XINPUT_GAMEPAD_RIGHT_THUMB
    if (!IsObject(state) || !EnsureVJoyReady())
        return
    if vJoyAxisExists.X
        VJoy_SetAxis_X(MapThumbAxis(state.ThumbLX, vJoyAxisMax.X), vJoyDeviceId)
    if vJoyAxisExists.Y
        VJoy_SetAxis_Y(MapThumbAxis(state.ThumbLY, vJoyAxisMax.Y), vJoyDeviceId)
    if vJoyAxisExists.RX
        VJoy_SetAxis_RX(MapThumbAxis(state.ThumbRX, vJoyAxisMax.RX), vJoyDeviceId)
    if vJoyAxisExists.RY
        VJoy_SetAxis_RY(MapThumbAxis(state.ThumbRY, vJoyAxisMax.RY), vJoyDeviceId)
    if vJoyAxisExists.Z
        VJoy_SetAxis_Z(MapTriggerAxis(state.LeftTrigger, vJoyAxisMax.Z), vJoyDeviceId)
    else if vJoyAxisExists.SL0
        VJoy_SetAxis_SL0(MapTriggerAxis(state.LeftTrigger, vJoyAxisMax.SL0), vJoyDeviceId)
    if vJoyAxisExists.RZ
        VJoy_SetAxis_RZ(MapTriggerAxis(state.RightTrigger, vJoyAxisMax.RZ), vJoyDeviceId)
    else if vJoyAxisExists.SL1
        VJoy_SetAxis_SL1(MapTriggerAxis(state.RightTrigger, vJoyAxisMax.SL1), vJoyDeviceId)

    ControllerApplyPov(state.Buttons, vJoyPovMode)
    SetVJoyButton(1, state.Buttons & XINPUT_GAMEPAD_A)
    SetVJoyButton(2, state.Buttons & XINPUT_GAMEPAD_B)
    SetVJoyButton(3, state.Buttons & XINPUT_GAMEPAD_X)
    SetVJoyButton(4, state.Buttons & XINPUT_GAMEPAD_Y)
    SetVJoyButton(5, state.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER)
    SetVJoyButton(6, state.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER)
    SetVJoyButton(7, state.Buttons & XINPUT_GAMEPAD_BACK)
    SetVJoyButton(8, state.Buttons & XINPUT_GAMEPAD_START)
    SetVJoyButton(9, state.Buttons & XINPUT_GAMEPAD_LEFT_THUMB)
    SetVJoyButton(10, state.Buttons & XINPUT_GAMEPAD_RIGHT_THUMB)
}

SetVJoyButton(btnId, pressed) {
    global vJoyDeviceId, vJoyButtonCount
    if (btnId > vJoyButtonCount)
        return
    VJoy_SetBtn(pressed ? 1 : 0, vJoyDeviceId, btnId)
}

ControllerApplyPov(buttons, mode) {
    global vJoyDeviceId
    global XINPUT_GAMEPAD_DPAD_UP, XINPUT_GAMEPAD_DPAD_DOWN
    global XINPUT_GAMEPAD_DPAD_LEFT, XINPUT_GAMEPAD_DPAD_RIGHT
    if (mode = "")
        return
    up := (buttons & XINPUT_GAMEPAD_DPAD_UP)
    down := (buttons & XINPUT_GAMEPAD_DPAD_DOWN)
    left := (buttons & XINPUT_GAMEPAD_DPAD_LEFT)
    right := (buttons & XINPUT_GAMEPAD_DPAD_RIGHT)
    if (!up && !down && !left && !right) {
        if (mode = "cont")
            VJoy_SetContPov(-1, vJoyDeviceId, 1)
        else
            VJoy_SetDiscPov(-1, vJoyDeviceId, 1)
        return
    }
    if (mode = "cont") {
        angle := 0
        if (up && right)
            angle := 4500
        else if (right && down)
            angle := 13500
        else if (down && left)
            angle := 22500
        else if (left && up)
            angle := 31500
        else if up
            angle := 0
        else if right
            angle := 9000
        else if down
            angle := 18000
        else if left
            angle := 27000
        VJoy_SetContPov(angle, vJoyDeviceId, 1)
    } else {
        dir := -1
        if up
            dir := 0
        else if right
            dir := 1
        else if down
            dir := 2
        else if left
            dir := 3
        VJoy_SetDiscPov(dir, vJoyDeviceId, 1)
    }
}

MapThumbAxis(value, axisMax) {
    if (axisMax <= 0)
        return 0
    return Round(((value + 32768) * axisMax) / 65535)
}

MapTriggerAxis(value, axisMax) {
    if (axisMax <= 0)
        return 0
    return Round((value * axisMax) / 255)
}

ControllerResetVJoyState() {
    global vJoyDeviceId, vJoyReady
    if !vJoyReady
        return
    VJoy_ResetVJD(vJoyDeviceId)
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

; ── Recorder / playback / sequence core ─────────────────────────────────────
; Keyboard/mouse recorder, playback engine, and sequence chaining.
; Controller recording and vJoy playback are implemented; live parity remains
; tracked in Plans/v2-port-completion.md.

StartRecorder(mode := "combined", suppressCombo := false, mouseCoordSpace := "screen") {
    global recorderActive, recorderPlaying, recorderEvents, recorderStart, recorderLast
    global recorderSendMode, currentSendMode, recorderKbMouseEnabled, recorderControllerEnabled
    global recorderMouseCoordSpace, recorderHasControllerEvents, recorderControllerPrevState
    global recorderControllerSuppress, recorderControllerSuppressUntil
    global recorderTargetHwnd, recorderTargetExe, recorderTargetClientW, recorderTargetClientH
    global tray
    recorderActive := true
    recorderPlaying := false
    recorderEvents := []
    recorderHasControllerEvents := false
    recorderStart := A_TickCount
    recorderLast  := recorderStart
    recorderSendMode := currentSendMode
    recorderKbMouseEnabled := (mode = "combined")
    recorderControllerEnabled := true
    recorderControllerPrevState := ""
    recorderMouseCoordSpace := "screen"
    recorderTargetHwnd := 0
    recorderTargetExe := ""
    recorderTargetClientW := 0
    recorderTargetClientH := 0

    if (mouseCoordSpace = "client") {
        recorderTargetHwnd := WinExist("A")
        if recorderTargetHwnd {
            try recorderTargetExe := WinGetProcessName("ahk_id " recorderTargetHwnd)
            if (recorderTargetExe != "" && Recorder_GetClientSize(recorderTargetHwnd, &recorderTargetClientW, &recorderTargetClientH))
                recorderMouseCoordSpace := "client"
        }
    }

    if suppressCombo {
        recorderControllerSuppress := true
        recorderControllerSuppressUntil := A_TickCount + 500
    } else {
        recorderControllerSuppress := false
        recorderControllerSuppressUntil := 0
    }

    if !EnsureXInputReady()
        recorderControllerEnabled := false
    else if !IsObject(ControllerGetState())
        recorderControllerEnabled := false

    tray.SetIcon("recording")
    if recorderKbMouseEnabled
        SetTimer RecorderSampleMouse, recorderMouseSampleMs
    else
        SetTimer RecorderSampleMouse, 0
    SetTimer RecorderSampleController, recorderControllerSampleMs
    if (recorderMouseCoordSpace = "client")
        ShowMacroToggledTip("Recording macro (client-locked: " recorderTargetExe ")... F5 to stop", 3000, true)
    else if (mouseCoordSpace = "client")
        ShowMacroToggledTip("Recording macro... F5 to stop (client lock unavailable)", 3000, true)
    else
        ShowMacroToggledTip("Recording... F5 to stop", 3000, true)
}

FinalizeRecording() {
    global recorderActive, recorderEvents, recorder, slots
    global recorderMouseCoordSpace
    global recorderKbMouseEnabled, recorderControllerEnabled, recorderControllerSuppress
    global recorderControllerSuppressUntil, recorderControllerPrevState, recorderSuppressStopTip
    global tray
    if !recorderActive
        return
    recorderActive := false
    SetTimer RecorderSampleMouse, 0
    SetTimer RecorderSampleController, 0
    recorderKbMouseEnabled := true
    recorderControllerEnabled := true
    recorderControllerSuppress := false
    recorderControllerSuppressUntil := 0
    recorderControllerPrevState := ""
    tray.SetIcon("idle")
    if recorderSuppressStopTip {
        recorderSuppressStopTip := false
        return
    }
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
    MacroGuiRefresh()
}

StopRecorder(silent := false) {
    global recorderActive, recorderPlaying
    global recorderControllerPrevState, recorderControllerSuppress, recorderControllerSuppressUntil
    global tray
    if !recorderActive && !recorderPlaying
        return
    StopPlayback(true)
    recorderActive  := false
    recorderPlaying := false
    SetTimer RecorderSampleMouse, 0
    SetTimer RecorderSampleController, 0
    recorderControllerPrevState := ""
    recorderControllerSuppress := false
    recorderControllerSuppressUntil := 0
    tray.SetIcon("idle")
    if !silent
        ShowMacroToggledTip("Macro Toggled Off")
}

StartPlayback(loopMode := "prompt") {
    global recorderEvents, recorderPlaying, recorderPaused
    global recorderPlayIndex, recorderLoopTarget, recorderLoopCurrent
    global recorderHasControllerEvents, recorder
    global recorderMouseCoordSpace, recorderTargetExe
    global tray
    if recorderPlaying
        return
    if (recorderEvents.Length = 0) {
        ShowMacroToggledTip("No recording to play")
        return
    }
    if (recorderHasControllerEvents && !EnsureVJoyReady()) {
        ShowMacroToggledTip("vJoy not ready - controller playback unavailable", 3000, false)
        return
    }
    if (recorderMouseCoordSpace = "client") {
        activeExe := ""
        try activeExe := WinGetProcessName("A")
        if (activeExe = "" || activeExe != recorderTargetExe) {
            ShowMacroToggledTip("Focus " recorderTargetExe " and press F12 again", 3000, false)
            return
        }
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
    global recorderLoopTarget, recorderLoopCurrent, recorderHasControllerEvents
    global tray
    if !recorderPlaying
        return
    recorderPlaying := false
    recorderPaused  := false
    SetTimer RecorderPlayNext, 0
    recorderPlayIndex   := 1
    recorderLoopTarget  := -1
    recorderLoopCurrent := 1
    if recorderHasControllerEvents
        ControllerResetVJoyState()
    tray.SetIcon("idle")
    if !silent
        ShowMacroToggledTip("Macro Toggled Off")
}

TogglePlaybackPause(*) {
    global recorderPlaying, recorderPaused
    global tray
    if !recorderPlaying
        return
    recorderPaused := !recorderPaused
    tray.SetIcon(recorderPaused ? "paused" : "playing")
    ShowMacroToggledTip(recorderPaused ? "Playback paused" : "Playback resumed", 1200, false)
    if !recorderPaused
        SetTimer RecorderPlayNext, -1
}

RecorderEventsHaveController(events) {
    if !IsObject(events)
        return false
    for evt in events {
        if !IsObject(evt)
            continue
        try {
            if (evt.type = "controller")
                return true
        }
    }
    return false
}

LoadRecorderSlot(slotName, showTip := true) {
    global slots, recorderEvents, recorder, recorderMouseCoordSpace, recorderHasControllerEvents
    global recorderTargetExe, recorderTargetClientW, recorderTargetClientH
    events := slots.Load(slotName)
    if (IsObject(events) && events.Length > 0) {
        recorderEvents := events
        recorder.slotName := slotName
        iniPath := A_ScriptDir "\macros.ini"
        recorderMouseCoordSpace := IniRead(iniPath, slotName, "coord_mode", "screen")
        recorderTargetExe := IniRead(iniPath, slotName, "target_exe", "")
        recorderTargetClientW := IniRead(iniPath, slotName, "target_client_w", 0) + 0
        recorderTargetClientH := IniRead(iniPath, slotName, "target_client_h", 0) + 0
        recorderHasControllerEvents := RecorderEventsHaveController(events)
        if showTip
            ShowMacroToggledTip("Slot '" slotName "' loaded | F12 to play", 2000, false)
        TrayMenuRebuild()
        MacroGuiRefresh()
        return true
    }
    if showTip
        ShowMacroToggledTip("Slot '" slotName "' is empty", 2000, false)
    return false
}

ClearRecorder() {
    global recorderEvents, recorderActive, recorderPlaying, recorderPaused
    global recorderPlayIndex, recorderLoopTarget, recorderLoopCurrent
    global recorderHasControllerEvents, recorder
    global recorderSendMode, recorderKbMouseEnabled, recorderControllerEnabled
    global recorderControllerSuppress, recorderControllerSuppressUntil, recorderControllerPrevState
    global recorderMouseCoordSpace, recorderTargetHwnd, recorderTargetExe, recorderTargetClientW, recorderTargetClientH
    StopPlayback(true)
    StopRecorder(true)
    recorderEvents          := []
    recorderHasControllerEvents := false
    recorderSendMode := ""
    recorderKbMouseEnabled := true
    recorderControllerEnabled := true
    recorderControllerSuppress := false
    recorderControllerSuppressUntil := 0
    recorderControllerPrevState := ""
    recorderMouseCoordSpace := "screen"
    recorderTargetHwnd := 0
    recorderTargetExe := ""
    recorderTargetClientW := 0
    recorderTargetClientH := 0
    recorderPlayIndex       := 1
    recorderPaused          := false
    recorderLoopTarget      := -1
    recorderLoopCurrent     := 1
    recorder.slotName       := ""
    ShowMacroToggledTip("Macro Toggled Off")
    MacroGuiRefresh()
}

; Playback timer: plays each event with scaled delay
RecorderPlayNext(*) {
    global recorderEvents, recorderPlaying, recorderPaused, recorderPlayIndex
    global recorderLoopTarget, recorderLoopCurrent, recorder
    global recorderMouseCoordSpace, recorderTargetExe
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
        if (evt.type = "key") {
            SendEventOrInput("{" evt.code " " evt.state "}")
        } else if (evt.type = "mousebtn") {
            if (evt.state != "")
                SendEventOrInput("{" evt.code " " evt.state "}")
            else
                SendEventOrInput("{" evt.code "}")
        } else if (evt.type = "mousemove") {
            CoordMode "Mouse", "Screen"
            if (recorderMouseCoordSpace = "client") {
                activeExe := ""
                try activeExe := WinGetProcessName("A")
                if (activeExe = "" || activeExe != recorderTargetExe) {
                    StopPlayback(true)
                    ShowMacroToggledTip("Playback stopped (focus lost: " recorderTargetExe ")", 3000, false)
                    return
                }
                hwnd := WinExist("A")
                if (!hwnd || !Recorder_ClientToScreen(hwnd, evt.x, evt.y, &sx, &sy)) {
                    StopPlayback(true)
                    ShowMacroToggledTip("Playback stopped (client coords conversion failed)", 3000, false)
                    return
                }
                MouseMove sx, sy, 0
            } else {
                MouseMove evt.x, evt.y, 0
            }
        } else if (evt.type = "controller") {
            ControllerApplyStateToVJoy(evt.state)
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

RecorderSampleController(*) {
    global recorderActive, recorderControllerEnabled, recorderControllerPrevState
    global recorderHasControllerEvents, recorderControllerSuppress, recorderControllerSuppressUntil
    if (!recorderActive || !recorderControllerEnabled)
        return

    if (recorderControllerSuppress && A_TickCount < recorderControllerSuppressUntil)
        return
    else if recorderControllerSuppress
        recorderControllerSuppress := false

    sampleState := ControllerGetState()
    if !IsObject(sampleState)
        return

    sampleNorm := NormalizeControllerState(sampleState)
    if (recorderControllerPrevState = "") {
        recorderControllerPrevState := sampleNorm
        if !ControllerStateIsNeutral(sampleNorm) {
            RecorderAddEvent("controller", "", "", "", "", sampleNorm)
            recorderHasControllerEvents := true
        }
        return
    }
    if !ControllerStatesEqual(sampleNorm, recorderControllerPrevState) {
        recorderControllerPrevState := sampleNorm
        RecorderAddEvent("controller", "", "", "", "", sampleNorm)
        recorderHasControllerEvents := true
    }
}

RecorderAddEvent(type, code := "", state := "", x := "", y := "", payload := "") {
    global recorderEvents, recorderLast, recorderActive
    global recorderMouseCoordSpace, recorderTargetHwnd
    if !recorderActive
        return
    if (type = "mousemove" && recorderMouseCoordSpace = "client") {
        if (!recorderTargetHwnd)
            return
        if !Recorder_ScreenToClient(recorderTargetHwnd, x, y, &cx, &cy)
            return
        if !Recorder_GetClientSize(recorderTargetHwnd, &cw, &ch)
            return
        if (cx < 0 || cy < 0 || cx >= cw || cy >= ch)
            return
    }
    now := A_TickCount
    delay := now - recorderLast
    recorderLast := now
    evt := {type: type, delay: delay}
    if (type = "key" || type = "mousebtn") {
        evt.code  := code
        evt.state := state
    } else if (type = "mousemove") {
        if (recorderMouseCoordSpace = "client") {
            evt.x := cx
            evt.y := cy
        } else {
            evt.x := x
            evt.y := y
        }
    } else if (type = "controller") {
        evt.state := payload
    }
    recorderEvents.Push(evt)
}

Recorder_GetClientSize(hwnd, &w, &h) {
    rect := Buffer(16, 0)
    if !DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect.Ptr, "Int")
        return false
    w := NumGet(rect, 8, "Int")
    h := NumGet(rect, 12, "Int")
    return true
}

Recorder_ScreenToClient(hwnd, sx, sy, &cx, &cy) {
    pt := Buffer(8, 0)
    NumPut("Int", sx, pt, 0)
    NumPut("Int", sy, pt, 4)
    if !DllCall("ScreenToClient", "Ptr", hwnd, "Ptr", pt.Ptr, "Int")
        return false
    cx := NumGet(pt, 0, "Int")
    cy := NumGet(pt, 4, "Int")
    return true
}

Recorder_ClientToScreen(hwnd, cx, cy, &sx, &sy) {
    pt := Buffer(8, 0)
    NumPut("Int", cx, pt, 0)
    NumPut("Int", cy, pt, 4)
    if !DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", pt.Ptr, "Int")
        return false
    sx := NumGet(pt, 0, "Int")
    sy := NumGet(pt, 4, "Int")
    return true
}

SendEventOrInput(seq) {
    global recorderSendMode, currentSendMode
    modeToUse := (recorderSendMode != "") ? recorderSendMode : currentSendMode
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
        DebugTip("Skipping empty step " stepIdx ": '" slotName "'", 1500)
        sequence.stepIndex := stepIdx + 1
        SetTimer SequencePlayStep, -10
        return
    }
    if (RecorderEventsHaveController(events) && !EnsureVJoyReady()) {
        SequenceStop()
        ShowMacroToggledTip("Sequence stopped - vJoy not ready for controller slot", 3000, false)
        return
    }
    coordMode := IniRead(A_ScriptDir "\macros.ini", slotName, "coord_mode", "screen")
    speedFactor := (recorder.speed > 0) ? recorder.speed : 1.0
    CoordMode "Mouse", "Screen"
    for evt in events {
        if !sequence.playing
            break
        Sleep Max(0, Round(evt.delay / speedFactor))
        if !sequence.playing
            break
        if (evt.type = "key")
            SendEventOrInput("{" evt.code " " evt.state "}")
        else if (evt.type = "mousebtn") {
            if (evt.state != "")
                SendEventOrInput("{" evt.code " " evt.state "}")
            else
                SendEventOrInput("{" evt.code "}")
        } else if (evt.type = "mousemove") {
            if (coordMode = "client") {
                hwnd := WinExist("A")
                if (hwnd && Recorder_ClientToScreen(hwnd, evt.x, evt.y, &sx, &sy))
                    MouseMove sx, sy, 0
            } else {
                MouseMove evt.x, evt.y, 0
            }
        } else if (evt.type = "controller") {
            ControllerApplyStateToVJoy(evt.state)
        }
    }
    if sequence.playing {
        sequence.stepIndex := stepIdx + 1
        if (step.delayAfter > 0)
            Sleep step.delayAfter
        SetTimer SequencePlayStep, -1
    }
}

; ── Feature helpers ──────────────────────────────────────────────────────────

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
StartHoldMacroSetup() {
    global holdMacroReady, holdMacroOn, holdMacroKey, holdMacroRepeatMs
    global holdMacroIsController, holdMacroControllerButton, holdMacroControllerLatched
    global promptHoldKeyXInputButton, promptHoldKeyIsController
    DeactivateHoldMacro(true)

    r := InputBox("Enter repeat interval in ms (default " holdMacroRepeatMs "):", "Turbo Hold", "w320 h130", holdMacroRepeatMs)
    if (r.Result != "Cancel" && Trim(r.Value) != "" && IsInteger(Trim(r.Value)))
        holdMacroRepeatMs := Clamp(Integer(Trim(r.Value)), 10, 10000)

    holdKey := PromptHoldKey("Input key to turbo (15s timeout).")
    if (holdKey = "") {
        ShowMacroToggledTip("Turbo canceled (invalid key)")
        return
    }

    holdMacroKey := holdKey
    holdMacroIsController := promptHoldKeyIsController
    holdMacroControllerButton := promptHoldKeyXInputButton
    holdMacroControllerLatched := false
    holdMacroReady := true
    holdMacroOn := false

    if holdMacroIsController {
        SetTimer HoldMacroControllerPoll, 50
        ShowMacroToggledTip("Turbo ready: " holdKey " (press again to toggle)")
    } else {
        BindHoldHotkey(holdMacroKey, "On")
        HoldMacroToggle()
    }
}

StartPureHoldSetup() {
    global holdHoldReady, holdHoldOn, holdHoldKey
    global holdHoldIsController, holdHoldControllerButton, holdHoldControllerLatched
    global promptHoldKeyXInputButton, promptHoldKeyIsController
    DeactivatePureHold(true)

    holdKey := PromptHoldKey("Input key to hold down (15s timeout).")
    if (holdKey = "") {
        ShowMacroToggledTip("Keyhold canceled (invalid key)")
        return
    }

    holdHoldKey := holdKey
    holdHoldIsController := promptHoldKeyIsController
    holdHoldControllerButton := promptHoldKeyXInputButton
    holdHoldControllerLatched := false
    holdHoldReady := true
    holdHoldOn := false

    if holdHoldIsController {
        SetTimer PureHoldControllerPoll, 50
        ShowMacroToggledTip("Pure Hold ready: " holdKey " (press again to toggle)")
    } else {
        BindPureHoldHotkey(holdHoldKey, "On")
        PureHoldToggle()
    }
}

PromptHoldKey(promptText) {
    global promptHoldKeyXInputButton, promptHoldKeyIsController
    promptHoldKeyXInputButton := 0
    promptHoldKeyIsController := false

    releaseStartTime := A_TickCount
    ToolTip "Release all controller buttons..."
    Loop {
        ctrlState := ControllerGetState()
        if (!IsObject(ctrlState) || ctrlState.Buttons = 0)
            break
        if (A_TickCount - releaseStartTime > 5000) {
            ToolTip
            return ""
        }
        Sleep 50
    }

    ToolTip promptText "`n(Controller buttons also supported)"
    SetTimer () => ToolTip(), -15000
    ih := InputHook("L1 T15 V")
    ih.Start()
    startTime := A_TickCount
    holdKey := ""

    Loop {
        if (ih.EndReason != "") {
            ih.Stop()
            holdKey := ih.Input
            if (holdKey = "")
                holdKey := ih.EndKey
            holdKey := GetKeyName(holdKey)
            break
        }

        for modKey in ["LShift", "RShift", "LControl", "RControl", "LAlt", "RAlt"] {
            if GetKeyState(modKey, "P") {
                ih.Stop()
                holdKey := modKey
                ToolTip "Modifier key detected: " holdKey
                KeyWait modKey
                Sleep 200
                break 2
            }
        }

        detected := ControllerDetectPressedButton()
        if IsObject(detected) {
            ih.Stop()
            holdKey := detected.name
            promptHoldKeyXInputButton := detected.button
            promptHoldKeyIsController := true
            ToolTip "Controller button detected: " holdKey
            Sleep 1000
            break
        }

        if (A_TickCount - startTime > 15000) {
            ih.Stop()
            holdKey := ""
            break
        }
        Sleep 50
    }

    ToolTip
    return holdKey
}

ControllerDetectPressedButton() {
    global XINPUT_GAMEPAD_A, XINPUT_GAMEPAD_B, XINPUT_GAMEPAD_X, XINPUT_GAMEPAD_Y
    global XINPUT_GAMEPAD_LEFT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER
    global XINPUT_GAMEPAD_DPAD_UP, XINPUT_GAMEPAD_DPAD_DOWN, XINPUT_GAMEPAD_DPAD_LEFT, XINPUT_GAMEPAD_DPAD_RIGHT
    ctrlState := ControllerGetState()
    if (!IsObject(ctrlState) || ctrlState.Buttons = 0)
        return ""
    if (ctrlState.Buttons & XINPUT_GAMEPAD_A)
        return {name: "A (Cross)", button: XINPUT_GAMEPAD_A}
    if (ctrlState.Buttons & XINPUT_GAMEPAD_B)
        return {name: "B (Circle)", button: XINPUT_GAMEPAD_B}
    if (ctrlState.Buttons & XINPUT_GAMEPAD_X)
        return {name: "X (Square)", button: XINPUT_GAMEPAD_X}
    if (ctrlState.Buttons & XINPUT_GAMEPAD_Y)
        return {name: "Y (Triangle)", button: XINPUT_GAMEPAD_Y}
    if (ctrlState.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER)
        return {name: "LB (L1)", button: XINPUT_GAMEPAD_LEFT_SHOULDER}
    if (ctrlState.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER)
        return {name: "RB (R1)", button: XINPUT_GAMEPAD_RIGHT_SHOULDER}
    if (ctrlState.Buttons & XINPUT_GAMEPAD_DPAD_UP)
        return {name: "D-Pad Up", button: XINPUT_GAMEPAD_DPAD_UP}
    if (ctrlState.Buttons & XINPUT_GAMEPAD_DPAD_DOWN)
        return {name: "D-Pad Down", button: XINPUT_GAMEPAD_DPAD_DOWN}
    if (ctrlState.Buttons & XINPUT_GAMEPAD_DPAD_LEFT)
        return {name: "D-Pad Left", button: XINPUT_GAMEPAD_DPAD_LEFT}
    if (ctrlState.Buttons & XINPUT_GAMEPAD_DPAD_RIGHT)
        return {name: "D-Pad Right", button: XINPUT_GAMEPAD_DPAD_RIGHT}
    return ""
}

BindHoldHotkey(key, mode := "On") {
    global holdMacroBoundKey
    if (holdMacroBoundKey != "") {
        try Hotkey "*" holdMacroBoundKey, "Off"
    }
    if (key = "") {
        holdMacroBoundKey := ""
        return
    }
    holdMacroBoundKey := key
    Hotkey "*" key, (*) => HoldMacroToggle(), mode
}

HoldMacroToggle(*) {
    global holdMacroReady, holdMacroOn, holdMacroKey, holdMacroRepeatMs, holdMacroIsController
    if (!holdMacroReady || holdMacroKey = "")
        return
    if holdMacroOn {
        if !holdMacroIsController
            Send "{" holdMacroKey " up}"
        holdMacroOn := false
        SetTimer HoldKeyRepeat, 0
        ShowMacroToggledTip("Turbo OFF: " holdMacroKey, 1000, false)
    } else {
        if !holdMacroIsController
            Send "{" holdMacroKey " down}"
        holdMacroOn := true
        SetTimer HoldKeyRepeat, holdMacroRepeatMs
        ShowMacroToggledTip("Turbo ON: " holdMacroKey, 1000, false)
    }
}

HoldMacroControllerPoll(*) {
    global holdMacroReady, holdMacroControllerButton, holdMacroControllerLatched
    if (!holdMacroReady || holdMacroControllerButton = 0)
        return
    ctrlState := ControllerGetState()
    if !IsObject(ctrlState)
        return
    buttonPressed := (ctrlState.Buttons & holdMacroControllerButton) != 0
    if buttonPressed {
        if !holdMacroControllerLatched {
            holdMacroControllerLatched := true
            HoldMacroToggle()
        }
    } else {
        holdMacroControllerLatched := false
    }
}

HoldKeyRepeat(*) {
    global holdMacroOn, holdMacroKey, holdMacroIsController
    if (!holdMacroOn || holdMacroKey = "" || holdMacroIsController)
        return
    Send "{" holdMacroKey "}"
}

DeactivateHoldMacro(silent := false) {
    global holdMacroReady, holdMacroOn, holdMacroKey
    global holdMacroIsController, holdMacroControllerButton, holdMacroControllerLatched
    if (!holdMacroReady && !holdMacroOn)
        return
    if (holdMacroOn && holdMacroKey != "" && !holdMacroIsController)
        Send "{" holdMacroKey " up}"
    SetTimer HoldKeyRepeat, 0
    SetTimer HoldMacroControllerPoll, 0
    holdMacroOn := false
    holdMacroReady := false
    holdMacroKey := ""
    holdMacroIsController := false
    holdMacroControllerButton := 0
    holdMacroControllerLatched := false
    BindHoldHotkey("", "Off")
    if !silent
        ShowMacroToggledTip("Macro Toggled Off")
}

BindPureHoldHotkey(key, mode := "On") {
    global holdHoldBoundKey
    if (holdHoldBoundKey != "") {
        try Hotkey "*" holdHoldBoundKey, "Off"
    }
    if (key = "") {
        holdHoldBoundKey := ""
        return
    }
    holdHoldBoundKey := key
    Hotkey "*" key, (*) => PureHoldToggle(), mode
}

PureHoldToggle(*) {
    global holdHoldReady, holdHoldOn, holdHoldKey, holdHoldIsController
    if (!holdHoldReady || holdHoldKey = "")
        return
    if holdHoldOn {
        if !holdHoldIsController
            Send "{" holdHoldKey " up}"
        holdHoldOn := false
        ShowMacroToggledTip("Hold OFF: " holdHoldKey, 1000, false)
    } else {
        if !holdHoldIsController
            Send "{" holdHoldKey " down}"
        holdHoldOn := true
        ShowMacroToggledTip("Hold ON: " holdHoldKey, 1000, false)
    }
}

PureHoldControllerPoll(*) {
    global holdHoldReady, holdHoldControllerButton, holdHoldControllerLatched
    if (!holdHoldReady || holdHoldControllerButton = 0)
        return
    ctrlState := ControllerGetState()
    if !IsObject(ctrlState)
        return
    buttonPressed := (ctrlState.Buttons & holdHoldControllerButton) != 0
    if buttonPressed {
        if !holdHoldControllerLatched {
            holdHoldControllerLatched := true
            PureHoldToggle()
        }
    } else {
        holdHoldControllerLatched := false
    }
}

DeactivatePureHold(silent := false) {
    global holdHoldReady, holdHoldOn, holdHoldKey
    global holdHoldIsController, holdHoldControllerButton, holdHoldControllerLatched
    if (!holdHoldReady && !holdHoldOn)
        return
    if (holdHoldOn && holdHoldKey != "" && !holdHoldIsController)
        Send "{" holdHoldKey " up}"
    SetTimer PureHoldControllerPoll, 0
    holdHoldOn := false
    holdHoldReady := false
    holdHoldKey := ""
    holdHoldIsController := false
    holdHoldControllerButton := 0
    holdHoldControllerLatched := false
    BindPureHoldHotkey("", "Off")
    if !silent
        ShowMacroToggledTip("Macro Toggled Off")
}

TrayMenuRebuild() {
    global tray
    tray.Rebuild()
}
DetectActiveProfile() {
    global profile
    profile.Detect()
}
