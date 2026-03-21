# UI_PATTERNS.md — Tooltip Copy Conventions & Dialog Specs

This document defines the standard UI text, timing, and interaction patterns used throughout Macros-Script. Follow these when adding new features.

---

## Tooltip Behavior

Tooltips appear at a **fixed bottom-right position** (320px from right edge, 100px from bottom) via `ShowMacroToggledTip()`. This prevents tooltips from obscuring gameplay.

All tooltips append `" (SendMode: X)"` automatically.

### Tooltip Copy Spec

| Trigger | Copy | Duration | Early-hide |
|---------|------|----------|------------|
| Start recording (keyboard) | `Recording macro... F5 to stop` | 3s | yes |
| Start recording (client-lock) | `Recording macro (client-locked: game.exe)... F5 to stop` | 3s | yes |
| Start recording (controller) | `Recording controller... (L1+L2+R1+R2+A to stop)` | 3s | yes |
| Stop recording, save prompt | (InputBox appears — no additional tip) | — | — |
| Saved successfully | `Saved 'slotname' ✓ \| F12 to play` | 3s | no |
| Save canceled (no name) | `Recorded N events (not saved) — F12 to play` | 3s | no |
| Save failed | `Save failed — check disk space! Ctrl+Esc to reload` | 5s | no |
| Playback start (infinite) | `Playing recorded macro (infinite loops, F12 to stop)` | persistent | no |
| Playback start (N loops) | `Playing recorded macro (N loops, F12 to stop)` | persistent | no |
| Playback paused | `Playback paused` | 1s | no |
| Playback resumed | `Playback resumed` | 1s | no |
| Playback complete | `Playback complete (N loops)` | 2s | no |
| Until-key loop start | `Looping until 'key' pressed \| Esc also stops` | 3s | no |
| Sequence step | `Sequence step N of M: 'slotname' \| Esc to stop` | persistent | no |
| Sequence complete | `Sequence complete` | 2s | no |
| Sequence stopped | `Sequence stopped` | 1.5s | no |
| Profile detected | `Profile loaded: gamename (SendPlay)` | 2s | no |
| No profile match | `No game profile matched — using Default` | 2s | no |
| Profile added | `Profile 'name' added` | 2s | no |
| SendMode cycled | `SendMode: X (Ctrl+Alt+P to cycle)` | 2s | no |
| Debug ON | `Debug mode ON` | 2s | no |
| Debug OFF | `Debug mode OFF` | 2s | no |
| Speed changed | `Playback speed: Nx` | 1.5s | no |
| Loop mode changed | `Loop mode: X` | 2s | no |
| Slot loaded from tray | `Slot 'slotname' loaded \| F12 to play` | 2s | no |
| Import complete | `Imported N macros` | 2s | no |
| Export complete | `Exported N slots to file` | 2s | no |
| Import invalid | `0 macros imported — invalid file format` | 3s | no |
| Macro Toggled Off | `Macro Toggled Off (SendMode: X) - Esc to exit` | 3s | yes |
| First run | `Macros-Script ready! \| Right-click tray for macros \| or Ctrl+Shift+Alt+Z for menu` | 5s | no |

---

## Dialog Specs

All dialogs are `InputBox` with these titles (exactly — `ControllerInputBoxHelper` matches on title):

| Dialog title | Prompt text | Default value | Timeout |
|-------------|-------------|---------------|---------|
| `Save Recording` | `Name this recording:` | `untitled` (or last slot name) | 30s |
| `Loop Until Key` | Inline via `Input` command | — | 15s |
| `New Profile` | `Profile name (e.g. RDR2):` | (blank) | 30s |
| `Game Process` | `Process name (e.g. RDR2.exe):` | `.exe` | 30s |
| `Slot Conflict` | `'slotname' already exists. Overwrite? (Y/N)` | `N` | 20s |
| `Build Sequence - Step N` | `Available slots:\n...\nEnter slot name (blank=done, Cancel=abort):` | (blank) | 60s |
| `Step N Delay` | `Delay after 'slotname' (ms, 0=none):` | `0` | 30s |
| `Save Sequence` | `Name this sequence:` | `sequence1` | 30s |
| `Autoclicker` | `Enter click interval in ms (default 50).` | `50` | 10s |
| `Turbo Hold` | `Input key to turbo (hold then press; 15s timeout).` | — | 15s |
| `Pure Key Hold` | `Input key to hold down (15s timeout).` | — | 15s |
| `Playback Loops` | `Enter playback loop count.\n...` | (blank = infinite) | 15s |

