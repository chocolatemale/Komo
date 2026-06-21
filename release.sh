#!/bin/bash
# Creates an Apple Silicon-only Developer ID release build, notarizes it, and
# emits a stapled DMG suitable for direct public download.
set -euo pipefail
cd "$(dirname "$0")"

APP="Komo.app"
DMG_NAME="Komo-arm64.dmg"
CONFIG="release"
DIST="dist"
STAGE="$DIST/dmg-root"
NOTARY_PROFILE="${KOMO_NOTARY_PROFILE:-komo-notary}"
SIGN_ID="${KOMO_SIGN_ID:-}"

if [ -z "$SIGN_ID" ]; then
    SIGN_ID=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')
fi

if [ -z "$SIGN_ID" ]; then
    cat >&2 <<'EOF'
error: no Developer ID Application certificate found.

Create one in Apple Developer, install it in Keychain, then rerun:

  ./release.sh

Or pass a specific identity:

  KOMO_SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./release.sh
EOF
    exit 1
fi

if [[ "$SIGN_ID" != Developer\ ID\ Application:* ]]; then
    echo "error: release signing requires a Developer ID Application identity, got: $SIGN_ID" >&2
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    cat >&2 <<EOF
error: notarytool profile "$NOTARY_PROFILE" is not configured.

Store credentials once, then rerun:

  xcrun notarytool store-credentials "$NOTARY_PROFILE" \\
    --apple-id "YOUR_APPLE_ID_EMAIL" \\
    --team-id "YOUR_TEAM_ID" \\
    --password "APP_SPECIFIC_PASSWORD"

You can override the profile name with KOMO_NOTARY_PROFILE.
EOF
    exit 1
fi

echo "▶ Compiling arm64 (${CONFIG})..."
swift build -c "$CONFIG" --arch arm64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/Komo"

echo "▶ Assembling ${APP}..."
rm -rf "$APP" "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"
cp "$BIN" "$APP/Contents/MacOS/Komo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/Komo.icns ]; then
    cp Resources/Komo.icns "$APP/Contents/Resources/Komo.icns"
fi

echo "▶ Signing app with: ${SIGN_ID}"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "▶ Preparing DMG..."
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Komo -srcfolder "$STAGE" -ov -format UDZO "$DIST/$DMG_NAME"

echo "▶ Signing DMG..."
codesign --force --timestamp --sign "$SIGN_ID" "$DIST/$DMG_NAME"

echo "▶ Submitting for notarization..."
xcrun notarytool submit "$DIST/$DMG_NAME" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▶ Stapling notarization ticket..."
xcrun stapler staple "$DIST/$DMG_NAME"
xcrun stapler validate "$DIST/$DMG_NAME"

echo "▶ Gatekeeper assessment..."
spctl --assess --type open --context context:primary-signature --verbose=4 "$DIST/$DMG_NAME"

echo "✅ Release ready: $DIST/$DMG_NAME"
