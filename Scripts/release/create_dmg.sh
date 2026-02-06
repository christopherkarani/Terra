#!/bin/zsh
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
  echo "Usage: create_dmg.sh /path/to/TraceMacApp.app" >&2
  exit 2
fi

ROOT_DIR="${0:a:h:h:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Apps/TraceMacApp/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/Apps/TraceMacApp/Info.plist")"
OUT_DIR="$ROOT_DIR/.build/releases/TraceMacApp/${VERSION}-${BUILD}"

STAGING_DIR="$OUT_DIR/dmg-staging"
DMG_PATH="$OUT_DIR/TraceMacApp-${VERSION}-${BUILD}.dmg"
TMP_DMG_PATH="$OUT_DIR/TraceMacApp-${VERSION}-${BUILD}-tmp.dmg"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

hdiutil create \
  -volname "TraceMacApp" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$TMP_DMG_PATH" >/dev/null

hdiutil convert "$TMP_DMG_PATH" -format UDZO -o "$DMG_PATH" >/dev/null
rm -f "$TMP_DMG_PATH"

echo "$DMG_PATH"

