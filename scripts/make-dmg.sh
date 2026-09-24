#!/bin/zsh
# Create a drag-to-Applications DMG from an .app bundle.
# Usage: ./scripts/make-dmg.sh /path/to/Avert.app [/path/to/Avert.dmg]
set -euo pipefail

APP="${1:?Usage: $0 /path/to/App.app [out.dmg]}"
if [[ ! -d "$APP" ]]; then
  echo "Not an app bundle: $APP" >&2
  exit 1
fi

APP_NAME="$(basename "$APP" .app)"
OUT="${2:-$(pwd)/${APP_NAME}.dmg}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

ditto "$APP" "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"

# UDZO = zlib-compressed read-only image (good for downloads)
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$OUT"

echo "DMG → $OUT"
