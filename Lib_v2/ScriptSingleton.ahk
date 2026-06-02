; Shared singleton guard for standalone AutoHotkey v2 scripts.
; #SingleInstance is path-scoped, so junction aliases can otherwise double-run
; the same physical script. This uses the resolved file path as a named mutex.

EnsureScriptSingleton(mutexSource := "") {
    static mutexHandle := 0

    if (mutexSource = "")
        mutexSource := ScriptSingletonResolvePath(A_ScriptFullPath)

    mutexName := "Local\AHK_ScriptSingleton_" ScriptSingletonMutexId(mutexSource)
    mutexHandle := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", mutexName, "Ptr")
    if (!mutexHandle || A_LastError = 183) {
        if mutexHandle
            DllCall("CloseHandle", "Ptr", mutexHandle)
        ExitApp()
    }
}

ScriptSingletonResolvePath(filePath) {
    fullPath := ScriptSingletonFullPath(filePath)
    handle := DllCall("CreateFile", "Str", fullPath, "UInt", 0, "UInt", 7, "Ptr", 0, "UInt", 3, "UInt", 0x02000000, "Ptr", 0, "Ptr")
    if (!handle || handle = -1)
        return fullPath

    capacityChars := 32768
    finalPath := Buffer(capacityChars * 2, 0)
    len := DllCall("GetFinalPathNameByHandle", "Ptr", handle, "Ptr", finalPath, "UInt", capacityChars, "UInt", 0, "UInt")
    DllCall("CloseHandle", "Ptr", handle)

    if (len <= 0 || len >= capacityChars)
        return fullPath

    resolved := StrGet(finalPath)
    if (SubStr(resolved, 1, 4) = "\\?\")
        resolved := SubStr(resolved, 5)
    return resolved
}

ScriptSingletonFullPath(filePath) {
    capacityChars := 32768
    fullPath := Buffer(capacityChars * 2, 0)
    len := DllCall("GetFullPathName", "Str", filePath, "UInt", capacityChars, "Ptr", fullPath, "Ptr", 0, "UInt")
    if (len <= 0 || len >= capacityChars)
        return filePath
    return StrGet(fullPath)
}

ScriptSingletonMutexId(text) {
    lowered := StrLower(text)
    clean := RegExReplace(lowered, "[^A-Za-z0-9_.-]", "_")
    if (StrLen(clean) > 220)
        clean := SubStr(clean, 1, 180) "_" ScriptSingletonChecksum(lowered)
    return clean
}

ScriptSingletonChecksum(text) {
    hash := 0
    Loop Parse, text
        hash := Mod((hash * 131) + Ord(A_LoopField), 4294967291)
    return Format("{:08X}", hash)
}
