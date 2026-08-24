#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[[ "$(uname -m)" == "arm64" ]] || { echo "This build targets Apple Silicon (arm64)."; exit 1; }
command -v swift >/dev/null || { echo "Swift toolchain not found."; exit 1; }
command -v sips >/dev/null || { echo "sips not found."; exit 1; }
command -v iconutil >/dev/null || { echo "iconutil not found."; exit 1; }

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/CardVoice"
APP="$ROOT/dist/CardVoice.app"
CONTENTS="$APP/Contents"
ICON_SOURCE="$ROOT/.build/AppIcon-Source.png"
ICONSET="$ROOT/.build/CardVoice.iconset"

rm -rf "$APP" "$ICONSET"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$ROOT/dist" "$ICONSET"
cp "$BIN" "$CONTENTS/MacOS/CardVoice"

swift "$ROOT/scripts/generate-icon.swift" "$ICON_SOURCE"

test -f "$ICON_SOURCE" || { echo "Icon generation failed."; exit 1; }

make_icon() {
  local px="$1"
  local name="$2"
  sips -z "$px" "$px" "$ICON_SOURCE" --out "$ICONSET/$name" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/CardVoice.icns"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>CardVoice</string>
<key>CFBundleIdentifier</key><string>com.phucdevvn.CardVoice</string>
<key>CFBundleIconFile</key><string>CardVoice</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>CardVoice</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
rm -f "$ROOT/dist/CardVoice-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/CardVoice-macOS-arm64.zip"

echo "Built: $APP"
echo "Zip:   $ROOT/dist/CardVoice-macOS-arm64.zip"
