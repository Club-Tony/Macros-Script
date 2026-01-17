#Requires AutoHotkey v1
#NoEnv ; Prevents Unnecessary Environment Variable lookup
#SingleInstance, Force ; Removes script already open warning when reloading scripts
#UseHook
#Warn
#Warn, LocalSameAsGlobal, Off
#Warn, Unreachable, Off
#Include <XInput>
#Include <VJoy_lib>
SendMode Input
SetWorkingDir, %A_ScriptDir%

; Script for common macros (fast clicking, fast repeated key presses, etc)

menuActive := false
slashMacroOn := false
macroTipVisible := false
macroTipIdleBaseline := 0
macroTipEarlyHide := true
holdMacroReady := false
holdMacroOn := false
holdMacroKey := ""
holdMacroBoundKey := ""
holdMacroRepeatMs := 40
holdMacroIsController := false
holdMacroControllerButton := 0
holdMacroControllerLatched := false
holdHoldReady := false
holdHoldOn := false
holdHoldKey := ""
holdHoldBoundKey := ""
holdHoldIsController := false
holdHoldControllerButton := 0
holdHoldControllerLatched := false
autoClickReady := false
autoClickOn := false
autoClickInterval := 1000
recorderActive := false
recorderPlaying := false
recorderPaused := false
recorderPlayIndex := 1
recorderSuppressStopTip := false
recorderEvents := []
recorderStart := 0
recorderLast := 0
recorderMouseSampleMs := 40
recorderControllerSampleMs := 20
recorderKbMouseEnabled := true
recorderControllerEnabled := true
recorderSendMode := ""
recorderControllerPrevState := ""
recorderHasControllerEvents := false
recorderControllerSuppress := false
recorderControllerSuppressUntil := 0
controllerUserIndex := 0
controllerComboTriggerThreshold := 30
controllerComboPollMs := 50
controllerComboLatched := false
controllerStartLatched := false
controllerBackLatched := false
controllerCancelLatched := false
controllerTurboLatched := false
controllerPureHoldLatched := false
controllerInputBoxALatched := false
controllerThumbDeadzone := 2500
controllerTriggerDeadzone := 5
controllerThumbStep := 256
controllerTriggerStep := 4
controllerXInputReady := false
controllerXInputFailed := false
vJoyDeviceId := 1
vJoyReady := false
vJoyUseContPov := false
vJoyPovMode := ""
vJoyAxisMax := {}
vJoyAxisExists := {}
vJoyButtonCount := 0
hVJDLL := 0
sendMode := "Input"
sendModeTip := "SendMode: Input (toggle: Ctrl+Alt+P)"

; DEBUG: Test XInput initialization at startup
xinputReady := EnsureXInputReady()
if (xinputReady)
    ToolTip, DEBUG: XInput initialized successfully
else
    ToolTip, DEBUG: XInput FAILED to initialize
SetTimer, HideTempTip, -3000

SetTimer, ControllerComboPoll, % controllerComboPollMs
SetTimer, ControllerInputBoxHelper, 100  ; Monitor for InputBoxes and allow A button to confirm

return


^Esc::Reload

^!p::
    ToggleSendMode()
return

; Ctrl+Shift+Alt+Z shows a temporary menu for staged actions.
^+!z::
    if (menuActive)
        return
    DeactivateSlashMacro(true)
    DeactivateHoldMacro(true)
    DeactivatePureHold(true)
    DeactivateAutoclicker(true)
    StopRecorder(true)
    ClearMacroTips()
    menuActive := true
    ToolTip, % MenuTooltipText()
    SetTimer, MenuTimeout, -15000
return

#If (menuActive)
Esc::
    CloseMenu("timeout")
return

; Ctrl+Alt+T shows help when menu is open (otherwise passes through to ToolTips.ahk)
^!t::
    ShowHotkeyHelp()
return

F1::
    CloseMenu()
    ActivateSlashMacro()
    ShowMacroToggledTip("Macro Toggled - Slash => Left click")
return

F2::
    CloseMenu()
    StartAutoclickerSetup()
return

F3::
    CloseMenu()
    StartHoldMacroSetup()
return

F4::
    CloseMenu()
    StartPureHoldSetup()
return

F5::
    CloseMenu()
    StartRecorder()
return
#If

#If (slashMacroOn)
$/::
    MouseClick, Left
return

Esc::
F1::
    DeactivateSlashMacro()
return
#If

#If (autoClickReady)
$/::
    ToggleAutoclicker()
return

F2::
Esc::
    DeactivateAutoclicker()
return
#If

#If (recorderActive && !recorderPlaying)
Esc::
F5::
    FinalizeRecording()
return
#If

#If (recorderEvents.MaxIndex() != "" && !recorderActive)
F12::ToggleRecorderPlayback()
#If

#If (!recorderActive && !recorderPlaying && recorderEvents.MaxIndex() != "")
Esc::ClearRecorder()
#If

ToggleRecorderPlayback()
{
    global recorderPlaying
    if (recorderPlaying)
        StopPlayback()
    else
        StartPlayback()
}

MenuTimeout:
    CloseMenu("timeout")
return

CloseMenu(reason := "", skipReload := false)
{
    global menuActive
    SetTimer, MenuTimeout, Off
    ToolTip
    menuActive := false
    if (reason = "timeout")
    {
        ToolTip, Timed Out
        SetTimer, HideTempTip, -3000
    }
    ; Reload script after menu closes unless explicitly skipped (e.g., controller combo triggers)
    if (!skipReload)
        SetTimer, DelayedReload, -100
}

DelayedReload:
    Reload
return


