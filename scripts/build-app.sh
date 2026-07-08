#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="rimedou"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICON_SOURCE="$ROOT/assets/AppIcon.icns"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"

cd "$ROOT"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp ".build/$CONFIGURATION/$APP_NAME" "$MACOS/$APP_NAME"
cp "$ROOT/support/Info.plist" "$CONTENTS/Info.plist"
if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$RESOURCES/AppIcon.icns"
fi
if [ -f "$ROOT/config.json" ]; then
    cp "$ROOT/config.json" "$RESOURCES/config.json"
fi

if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/"[^"]+"/ { print $2; exit }')"
fi

if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="-"
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
touch "$APP_DIR" "$CONTENTS/Info.plist"
[ -f "$RESOURCES/AppIcon.icns" ] && touch "$RESOURCES/AppIcon.icns"
if [ -x "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" ]; then
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -f "$APP_DIR" >/dev/null 2>&1 || true
fi
echo "signed with: $SIGN_IDENTITY"
echo "$APP_DIR"
