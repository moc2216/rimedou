#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="rimedou"
LABEL="com.moc2216.rimedou.keepalive"
APP_PATH="${APP_PATH:-$ROOT/build/$APP_NAME.app}"
EXECUTABLE="$APP_PATH/Contents/MacOS/$APP_NAME"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/$APP_NAME"
USER_ID="$(id -u)"

if [ ! -x "$EXECUTABLE" ]; then
    echo "App executable not found: $EXECUTABLE"
    echo "Build it first with: ./scripts/build-app.sh"
    exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$EXECUTABLE</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/launch-agent.out.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/launch-agent.err.log</string>
</dict>
</plist>
PLIST

plutil -lint "$PLIST" >/dev/null

if launchctl print "gui/$USER_ID/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$USER_ID/$LABEL" >/dev/null 2>&1 || true
fi

launchctl bootstrap "gui/$USER_ID" "$PLIST"
launchctl enable "gui/$USER_ID/$LABEL"
launchctl kickstart -k "gui/$USER_ID/$LABEL"

echo "Installed LaunchAgent: $PLIST"
launchctl print "gui/$USER_ID/$LABEL" | sed -n '1,80p'
