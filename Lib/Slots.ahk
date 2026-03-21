; Lib/Slots.ahk -- Named recording slots with .ini persistence + sequencer
; Split-format storage:
;   macros.ini      -- slot metadata (names, counts, dates)
;   macros_events/  -- one .txt per slot (pipe-delimited events, one per line)
;
; Event line format:
;   K|code|state|delay_ms          (key/mousebtn)
;   M|x|y|delay_ms                 (mousemove)
;   C|buttons|lt|rt|lx|ly|rx|ry|delay_ms  (controller state)
;
; ============================================================
; SLOT FUNCTIONS
; ============================================================

; Save current recorderEvents to a named slot.
; Creates/updates macros.ini metadata and macros_events/<name>.txt event data.
SlotSave(slotName, events, coordMode := "screen")
{
    global debugEnabled
    iniPath    := A_ScriptDir "\macros.ini"
    backupPath := A_ScriptDir "\macros.ini.bak"
    eventsDir  := A_ScriptDir "\macros_events"

    ; Sanitize slot name BEFORE computing paths
    slotName := RegExReplace(slotName, "[\\/:*?""<>|]", "_")
    slotName := Trim(slotName)
    if (slotName = "")
        slotName := "untitled"
    eventsPath := eventsDir "\" slotName ".txt"

    ; 1. Backup metadata .ini
    if (FileExist(iniPath))
        FileCopy, %iniPath%, %backupPath%, 1

    ; 2. Write events file
    if (!FileExist(eventsDir))
        FileCreateDir, %eventsDir%
    FileDelete, %eventsPath%
    eventCount := 0
    for _, evt in events
    {
        line := SlotSerializeEvent(evt)
        if (line != "")
        {
            FileAppend, %line%`n, %eventsPath%
            eventCount++
        }
    }

    ; 3. Update metadata in .ini
    ; Register slot name in [Slots] section
    IniRead, existingCount, %iniPath%, Slots, count, 0
    ; Check if slot already registered
    alreadyRegistered := false
    loop % existingCount
    {
        IniRead, existingName, %iniPath%, Slots, slot_%A_Index%, ""
        if (existingName = slotName)
        {
            alreadyRegistered := true
            break
        }
    }
    if (!alreadyRegistered)
    {
        newIndex := existingCount + 1
        IniWrite, %newIndex%, %iniPath%, Slots, count
        IniWrite, %slotName%, %iniPath%, Slots, slot_%newIndex%
    }

    ; Write slot-specific metadata
    IniWrite, %eventCount%, %iniPath%, %slotName%, event_count
    IniWrite, %coordMode%, %iniPath%, %slotName%, coord_mode
    FormatTime, nowStr,, yyyy-MM-dd
    IniWrite, %nowStr%, %iniPath%, %slotName%, recorded

    ; 4. Verify write success (check file exists, not A_LastError which gives false positives)
    if (!FileExist(eventsPath))
    {
        ShowMacroToggledTip("Save failed -- check disk space! Ctrl+Esc to reload", 5000, false)
        return false
    }

    ShowMacroToggledTip("Saved '" slotName "' OK | F12 to play", 3000, false)
    TrayMenuRebuild()
    return true
}

; Load events array from a named slot. Returns array or "" on failure.
SlotLoad(slotName)
{
    global debugEnabled
    iniPath    := A_ScriptDir "\macros.ini"
    eventsPath := A_ScriptDir "\macros_events\" slotName ".txt"

    if (!FileExist(eventsPath))
    {
        if (debugEnabled)
            ShowMacroToggledTip("DEBUG: SlotLoad -- events file missing: " slotName, 2000, false)
        return ""
    }

    FileRead, rawText, %eventsPath%
    if (rawText = "" && A_LastError != 0)
    {
        ShowMacroToggledTip("Failed to read slot '" slotName "'", 2000, false)
        return ""
    }

    events := []
    badLines := 0
    loop, parse, rawText, `n, `r
    {
        line := Trim(A_LoopField)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        evt := SlotDeserializeEvent(line)
        if (IsObject(evt))
            events.Push(evt)
        else
            badLines++
    }

    if (badLines > 0 && debugEnabled)
        ShowMacroToggledTip("DEBUG: SlotLoad skipped " badLines " bad lines in '" slotName "'", 2000, false)

    return events
}

; Delete a named slot from disk and remove from macros.ini index.
SlotDelete(slotName)
{
    iniPath    := A_ScriptDir "\macros.ini"
    eventsPath := A_ScriptDir "\macros_events\" slotName ".txt"

    ; Remove events file
    if (FileExist(eventsPath))
        FileDelete, %eventsPath%

    ; Remove slot metadata section
    IniDelete, %iniPath%, %slotName%

    ; Rebuild slot index (remove from Slots list)
    IniRead, count, %iniPath%, Slots, count, 0
    newIndex := 0
    loop % count
    {
        IniRead, name, %iniPath%, Slots, slot_%A_Index%, ""
        if (name != "" && name != slotName)
        {
            newIndex++
            IniWrite, %name%, %iniPath%, Slots, slot_%newIndex%
        }
    }
    ; Remove leftover entries beyond new count
    loop % count
    {
        if (A_Index > newIndex)
            IniDelete, %iniPath%, Slots, slot_%A_Index%
    }
    IniWrite, %newIndex%, %iniPath%, Slots, count

    TrayMenuRebuild()
}

; Return ordered array of all slot names from macros.ini.
SlotListNames()
{
    iniPath := A_ScriptDir "\macros.ini"
    IniRead, count, %iniPath%, Slots, count, 0
    names := []
    loop % count
    {
        IniRead, name, %iniPath%, Slots, slot_%A_Index%, ""
        if (name != "")
            names.Push(name)
    }
    return names
}

; Prompt user for a slot name at save time. Returns "" on cancel.
SlotPromptName(defaultName := "untitled")
{
    InputBox, slotName, Save Recording, Name this recording:, , 300, 120, , , , , %defaultName%
    if (ErrorLevel)  ; Cancel pressed
        return ""
    slotName := Trim(slotName)
    if (slotName = "")
        slotName := "untitled"
    return slotName
}

; ============================================================
; IMPORT / EXPORT
; ============================================================

; Export all slots to a single .ini file chosen via PowerShell dialog.
SlotExportAll()
{
    names := SlotListNames()
    if (names.MaxIndex() = "" || names.MaxIndex() = 0)
    {
        ShowMacroToggledTip("No slots to export", 2000, false)
        return
    }

    exportPath := SlotPickFileSave("Export Slots", "macros_export.ini")
    if (exportPath = "")
        return

    ; Write header
    FileDelete, %exportPath%
    slotCount := names.MaxIndex()
    FileAppend, [ExportHeader]`nexport_version=1`nslot_count=%slotCount%`n`n, %exportPath%

    ; Write each slot: metadata + events inline
    for _, name in names
    {
        iniPath := A_ScriptDir "\macros.ini"
        IniRead, eventCount, %iniPath%, %name%, event_count, 0
        IniRead, coordMode,  %iniPath%, %name%, coord_mode, screen
        IniRead, recorded,   %iniPath%, %name%, recorded, ""
        FileAppend, [%name%]`n, %exportPath%
        FileAppend, event_count=%eventCount%`n, %exportPath%
        FileAppend, coord_mode=%coordMode%`n, %exportPath%
        FileAppend, recorded=%recorded%`n, %exportPath%

        ; Write events inline under a sub-key
        eventsPath := A_ScriptDir "\macros_events\" name ".txt"
        if (FileExist(eventsPath))
        {
            FileRead, evtData, %eventsPath%
            ; Escape each line as events_N=...
            idx := 0
            loop, parse, evtData, `n, `r
            {
                line := Trim(A_LoopField)
                if (line = "" || SubStr(line, 1, 1) = ";")
                    continue
                idx++
                FileAppend, event_%idx%=%line%`n, %exportPath%
            }
        }
        FileAppend, `n, %exportPath%
    }

    ShowMacroToggledTip("Exported " names.MaxIndex() " slots to file", 2000, false)
}

; Import slots from an exported .ini file chosen via PowerShell dialog.
SlotImportAll()
{
    importPath := SlotPickFileOpen("Import Slots", "*.ini")
    if (importPath = "")
        return

    if (!FileExist(importPath))
    {
        ShowMacroToggledTip("Import file not found", 2000, false)
        return
    }

    ; Read and validate header
    IniRead, exportVer, %importPath%, ExportHeader, export_version, ""
    if (exportVer = "" || exportVer != "1")
    {
        ShowMacroToggledTip("0 macros imported -- invalid file format", 3000, false)
        return
    }

    IniRead, slotCount, %importPath%, ExportHeader, slot_count, 0
    if (slotCount = 0)
    {
        ShowMacroToggledTip("0 macros imported -- file is empty", 2000, false)
        return
    }

    ; Read all section names to find slots
    imported := 0
    skipped  := 0

    ; Parse the file to find section names
    FileRead, rawText, %importPath%
    loop, parse, rawText, `n, `r
    {
        line := Trim(A_LoopField)
        if (!RegExMatch(line, "^\[(.+)\]$", m))
            continue
        sectionName := m1
        if (sectionName = "ExportHeader")
            continue

        ; Read this slot's metadata
        IniRead, eventCount, %importPath%, %sectionName%, event_count, 0
        IniRead, coordMode,  %importPath%, %sectionName%, coord_mode, screen
        IniRead, recorded,   %importPath%, %sectionName%, recorded, ""

        ; Collect event lines
        events := []
        loop % eventCount
        {
            IniRead, evtLine, %importPath%, %sectionName%, event_%A_Index%, ""
            if (evtLine != "")
                events.Push(evtLine)
        }

        ; Handle conflict
        existingNames := SlotListNames()
        nameConflict := false
        for _, existing in existingNames
        {
            if (existing = sectionName)
            {
                nameConflict := true
                break
            }
        }

        finalName := sectionName
        if (nameConflict)
        {
            InputBox, choice, Slot Conflict, '%sectionName%' already exists. Overwrite? (Y/N), , 280, 120, , , , , N
            if (ErrorLevel || choice != "Y")
            {
                ; Rename: try slotname_2, _3, etc.
                i := 2
                loop
                {
                    candidate := sectionName "_" i
                    alreadyExists := false
                    for _, existing in existingNames
                    {
                        if (existing = candidate)
                        {
                            alreadyExists := true
                            break
                        }
                    }
                    if (!alreadyExists)
                    {
                        finalName := candidate
                        break
                    }
                    i++
                }
            }
        }

        ; Write events file
        eventsPath := A_ScriptDir "\macros_events\" finalName ".txt"
        FileDelete, %eventsPath%
        for _, evtLine in events
            FileAppend, %evtLine%`n, %eventsPath%

        ; Register slot
        iniPath := A_ScriptDir "\macros.ini"
        IniRead, existingCount, %iniPath%, Slots, count, 0
        alreadyRegistered := false
        loop % existingCount
        {
            IniRead, nm, %iniPath%, Slots, slot_%A_Index%, ""
            if (nm = finalName)
            {
                alreadyRegistered := true
                break
            }
        }
        if (!alreadyRegistered)
        {
            newIdx := existingCount + 1
            IniWrite, %newIdx%, %iniPath%, Slots, count
            IniWrite, %finalName%, %iniPath%, Slots, slot_%newIdx%
        }
        evtCount := events.MaxIndex()
        if (evtCount = "")
            evtCount := 0
        IniWrite, %evtCount%, %iniPath%, %finalName%, event_count
        IniWrite, %coordMode%, %iniPath%, %finalName%, coord_mode
        IniWrite, %recorded%, %iniPath%, %finalName%, recorded

        imported++
    }

    ShowMacroToggledTip("Imported " imported " macros", 2000, false)
    TrayMenuRebuild()
}