ControllerComboPoll:
    global controllerComboLatched, controllerStartLatched, controllerBackLatched, controllerCancelLatched
    global controllerTurboLatched, controllerPureHoldLatched
    global recorderActive, recorderPlaying, menuActive, recorderEvents
    global XINPUT_GAMEPAD_START, XINPUT_GAMEPAD_BACK
    comboState := ControllerGetState()
    if (!comboState)
    {
        controllerComboLatched := false
        controllerStartLatched := false
        controllerBackLatched := false
        controllerCancelLatched := false
        controllerTurboLatched := false
        controllerPureHoldLatched := false
        return
    }
    if (IsControllerCancelComboPressed(comboState))
    {
        if (!controllerCancelLatched)
        {
            controllerCancelLatched := true
            if (recorderActive)
            {
                recorderSuppressStopTip := true
                FinalizeRecording()
                ShowMacroToggledTip("Recording stopped - F12 toggles playback", 1500, false)
            }
            else
            {
                DeactivateSlashMacro(true)
                DeactivateHoldMacro(true)
                DeactivatePureHold(true)
                DeactivateAutoclicker(true)
                StopPlayback(true)
                StopRecorder(true)
                ClearRecorder()  ; Also clear any recorded macro data
                if (menuActive)
                    CloseMenu("", true)  ; Skip reload for controller combo
                ShowMacroToggledTip("All macros stopped and cleared", 1500, false)
            }
        }
        return
    }
    controllerCancelLatched := false
    if (recorderActive && IsControllerBackPressed(comboState))
    {
        if (!controllerBackLatched)
        {
            controllerBackLatched := true
            FinalizeRecording()
        }
        return
    }
    controllerBackLatched := false
    if (IsControllerTurboComboPressed(comboState))
    {
        if (!controllerTurboLatched)
        {
            controllerTurboLatched := true
            ToolTip, DEBUG: Turbo combo detected! Starting turbo keyhold setup...
            SetTimer, HideTempTip, -2000
            if (menuActive)
                CloseMenu("", true)  ; Skip reload for controller combo
            if (!recorderActive && !recorderPlaying)
                StartHoldMacroSetup()
        }
        return
    }
    controllerTurboLatched := false
    if (IsControllerPureHoldComboPressed(comboState))
    {
        if (!controllerPureHoldLatched)
        {
            controllerPureHoldLatched := true
            ToolTip, DEBUG: Pure hold combo detected! Starting pure keyhold setup...
            SetTimer, HideTempTip, -2000
            if (menuActive)
                CloseMenu("", true)  ; Skip reload for controller combo
            if (!recorderActive && !recorderPlaying)
                StartPureHoldSetup()
        }
        return
    }
    controllerPureHoldLatched := false
    ; L1+L2+R1+R2+A: Start/Stop recording (like F5/F6 for keyboard)
    if (IsControllerComboPressed(comboState))
    {
        if (!controllerComboLatched)
        {
            controllerComboLatched := true
            if (recorderActive)
            {
                ; Stop recording (like pressing F5/F6 during recording)
                FinalizeRecording()
                return
            }
            if (recorderPlaying)
            {
                ; Stop playback if playing (like pressing F12 during playback)
                StopPlayback()
                return
            }
            if (menuActive)
                CloseMenu("", true)  ; Skip reload for controller combo
            ; Start controller recording with suppression
            StartRecorder("controller", true)  ; true = suppress combo input
        }
    }
    else
    {
        controllerComboLatched := false
    }

    ; Start button: Toggle playback (like F12 for keyboard)
    if (!recorderActive && (comboState.Buttons & XINPUT_GAMEPAD_START))
    {
        if (!controllerStartLatched)
        {
            controllerStartLatched := true
            if (recorderPlaying)
            {
                ; Pause/Resume playback (like pressing Start during playback)
                TogglePlaybackPause()
            }
            else if (recorderEvents.MaxIndex() != "")
            {
                ; Start playback (like pressing F12 with recorded macro)
                ToggleRecorderPlayback()
            }
        }
    }
    else
    {
        controllerStartLatched := false
    }
return

ControllerInputBoxHelper:
    ; Check if an InputBox or MsgBox is active
    if (WinExist("ahk_class #32770"))  ; Standard Windows dialog
    {
        global XINPUT_GAMEPAD_A, controllerInputBoxALatched
        ctrlState := ControllerGetState()
        if (ctrlState && (ctrlState.Buttons & XINPUT_GAMEPAD_A))
        {
            if (!controllerInputBoxALatched)
            {
                controllerInputBoxALatched := true
                ; Send Enter to confirm the dialog
                ControlSend,, {Enter}, ahk_class #32770
            }
        }
        else
        {
            controllerInputBoxALatched := false
        }
    }
return

ActivateSlashMacro()
{
    global slashMacroOn
    if (slashMacroOn)
        return
    slashMacroOn := true
    ShowMacroToggledTip("Macro Toggled - Slash => Left click")
}

DeactivateSlashMacro(silent := false)
{
    global slashMacroOn
    if (!slashMacroOn)
        return
    slashMacroOn := false
    if (!silent)
        ShowMacroToggledTip("Macro Toggled Off")
}

ShowMacroToggledTip(text := "Macro Toggled", durationMs := 3000, earlyHide := true)
{
    global macroTipVisible, macroTipIdleBaseline, macroTipEarlyHide, sendMode
    if InStr(text, "Macro Toggled Off")
        text := "Macro Toggled Off (SendMode: " sendMode ") - Esc to exit"
    else
        text := text " (SendMode: " sendMode ")"
    macroTipVisible := true
    macroTipEarlyHide := earlyHide
    macroTipIdleBaseline := earlyHide ? (A_TimeIdlePhysical + 1) : 0
    ToolTip, %text%
    SetTimer, HideMacroTipTimeout, % -durationMs
    if (earlyHide)
        SetTimer, HideMacroTipOnInput, 50
    else
        SetTimer, HideMacroTipOnInput, Off
}

HideMacroTipTimeout:
    HideMacroTip()
return

HideMacroTipOnInput:
    global macroTipVisible, macroTipIdleBaseline, macroTipEarlyHide
    if (!macroTipVisible || !macroTipEarlyHide)
        return
    if (A_TimeIdlePhysical < macroTipIdleBaseline)
        HideMacroTip()
return

HideMacroTip()
{
    global macroTipVisible
    if (!macroTipVisible)
        return
    macroTipVisible := false
    SetTimer, HideMacroTipTimeout, Off
    SetTimer, HideMacroTipOnInput, Off
    ToolTip
}

ClearMacroTips()
{
    global macroTipVisible
    macroTipVisible := false
    SetTimer, HideMacroTipTimeout, Off
    SetTimer, HideMacroTipOnInput, Off
    ToolTip
}

ShowHotkeyHelp()
{
    global sendMode
    ctrlSupport := ControllerSupportAvailable()
    text := "Macros Script Hotkeys`n"
        . "======================`n"
        . "Ctrl+Shift+Alt+Z - Open macro menu`n"
        . "Ctrl+Alt+P - Toggle SendMode (" sendMode ")`n"
        . "Ctrl+Esc - Reload script`n"
        . "Ctrl+Alt+T - Show this help`n"
        . "`n"
        . "Menu Options (F1-F5):`n"
        . "F1 - Slash key => Left click`n"
        . "F2 - Autoclicker (configurable interval)`n"
        . "F3 - Turbo keyhold (rapid repeat)`n"
        . "F4 - Pure key hold (toggle down/up)`n"
        . "F5 - Record macro`n"
        . "`n"
        . "Recording/Playback:`n"
        . "F5 - Start/stop recording`n"
        . "F12 - Toggle playback`n"
        . "Esc - Cancel/stop current mode`n"
    if (ctrlSupport)
    {
        text .= "`n"
            . "Controller Combos:`n"
            . "L1+L2+R1+R2+A - Start/stop recording`n"
            . "L1+L2+R1+R2+B - Turbo keyhold setup`n"
            . "L1+L2+R1+R2+Y - Pure key hold setup`n"
            . "L1+L2+R1+R2+X - Kill switch (stop all)`n"
            . "Start - Toggle/pause playback`n"
            . "Back - Cancel recording`n"
    }
    ToolTip, %text%
    SetTimer, HideHotkeyHelp, -15000
}

HideHotkeyHelp:
    ToolTip
return

