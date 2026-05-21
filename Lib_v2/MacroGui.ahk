; Lib_v2/MacroGui.ahk - 4-tab GUI panel for Macros-Script (AHK v2)
;
; Public API:
;   MacroGuiCreate()
;   MacroGuiShow()
;   MacroGuiHide()
;   MacroGuiToggle()
;   MacroGuiRefresh()
;   MacroGuiUpdateStatus()

MacroGuiCreate() {
    global macroGui, macroGuiControls, macroGuiCreated, macroGuiVisible
    if macroGuiCreated
        return

    macroGuiControls := Map()
    g := Gui("+Resize -MaximizeBox", "Macros-Script")
    g.MarginX := 8
    g.MarginY := 8
    g.OnEvent("Close", MacroGuiWindowClose)
    g.OnEvent("Escape", MacroGuiWindowClose)

    tab := g.Add("Tab3", "w520 h430", ["Main", "Slots", "Sequences", "Settings"])
    tab.OnEvent("Change", (*) => MacroGuiRefresh())
    macroGuiControls["tab"] := tab

    tab.UseTab(1)
    macroGuiControls["statusText"] := g.Add("Text", "xm ym+34 w490 h22", "Status: Idle")
    macroGuiControls["btnRecord"] := g.Add("Button", "xm w112 h28", "Record (F5)")
    macroGuiControls["btnPlay"] := g.Add("Button", "x+6 yp w112 h28", "Play (F12)")
    macroGuiControls["btnPause"] := g.Add("Button", "x+6 yp w112 h28", "Pause")
    macroGuiControls["btnStop"] := g.Add("Button", "x+6 yp w112 h28", "Stop")
    macroGuiControls["btnRecord"].OnEvent("Click", MacroGuiRecord)
    macroGuiControls["btnPlay"].OnEvent("Click", MacroGuiPlay)
    macroGuiControls["btnPause"].OnEvent("Click", MacroGuiPause)
    macroGuiControls["btnStop"].OnEvent("Click", MacroGuiStop)

    g.Add("Text", "xm y+16 w80 h22", "Current slot:")
    macroGuiControls["slotDDL"] := g.Add("DropDownList", "x+8 yp-3 w275")
    macroGuiControls["btnLoadSlot"] := g.Add("Button", "x+8 yp w80 h24", "Load")
    macroGuiControls["btnLoadSlot"].OnEvent("Click", MacroGuiLoadSelectedSlot)
    macroGuiControls["eventCount"] := g.Add("Text", "xm y+10 w210 h22", "Events: 0")
    macroGuiControls["controllerFlag"] := g.Add("Text", "x+12 yp w220 h22", "Controller: no")

    g.Add("Text", "xm y+14 w80 h22", "Speed:")
    macroGuiControls["speedDDL"] := g.Add("DropDownList", "x+8 yp-3 w100", ["0.5x", "1x", "2x"])
    macroGuiControls["speedDDL"].OnEvent("Change", MacroGuiSpeedChanged)
    g.Add("Text", "x+24 yp+3 w80 h22", "Loop:")
    macroGuiControls["loopDDL"] := g.Add("DropDownList", "x+8 yp-3 w130", ["Infinite", "Fixed Count", "Until Key"])
    macroGuiControls["loopDDL"].OnEvent("Change", MacroGuiLoopModeChanged)
    g.Add("Text", "xm y+12 w80 h22", "Fixed count:")
    macroGuiControls["fixedCount"] := g.Add("Edit", "x+8 yp-3 w70 Number", "5")
    g.Add("Text", "x+24 yp+3 w70 h22", "Until key:")
    macroGuiControls["untilKey"] := g.Add("Edit", "x+8 yp-3 w90")

    g.Add("Text", "xm y+16 w80 h22", "Profile:")
    macroGuiControls["profileDDL"] := g.Add("DropDownList", "x+8 yp-3 w220")
    macroGuiControls["profileDDL"].OnEvent("Change", MacroGuiProfileChanged)
    macroGuiControls["sendModeText"] := g.Add("Text", "xm y+10 w280 h22", "SendMode: Input")

    tab.UseTab(2)
    macroGuiControls["slotList"] := g.Add("ListView", "xm ym+34 w490 h230 Grid", ["Name", "Events", "Date", "Coords"])
    macroGuiControls["slotList"].OnEvent("DoubleClick", MacroGuiSlotListLoad)
    macroGuiControls["btnSlotLoad"] := g.Add("Button", "xm y+8 w80 h26", "Load")
    macroGuiControls["btnSlotDelete"] := g.Add("Button", "x+6 yp w80 h26", "Delete")
    macroGuiControls["btnSlotRename"] := g.Add("Button", "x+6 yp w80 h26", "Rename")
    macroGuiControls["btnSlotRefresh"] := g.Add("Button", "x+6 yp w80 h26", "Refresh")
    macroGuiControls["btnSlotLoad"].OnEvent("Click", MacroGuiSlotListLoad)
    macroGuiControls["btnSlotDelete"].OnEvent("Click", MacroGuiSlotListDelete)
    macroGuiControls["btnSlotRename"].OnEvent("Click", MacroGuiSlotListRename)
    macroGuiControls["btnSlotRefresh"].OnEvent("Click", (*) => MacroGuiRefresh())
    macroGuiControls["btnExportSlots"] := g.Add("Button", "xm y+10 w100 h26", "Export All")
    macroGuiControls["btnImportSlots"] := g.Add("Button", "x+6 yp w100 h26", "Import")
    macroGuiControls["btnNewRecording"] := g.Add("Button", "x+6 yp w120 h26", "New Recording")
    macroGuiControls["btnExportSlots"].OnEvent("Click", MacroGuiExportSlots)
    macroGuiControls["btnImportSlots"].OnEvent("Click", MacroGuiImportSlots)
    macroGuiControls["btnNewRecording"].OnEvent("Click", MacroGuiRecord)

    tab.UseTab(3)
    macroGuiControls["seqList"] := g.Add("ListView", "xm ym+34 w490 h160 Grid", ["Name", "Steps"])
    macroGuiControls["seqList"].OnEvent("DoubleClick", MacroGuiSeqPlay)
    macroGuiControls["btnSeqPlay"] := g.Add("Button", "xm y+8 w80 h26", "Play")
    macroGuiControls["btnSeqDelete"] := g.Add("Button", "x+6 yp w80 h26", "Delete")
    macroGuiControls["btnSeqBuild"] := g.Add("Button", "x+6 yp w90 h26", "Build New")
    macroGuiControls["btnSeqPreview"] := g.Add("Button", "x+6 yp w80 h26", "Preview")
    macroGuiControls["btnSeqPlay"].OnEvent("Click", MacroGuiSeqPlay)
    macroGuiControls["btnSeqDelete"].OnEvent("Click", MacroGuiSeqDelete)
    macroGuiControls["btnSeqBuild"].OnEvent("Click", MacroGuiSeqBuild)
    macroGuiControls["btnSeqPreview"].OnEvent("Click", MacroGuiSeqPreview)
    macroGuiControls["seqSteps"] := g.Add("ListView", "xm y+10 w490 h125 Grid", ["#", "Slot", "Delay ms"])

    tab.UseTab(4)
    g.Add("Text", "xm ym+34 w90 h22", "Active profile:")
    macroGuiControls["settingsProfileDDL"] := g.Add("DropDownList", "x+8 yp-3 w210")
    macroGuiControls["settingsProfileDDL"].OnEvent("Change", MacroGuiSettingsProfileChanged)
    macroGuiControls["btnAddProfile"] := g.Add("Button", "x+8 yp w70 h24", "Add")
    macroGuiControls["btnDetectProfile"] := g.Add("Button", "x+6 yp w70 h24", "Detect")
    macroGuiControls["btnAddProfile"].OnEvent("Click", MacroGuiAddProfile)
    macroGuiControls["btnDetectProfile"].OnEvent("Click", MacroGuiDetectProfile)
    macroGuiControls["debugCheck"] := g.Add("CheckBox", "xm y+18 w160 h24", "Debug Mode")
    macroGuiControls["debugCheck"].OnEvent("Click", MacroGuiDebugChanged)
    macroGuiControls["xinputStatus"] := g.Add("Text", "xm y+12 w360 h22", "XInput: checking")
    macroGuiControls["vjoyStatus"] := g.Add("Text", "xm y+6 w360 h22", "vJoy: checking")
    macroGuiControls["currentSlotText"] := g.Add("Text", "xm y+16 w430 h22", "Slot: (none)")
    macroGuiControls["currentProfileText"] := g.Add("Text", "xm y+6 w430 h22", "Profile: Default")
    macroGuiControls["btnReload"] := g.Add("Button", "xm y+18 w100 h28", "Reload")
    macroGuiControls["btnExit"] := g.Add("Button", "x+8 yp w100 h28", "Exit")
    macroGuiControls["btnReload"].OnEvent("Click", MacroGuiReload)
    macroGuiControls["btnExit"].OnEvent("Click", MacroGuiExit)

    tab.UseTab()
    macroGuiControls["statusBar"] := g.Add("StatusBar")
    macroGuiControls["statusBar"].SetParts(130)

    macroGui := g
    macroGuiCreated := true
    macroGuiVisible := false
    MacroGuiRefresh()
}

