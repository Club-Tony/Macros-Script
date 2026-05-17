# Native Engine — Stretch Items from Completed Plan

**Status:** In Progress (code complete 2026-04-28; all automatable verification green 2026-05-17 incl. .NET smoke; only physical-controller live parity gate pending)
**Created:** 2026-04-24
**Goal:** Implement the three deferred items the `native-controller-dll.md` plan called out as out-of-scope when it was marked complete on 2026-04-23.

## Context

The completed plan `Plans/Completed/native-controller-dll.md` shipped a working C# WinForms app (`MacrosApp/`) backed by a native C engine (`MacrosEngine/`). The 2026-04-24 debug session confirmed:

- `MacrosEngine/build-x64/test_engine.exe` passes 48/48 native tests.
- `MacrosApp/tools/MacrosApp.Smoke` passes the full record→persist→playback→Idle round-trip.
- `MacrosApp.exe` Debug build is current (rebuilt 2026-04-22).

Three items in the original plan's "Deferred" list are now eligible for follow-up work:

1. **Controller event recording in the engine** — `xinput_poller.c` does not yet emit `EVENT_CONTROLLER` records into `event_recorder.c`'s circular buffer. C# UI never sees controller events back from the engine.
2. **vJoy playback** — `MacrosEngine/src/event_player.c:163` drops `EVENT_CONTROLLER` events at playback time with `OutputDebugStringA("MacrosEngine: EVENT_CONTROLLER skipped (vJoy not implemented)\n")`.
3. **Playback-thread shutdown hardening** — current shutdown still relies on `TerminateThread` timeout fallback per the completed plan's note. Should be replaced with a cooperative cancellation event.

## Implementation Update — 2026-04-28

- E1, E2, and E3 are implemented in the native engine and MacrosApp wrapper.
- Automated verification now covers controller event recording/injection, controller event file round-trip, long playback cancellation, optional vJoy state/playback, app build, and the WinForms smoke record→persist→playback→Idle flow.
- Verified commands: `MacrosEngine/build-x64/test_engine.exe` passed 66/66, `dotnet build MacrosApp/MacrosApp/MacrosApp.csproj` passed with 0 warnings/errors, and `dotnet run --project MacrosApp/tools/MacrosApp.Smoke/MacrosApp.Smoke.csproj` passed with 6 saved events and final Idle state.
- vJoy was available and ready on the test machine during the native vJoy API test. No live controller was connected during the automated controller polling sample.
- Remaining work is the live parity gate: exercise a real mixed keyboard + mouse + controller recording through MacrosApp, verify vJoy output in `joy.cpl`, and compare against AHK v1 behavior on real hardware.

## Pre-Manual Automation Update — 2026-05-02

Additional pre-manual automation landed to shrink the manual gate. Reference: `~/.claude/plans/5-serene-gizmo.md`.

- Native engine suite expanded **66 → 96 passing checks** in `MacrosEngine/build-x64/test_engine.exe`.
- New separate suite **`test_xinput_diff.exe`: 37/37 passing** for the pure controller-state diff helpers (quantize, normalize, equality, neutrality, multi-field diff scenarios).
- Additions:
  - `test_playback_cancel_midsleep` (5 checks) — cancels during inter-event sleep, asserts return within 1s.
  - `test_ahk_v1_format` (19 checks) — loads `MacrosEngine/test/fixtures/ahk_v1_mixed.txt` and round-trips key/mouse/controller rows through `Engine_LoadEventsFromFile`, then plays back through the engine API.
  - `test_vjoy_disabled` (5 checks) — uses the new `MACROS_DISABLE_VJOY=1` env-var seam in `vjoy_output.c` to exercise the no-vJoy graceful path on a vJoy-equipped box.
  - `MacrosApp.Smoke` now asserts the persisted slot file contains a `C|...` row with the expected button bytes, and that `TrySetVJoyDeviceId(1)` + `TryGetVJoyState` round-trip without throwing.
