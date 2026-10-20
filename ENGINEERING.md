# Engineering

IOGuard uses AppKit for its menu-bar UI and Core Audio for device discovery and system defaults. No audio is recorded or processed. macOS 13 or later is the minimum; release binaries target arm64 and x86_64.

The app guards three properties on the Core Audio system object: default input, default output, and default system-sound output. Device IDs are ephemeral; app preferences store UIDs and resolve them against the current device list. Input/output stream capability must be checked independently. Missing preferred devices are reported and retried, without switching to an unrelated device.

Device/default notifications schedule restoration after one second on the main queue. Subsequent notifications cancel pending work. This gives audio clients time to adopt a route before restoring the preferred one. A five-second retry supports reconnect and wake recovery. Writes are made only when the default differs, and Core Audio failures are surfaced. Restoration may permit a brief audible switch. Apps can choose their own audio route, and AirPlay behavior needs listening verification.

Launch at login uses Apple's SMAppService.mainApp and reflects its actual status. Pause and Quit must stop enforcement. The historical LaunchAgent is a separate installation; two simultaneous guards could fight. Keep it until the app is ready, then migrate explicitly.

## Build and release
`./scripts/build.sh` builds the app; `SIGNING_IDENTITY='Developer ID Application: ...' ./scripts/sign.sh` signs it. `./scripts/package.sh` creates the DMG and checksum. A signing identity supplied to package.sh also signs the DMG. `NOTARY_PROFILE=profile ./scripts/notarize.sh` submits, staples, and validates the disk image. Never distribute signing private keys. Regenerate checksums after stapling.

The icon's editable drawing lives in scripts/make-icon.swift. AppIcon.icns contains every app icon size, while the menu-bar template reuses its speaker/lock motif. The DMG carries a custom file icon and a .VolumeIcon.icns for the mounted volume.

The legacy CLI's periodic fallback must also respect pending delayed restoration. Version 1.0.2 clears pending before enforcing and skips fallback while pending; run `./ua-audio-guard --self-test-timing` to verify scheduling without audio-device writes.