---

## Tray Menu Layout

```
[Macros-Script tray icon]  right-click:
  ─────────────────────────────────────────
  Slot: <current slot name>    (disabled header)
  Profile: <name> (Send<mode>) (disabled header)
  ─────────────────────────────────────────
  Slots ▸
    [slot1]
    [slot2]
    ─────────
    New Recording (F5)
    Export All Slots
    Import Slots
  Sequences ▸
    [seq1]
    ─────────
    Build Sequence
  Profiles ▸
    Default ✓
    [game profile]
    ─────────
    Add Profile
  ─────────────────────────────────────────
  Playback Speed ▸   [0.5x]  [1x ✓]  [2x]
  Loop Mode ▸        [Fixed Count]  [Infinite ✓]  [Until Key]
  ─────────────────────────────────────────
  Open Macro Menu
  Debug: OFF (Ctrl+Alt+D)
  Reload Script
  ─────────────────────────────────────────
  Exit
```

---

## Icon State Machine

```
     ┌─────────────────────────────────┐
     │    IDLE (grey M icon)            │ ◄── startup / stop / reload
     └──┬───────────────────────────────┘
        │ StartRecorder()
        ▼
     ┌─────────────────────────────────┐
     │   RECORDING (red R icon)         │
     └──┬───────────────────────────────┘
        │ FinalizeRecording() / Esc / stop
        ▼
     ┌─────────────────────────────────┐
     │   PLAYING (green P icon)         │ ◄── F12 resume / StartPlayback
     └──┬───────────────────────────────┘
        │ F12 pause
        ▼
     ┌─────────────────────────────────┐
     │   PAUSED (yellow icon)           │
     └─────────────────────────────────┘
```

Icon files: `icons/idle.ico`, `icons/recording.ico`, `icons/playing.ico`, `icons/paused.ico`

---

## SendMode Reference

| Mode | AHK Command | Best for |
|------|------------|----------|
| `Input` | `SendInput` | Default — fast, works in most apps |
| `Play` | `SendPlay` | Games that block SendInput (e.g. older DirectInput) |
| `Event` | `SendEvent` | Games that block both Input and Play; slower but more compatible |

Cycle with `Ctrl+Alt+P`. Stored globally in `sendMode`. Profile can override at load time.

---

## Data File Formats

### macros.ini (metadata only — DO NOT store events here)
```ini
[Slots]
count=2
slot_1=looting_loop
slot_2=fast_loot

[looting_loop]
event_count=847
coord_mode=screen
recorded=2026-03-19

[Sequences]
count=1
seq_1=farming_run

[seq_farming_run]
step_count=2
step_1_slot=looting_loop
step_1_delay=500
step_2_slot=fast_loot
step_2_delay=0
```

### macros_events/slotname.txt (bulk event data)
```
K|a|down|0
K|a|up|120
M|800|600|50
C|4096|0|255|0|0|0|0|50
```
Format per line:
- `K|code|state|delay_ms` — keyboard key (state: `down` or `up`)
- `mousebtn|code|state|delay_ms` — mouse button
- `M|x|y|delay_ms` — mouse move (screen coords)
- `C|buttons|lt|rt|lx|ly|rx|ry|delay_ms` — controller state

### profiles.ini
```ini
[Default]
SendMode=Input
vJoyDeviceId=1
vJoyPovMode=

[RDR2]
Process=RDR2.exe
SendMode=Play
vJoyDeviceId=2
vJoyPovMode=Continuous
```
