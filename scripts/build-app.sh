#!/bin/bash
# Bygger build/ClaudePill.app (ad hoc-signerad). Flagga --dmg skapar även build/ClaudePill.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product ClaudePill
BIN="$(swift build -c release --show-bin-path)/ClaudePill"

APP=build/ClaudePill.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudePill"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier se.softlabs.claudepill "$APP"
echo "Byggd: $APP"

if [[ "${1:-}" == "--dmg" ]]; then
  rm -f build/ClaudePill.dmg
  hdiutil create -volname ClaudePill -srcfolder "$APP" -ov -format UDZO build/ClaudePill.dmg >/dev/null
  echo "Byggd: build/ClaudePill.dmg"
fi
