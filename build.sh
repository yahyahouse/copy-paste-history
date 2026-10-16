#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="ClipHistory.app"
BIN="$APP/Contents/MacOS/ClipHistory"
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
codesign --force --sign - "$APP"

echo "Selesai: $(pwd)/$APP"