; ============================================================
; FILE PICKER HELPERS (PowerShell OpenFileDialog/SaveFileDialog)
; ============================================================

SlotPickFileOpen(title, filter := "*.ini")
{
    tmpFile := A_Temp "\ms_picker_result.txt"
    FileDelete, %tmpFile%
    script := "Add-Type -AssemblyName System.Windows.Forms; "
            . "$d = New-Object System.Windows.Forms.OpenFileDialog; "
            . "$d.Title = '" title "'; "
            . "$d.Filter = 'INI Files (*.ini)|*.ini|All Files (*.*)|*.*'; "
            . "$d.InitialDirectory = [System.Environment]::GetFolderPath('MyDocuments'); "
            . "if ($d.ShowDialog() -eq 'OK') { [IO.File]::WriteAllText('" tmpFile "', $d.FileName) }"
    RunWait, powershell.exe -NoProfile -Command "%script%",,Hide
    if (FileExist(tmpFile))
    {
        FileRead, result, %tmpFile%
        FileDelete, %tmpFile%
        return Trim(result)
    }
    return ""
}

SlotPickFileSave(title, defaultName := "export.ini")
{
    tmpFile := A_Temp "\ms_picker_result.txt"
    FileDelete, %tmpFile%
    script := "Add-Type -AssemblyName System.Windows.Forms; "
            . "$d = New-Object System.Windows.Forms.SaveFileDialog; "
            . "$d.Title = '" title "'; "
            . "$d.FileName = '" defaultName "'; "
            . "$d.Filter = 'INI Files (*.ini)|*.ini|All Files (*.*)|*.*'; "
            . "$d.InitialDirectory = [System.Environment]::GetFolderPath('MyDocuments'); "
            . "if ($d.ShowDialog() -eq 'OK') { [IO.File]::WriteAllText('" tmpFile "', $d.FileName) }"
    RunWait, powershell.exe -NoProfile -Command "%script%",,Hide
    if (FileExist(tmpFile))
    {
        FileRead, result, %tmpFile%
        FileDelete, %tmpFile%
        return Trim(result)
    }
    return ""
}

