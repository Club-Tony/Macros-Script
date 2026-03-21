; Lib_v2/Slots.ahk — Named recording slots with .ini persistence + sequencer (AHK v2)
; Same .ini / macros_events/ format as v1 — data is cross-compatible.
;
; Usage: Create a SlotManager instance:
;   global slots := SlotManager()
;
; ============================================================

class SlotManager {
    ; ── Public state ──
    slotName    := ""
    speed       := 1.0
    loopMode    := "infinite"  ; "infinite" | "fixed" | "untilkey"
    loopUntilKey := ""

    ; ──────────────────────────────────────────────────────────────────────────
    ; SAVE
    ; ──────────────────────────────────────────────────────────────────────────
    Save(slotName, events, coordMode := "screen") {
        iniPath    := A_ScriptDir "\macros.ini"
        backupPath := A_ScriptDir "\macros.ini.bak"
        eventsDir  := A_ScriptDir "\macros_events"
        eventsPath := eventsDir "\" slotName ".txt"

        slotName := RegExReplace(slotName, "[\\/:*?`"<>|]", "_")
        slotName := Trim(slotName)
        if (slotName = "")
            slotName := "untitled"

        ; Backup
        if FileExist(iniPath)
            FileCopy iniPath, backupPath, 1

        ; Write events file
        if !DirExist(eventsDir)
            DirCreate eventsDir
        if FileExist(eventsPath)
            FileDelete eventsPath

        eventCount := 0
        for evt in events {
            line := this.SerializeEvent(evt)
            if (line != "") {
                FileAppend line "`n", eventsPath
                eventCount++
            }
        }

        ; Update metadata
        existingCount := IniRead(iniPath, "Slots", "count", 0)
        alreadyReg := false
        loop existingCount {
            nm := IniRead(iniPath, "Slots", "slot_" A_Index, "")
            if (nm = slotName) {
                alreadyReg := true
                break
            }
        }
        if !alreadyReg {
            newIdx := existingCount + 1
            IniWrite newIdx, iniPath, "Slots", "count"
            IniWrite slotName, iniPath, "Slots", "slot_" newIdx
        }
        IniWrite eventCount, iniPath, slotName, "event_count"
        IniWrite coordMode, iniPath, slotName, "coord_mode"
        IniWrite FormatTime(, "yyyy-MM-dd"), iniPath, slotName, "recorded"

        ShowMacroToggledTip("Saved '" slotName "' ✓ | F12 to play", 3000, false)
        TrayMenuRebuild()
        return true
    }

    ; ──────────────────────────────────────────────────────────────────────────
    ; LOAD
    ; ──────────────────────────────────────────────────────────────────────────
    Load(slotName) {
        eventsPath := A_ScriptDir "\macros_events\" slotName ".txt"
        if !FileExist(eventsPath)
            return ""

        rawText := FileRead(eventsPath)
        events := []
        for line in StrSplit(rawText, "`n", "`r") {
            line := Trim(line)
            if (line = "" || SubStr(line, 1, 1) = ";")
                continue
            evt := this.DeserializeEvent(line)
            if IsObject(evt)
                events.Push(evt)
        }
        return events
    }

    ; ──────────────────────────────────────────────────────────────────────────
    ; LIST
    ; ──────────────────────────────────────────────────────────────────────────
    ListNames() {
        iniPath := A_ScriptDir "\macros.ini"
        count := IniRead(iniPath, "Slots", "count", 0)
        names := []
        loop count {
            nm := IniRead(iniPath, "Slots", "slot_" A_Index, "")
            if (nm != "")
                names.Push(nm)
        }
        return names
    }

    ; ──────────────────────────────────────────────────────────────────────────
    ; DELETE
    ; ──────────────────────────────────────────────────────────────────────────
    Delete(slotName) {
        iniPath    := A_ScriptDir "\macros.ini"
        eventsPath := A_ScriptDir "\macros_events\" slotName ".txt"
        if FileExist(eventsPath)
            FileDelete eventsPath
        IniDelete iniPath, slotName
        count := IniRead(iniPath, "Slots", "count", 0)
        newIdx := 0
        loop count {
            nm := IniRead(iniPath, "Slots", "slot_" A_Index, "")
            if (nm != "" && nm != slotName) {
                newIdx++
                IniWrite nm, iniPath, "Slots", "slot_" newIdx
            }
        }
        loop count {
            if (A_Index > newIdx)
                IniDelete iniPath, "Slots", "slot_" A_Index
        }
        IniWrite newIdx, iniPath, "Slots", "count"
        TrayMenuRebuild()
    }

