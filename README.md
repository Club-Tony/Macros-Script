# Macros-Script

Macros-Script is a Windows 11 macro recorder and playback tool designed to stay out of the way of a game. The primary product is the .NET WinForms `MacrosApp` backed by the native C `MacrosEngine`.

## Current product

`MacrosApp` starts in the notification area after first-run setup. Background Raw Input and controller polling observe configured bindings without consuming physical input. The adaptive in-game HUD is a normally painted, double-buffered borderless window. It is topmost, taskbar-hidden, and uses `WS_EX_NOACTIVATE`, so showing it does not take keyboard focus from the foreground game. Placement follows the foreground window's monitor rather than the primary display. Recording and playback stay compact while active; save results, warnings, and errors expand into controller-aware Play / Record Again / Cancel choices without a blocking message box. The full window remains available from the tray for setup and management.

First-run palette defaults:

- Keyboard: `Ctrl+Shift+Alt+Z`
- Controller: unset

Bindings for the palette, slash macro, autoclicker, turbo hold, pure hold, recorder, playback, and cancel can be single inputs or chords. Multi-input chords are recommended. Controller-enabled settings migrate to a dedicated `LB+RB+LT+RT+Y` Cancel chord when that chord is unused. Settings are stored atomically in `%LocalAppData%\Macros-Script\settings.json`; old slot/event files remain readable while new slot metadata records the controller-event count. Each game profile persists its exact `VJoy` or `VirtualXbox` output choice and whether the controller pulse has verified it.

Build and run:

```powershell
dotnet build MacrosApp\MacrosApp\MacrosApp.csproj
dotnet run --project MacrosApp\MacrosApp\MacrosApp.csproj
```

The managed build incrementally configures/builds `MacrosEngine` first, copies that exact DLL into the app output, and rejects stale native ABI/capability identifiers at runtime.

Run the automated gate from the workspace tooling checkout (maintained separately, not part of this repository):

```powershell
python tests\live\run_live_tests.py macros
python tests\live\run_live_tests.py macros --fixture visual
```

Visual baselines update only through the explicit visual fixture with `--update-baselines`, followed by human inspection. Do not run GUI fixtures unattended during gameplay.

## Runtime compatibility

- Keyboard and mouse playback uses Windows `SendInput`. It is subject to UIPI and can be ignored by elevated games or anti-cheat systems; this project does not pursue bypasses or stealth drivers. See [SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput).
- Controller input currently uses XInput. A future GameInput adapter is tracked because Microsoft describes GameInput as the modern superset of XInput, DirectInput, Raw Input, and HID. See [GameInput](https://learn.microsoft.com/en-us/gaming/gdk/docs/features/common/input/overviews/input-overview).
- Controller output supports vJoy and VirtualXbox through isolated backends. ViGEmBus is retired, so VirtualXbox compatibility is retained without deepening that dependency. See [ViGEmBus retirement](https://github.com/nefarius/ViGEmBus).
- Exclusive-fullscreen status rendering is not promised. The no-focus painted HUD is intended for windowed and borderless modes and follows the focused game's screen; a separate Vulkan status-only layer is deferred for exclusive-fullscreen compositors that still hide desktop overlays.

## Frozen legacy fallback

The original non-GUI AHK v1 implementation is vendored immutably inside this repository at commit `05226d8`:

`legacy\frozen-05226d8`

`legacy\frozen-05226d8\manifest.json` pins every runtime file by SHA-256, Git blob, and byte length. `tools\legacy\Launch-LegacyMacros.ps1` validates that manifest, resolves AutoHotkey v1.1.37.02 explicitly, and refuses to force-kill another Macros runtime. MacrosApp performs the same exclusion check in the opposite direction and only offers a graceful switch from AHK. Run `tools\legacy\Install-LegacyDesktopShortcut.ps1` once to create or retarget the Desktop shortcut.

## Archived AHK v2 experiment

`Macros_v2.ahk` and `Lib_v2/` are retained as an archived compatibility experiment, not the active product direction. New functionality belongs in `MacrosApp` and `MacrosEngine` unless a plan explicitly says otherwise.

See [TESTING.md](TESTING.md). Product plans live in the workspace tooling checkout, not this repository.