MenuTooltipText()
{
    global sendMode
    ctrlSupport := ControllerSupportAvailable()
    text := "F1 - Stage left click with ""/"" key`n"
        . "F2 - Stage Autoclicker`n"
        . "F3 - Stage turbo keyhold`n"
        . "F4 - Stage pure key hold`n"
    if (ctrlSupport)
    {
        text .= "F5 - Record Macro (kb/mouse + controller)`n"
            . "L1+L2+R1+R2+A - Controller record/stop`n"
            . "L1+L2+R1+R2+B - Start turbo keyhold`n"
            . "L1+L2+R1+R2+Y - Start pure key hold`n"
            . "L1+L2+R1+R2+X - Kill switch (stop & clear all macros)`n"
            . "Start/Options - Toggle playback/pause`n"
            . "Share/Back - Cancel recording`n"
            . "Controller map: L1/LB=Left Shoulder, L2/LT=Left Trigger`n"
            . "R1/RB=Right Shoulder, R2/RT=Right Trigger`n"
            . "A/Cross, B/Circle, X/Square, Y/Triangle, Start/Options, Back/Share`n"
    }
    else
    {
        text .= "F5 - Record Macro (kb/mouse)`n"
        if (!VJoyAvailable())
            text .= "vJoy driver not installed, limited to keyboard/mouse recording/playback`n"
                . "Install vJoy: run vJoySetup.exe, then reboot`n"
        if (!EnsureXInputReady())
            text .= "XInput unavailable; controller input disabled`n"
                . "Install DirectX or copy xinput1_3/xinput1_4.dll`n"
    }
    text .= "^!P - Toggle send mode (" sendMode ")"
    return text
}

StartAutoclickerSetup()
{
    global autoClickInterval, autoClickReady, autoClickOn
    tooltipText := "Type click frequency in ms and press Enter (10s timeout)."
    ToolTip, %tooltipText%
    SetTimer, HideTempTip, -10000
    InputBox, newInterval, Autoclicker, % "Enter click interval in ms (e.g., 100).", , , , , , , 10
    SetTimer, HideTempTip, Off
    ToolTip
    if (ErrorLevel)
    {
        ShowMacroToggledTip("Autoclicker canceled")
        return
    }
    if newInterval is not integer
    {
        ShowMacroToggledTip("Autoclicker canceled (invalid number)")
        return
    }
    if (newInterval < 10)
        newInterval := 10
    else if (newInterval > 10000)
        newInterval := 10000
    autoClickInterval := newInterval
    autoClickOn := false
    autoClickReady := true
    ShowMacroToggledTip("Macro ready - / toggles autoclicker (" autoClickInterval " ms)")
}

ActivateAutoclicker()
{
    global autoClickOn, autoClickInterval
    if (autoClickOn)
        return
    autoClickOn := true
    SetTimer, AutoClickTick, %autoClickInterval%
    ShowMacroToggledTip("Macro Toggled - Autoclicker " autoClickInterval " ms")
}

ToggleAutoclicker()
{
    global autoClickOn
    if (autoClickOn)
    {
        StopAutoclickerKeepReady()
    }
    else
    {
        ActivateAutoclicker()
    }
}

StopAutoclickerKeepReady()
{
    global autoClickOn
    if (!autoClickOn)
        return
    autoClickOn := false
    SetTimer, AutoClickTick, Off
    ShowMacroToggledTip("Macro Toggled Off")
}

DeactivateAutoclicker(silent := false)
{
    global autoClickOn, autoClickReady
    if (!autoClickOn && !autoClickReady)
        return
    autoClickOn := false
    autoClickReady := false
    SetTimer, AutoClickTick, Off
    if (!silent)
        ShowMacroToggledTip("Macro Toggled Off")
}

AutoClickTick:
    MouseClick, Left
return

HideTempTip:
    ToolTip
return

; Global to pass XInput button constant from PromptHoldKey to caller
promptHoldKeyXInputButton := 0
promptHoldKeyIsController := false

