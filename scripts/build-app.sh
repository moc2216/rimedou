#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="RimeDou"
BUNDLE_ID="com.local.rimedou"
PRODUCT_NAME="rimedou"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

env CLANG_MODULE_CACHE_PATH=.build/module-cache \
  XDG_CACHE_HOME=.build/xdg-cache \
  swift build \
  -c release \
  --disable-sandbox \
  --cache-path .build/swiftpm-cache \
  --product "$PRODUCT_NAME"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp ".build/release/$PRODUCT_NAME" "$MACOS_DIR/$APP_NAME"
cp "config/default.json" "$RESOURCES_DIR/default.json"
cp "assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>用于与系统输入法和辅助功能事件协作。</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>用于全局监听触发键（右 Command）与语音中的任意按键，以唤起或结束豆包语音输入。</string>
  <key>NSAccessibilityUsageDescription</key>
  <string>用于向豆包输入法发送右 Ctrl 语音快捷键。</string>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