    ; ──────────────────────────────────────────────────────────────────────────
    ; PROMPT NAME
    ; ──────────────────────────────────────────────────────────────────────────
    PromptName(defaultName := "untitled") {
        result := InputBox("Name this recording:", "Save Recording", "w300 h120", defaultName)
        if (result.Result = "Cancel")
            return ""
        name := Trim(result.Value)
        return (name = "") ? "untitled" : name
    }

    ; ──────────────────────────────────────────────────────────────────────────
    ; IMPORT / EXPORT
    ; ──────────────────────────────────────────────────────────────────────────
    ExportAll() {
        names := this.ListNames()
        if (names.Length = 0) {
            ShowMacroToggledTip("No slots to export", 2000, false)
            return
        }
        exportPath := this.PickFileSave("Export Slots", "macros_export.ini")
        if (exportPath = "")
            return
        if FileExist(exportPath)
            FileDelete exportPath
        FileAppend "[ExportHeader]`nexport_version=1`nslot_count=" names.Length "`n`n", exportPath
        for name in names {
            iniPath   := A_ScriptDir "\macros.ini"
            evtCount  := IniRead(iniPath, name, "event_count", 0)
            coordMode := IniRead(iniPath, name, "coord_mode", "screen")
            recorded  := IniRead(iniPath, name, "recorded", "")
            FileAppend "[" name "]`n", exportPath
            FileAppend "event_count=" evtCount "`n", exportPath
            FileAppend "coord_mode=" coordMode "`n", exportPath
            FileAppend "recorded=" recorded "`n", exportPath
            eventsPath := A_ScriptDir "\macros_events\" name ".txt"
            if FileExist(eventsPath) {
                idx := 0
                for line in StrSplit(FileRead(eventsPath), "`n", "`r") {
                    line := Trim(line)
                    if (line = "" || SubStr(line, 1, 1) = ";")
                        continue
                    idx++
                    FileAppend "event_" idx "=" line "`n", exportPath
                }
            }
            FileAppend "`n", exportPath
        }
        ShowMacroToggledTip("Exported " names.Length " slots", 2000, false)
    }

    ImportAll() {
        importPath := this.PickFileOpen("Import Slots", "*.ini")
        if (importPath = "")
            return
        if !FileExist(importPath) {
            ShowMacroToggledTip("Import file not found", 2000, false)
            return
        }
        ver := IniRead(importPath, "ExportHeader", "export_version", "")
        if (ver != "1") {
            ShowMacroToggledTip("0 macros imported — invalid file format", 3000, false)
            return
        }
        imported := 0
        rawText := FileRead(importPath)
        for line in StrSplit(rawText, "`n", "`r") {
            if !RegExMatch(Trim(line), "^\[(.+)\]$", &m)
                continue
            sec := m[1]
            if (sec = "ExportHeader")
                continue
            evtCount  := IniRead(importPath, sec, "event_count", 0)
            coordMode := IniRead(importPath, sec, "coord_mode", "screen")
            recorded  := IniRead(importPath, sec, "recorded", "")
            events := []
            loop evtCount {
                ln := IniRead(importPath, sec, "event_" A_Index, "")
                if (ln != "")
                    events.Push(ln)
            }
            finalName := sec
            existingNames := this.ListNames()
            for nm in existingNames {
                if (nm = sec) {
                    r := InputBox("'" sec "' already exists. Overwrite? (Y/N)", "Slot Conflict", "w280 h120", "N")
                    if (r.Result = "Cancel" || r.Value != "Y") {
                        i := 2
                        loop {
                            cand := sec "_" i
                            found := false
                            for nm2 in existingNames
                                if (nm2 = cand) { found := true; break }
                            if !found { finalName := cand; break }
                            i++
                        }
                    }
                    break
                }
            }
            eventsPath := A_ScriptDir "\macros_events\" finalName ".txt"
            if FileExist(eventsPath)
                FileDelete eventsPath
            for ln in events
                FileAppend ln "`n", eventsPath
            iniPath := A_ScriptDir "\macros.ini"
            cnt := IniRead(iniPath, "Slots", "count", 0)
            alreg := false
            loop cnt {
                if (IniRead(iniPath, "Slots", "slot_" A_Index, "") = finalName) {
                    alreg := true; break
                }
            }
            if !alreg {
                newIdx := cnt + 1
                IniWrite newIdx, iniPath, "Slots", "count"
                IniWrite finalName, iniPath, "Slots", "slot_" newIdx
            }
            IniWrite events.Length, iniPath, finalName, "event_count"
            IniWrite coordMode, iniPath, finalName, "coord_mode"
            IniWrite recorded, iniPath, finalName, "recorded"
            imported++
        }
        ShowMacroToggledTip("Imported " imported " macros", 2000, false)
        TrayMenuRebuild()
    }

