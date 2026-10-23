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

## Recurrence — October 20, 2026
TV power-on again sent Firefox audio through the TV return despite reported defaults being UA. Switching to built-in output and letting the guard restore UA reactivated COMPUTER and quieted ANALOG 5/6. Legacy v1.0.1 fallback could bypass pending debounce; CLI v1.0.2 fixes that race. Root cause of every AirPlay reroute is still unproven; a fresh TV power-on listening test is required.

## Recovery work — October 23, 2026
Silence returned while defaults still reported Universal Audio. A manual switch to built-in and guard restoration reactivated COMPUTER playback; user said sound returned. Added a shared bounded, output-only recovery engine in app1.2.0/background1.0.3, triggered by display/output changes and wake, plus manual recovery. No silence detection or audio capture. Auto cooldown60s and manual5s use one last-attempt timestamp. Live manual recovery completed; no guarantee of preventing stalls without system events. See docs/VALIDATION.md for proof levels.

User confirmed normal Apollo playback after the controlled manual recovery. The app recovery UI was visually accepted; legacy detection kept it paused.
Automatic TV-output selection recovery also completed on the final build; Sound returned to UA and COMPUTER carried playback. Full TV power-cycle and sleep/wake remain untested.
