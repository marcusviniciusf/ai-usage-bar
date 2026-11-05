#!/bin/bash
# Build "AI Usage.app" and install it into ~/Applications, then relaunch it.
set -euo pipefail
cd "$(dirname "$0")"
APP="$HOME/Applications/AI Usage.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

./scripts/build_app.sh "$WORK"

pkill -x AIUsage 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$HOME/Applications"
mv "$WORK/AI Usage.app" "$APP"
touch "$APP"
# LaunchServices can briefly report -600 while the old process exits.
launched=false
for attempt in 1 2 3; do
  if open "$APP"; then launched=true; break; fi
  sleep 1
done
if [ "$launched" != true ]; then echo "Built $APP, but macOS could not relaunch it." >&2; exit 1; fi
echo "Installed $APP"
