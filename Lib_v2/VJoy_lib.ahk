#Requires AutoHotkey v2.0
; Minimal vJoyInterface wrapper for Macros_v2.ahk.

global hVJDLL := 0
global VJDev := Map()

global VJD_STAT_OWN := 0
global VJD_STAT_FREE := 1
global VJD_STAT_BUSY := 2
global VJD_STAT_MISS := 3
global VJD_STAT_UNKN := 4

global HID_USAGE_X := 0x30
global HID_USAGE_Y := 0x31
global HID_USAGE_Z := 0x32
global HID_USAGE_RX := 0x33
global HID_USAGE_RY := 0x34
global HID_USAGE_RZ := 0x35
global HID_USAGE_SL0 := 0x36
global HID_USAGE_SL1 := 0x37

VJoy_LoadLibrary() {
    global hVJDLL
    if hVJDLL
        return hVJDLL

    candidates := []
    dllDir := RegRead64("HKEY_LOCAL_MACHINE", "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{8E31F76F-74C3-47F1-9550-E041EEDC5FBB}_is1", A_PtrSize = 8 ? "DllX64Location" : "DllX86Location")
    if (dllDir != "")
        candidates.Push(VJoyJoinPath(dllDir, "vJoyInterface.dll"))

    installDir := RegRead64("HKEY_LOCAL_MACHINE", "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{8E31F76F-74C3-47F1-9550-E041EEDC5FBB}_is1", "InstallLocation")
    if (installDir != "") {
        candidates.Push(VJoyJoinPath(installDir, "x64\vJoyInterface.dll"))
        candidates.Push(VJoyJoinPath(installDir, "x86\vJoyInterface.dll"))
        candidates.Push(VJoyJoinPath(installDir, "vJoyInterface.dll"))
    }

    for base in [A_ProgramFiles, EnvGet("ProgramW6432")] {
        if (base != "") {
            candidates.Push(base "\vJoy\x64\vJoyInterface.dll")
            candidates.Push(base "\vJoy\x86\vJoyInterface.dll")
            candidates.Push(base "\vJoy\vJoyInterface.dll")
        }
    }
    candidates.Push(A_ScriptDir "\vJoyInterface.dll")

    for path in candidates {
        if (path != "" && FileExist(path)) {
            hVJDLL := DllCall("LoadLibrary", "Str", path, "Ptr")
            if hVJDLL
                return hVJDLL
        }
    }
    return 0
}

VJoyJoinPath(dir, file) {
    if (dir = "")
        return file
    return RTrim(dir, "\/") "\" file
}

