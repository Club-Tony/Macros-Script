# AHK v2 Port Completion

**Status:** In Progress (implementation complete; slot-metadata parity fix + parse smoke green 2026-05-20; live controller/vJoy verification pending)
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

## Verification Update - 2026-05-09

- Ran `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe /ErrorStdOut=UTF-8 /iLib '*' Macros_v2.ahk`; exit code 0.
- Confirmed vJoy is installed under `C:\Program Files\vJoy\`, but did not perform live controller/vJoy output verification in this session.
- Removed stale `Macros_v2.ahk` comments that still described controller recording and vJoy playback as unported.
- This plan remains active until the manual controller/vJoy parity gate is exercised.

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

## Historical starting gaps

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

## Current parity status

| Component | Status |
|-----------|--------|
| `Lib_v2/MacroGui.ahk` | Implemented - 4-tab GUI panel for Main, Slots, Sequences, and Settings |
| `Lib_v2/Recorder_Keys.ahk` | Implemented - v2 `#HotIf` pass-through map for keyboard/mouse recording |
| `Lib_v2/XInput.ahk` | Implemented - DllCall/Buffer wrapper plus debug state readout |
| `Lib_v2/VJoy_lib.ahk` | Implemented - vJoy device, axis, button, and POV wrapper |
| `Lib_v2/Debug.ahk` | Implemented - `DebugTip()` / `DebugLog()` helpers |
| Controller polling loop | Implemented - `ControllerComboPoll()` plus L1+L2+R1+R2 combos |
| Turbo Hold (F3) | Implemented - keyboard and controller binding flow |
| Pure Hold (F4) | Implemented - keyboard and controller binding flow |
| Slot target-window metadata | Implemented 2026-05-20 - `has_controller` + `target_exe`/`target_client_w`/`target_client_h` persisted and restored across save, load, rename, export, and import |
| Live controller/vJoy round-trip | Pending manual hardware verification |

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

## Automated Verification Run - 2026-05-16

Unattended auto-test sweep (no live hardware). Tooling: AutoHotkey64 v2.0.18.

- **Verification step 2 — AHK v2 parse/syntax check: PASS.** `Macros_v2.ahk` validated via `AutoHotkey64.exe /ErrorStdOut /iLib <tmp> Macros_v2.ahk` with working dir = repo root (so `Lib_v2\` `#Include`s resolve). Result: exit code 0, empty stderr. Confirms the plan's prior parse-smoke claim. (Note: AHK exit codes are unreliable when launched via MSYS-bash pipes — verified through PowerShell `Start-Process -PassThru` with redirected stderr; calibrated against known-good and deliberately-broken probe scripts.)
- **Verification step 4 — v1→v2 slot cross-compatibility, static format-equivalence diff (partial automatable substitute for the live byte-identity gate):**
  - **Event-data file (`macros_events/*.txt`): byte-identical by construction. PASS.** `Lib/Slots.ahk` and `Lib_v2/Slots.ahk` use the same write (`FileAppend line + "\n"` per event) and the same read (`StrSplit/loop-parse on "\n", strip "\r", Trim, skip blank and ";"-comment lines`). A v1-recorded events file round-trips through v2 identically.
  - **Slot INI metadata: DIVERGENCE — RESOLVED 2026-05-20 (see "Slot Metadata Parity Fix - 2026-05-20" below).** *[Original 2026-05-16 finding follows; note its "fuller timestamp" claim is corrected in the resolution section.]* v1 `SaveSlot` persists `event_count, coord_mode, has_controller, target_exe, target_client_w, target_client_h, recorded`; the v2 `Lib_v2/Slots.ahk` save path writes only `event_count, coord_mode, recorded`, and `recorded` is date-only (`FormatTime(,"yyyy-MM-dd")`) vs v1's fuller timestamp. Event playback is unaffected (the event stream is identical), but **target-window remap metadata and controller-presence flag are not written by v2** — verify during the live parity gate whether v2 still remaps coordinates correctly for a v1 slot recorded against a specific target window.

**Still manual-only (unchanged):** verification steps 1 (TESTING.md authoring) and 3 (live-exercise), plus the live controller + vJoy round-trip and a true byte-identical comparison of a freshly v1-recorded slot — these require live input capture and hardware and remain the open parity gate.

## Slot Metadata Parity Fix - 2026-05-20

Closed the slot-metadata divergence flagged in the 2026-05-16 run. The v2 slot save path now persists and restores the full v1 metadata set.

- **`Lib_v2/Slots.ahk` `Save()`** — writes `has_controller`, `target_exe`, `target_client_w`, `target_client_h` alongside `event_count`/`coord_mode`/`recorded`. Target keys are filled from the `recorderTarget*` globals when `coord_mode = "client"`, zero/empty otherwise — mirroring v1 `SlotSave`.
- **`Lib_v2/Slots.ahk` `ExportAll()` / `ImportAll()`** — carry all four keys through the export file and back, matching v1's export format.
- **`Macros_v2.ahk` `LoadRecorderSlot()`** — reads `target_exe`/`target_client_w`/`target_client_h` back and restores `recorderTargetExe`/`recorderTargetClientW`/`recorderTargetClientH`.
- **`Lib_v2/MacroGui.ahk` rename path** — loads the source slot before re-saving so a renamed `client`-mode slot keeps its target-window context instead of stale globals.

**Why it mattered (functional bug, not cosmetic):** before the fix, a saved `client`-coord-mode slot loaded in v2 left `recorderTargetExe` empty; `RecorderPlayNext`'s focus check (`activeExe != recorderTargetExe`) then stopped playback immediately with "focus lost", making client-mode slots effectively unplayable after a load-from-disk.

**Correction to the 2026-05-16 note:** v2's `recorded` field (`FormatTime(, "yyyy-MM-dd")`) is **identical** to v1 — v1's `SlotSave` also writes date-only (`FormatTime, nowStr,, yyyy-MM-dd`). The earlier "v1's fuller timestamp" claim was wrong; there is no `recorded` timestamp divergence.

**Verification:** `AutoHotkey64.exe /validate /ErrorStdOut Macros_v2.ahk` exits 0 with empty stderr after all six edits (calibrated against known-good and deliberately-broken probes). The save→load→playback round-trip with a real `client`-mode slot remains part of the open live controller/vJoy gate.
