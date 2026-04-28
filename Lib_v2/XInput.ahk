#Requires AutoHotkey v2.0
; XInput wrapper for Macros_v2.ahk.

global _XInput_hm := 0
global _XInput_GetState := 0
global _XInput_SetState := 0
global _XInput_GetKeystroke := 0
global _XInput_GetCapabilities := 0
global _XInput_GetBatteryInformation := 0

global XUSER_MAX_COUNT := 4
global XUSER_INDEX_ANY := 0x0FF

global ERROR_SUCCESS := 0x000
global ERROR_EMPTY := 0x10D2
global ERROR_DEVICE_NOT_CONNECTED := 0x48F

global XINPUT_GAMEPAD_DPAD_UP := 0x0001
global XINPUT_GAMEPAD_DPAD_DOWN := 0x0002
global XINPUT_GAMEPAD_DPAD_LEFT := 0x0004
global XINPUT_GAMEPAD_DPAD_RIGHT := 0x0008
global XINPUT_GAMEPAD_START := 0x0010
global XINPUT_GAMEPAD_BACK := 0x0020
global XINPUT_GAMEPAD_LEFT_THUMB := 0x0040
global XINPUT_GAMEPAD_RIGHT_THUMB := 0x0080
global XINPUT_GAMEPAD_LEFT_SHOULDER := 0x0100
global XINPUT_GAMEPAD_RIGHT_SHOULDER := 0x0200
global XINPUT_GAMEPAD_A := 0x1000
global XINPUT_GAMEPAD_B := 0x2000
global XINPUT_GAMEPAD_X := 0x4000
global XINPUT_GAMEPAD_Y := 0x8000

global VK_PAD_A := 0x5800
global VK_PAD_B := 0x5801
global VK_PAD_X := 0x5802
global VK_PAD_Y := 0x5803
global VK_PAD_RSHOULDER := 0x5804
global VK_PAD_LSHOULDER := 0x5805
global VK_PAD_LTRIGGER := 0x5806
global VK_PAD_RTRIGGER := 0x5807
global VK_PAD_DPAD_UP := 0x5810
global VK_PAD_DPAD_DOWN := 0x5811
global VK_PAD_DPAD_LEFT := 0x5812
global VK_PAD_DPAD_RIGHT := 0x5813
global VK_PAD_START := 0x5814
global VK_PAD_BACK := 0x5815
global VK_PAD_LTHUMB_PRESS := 0x5816
global VK_PAD_RTHUMB_PRESS := 0x5817

global XINPUT_KEYSTROKE_KEYDOWN := 0x0001
global XINPUT_KEYSTROKE_KEYUP := 0x0002
global XINPUT_KEYSTROKE_REPEAT := 0x0004

global BATTERY_DEVTYPE_GAMEPAD := 0x00
global BATTERY_DEVTYPE_HEADSET := 0x01
global BATTERY_TYPE_DISCONNECTED := 0x00
global BATTERY_TYPE_WIRED := 0x01
global BATTERY_TYPE_ALKALINE := 0x02
global BATTERY_TYPE_NIMH := 0x03
global BATTERY_TYPE_UNKNOWN := 0xFF
global BATTERY_LEVEL_EMPTY := 0x00
global BATTERY_LEVEL_LOW := 0x01
global BATTERY_LEVEL_MEDIUM := 0x02
global BATTERY_LEVEL_FULL := 0x03

XInput_Init(dll := "xinput1_3.dll", silent := false) {
    global _XInput_hm, _XInput_GetState, _XInput_SetState
    global _XInput_GetKeystroke, _XInput_GetCapabilities, _XInput_GetBatteryInformation

    if _XInput_hm
        return true

    _XInput_hm := DllCall("LoadLibrary", "Str", dll, "Ptr")
    if !_XInput_hm {
        if !silent
            MsgBox "Failed to initialize XInput: " dll " not found."
        return false
    }

    _XInput_GetState := DllCall("GetProcAddress", "Ptr", _XInput_hm, "Ptr", 100, "Ptr")
    if !_XInput_GetState
        _XInput_GetState := DllCall("GetProcAddress", "Ptr", _XInput_hm, "AStr", "XInputGetState", "Ptr")
    _XInput_SetState := DllCall("GetProcAddress", "Ptr", _XInput_hm, "AStr", "XInputSetState", "Ptr")
    _XInput_GetKeystroke := DllCall("GetProcAddress", "Ptr", _XInput_hm, "AStr", "XInputGetKeystroke", "Ptr")
    _XInput_GetCapabilities := DllCall("GetProcAddress", "Ptr", _XInput_hm, "AStr", "XInputGetCapabilities", "Ptr")
    _XInput_GetBatteryInformation := DllCall("GetProcAddress", "Ptr", _XInput_hm, "AStr", "XInputGetBatteryInformation", "Ptr")

    if !(_XInput_GetState && _XInput_SetState && _XInput_GetKeystroke && _XInput_GetCapabilities && _XInput_GetBatteryInformation) {
        XInput_Term()
        if !silent
            MsgBox "Failed to initialize XInput: function not found."
        return false
    }

    return true
}

