#!/bin/bash
# Build and install "AI Usage.app" into ~/Applications, then relaunch it.
set -euo pipefail
cd "$(dirname "$0")"
APP="$HOME/Applications/AI Usage.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

xcrun swiftc -parse-as-library -O -target "$(uname -m)-apple-macos14.0" main.swift -o "$WORK/AIUsage"

# App icon: the binary renders its own 1024px icon, then iconutil packs the sizes.
"$WORK/AIUsage" --icon "$WORK/icon.png"
mkdir "$WORK/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK/icon.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$WORK/icon.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o "$WORK/AppIcon.icns"

pkill -x AIUsage 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$WORK/AIUsage" "$APP/Contents/MacOS/AIUsage"
mv "$WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.marcus.ai-usage</string>
  <key>CFBundleName</key><string>AI Usage</string>
  <key>CFBundleExecutable</key><string>AIUsage</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$APP"
touch "$APP"
open "$APP"
echo "Installed $APP"
