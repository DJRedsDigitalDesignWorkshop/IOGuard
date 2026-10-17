#!/bin/zsh
set -eu
cd "${0:A:h}"
DEST="$HOME/Library/Application Support/UniversalAudioGuard"
AGENT="$HOME/Library/LaunchAgents/com.djred.universalaudioguard.plist"
mkdir -p "$DEST" "$HOME/Library/LaunchAgents"
cp ua-audio-guard "$DEST/ua-audio-guard"
chmod 755 "$DEST/ua-audio-guard"
/usr/bin/python3 - "$DEST" "$AGENT" <<'PY'
import plistlib, sys
from pathlib import Path
folder, agent = sys.argv[1:]
data = {'Label':'com.djred.universalaudioguard', 'ProgramArguments':[folder+'/ua-audio-guard'], 'RunAtLoad':True, 'KeepAlive':True, 'ThrottleInterval':10, 'ProcessType':'Background'}
Path(agent).write_bytes(plistlib.dumps(data))
PY
launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo 'Universal Audio Guard 1.0.0 installed and running.'
