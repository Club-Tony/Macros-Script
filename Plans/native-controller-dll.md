# Macros-Script — C# App + Native C/C++ Engine DLL

**Status:** Planned
**Created:** 2026-03-23
**Goal:** Rebuild Macros-Script as a two-layer architecture: C# UI app + native C/C++ engine DLL — replacing AHK entirely

## Problem / Rationale

### Engine Problems (AHK as hardware interface)
- `DllCall()` has overhead per invocation — at 50Hz polling that adds up
- **Timer precision** — AHK's `SetTimer` resolution is ~15ms, making 20ms controller polling unreliable
- **No threading** — AHK is single-threaded; polling blocks hotkey responsiveness
- **Deadzone/normalization math** in AHK is awkward — no native floating-point or vector types
- **Event playback timing** drifts because AHK's `Sleep` is imprecise at small intervals

### UI Problems (AHK as user interface)
- AHK GUIs are functional but crude — no modern controls, no data binding, no visual polish
- Menu system is a custom overlay (`MacroGui.ahk`), not a real UI framework
- No visual feedback for controller state (which stick, which buttons, deadzones)
- Tray icon management is manual bitmap swapping
- Settings/configuration is all ini-file editing or hotkey-driven — not discoverable for new users
- **The goal is "extremely simple to use and user friendly"** — AHK can't deliver that

## Architecture

```
+----------------------------------+     +------------------------+
|   C# WPF/WinForms App           |     |   Native Engine DLL    |
|                                  |     |   (C/C++)              |
| - Modern Windows UI              |     |                        |
| - Global hotkeys (RegisterHotKey)|<--->| - XInput polling       |
| - System tray icon               |     | - vJoy output          |
| - Slot manager (visual)          |     | - Event recording      |
| - Profile manager (visual)       |     | - Event playback       |
| - Live controller state display  |     | - Timing engine        |
| - Settings panel                 |     | - Deadzone math        |
| - Recording visualizer           |     | - SendInput dispatch   |
+----------------------------------+     +------------------------+
```

The C# app handles all user interaction. The native DLL handles all timing-critical hardware work. They communicate via P/Invoke (C# calling DLL exports).

## Why This Over Keeping AHK

| Concern | AHK Shell | C# App |
|---------|-----------|--------|
| Global hotkeys | Built-in (`#If` contexts) | `RegisterHotKey` Win32 API — same capability |
| Tray icon | Manual bitmap swap | `NotifyIcon` — built-in, supports balloons/tooltips |
| GUI | Custom overlay, limited controls | Full WinForms/WPF — buttons, sliders, lists, tabs |
| Controller visualization | Not possible | Draw stick positions, button highlights, deadzone rings |
| Slot management | Tray menu + ini editing | Visual list with rename, reorder, delete, preview |
| Profile management | Hotkey cycle + ini editing | Dropdown with per-game settings panel |
| Discoverability | Must know hotkeys to start | Visual menu — click what you want |
| Distribution | Requires AHK runtime installed | Single exe (self-contained publish) |

## Scope

### Phase 1 — Native Engine DLL (C/C++)
- [ ] DLL project setup (C, Win32, static-linked, no CRT dependency)
- [ ] `Engine_Init()` / `Engine_Shutdown()` exports
- [ ] Threaded XInput polling at configurable rate (default 5ms, 200Hz)
- [ ] `QueryPerformanceCounter`-based high-resolution timing
- [ ] Deadzone normalization (configurable per-stick, per-trigger)
- [ ] Button state change detection + combo detection (L1+L2+R1+R2+button)
- [ ] `Engine_GetControllerState()` for UI to read current state
- [ ] Event recording (keyboard, mouse, controller — timestamped)
- [ ] Event playback with microsecond timing reconstruction
- [ ] vJoy output for controller playback (graceful fallback if not installed)
- [ ] `SendInput` dispatch for keyboard/mouse playback
- [ ] Read/write existing pipe-delimited event format (backward compatible with `.txt` files)

### Phase 2 — C# App (Core)
- [ ] C# WinForms or WPF project setup
- [ ] P/Invoke bindings to engine DLL
- [ ] Global hotkey registration (`RegisterHotKey`)
- [ ] System tray icon with context menu
- [ ] Main window with macro type selection (Slash, Autoclicker, Turbo, Hold, Recorder)
- [ ] Basic record/play/stop controls
- [ ] Status indicator (idle / recording / playing / paused)

### Phase 3 — C# App (Rich UI)
- [ ] Slot manager — visual list with names, durations, loop counts
- [ ] Profile manager — per-game settings with auto-detection
- [ ] Live controller state display (stick positions, button highlights)
- [ ] Deadzone visualization (rings showing active deadzone)
- [ ] Settings panel (intervals, SendMode, controller config)
- [ ] Recording preview/timeline visualization
- [ ] Sequence builder (chain multiple slots)

### Phase 4 — Distribution & Migration
- [ ] Self-contained single-exe publish
- [ ] Import existing `macros.ini` + `macros_events/*.txt` + `profiles.ini`
- [ ] Data file compatibility (reads existing AHK-era files)
- [ ] No installer needed — single exe + DLL (or embed DLL as resource)

## Key Constraints

- **Backward compatible data** — must read existing `.txt` event files, `macros.ini`, `profiles.ini`
- **No runtime dependencies on target** — self-contained C# publish + static-linked DLL
- **vJoy is optional** — graceful degradation if not installed
- **Original AHK version stays untouched** — this is a new parallel build
- **Must be simpler to use than the AHK version** — if a user can't figure it out without reading docs, the UI has failed

## UX Design Principles

- **Zero-config start** — launch, pick a macro type, press a button. No hotkey memorization required
- **Hotkeys are shortcuts, not requirements** — everything accessible via the UI; power users can still use keyboard
- **Visual feedback** — always show what's happening (recording state, controller input, playback progress)
- **Progressive disclosure** — simple view by default, advanced settings available but not in the way

## Risks

- **Build toolchain** — need MSVC or MinGW for the DLL + .NET SDK for the C# app
- **Two languages** — C/C++ for the DLL and C# for the app is more complexity than a single-language solution
- **DLL crashes** — native crashes can take down the C# process; need defensive error handling and crash recovery
- **vJoy driver compatibility** — vJoy versions may have different DLL interfaces
- **Learning curve** — WPF/WinForms if not already familiar (WinForms is simpler to start with)

## Alternative Considered: Pure C#

Could skip the native DLL entirely and do everything in C#:
- XInput via `SharpDX.XInput` or direct P/Invoke to `xinput1_4.dll`
- vJoy via P/Invoke to `vJoyInterface.dll`
- High-resolution timing via `Stopwatch` (wraps `QueryPerformanceCounter`)
- Dedicated `Task`/`Thread` for polling

This is simpler (one language) but gives up the guaranteed sub-millisecond timing precision of native code. For most users this would be fine — the .NET `Stopwatch` is accurate to ~1 microsecond. Worth considering if the two-language build complexity is a blocker.

## When

Medium priority. The current AHK version works. This is a UX and precision upgrade. Good candidate for incremental implementation — Phase 1 (DLL) and Phase 2 (basic C# shell) together form a usable MVP.
