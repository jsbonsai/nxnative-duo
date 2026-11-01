#!/bin/sh
# Build "Duo Builder.app" next to this script (release build, its own icon, ad-hoc signed). The app finds the
# project when it sits anywhere inside it, or asks once. Usage: duo/app/package.sh [output folder]
set -e
cd "$(dirname "$0")"
OUT="${1:-$PWD/build}"
swift build -c release --product DuoBuilder
BIN="$(swift build -c release --show-bin-path)/DuoBuilder"
APP="$OUT/Duo Builder.app"
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DuoBuilder"
ICON=$(mktemp -d)/AppIcon.iconset && mkdir -p "$ICON"
"$BIN" --icon "$ICON/../icon1024.png" >/dev/null 2>&1
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICON/../icon1024.png" --out "$ICON/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ICON/../icon1024.png" --out "$ICON/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICON" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Duo Builder</string>
  <key>CFBundleDisplayName</key><string>Duo Builder</string>
  <key>CFBundleIdentifier</key><string>org.nxnativeduo.builder</string>
  <key>CFBundleExecutable</key><string>DuoBuilder</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign -f -s - "$APP" >/dev/null 2>&1
echo "$APP"
