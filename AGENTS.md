# AGENTS.md

AutoHotkey v1 macro automation script with autoclicker, key holds, and recording/playback with controller support.

## Key files
- Macros.ahk: main script, state machine with #If context hotkeys.
- Lib/XInput.ahk, Lib/VJoy_lib.ahk, Lib/Recorder_Keys.ahk.

## Controller notes
- XInput-compatible controller required; vJoy needed for playback.
- Controller recording suppresses the trigger combo for ~500ms.

## Hotkeys and docs
- Ctrl+Esc reloads; Ctrl+Alt+T shows hotkey help when menu is open.
- When adding or changing hotkeys, update README.md and ShowHotkeyHelp() in Macros.ahk.
