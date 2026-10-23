# Changelog

## 1.2.0
- Add shared, bounded output-route recovery after display/device changes and wake.
- Add Recover Sound Now and an automatic recovery preference.
- Verify a muted built-in fallback before a short handoff; return to the preferred interface with failure reporting and cooldown.
- Fix universal-binary verification argument order in CI.

## 1.1.0
- Native macOS menu-bar app with selectable preferred devices, status, pause/resume, and optional launch at login.
- Universal Apple Silicon/Intel build and drag-to-Applications DMG.
- Lock-over-speakers app and installer artwork.
- Signing, notarization, release, and contributor documentation.

## 1.0.3 — Legacy guard recovery
- Use the same recovery engine as the app, including wake/output-change triggers.
- Add a manual recovery command and local diagnostics.
- Keep periodic device enforcement separate from route-reset attempts.

## 1.0.2 — Legacy guard patch
- Prevent the fallback timer from bypassing a pending one-second restoration.
- Clear completed delayed work so idle retry continues.
- Add a hardware-free timing self-check.

## 1.0.1
- Restore preferred defaults one second after device-change notifications.
- Verified Firefox routing after AirPlay TV output selection and user-confirmed screen-sharing reconnection.

## 1.0.0
- Initial Universal Audio Thunderbolt Core Audio guard and per-user LaunchAgent.
