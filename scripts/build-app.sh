#!/bin/bash
# Bygger build/AgentPill.app (ad hoc-signerad). Flagga --dmg skapar även build/AgentPill.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product AgentPill
BIN="$(swift build -c release --show-bin-path)/AgentPill"

APP=build/AgentPill.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AgentPill"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier se.softlabs.agentpill "$APP"
echo "Byggd: $APP"

if [[ "${1:-}" == "--dmg" ]]; then
  rm -f build/AgentPill.dmg
  hdiutil create -volname AgentPill -srcfolder "$APP" -ov -format UDZO build/AgentPill.dmg >/dev/null
  echo "Byggd: build/AgentPill.dmg"
fi
