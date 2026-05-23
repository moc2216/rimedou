#!/usr/bin/env bash
set -euo pipefail

LABEL="local.doubao-voice-bridge.keepalive"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
USER_ID="$(id -u)"

if launchctl print "gui/$USER_ID/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$USER_ID/$LABEL" >/dev/null 2>&1 || true
fi

rm -f "$PLIST"
echo "Uninstalled LaunchAgent: $LABEL"