- Refactor: extracted `quantize_thumb`, `quantize_trigger`, `normalize_for_recording`, `states_equal`, `state_is_neutral` from `xinput_poller.c` into a new `MacrosEngine/src/xinput_diff.h` (`static inline`) so the new test TU can include them without dragging in the engine exports.

What still needs human eyes (true manual gate):

- Real-stick parity feel with a physical Xbox/PS4 controller.
- Observable vJoy output in `joy.cpl` Properties visualizer during playback.
- Side-by-side AHK v1 vs MacrosApp playback with an AHK-v1-recorded controller slot.
- MacrosApp UI behavior when launched with `MACROS_DISABLE_VJOY=1` — engine no-crash is automated; the *visible UI warning* for the user is what's left.

## Live Hardware Triage - 2026-05-17

- DS4Windows was observed exposing the PS4 controller as a virtual X360/XInput device, and direct PowerShell XInput probing saw live changing stick values.
- The AHK v1 `Lib/XInput.ahk` wrapper initially read neutral values because `GetProcAddress` calls did not declare a `ptr` return type on 64-bit AutoHotkey. This truncated function pointers before `XInputGetState` calls.
- Fixed the AHK v1 wrapper signatures and confirmed an AHK probe can now read live XInput stick changes through `xinput1_4.dll`.
- vJoy availability still looks technically healthy from the native/MacrosEngine side, but the previous `zz_controller_smoke` slot is not a valid controller playback proof because it contains only mouse events and no `C|` controller rows.

AHK v1 baseline status after reload:

- **Tentatively complete for desktop/vJoy parity.** `Macros.ahk` was reloaded with the patched XInput wrapper active.
- Keyboard/mouse recording and playback were previously exercised with `zz_smoke_v1_kbm` and passed.
- A fresh controller slot, `zz_controller_xinput_pass`, saved with `has_controller=1`, `event_count=264`, and 74 `C|` controller rows.
- Replaying `zz_controller_xinput_pass` through AHK v1 moved vJoy successfully, and MacrosApp also replayed that AHK v1 slot through vJoy successfully.
- Caveat: this has not yet been proven inside an actual game. The current evidence is vJoy/desktop-level parity, not in-game behavior under a target title.

WinForms observation pass:

- `MacrosApp.exe` opens cleanly into the dark WinForms UI with status `Idle`, top-level macro buttons, settings, controller panel, `Engine: loaded`, and `Profile: Default`.
- The controller viewer is present and wired as a read-only XInput status panel.
- When launched directly from `MacrosApp/MacrosApp/bin/Debug/net8.0-windows`, the Saved Recordings list appeared empty. The code resolves the repo root by walking up from the executable path and then falling back to the current directory, so launch context affects whether repo-root `macros.ini` slots are visible. No C# changes were made because Claude is actively working on this area.

## Remaining Acceptance Gate

- Record a real mixed keyboard + mouse + controller macro in MacrosApp and confirm the saved event file contains `C|` controller rows.
- Restart MacrosApp and replay that mixed slot through vJoy; confirm output in `joy.cpl`.
- Run the AHK v1 controller macro in a real target game and confirm the target sees the intended controller behavior, not only vJoy movement.
- Load an AHK v1-recorded controller slot in MacrosApp and confirm controller playback maps through vJoy with no skipped-controller log messages.
- Temporarily run without vJoy available and confirm MacrosApp warns clearly while staying stable.
- After those manual checks pass, move this plan to `Plans/Completed/`.

## Solution / Scope

### E1 — Controller event recording (recommended first; simpler)

