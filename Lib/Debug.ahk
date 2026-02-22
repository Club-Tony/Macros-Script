#Requires AutoHotkey v1
; Debug.ahk - Debug tooltip utilities for Macros.ahk
; Include this library and set DEBUG_ENABLED := true to enable debug tooltips
;
; Usage:
;   #Include <Debug>
;   DEBUG_ENABLED := true  ; Set to false to disable all debug output
;
;   DebugTip("Message here")                    ; Shows tooltip for 2 seconds
;   DebugTip("Message", 5000)                   ; Shows tooltip for 5 seconds
;   DebugTip("XInput initialized", 3000, 1)     ; Uses tooltip #1
;   DebugTipIf(condition, "Only shows if true")
;   DebugLog("Message")                         ; Outputs to stdout (for debugging with console)

global DEBUG_ENABLED := false
global DEBUG_TOOLTIP_NUM := 20  ; Default tooltip number to avoid conflicts with main tooltips

; Show a debug tooltip that auto-hides
; msg: The message to display
; duration: How long to show (ms), default 2000
; tooltipNum: Which tooltip slot to use (1-20), default DEBUG_TOOLTIP_NUM
DebugTip(msg, duration := 2000, tooltipNum := 0)
{
    global DEBUG_ENABLED, DEBUG_TOOLTIP_NUM
    if (!DEBUG_ENABLED)
        return
    if (tooltipNum = 0)
        tooltipNum := DEBUG_TOOLTIP_NUM
    ToolTip, DEBUG: %msg%, , , %tooltipNum%
    SetTimer, DebugTipHide%tooltipNum%, % -duration
}

; Show debug tooltip only if condition is true
DebugTipIf(condition, msg, duration := 2000, tooltipNum := 0)
{
    if (condition)
        DebugTip(msg, duration, tooltipNum)
}

; Log message to stdout (useful when running with console)
DebugLog(msg)
{
    global DEBUG_ENABLED
    if (!DEBUG_ENABLED)
        return
    FileAppend, [DEBUG %A_Now%] %msg%`n, *
}

; Log with timestamp to a file
DebugLogFile(msg, logFile := "")
{
    global DEBUG_ENABLED
    if (!DEBUG_ENABLED)
        return
    if (logFile = "")
        logFile := A_ScriptDir "\debug.log"
    FileAppend, [%A_Now%] %msg%`n, %logFile%
}

; Timer labels for hiding tooltips (slots 1-20)
DebugTipHide1:
    ToolTip, , , , 1
return
DebugTipHide2:
    ToolTip, , , , 2
return
DebugTipHide3:
    ToolTip, , , , 3
return
DebugTipHide4:
    ToolTip, , , , 4
return
DebugTipHide5:
    ToolTip, , , , 5
return
DebugTipHide6:
    ToolTip, , , , 6
return
DebugTipHide7:
    ToolTip, , , , 7
return
DebugTipHide8:
    ToolTip, , , , 8
return
DebugTipHide9:
    ToolTip, , , , 9
return
DebugTipHide10:
    ToolTip, , , , 10
return
DebugTipHide11:
    ToolTip, , , , 11
return
DebugTipHide12:
    ToolTip, , , , 12
return
DebugTipHide13:
    ToolTip, , , , 13
return
DebugTipHide14:
    ToolTip, , , , 14
return
DebugTipHide15:
    ToolTip, , , , 15
return
DebugTipHide16:
    ToolTip, , , , 16
return
DebugTipHide17:
    ToolTip, , , , 17
return
DebugTipHide18:
    ToolTip, , , , 18
return
DebugTipHide19:
    ToolTip, , , , 19
return
DebugTipHide20:
    ToolTip, , , , 20
return
