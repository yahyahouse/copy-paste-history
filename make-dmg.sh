#!/bin/bash
set -e
cd "$(dirname "$0")"

VERSION="${1:-dev}"
DMG="ClipHistory-$VERSION.dmg"

# Samakan versi app dengan tag rilis (dipakai auto-update)
if [ "$VERSION" != "dev" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" Info.plist
fi

./build.sh

rm -rf dmg "$DMG"
mkdir dmg
cp -R ClipHistory.app dmg/
ln -s /Applications dmg/Applications

# hdiutil kadang gagal "Resource busy", coba ulang beberapa kali
for i in 1 2 3 4 5; do
  if hdiutil create -volname "Clip History" -srcfolder dmg -ov -format UDZO "$DMG"; then
    break
  fi
  echo "hdiutil gagal, coba lagi ($i)..."
  sleep 5
  [ "$i" = 5 ] && exit 1
done
rm -rf dmg

echo "DMG: $(pwd)/$DMG"
