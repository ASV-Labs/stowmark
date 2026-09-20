#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --product Stowmark
BIN="$ROOT/.build/release/Stowmark"
DIST="$ROOT/dist/Stowmark.app"
rm -rf "$DIST"
mkdir -p "$DIST/Contents/MacOS" "$DIST/Contents/Resources"
cp "$BIN" "$DIST/Contents/MacOS/Stowmark"
cp "$ROOT/App/Info.plist" "$DIST/Contents/Info.plist"
cp "$ROOT/App/Resources/"*.png "$DIST/Contents/Resources/" 2>/dev/null || true
if [[ -f "$ROOT/App/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/App/Resources/AppIcon.icns" "$DIST/Contents/Resources/AppIcon.icns"
fi

if command -v codesign >/dev/null; then
  codesign --force --sign - --entitlements "$ROOT/App/Stowmark.entitlements" "$DIST" || true
fi

echo "Built $DIST"
open -R "$DIST"
