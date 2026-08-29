# Repository guidance

## Product direction

Treat `MacrosApp` plus `MacrosEngine` as the primary product. It is a tray-first Windows 11 application whose main UX constraint is preserving foreground-game focus. The full WinForms window is for setup and management; the compact palette must remain `WS_EX_NOACTIVATE`, topmost, taskbar-hidden, and non-modal.

The AHK v1 `Macros.ahk` implementation on `main` is a frozen fallback at commit `05226d8`, materialized in `..\Macros-Script-Legacy-05226d8`. Do not modernize that frozen copy. `Macros_v2.ahk` and `Lib_v2/` are archived and should not receive new product work.

## Architecture

- `MacrosApp/MacrosApp/`: WinForms lifecycle, tray, onboarding, settings, bindings, palette, and local control channel.
- `MacrosEngine/`: native C recording/playback engine and stable ABI.
- `MacrosApp/MacrosApp/InputBindingRuntime.cs`: background Raw Input plus controller polling and chord latching.
- `%LocalAppData%\Macros-Script\settings.json`: versioned application and binding settings, saved atomically.
- `macros.ini`, `macros_events/*.txt`, `profiles.ini`: backward-compatible legacy data formats.
- `tools/legacy/`: canonical frozen-launcher and shortcut-installer scripts copied beside the detached worktree.

Keep XInput, SendInput, vJoy, and VirtualXbox isolated behind their existing runtime boundaries. Do not rewrite working engine code merely to adopt a new input API. GameInput is an investigation item. ViGEmBus is retired; retain compatibility without expanding the dependency.

## Safety and focus invariants

- Physical binding input passes through to the game; capture observes and does not suppress.
- A held chord fires once and rearms only after release.
- Exact duplicate action bindings are rejected.
- Palette show/hide must never change the foreground window.
- The frozen legacy runtime must never run concurrently with MacrosApp or another Macros AHK runtime.
- Runtime switching is graceful only. Never force-kill a process that may hold keys or virtual controls.
- Do not build anti-cheat bypass, elevated-input bypass, stealth-driver, or injection behavior.

## Validation

Use `python tests/live/run_live_tests.py macros` for the normal gate and `python tests/live/run_live_tests.py macros --fixture visual` for explicit committed UI fixtures. Baseline updates require `--update-baselines` and human review. Follow `TESTING.md` for the supervised game matrix. Do not run GUI fixtures unattended during gameplay.

Plans are indexed in `Plans/README.md`. Do not reopen completed historical plans unless the user explicitly changes their status.
