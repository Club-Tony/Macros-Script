# Macros-Script - C# App + Native C Engine DLL

**Status:** In Progress
**Created:** 2026-03-23
**Goal:** Finish migrating Macros-Script into a two-layer architecture: a C# desktop app for UX plus a native C engine DLL for timing-sensitive input and controller work, while preserving compatibility with the existing AHK-era data files during the transition.

## Current Status Snapshot

As of 2026-04-21, this repo is beyond the proposal stage and already has a working vertical slice.

- `MacrosEngine/` exists as a native DLL plus smoke-test executable.
- `MacrosApp/` exists as a WinForms shell with tray behavior, global hotkeys, slot/profile loading, controller visualization, recording hooks, native playback, and save-to-disk flow.
- Existing `macros.ini` and `macros_events/*.txt` data are being read by the C# app already.
- The architecture choice is validated. The remaining work is MVP verification, app-behavior polish, controller playback, and packaging.

## Verification

Verified on 2026-04-21:

- `cmake -S MacrosEngine -B MacrosEngine/build` succeeded
- `cmake --build MacrosEngine/build` succeeded
- `MacrosEngine/build/test_engine.exe` built successfully
- `dotnet build MacrosApp/MacrosApp/MacrosApp.csproj` succeeded
- `dotnet run --no-build --project MacrosApp/tools/MacrosApp.Smoke/MacrosApp.Smoke.csproj` succeeded
- `MacrosApp/tools/Validate-Tooltips.ps1` succeeded in deterministic source-validation mode

## Problem / Rationale

### Engine Problems (AHK as hardware interface)

- `DllCall()` has overhead per invocation, and repeated controller polling makes that cost matter.
- AHK timer precision is limited enough that frequent polling and short playback delays become unreliable.
- AHK is single-threaded, so controller polling and playback work compete with hotkey responsiveness.
- Deadzone and normalization math are much cleaner in native code than in AHK.
- Playback timing drifts because short `Sleep` intervals are imprecise.

### UI Problems (AHK as user interface)

- AHK GUIs are functional but crude, with limited controls and poor discoverability.
- The current menu system is a custom overlay (`MacroGui.ahk`), not a real desktop UI.
- The current UX does not expose controller state visually.
- Tray icon management is manual and stateful in AHK.
- Settings and profiles rely on ini editing or memorized hotkeys.
- The goal is "extremely simple to use and user friendly," and AHK is not a good long-term UI layer for that.

## Architecture

```text
+-------------------------------+     +---------------------------+
| C# WinForms App               |     | Native C Engine DLL       |
|                               |     |                           |
| - Main window                 |<--->| - XInput polling          |
| - Global hotkeys              |     | - High-resolution timing  |
| - Tray icon                   |     | - Event recording buffer  |
| - Slot/profile managers       |     | - Event playback          |
| - Controller visualization    |     | - File format I/O         |
| - Settings and UX             |     | - Future vJoy output      |
+-------------------------------+     +---------------------------+
```

Current repo layout:

- `MacrosEngine/` - native C DLL, timing helpers, XInput polling, event recorder/player, file I/O, smoke tests
- `MacrosApp/MacrosApp/` - WinForms shell, tray icon, hotkeys, slot/profile managers, controller state panel, native bindings
- `Macros.ahk` and `Macros_v2.ahk` - existing working implementations that remain the behavior baseline during migration

## Why This Over Keeping AHK

| Concern | AHK Shell | C# App |
|---------|-----------|--------|
| Global hotkeys | Built-in via `#If` contexts | `RegisterHotKey` Win32 API |
| Tray icon | Manual bitmap swapping | `NotifyIcon` support |
| GUI | Custom overlay and limited controls | Real desktop controls and layouts |
| Controller visualization | Effectively absent | Native drawing and live state panel |
| Slot management | Tray menu plus ini editing | Visual list with rename, delete, export |
| Profile management | Hotkey and ini driven | Detectable and editable in UI |
| Discoverability | Requires memorized hotkeys | Clickable UI with visible state |
| Distribution | Requires AHK runtime | Can become a self-contained app |

## Implementation Status

### Phase 1 - Native Engine DLL