; ============================================================
; EVENT SERIALIZATION
; ============================================================

; Convert event object to a pipe-delimited string line.
SlotSerializeEvent(evt)
{
    if (!IsObject(evt))
        return ""
    t := evt.type
    d := evt.delay
    if (d = "")
        d := 0
    if (t = "key" || t = "mousebtn")
        return t "|" evt.code "|" evt.state "|" d
    else if (t = "mousemove")
        return "M|" evt.x "|" evt.y "|" d
    else if (t = "controller")
    {
        s := evt.state
        if (!IsObject(s))
            return ""
        return "C|" s.Buttons "|" s.LeftTrigger "|" s.RightTrigger
             . "|" s.ThumbLX "|" s.ThumbLY "|" s.ThumbRX "|" s.ThumbRY "|" d
    }
    return ""
}

; Parse a pipe-delimited line back into an event object. Returns "" on failure.
SlotDeserializeEvent(line)
{
    parts := StrSplit(line, "|")
    if (parts.MaxIndex() < 2)
        return ""
    t := parts[1]
    if (t = "key" || t = "mousebtn")
    {
        if (parts.MaxIndex() < 4)
            return ""
        evt := {}
        evt.type  := t
        evt.code  := parts[2]
        evt.state := parts[3]
        evt.delay := parts[4] + 0
        return evt
    }
    else if (t = "M")
    {
        if (parts.MaxIndex() < 4)
            return ""
        evt := {}
        evt.type  := "mousemove"
        evt.x     := parts[2] + 0
        evt.y     := parts[3] + 0
        evt.delay := parts[4] + 0
        return evt
    }
    else if (t = "C")
    {
        if (parts.MaxIndex() < 9)
            return ""
        s := {}
        s.Buttons      := parts[2] + 0
        s.LeftTrigger  := parts[3] + 0
        s.RightTrigger := parts[4] + 0
        s.ThumbLX      := parts[5] + 0
        s.ThumbLY      := parts[6] + 0
        s.ThumbRX      := parts[7] + 0
        s.ThumbRY      := parts[8] + 0
        evt := {}
        evt.type  := "controller"
        evt.state := s
        evt.delay := parts[9] + 0
        return evt
    }
    return ""
}