PromptHoldKey(promptText)
{
    global XINPUT_GAMEPAD_A, XINPUT_GAMEPAD_B, XINPUT_GAMEPAD_X, XINPUT_GAMEPAD_Y
    global XINPUT_GAMEPAD_LEFT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER
    global XINPUT_GAMEPAD_DPAD_UP, XINPUT_GAMEPAD_DPAD_DOWN, XINPUT_GAMEPAD_DPAD_LEFT, XINPUT_GAMEPAD_DPAD_RIGHT
    global promptHoldKeyXInputButton, promptHoldKeyIsController

    ; Reset globals
    promptHoldKeyXInputButton := 0
    promptHoldKeyIsController := false

    ; Wait for user to release any held controller buttons before accepting input
    ; This prevents the combo buttons (L1+L2+R1+R2) from being detected as the key to hold
    releaseStartTime := A_TickCount
    ToolTip, Release all controller buttons...
    Loop
    {
        ctrlState := ControllerGetState()
        if (!ctrlState || ctrlState.Buttons = 0)
            break
        if (A_TickCount - releaseStartTime > 5000)  ; 5s timeout for release
        {
            ToolTip
            return ""
        }
        Sleep, 50
    }

    ToolTip, %promptText%`n(Controller buttons also supported)
    SetTimer, HideTempTip, -15000

    ; Start keyboard input hook
    ih := InputHook("L1 T15 V")
    ih.Start()

    ; Also monitor controller input
    startTime := A_TickCount
    controllerDetected := false
    detectedButton := ""
    detectedXInputButton := 0

    ; Poll for both keyboard and controller input
    Loop
    {
        ; Check if keyboard input received
        if (ih.EndReason != "")
        {
            ih.Stop()
            holdKey := ih.Input
            if (holdKey = "")
                holdKey := ih.EndKey
            holdKey := GetKeyName(holdKey)
            break
        }

        ; Check controller input
        ctrlState := ControllerGetState()
        if (ctrlState && ctrlState.Buttons != 0)
        {
            ; Map controller buttons to names AND store XInput constant
            if (ctrlState.Buttons & XINPUT_GAMEPAD_A)
            {
                detectedButton := "A (Cross)"
                detectedXInputButton := XINPUT_GAMEPAD_A
            }
            else if (ctrlState.Buttons & XINPUT_GAMEPAD_B)
            {
                detectedButton := "B (Circle)"
                detectedXInputButton := XINPUT_GAMEPAD_B
            }
            else if (ctrlState.Buttons & XINPUT_GAMEPAD_X)
            {
                detectedButton := "X (Square)"
                detectedXInputButton := XINPUT_GAMEPAD_X
            }
            else if (ctrlState.Buttons & XINPUT_GAMEPAD_Y)
            {
                detectedButton := "Y (Triangle)"
                detectedXInputButton := XINPUT_GAMEPAD_Y
            }
            else if (ctrlState.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER)
            {
                detectedButton := "LB (L1)"
                detectedXInputButton := XINPUT_GAMEPAD_LEFT_SHOULDER
            }
            else if (ctrlState.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER)
            {
                detectedButton := "RB (R1)"
                detectedXInputButton := XINPUT_GAMEPAD_RIGHT_SHOULDER
            }
            else if (ctrlState.Buttons & XINPUT_GAMEPAD_DPAD_UP)
            {
                detectedButton := "D-Pad Up"
                detectedXInputButton := XINPUT_GAMEPAD_DPAD_UP
            }
            else if (ctrlState.Buttons & XINPUT_GAMEPAD_DPAD_DOWN)
            {
                detectedButton := "D-Pad Down"
                detectedXInputButton := XINPUT_GAMEPAD_DPAD_DOWN
            }
            else if (ctrlState.Buttons & XINPUT_GAMEPAD_DPAD_LEFT)
            {
                detectedButton := "D-Pad Left"
                detectedXInputButton := XINPUT_GAMEPAD_DPAD_LEFT
            }
            else if (ctrlState.Buttons & XINPUT_GAMEPAD_DPAD_RIGHT)
            {
                detectedButton := "D-Pad Right"
                detectedXInputButton := XINPUT_GAMEPAD_DPAD_RIGHT
            }

            if (detectedButton != "")
            {
                ih.Stop()
                holdKey := detectedButton
                promptHoldKeyXInputButton := detectedXInputButton
                promptHoldKeyIsController := true
                controllerDetected := true
                ToolTip, Controller button detected: %holdKey%
                Sleep, 1000
                break
            }
        }

        ; Check timeout
        if (A_TickCount - startTime > 15000)
        {
            ih.Stop()
            holdKey := ""
            break
        }

        Sleep, 50
    }

    SetTimer, HideTempTip, Off
    ToolTip
    return holdKey
}

#If (holdMacroReady)
Esc::
F3::
    DeactivateHoldMacro()
return
#If

#If (holdHoldReady)
Esc::
F4::
    DeactivatePureHold()
return
#If

#If (recorderPlaying)
F12::
    StopPlayback()
return

F5::
Esc::
    StopRecorder()
return
#If

StartHoldMacroSetup()
{
    global holdMacroReady, holdMacroOn, holdMacroKey, holdMacroBoundKey, holdMacroRepeatMs
    global holdMacroIsController, holdMacroControllerButton, holdMacroControllerLatched
    global promptHoldKeyXInputButton, promptHoldKeyIsController
    ; reset any existing hold macro
    DeactivateHoldMacro(true)
    InputBox, repeatMs, Turbo Hold, % "Enter repeat interval in ms (default " holdMacroRepeatMs ").", , , , , , , 10, %holdMacroRepeatMs%
    if (!ErrorLevel && repeatMs != "")
    {
        if repeatMs is integer
        {
            if (repeatMs < 10)
                repeatMs := 10
            else if (repeatMs > 10000)
                repeatMs := 10000
            holdMacroRepeatMs := repeatMs
        }
    }
    tooltipText := "Input key to turbo (15s timeout)."
    holdKey := PromptHoldKey(tooltipText)
    if (holdKey = "")
    {
        ShowMacroToggledTip("Turbo canceled (invalid key)")
        return
    }
    holdMacroKey := holdKey
    holdMacroIsController := promptHoldKeyIsController
    holdMacroControllerButton := promptHoldKeyXInputButton
    holdMacroControllerLatched := false

    if (holdMacroIsController)
    {
        ; For controller buttons, use XInput polling instead of AHK hotkey
        SetTimer, HoldMacroControllerPoll, 50
        holdMacroReady := true
        holdMacroOn := false
        ShowMacroToggledTip("Turbo ready: " holdKey " (press again to toggle)")
    }
    else
    {
        ; For keyboard keys, use standard hotkey binding
        BindHoldHotkey(holdMacroKey, "On")
        holdMacroReady := true
        holdMacroOn := false
        Gosub, HoldMacroToggle  ; first press activates hold
    }
}

BindHoldHotkey(key, mode := "On")
{
    global holdMacroBoundKey
    if (holdMacroBoundKey != "")
        Hotkey, *%holdMacroBoundKey%, Off
    if (key = "")
    {
        holdMacroBoundKey := ""
        return
    }
    holdMacroBoundKey := key
    Hotkey, *%key%, HoldMacroToggle, %mode%
}

HoldMacroToggle:
    global holdMacroReady, holdMacroOn, holdMacroKey, holdMacroRepeatMs, holdMacroIsController
    if (!holdMacroReady || holdMacroKey = "")
        return
    if (holdMacroOn)
    {
        if (!holdMacroIsController)
            Send, {%holdMacroKey% up}
        holdMacroOn := false
        SetTimer, HoldKeyRepeat, Off
        ShowMacroToggledTip("Turbo OFF: " holdMacroKey, 1000, false)
    }
    else
    {
        if (!holdMacroIsController)
            Send, {%holdMacroKey% down}
        holdMacroOn := true
        SetTimer, HoldKeyRepeat, % holdMacroRepeatMs
        ShowMacroToggledTip("Turbo ON: " holdMacroKey, 1000, false)
    }
return

; Poll controller for turbo hold toggle (used when bound key is a controller button)
HoldMacroControllerPoll:
    global holdMacroReady, holdMacroControllerButton, holdMacroControllerLatched
    if (!holdMacroReady || holdMacroControllerButton = 0)
        return
    ctrlState := ControllerGetState()
    if (!ctrlState)
        return
    buttonPressed := (ctrlState.Buttons & holdMacroControllerButton) != 0
    if (buttonPressed)
    {
        if (!holdMacroControllerLatched)
        {
            holdMacroControllerLatched := true
            Gosub, HoldMacroToggle
        }
    }
    else
    {
        holdMacroControllerLatched := false
    }
return

DeactivateHoldMacro(silent := false)
{
    global holdMacroReady, holdMacroOn, holdMacroKey, holdMacroBoundKey
    global holdMacroIsController, holdMacroControllerButton, holdMacroControllerLatched
    if (!holdMacroReady && !holdMacroOn)
        return
    if (holdMacroOn && holdMacroKey != "" && !holdMacroIsController)
        Send, {%holdMacroKey% up}
    SetTimer, HoldKeyRepeat, Off
    SetTimer, HoldMacroControllerPoll, Off
    holdMacroOn := false
    holdMacroReady := false
    holdMacroKey := ""
    holdMacroIsController := false
    holdMacroControllerButton := 0
    holdMacroControllerLatched := false
    BindHoldHotkey("", "Off")
    if (!silent)
        ShowMacroToggledTip("Macro Toggled Off")
}

HoldKeyRepeat:
    global holdMacroOn, holdMacroKey
    if (!holdMacroOn || holdMacroKey = "")
        return
    Send, {%holdMacroKey%}
return

StartRecorder(mode := "combined", suppressCombo := false)
{
    global recorderActive, recorderPlaying, recorderEvents, recorderStart, recorderLast, recorderMouseSampleMs
    global recorderControllerSampleMs, recorderKbMouseEnabled, recorderControllerEnabled
    global recorderControllerPrevState, recorderHasControllerEvents, recorderSendMode
    global sendMode, debugControllerSampleCount
    global recorderControllerSuppress, recorderControllerSuppressUntil
    StopRecorder(true)
    recorderActive := true
    recorderPlaying := false
    recorderEvents := []
    recorderHasControllerEvents := false
    recorderStart := A_TickCount
    recorderLast := recorderStart
    recorderSendMode := sendMode
    recorderKbMouseEnabled := (mode = "combined")
    recorderControllerEnabled := true
    recorderControllerPrevState := ""
    debugControllerSampleCount := 0  ; DEBUG: Reset sample counter

    ; Suppress controller input for 500ms if triggered by combo (prevents recording the combo itself)
    if (suppressCombo)
    {
        recorderControllerSuppress := true
        recorderControllerSuppressUntil := A_TickCount + 500
        ToolTip, DEBUG: Controller input suppressed for 500ms (combo grace period)
        SetTimer, HideTempTip, -1500
    }
    else
    {
        recorderControllerSuppress := false
        recorderControllerSuppressUntil := 0
    }

    ; Check XInput and controller state - gracefully degrade if unavailable
    if (!EnsureXInputReady())
    {
        ToolTip, DEBUG: XInput NOT READY! Recording keyboard/mouse only.
        SetTimer, HideTempTip, -3000
        recorderControllerEnabled := false
    }
    else
    {
        testState := ControllerGetState()
        if (!testState)
        {
            ToolTip, DEBUG: NO CONTROLLER DETECTED! Recording keyboard/mouse only.
            SetTimer, HideTempTip, -3000
            recorderControllerEnabled := false
        }
        else
        {
            testButtons := testState.Buttons
            ToolTip, DEBUG: Controller detected! Buttons: %testButtons% - Starting recording...
            SetTimer, HideTempTip, -2000
        }
    }

    if (recorderKbMouseEnabled)
        SetTimer, RecorderSampleMouse, % recorderMouseSampleMs
    else
        SetTimer, RecorderSampleMouse, Off
    SetTimer, RecorderSampleController, % recorderControllerSampleMs
    if (mode = "controller")
        ShowMacroToggledTip("Recording controller... (L1+L2+R1+R2+A to stop)", 3000, true)
    else
        ShowMacroToggledTip("Recording macro... F5 to stop", 3000, true)
    ; install low-level hooks for keys via hotkey prefix below
}

StopRecorder(silent := false)
{
    global recorderActive, recorderPlaying, recorderControllerPrevState
    if (!recorderActive && !recorderPlaying)
        return
    StopPlayback(true)
    recorderActive := false
    recorderPlaying := false
    recorderControllerPrevState := ""
    SetTimer, RecorderSampleMouse, Off
    SetTimer, RecorderSampleController, Off
    if (!silent)
        ShowMacroToggledTip("Macro Toggled Off")
}

StartPlayback()
{
    global recorderEvents, recorderPlaying, recorderHasControllerEvents
    global recorderPaused, recorderPlayIndex
    if (recorderPlaying)
        return
    if (recorderEvents.MaxIndex() = "")
    {
        ShowMacroToggledTip("No recording to play")
        return
    }
    if (recorderHasControllerEvents && !EnsureVJoyReady())
    {
        ; DEBUG: vJoy not ready for controller playback
        ToolTip, DEBUG: vJoy NOT READY! Controller playback requires vJoy driver.`nInstall vJoySetup.exe and reboot.
        SetTimer, HideTempTip, -5000
        return
    }
    recorderPlaying := true
    recorderPaused := false
    recorderPlayIndex := 1
    ; DEBUG: Show what type of events will play
    if (recorderHasControllerEvents)
    {
        ToolTip, DEBUG: Starting playback with CONTROLLER events (vJoy active)
        SetTimer, HideTempTip, -2000
    }
    ShowMacroToggledTip("Playing recorded macro (F12 to stop)")
    SetTimer, RecorderPlayNext, -1
}

