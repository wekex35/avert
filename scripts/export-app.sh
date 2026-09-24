#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="Avert"
SCHEME="Avert"
CONFIG="Release"

mkdir -p "$DIST"
rm -rf "$DIST/${APP_NAME}.app" "$DIST/DerivedData"

echo "Building $APP_NAME ($CONFIG)…"
xcodebuild \
  -project "$ROOT/Avert.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DIST/DerivedData" \
  build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO

PRODUCT="$DIST/DerivedData/Build/Products/$CONFIG/${APP_NAME}.app"
if [[ ! -d "$PRODUCT" ]]; then
  echo "Missing app at $PRODUCT" >&2
  exit 1
fi

cp -R "$PRODUCT" "$DIST/${APP_NAME}.app"
chmod +x "$ROOT/scripts/make-dmg.sh"
"$ROOT/scripts/make-dmg.sh" "$DIST/${APP_NAME}.app" "$DIST/${APP_NAME}.dmg"
echo "Exported → $DIST/${APP_NAME}.app"
echo "DMG      → $DIST/${APP_NAME}.dmg"
echo "Open with: open \"$DIST/${APP_NAME}.app\""
echo "For distribution: sign + notarize with your Developer ID (see docs/SIGNING.md)."