    ; ──────────────────────────────────────────────────────────────────────────
    ; FILE PICKERS
    ; ──────────────────────────────────────────────────────────────────────────
    PickFileOpen(title, filter := "*.ini") {
        tmpFile := A_Temp "\ms_picker_result.txt"
        if FileExist(tmpFile)
            FileDelete tmpFile
        script := "Add-Type -AssemblyName System.Windows.Forms; "
                . "$d = New-Object System.Windows.Forms.OpenFileDialog; "
                . "$d.Title = '" title "'; "
                . "$d.Filter = 'INI Files (*.ini)|*.ini|All Files (*.*)|*.*'; "
                . "if ($d.ShowDialog() -eq 'OK') { [IO.File]::WriteAllText('" tmpFile "', $d.FileName) }"
        RunWait "powershell.exe -NoProfile -Command `"" script "`"",, "Hide"
        if FileExist(tmpFile) {
            result := Trim(FileRead(tmpFile))
            FileDelete tmpFile
            return result
        }
        return ""
    }

    PickFileSave(title, defaultName := "export.ini") {
        tmpFile := A_Temp "\ms_picker_result.txt"
        if FileExist(tmpFile)
            FileDelete tmpFile
        script := "Add-Type -AssemblyName System.Windows.Forms; "
                . "$d = New-Object System.Windows.Forms.SaveFileDialog; "
                . "$d.Title = '" title "'; "
                . "$d.FileName = '" defaultName "'; "
                . "$d.Filter = 'INI Files (*.ini)|*.ini|All Files (*.*)|*.*'; "
                . "if ($d.ShowDialog() -eq 'OK') { [IO.File]::WriteAllText('" tmpFile "', $d.FileName) }"
        RunWait "powershell.exe -NoProfile -Command `"" script "`"",, "Hide"
        if FileExist(tmpFile) {
            result := Trim(FileRead(tmpFile))
            FileDelete tmpFile
            return result
        }
        return ""
    }

    ; ──────────────────────────────────────────────────────────────────────────
    ; SERIALIZATION
    ; ──────────────────────────────────────────────────────────────────────────
    SerializeEvent(evt) {
        if !IsObject(evt)
            return ""
        t := evt.type
        d := evt.HasProp("delay") ? evt.delay : 0
        if (t = "key" || t = "mousebtn")
            return t "|" evt.code "|" evt.state "|" d
        else if (t = "mousemove")
            return "M|" evt.x "|" evt.y "|" d
        else if (t = "controller") {
            s := evt.state
            if !IsObject(s)
                return ""
            return "C|" s.Buttons "|" s.LeftTrigger "|" s.RightTrigger
                 . "|" s.ThumbLX "|" s.ThumbLY "|" s.ThumbRX "|" s.ThumbRY "|" d
        }
        return ""
    }