StopPlayback(silent := false)
{
    global recorderPlaying, recorderHasControllerEvents
    global recorderPaused, recorderPlayIndex
    if (!recorderPlaying)
        return
    ; Set flag first to signal any running loop to exit
    recorderPlaying := false
    recorderPaused := false
    ; Disable timer before resetting index to prevent race condition
    SetTimer, RecorderPlayNext, Off
    recorderPlayIndex := 1
    if (recorderHasControllerEvents)
        ControllerResetVJoyState()
    if (!silent)
        ShowMacroToggledTip("Macro Toggled Off")
}

TogglePlaybackPause()
{
    global recorderPlaying, recorderPaused
    if (!recorderPlaying)
        return
    if (recorderPaused)
    {
        recorderPaused := false
        ShowMacroToggledTip("Playback resumed", 1000, false)
        SetTimer, RecorderPlayNext, -1
    }
    else
    {
        recorderPaused := true
        ShowMacroToggledTip("Playback paused", 1000, false)
    }
}

ClearRecorder()
{
    global recorderEvents, recorderStart, recorderLast, recorderHasControllerEvents, recorderSendMode
    global recorderKbMouseEnabled, recorderControllerEnabled, recorderControllerSuppress
    global recorderControllerSuppressUntil, recorderControllerPrevState
    global recorderPlayIndex, recorderPaused
    recorderEvents := []
    recorderStart := 0
    recorderLast := 0
    recorderHasControllerEvents := false
    recorderSendMode := ""
    ; Reset all recording/playback state to defaults
    recorderKbMouseEnabled := true
    recorderControllerEnabled := true
    recorderControllerSuppress := false
    recorderControllerSuppressUntil := 0
    recorderControllerPrevState := ""
    recorderPlayIndex := 1
    recorderPaused := false
    ShowMacroToggledTip("Macro Toggled Off")
}

RecorderPlayNext:
    global recorderEvents, recorderPlaying, recorderPaused, recorderPlayIndex
    if (!recorderPlaying)
        return
    maxIndex := recorderEvents.MaxIndex()
    if (maxIndex = "")
        return
    idx := recorderPlayIndex
    while (idx <= maxIndex)
    {
        if (!recorderPlaying)
            return
        if (recorderPaused)
        {
            recorderPlayIndex := idx
            return
        }
        evt := recorderEvents[idx]
        Sleep, % evt.delay
        if (recorderPaused)
        {
            recorderPlayIndex := idx
            return
        }
        if (evt.type = "key")
        {
            SendEventOrInput("{" evt.code " " evt.state "}", evt.state)
        }
        else if (evt.type = "mousebtn")
        {
            ; DEBUG: Show mouse button playback
            evtCode := evt.code
            evtState := evt.state
            ToolTip, DEBUG PLAYBACK: Mouse %evtCode% %evtState%
            SetTimer, HideTempTip, -500
            SendEventOrInput("{" evt.code " " evt.state "}")
        }
        else if (evt.type = "mousemove")
        {
            ; DEBUG: Show mouse movement playback
            evtX := evt.x
            evtY := evt.y
            MouseGetPos, currentX, currentY
            ToolTip, DEBUG PLAYBACK: Moving from (%currentX%`, %currentY%) to (%evtX%`, %evtY%)
            SetTimer, HideTempTip, -300
            ; Use original syntax - force expression mode with %
            MouseMove, % evt.x, % evt.y, 0
        }
        else if (evt.type = "controller")
        {
            ; DEBUG: Show controller playback
            ctrlButtons := evt.state.Buttons
            ToolTip, DEBUG PLAYBACK: Controller buttons: %ctrlButtons%
            SetTimer, HideTempTip, -500
            ControllerApplyStateToVJoy(evt.state)
        }
        idx++
    }
    ; Only reset index and reschedule if still playing (state may have changed during Sleep)
    if (recorderPlaying)
    {
        recorderPlayIndex := 1
        SetTimer, RecorderPlayNext, -1
    }
return

SendEventOrInput(seq, state := "")
{
    ; Use a stable send path for recorder playback to avoid unexpected window drags.
    global recorderSendMode, sendMode
    modeToUse := recorderSendMode != "" ? recorderSendMode : sendMode
    if (modeToUse = "Play")
        SendPlay, %seq%
    else
        SendInput, %seq%
}

ToggleSendMode()
{
    global sendMode, menuActive
    if (sendMode = "Input")
        sendMode := "Play"
    else
        sendMode := "Input"
    ApplySendMode()
    ShowMacroToggledTip("SendMode: " sendMode)
    if (menuActive)
        ToolTip, % MenuTooltipText()
}

ApplySendMode()
{
    global sendMode
    SendMode %sendMode%
    SetKeyDelay, -1, -1
    SetMouseDelay, -1
}

RecorderSampleMouse:
    global recorderActive
    if (!recorderActive)
        return
    MouseGetPos, mx, my
    RecorderAddEvent("mousemove", "", "", mx, my)
