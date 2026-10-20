# Validation

## Original guard v1.0.1 — October 17, 2026
Verified with Firefox YouTube playback, Universal Audio Thunderbolt, and 43in TCL Roku TV AirPlay. User confirmed direct Apollo playback and a subsequent screen-sharing reconnection worked. TV analog output feeds Apollo ANALOG 5/6; direct computer audio appears on COMPUTER.

## Native app v1.1.0 — October 19, 2026
- Universal release build succeeded: x86_64 and arm64; deployment target macOS 13.
- Developer ID Application signature verified with hardened runtime and trusted timestamp.
- Read-only --diagnose identified live audio devices by UID and confirmed current input, output, and system output as Universal Audio Thunderbolt.
- Preferences window was visually inspected: matching artwork, readable controls/status, preferred input/output, launch-at-login control.
- Legacy migration safeguard verified: original LaunchAgent detected; app paused and Enable disabled. Existing audio defaults remained unchanged.
- Shell syntax checks and git diff --check passed.
- DMG checksum validated with hdiutil; app and DMG signatures verified. Mounted payload contained the signed app, Applications link, readme, and matching .VolumeIcon.icns. Finder custom-icon flags were present on the mounted volume and local DMG file.

Not yet verified: native app enforcement with legacy service removed, preference persistence after a device change, disconnect/reconnect, actual launch at login, and native app AirPlay recovery. The original CLI guard remains the user's active audio guard. Notarization is pending a usable notarytool keychain profile; keep release as a draft.

## Legacy guard v1.0.2 — October 20, 2026
- Compiled cleanly and independently reviewed. Hardware-free timing test passes: pending debounce blocks fallback, repeated notifications delay restoration, and fallback resumes afterward.
- Installed executable matches the built v1.0.2 binary; LaunchAgent restarted successfully. Previous v1.0.1 executable retained locally as rollback backup.
- Current playback was restored from TV return to Apollo COMPUTER before installing the patch. A new full TV power-on test remains required; the timing defect is verified, but its role in every AirPlay failure is unproven.
- Post-install TV-output selection test restored Universal Audio; Console COMPUTER showed playback and ANALOG 5/6 was quiet. This tests selecting an already-connected TV, not a full power-cycle.