- [x] DLL project setup (`MacrosEngine/CMakeLists.txt`)
- [x] `Engine_Init()` / `Engine_Shutdown()` exports
- [x] Threaded XInput polling
- [x] `QueryPerformanceCounter`-based timing helpers
- [x] Configurable deadzone normalization for sticks and triggers
- [x] `Engine_GetControllerState()` for UI polling
- [x] Keyboard and mouse recording API with timestamped buffering
- [x] High-resolution playback loop
- [x] `SendInput` dispatch for keyboard and mouse playback
- [x] Read/write compatibility for the existing pipe-delimited event format
- [x] Native smoke-test executable covering lifecycle, recording, file I/O, polling, playback, and shutdown
- [ ] Button state change detection and combo detection (`L1+L2+R1+R2+button`)
- [ ] Controller-event recording inside the engine
- [ ] vJoy output for controller playback
- [ ] Playback-thread hardening before release; current code still has a `TerminateThread()` timeout fallback

### Phase 2 - C# App (Core)

- [x] WinForms project setup
- [x] P/Invoke bindings to the native DLL
- [x] Global hotkey registration
- [x] System tray shell
- [x] Main window with macro type selection
- [x] Status indicator for idle, recording, playing, and paused states
- [x] End-to-end record/play/stop wired through the engine
- [x] Persist newly recorded events back into `macros.ini` and `macros_events/*.txt`
- [x] Load a selected slot's event file into native playback
- [ ] Playback lifecycle polish and remaining macro-mode parity cleanup (`SendMode` is now honored for direct app-emitted output; recorded slot playback still runs through the native engine path)

### Phase 3 - C# App (Rich UI)

- [x] Slot manager foundation (load, delete, rename, export)
- [x] Profile manager foundation (load profiles, detect active profile by process)
- [x] Live controller state display
- [x] Deadzone visualization
- [ ] Rich settings and profile editing UI
- [ ] Recording preview or timeline visualization
- [ ] Sequence builder
- [ ] Tray-menu parity with the current AHK workflow

### Phase 4 - Distribution and Migration

- [x] Data file compatibility is partially proven by current slot/profile readers and native event file I/O
- [x] Local .NET build toolchain setup and verification
- [ ] Self-contained publish flow for the WinForms app
- [ ] First-run import or migration UX for `macros.ini`, `macros_events/*.txt`, and `profiles.ini`
- [ ] No-installer packaging story for the app plus DLL

## Recommended Next Milestone

Target MVP verification and app-behavior polish instead of more architecture work:

1. Run the built WinForms app through the real user path: select an existing slot, play it, stop it, record a new macro, save it, and replay it.
2. Keep the new smoke harness passing while fixing app-state gaps found during that path, especially playback lifecycle cleanup when native playback ends on its own.
3. Manually verify the controller viewer with a real device attach/detach pass now that the UI waits quietly when no pad is present and switches back to live polling when one appears.
4. Keep controller visualization read-only for this milestone; defer vJoy and controller recording until keyboard/mouse parity is stable.

That yields a concrete MVP: launch the WinForms app, view existing slots, record a keyboard/mouse macro, save it, replay it, and return cleanly to idle without running AHK.

## Key Constraints

- Backward-compatible data remains mandatory: `.txt` event files, `macros.ini`, and `profiles.ini` must continue to work.
- The original AHK implementation stays untouched during the migration.
- vJoy remains optional and must degrade gracefully when absent.
- The final UX has to be simpler to use than the AHK version, not just technically cleaner.

## UX Design Principles

- Zero-config start: launch the app, pick a macro type, press a button.
- Hotkeys are shortcuts, not requirements.
- Visual feedback should always show recording state, playback state, and controller state.
- Progressive disclosure should keep common actions obvious while hiding advanced settings until needed.

## Risks

- Two languages means more maintenance and integration complexity than a single-language app.
- Native crashes can still take down the C# process.
- Controller playback still depends on vJoy integration that does not exist yet.
- The current playback thread shutdown strategy is acceptable for prototyping, not for release.
- GUI-heavy flows still lack strong automated end-to-end coverage, so regressions can hide in app-state transitions.

## Alternative Considered: Pure C#

A pure C# implementation remains viable:

- XInput via direct P/Invoke
- High-resolution timing via `Stopwatch`
- Dedicated polling and playback threads in managed code
- vJoy via P/Invoke to the driver DLL

That would simplify the stack, but the current repo already has a working native prototype. Revisit the pure-C# option only if the native/controller work stalls or the two-language maintenance cost becomes the dominant problem.

## When

Medium priority. The current AHK version still works, and the prototype architecture now exists. The best path is incremental implementation: finish keyboard/mouse MVP behavior in the WinForms app first, then add controller playback and packaging.
