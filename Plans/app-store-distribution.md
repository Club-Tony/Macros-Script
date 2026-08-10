# App-store distribution and gamer-market pathway

**Status:** Deferred
**Created:** 2026-08-08
**Gate:** Nonintrusive native runtime completes supervised game acceptance and has a stable release build

## Goal

Evaluate a credible path for distributing MacrosApp through the Microsoft Store and other suitable PC software marketplaces, positioning it for gamers and people who want straightforward desktop macros.

## Product positioning to validate

- Tray-first macros that do not interrupt foreground gameplay.
- Simple onboarding and safer multi-input keyboard/controller chords.
- Keyboard, mouse, and controller recording/playback in one native Windows app.
- Transparent compatibility boundaries: no anti-cheat bypass, stealth driver, or guaranteed support for protected/elevated games.
- A useful free/core experience before considering paid tiers or one-time purchase pricing.

## Microsoft Store investigation

1. Audit the current Microsoft Store policy and submission requirements at execution time.
2. Prototype signed MSIX packaging for `MacrosApp`, `MacrosEngine`, icons, protocol/shortcut behavior, uninstall, and per-user settings.
3. Determine whether vJoy/ViGEm-related optional integrations can remain external and optional without creating Store certification or driver-installation problems.
4. Confirm that background Raw Input, tray-only startup, global bindings, named-pipe control, and startup registration behave correctly in the selected packaging model.
5. Prepare privacy, support, accessibility, age-rating, telemetry, licensing, and data-use declarations. Prefer no telemetry by default.
6. Run Windows App Certification Kit and a clean-machine install/update/uninstall matrix before submission.
7. Create Store-ready screenshots and copy from the committed visual fixtures, supplemented by supervised gameplay-safe promotional captures.

## Other channels to compare

- Direct signed download with an installer and automatic update strategy.
- `winget` for discoverability and scriptable installation.
- Steam's software catalog if its current rules, audience fit, commercial terms, and controller expectations justify the overhead.
- itch.io or another lightweight creator marketplace for early paid/beta distribution.
- Do not assume another store is suitable; re-check current policies, fees, signing, update, refund, and prohibited-software rules before choosing one.

## Release engineering prerequisites

- Stable semantic versioning and reproducible release builds.
- Code-signing certificate and protected signing workflow.
- SBOM, dependency/license inventory, native DLL provenance, and vulnerability checks.
- Crash-safe key/controller release behavior and a documented recovery path.
- Store-safe first launch, update migration, rollback, and uninstall cleanup.
- Support page, compatibility matrix, known limitations, and concise in-app diagnostics.
- Separate the frozen AHK v1 fallback from the packaged Store product; it is a developer/user recovery artifact, not a Store payload.

## Marketing research backlog

- Interview gamers and general PC macro users about setup friction, controller bindings, profiles, and the no-focus promise.
- Compare against current macro utilities on simplicity, game interruption, controller support, trust, price, and onboarding.
- Test names, iconography, screenshots, short demo video, and messaging without implying universal game or anti-cheat compatibility.
- Decide whether profiles/templates can become a safe sharing ecosystem without executable-script distribution.

## Exit criteria

Produce a go/no-go decision with current policy citations, packaging proof, certification results, channel economics, launch scope, pricing hypothesis, support burden, and a release checklist. Store submission or commercial release requires separate authorization.
