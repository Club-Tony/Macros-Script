# TESTING.md — Manual Test Checklist

All tests are manual (AHK v1 has no automated test framework). Run after each feature is implemented.

---

## Critical Paths (must work before anything else)

1. **Script starts without error**
   - Run `Macros.ahk` → no error dialogs
   - Tray icon appears (idle state, grey M icon)
   - First-run tooltip appears bottom-right if `macros.ini` missing

2. **Existing features still work (regression baseline)**
   - `Ctrl+Shift+Alt+Z` → menu opens with slot/profile header
   - F1 (slash macro), F2 (autoclicker), F3 (turbo), F4 (pure hold) all work
   - F5 keyboard recording + F12 playback still works
   - `Ctrl+Esc` reload works cleanly

3. **Slot save/load round-trip (CRITICAL)**
   - Record keyboard macro → stop → name it `test_slot` → save
   - Press `Ctrl+Esc` to reload script
   - Right-click tray → verify `test_slot` appears in Slots list
   - Select it → play back → verify events replay correctly

---

## Feature Checklists

### Native MacrosApp Controller + vJoy Parity
- [ ] Run `MacrosEngine/build-x64/test_engine.exe` → all native tests pass
- [ ] Run `dotnet run --project MacrosApp/tools/MacrosApp.Smoke/MacrosApp.Smoke.csproj` → smoke test passes
- [ ] Record a mixed keyboard + mouse + controller slot in MacrosApp → saved event file contains `C|` controller rows
- [ ] Restart MacrosApp → saved mixed slot is still listed and playable
- [ ] Play an AHK v1-recorded controller slot in MacrosApp → vJoy output moves in `joy.cpl`
- [ ] Set `vJoyDeviceId=2` in the active profile → MacrosApp routes controller playback to device 2
- [ ] Disable or uninstall vJoy → MacrosApp playback status warns that vJoy is unavailable and does not crash
- [ ] Start a long or infinite playback → stop it → playback exits promptly and no `TerminateThread` warning appears
- [ ] End-to-end parity: compare a 60-second mixed MacrosApp recording against the same AHK v1 workflow

---

### Feature 1: Named Slots + .ini Persistence
- [ ] Save unnamed slot (hit Enter at name prompt) → saved as `untitled`
- [ ] Save named slot → appears in tray menu immediately
- [ ] Reload script → slot persists in tray menu
- [ ] Play slot via F12 after selecting from tray
- [ ] `macros.ini.bak` created after each save
- [ ] Disk-full simulation: if `macros.ini` locked, error tooltip shown

### Feature 2: Tri-Mode SendMode
- [ ] `Ctrl+Alt+P` cycles: Input → Play → Event → Input → ...
- [ ] Tooltip shows new mode after each cycle
- [ ] Menu tooltip reflects current SendMode
- [ ] SendMode applies to keyboard/mouse playback (test each mode with a game)
- [ ] `SendEvent` mode works for games that block Input/Play

### Feature 3: Tray Icon + Menu
- [ ] Tray icon appears on startup
- [ ] Icon changes to red during recording
- [ ] Icon changes to green during playback
- [ ] Icon changes to yellow when paused
- [ ] Icon returns to grey on stop
- [ ] Right-click menu shows current slot and profile in header
- [ ] All menu items invoke correct functions

### Feature 4: Playback Speed Multiplier
- [ ] Tray → Playback Speed → 2x selected → tooltip confirms
- [ ] Record a 2-second macro → play at 2x → verify takes ~1 second
- [ ] Record a 2-second macro → play at 0.5x → verify takes ~4 seconds
- [ ] Speed applies to both keyboard and mouse events

### Feature 5: Conditional Loop (Until Keypress)
- [ ] Tray → Loop Mode → Until Key → Input prompt shown for key selection
- [ ] Press a key (e.g. Space) → confirmed as stop trigger
- [ ] Start playback → loops indefinitely
- [ ] Press Space → loop stops cleanly at end of current iteration
- [ ] Esc also stops loop

### Feature 6: Import/Export
- [ ] Export all slots → .ini file created with correct format
- [ ] Import that file on another machine → all slots restored
- [ ] Import with conflict → InputBox shown for each conflicting slot
- [ ] Import Y → slot overwritten
- [ ] Import N → slot renamed to `slotname_2`
- [ ] Import malformed .ini → "0 macros imported" tooltip, no crash

### Feature 7: Sequence Builder
- [ ] Tray → Sequences → Build Sequence → add 3 slots with delays
- [ ] Save sequence → appears in Sequences submenu
- [ ] Play sequence → tooltip shows "step 1 of 3: slot_name"
- [ ] Empty step → skipped with debug tooltip (if debug on)
- [ ] Esc during step 2 of 3 → stops cleanly, no hang

### Feature 8: Debug Toggle
- [ ] AHK v2: empty/missing sequence step shows a `DEBUG:` tooltip only while debug mode is ON
- [ ] AHK v2: `DebugLog()` writes to stdout and `DebugLogFile()` writes to `debug.log` only while debug mode is ON
- [ ] `Ctrl+Alt+D` → "Debug mode ON" tooltip
- [ ] Debug tooltips appear during controller events, suppression, etc.
- [ ] `Ctrl+Alt+D` again → "Debug mode OFF" tooltip
- [ ] Debug state persists through F-key mode activation

