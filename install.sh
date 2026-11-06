#!/bin/bash
# Install AI Usage on this Mac: collector scripts into ~/.local/bin, then build the menu bar app.
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Swift compiler missing. Run: xcode-select --install   then re-run this script."
  exit 1
fi

# Keep collectors outside TCC-protected folders such as Documents. Re-run install.sh after edits.
mkdir -p "$HOME/.local/bin"
chmod +x bin/ai-usage bin/cursor-spend
rm -f "$HOME/.local/bin/ai-usage" "$HOME/.local/bin/cursor-spend"
cp bin/ai-usage "$HOME/.local/bin/ai-usage"
cp bin/cursor-spend "$HOME/.local/bin/cursor-spend"
chmod 755 "$HOME/.local/bin/ai-usage" "$HOME/.local/bin/cursor-spend"

echo "Checking collector..."
/usr/bin/python3 "$HOME/.local/bin/ai-usage" | /usr/bin/python3 -c '
import json, sys
for t in json.load(sys.stdin)["tools"]:
    print("  %-12s today $%.2f  %s" % (t["name"], t["today"], "ERROR: " + t["error"] if t["error"] else "ok"))'

./build.sh
echo "Done. Click the sparkles icon in the menu bar, then open the gear menu and turn on Launch at login."