MacroGuiShow(*) {
    global macroGui, macroGuiCreated, macroGuiVisible
    if !macroGuiCreated
        MacroGuiCreate()
    MacroGuiRefresh()
    MacroGuiLoadPosition(&guiX, &guiY)
    if (guiX != "" && guiY != "")
        macroGui.Show("x" guiX " y" guiY " NoActivate")
    else
        macroGui.Show("NoActivate")
    macroGuiVisible := true
    MacroGuiUpdateStatus()
}

MacroGuiHide(*) {
    global macroGui, macroGuiCreated, macroGuiVisible
    if !macroGuiCreated
        return true
    MacroGuiSavePosition()
    macroGui.Hide()
    macroGuiVisible := false
    return true
}

MacroGuiToggle(*) {
    global macroGuiVisible
    if macroGuiVisible
        MacroGuiHide()
    else
        MacroGuiShow()
}

MacroGuiWindowClose(*) {
    return MacroGuiHide()
}

MacroGuiRefresh(*) {
    global macroGuiCreated, macroGuiRefreshing
    if !macroGuiCreated
        return
    macroGuiRefreshing := true
    try {
        MacroGuiRefreshMainTab()
        MacroGuiRefreshSlotList()
        MacroGuiRefreshSequenceList()
        MacroGuiRefreshSettingsTab()
        MacroGuiUpdateStatus()
    } finally {
        macroGuiRefreshing := false
    }
}

