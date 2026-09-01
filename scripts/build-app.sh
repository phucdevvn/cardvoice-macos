#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[[ "$(uname -m)" == "arm64" ]] || { echo "This build targets Apple Silicon (arm64)."; exit 1; }
command -v swift >/dev/null || { echo "Swift toolchain not found."; exit 1; }

swift build --disable-sandbox -c release --arch arm64
BIN="$(swift build --disable-sandbox -c release --arch arm64 --show-bin-path)/CardVoice"
APP="$ROOT/dist/CardVoice.app"
CONTENTS="$APP/Contents"
ICON="$ROOT/AppIcon.icns"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$ROOT/dist"
cp "$BIN" "$CONTENTS/MacOS/CardVoice"
test -f "$ICON" || { echo "AppIcon.icns not found."; exit 1; }
cp "$ICON" "$CONTENTS/Resources/CardVoice.icns"

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
<key>CFBundleShortVersionString</key><string>0.6.2</string>
<key>CFBundleVersion</key><string>10</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
rm -f "$ROOT/dist/CardVoice-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/CardVoice-macOS-arm64.zip"

echo "Built: $APP"
echo "Zip:   $ROOT/dist/CardVoice-macOS-arm64.zip"