**Files:**
- `MacrosEngine/src/xinput_poller.c` — extend the polling loop to diff against previous `XINPUT_STATE` and emit `EVENT_CONTROLLER` records via `event_recorder.c` API
- `MacrosEngine/include/macros_engine.h` — add new exports `Engine_StartControllerRecording`, `Engine_StopControllerRecording`, `Engine_IsRecordingController`
- `MacrosApp/MacrosApp/NativeEngine.cs` — add `Try*` wrappers for the new exports
- `MacrosApp/MacrosApp/MainForm.cs` — wire controller-record toggle into the UI (probably a checkbox or hotkey alongside the existing keyboard/mouse recorder)
- `MacrosApp/MacrosApp/RecordingInputHook.cs` — confirm no overlap with existing keyboard/mouse hook
- `MacrosEngine/test/test_engine.c` — add test cases bringing suite to ~52
- `MacrosApp/tools/MacrosApp.Smoke/Program.cs` — extend to exercise controller-record path

**Reuse:** AHK v1 `Macros.ahk:1616+` (`RecorderSampleController`) for the diff-and-emit reference; `Lib/XInput.ahk:204+` for the deadzone + quantization constants (deadzone 2500 thumb / 5 trigger; step 256 thumb / 4 trigger).

### E2 — vJoy playback (do after E1)

**Files:**
- `MacrosEngine/CMakeLists.txt` — add vJoy SDK header + library link (or LoadLibrary at runtime to allow optional dependency)
- `MacrosEngine/src/event_player.c:163` — replace the skip with vJoy device acquire + `SetBtn`/`SetAxis`/`SetContPov` calls
- `MacrosEngine/include/macros_engine.h` — add `Engine_GetVJoyState`, `Engine_SetVJoyDeviceId` exports
- `MacrosApp/MacrosApp/NativeEngine.cs` — corresponding `Try*` methods
- `MacrosApp/MacrosApp/MainForm.cs` — settings UI for vJoy device id + POV mode

**Reuse:** `Lib/VJoy_lib.ahk` (~865 LOC) has working device-id, POV-mode, axis-existence, and button-count handling. Mirror its behavior in C — same registry-based DLL discovery, same thumbstick / trigger axis mapping (`MapThumbAxis`, `MapTriggerAxis`).

### E3 — Cooperative playback-thread shutdown

**Files:**
- `MacrosEngine/src/event_player.c` — add a manual-reset event handle (`HANDLE g_player_cancel`); poll it in the main playback loop with `WaitForSingleObject(handle, 0)` between events; replace the `TerminateThread` fallback with `SetEvent(g_player_cancel)` followed by `WaitForSingleObject(thread_handle, timeout_ms)`
- `MacrosEngine/src/engine.c` — initialize/destroy the cancel event in `Engine_Init` / `Engine_Shutdown`
- `MacrosEngine/test/test_engine.c` — add a "shutdown during playback" stress test that asserts thread exits cleanly

**Reuse:** Standard Win32 cooperative-cancel pattern. No external code to mirror.

## When