MacroGuiRefreshMainTab() {
    global macroGuiControls, slots, recorder, recorderEvents, recorderHasControllerEvents, profile, currentSendMode
    c := macroGuiControls

    slotNames := slots.ListNames()
    c["slotDDL"].Delete()
    if (slotNames.Length = 0) {
        c["slotDDL"].Add(["(none)"])
        c["slotDDL"].Choose(1)
    } else {
        c["slotDDL"].Add(slotNames)
        selected := 1
        for i, name in slotNames {
            if (name = recorder.slotName) {
                selected := i
                break
            }
        }
        c["slotDDL"].Choose(selected)
    }

    c["eventCount"].Text := "Events: " recorderEvents.Length
    c["controllerFlag"].Text := "Controller: " (recorderHasControllerEvents ? "yes" : "no")
    c["speedDDL"].Choose(recorder.speed = 0.5 ? 1 : recorder.speed = 2.0 ? 3 : 2)
    c["loopDDL"].Choose(recorder.loopMode = "fixed" ? 2 : recorder.loopMode = "untilkey" ? 3 : 1)
    c["untilKey"].Text := recorder.loopUntilKey
    MacroGuiLoopModeChanged()

    MacroGuiPopulateProfileDDL(c["profileDDL"])
    c["sendModeText"].Text := "SendMode: " currentSendMode
}

MacroGuiRefreshSlotList() {
    global macroGuiControls, slots
    lv := macroGuiControls["slotList"]
    lv.Delete()
    iniPath := A_ScriptDir "\macros.ini"
    for name in slots.ListNames() {
        evtCount := IniRead(iniPath, name, "event_count", 0)
        recorded := IniRead(iniPath, name, "recorded", "--")
        coordMode := IniRead(iniPath, name, "coord_mode", "screen")
        lv.Add("", name, evtCount, recorded, coordMode)
    }
    lv.ModifyCol(1, 190)
    lv.ModifyCol(2, 70)
    lv.ModifyCol(3, 105)
    lv.ModifyCol(4, 90)
}

MacroGuiRefreshSequenceList() {
    global macroGuiControls
    sm := SequenceManager()
    lv := macroGuiControls["seqList"]
    lv.Delete()
    for name in sm.ListNames() {
        steps := sm.Load(name)
        stepCount := IsObject(steps) ? steps.Length : 0
        lv.Add("", name, stepCount)
    }
    lv.ModifyCol(1, 300)
    lv.ModifyCol(2, 70)
}

