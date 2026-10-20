# IOGuard

A small macOS menu-bar app by **djred** that keeps your preferred audio input and output selected when AirPlay, screen sharing, displays, or reconnects change the defaults.

Choose your interface, enable the guard, and optionally launch it at login. IOGuard restores input, output, and system-sound output after a one-second delay. It waits when a preferred device is disconnected and provides pause/resume controls for intentional changes.

Requires macOS 13 or later. Universal release builds support Apple Silicon and Intel. No audio drivers, recordings, accounts, or network service are involved.

## Install
Download the versioned DMG from [GitHub Releases](https://github.com/DJRedsDigitalDesignWorkshop/IOGuard/releases), drag IOGuard to Applications, and open it. Configure your preferred devices in Settings. See [installation instructions](docs/INSTALL.txt) and [migration from the original script](docs/MIGRATION.md).

The guard may allow a brief switch before restoring the defaults. Apps with their own selected outputs can behave independently. Check actual playback when testing AirPlay; a selected device name alone is insufficient verification.

## Build
```sh
./scripts/build.sh
./scripts/package.sh
```
Requires Xcode command-line tools and the macOS SDK. Rebuild artwork with `swift scripts/make-icon.swift` if needed. See [signing and notarization](docs/SIGNING.md), [engineering](ENGINEERING.md), [plan](PLAN.md), and [changelog](CHANGELOG.md).

## Original script
AudioGuard.swift, Install.command, Uninstall.command, and ua-audio-guard preserve the original user-verified Universal Audio Thunderbolt guard. Its version is 1.0.2; the native app starts at 1.1.0. Run only one guard at a time.

Author: djred.
