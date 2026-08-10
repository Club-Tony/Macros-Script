# Nonintrusive native runtime and frozen legacy launcher

**Status:** Awaiting Manual Action
**Branch:** `feature/gui-panel`
**Created:** 2026-08-08

## Goal

Make MacrosApp the tray-first, focus-preserving primary runtime while preserving the original non-GUI AHK v1 implementation as a frozen fallback independent of the active branch.

## Implemented in the current worktree

- Tray-owned application lifetime, first-run launch-binding setup, and hidden subsequent startup.
- Versioned atomic settings and customizable keyboard/controller chords for all actions.
- Background Raw Input and controller polling with duplicate rejection and release latching.
- Compact 15-second `WS_EX_NOACTIVATE` palette and current-user status/shutdown pipe.
- Detached legacy worktree pinned to `05226d8`, plus commit/blob/runtime-verifying launcher and manual Desktop shortcut installer.
- Deterministic smoke and visual-fixture coverage, including a foreground sentinel.

## Automated validation completed

- Native engine: 105/105.
- .NET build: zero warnings and zero errors.
- Settings/binding, foreground-sentinel, tray lifecycle, control-pipe shutdown, recording/playback, and controller-output smoke: passed.
- Tooltip source validation: 14/14.
- Visual comparisons for onboarding, bindings, and palette idle/recording/playback/error: passed at 0.0000% difference after baseline inspection.
- Foreground sentinel passed three consecutive focused stress runs after moving palette handle creation out of the gameplay-time show path.
- Frozen worktree commit/blob, AHK v1.1.37.02 resolution and syntax, launcher/installer validation, and canonical/worktree launcher hashes: passed.
- AutoHotkey runtime switching posts the hidden script window's native Exit command; a disposable AHK v1 probe confirmed its `OnExit` cleanup ran and the process exited without force-kill.
- Native startup now detects Macros AHK hidden control windows, offers the reverse graceful switch, waits up to five seconds, and cancels without force-kill if shutdown does not complete. Both interactive paths were exercised against frozen legacy PID 26220: cancellation left AHK as the sole runtime, while an approved switch gracefully removed AHK and started MacrosApp as the sole runtime.

## Manual completion steps

- Desktop shortcut refresh completed and independently inspected on 2026-08-08: target is Windows PowerShell, arguments include `-WindowStyle Hidden` and the frozen-worktree launcher path, and the working directory is the frozen worktree.
- Refreshed shortcut launch produced the user-visible `Macros legacy is active` notification, confirmed by the user on 2026-08-08. A repeated launch left frozen legacy PID 60080 active as the sole Macros runtime across three process checks over approximately five seconds.
- Run the windowed, borderless, and exclusive-fullscreen game matrix in `TESTING.md`.
- Confirm real controller chord capture and disconnect/reconnect on target hardware.

## Constraints

No merge, commit, or push to `main` without separate authorization. No forced runtime termination, input-protection bypass, stealth driver, or legacy data/ABI break.
