#!/bin/bash
# Build and install "AI Usage.app" into ~/Applications, then relaunch it.
set -euo pipefail
cd "$(dirname "$0")"
APP="$HOME/Applications/AI Usage.app"

xcrun swiftc -parse-as-library -O -target "$(uname -m)-apple-macos14.0" main.swift -o AIUsage

pkill -x AIUsage 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mv AIUsage "$APP/Contents/MacOS/AIUsage"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.marcus.ai-usage</string>
  <key>CFBundleName</key><string>AI Usage</string>
  <key>CFBundleExecutable</key><string>AIUsage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$APP"
open "$APP"
echo "Installed $APP"
