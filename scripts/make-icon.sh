#!/bin/bash
# Generates Resources/AppIcon.icns (and Resources/AppIcon.png) from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

COLOR=007ACC                                   # VS Code blue
SYMBOL=chevron.left.forwardslash.chevron.right

TMP=$(mktemp -d)
swift scripts/make-icon.swift "$COLOR" "$SYMBOL" "$TMP/icon.png" >/dev/null
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$TMP/icon.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
sips -z 512 512 "$TMP/icon.png" --out Resources/AppIcon.png >/dev/null
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns"