    DeserializeEvent(line) {
        parts := StrSplit(line, "|")
        if (parts.Length < 2)
            return ""
        t := parts[1]
        if (t = "key" || t = "mousebtn") {
            if (parts.Length < 4)
                return ""
            evt := {type: t, code: parts[2], state: parts[3], delay: Integer(parts[4])}
            return evt
        } else if (t = "M") {
            if (parts.Length < 4)
                return ""
            return {type: "mousemove", x: Integer(parts[2]), y: Integer(parts[3]), delay: Integer(parts[4])}
        } else if (t = "C") {
            if (parts.Length < 9)
                return ""
            s := {Buttons: Integer(parts[2]), LeftTrigger: Integer(parts[3]),
                  RightTrigger: Integer(parts[4]), ThumbLX: Integer(parts[5]),
                  ThumbLY: Integer(parts[6]), ThumbRX: Integer(parts[7]),
                  ThumbRY: Integer(parts[8])}
            return {type: "controller", state: s, delay: Integer(parts[9])}
        }
        return ""
    }
}

; ============================================================
; SEQUENCER (v2)
; ============================================================

class SequenceManager {
    steps     := []
    stepIndex := 0
    playing   := false

    Build() {
        sm := SlotManager()
        names := sm.ListNames()
        if (names.Length = 0) {
            ShowMacroToggledTip("No saved slots — record and save a slot first", 3000, false)
            return ""
        }
        slotList := ""
        for i, name in names
            slotList .= i ". " name "`n"

        steps := []
        loop {
            stepNum := steps.Length + 1
            r := InputBox("Available slots:`n" slotList "`nEnter slot name (blank=done, Cancel=abort):",
                          "Build Sequence - Step " stepNum, "w340 h260")
            if (r.Result = "Cancel")
                return ""
            input := Trim(r.Value)
            if (input = "")
                break
            found := false
            for nm in names
                if (nm = input) { found := true; break }
            if !found {
                ShowMacroToggledTip("Slot '" input "' not found", 1500, false)
                continue
            }
            dr := InputBox("Delay after '" input "' (ms, 0=none):", "Step " stepNum " Delay", "w280 h100", "0")
            if (dr.Result = "Cancel")
                return ""
            delayMs := Max(0, Integer(dr.Value))
            steps.Push({slotName: input, delayAfter: delayMs})
        }
        if (steps.Length = 0) {
            ShowMacroToggledTip("Sequence canceled — no steps added", 2000, false)
            return ""
        }
        return steps
    }

    Save(seqName, steps) {
        iniPath := A_ScriptDir "\macros.ini"
        cnt := IniRead(iniPath, "Sequences", "count", 0)
        alreg := false
        loop cnt {
            if (IniRead(iniPath, "Sequences", "seq_" A_Index, "") = seqName) { alreg := true; break }
        }
        if !alreg {
            IniWrite cnt + 1, iniPath, "Sequences", "count"
            IniWrite seqName, iniPath, "Sequences", "seq_" (cnt + 1)
        }
        IniWrite steps.Length, iniPath, "seq_" seqName, "step_count"
        for i, step in steps {
            IniWrite step.slotName,   iniPath, "seq_" seqName, "step_" i "_slot"
            IniWrite step.delayAfter, iniPath, "seq_" seqName, "step_" i "_delay"
        }
        ShowMacroToggledTip("Sequence '" seqName "' saved", 2000, false)
        TrayMenuRebuild()
    }

    Load(seqName) {
        iniPath := A_ScriptDir "\macros.ini"
        cnt := IniRead(iniPath, "seq_" seqName, "step_count", 0)
        if (cnt = 0)
            return ""
        steps := []
        loop cnt {
            slotName := IniRead(iniPath, "seq_" seqName, "step_" A_Index "_slot", "")
            delayMs  := IniRead(iniPath, "seq_" seqName, "step_" A_Index "_delay", 0)
            if (slotName != "")
                steps.Push({slotName: slotName, delayAfter: Integer(delayMs)})
        }
        return steps
    }

    ListNames() {
        iniPath := A_ScriptDir "\macros.ini"
        cnt := IniRead(iniPath, "Sequences", "count", 0)
        names := []
        loop cnt {
            nm := IniRead(iniPath, "Sequences", "seq_" A_Index, "")
            if (nm != "")
                names.Push(nm)
        }
        return names
    }
}
