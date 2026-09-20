#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/version.sh"

IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: CHARLES B BONETTI (6KZQK3A2B3)}"
DIST="$ROOT/dist"
APP="$DIST/Stowmark.app"
DMG="$DIST/Stowmark-$VERSION.dmg"
STAGE="$DIST/dmg-stage"
NOTES="$DIST/ALPHA-NOTES.md"

echo "== Version $VERSION (build $BUILD) =="

echo "== Building release =="
swift build -c release --product Stowmark
swift build -c release --product StowmarkTool

echo "== Assembling app bundle =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$ROOT/.build/release/Stowmark" "$APP/Contents/MacOS/Stowmark"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
stamp_plist "$APP/Contents/Info.plist"
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

echo "== Chrome native messaging host =="
"$ROOT/scripts/assemble-chrome-host.sh" "$APP"

echo "== Diagnostic tool =="
"$ROOT/scripts/assemble-tool.sh" "$APP"

echo "== Signing =="
codesign --force --options runtime --timestamp --entitlements "$ROOT/App/Stowmark.entitlements" --sign "$IDENTITY" "$APP/Contents/MacOS/Stowmark"
codesign --force --options runtime --timestamp --entitlements "$ROOT/App/Stowmark.entitlements" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "== Building DMG =="
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/README-ALPHA.txt" <<EOF
Stowmark — Alpha $VERSION

Local-first visual library for links, images, excerpts, and PDFs.
Proprietary evaluation license — see LICENSE in the repository.
Not notarized: first launch is right-click → Open.

Export your current library from Settings before replacing an older Stowmark.

1. Drag "Stowmark" into Applications.
2. First launch: right-click the app → Open (Gatekeeper).
3. Paste a link into the capture bar at the bottom, press Return.
4. Search with Command-F.
5. Use the layout switcher for Cards, Rows & Columns, or Covers.
6. The gear opens Settings. Appearance lives there.

Safari: Settings → Capture → Turn on Stowmark in Safari… then enable the extension.
Save Page is a click, not automatic. "Saved" appears only after the library confirms it.

Share: from Safari, Chrome, Arc, Preview, Finder, or Notes, choose Share → Stowmark.
Chrome: Settings → Capture → Install Chrome capture, then load the Chrome extension
(developer mode or the Web Store listing when published).

Services menu, Dock drop, and Shortcuts also save into the same library.
EOF

hdiutil create -volname "Stowmark Alpha" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

codesign --force --sign "$IDENTITY" "$DMG" || true

echo "== Verify =="
spctl --assess --type open --context context:primarySignature -v "$APP" 2>&1 || true
ls -lh "$DMG" "$APP"
SHA="$(shasum -a 256 "$DMG" | tee "$DIST/Stowmark-$VERSION.dmg.sha256" | awk '{print $1}')"

cat > "$NOTES" <<EOF
# Stowmark Alpha $VERSION

**Your visual library. On your Mac.**

Public alpha. Proprietary evaluation license — see \`LICENSE\`. The library is local; retention labels say what was actually saved.

## Installer

\`dist/Stowmark-$VERSION.dmg\`

SHA-256: \`$SHA\`

1. Drag **Stowmark** into Applications.
2. First launch: right-click → **Open** (not notarized yet).
3. Paste a link into the capture bar, use the menu bar icon, or Safari / Share / Services / Dock / Shortcuts / Chrome.
4. Search with Command-F. Layout switcher: Cards, Rows & Columns, Covers.
5. Gear → Settings. Appearance, library export/restore, and Capture live there.

## What this build includes

- Equal cards, native table, covers; collapsible sidebar; shelves, tags, keyboard browsing
- Preview photo upload and a resizable description on each card
- Safari extension (honest pending/saved), Share sheet, Services, Dock drop, Shortcuts
- Chrome native messaging host + unpackable Chrome extension (Web Store still pending)
- Menu bar capture (clipboard save + open library)
- Thumbnail cache, drop of links/images/PDFs, closed-app Safari absorb
- Continuity: migrates Cardfile / My Mind Application Support + App Groups; accepts \`stowmark://\`, \`cardfile://\`, \`mymind://\`; restores \`.stowmark\`, \`.cardfile\`, \`.mymind\`

## Known limits

- Not notarized — Gatekeeper requires right-click → Open
- Chrome Web Store listing not published yet (developer-mode load works)
- GIF / WebP / TIFF / SVG / video not accepted yet
- No Retry button after a failed save
- Opt-in clipboard watcher not built
- Name not trademark-cleared; preliminary screening only

## Sign

Developer ID Application: CHARLES B BONETTI (6KZQK3A2B3).
EOF

echo "DMG ready: $DMG"
echo "Notes: $NOTES"
