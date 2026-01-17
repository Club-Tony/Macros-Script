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

**SendMode Toggle** (`Ctrl+Alt+P`): Switches between `SendInput` (default) and `SendPlay` for compatibility with games that block SendInput.

## Hotkeys Reference

| Hotkey | Action |
|--------|--------|
| `Ctrl+Shift+Alt+Z` | Open macro menu |
| `Ctrl+Esc` | Reload script |
| `Ctrl+Alt+P` | Toggle SendMode (Input/Play) |
| `Esc` | Cancel/exit current macro mode |
| `F12` | Toggle playback (after recording) |

## Development Notes

- AutoHotkey v1 syntax (`#Requires AutoHotkey v1`)
- Uses `#Include <LibName>` for library imports from `Lib/` folder
- Debug tooltips are currently enabled throughout - look for `ToolTip, DEBUG:` lines
- Controller recording uses normalization with configurable deadzones (`controllerThumbDeadzone`, `controllerTriggerDeadzone`)