Should be picked up after the user signs off on the post-2026-04-24 commit (Phase F of the debug session). E1 first (simpler, unblocks controller use cases). E2 second (depends on E1's controller-event flow being verified end-to-end). E3 can land in parallel with either since it's independent of the controller path.

Each item should be its own focused PR with: native test added, C# smoke coverage extended, manual test in `TESTING.md`, and a live-exercise note.

## Critical files

- `MacrosEngine/include/macros_engine.h`
- `MacrosEngine/src/xinput_poller.c`, `event_recorder.c`, `event_player.c`, `engine.c`
- `MacrosEngine/test/test_engine.c`
- `MacrosApp/MacrosApp/NativeEngine.cs`, `MainForm.cs`, `RecordingInputHook.cs`
- `MacrosApp/tools/MacrosApp.Smoke/Program.cs`
- Reference: `Macros.ahk` controller polling + `Lib/VJoy_lib.ahk`, `Lib/XInput.ahk`

## Verification

- E1: native test_engine suite ≥ 52/52 pass; smoke harness records controller event and reads it back; live-exercise on Xbox/PS4 controller and confirm event format compatibility with AHK v1 `macros_events/*.txt` files.
- E2: load an existing AHK-recorded slot containing controller events into MacrosApp, play back, observe vJoy device output (joy.cpl); confirm no events skipped.
- E3: kick off a long-running playback, call shutdown — observe thread exits within configured timeout, no `TerminateThread` log warning.

End-to-end test for the full set: record a 60-second mixed keyboard + mouse + controller macro in MacrosApp, save, restart MacrosApp, replay against vJoy — observe identical output to AHK v1.

## Automated Verification Run - 2026-05-16

Unattended auto-test sweep (no live hardware). Tooling: CMake 4.2.3 + MinGW gcc 6.3.0.

- **Clean rebuild from current `feature/gui-panel` source: PASS.** Fresh out-of-tree configure + build (`cmake -S . -B build_ci -G "MinGW Makefiles"`, `cmake --build build_ci`) — all 7 engine TUs (engine, xinput_poller, event_recorder, event_player, event_format, vjoy_output, timing) compiled, `MacrosEngine.dll` + both test exes linked, exit 0. No warnings surfaced in build tail. (`build_ci/` is a throwaway CI dir, not committed.)
- **E1 (automatable portion) — `test_engine.exe`: PASS, 96 / 96.** Far exceeds the ≥52/52 bar; covers init/shutdown lifecycle, edge cases, double-shutdown safety, uninit-safety guards. Exit 0.
- **E1/E2 supporting — `test_xinput_diff.exe`: PASS, 37 / 37.** states_equal symmetry, neutral detection, sub-deadzone wiggle filtering, dpad-direction diffs. Exit 0.
- **MacrosApp.Smoke (.NET 8): KNOWN-SKIPPED → CLOSED 2026-05-17 (see next section).** No .NET SDK on this device at the time; predicted to be closeable by installing an SDK rather than by human hands — confirmed below.

**Still manual-only (unchanged — the real parity gate):** E1 live-exercise on a physical Xbox/PS4 controller, E2 observable vJoy output in `joy.cpl`, E3 long-playback shutdown observed against a live run, and the 60-second mixed end-to-end vs AHK v1. These require live input and the vJoy visualizer and cannot be automated away.

## Automated Verification Run - 2026-05-17

Closes the previously KNOWN-SKIPPED .NET smoke gate without any manual testing, exactly as the 2026-05-16 note predicted.

- **.NET 8 SDK provisioned automatically.** Installed user-scope (`~/.dotnet`, SDK 8.0.421, no admin/elevation) via the official `dotnet-install` script — no system change requiring the user.
- **`dotnet build MacrosApp/MacrosApp/MacrosApp.csproj` (net8.0-windows WinForms): PASS** — 0 warnings, 0 errors.
- **`MacrosApp.Smoke`: PASS (exit 0, "Smoke test passed.").** Evidence: `saved_count=6`; `controller_row=C|4096|16|20|512|-512|0|0|25` (the E1/E2 assertion — a controller event was recorded and persisted to the slot file in the expected `C|` byte format); `saved_slot=smoke-slot`; record→persist→playback→`final_status=Idle`/`final_state=Idle` round-trip clean (E3 cooperative shutdown — no hang, no `TerminateThread`); `vjoy_available=True vjoy_ready=False` → `start_status=Playing: smoke-slot (vJoy unavailable)` exercised the graceful vJoy-absent path (TESTING.md failure-mode item) without crashing.
- Re-confirmed alongside the 2026-05-16 native results: `test_engine.exe` 96/96, `test_xinput_diff.exe` 37/37 (re-run 2026-05-17, still PASS, exit 0).

**Net:** every automatable gate for E1/E2/E3 is now green. The sole remaining gate is the genuinely-physical one: live-exercise with a real Xbox/PS4 controller and an *enabled* vJoy device (here `vjoy_ready=False`, so observable `joy.cpl` deflection and true hardware recording fidelity still need a human + configured vJoy). Not marking the plan Completed on that basis — but no code or tooling work remains.
