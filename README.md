# Macros-Script

Macros-Script is a Windows 11 macro recorder and playback tool designed to stay out of the way of a game. The primary product is the .NET WinForms `MacrosApp` backed by the native C `MacrosEngine`.

## Current product

`MacrosApp` starts in the notification area after first-run setup. Background Raw Input and controller polling observe configured bindings without consuming physical input. The compact in-game palette is topmost, taskbar-hidden, and uses `WS_EX_NOACTIVATE`, so showing it does not take keyboard focus from the foreground game. The full window remains available from the tray for setup and management.

First-run palette defaults:

- Keyboard: `Ctrl+Shift+Alt+Z`
- Controller: unset

Bindings for the palette, slash macro, autoclicker, turbo hold, pure hold, recorder, playback, and cancel can be single inputs or chords. Multi-input chords are recommended. Settings are stored atomically in `%LocalAppData%\Macros-Script\settings.json`; existing slot and profile formats are unchanged.

Build and run:

```powershell
dotnet build MacrosApp\MacrosApp\MacrosApp.csproj
dotnet run --project MacrosApp\MacrosApp\MacrosApp.csproj
```

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
- Exclusive-fullscreen status rendering is not promised. The no-focus desktop palette is intended for windowed and borderless modes; a separate Vulkan status-only layer is deferred.

## Frozen legacy fallback

The original non-GUI AHK v1 implementation is preserved in a detached worktree at commit `05226d8`:

`%USERPROFILE%\Documents\.workspace\Repositories\Macros-Script-Legacy-05226d8`

Its launcher verifies both the exact commit and `Macros.ahk` blob, resolves AutoHotkey v1.1.37.02 explicitly, and refuses to force-kill another Macros runtime. MacrosApp performs the same exclusion check in the opposite direction and only offers a graceful switch from AHK. Run `Install-LegacyDesktopShortcut.ps1` in that directory once to create the Desktop shortcut. The shortcut is independent of whichever branch is active in this repository.

## Archived AHK v2 experiment

`Macros_v2.ahk` and `Lib_v2/` are retained as an archived compatibility experiment, not the active product direction. New functionality belongs in `MacrosApp` and `MacrosEngine` unless a plan explicitly says otherwise.

See [TESTING.md](TESTING.md) and [Plans/README.md](Plans/README.md).