; ============================================================
; SEQUENCER
; ============================================================
; A sequence is a list of steps, each step = {slotName, delayAfter_ms}
; Sequences stored in macros.ini under [Sequences] section.
;
; State (declared global in Macros.ahk):
;   sequence         -- {steps:[], stepIndex:0, playing:false}
;   sequencePlaying  -- thin boolean alias for #If

; Build a sequence interactively via InputBox chain.
; Returns array of {slotName, delayAfter} or "" on cancel.
SequenceBuild()
{
    names := SlotListNames()
    if (names.MaxIndex() = "" || names.MaxIndex() = 0)
    {
        ShowMacroToggledTip("No saved slots -- record and save a slot first", 3000, false)
        return ""
    }

    ; Build slot list string for display
    slotList := ""
    for i, name in names
        slotList .= i ". " name "`n"

    steps := []
    loop
    {
        stepNum := steps.MaxIndex() + 1
        if (stepNum = "")
            stepNum := 1
        InputBox, input, Build Sequence - Step %stepNum%
                , Available slots:`n%slotList%`nEnter slot name (blank = done, Cancel = abort):
                , , 340, 260
        if (ErrorLevel)  ; Cancel
            return ""
        input := Trim(input)
        if (input = "")
            break   ; Done adding steps

        ; Validate slot name
        found := false
        for _, name in names
        {
            if (name = input)
            {
                found := true
                break
            }
        }
        if (!found)
        {
            ShowMacroToggledTip("Slot '" input "' not found", 1500, false)
            continue
        }

        ; Ask for delay after this step
        InputBox, delayStr, Step %stepNum% Delay, Delay after '" input "' (ms, 0 = none):, , 280, 100, , , , , 0
        if (ErrorLevel)
            return ""
        delayMs := delayStr + 0
        if (delayMs < 0)
            delayMs := 0

        step := {}
        step.slotName    := input
        step.delayAfter  := delayMs
        steps.Push(step)
    }

    if (steps.MaxIndex() = "" || steps.MaxIndex() = 0)
    {
        ShowMacroToggledTip("Sequence canceled -- no steps added", 2000, false)
        return ""
    }
    return steps
}

