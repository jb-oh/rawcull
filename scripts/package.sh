#!/bin/bash
# Builds a Developer ID signed, notarized and stapled RawCull DMG for testers.
#
# Usage: scripts/package.sh [--skip-notarize]
#
# Needs the "Developer ID Application" certificate in the login keychain and
# ~/.config/favren/asc.env (FAVREN_APPLE_TEAM_ID, FAVREN_ASC_KEY_ID,
# FAVREN_ASC_ISSUER_ID, FAVREN_ASC_KEY_PATH). Values are read, never printed.
# Output: build/RawCull-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
BUILD="$ROOT/build"
NOTARIZE=1
[[ "${1:-}" == "--skip-notarize" ]] && NOTARIZE=0

ENV_FILE="$HOME/.config/favren/asc.env"
[[ -f "$ENV_FILE" ]] || { echo "missing $ENV_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
for name in FAVREN_APPLE_TEAM_ID FAVREN_ASC_KEY_ID FAVREN_ASC_ISSUER_ID FAVREN_ASC_KEY_PATH; do
    [[ -n "${!name:-}" ]] || { echo "$name is not set in $ENV_FILE" >&2; exit 1; }
done

VERSION=$(awk -F'"' '/MARKETING_VERSION/ { print $2; exit }' project.yml)
BUILD_NUMBER=$(awk -F'"' '/CURRENT_PROJECT_VERSION/ { print $2; exit }' project.yml)
ARCHIVE="$BUILD/RawCull.xcarchive"
EXPORT="$BUILD/export"
APP="$EXPORT/RawCull.app"
DMG="$BUILD/RawCull-$VERSION.dmg"

echo "==> RawCull $VERSION ($BUILD_NUMBER)"
rm -rf "$ARCHIVE" "$EXPORT" "$BUILD/dmg" "$DMG"
mkdir -p "$BUILD"

echo "==> Archiving (universal Release)"
xcodebuild archive \
    -project RawCull.xcodeproj -scheme RawCull -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$FAVREN_APPLE_TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    -quiet

echo "==> Exporting with Developer ID"
EXPORT_OPTIONS="$BUILD/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
    <key>teamID</key><string>$FAVREN_APPLE_TEAM_ID</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
    -exportOptionsPlist "$EXPORT_OPTIONS" -quiet
rm -f "$EXPORT_OPTIONS"

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP"
codesign -dvv "$APP" 2>&1 | grep -E '^(Authority=Developer ID Application|Runtime Version|TeamIdentifier)' || {
    echo "app is not signed with Developer ID and the hardened runtime" >&2; exit 1; }
lipo -archs "$APP/Contents/MacOS/RawCull"

echo "==> Building DMG"
mkdir -p "$BUILD/dmg"
cp -R "$APP" "$BUILD/dmg/"
ln -s /Applications "$BUILD/dmg/Applications"
hdiutil create -volname "RawCull $VERSION" -srcfolder "$BUILD/dmg" -ov -format UDZO "$DMG" -quiet
rm -rf "$BUILD/dmg"
codesign --sign "Developer ID Application" --timestamp "$DMG"

if [[ $NOTARIZE == 1 ]]; then
    echo "==> Notarizing (this usually takes a few minutes)"
    xcrun notarytool submit "$DMG" \
        --key "$FAVREN_ASC_KEY_PATH" --key-id "$FAVREN_ASC_KEY_ID" --issuer "$FAVREN_ASC_ISSUER_ID" \
        --wait
    xcrun stapler staple "$DMG"
    echo "==> Gatekeeper check"
    spctl -a -t open --context context:primary-signature -vv "$DMG"
else
    echo "==> Skipped notarization; testers will see a Gatekeeper warning"
fi

echo "==> Done: $DMG"
