#!/bin/bash
# Builds PeSarma.app (Pe sârmă) without needing Xcode.
# Usage: [PESARMA_BUILD_DIR=/path] scripts/build-app.sh [debug|release]
# Everything generated goes under PESARMA_BUILD_DIR (default: ./build).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
BUILD_DIR="${PESARMA_BUILD_DIR:-build}"
mkdir -p "$BUILD_DIR"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"
SCRATCH="$BUILD_DIR/swiftpm"
APP="$BUILD_DIR/PeSarma.app"
VERSION="$(cat VERSION)"
BUILD_NUMBER="$(cat BUILD_NUMBER)"

# Builds one architecture and copies its binary into $OUT.
# The Command Line Tools for macOS 27 ship an SDK whose SwiftUI needs a macro
# plugin they do not include. If the default SDK fails, fall back to the
# newest macOS 26 SDK installed alongside it.
build_arch() {
  local triple="$1-apple-macosx14.0"
  if [ -z "${SDKROOT:-}" ] && ! swift build -c "$CONFIG" --scratch-path "$SCRATCH" --triple "$triple" >&2; then
    FALLBACK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1)"
    if [ -z "$FALLBACK" ]; then exit 1; fi
    echo "Retrying with $FALLBACK" >&2
    export SDKROOT="$FALLBACK"
  fi
  if [ -n "${SDKROOT:-}" ]; then swift build -c "$CONFIG" --scratch-path "$SCRATCH" --triple "$triple" >&2; fi
  cp "$(swift build -c "$CONFIG" --scratch-path "$SCRATCH" --triple "$triple" --show-bin-path)/PeSarma" "$OUT/PeSarma-$1"
}

# A universal binary, so it runs on Apple silicon and on Intel Macs, from
# macOS 14 Sonoma onwards.
OUT="$BUILD_DIR/stage"; rm -rf "$OUT"; mkdir -p "$OUT"
build_arch arm64
build_arch x86_64
lipo -create "$OUT/PeSarma-arm64" "$OUT/PeSarma-x86_64" -output "$OUT/PeSarma"
BIN="$OUT/PeSarma"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PeSarma"

# Icon
WORK="$BUILD_DIR/icon-work"; rm -rf "$WORK"; mkdir -p "$WORK"
swift scripts/brand/Logotip.swift "$WORK"
mv "$WORK/PeSarma-Simbol.png" "$WORK/icon.png"
cp Sources/PeSarma/Resources/StatusIcon.png Sources/PeSarma/Resources/StatusIcon@2x.png "$APP/Contents/Resources/"
ICONSET="$WORK/PeSarma.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/PeSarma.icns"
rm -rf "$WORK"

# Translations: one folder per language, listed in Info.plist so macOS knows
# which languages the app speaks.
LANGUAGES=""
for dir in Sources/PeSarma/Resources/*.lproj; do
  cp -R "$dir" "$APP/Contents/Resources/"
  LANGUAGES="$LANGUAGES<string>$(basename "$dir" .lproj)</string>"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Pe sârmă</string>
  <key>CFBundleDisplayName</key><string>Pe sârmă</string>
  <key>CFBundleIdentifier</key><string>dev.gordas.PeSarma</string>
  <key>CFBundleExecutable</key><string>PeSarma</string>
  <key>CFBundleIconFile</key><string>PeSarma</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleDevelopmentRegion</key><string>ro</string>
  <key>CFBundleLocalizations</key><array>${LANGUAGES}</array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key>
  <string>Pe sârmă — ediția în limba română, publicată și întreținută de Cristi Gordaș. Bazată pe Tendedero de Alejandro Buján. Licență MIT.</string>
  <key>NSDesktopFolderUsageDescription</key>
  <string>Pe sârmă urmărește folderul în care macOS salvează capturile tale, ca să le poată agăța pe fir.</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>Pe sârmă urmărește folderul ales de tine, ca să agațe pe fir imaginile noi.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>Pe sârmă urmărește folderul ales de tine, ca să agațe pe fir imaginile noi.</string>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Agață pe fir</string></dict>
      <key>NSMessage</key><string>hangOnLine</string>
      <key>NSPortName</key><string>PeSarma</string>
      <key>NSRequiredContext</key><dict/>
      <key>NSSendFileTypes</key><array><string>public.image</string><string>public.plain-text</string><string>public.rtf</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Sign with a Developer ID when one is in the keychain (or SIGN_IDENTITY is
# set), with the hardened runtime and a secure timestamp that notarization
# requires. Without one, sign ad hoc so the app still runs locally.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')}"
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  echo "Signed with $IDENTITY"
else
  codesign --force --deep --sign - "$APP" >/dev/null
  echo "Signed ad hoc (no Developer ID found)"
fi
echo "Built $APP"
