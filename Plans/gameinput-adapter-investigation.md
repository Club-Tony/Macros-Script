# GameInput adapter investigation

**Status:** Deferred
**Created:** 2026-08-08
**Gate:** Tray-first runtime completes supervised keyboard/controller acceptance

## Question

Can a GameInput-backed adapter broaden reliable keyboard, mouse, HID, and controller observation without breaking the native engine ABI, legacy data formats, physical input pass-through, or the current XInput path?

## Investigation

1. Re-check current Microsoft GameInput redistribution, packaging, desktop support, and Store requirements.
2. Build an isolated read-only proof of concept for controller 0 and compare latency, reconnect behavior, device identity, triggers, D-pad, stick clicks, and chord latching against the current XInput polling stream.
3. Evaluate keyboard, mouse, and generic HID coverage without suppressing physical input or requiring elevated/driver behavior.
4. Define an input-source interface that permits Raw Input/XInput and GameInput implementations to coexist behind a feature flag.
5. Add deterministic adapter-contract tests plus supervised device coverage before considering a default change.

## Constraints

- No rewrite of working SendInput, XInput, vJoy, or VirtualXbox behavior during the investigation.
- No native-engine ABI or legacy slot/profile-format break.
- No anti-cheat bypass, stealth driver, kernel component, or input suppression.
- GameInput adoption requires a measured benefit and a rollback path; otherwise retain the current adapters.
