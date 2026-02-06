#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:a:h:h:h}"
PROJECT_PATH="$ROOT_DIR/Apps/TraceMacApp/TraceMacApp.xcodeproj"
SCHEME="TraceMacApp"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Apps/TraceMacApp/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/Apps/TraceMacApp/Info.plist")"

OUT_DIR="$ROOT_DIR/.build/releases/TraceMacApp/${VERSION}-${BUILD}"
ARCHIVE_PATH="$OUT_DIR/TraceMacApp.xcarchive"

SIGNING_IDENTITY="${TRACE_MAC_APP_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "Missing TRACE_MAC_APP_SIGNING_IDENTITY (Developer ID Application …)" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/TraceMacApp.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app at: $APP_PATH" >&2
  exit 3
fi

echo "$APP_PATH"

