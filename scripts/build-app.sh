#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DoubaoVoiceBridge"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICON_SOURCE="$ROOT/Sources/assets/appicon.png"
ICON_BUILD_DIR="$ROOT/build/icon"
ICON_CANVAS_SCALE="${ICON_CANVAS_SCALE:-0.88}"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"

make_app_icon() {
    local source="$1"
    local output="$2"
    local normalized
    local iconset
    local asset_catalog
    local appiconset
    local asset_info
    normalized="$ICON_BUILD_DIR/AppIcon-1024.png"
    iconset="$ICON_BUILD_DIR/AppIcon.iconset"
    asset_catalog="$ICON_BUILD_DIR/AppIcon.xcassets"
    appiconset="$asset_catalog/AppIcon.appiconset"
    asset_info="$ICON_BUILD_DIR/asset-info.plist"

    rm -rf "$ICON_BUILD_DIR"
    mkdir -p "$iconset" "$appiconset"

    swift "$ROOT/scripts/normalize-app-icon.swift" "$source" "$normalized" "$ICON_CANVAS_SCALE"

    sips -z 16 16 "$normalized" --out "$iconset/icon_16x16.png" >/dev/null
    sips -z 32 32 "$normalized" --out "$iconset/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$normalized" --out "$iconset/icon_32x32.png" >/dev/null
    sips -z 64 64 "$normalized" --out "$iconset/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$normalized" --out "$iconset/icon_128x128.png" >/dev/null
    sips -z 256 256 "$normalized" --out "$iconset/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$normalized" --out "$iconset/icon_256x256.png" >/dev/null
    sips -z 512 512 "$normalized" --out "$iconset/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$normalized" --out "$iconset/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$normalized" --out "$iconset/icon_512x512@2x.png" >/dev/null

    cp "$iconset"/icon_*.png "$appiconset/"
    printf '%s\n' \
        '{' \
        '  "images" : [' \
        '    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },' \
        '    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },' \
        '    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },' \
        '    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },' \
        '    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },' \
        '    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },' \
        '    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },' \
        '    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },' \
        '    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },' \
        '    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }' \
        '  ],' \
        '  "info" : { "author" : "xcode", "version" : 1 }' \
        '}' > "$appiconset/Contents.json"

    iconutil -c icns "$iconset" -o "$output"
    xcrun actool "$asset_catalog" \
        --compile "$RESOURCES" \
        --platform macosx \
        --minimum-deployment-target 13.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "$asset_info" >/dev/null
}

cd "$ROOT"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp ".build/$CONFIGURATION/$APP_NAME" "$MACOS/$APP_NAME"
cp "$ROOT/support/Info.plist" "$CONTENTS/Info.plist"
if [ -f "$ICON_SOURCE" ]; then
    make_app_icon "$ICON_SOURCE" "$RESOURCES/AppIcon.icns"
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
touch "$APP_DIR" "$CONTENTS/Info.plist" "$RESOURCES/AppIcon.icns"
if [ -x "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" ]; then
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -f "$APP_DIR" >/dev/null 2>&1 || true
fi
echo "signed with: $SIGN_IDENTITY"
echo "$APP_DIR"
