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
  <key>UTImportedTypeDeclarations</key><array>
    <dict><key>UTTypeIdentifier</key><string>org.nxnativeduo.nsp</string>
      <key>UTTypeDescription</key><string>Nintendo Switch package</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string></array>
      <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>nsp</string></array></dict></dict>
    <dict><key>UTTypeIdentifier</key><string>org.nxnativeduo.xci</string>
      <key>UTTypeDescription</key><string>Nintendo Switch cartridge image</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string></array>
      <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>xci</string></array></dict></dict>
  </array>
  <key>CFBundleDocumentTypes</key><array>
    <dict><key>CFBundleTypeName</key><string>Game files</string><key>LSHandlerRank</key><string>None</string>
      <key>LSItemContentTypes</key><array><string>org.nxnativeduo.nsp</string><string>org.nxnativeduo.xci</string><string>public.iso-image</string></array></dict>
  </array>
</dict></plist>
PLIST
codesign -f -s - "$APP" >/dev/null 2>&1
echo "$APP"
