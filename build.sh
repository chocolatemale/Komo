#!/bin/bash
# Builds Komo with SwiftPM and packages it into a double-clickable .app bundle
# plus a zip that can be shared directly.
#
# Signing identity selection (override with KOMO_SIGN_ID="..."):
#   1. a "Developer ID Application" cert (for distribution + notarization), else
#   2. an "Apple Development" cert (stable signature for local use), else
#   3. ad-hoc ("-").
# A stable (non-ad-hoc) signature is what makes the Input Monitoring grant
# survive rebuilds instead of forcing a re-grant every time.
set -euo pipefail
cd "$(dirname "$0")"

APP="Komo.app"
ZIP="Komo-installable.zip"
CONFIG="release"

SIGN_ID="${KOMO_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
    SIGN_ID=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')
    [ -z "$SIGN_ID" ] && SIGN_ID=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')
    [ -z "$SIGN_ID" ] && SIGN_ID="-"
fi

echo "▶ Compiling (${CONFIG})..."
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Komo"

echo "▶ Assembling ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Komo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/Komo.icns ]; then
    cp Resources/Komo.icns "$APP/Contents/Resources/Komo.icns"
fi

echo "▶ Signing with: $SIGN_ID"
if [[ "$SIGN_ID" == "Developer ID"* ]]; then
    # Hardened runtime + secure timestamp, required for notarization.
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
    codesign --force --sign "$SIGN_ID" "$APP"
fi

echo "✅ Built ${APP}"
codesign -dvv "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier|Signature' | head -4 || true

echo "▶ Packaging ${ZIP}..."
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "✅ Packaged ${ZIP}"
