# Testing IOGuard

Use a quiet, controlled playback source and record the app, macOS version, and interface. Never run the original LaunchAgent and the app simultaneously.

## Build checks
Run scripts/build.sh, inspect both Mach-O architectures, validate Info.plist, and verify the bundle signature. `build/IOGuard.app/Contents/MacOS/IOGuard --diagnose` reads devices/defaults without changing them.

## App controls
Select input and output devices and confirm those preferences survive quitting/reopening. Pause, change the default manually, and confirm it stays changed. Resume and confirm the preferred defaults return. Close/reopen the settings window. Enable/disable launch at login and confirm the system-reported status.

## Device lifecycle
Disconnect the preferred interface: the app should report it missing without choosing another preference. Reconnect it: the same UID should be selected. Do not assume that a reused numeric device ID is the same interface.

## AirPlay acceptance
While Firefox plays audio, connect an AirPlay screen, and verify actual sound returns to the preferred interface. For the original Apollo setup, the TV's physical return on ANALOG 5/6 should quiet and the COMPUTER channel should show playback. A selected Sound name alone is not sufficient. Verify input and system-sound output as separate defaults.

## Distribution
Mount the DMG, inspect the app icon, mounted-volume icon, Applications shortcut, and readme. Verify the universal app signature and, for public releases, accepted notarization plus the stapled ticket. Development CI artifacts are ad-hoc signed and are not public release installers.
