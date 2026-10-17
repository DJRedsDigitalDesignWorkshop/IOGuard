#!/bin/zsh
set -eu
AGENT="$HOME/Library/LaunchAgents/com.djred.universalaudioguard.plist"
launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
rm -f "$AGENT" "$HOME/Library/Application Support/UniversalAudioGuard/ua-audio-guard"
echo 'Universal Audio Guard removed. Normal audio switching is restored.'
