#!/usr/bin/env bash
set -euo pipefail

LABEL="local.doubao-voice-bridge.keepalive"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
USER_ID="$(id -u)"

if [ -f "$PLIST" ]; then
    echo "Plist: $PLIST"
    plutil -p "$PLIST"
else
    echo "Plist not found: $PLIST"
fi

echo
if launchctl print "gui/$USER_ID/$LABEL" >/dev/null 2>&1; then
    launchctl print "gui/$USER_ID/$LABEL"
else
    echo "LaunchAgent is not loaded: $LABEL"
fi
