#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="RimeDou"
VERSION="0.2.0"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME-v$VERSION.zip"
TMP_ZIP="$DIST_DIR/$APP_NAME-v$VERSION.$$.zip"

"$ROOT_DIR/scripts/build-app.sh" >/dev/null

if [[ ! -d "$APP_DIR" ]]; then
  echo "App bundle not found: $APP_DIR" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
(
  cd "$DIST_DIR"
  zip -r -X "$TMP_ZIP" "$APP_NAME.app" -x "*/._*" "*/__MACOSX/*" >/dev/null
)
mv -f "$TMP_ZIP" "$ZIP_PATH"

echo "$ZIP_PATH"