XInput_Term() {
    global _XInput_hm, _XInput_GetState, _XInput_SetState
    global _XInput_GetKeystroke, _XInput_GetCapabilities, _XInput_GetBatteryInformation

    if _XInput_hm {
        DllCall("FreeLibrary", "Ptr", _XInput_hm)
        _XInput_hm := 0
        _XInput_GetState := 0
        _XInput_SetState := 0
        _XInput_GetKeystroke := 0
        _XInput_GetCapabilities := 0
        _XInput_GetBatteryInformation := 0
    }
}

XInput_GetState(userIndex := 0) {
    global _XInput_GetState
    if !_XInput_GetState
        return 0

    xiState := Buffer(16, 0)
    if DllCall(_XInput_GetState, "UInt", userIndex, "Ptr", xiState.Ptr, "UInt")
        return 0

    return {
        UserIndex: userIndex,
        PacketNumber: NumGet(xiState, 0, "UInt"),
        Buttons: NumGet(xiState, 4, "UShort"),
        LeftTrigger: NumGet(xiState, 6, "UChar"),
        RightTrigger: NumGet(xiState, 7, "UChar"),
        ThumbLX: NumGet(xiState, 8, "Short"),
        ThumbLY: NumGet(xiState, 10, "Short"),
        ThumbRX: NumGet(xiState, 12, "Short"),
        ThumbRY: NumGet(xiState, 14, "Short")
    }
}

XInput_GetKeystroke(userIndex := 0x0FF) {
    global _XInput_GetKeystroke
    if !_XInput_GetKeystroke
        return 0

    xiKeystroke := Buffer(8, 0)
    if DllCall(_XInput_GetKeystroke, "UInt", userIndex, "UInt", 0, "Ptr", xiKeystroke.Ptr, "UInt")
        return 0

    return {
        VirtualKey: NumGet(xiKeystroke, 0, "UShort"),
        Flags: NumGet(xiKeystroke, 4, "UShort"),
        UserIndex: NumGet(xiKeystroke, 6, "UChar"),
        HidCode: NumGet(xiKeystroke, 7, "UChar")
    }
}

XInput_SetState(userIndex, leftMotorSpeed, rightMotorSpeed) {
    global _XInput_SetState
    if !_XInput_SetState
        return false

    vibration := Buffer(4, 0)
    NumPut("UShort", leftMotorSpeed, vibration, 0)
    NumPut("UShort", rightMotorSpeed, vibration, 2)
    return DllCall(_XInput_SetState, "UInt", userIndex, "Ptr", vibration.Ptr, "UInt") = 0
}

XInput_GetCapabilities(userIndex := 0, flags := 0) {
    global _XInput_GetCapabilities
    if !_XInput_GetCapabilities
        return 0

    xiCaps := Buffer(20, 0)
    if DllCall(_XInput_GetCapabilities, "UInt", userIndex, "UInt", flags, "Ptr", xiCaps.Ptr, "UInt")
        return 0

    return {
        UserIndex: userIndex,
        Type: NumGet(xiCaps, 0, "UChar"),
        SubType: NumGet(xiCaps, 1, "UChar"),
        Flags: NumGet(xiCaps, 2, "UShort"),
        Buttons: NumGet(xiCaps, 4, "UShort"),
        LeftTrigger: NumGet(xiCaps, 6, "UChar"),
        RightTrigger: NumGet(xiCaps, 7, "UChar"),
        ThumbLX: NumGet(xiCaps, 8, "UShort"),
        ThumbLY: NumGet(xiCaps, 10, "UShort"),
        ThumbRX: NumGet(xiCaps, 12, "UShort"),
        ThumbRY: NumGet(xiCaps, 14, "UShort"),
        LeftMotorSpeed: NumGet(xiCaps, 16, "UShort"),
        RightMotorSpeed: NumGet(xiCaps, 18, "UShort")
    }
}

XInput_GetBatteryInformation(userIndex := 0, devType := 1) {
    global _XInput_GetBatteryInformation
    if !_XInput_GetBatteryInformation
        return 0

    xiBattery := Buffer(8, 0)
    if DllCall(_XInput_GetBatteryInformation, "UInt", userIndex, "UChar", devType, "Ptr", xiBattery.Ptr, "UInt")
        return 0

    return {
        UserIndex: userIndex,
        DevType: devType,
        BatteryType: NumGet(xiBattery, 0, "UChar"),
        BatteryLevel: NumGet(xiBattery, 1, "UChar")
    }
}
