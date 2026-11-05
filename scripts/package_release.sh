#!/bin/bash
# Build the universal app and package it for a GitHub Release: zip + SHA-256.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-${AI_USAGE_VERSION:-}}"
if [ -z "$VERSION" ]; then
  VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
fi
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi

DIST="dist"
rm -rf "$DIST"
mkdir -p "$DIST"

AI_USAGE_VERSION="$VERSION" ./scripts/build_app.sh "$DIST"

ZIP="$DIST/AIUsage-$VERSION-macos-universal.zip"
ditto -c -k --keepParent "$DIST/AI Usage.app" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "Packaged $ZIP"
