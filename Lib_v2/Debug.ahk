#Requires AutoHotkey v2.0
; Debug tooltip and logging utilities for Macros_v2.ahk.

global debugTooltipNum := 20

DebugTip(msg, durationMs := 2000, tooltipNum := 0) {
    global debugEnabled, debugTooltipNum
    if !debugEnabled
        return

    if (tooltipNum = 0)
        tooltipNum := debugTooltipNum

    ToolTip "DEBUG: " msg,,, tooltipNum
    SetTimer () => ToolTip("",,, tooltipNum), -durationMs
}

DebugTipIf(condition, msg, durationMs := 2000, tooltipNum := 0) {
    if condition
        DebugTip(msg, durationMs, tooltipNum)
}

DebugLog(msg) {
    global debugEnabled
    if !debugEnabled
        return

    FileAppend "[DEBUG " A_Now "] " msg "`n", "*"
}

DebugLogFile(msg, logFile := "") {
    global debugEnabled
    if !debugEnabled
        return

    if (logFile = "")
        logFile := A_ScriptDir "\debug.log"

    FileAppend "[" A_Now "] " msg "`n", logFile
}
