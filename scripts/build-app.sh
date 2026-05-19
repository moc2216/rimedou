#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DoubaoVoiceBridge"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

cd "$ROOT"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp ".build/$CONFIGURATION/$APP_NAME" "$MACOS/$APP_NAME"
cp "$ROOT/support/Info.plist" "$CONTENTS/Info.plist"
if [ -f "$ROOT/config.json" ]; then
    cp "$ROOT/config.json" "$RESOURCES/config.json"
fi

codesign --force --deep --sign - "$APP_DIR" >/dev/null
echo "$APP_DIR"
