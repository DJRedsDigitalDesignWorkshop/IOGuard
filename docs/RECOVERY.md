# Playback recovery

IOGuard 1.2.0 and legacy guard 1.0.3 share one output-recovery engine. This extends device selection with a bounded route reset based on the built-in-to-interface reset verified on the original Apollo setup.

With automatic recovery enabled, a changed output device, a changed output-device list, or waking the Mac schedules one attempt after the normal restoration settles. Automatic attempts are rate-limited, coalesced, and never run from the periodic default-device retry timer. A healthy stream can briefly pause when a real event triggers recovery.

Recovery requires a connected preferred interface and a built-in speaker device with a working mute control. It mutes the built-in device before using it for a short output handoff, then returns to the preferred interface and restores the built-in mute state. It never uses the TV, Bluetooth, or HDMI as the temporary device and never changes input for recovery. It verifies transitions and reports failures. If it cannot leave the temporary device safely, it keeps that device muted rather than risking a loud speaker burst.

The app provides **Recover Sound Now** and an automatic recovery checkbox. The legacy installed guard accepts a manual request through Recover-Sound.command (which signals the running guard rather than starting a second guard). Its automatic recovery can be disabled by setting IOGUARD_AUTO_RECOVER=0 in the LaunchAgent environment and reloading it. Diagnostics are written locally to ~/Library/Application Support/UniversalAudioGuard/guard.log.

This is event-based recovery, not silence detection. IOGuard does not record or inspect audio samples. An app-specific stall with no system event still needs the manual action. Selected device names and running processes cannot prove audible playback. No claim is made that every driver, application, or AirPlay failure is prevented.
