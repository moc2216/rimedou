#!/usr/bin/env zsh
set -euo pipefail

# 生成多分辨率 AppIcon.icns。用法: scripts/build-icon.sh [design]
# design: mono-light（默认）/ mono-dark
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DESIGN="${1:-mono-light}"
ICONSET="$ROOT_DIR/assets/AppIcon.iconset"
OUT="$ROOT_DIR/assets/AppIcon.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render() {
  local name=$1 px=$2
  swift "$ROOT_DIR/scripts/make-icon.swift" "$DESIGN" "$ICONSET/$name" "$px"
}

render "icon_16x16.png"      16
render "icon_16x16@2x.png"   32
render "icon_32x32.png"      32
render "icon_32x32@2x.png"   64
render "icon_128x128.png"   128
render "icon_128x128@2x.png" 256
render "icon_256x256.png"   256
render "icon_256x256@2x.png" 512
render "icon_512x512.png"   512
render "icon_512x512@2x.png" 1024

iconutil -c icns -o "$OUT" "$ICONSET"
echo "$OUT"