### AHK v2 Recorder Keys Port
- [ ] Run `AutoHotkey.exe /ErrorStdOut=UTF-8 /iLib '*' Macros_v2.ahk` and confirm exit code 0
- [ ] Start an AHK v2 F5 recording, type letters/numbers/punctuation, click mouse buttons, scroll wheel, then stop with F5
- [ ] Confirm the saved event file contains `K|` rows for keys, `B|` rows for mouse buttons/wheel, and `M|` rows for mouse movement
- [ ] Replay the saved slot and confirm keys, clicks, wheel, and movement replay without blocking the original inputs during recording
- [ ] Confirm F5/F6/Esc still stop recording reliably and are not required as recorded events

### AHK v2 XInput Port
- [ ] Run `AutoHotkey.exe /ErrorStdOut=UTF-8 /iLib '*' Macros_v2.ahk` and confirm exit code 0
- [ ] With debug ON and an XInput-compatible controller connected, confirm the debug tooltip shows pad index, buttons, triggers, and thumb axes
- [ ] With debug ON and no controller connected, confirm the debug tooltip reports controller state unavailable without crashing
- [ ] Confirm keyboard/mouse recording and playback behavior is unchanged while controller polling is active

### AHK v2 Controller + vJoy Port
- [ ] Run `AutoHotkey.exe /ErrorStdOut=UTF-8 /iLib '*' Macros_v2.ahk` and confirm exit code 0
- [ ] With an XInput-compatible controller connected, press L1+L2+R1+R2+A to start recording and confirm keyboard/mouse/controller events can be captured
- [ ] Stop the combo recording and confirm auto-playback routes controller events through vJoy without crashing
- [ ] Load a saved slot containing `C|` controller rows from the tray and from the GUI, then confirm playback requires vJoy and preserves controller-event metadata
- [ ] Press L1+L2+R1+R2+X during an active mode and confirm cancel/back behavior stops the current mode cleanly

### AHK v2 Hold Ports
- [ ] Open the macro menu, press F3, bind a keyboard key, and confirm the chosen trigger toggles repeated key output
- [ ] Open the macro menu, press F4, bind a keyboard key, and confirm the chosen trigger toggles key-down/key-up hold behavior
- [ ] Repeat F3/F4 setup with a controller button and confirm each controller trigger toggles only once per physical press
- [ ] Press Esc or F3/F4 while each hold mode is staged and confirm all held keys are released

### AHK v2 MacroGui Port
- [ ] Run `AutoHotkey.exe /ErrorStdOut=UTF-8 /iLib '*' Macros_v2.ahk` and confirm exit code 0
- [ ] Open the tray menu -> Open Control Panel, then confirm the Main, Slots, Sequences, and Settings tabs render
- [ ] Press `Ctrl+Shift+Alt+G` and confirm the control panel toggles without affecting the existing `Ctrl+Shift+Alt+Z` macro menu
- [ ] From Main, load a slot, change speed/loop controls, play, pause/resume, and stop playback
- [ ] From Slots, load, rename, delete, export, import, refresh, and start a new recording
- [ ] From Sequences, preview steps, build a sequence, play it, and delete it
- [ ] From Settings, apply/detect profiles, toggle debug mode, and confirm XInput/vJoy status text updates

### Per-Game Profiles
- [ ] Open `profiles.ini` → add profile for a game with `Process=game.exe`
- [ ] Launch that game → open macro menu → "Profile loaded: gamename" tooltip
- [ ] Profile applies correct SendMode automatically
- [ ] Profile with `vJoyDeviceId=2` → vJoy switches to device 2
- [ ] No matching process → uses Default profile

---

## Edge Cases

- Slot name with special chars (spaces, forward slashes, quotes) → saved/loaded correctly
- Slot name 47 characters long → truncated or stored correctly
- 20+ slots saved → tray menu scrolls or handles gracefully
- Recording with 10,000 events → save/load completes without hang
- Speed multiplier at 0.5x on controller events → no floating-point drift in timing
- Two profiles with same Process name → first one in file wins
- Import of 50 slots at once → no timeout or hang
- Sequence with 10 steps → plays all steps without memory issue

---

## Failure Mode Tests

- [ ] `macros.ini` deleted mid-session → reload → new .ini created fresh
- [ ] `macros.ini` manually corrupted → load attempts → error tooltip, no crash
- [ ] vJoy not installed → controller playback shows tooltip warning (existing behavior)
- [ ] XInput not found → controller recording disabled tooltip (existing behavior)
- [ ] Game with aggressive anti-cheat → document: all 3 SendModes + vJoy may be blocked

---

## Regression Tests (existing features)

After all new features implemented, verify these still work:

- [ ] F5 screen-coord recording
- [ ] F6 client-locked recording
- [ ] Controller recording with suppression (L1+L2+R1+R2+A)
- [ ] Controller auto-playback after recording stops
- [ ] Loop count InputBox (blank = infinite, number = fixed, Esc = cancel)
- [ ] Controller kill switch (L1+L2+R1+R2+X clears all)
- [ ] `Ctrl+Alt+T` help tooltip in menu context
