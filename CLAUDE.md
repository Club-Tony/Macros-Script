# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AutoHotkey v1 macro automation script providing fast clicking, key holds, autoclicker, and input recording/playback with both keyboard/mouse and Xbox-style controller support.

## Architecture

**Main Script**: `Macros.ahk` - Single-file automation script with modular state machine design

**Libraries** (in `Lib/`):
- `XInput.ahk` - Xbox controller API wrapper (XInput DLL interface)
- `VJoy_lib.ahk` - Virtual joystick driver interface for controller playback
- `Recorder_Keys.ahk` - Keyboard/mouse hook definitions for macro recording
- `Slots.ahk` - Named slot save/load/import/export + sequencer (pipe-delimited events in `macros_events/`)
- `Profiles.ahk` - Per-game compatibility profiles with auto-detection via WinGet
- `TrayMenu.ahk` - System tray icon (4 states) + right-click menu

**AHK v2 port** (`Macros_v2.ahk` + `Lib_v2/`): Full feature parity using classes (`SlotManager`, `ProfileManager`, `TrayMenuManager`). Shares same `.ini` data format.

**Data files** (auto-created on first run):
- `macros.ini` - slot metadata and sequence definitions
- `macros_events/*.txt` - one file per slot, pipe-delimited event data
- `profiles.ini` - per-game compatibility profiles
- `icons/` - 4 tray icon states (idle/recording/playing/paused)

**State Machine Pattern**: The script uses global state variables with `#If` context-sensitive hotkeys to manage different modes (menu active, slash macro on, autoclicker ready, recorder active, etc.).

## Key Concepts

**Macro Types**:
- Slash Macro (`F1`): Maps `/` key to left click
- Autoclicker (`F2`): Configurable interval auto-clicking
- Turbo Hold (`F3`): Rapid key repeat while toggled
- Pure Hold (`F4`): Simple key down/up toggle
- Recorder (`F5`): Records and plays back keyboard, mouse, and controller input

**Controller Integration**:
- Requires XInput-compatible controller (Xbox, or PlayStation via DS4Windows)
- Controller playback requires vJoy driver installation
- Button combos: `L1+L2+R1+R2+A/B/Y/X` for various functions
- 500ms suppression period prevents recording the trigger combo itself

**SendMode Cycle** (`Ctrl+Alt+P`): Cycles `SendInput` → `SendPlay` → `SendEvent` for game compatibility.

**Per-game profiles** (`profiles.ini`): Auto-detected on menu open by foreground process name. Each profile sets SendMode + vJoyDeviceId.

**Named slots** (`macros.ini` + `macros_events/`): Recordings persist across reloads. Saved after each recording with a user-chosen name. Accessible from the tray menu.

## Hotkeys Reference

| Hotkey | Action |
|--------|--------|
| `Ctrl+Shift+Alt+Z` | Open macro menu |
| `Ctrl+Alt+T` | Show hotkey help (only when menu is open) |
| `Ctrl+Esc` | Reload script |
| `Ctrl+Alt+P` | Cycle SendMode (Input → Play → Event) |
| `Ctrl+Alt+D` | Toggle debug mode |
| `Esc` | Cancel/exit current macro mode |
| `F12` | Toggle playback (after recording) |
| Right-click tray | Full menu: slots, sequences, profiles, speed, loop mode |

## Development Notes

- AutoHotkey v1 syntax (`#Requires AutoHotkey v1`)
- Uses `#Include <LibName>` for library imports from `Lib/` folder
- Debug system (`Lib/Debug.ahk`) is available but currently disabled -- the `#Include` is commented out in Macros.ahk
- Controller recording uses normalization with configurable deadzones (`controllerThumbDeadzone`, `controllerTriggerDeadzone`)

## When Adding/Modifying Hotkeys

1. **Update README.md** - Document new hotkeys in the appropriate section
2. **Update `ShowHotkeyHelp()`** in Macros.ahk - The built-in tooltip help (Ctrl+Alt+T) should include all hotkeys
