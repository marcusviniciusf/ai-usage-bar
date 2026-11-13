#!/bin/bash
# Build a self-contained "AI Usage.app" into the given directory (default: build/).
# No install side effects: CI and the release script reuse this.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${AI_USAGE_VERSION:-1.1.0}"
OUT="${1:-build}"
ARCHS="${AI_USAGE_ARCHS:-arm64 x86_64}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

APP="$OUT/AI Usage.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

binaries=()
for arch in $ARCHS; do
  xcrun swiftc -parse-as-library -O -target "$arch-apple-macos14.0" main.swift -o "$WORK/AIUsage-$arch"
  binaries+=("$WORK/AIUsage-$arch")
done
if [ "${#binaries[@]}" -gt 1 ]; then
  lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/AIUsage"
else
  cp "${binaries[0]}" "$APP/Contents/MacOS/AIUsage"
fi

# App icon: the binary renders its own 1024px icon, then iconutil packs the sizes.
"$APP/Contents/MacOS/AIUsage" --icon "$WORK/icon.png"
mkdir "$WORK/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK/icon.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$WORK/icon.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

# Collectors ship inside the bundle, so the app needs no ~/.local/bin install.
cp bin/ai-usage bin/cursor-spend "$APP/Contents/Resources/"
chmod 755 "$APP/Contents/Resources/ai-usage" "$APP/Contents/Resources/cursor-spend"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.marcus.ai-usage</string>
  <key>CFBundleName</key><string>AI Usage</string>
  <key>CFBundleExecutable</key><string>AIUsage</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$APP"
echo "Built $APP ($VERSION, $ARCHS)"
