#!/bin/bash
set -e
cd "$(dirname "$0")"

VERSION="${1:-dev}"
DMG="ClipHistory-$VERSION.dmg"

./build.sh

rm -rf dmg "$DMG"
mkdir dmg
cp -R ClipHistory.app dmg/
ln -s /Applications dmg/Applications

hdiutil create -volname "ClipHistory" -srcfolder dmg -ov -format UDZO "$DMG"
rm -rf dmg

echo "DMG: $(pwd)/$DMG"