MacroGuiRefreshSettingsTab() {
    global macroGuiControls, debugEnabled, controllerXInputReady, vJoyReady, recorder, profile, currentSendMode
    c := macroGuiControls
    MacroGuiPopulateProfileDDL(c["settingsProfileDDL"])
    c["debugCheck"].Value := debugEnabled ? 1 : 0
    c["xinputStatus"].Text := controllerXInputReady ? "XInput: available" : "XInput: unavailable"
    c["vjoyStatus"].Text := vJoyReady ? "vJoy: ready" : (VJoyAvailable() ? "vJoy: installed" : "vJoy: not installed")
    c["currentSlotText"].Text := "Slot: " (recorder.slotName != "" ? recorder.slotName : "(none)")
    c["currentProfileText"].Text := "Profile: " profile.name " (Send" currentSendMode ")"
}

MacroGuiUpdateStatus(*) {
    global macroGuiCreated, macroGuiVisible, macroGuiControls
    global recorderActive, recorderPlaying, recorderPaused, recorderEvents
    global recorderLoopCurrent, recorderLoopTarget, sequencePlaying, profile, currentSendMode
    if (!macroGuiCreated || !macroGuiVisible)
        return

    c := macroGuiControls
    if recorderActive
        statusText := "Status: Recording (" recorderEvents.Length " events)"
    else if (recorderPlaying && recorderPaused)
        statusText := "Status: Paused"
    else if recorderPlaying
        statusText := recorderLoopTarget > 0
            ? "Status: Playing loop " recorderLoopCurrent "/" recorderLoopTarget
            : "Status: Playing"
    else if sequencePlaying
        statusText := "Status: Sequence playing"
    else
        statusText := "Status: Idle"

    c["statusText"].Text := statusText
    c["eventCount"].Text := "Events: " recorderEvents.Length
    c["btnRecord"].Enabled := !recorderActive && !recorderPlaying && !sequencePlaying
    c["btnPlay"].Enabled := !recorderActive && !recorderPlaying && recorderEvents.Length > 0
    c["btnStop"].Enabled := recorderActive || recorderPlaying || sequencePlaying
    c["btnPause"].Enabled := recorderPlaying
    c["btnPause"].Text := recorderPaused ? "Resume" : "Pause"
    c["statusBar"].SetText(recorderActive ? "Recording" : recorderPlaying ? (recorderPaused ? "Paused" : "Playing") : "Idle", 1)
    c["statusBar"].SetText("Profile: " profile.name " (Send" currentSendMode ")", 2)
}

MacroGuiPopulateProfileDDL(ddl) {
    global profile
    names := ["Default"]
    for name in profile.ListNames()
        names.Push(name)
    ddl.Delete()
    ddl.Add(names)
    selected := 1
    for i, name in names {
        if (name = profile.name) {
            selected := i
            break
        }
    }
    ddl.Choose(selected)
}

MacroGuiApplyPlaybackSettings() {
    global macroGuiControls, recorder
    c := macroGuiControls
    speedText := c["speedDDL"].Text
    recorder.speed := speedText = "0.5x" ? 0.5 : speedText = "2x" ? 2.0 : 1.0

    loopText := c["loopDDL"].Text
    if (loopText = "Fixed Count")
        recorder.loopMode := "fixed"
    else if (loopText = "Until Key")
        recorder.loopMode := "untilkey"
    else
        recorder.loopMode := "infinite"
    recorder.loopUntilKey := Trim(c["untilKey"].Text)
}

MacroGuiLoopModeChanged(*) {
    global macroGuiControls, macroGuiRefreshing
    if !macroGuiControls.Has("loopDDL")
        return
    loopText := macroGuiControls["loopDDL"].Text
    macroGuiControls["fixedCount"].Enabled := loopText = "Fixed Count"
    macroGuiControls["untilKey"].Enabled := loopText = "Until Key"
    if !macroGuiRefreshing
        MacroGuiApplyPlaybackSettings()
}

MacroGuiSpeedChanged(*) {
    global macroGuiRefreshing
    if !macroGuiRefreshing {
        MacroGuiApplyPlaybackSettings()
        TrayMenuRebuild()
    }
}

