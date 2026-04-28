# AHK v2 Port Completion

**Status:** In Progress (implementation complete 2026-04-28; live controller/vJoy verification pending)
**Created:** 2026-04-24
**Goal:** Bring `Macros_v2.ahk` + `Lib_v2/` to feature parity with `Macros.ahk` + `Lib/`.

## Context

The v2 port currently sits at ~23% of v1's line count (1,428 vs 6,258 LOC). The 2026-04-24 debug session unblocked v2 by fixing a `sendMode` global / built-in `SendMode` function name collision in `Lib_v2/Profiles.ahk:48` (renamed global to `currentSendMode`). With that fix, v2 parses and loads, but it remains a keyboard/mouse-only MVP — controller input, vJoy output, the GUI panel, and several library files are absent.

Resolution as of 2026-04-28: `MacrosApp` (C# + native engine) is the active replacement path. Keep this AHK v2 parity plan on hold unless native parity fails or a specific AHK v2 need appears.

Reactivated 2026-04-28 by explicit user request to proceed with the AHK v2 plan while leaving the native live parity gate open.

## Implementation Update - 2026-04-28

- Implemented `Lib_v2/Debug.ahk`, a v2-native debug tooltip/logging helper that uses the existing `debugEnabled` toggle.
- `Macros_v2.ahk` now includes the debug helper and uses `DebugTip()` for the empty sequence-step debug path.
- Added a missing v2 `Clamp()` helper used by autoclicker setup, fixing the launch warning that AutoHotkey raised for `Clamp`.
- Implemented `Lib_v2/XInput.ahk`, startup XInput initialization, controller state lookup, and a debug tooltip that reports live XInput state when debug mode is enabled.
- Implemented `Lib_v2/Recorder_Keys.ahk`, a `#HotIf`-gated pass-through hotkey map for keyboard keys, mouse buttons, and wheel input while recording is active.
- F5/F6/Esc remain recorder controls in v2 rather than recorded keys, so users can reliably stop a recording.
- Implemented controller combo polling, L1+L2+R1+R2 latching, controller recording sampling, controller auto-playback after combo recording, and the controller cancel/back combos.
- Replaced the F3 Turbo Hold and F4 Pure Hold stubs with keyboard and controller binding flows.
- Implemented `Lib_v2/VJoy_lib.ahk` plus controller-event playback mapping for buttons, axes, triggers, and POV.
- Implemented `Lib_v2/MacroGui.ahk`, a v2 `Gui`-class 4-tab panel for Main, Slots, Sequences, and Settings, available from the tray and `Ctrl+Shift+Alt+G`.
- Added a shared slot-load path so tray and GUI loads preserve controller-event metadata for vJoy-gated playback.
- Updated sequence playback so slots with wheel-style mouse events and controller events replay correctly through the sequence runner.
- Validation so far: `AutoHotkey.exe /ErrorStdOut=UTF-8 /iLib '*' Macros_v2.ahk` exits 0, and a hidden startup smoke run produced no stderr. Live controller and vJoy behavior still needs hardware verification.

## What v2 currently has

- F1 slash macro, F2 autoclicker (fully ported)
- F5/F6 recorder (keyboard/mouse keys, buttons, wheel, and sampled mouse movement)
- F12 playback, sequence builder, Ctrl+Alt+P SendMode cycle
- Per-game profiles (Lib_v2/Profiles.ahk)
- Tray menu (Lib_v2/TrayMenu.ahk — partial)
- Slot manager (Lib_v2/Slots.ahk)
- Controller combo recording/playback path through XInput + vJoy
- F3 Turbo Hold and F4 Pure Hold setup/toggle flows
- 4-tab MacroGui panel (Lib_v2/MacroGui.ahk)

## What v2 is missing

| Component | v1 size | v2 size | Status |
|-----------|---------|---------|--------|
| `Lib/MacroGui.ahk` | 1000 | absent | Not started — 4-tab GUI panel (Main/Slots/Sequences/Settings) |
| `Lib/Recorder_Keys.ahk` | 251 | present | Implemented - v2 `#HotIf` pass-through map added for keyboard/mouse recording |
| `Lib/XInput.ahk` | 428 | present | Implemented - DllCall/Buffer wrapper plus debug state readout added |
| `Lib/VJoy_lib.ahk` | 865 | absent | Not started — vJoy device + axis/button/POV API |
| `Lib/Debug.ahk` | 120 | present | Implemented - DebugTip / DebugLog helpers added |
| Controller polling loop | embedded in `Macros.ahk` | absent | Not started — `ControllerComboPoll` + L1+L2+R1+R2 detection |
| Turbo Hold (F3) | embedded in `Macros.ahk` | stub | `Macros_v2.ahk:630` — toast only |
| Pure Hold (F4) | embedded in `Macros.ahk` | stub | `Macros_v2.ahk:634` — toast only |

2026-04-28 implementation note: the historical table above still reflects the plan's starting gap analysis for some rows. Current code now includes MacroGui, VJoy, controller polling, Turbo Hold, and Pure Hold implementations; the remaining open item is live hardware verification with an XInput controller and vJoy.

## Solution / Scope

Recommended order (independent → dependent):

1. **Port `Debug.ahk`** — small, no dependencies. Establishes v2 debug pattern.
2. **Port `XInput.ahk`** — DllCall signature changes (v2 uses different `Buffer` semantics). Validate by reading controller state and dumping it to a tooltip.
3. **Port `Recorder_Keys.ahk`** — `#HotIf` is already used in v2; convert dynamic `Hotkey` calls and `~` prefix usage to v2 syntax. Wires keyboard/mouse hooks into the recorder.
4. **Port controller polling + combo detection** — `ControllerComboPoll` from `Macros.ahk:413`, L1+L2+R1+R2 latching, 500ms suppression window.
5. **Port Turbo Hold (F3) + Pure Hold (F4)** — replace stubs at `Macros_v2.ahk:630-636`. Depends on the controller polling layer.
6. **Port `VJoy_lib.ahk`** — biggest single port (865 lines). DllCall + class wrapping + registry-based DLL discovery.
7. **Port `MacroGui.ahk`** — significant rewrite. AHK v2's `Gui` class API differs substantially from v1's named-GUI pattern. May warrant a different UI architecture entirely (e.g., one Gui object owning all tabs).

## When

Do not start AHK v2 parity work while the native MacrosApp path remains viable. Revisit this plan only if the native parity gate fails, a concrete AHK v2-only need appears, or the user explicitly reactivates the v2 port. If reactivated, treat this as a multi-week effort and break each numbered step above into its own sub-plan with tests and live verification.

## Critical files

- `Macros_v2.ahk` (current port)
- `Lib_v2/{Slots,Profiles,TrayMenu}.ahk` (current libs)
- `Macros.ahk` + `Lib/*` (reference implementation to port from)
- `tests/live/artifacts/` (validation harness output target — consider extending to v2)

## Verification

Each sub-plan should:
1. Add or extend a manual test in `TESTING.md` covering the newly ported feature.
2. Run `AutoHotkey64.exe /ErrorStdOut=UTF-8 /iLib '*' Macros_v2.ahk` and confirm exit code 0.
3. Live-exercise the feature in the same scenarios as v1.
4. Confirm cross-compatibility — slots recorded in v1 should still play back in v2.

End-to-end final-acceptance: a recording made on v1 plays back on v2 byte-identically across all event types, and v2 can record + save + replay with full controller + vJoy round-trip.