; Save a sequence to macros.ini.
SequenceSave(seqName, steps)
{
    iniPath := A_ScriptDir "\macros.ini"
    ; Register in [Sequences] index
    IniRead, count, %iniPath%, Sequences, count, 0
    alreadyReg := false
    loop % count
    {
        IniRead, nm, %iniPath%, Sequences, seq_%A_Index%, ""
        if (nm = seqName)
        {
            alreadyReg := true
            break
        }
    }
    if (!alreadyReg)
    {
        newIdx := count + 1
        IniWrite, %newIdx%, %iniPath%, Sequences, count
        IniWrite, %seqName%, %iniPath%, Sequences, seq_%newIdx%
    }

    ; Write step data
    stepCount := steps.MaxIndex()
    if (stepCount = "")
        stepCount := 0
    IniWrite, %stepCount%, %iniPath%, seq_%seqName%, step_count
    for i, step in steps
    {
        IniWrite, % step.slotName,   %iniPath%, seq_%seqName%, step_%i%_slot
        IniWrite, % step.delayAfter, %iniPath%, seq_%seqName%, step_%i%_delay
    }
    ShowMacroToggledTip("Sequence '" seqName "' saved", 2000, false)
    TrayMenuRebuild()
}

; Load a sequence's steps from macros.ini. Returns array or "".
SequenceLoad(seqName)
{
    iniPath := A_ScriptDir "\macros.ini"
    IniRead, stepCount, %iniPath%, seq_%seqName%, step_count, 0
    if (stepCount = 0)
        return ""
    steps := []
    loop % stepCount
    {
        IniRead, slotName, %iniPath%, seq_%seqName%, step_%A_Index%_slot, ""
        IniRead, delayMs,  %iniPath%, seq_%seqName%, step_%A_Index%_delay, 0
        if (slotName = "")
            continue
        step := {}
        step.slotName   := slotName
        step.delayAfter := delayMs + 0
        steps.Push(step)
    }
    return steps
}

; Return ordered array of sequence names.
SequenceListNames()
{
    iniPath := A_ScriptDir "\macros.ini"
    IniRead, count, %iniPath%, Sequences, count, 0
    names := []
    loop % count
    {
        IniRead, name, %iniPath%, Sequences, seq_%A_Index%, ""
        if (name != "")
            names.Push(name)
    }
    return names
}

; Start playing a named sequence.
; Uses SetTimer-driven label SequencePlayStep in Macros.ahk.
SequenceStart(seqName)
{
    global sequence, sequencePlaying, debugEnabled
    steps := SequenceLoad(seqName)
    if (!IsObject(steps) || steps.MaxIndex() = "" || steps.MaxIndex() = 0)
    {
        ShowMacroToggledTip("Sequence '" seqName "' is empty or missing", 2000, false)
        return
    }
    sequence := {}
    sequence.steps     := steps
    sequence.stepIndex := 1
    sequence.playing   := true
    sequencePlaying    := true
    SetTimer, SequencePlayStep, -1
}

; Stop the sequence playback.
SequenceStop()
{
    global sequence, sequencePlaying
    SetTimer, SequencePlayStep, Off
    sequence := {}
    sequence.steps     := []
    sequence.stepIndex := 0
    sequence.playing   := false
    sequencePlaying    := false
    StopPlayback()
    ShowMacroToggledTip("Sequence stopped", 1500, false)
}