MacroGuiRecord(*) {
    MacroGuiHide()
    StartRecorder()
}

MacroGuiPlay(*) {
    global macroGuiControls, recorder, recorderEvents
    if (recorderEvents.Length = 0) {
        ShowMacroToggledTip("No events loaded - record or load a slot first", 2000, false)
        return
    }
    MacroGuiApplyPlaybackSettings()
    if (recorder.loopMode = "fixed") {
        countText := Trim(macroGuiControls["fixedCount"].Text)
        loopCount := (IsInteger(countText) && Integer(countText) > 0) ? Integer(countText) : 1
        StartPlayback(loopCount)
    } else if (recorder.loopMode = "untilkey") {
        StartPlaybackUntilKey()
    } else {
        StartPlayback(-1)
    }
    TrayMenuRebuild()
    MacroGuiUpdateStatus()
}

MacroGuiPause(*) {
    TogglePlaybackPause()
    MacroGuiUpdateStatus()
}

MacroGuiStop(*) {
    global recorderActive, recorderPlaying, sequencePlaying
    if recorderActive
        FinalizeRecording()
    else if recorderPlaying
        StopPlayback()
    else if sequencePlaying
        SequenceStop()
    MacroGuiRefresh()
}

MacroGuiLoadSelectedSlot(*) {
    global macroGuiControls
    slotName := macroGuiControls["slotDDL"].Text
    if (slotName = "" || slotName = "(none)")
        return
    LoadRecorderSlot(slotName)
    MacroGuiRefresh()
}

MacroGuiSelectedListText(listName, col := 1) {
    global macroGuiControls
    lv := macroGuiControls[listName]
    row := lv.GetNext(0)
    if (row = 0)
        row := lv.GetNext(0, "F")
    return row > 0 ? lv.GetText(row, col) : ""
}

MacroGuiSlotListLoad(*) {
    slotName := MacroGuiSelectedListText("slotList")
    if (slotName = "") {
        ShowMacroToggledTip("Select a slot first", 1500, false)
        return
    }
    LoadRecorderSlot(slotName)
    MacroGuiRefresh()
}

MacroGuiSlotListDelete(*) {
    global slots
    slotName := MacroGuiSelectedListText("slotList")
    if (slotName = "") {
        ShowMacroToggledTip("Select a slot first", 1500, false)
        return
    }
    answer := MsgBox("Delete slot '" slotName "'? This cannot be undone.", "Delete Slot", "YesNo")
    if (answer != "Yes")
        return
    slots.Delete(slotName)
    ShowMacroToggledTip("Slot '" slotName "' deleted", 2000, false)
    MacroGuiRefresh()
}

MacroGuiSlotListRename(*) {
    global slots
    oldName := MacroGuiSelectedListText("slotList")
    if (oldName = "") {
        ShowMacroToggledTip("Select a slot first", 1500, false)
        return
    }
    r := InputBox("New name for '" oldName "':", "Rename Slot", "w300 h120", oldName)
    if (r.Result = "Cancel")
        return
    newName := Trim(r.Value)
    if (newName = "" || newName = oldName)
        return
    newName := RegExReplace(newName, "[\\/:*?`"<>|]", "_")
    events := slots.Load(oldName)
    if (!IsObject(events) || events.Length = 0) {
        ShowMacroToggledTip("Cannot rename empty slot '" oldName "'", 2000, false)
        return
    }
    coordMode := IniRead(A_ScriptDir "\macros.ini", oldName, "coord_mode", "screen")
    LoadRecorderSlot(oldName, false)
    slots.Save(newName, events, coordMode)
    slots.Delete(oldName)
    LoadRecorderSlot(newName, false)
    ShowMacroToggledTip("Renamed '" oldName "' to '" newName "'", 2000, false)
    MacroGuiRefresh()
}

MacroGuiExportSlots(*) {
    global slots
    slots.ExportAll()
}

MacroGuiImportSlots(*) {
    global slots
    slots.ImportAll()
    MacroGuiRefresh()
}

MacroGuiSeqPreview(*) {
    global macroGuiControls
    seqName := MacroGuiSelectedListText("seqList")
    stepsList := macroGuiControls["seqSteps"]
    stepsList.Delete()
    if (seqName = "")
        return
    sm := SequenceManager()
    steps := sm.Load(seqName)
    if IsObject(steps) {
        for i, step in steps
            stepsList.Add("", i, step.slotName, step.delayAfter)
    }
    stepsList.ModifyCol(1, 40)
    stepsList.ModifyCol(2, 310)
    stepsList.ModifyCol(3, 90)
}

