# Project memory

## Verified on October 17, 2026
- User's audio interface is named Universal Audio Thunderbolt.
- AirPlay display is 43in TCL Roku TV.
- The TV's analog audio output is physically connected to Apollo ANALOG 5/6.
- Firefox YouTube audio continued through the TV even when all macOS default-device properties said Universal Audio Thunderbolt. The Sound selection alone did not prove routing.
- Switching system output to MacBook Pro Speakers and back to Universal Audio Thunderbolt restored direct playback. The user confirmed it sounded correct.
- Guard v1.0.1 added a one-second delayed restore. A TV-output selection test restored Thunderbolt, activated Console's COMPUTER channel, and quieted ANALOG 5/6. The user subsequently reconnected screen sharing and said the fix worked.
- The CLI LaunchAgent is com.djred.universalaudioguard. Its executable is installed in ~/Library/Application Support/UniversalAudioGuard. This legacy service is kept until app migration is validated.
- Original CLI commits: 75f88ec (1.0.0), 42740bc (1.0.1).
- User requested IOGuard directly in Documents, a signable Mac app, GitHub downloads, project planning/engineering/memory files, and lock-over-speakers artwork for all icons including the DMG.

## Working assumptions to verify
- A device-change timing race is a plausible explanation; no root cause has been proven.
- Current app release work targets 1.1.0; live app-specific audio behavior is not yet verified.

## App preparation — October 19, 2026
- IOGuard 1.1.0 built for arm64 and x86_64, macOS 13+.
- Developer ID signatures on app and DMG verified. Custom icon flags and mounted payload verified.
- UI inspected with real Universal Audio devices; legacy-detection block kept the app paused. Original working audio guard remains installed.
- Source repository: https://github.com/DJRedsDigitalDesignWorkshop/IOGuard . Signed release prepared as a draft; notarization credentials need local user setup.
- No native app live-route, disconnected-device, or launch-at-login claim has been made; see docs/VALIDATION.md.
