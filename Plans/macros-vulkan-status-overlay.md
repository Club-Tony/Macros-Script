# Macros Vulkan status overlay

**Status:** Deferred
**Gate:** RAC Vulkan layer passes live emulator certification
**Created:** 2026-08-08

After the gate, evaluate a separate Macros-specific Vulkan implicit layer using only generalizable architecture from the certified RAC work. Version 1 is status-only: recording start/stop, playback, pause, and error. Use a process allowlist and current-user local IPC; keep the desktop no-focus palette as the interactive surface.

Do not use AHK `DllCall`, create RAC runtime integration, promise anti-cheat bypass, or implement this plan before the certification gate.
