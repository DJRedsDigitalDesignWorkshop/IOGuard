IOGuard 1.2.0 adds recovery for a playback stream that can remain stuck even when macOS shows the correct output device.

- Recover Sound Now in the menu and preferences.
- Optional bounded recovery after output/display changes and waking the Mac.
- Verified muted built-in fallback, short output handoff, cooldown, and return-state checks.
- Shared recovery engine in the app and legacy background guard 1.0.3.
- No audio recording or silence monitoring. Unexpected stalls with no system event can still require the manual action.

Universal app for Apple Silicon and Intel, macOS 13+. A brief playback interruption is possible during recovery. The release is signed with Developer ID but remains a draft until notarization is completed. See docs/RECOVERY.md and docs/VALIDATION.md for limits and verification.
