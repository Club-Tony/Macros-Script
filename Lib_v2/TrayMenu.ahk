; Lib_v2/TrayMenu.ahk — System tray icon + right-click menu (AHK v2)
; Uses AHK v2 Menu class and class-based API.

class TrayMenuManager {
    ; ──────────────────────────────────────────────────────────────────────────
    ; INIT
    ; ──────────────────────────────────────────────────────────────────────────
    Init() {
        A_TrayMenu.Delete()    ; Remove default AHK menu items
        A_IconTip := "Macros-Script"
        this.SetIcon("idle")
        this.Rebuild()
    }

    ; ──────────────────────────────────────────────────────────────────────────
    ; ICON
    ; ──────────────────────────────────────────────────────────────────────────
    SetIcon(state) {
        iconDir := A_ScriptDir "\icons\"
        iconFile := iconDir (state = "recording" ? "recording.ico"
                           : state = "playing"   ? "playing.ico"
                           : state = "paused"    ? "paused.ico"
                           :                       "idle.ico")
        if FileExist(iconFile)
            TraySetIcon iconFile
    }

    ; ──────────────────────────────────────────────────────────────────────────
    ; REBUILD
    ; ──────────────────────────────────────────────────────────────────────────
    Rebuild() {
        global slots, profile, recorder, debugEnabled

        ; Build submenus
        slotsMenu     := this._BuildSlotsMenu()
        seqMenu       := this._BuildSequencesMenu()
        profilesMenu  := this._BuildProfilesMenu()
        speedMenu     := this._BuildSpeedMenu()
        loopMenu      := this._BuildLoopMenu()

        ; Main tray menu
        m := A_TrayMenu
        m.Delete()

        ; Status headers (disabled items)
        slotDisplay    := (recorder.slotName != "") ? recorder.slotName : "(none)"
        profileDisplay := profile.name " (Send" profile.sendMode ")"
        m.Add("Slot: " slotDisplay, (*) => 0)
        m.Add("Profile: " profileDisplay, (*) => 0)
        m.Disable("Slot: " slotDisplay)
        m.Disable("Profile: " profileDisplay)
        m.Add()

        m.Add("Slots",          slotsMenu)
        m.Add("Sequences",      seqMenu)
        m.Add("Profiles",       profilesMenu)
        m.Add()
        m.Add("Playback Speed", speedMenu)
        m.Add("Loop Mode",      loopMenu)
        m.Add()
        m.Add("Open Macro Menu",  (*) => this._OpenMenu())
        dbgLabel := debugEnabled ? "Debug: ON  (Ctrl+Alt+D)" : "Debug: OFF (Ctrl+Alt+D)"
        m.Add(dbgLabel,           (*) => this._ToggleDebug())
        m.Add("Reload Script",    (*) => Reload())
        m.Add()
        m.Add("Exit",             (*) => ExitApp())
    }

    ; ──────────────────────────────────────────────────────────────────────────
    ; SUBMENU BUILDERS
    ; ──────────────────────────────────────────────────────────────────────────
    _BuildSlotsMenu() {
        global slots, recorderEvents, recorder
        m := Menu()
        names := slots.ListNames()
        for name in names {
            capName := name   ; capture for closure
            m.Add(capName, (item, *) => this._LoadSlot(item))
        }
        if (names.Length > 0)
            m.Add()
        m.Add("New Recording (F5)",  (*) => StartRecorder())
        m.Add("Export All Slots",    (*) => slots.ExportAll())
        m.Add("Import Slots",        (*) => slots.ImportAll())
        return m
    }

    _LoadSlot(slotName) {
        global slots, recorderEvents, recorder
        events := slots.Load(slotName)
        if (IsObject(events) && events.Length > 0) {
            recorderEvents := events
            recorder.slotName := slotName
            ShowMacroToggledTip("Slot '" slotName "' loaded | F12 to play", 2000, false)
            this.Rebuild()
        } else
            ShowMacroToggledTip("Slot '" slotName "' is empty", 2000, false)
    }

    _BuildSequencesMenu() {
        global sequence
        m := Menu()
        sm := SequenceManager()
        names := sm.ListNames()
        for name in names {
            capName := name
            m.Add(capName, (item, *) => SequenceStart(item))
        }
        if (names.Length > 0)
            m.Add()
        m.Add("Build Sequence", (*) => this._BuildAndSaveSequence())
        return m
    }

    _BuildAndSaveSequence() {
        sm := SequenceManager()
        steps := sm.Build()
        if IsObject(steps) && steps.Length > 0 {
            r := InputBox("Name this sequence:", "Save Sequence", "w280 h100", "sequence1")
            if (r.Result != "Cancel" && Trim(r.Value) != "")
                sm.Save(Trim(r.Value), steps)
        }
    }

    _BuildProfilesMenu() {
        global profile
        m := Menu()
        m.Add("Default", (*) => profile.Apply("Default"))
        for name in profile.ListNames() {
            capName := name
            m.Add(capName, (item, *) => profile.Apply(item))
        }
        m.Check(profile.name)
        m.Add()
        m.Add("Add Profile", (*) => profile.Add())
        return m
    }

    _BuildSpeedMenu() {
        global recorder
        m := Menu()
        m.Add("0.5x", (*) => this._SetSpeed(0.5))
        m.Add("1x",   (*) => this._SetSpeed(1.0))
        m.Add("2x",   (*) => this._SetSpeed(2.0))
        cur := recorder.speed
        m.Check(cur = 0.5 ? "0.5x" : cur = 2.0 ? "2x" : "1x")
        return m
    }

    _SetSpeed(spd) {
        global recorder
        recorder.speed := spd
        ShowMacroToggledTip("Playback speed: " spd "x", 1500, false)
        this.Rebuild()
    }

    _BuildLoopMenu() {
        global recorder
        m := Menu()
        m.Add("Fixed Count", (*) => this._SetLoop("fixed"))
        m.Add("Infinite",    (*) => this._SetLoop("infinite"))
        m.Add("Until Key",   (*) => this._SetLoopUntilKey())
        cur := recorder.loopMode
        m.Check(cur = "fixed" ? "Fixed Count" : cur = "untilkey" ? "Until Key" : "Infinite")
        return m
    }

    _SetLoop(mode) {
        global recorder
        recorder.loopMode := mode
        ShowMacroToggledTip("Loop mode: " mode, 1500, false)
        this.Rebuild()
    }

    _SetLoopUntilKey() {
        global recorder
        ShowMacroToggledTip("Press any key to set as loop stop trigger...", 3000, false)
        ih := InputHook("L1 T15")
        ih.Start()
        ih.Wait()
        if (ih.EndReason = "Timeout" || ih.Input = "") {
            ShowMacroToggledTip("Loop key not set (timeout)", 1500, false)
            return
        }
        recorder.loopMode    := "untilkey"
        recorder.loopUntilKey := ih.Input
        ShowMacroToggledTip("Loop mode: Until '" ih.Input "' pressed", 2000, false)
        this.Rebuild()
    }

    _OpenMenu() {
        global menuActive
        if !menuActive {
            menuActive := true
            DetectActiveProfile()
            ToolTip MenuTooltipText()
            SetTimer () => CloseMenu("timeout"), -15000
        }
    }

    _ToggleDebug() {
        global debugEnabled
        debugEnabled := !debugEnabled
        ShowMacroToggledTip("Debug mode " (debugEnabled ? "ON" : "OFF"), 2000, false)
        this.Rebuild()
    }
}