return

RecorderSampleController:
    global recorderActive, recorderControllerEnabled, recorderControllerPrevState
    global recorderHasControllerEvents, debugControllerSampleCount
    global recorderControllerSuppress, recorderControllerSuppressUntil
    if (!recorderActive || !recorderControllerEnabled)
        return

    ; DEBUG: Increment sample counter
    debugControllerSampleCount++

    ; Check if we're in suppression period (grace period after combo press)
    if (recorderControllerSuppress && A_TickCount < recorderControllerSuppressUntil)
    {
        ; Still suppressing - don't record
        if (Mod(debugControllerSampleCount, 25) = 0)  ; Every 0.5 seconds
        {
            remaining := Round((recorderControllerSuppressUntil - A_TickCount) / 1000, 1)
            ToolTip, DEBUG: Suppression active (%remaining%s remaining)
        }
        return
    }
    else if (recorderControllerSuppress)
    {
        ; Suppression period ended
        recorderControllerSuppress := false
        ToolTip, DEBUG: Suppression ended - now recording controller input!
        SetTimer, HideTempTip, -1500
    }

    sampleState := ControllerGetState()
    if (!sampleState)
    {
        ; DEBUG: Show that we're not getting controller state
        if (Mod(debugControllerSampleCount, 50) = 0)  ; Every 50 samples (1 second)
            ToolTip, DEBUG: Controller state is EMPTY (sample %debugControllerSampleCount%)
        return
    }

    ; DEBUG: Show we got controller state
    if (Mod(debugControllerSampleCount, 50) = 0)
    {
        sampleButtons := sampleState.Buttons
        ToolTip, DEBUG: Got controller state! Buttons: %sampleButtons% (sample %debugControllerSampleCount%)
    }

    sampleNorm := NormalizeControllerState(sampleState)
    if (recorderControllerPrevState = "")
    {
        recorderControllerPrevState := sampleNorm
        if (!ControllerStateIsNeutral(sampleNorm))
        {
            RecorderAddEvent("controller", "", "", "", "", sampleNorm)
            recorderHasControllerEvents := true
            ToolTip, DEBUG: First controller event recorded!
        }
        return
    }
    if (!ControllerStatesEqual(sampleNorm, recorderControllerPrevState))
    {
        recorderControllerPrevState := sampleNorm
        RecorderAddEvent("controller", "", "", "", "", sampleNorm)
        recorderHasControllerEvents := true
        ToolTip, DEBUG: Controller state change recorded! Total events: %recorderHasControllerEvents%
    }
return

; Global hook for keyboard/mouse while recording
#Include <Recorder_Keys>

