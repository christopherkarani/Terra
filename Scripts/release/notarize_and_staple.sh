#!/bin/zsh
set -euo pipefail

DMG_PATH="${1:-}"
if [[ -z "$DMG_PATH" ]]; then
  echo "Usage: notarize_and_staple.sh /path/to/TraceMacApp.dmg" >&2
  exit 2
fi

PROFILE="${APPLE_NOTARYTOOL_PROFILE:-}"
if [[ -z "$PROFILE" ]]; then
  echo "Missing APPLE_NOTARYTOOL_PROFILE (run: xcrun notarytool store-credentials …)" >&2
  exit 3
fi

xcrun notarytool submit "$DMG_PATH" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
spctl -a -vv "$DMG_PATH"

