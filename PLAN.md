# IOGuard plan

## Objective
Turn the user-verified Universal Audio Guard into a downloadable macOS menu-bar application with selectable input/output devices, pause/resume, and optional launch at login.

## Delivery steps
- [x] Move existing source and Git history to Documents/IOGuard.
- [x] Record engineering constraints and working audio-routing evidence.
- [x] Build native app settings and menu-bar controls.
- [x] Create matching lock-over-speakers artwork for all app and installer icons.
- [x] Compile universal app and inspect UI; live app restoration and login testing remain pending.
- [x] Package a Developer ID signed drag-to-Applications DMG.
- [ ] Notarize and staple if a usable saved profile is available.
- [x] Create GitHub repository and push source.
- [ ] Publish notarized release (signed draft available; Apple credential setup pending).

## Acceptance
Guard defaults by stable device UID; handle unplugged/ambiguous devices without choosing another device. Preserve the one-second restoration delay. Distinguish static build checks, UI verification, live audio tests, signing, and notarization. Keep the existing installed guard working until migration is deliberate.
