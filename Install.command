#!/bin/zsh
set -eu
cd "${0:A:h}"
DEST="$HOME/Library/Application Support/UniversalAudioGuard"
AGENT="$HOME/Library/LaunchAgents/com.djred.universalaudioguard.plist"
mkdir -p "$DEST" "$HOME/Library/LaunchAgents"
# Prepare the executable before stopping the old process; replace it atomically.
TEMP_BINARY="$DEST/.ua-audio-guard.install.$$"
cp ua-audio-guard "$TEMP_BINARY"
chmod 755 "$TEMP_BINARY"
launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
mv -f "$TEMP_BINARY" "$DEST/ua-audio-guard"
/usr/bin/python3 - "$DEST" "$AGENT" <<'PY'
import plistlib, sys
from pathlib import Path
folder, agent = sys.argv[1:]
data = {'Label':'com.djred.universalaudioguard', 'ProgramArguments':[folder+'/ua-audio-guard'], 'RunAtLoad':True, 'KeepAlive':True, 'ThrottleInterval':10, 'ProcessType':'Background', 'StandardErrorPath':folder+'/guard.log'}
Path(agent).write_bytes(plistlib.dumps(data))
PY
launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo 'Universal Audio Guard 1.0.3 installed and running.'
