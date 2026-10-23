#!/bin/bash
# Install AI Usage on this Mac: collector scripts into ~/.local/bin, ccusage, then build the menu bar app.
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Swift compiler missing. Run: xcode-select --install   then re-run this script."
  exit 1
fi

# Symlinks, so edits in this repo apply without reinstalling. Rebuild only after main.swift changes.
mkdir -p "$HOME/.local/bin"
chmod +x bin/ai-usage bin/cursor-spend
ln -sf "$PWD/bin/ai-usage" "$HOME/.local/bin/ai-usage"
ln -sf "$PWD/bin/cursor-spend" "$HOME/.local/bin/cursor-spend"

export PATH="$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v ccusage >/dev/null; then
  if command -v bun >/dev/null; then
    bun add -g ccusage
  elif command -v npm >/dev/null; then
    npm install -g ccusage
  else
    echo "Need bun or npm to install ccusage (brew install node)."
    exit 1
  fi
fi

echo "Checking collector..."
/usr/bin/python3 "$HOME/.local/bin/ai-usage" | /usr/bin/python3 -c '
import json, sys
for t in json.load(sys.stdin)["tools"]:
    print("  %-12s today $%.2f  %s" % (t["name"], t["today"], "ERROR: " + t["error"] if t["error"] else "ok"))'

./build.sh
echo "Done. Click the sparkles icon in the menu bar, then turn on Login in the footer."
