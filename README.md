# Macros-Script

Staged macro menu for fast click, turbo key hold, pure hold, and macro recorder playback with keyboard/mouse and controller support.

## Setup
Add a shortcut to `Macros.ahk` in your Startup folder (`Win+R` → `Shell:Startup`) so it runs automatically.

## Requirements
- **AutoHotkey v1** installed
- **vJoy driver** (optional) - required for controller playback. Install from vJoySetup.exe and reboot.
- **XInput-compatible controller** (optional) - Xbox controllers work natively; PlayStation controllers need DS4Windows.

## Essential Hotkeys

- `Ctrl+Shift+Alt+Z` — open the macro menu overlay; use `Esc` to cancel/timeout.
- While menu is open: `F1` stage `/` => left-click toggle; `F2` stage autoclicker; `F3` stage turbo key hold; `F4` stage pure key hold; `F5` start recording (screen coords); `F6` start recording (client-locked mouse).
- To toggle off F1-F6 functions - `Esc` or corresponding FKey (recording stops with `F5`).
- `Ctrl+Alt+P` — toggle SendMode (Input/Play) used by the macros. Useful as a switch to SendPlay if a game doesn't allow SendInput.
- `Ctrl+Esc` — reload the script.

## Controller Combos (vJoy + XInput)

All controller functions require the L1+L2+R1+R2 combo to prevent accidental in-game triggers:

- `L1+L2+R1+R2+A` — start recording; press again to stop and auto-start infinite playback; press again to stop playback
- `L1+L2+R1+R2+B` — start turbo key hold
- `L1+L2+R1+R2+Y` — start pure key hold
- `L1+L2+R1+R2+X` — kill switch (stop and clear all macros)

## Macro Recording (F5)

- `F5` toggles start/end macro recording
- From the menu: `F6` starts recording with client-locked mouse movement relative to the active window (focus the same app for playback)
- `F12` prompts for playback loops after recording (blank/Enter or 15s timeout = infinite, Esc cancels)
- If using controller: combos above control recording/playback
- Tooltip will warn if controller support is unavailable (vJoy/XInput missing)

## Button Mapping Reference

| PlayStation | Xbox | Function |
|-------------|------|----------|
| L1 | LB | Left Shoulder |
| L2 | LT | Left Trigger |
| R1 | RB | Right Shoulder |
| R2 | RT | Right Trigger |
| Cross | A | Face button |
| Circle | B | Face button |
| Square | X | Face button |
| Triangle | Y | Face button |
| Options | Start | Start button |
| Share | Back | Back button |
