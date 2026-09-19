#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: CHARLES B BONETTI (6KZQK3A2B3)}"
VERSION="1.0.0-alpha.9"
DIST="$ROOT/dist"
APP="$DIST/My Mind.app"
DMG="$DIST/MyMind-$VERSION.dmg"
STAGE="$DIST/dmg-stage"

echo "== Building release =="
swift build -c release --product MyMind
swift build -c release --product MyMindTool

echo "== Assembling app bundle =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$ROOT/.build/release/MyMind" "$APP/Contents/MacOS/MyMind"
cp "$ROOT/.build/release/MyMindTool" "$APP/Contents/Helpers/MyMindTool"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/App/Resources/"*.png "$APP/Contents/Resources/" 2>/dev/null || true
if [[ -f "$ROOT/App/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/App/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Ensure Finder launches as GUI app
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool false" "$APP/Contents/Info.plist" 2>/dev/null || true

echo "== Safari extension =="
"$ROOT/scripts/assemble-appex.sh" "$APP"

echo "== Share extension =="
"$ROOT/scripts/assemble-share-appex.sh" "$APP"

echo "== Signing =="
codesign --force --options runtime --timestamp --entitlements "$ROOT/App/MyMind.entitlements" --sign "$IDENTITY" "$APP/Contents/Helpers/MyMindTool"
codesign --force --options runtime --timestamp --entitlements "$ROOT/App/MyMind.entitlements" --sign "$IDENTITY" "$APP/Contents/MacOS/MyMind"
codesign --force --options runtime --timestamp --entitlements "$ROOT/App/MyMind.entitlements" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "== Building DMG =="
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# README for alpha install
cat > "$STAGE/README-ALPHA.txt" <<'EOF'
My Mind — Alpha 1.0.0-alpha.9

Export your current library from Settings before replacing an older My Mind.

1. Drag "My Mind" into Applications.
2. First launch: right-click the app → Open (Gatekeeper).
3. Paste a link into the capture bar at the bottom, press Return.
4. Search with Command-F.
5. Use the layout switcher for Cards, Rows & Columns, or Covers.
6. The gear opens Settings. Appearance lives there.

Safari: Settings → Open Safari Extensions… and turn on My Mind.
Save Page is a click, not automatic. "Saved" appears only after the library confirms it.

Share: from Safari, Chrome, Arc, Preview, Finder, or Notes, choose Share → My Mind.
The sheet says what will be kept before you save. "Saved" appears only after the library confirms it.
EOF

hdiutil create -volname "My Mind Alpha" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

# Sign the DMG as well (optional but good for distribution)
codesign --force --sign "$IDENTITY" "$DMG" || true

echo "== Verify =="
spctl --assess --type open --context context:primarySignature -v "$APP" 2>&1 || true
ls -lh "$DMG" "$APP"
shasum -a 256 "$DMG" | tee "$DIST/MyMind-$VERSION.dmg.sha256"
echo "DMG ready: $DMG"
