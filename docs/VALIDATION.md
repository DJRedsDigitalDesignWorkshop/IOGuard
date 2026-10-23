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

## Recovery app 1.2.0 / background guard 1.0.3 — October 23, 2026
- Shared recovery engine and both entrypoints compile for arm64 and x86_64.
- Deterministic fake-backend tests pass: manual/automatic cooldowns, event bursts, missing preferred output, safe fallback eligibility, UID changes, failed return, and cancellation. Tests make no real audio-device writes.
- Legacy debounce self-test passes. CI's lipo argument order was corrected after inspecting the prior failed run.
- Initial live manual-request test exposed a startup signal race; fixed by publishing a PID readiness file and requiring the command to match the running service before signaling. Subsequent live manual recovery completed, the process stayed running (one launch), and Universal Audio input/output/system defaults remained selected.
- Apollo COMPUTER and output meters showed playback after the controlled recovery; ANALOG 5/6 was quiet. This verifies routing observations, not listening or automatic silence detection.
- Updated app and DMG signatures validate. Native recovery controls were visually inspected: checkbox, interruption explanation, manual button, and status fit the window. Legacy detection correctly disables the native guard to avoid duplicate enforcement. The original service remains the active guard; no native-app migration has occurred.
- Full TV power-cycle and wake acceptance remain pending. Notarization profile IOGuard is still absent; the GitHub release remains a draft.
- User confirmed sound was normal after the controlled manual recovery.
- Cleanup-failure tests additionally verify that a failed mute restoration or unknown output produces a final failed status, rather than a misleading success.
- Final live automatic test: selecting 43in TCL Roku TV caused logged output-change recovery to complete; Sound returned to Universal Audio, COMPUTER and output meters were active, and ANALOG 5/6 was quiet. No full power-cycle or wake was performed.
