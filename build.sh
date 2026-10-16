#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="ClipHistory.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 main.swift \
  -o "$APP/Contents/MacOS/ClipHistory" \
  -framework Cocoa -framework Carbon -framework ServiceManagement

cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"

echo "Selesai: $(pwd)/$APP"
echo "Pindahkan ke Applications: mv $APP /Applications/"
