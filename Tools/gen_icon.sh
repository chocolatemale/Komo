#!/bin/bash
# Generates Resources/Komo.icns from a 1024px master rendered by the app's
# AppIconRenderer (Komo --appicon), so the Dock icon matches the menu-bar bunny.
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER=/tmp/komo_icon_1024.png
swift build -c release >/dev/null
"$(swift build -c release --show-bin-path)/Komo" --appicon "$MASTER"

ICONSET=/tmp/Komo.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"

# size  filename
gen() { sips -z "$1" "$1" "$MASTER" --out "$ICONSET/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/Komo.icns
echo "✅ Wrote Resources/Komo.icns"
