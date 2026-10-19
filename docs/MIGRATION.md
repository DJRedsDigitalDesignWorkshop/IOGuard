# Migrating from the original script

The original guard and app are separate installations. Keep the original working guard until you are ready to test the app.

1. Quit IOGuard or pause it.
2. In this project, run `./Uninstall.command` to stop/remove the legacy per-user LaunchAgent.
3. Copy the built app to Applications, open it, select your preferred devices, and enable it.
4. Play audio in Firefox, connect the TV through screen sharing, and verify actual playback. On the original system, TV return meters on Apollo ANALOG 5/6 should become quiet and COMPUTER should carry direct audio.
5. Enable Launch at Login in app settings if wanted.

Rollback: quit IOGuard, turn off its launch-at-login setting, then run `./Install.command` to restore the legacy v1.0.1 guard. That installer configures Universal Audio Thunderbolt specifically; the app supports chosen devices.