FinalizeRecording()
{
    global recorderActive, recorderEvents, recorderSuppressStopTip, recorderHasControllerEvents
    global recorderKbMouseEnabled, recorderControllerEnabled, recorderControllerSuppress
    global recorderControllerSuppressUntil, recorderControllerPrevState
    if (!recorderActive)
        return
    recorderActive := false
    SetTimer, RecorderSampleMouse, Off
    SetTimer, RecorderSampleController, Off
    ; Reset recording state variables to defaults for next session
    recorderKbMouseEnabled := true
    recorderControllerEnabled := true
    recorderControllerSuppress := false
    recorderControllerSuppressUntil := 0
    recorderControllerPrevState := ""

    ; DEBUG: Show recording results and breakdown
    totalEvents := recorderEvents.MaxIndex()
    if (totalEvents = "")
        totalEvents := 0

    ; Count event types
    keyCount := 0
    mouseCount := 0
    mouseMoveCount := 0
    controllerCount := 0
    for idx, evt in recorderEvents
    {
        if (evt.type = "key")
            keyCount++
        else if (evt.type = "mousebtn")
            mouseCount++
        else if (evt.type = "mousemove")
            mouseMoveCount++
        else if (evt.type = "controller")
            controllerCount++
    }

    ToolTip, DEBUG: Recording stopped!`nTotal: %totalEvents% | Keys: %keyCount% | Mouse buttons: %mouseCount% | Mouse moves: %mouseMoveCount% | Controller: %controllerCount%
    SetTimer, HideTempTip, -5000

    if (recorderSuppressStopTip)
    {
        recorderSuppressStopTip := false
        return
    }
    ShowMacroToggledTip("Recording stopped - F12 toggles playback")
}

RecorderAddEvent(type, code := "", state := "", x := "", y := "", payload := "")
{
    global recorderEvents, recorderLast, recorderActive
    ; Guard: Ignore events if recording was stopped (hotkey context may not have refreshed yet)
    if (!recorderActive)
        return
    now := A_TickCount
    delay := now - recorderLast
    recorderLast := now
    recEvt := {}
    recEvt.type := type
    recEvt.delay := delay
    if (type = "key" || type = "mousebtn")
    {
        recEvt.code := code
        recEvt.state := state
    }
    else if (type = "mousemove")
    {
        recEvt.x := x
        recEvt.y := y
    }
    else if (type = "controller")
    {
        recEvt.state := payload
    }
    recorderEvents.Push(recEvt)
}

StartPureHoldSetup()
{
    global holdHoldReady, holdHoldOn, holdHoldKey, holdHoldBoundKey
    global holdHoldIsController, holdHoldControllerButton, holdHoldControllerLatched
    global promptHoldKeyXInputButton, promptHoldKeyIsController
    DeactivatePureHold(true)
    tooltipText := "Input key to hold down (15s timeout)."
    holdKey := PromptHoldKey(tooltipText)
    if (holdKey = "")
    {
        ShowMacroToggledTip("Keyhold canceled (invalid key)")
        return
    }
    holdHoldKey := holdKey
    holdHoldIsController := promptHoldKeyIsController
    holdHoldControllerButton := promptHoldKeyXInputButton
    holdHoldControllerLatched := false

    if (holdHoldIsController)
    {
        ; For controller buttons, use XInput polling instead of AHK hotkey
        SetTimer, PureHoldControllerPoll, 50
        holdHoldReady := true
        holdHoldOn := false
        ShowMacroToggledTip("Pure Hold ready: " holdKey " (press again to toggle)")
    }
    else
    {
        ; For keyboard keys, use standard hotkey binding
        BindPureHoldHotkey(holdHoldKey, "On")
        holdHoldReady := true
        holdHoldOn := false
        Gosub, PureHoldToggle
    }
}

BindPureHoldHotkey(key, mode := "On")
{
    global holdHoldBoundKey
    if (holdHoldBoundKey != "")
        Hotkey, *%holdHoldBoundKey%, Off
    if (key = "")
    {
        holdHoldBoundKey := ""
        return
    }
    holdHoldBoundKey := key
    Hotkey, *%key%, PureHoldToggle, %mode%
}

PureHoldToggle:
    global holdHoldReady, holdHoldOn, holdHoldKey, holdHoldIsController
    if (!holdHoldReady || holdHoldKey = "")
        return
    if (holdHoldOn)
    {
        if (!holdHoldIsController)
            Send, {%holdHoldKey% up}
        holdHoldOn := false
        ShowMacroToggledTip("Hold OFF: " holdHoldKey, 1000, false)
    }
    else
    {
        if (!holdHoldIsController)
            Send, {%holdHoldKey% down}
        holdHoldOn := true
        ShowMacroToggledTip("Hold ON: " holdHoldKey, 1000, false)
    }
return

; Poll controller for pure hold toggle (used when bound key is a controller button)
PureHoldControllerPoll:
    global holdHoldReady, holdHoldControllerButton, holdHoldControllerLatched
    if (!holdHoldReady || holdHoldControllerButton = 0)
        return
    ctrlState := ControllerGetState()
    if (!ctrlState)
        return
    buttonPressed := (ctrlState.Buttons & holdHoldControllerButton) != 0
    if (buttonPressed)
    {
        if (!holdHoldControllerLatched)
        {
            holdHoldControllerLatched := true
            Gosub, PureHoldToggle
        }
    }
    else
    {
        holdHoldControllerLatched := false
    }
return

DeactivatePureHold(silent := false)
{
    global holdHoldReady, holdHoldOn, holdHoldKey, holdHoldBoundKey
    global holdHoldIsController, holdHoldControllerButton, holdHoldControllerLatched
    if (!holdHoldReady && !holdHoldOn)
        return
    if (holdHoldOn && holdHoldKey != "" && !holdHoldIsController)
        Send, {%holdHoldKey% up}
    SetTimer, PureHoldControllerPoll, Off
    holdHoldOn := false
    holdHoldReady := false
    holdHoldKey := ""
    holdHoldIsController := false
    holdHoldControllerButton := 0
    holdHoldControllerLatched := false
    BindPureHoldHotkey("", "Off")
    if (!silent)
        ShowMacroToggledTip("Macro Toggled Off")
}

EnsureXInputReady()
{
    global controllerXInputReady, controllerXInputFailed, _XInput_hm
    if (controllerXInputReady)
        return true
    if (controllerXInputFailed)
        return false
    dlls := GetXInputDllPaths()
    if (!IsObject(dlls) || dlls.MaxIndex() = "")
    {
        ; DEBUG: No DLLs found
        ToolTip, DEBUG: No XInput DLLs found in system!
        SetTimer, HideTempTip, -3000
        controllerXInputFailed := true
        return false
    }

    ; DEBUG: Show which DLLs were found
    dllList := ""
    for idx, dll in dlls
        dllList .= dll "`n"
    ToolTip, DEBUG: Found XInput DLLs:`n%dllList%
    SetTimer, HideTempTip, -3000

    for _, dll in dlls
    {
        if (XInput_Init(dll, true))
        {
            controllerXInputReady := (_XInput_hm != "")
            if (controllerXInputReady)
            {
                ToolTip, DEBUG: Successfully loaded: %dll%
                SetTimer, HideTempTip, -2000
                return true
            }
        }
    }
    ToolTip, DEBUG: Failed to initialize any XInput DLL!
    SetTimer, HideTempTip, -3000
    controllerXInputFailed := true
    return false
}

ControllerGetState()
{
    global controllerUserIndex
    if (!EnsureXInputReady())
        return ""
    padState := XInput_GetState(controllerUserIndex)
    if (padState)
        return padState
    Loop 4
    {
        idx := A_Index - 1
        if (idx = controllerUserIndex)
            continue
        padState := XInput_GetState(idx)
        if (padState)
        {
            controllerUserIndex := idx
            return padState
        }
    }
    return ""
}

NormalizeControllerState(state)
{
    global controllerThumbDeadzone, controllerTriggerDeadzone
    global controllerThumbStep, controllerTriggerStep
    normState := {}
    normState.Buttons := state.Buttons
    normState.LeftTrigger := NormalizeTrigger(state.LeftTrigger, controllerTriggerDeadzone, controllerTriggerStep)
    normState.RightTrigger := NormalizeTrigger(state.RightTrigger, controllerTriggerDeadzone, controllerTriggerStep)
    normState.ThumbLX := NormalizeThumb(state.ThumbLX, controllerThumbDeadzone, controllerThumbStep)
    normState.ThumbLY := NormalizeThumb(state.ThumbLY, controllerThumbDeadzone, controllerThumbStep)
    normState.ThumbRX := NormalizeThumb(state.ThumbRX, controllerThumbDeadzone, controllerThumbStep)
    normState.ThumbRY := NormalizeThumb(state.ThumbRY, controllerThumbDeadzone, controllerThumbStep)
    return normState
}

NormalizeThumb(value, deadzone, step)
{
    if (Abs(value) < deadzone)
        value := 0
    return Round(value / step) * step
}

NormalizeTrigger(value, deadzone, step)
{
    if (value < deadzone)
        value := 0
    return Round(value / step) * step
}

ControllerStatesEqual(a, b)
{
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

ControllerStateIsNeutral(state)
{
    if (!IsObject(state))
        return true
    return (state.Buttons = 0
        && state.LeftTrigger = 0
        && state.RightTrigger = 0
        && state.ThumbLX = 0
        && state.ThumbLY = 0
        && state.ThumbRX = 0
        && state.ThumbRY = 0)
}

IsControllerComboPressed(state)
{
    global XINPUT_GAMEPAD_LEFT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER
    global XINPUT_GAMEPAD_A, controllerComboTriggerThreshold
    return ((state.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_A)
        && (state.LeftTrigger >= controllerComboTriggerThreshold)
        && (state.RightTrigger >= controllerComboTriggerThreshold))
}

IsControllerTurboComboPressed(state)
{
    global XINPUT_GAMEPAD_LEFT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER
    global XINPUT_GAMEPAD_B, controllerComboTriggerThreshold
    return ((state.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_B)
        && (state.LeftTrigger >= controllerComboTriggerThreshold)
        && (state.RightTrigger >= controllerComboTriggerThreshold))
}

IsControllerPureHoldComboPressed(state)
{
    global XINPUT_GAMEPAD_LEFT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER
    global XINPUT_GAMEPAD_Y, controllerComboTriggerThreshold
    return ((state.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_Y)
        && (state.LeftTrigger >= controllerComboTriggerThreshold)
        && (state.RightTrigger >= controllerComboTriggerThreshold))
}

IsControllerCancelComboPressed(state)
{
    global XINPUT_GAMEPAD_LEFT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER
    global XINPUT_GAMEPAD_X
    global XINPUT_KEYSTROKE_KEYDOWN, VK_PAD_X
    global controllerComboTriggerThreshold
    if (!IsObject(state))
        return false
    facePressed := (state.Buttons & XINPUT_GAMEPAD_X)
    if (!facePressed && EnsureXInputReady())
    {
        keystroke := XInput_GetKeystroke()
        if (keystroke && (keystroke.Flags & XINPUT_KEYSTROKE_KEYDOWN))
            facePressed := (keystroke.VirtualKey = VK_PAD_X)
    }
    return ((state.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER)
        && (state.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER)
        && facePressed
        && (state.LeftTrigger >= controllerComboTriggerThreshold)
        && (state.RightTrigger >= controllerComboTriggerThreshold))
}

IsControllerBackPressed(state)
{
    global XINPUT_GAMEPAD_BACK, XINPUT_KEYSTROKE_KEYDOWN, VK_PAD_BACK
    if (IsObject(state) && (state.Buttons & XINPUT_GAMEPAD_BACK))
        return true
    if (EnsureXInputReady())
    {
        keystroke := XInput_GetKeystroke()
        if (keystroke && (keystroke.VirtualKey = VK_PAD_BACK)
            && (keystroke.Flags & XINPUT_KEYSTROKE_KEYDOWN))
            return true
    }
    return false
}

EnsureVJoyReady()
{
    global vJoyDeviceId, vJoyReady, vJoyUseContPov, vJoyPovMode, vJoyAxisMax, vJoyAxisExists
    global vJoyButtonCount
    if (vJoyReady)
        return true
    if (!VJoyRegistryPresent())
    {
        if (!TryLoadVJoyDll())
        {
            ShowMacroToggledTip("vJoy not installed")
            return false
        }
    }
    VJoy_init(vJoyDeviceId)
    if (!VJoy_Ready(vJoyDeviceId))
    {
        ShowMacroToggledTip("vJoy not ready")
        return false
    }
    vJoyReady := true
    vJoyUseContPov := (VJoy_GetContPovNumber(vJoyDeviceId) > 0)
    if (vJoyUseContPov)
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

VJoyRegistryPresent()
{
    install := RegRead64("HKEY_LOCAL_MACHINE"
        , "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{8E31F76F-74C3-47F1-9550-E041EEDC5FBB}_is1"
        , "InstallLocation")
    return (install != "")
}

ControllerSupportAvailable()
{
    return (EnsureXInputReady() && VJoyAvailable())
}

XInputDllAvailable()
{
    dlls := GetXInputDllPaths()
    return (IsObject(dlls) && dlls.MaxIndex() != "")
}

GetXInputDllPaths()
{
    candidates := ["xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll"]
    dirs := []
    if (A_PtrSize = 8)
    {
        dirs.Push(A_WinDir "\System32")
    }
    else
    {
        dirs.Push(A_WinDir "\SysWOW64")
        dirs.Push(A_WinDir "\System32")
    }
    dirs.Push(A_ScriptDir)
    paths := []
    for _, dir in dirs
    {
        for _, dll in candidates
        {
            path := dir "\" dll
            if (FileExist(path))
                paths.Push(path)
        }
    }
    return paths
}

VJoyAvailable()
{
    if (VJoyRegistryPresent())
        return true
    return TryLoadVJoyDll()
}

TryLoadVJoyDll()
{
    global hVJDLL
    if (hVJDLL)
        return true
    pf64 := ""
    if (A_Is64bitOS)
        EnvGet, pf64, ProgramW6432
    bases := []
    if (A_ProgramFiles != "")
        bases.Push(A_ProgramFiles)
    if (pf64 != "" && pf64 != A_ProgramFiles)
        bases.Push(pf64)
    candidates := []
    for index, base in bases
    {
        candidates.Push(base "\\vJoy\\x64\\vJoyInterface.dll")
        candidates.Push(base "\\vJoy\\x86\\vJoyInterface.dll")
        candidates.Push(base "\\vJoy\\vJoyInterface.dll")
    }
    for index, path in candidates
    {
        if (FileExist(path))
        {
            hVJDLL := DllCall("LoadLibrary", "Str", path)
            if (hVJDLL)
                return true
        }
    }
    return false
}

ControllerApplyStateToVJoy(state)
{
    global vJoyDeviceId, vJoyAxisMax, vJoyAxisExists, vJoyPovMode
    global XINPUT_GAMEPAD_A, XINPUT_GAMEPAD_B, XINPUT_GAMEPAD_X, XINPUT_GAMEPAD_Y
    global XINPUT_GAMEPAD_LEFT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER
    global XINPUT_GAMEPAD_BACK, XINPUT_GAMEPAD_START
    global XINPUT_GAMEPAD_LEFT_THUMB, XINPUT_GAMEPAD_RIGHT_THUMB
    if (!EnsureVJoyReady())
        return
    if (vJoyAxisExists.X)
        VJoy_SetAxis_X(MapThumbAxis(state.ThumbLX, vJoyAxisMax.X), vJoyDeviceId)
    if (vJoyAxisExists.Y)
        VJoy_SetAxis_Y(MapThumbAxis(state.ThumbLY, vJoyAxisMax.Y), vJoyDeviceId)
    if (vJoyAxisExists.RX)
        VJoy_SetAxis_RX(MapThumbAxis(state.ThumbRX, vJoyAxisMax.RX), vJoyDeviceId)
    if (vJoyAxisExists.RY)
        VJoy_SetAxis_RY(MapThumbAxis(state.ThumbRY, vJoyAxisMax.RY), vJoyDeviceId)
    if (vJoyAxisExists.Z)
        VJoy_SetAxis_Z(MapTriggerAxis(state.LeftTrigger, vJoyAxisMax.Z), vJoyDeviceId)
    else if (vJoyAxisExists.SL0)
        VJoy_SetAxis_SL0(MapTriggerAxis(state.LeftTrigger, vJoyAxisMax.SL0), vJoyDeviceId)
    if (vJoyAxisExists.RZ)
        VJoy_SetAxis_RZ(MapTriggerAxis(state.RightTrigger, vJoyAxisMax.RZ), vJoyDeviceId)
    else if (vJoyAxisExists.SL1)
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

SetVJoyButton(btnId, pressed)
{
    global vJoyDeviceId, vJoyButtonCount
    if (btnId > vJoyButtonCount)
        return
    VJoy_SetBtn(pressed ? 1 : 0, vJoyDeviceId, btnId)
}

ControllerApplyPov(buttons, mode)
{
    global vJoyDeviceId
    global XINPUT_GAMEPAD_DPAD_UP, XINPUT_GAMEPAD_DPAD_DOWN
    global XINPUT_GAMEPAD_DPAD_LEFT, XINPUT_GAMEPAD_DPAD_RIGHT
    if (mode = "")
        return
    up := (buttons & XINPUT_GAMEPAD_DPAD_UP)
    down := (buttons & XINPUT_GAMEPAD_DPAD_DOWN)
    left := (buttons & XINPUT_GAMEPAD_DPAD_LEFT)
    right := (buttons & XINPUT_GAMEPAD_DPAD_RIGHT)
    if (!up && !down && !left && !right)
    {
        if (mode = "cont")
            VJoy_SetContPov(-1, vJoyDeviceId, 1)
        else
            VJoy_SetDiscPov(-1, vJoyDeviceId, 1)
        return
    }
    if (mode = "cont")
    {
        angle := 0
        if (up && right)
            angle := 4500
        else if (right && down)
            angle := 13500
        else if (down && left)
            angle := 22500
        else if (left && up)
            angle := 31500
        else if (up)
            angle := 0
        else if (right)
            angle := 9000
        else if (down)
            angle := 18000
        else if (left)
            angle := 27000
        VJoy_SetContPov(angle, vJoyDeviceId, 1)
    }
    else
    {
        dir := -1
        if (up)
            dir := 0
        else if (right)
            dir := 1
        else if (down)
            dir := 2
        else if (left)
            dir := 3
        VJoy_SetDiscPov(dir, vJoyDeviceId, 1)
    }
}

MapThumbAxis(value, axisMax)
{
    if (axisMax <= 0)
        return 0
    return Round(((value + 32768) * axisMax) / 65535)
}

MapTriggerAxis(value, axisMax)
{
    if (axisMax <= 0)
        return 0
    return Round((value * axisMax) / 255)
}

ControllerResetVJoyState()
{
    global vJoyDeviceId, vJoyReady
    if (!vJoyReady)
        return
    VJoy_ResetVJD(vJoyDeviceId)
}
