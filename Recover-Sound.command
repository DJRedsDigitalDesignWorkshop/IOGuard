#!/bin/zsh
set -eu
TARGET="gui/$(id -u)/com.djred.universalaudioguard"
READY_FILE="$HOME/Library/Application Support/UniversalAudioGuard/ready.pid"
# Wait for this exact service process to publish readiness, never signal a starting binary.
for ATTEMPT in {1..20}; do
 PID="$(launchctl print "$TARGET" 2>/dev/null | awk '$1 == "pid" && $2 == "=" {print $3; exit}')"
 READY="$(cat "$READY_FILE" 2>/dev/null || true)"
 if [[ "$PID" == <-> && "$READY" == "$PID" ]]; then
  launchctl kill SIGUSR1 "$TARGET"
  print 'Requested one sound recovery. It may briefly interrupt playback.'
  exit 0
 fi
 sleep 0.25
done
print 'The recovery-enabled background guard is not ready. Open IOGuard and choose Recover Sound Now instead.'
exit 1
