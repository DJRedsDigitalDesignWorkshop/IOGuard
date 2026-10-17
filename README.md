# Universal Audio Guard 1.0.1
Author: djred

Keeps macOS default input, output, and system sound output on the exact device named Universal Audio Thunderbolt. Watches Core Audio changes and retries every five seconds. A switch may still occur briefly before restoration. When the interface is disconnected or its name is ambiguous, the guard leaves defaults alone. Apps with their own explicit audio device settings remain responsible for those settings.

Double-click Install.command to install for the current user and start at every login. Double-click Uninstall.command to stop and remove it. While running, it also reverses manual selection of other default audio devices.

Source: AudioGuard.swift. Build: swiftc AudioGuard.swift -o ua-audio-guard
List devices: ./ua-audio-guard --list
Apply once: ./ua-audio-guard --once

The included executable is for Apple Silicon Macs. No additional audio utility is required.

Version 1.0.1 delays restoration one second after device-change notifications to allow audio clients to finish switching first. Actual Firefox/AirPlay behavior requires listening verification.