MacroGuiSeqPlay(*) {
    seqName := MacroGuiSelectedListText("seqList")
    if (seqName = "") {
        ShowMacroToggledTip("Select a sequence first", 1500, false)
        return
    }
    SequenceStart(seqName)
    MacroGuiUpdateStatus()
}

MacroGuiSeqDelete(*) {
    seqName := MacroGuiSelectedListText("seqList")
    if (seqName = "") {
        ShowMacroToggledTip("Select a sequence first", 1500, false)
        return
    }
    answer := MsgBox("Delete sequence '" seqName "'?", "Delete Sequence", "YesNo")
    if (answer != "Yes")
        return
    MacroGuiDeleteSequence(seqName)
    ShowMacroToggledTip("Sequence '" seqName "' deleted", 2000, false)
    MacroGuiRefresh()
}

MacroGuiSeqBuild(*) {
    sm := SequenceManager()
    steps := sm.Build()
    if (!IsObject(steps) || steps.Length = 0)
        return
    r := InputBox("Name this sequence:", "Save Sequence", "w280 h100", "sequence1")
    if (r.Result != "Cancel" && Trim(r.Value) != "") {
        sm.Save(Trim(r.Value), steps)
        MacroGuiRefresh()
    }
}

MacroGuiDeleteSequence(seqName) {
    iniPath := A_ScriptDir "\macros.ini"
    IniDelete iniPath, "seq_" seqName
    count := IniRead(iniPath, "Sequences", "count", 0)
    newIdx := 0
    loop count {
        nm := IniRead(iniPath, "Sequences", "seq_" A_Index, "")
        if (nm != "" && nm != seqName) {
            newIdx++
            IniWrite nm, iniPath, "Sequences", "seq_" newIdx
        }
    }
    loop count {
        if (A_Index > newIdx)
            IniDelete iniPath, "Sequences", "seq_" A_Index
    }
    IniWrite newIdx, iniPath, "Sequences", "count"
    TrayMenuRebuild()
}

MacroGuiProfileChanged(*) {
    global macroGuiControls, macroGuiRefreshing, profile
    if macroGuiRefreshing
        return
    selected := macroGuiControls["profileDDL"].Text
    if (selected != "") {
        profile.Apply(selected)
        TrayMenuRebuild()
        MacroGuiRefresh()
    }
}

MacroGuiSettingsProfileChanged(*) {
    global macroGuiControls, macroGuiRefreshing, profile
    if macroGuiRefreshing
        return
    selected := macroGuiControls["settingsProfileDDL"].Text
    if (selected != "") {
        profile.Apply(selected)
        TrayMenuRebuild()
        MacroGuiRefresh()
    }
}

MacroGuiAddProfile(*) {
    global profile
    profile.Add()
    MacroGuiRefresh()
}

MacroGuiDetectProfile(*) {
    DetectActiveProfile()
    TrayMenuRebuild()
    MacroGuiRefresh()
}

MacroGuiDebugChanged(*) {
    global macroGuiControls, macroGuiRefreshing, debugEnabled
    if macroGuiRefreshing
        return
    debugEnabled := macroGuiControls["debugCheck"].Value ? true : false
    TrayMenuRebuild()
    ShowMacroToggledTip("Debug mode " (debugEnabled ? "ON" : "OFF"), 1500, false)
    if debugEnabled
        ShowControllerDebugState()
}

MacroGuiReload(*) {
    MacroGuiSavePosition()
    Reload()
}

MacroGuiExit(*) {
    MacroGuiSavePosition()
    ExitApp()
}

MacroGuiSavePosition() {
    global macroGui, macroGuiCreated
    if !macroGuiCreated
        return
    macroGui.GetPos(&gx, &gy)
    if (gx = "" || gy = "")
        return
    iniPath := A_ScriptDir "\macros.ini"
    IniWrite gx, iniPath, "GuiState", "x"
    IniWrite gy, iniPath, "GuiState", "y"
}

MacroGuiLoadPosition(&outX, &outY) {
    iniPath := A_ScriptDir "\macros.ini"
    outX := IniRead(iniPath, "GuiState", "x", "")
    outY := IniRead(iniPath, "GuiState", "y", "")
}