RegRead64(rootKey, keyName, valueName := "") {
    try return RegRead(rootKey "\" keyName, valueName)
    catch
        return ""
}

VJoy_init(id := 1) {
    global VJDev, VJD_STAT_OWN, VJD_STAT_FREE
    if !VJoy_LoadLibrary()
        return false

    deviceEnabled := DllCall("vJoyInterface\vJoyEnabled", "Int")
    if !deviceEnabled
        return false

    status := DllCall("vJoyInterface\GetVJDStatus", "UInt", id, "Int")
    if (status = VJD_STAT_FREE)
        DllCall("vJoyInterface\AcquireVJD", "UInt", id, "Int")
    else if (status != VJD_STAT_OWN)
        return false

    dev := {
        DeviceID: id,
        DeviceReady: true,
        ContPovNumber: DllCall("vJoyInterface\GetVJDContPovNumber", "UInt", id, "Int"),
        DiscPovNumber: DllCall("vJoyInterface\GetVJDDiscPovNumber", "UInt", id, "Int"),
        NumberOfButtons: DllCall("vJoyInterface\GetVJDButtonNumber", "Int", id, "Int")
    }
    dev.AxisExist_X := VJoy_GetAxisExistRaw(id, HID_USAGE_X)
    dev.AxisExist_Y := VJoy_GetAxisExistRaw(id, HID_USAGE_Y)
    dev.AxisExist_Z := VJoy_GetAxisExistRaw(id, HID_USAGE_Z)
    dev.AxisExist_RX := VJoy_GetAxisExistRaw(id, HID_USAGE_RX)
    dev.AxisExist_RY := VJoy_GetAxisExistRaw(id, HID_USAGE_RY)
    dev.AxisExist_RZ := VJoy_GetAxisExistRaw(id, HID_USAGE_RZ)
    dev.AxisExist_SL0 := VJoy_GetAxisExistRaw(id, HID_USAGE_SL0)
    dev.AxisExist_SL1 := VJoy_GetAxisExistRaw(id, HID_USAGE_SL1)
    dev.AxisMax_X := VJoy_GetAxisMaxRaw(id, HID_USAGE_X)
    dev.AxisMax_Y := VJoy_GetAxisMaxRaw(id, HID_USAGE_Y)
    dev.AxisMax_Z := VJoy_GetAxisMaxRaw(id, HID_USAGE_Z)
    dev.AxisMax_RX := VJoy_GetAxisMaxRaw(id, HID_USAGE_RX)
    dev.AxisMax_RY := VJoy_GetAxisMaxRaw(id, HID_USAGE_RY)
    dev.AxisMax_RZ := VJoy_GetAxisMaxRaw(id, HID_USAGE_RZ)
    dev.AxisMax_SL0 := VJoy_GetAxisMaxRaw(id, HID_USAGE_SL0)
    dev.AxisMax_SL1 := VJoy_GetAxisMaxRaw(id, HID_USAGE_SL1)
    VJDev[id] := dev
    return true
}

VJoy_DeviceErr(id) {
    global VJDev
    return !VJDev.Has(id) || !VJDev[id].DeviceReady
}

VJoy_Ready(id) {
    return !VJoy_DeviceErr(id)
}

VJoy_GetAxisExistRaw(id, usage) {
    return DllCall("vJoyInterface\GetVJDAxisExist", "Int", id, "Int", usage, "Int")
}

VJoy_GetAxisMaxRaw(id, usage) {
    result := 0
    if DllCall("vJoyInterface\GetVJDAxisMax", "Int", id, "Int", usage, "Int*", &result, "Int")
        return result
    return 0
}

VJoy_GetContPovNumber(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? 0 : VJDev[id].ContPovNumber
}

VJoy_GetDiscPovNumber(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? 0 : VJDev[id].DiscPovNumber
}

VJoy_GetVJDButtonNumber(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? 0 : VJDev[id].NumberOfButtons
}

VJoy_GetAxisExist_X(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? false : VJDev[id].AxisExist_X
}

VJoy_GetAxisExist_Y(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? false : VJDev[id].AxisExist_Y
}

VJoy_GetAxisExist_Z(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? false : VJDev[id].AxisExist_Z
}

VJoy_GetAxisExist_RX(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? false : VJDev[id].AxisExist_RX
}

VJoy_GetAxisExist_RY(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? false : VJDev[id].AxisExist_RY
}

VJoy_GetAxisExist_RZ(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? false : VJDev[id].AxisExist_RZ
}

VJoy_GetAxisExist_SL0(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? false : VJDev[id].AxisExist_SL0
}

VJoy_GetAxisExist_SL1(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? false : VJDev[id].AxisExist_SL1
}

VJoy_GetAxisMax_X(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? 0 : VJDev[id].AxisMax_X
}

VJoy_GetAxisMax_Y(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? 0 : VJDev[id].AxisMax_Y
}

VJoy_GetAxisMax_Z(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? 0 : VJDev[id].AxisMax_Z
}

VJoy_GetAxisMax_RX(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? 0 : VJDev[id].AxisMax_RX
}

VJoy_GetAxisMax_RY(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? 0 : VJDev[id].AxisMax_RY
}

VJoy_GetAxisMax_RZ(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? 0 : VJDev[id].AxisMax_RZ
}

VJoy_GetAxisMax_SL0(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? 0 : VJDev[id].AxisMax_SL0
}

VJoy_GetAxisMax_SL1(id) {
    global VJDev
    return VJoy_DeviceErr(id) ? 0 : VJDev[id].AxisMax_SL1
}

VJoy_SetAxis(axisVal, id, usage) {
    if VJoy_DeviceErr(id)
        return false
    return DllCall("vJoyInterface\SetAxis", "Int", axisVal, "UInt", id, "UInt", usage, "Int")
}

VJoy_SetAxis_X(axisVal, id) {
    return VJoy_SetAxis(axisVal, id, HID_USAGE_X)
}

VJoy_SetAxis_Y(axisVal, id) {
    return VJoy_SetAxis(axisVal, id, HID_USAGE_Y)
}

VJoy_SetAxis_Z(axisVal, id) {
    return VJoy_SetAxis(axisVal, id, HID_USAGE_Z)
}

VJoy_SetAxis_RX(axisVal, id) {
    return VJoy_SetAxis(axisVal, id, HID_USAGE_RX)
}

VJoy_SetAxis_RY(axisVal, id) {
    return VJoy_SetAxis(axisVal, id, HID_USAGE_RY)
}

VJoy_SetAxis_RZ(axisVal, id) {
    return VJoy_SetAxis(axisVal, id, HID_USAGE_RZ)
}

VJoy_SetAxis_SL0(axisVal, id) {
    return VJoy_SetAxis(axisVal, id, HID_USAGE_SL0)
}

VJoy_SetAxis_SL1(axisVal, id) {
    return VJoy_SetAxis(axisVal, id, HID_USAGE_SL1)
}

VJoy_SetBtn(sw, id, btnId) {
    if VJoy_DeviceErr(id)
        return false
    return DllCall("vJoyInterface\SetBtn", "Int", sw, "UInt", id, "UChar", btnId, "Int")
}

VJoy_SetDiscPov(value, id, nPov) {
    if VJoy_DeviceErr(id)
        return false
    return DllCall("vJoyInterface\SetDiscPov", "Int", value, "UInt", id, "UChar", nPov, "Int")
}

VJoy_SetContPov(value, id, nPov) {
    if VJoy_DeviceErr(id)
        return false
    return DllCall("vJoyInterface\SetContPov", "Int", value, "UInt", id, "UChar", nPov, "Int")
}

VJoy_ResetVJD(id) {
    if VJoy_DeviceErr(id)
        return false
    return DllCall("vJoyInterface\ResetVJD", "UInt", id, "Int")
}
