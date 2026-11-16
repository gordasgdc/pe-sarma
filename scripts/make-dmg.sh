#!/bin/bash
# Builds PeSarma.app, notarizes and staples it, and packs it into a signed,
# notarized, stapled disk image: PeSarma-<version>.dmg (ASCII file name; the
# visible names are in Romanian).
# Usage: [PESARMA_BUILD_DIR=/path] [NOTARY_PROFILE=name] scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

export PESARMA_BUILD_DIR="${PESARMA_BUILD_DIR:-build}"
mkdir -p "$PESARMA_BUILD_DIR"
BUILD_DIR="$(cd "$PESARMA_BUILD_DIR" && pwd)"
export PESARMA_BUILD_DIR="$BUILD_DIR"
scripts/build-app.sh release
APP="$BUILD_DIR/PeSarma.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$BUILD_DIR/PeSarma-$VERSION.dmg"
NAME="Pe sârmă"
PROFILE="${NOTARY_PROFILE:-}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')}"

# Notarize and staple the app first, so the copy inside the image carries its
# own ticket and opens offline.
if [ -n "$IDENTITY" ] && [ -n "$PROFILE" ]; then
  ZIP="$BUILD_DIR/PeSarma-notarize.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  rm -f "$ZIP"
  xcrun stapler staple "$APP"
fi

WORK="$BUILD_DIR/dmg-work"; rm -rf "$WORK"; mkdir -p "$WORK"
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
swift scripts/make-dmg-background.swift "$WORK/bg1x.png" 1
swift scripts/make-dmg-background.swift "$WORK/bg2x.png" 2
# One TIFF holding both resolutions, so the window is sharp on Retina.
tiffutil -cathidpicheck "$WORK/bg1x.png" "$WORK/bg2x.png" -out "$STAGE/.background/background.tiff" >/dev/null

RW="$WORK/rw.dmg"
hdiutil create -quiet -srcfolder "$STAGE" -volname "$NAME" -fs HFS+ -format UDRW -size 60m "$RW"
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')"

# Tiling window managers resize the window, and Finder would save that size
# into the image. Pause AeroSpace while laying it out, if it is running.
if command -v aerospace >/dev/null && pgrep -qx AeroSpace; then
  aerospace enable off
  trap 'aerospace enable on' EXIT
fi

# Lay out the window. Needs permission to control Finder; without it the
# image still works, just with Finder's default layout.
osascript <<OSA || echo "Finder layout skipped"
tell application "Finder"
  tell disk "$NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 528}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "PeSarma.app" of container window to {160, 178}
    set position of item "Applications" of container window to {440, 178}
    -- Size last: Finder can resize the window while it applies the options.
    set the bounds of container window to {200, 120, 800, 528}
    update without registering applications
    delay 1
    set the bounds of container window to {200, 120, 800, 528}
    delay 1
    close
  end tell
end tell
OSA

chmod -Rf go-w "$MOUNT" || true
sync
hdiutil detach -quiet "$MOUNT"
rm -f "$DMG"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$WORK"
echo "Built $DMG"

# Sign the disk image, send it to Apple for notarization and staple the
# ticket. NOTARY_PROFILE names a notarytool keychain profile stored with:
#   xcrun notarytool store-credentials <name> --apple-id ... --team-id ...
if [ -n "$IDENTITY" ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  if [ -n "$PROFILE" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  else
    echo "NOTARY_PROFILE not set: the image is signed but not notarized."
  fi
fi

# The same image under a name without the version, uploaded to every release
# beside the versioned one, so this link always downloads the newest:
#   https://github.com/gordasgdc/pe-sarma/releases/latest/download/PeSarma.dmg
cp -f "$DMG" "$BUILD_DIR/PeSarma.dmg"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Publish: gh release create v$VERSION \"$DMG\" \"$BUILD_DIR/PeSarma.dmg\" ..."
