#!/bin/zsh
# Sign with Developer ID, notarize, staple, and build a Gatekeeper-safe DMG.
# Prerequisites: Developer ID Application identity in Keychain + App Store Connect API key in certs/
# Usage: ./scripts/notarize-release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
CERTS="$ROOT/certs"
APP_NAME="Avert"
SCHEME="Avert"
TEAM_ID="${APPLE_TEAM_ID:-9YCF9S8W2Y}"

mkdir -p "$DIST"
chmod +x "$ROOT/scripts/make-dmg.sh"

IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)
if [[ -z "$IDENTITY" ]]; then
  echo "ERROR: No 'Developer ID Application' identity in Keychain." >&2
  echo "Create one at https://developer.apple.com/account/resources/certificates/add" >&2
  echo "Type: Developer ID Application — use certs/CertificateSigningRequest.certSigningRequest" >&2
  echo "Then double-click the downloaded .cer to install it." >&2
  exit 1
fi
echo "Using: $IDENTITY"

API_KEY_FILE=$(ls "$CERTS"/AuthKey_*.p8 2>/dev/null | head -1 || true)
if [[ -z "$API_KEY_FILE" ]]; then
  echo "ERROR: Missing App Store Connect API key (certs/AuthKey_*.p8)" >&2
  exit 1
fi
API_KEY_ID=$(basename "$API_KEY_FILE" .p8 | sed 's/^AuthKey_//')
ISSUER_ID="${APPLE_API_ISSUER_ID:-}"
if [[ -z "$ISSUER_ID" ]]; then
  if [[ -f "$CERTS/issuer_id" ]]; then
    ISSUER_ID=$(tr -d ' \n' < "$CERTS/issuer_id")
  else
    echo "ERROR: Set APPLE_API_ISSUER_ID or put the Issuer UUID in certs/issuer_id" >&2
    echo "Find it at https://appstoreconnect.apple.com/access/integrations/api" >&2
    exit 1
  fi
fi
echo "Notary API key: $API_KEY_ID"

ARCHIVE="$DIST/Avert.xcarchive"
EXPORT="$DIST/export"
rm -rf "$ARCHIVE" "$EXPORT" "$DIST/${APP_NAME}.app"
mkdir -p "$EXPORT"

echo "Archiving…"
xcodebuild archive \
  -project "$ROOT/Avert.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$DIST/DerivedDataSigned" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  ENABLE_HARDENED_RUNTIME=YES

cat > "$DIST/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
</dict>
</plist>
EOF

echo "Exporting Developer ID build…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$DIST/ExportOptions.plist"

APP=$(find "$EXPORT" -name "${APP_NAME}.app" -maxdepth 3 | head -1)
test -d "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")

ZIP="$DIST/Avert-notarize.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Submitting to Apple notary service (wait)…"
xcrun notarytool submit "$ZIP" \
  --key "$API_KEY_FILE" \
  --key-id "$API_KEY_ID" \
  --issuer "$ISSUER_ID" \
  --wait

echo "Stapling…"
xcrun stapler staple "$APP"
spctl --assess --type execute -vv "$APP" 2>&1 || true

ditto "$APP" "$DIST/${APP_NAME}.app"
OUT_DMG="$DIST/Avert-${VERSION}-macos-notarized.dmg"
OUT_ZIP="$DIST/Avert-${VERSION}-macos-notarized.zip"
"$ROOT/scripts/make-dmg.sh" "$APP" "$OUT_DMG"
# Staple the DMG too when possible
xcrun stapler staple "$OUT_DMG" 2>/dev/null || true
ditto -c -k --keepParent "$APP" "$OUT_ZIP"

echo ""
echo "Ready for Product Hunt / public download:"
echo "  $OUT_DMG"
echo "  $OUT_ZIP"
echo "Verify: spctl --assess --type execute -vv \"$DIST/${APP_NAME}.app\""
