#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="ClipHistory.app"
BIN="$APP/Contents/MacOS/ClipHistory"
SIGN_ID="${SIGN_ID:--}"   # "-" = ad-hoc, isi nama sertifikat untuk identitas tetap

rm -rf "$APP" build
mkdir -p "$APP/Contents/MacOS" build

# Universal binary: Apple Silicon + Intel
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 main.swift \
    -target "$ARCH-apple-macos13.0" \
    -o "build/ClipHistory-$ARCH" \
    -framework Cocoa -framework SwiftUI -framework Carbon -framework ServiceManagement
done
lipo -create build/ClipHistory-arm64 build/ClipHistory-x86_64 -output "$BIN"
rm -rf build

cp Info.plist "$APP/Contents/"

# Ikon app (.icns) dari icon/AppIcon-1024.png
RES="$APP/Contents/Resources"
mkdir -p "$RES" AppIcon.iconset
for SZ in 16 32 128 256 512; do
  sips -z $SZ $SZ icon/AppIcon-1024.png --out "AppIcon.iconset/icon_${SZ}x${SZ}.png" >/dev/null
  D=$((SZ * 2))
  sips -z $D $D icon/AppIcon-1024.png --out "AppIcon.iconset/icon_${SZ}x${SZ}@2x.png" >/dev/null
done
iconutil -c icns AppIcon.iconset -o "$RES/AppIcon.icns"
rm -rf AppIcon.iconset

# Nama tampilan "Clip History" (file app tetap ClipHistory.app)
for LANG_DIR in en id; do
  mkdir -p "$RES/$LANG_DIR.lproj"
  printf 'CFBundleDisplayName = "Clip History";\nCFBundleName = "Clip History";\n' > "$RES/$LANG_DIR.lproj/InfoPlist.strings"
done
codesign --force --sign "$SIGN_ID" --identifier com.yahyawijaya.cliphistory "$APP"
codesign -dr - "$APP" 2>&1 | tail -1

echo "Selesai: $(pwd)/$APP"
