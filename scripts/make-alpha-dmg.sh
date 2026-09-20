#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/version.sh"

IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: CHARLES B BONETTI (6KZQK3A2B3)}"
DIST="$ROOT/dist"
APP="$DIST/Cardfile.app"
DMG="$DIST/Cardfile-$VERSION.dmg"
STAGE="$DIST/dmg-stage"
NOTES="$DIST/ALPHA-NOTES.md"

echo "== Version $VERSION (build $BUILD) =="

echo "== Building release =="
swift build -c release --product Cardfile
swift build -c release --product CardfileTool

echo "== Assembling app bundle =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$ROOT/.build/release/Cardfile" "$APP/Contents/MacOS/Cardfile"
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
codesign --force --options runtime --timestamp --entitlements "$ROOT/App/Cardfile.entitlements" --sign "$IDENTITY" "$APP/Contents/MacOS/Cardfile"
codesign --force --options runtime --timestamp --entitlements "$ROOT/App/Cardfile.entitlements" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "== Building DMG =="
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/README-ALPHA.txt" <<EOF
Cardfile — Alpha $VERSION

Local-first visual library for links, images, excerpts, and PDFs.
Proprietary evaluation license — see LICENSE in the repository.
Not notarized: first launch is right-click → Open.

Export your current library from Settings before replacing an older Cardfile.

1. Drag "Cardfile" into Applications.
2. First launch: right-click the app → Open (Gatekeeper).
3. Paste a link into the capture bar at the bottom, press Return.
4. Search with Command-F.
5. Use the layout switcher for Cards, Rows & Columns, or Covers.
6. The gear opens Settings. Appearance lives there.

Safari: Settings → Capture → Turn on Cardfile in Safari… then enable the extension.
Save Page is a click, not automatic. "Saved" appears only after the library confirms it.

Share: from Safari, Chrome, Arc, Preview, Finder, or Notes, choose Share → Cardfile.
Chrome: Settings → Capture → Install Chrome capture, then load the Chrome extension
(developer mode or the Web Store listing when published).

Services menu, Dock drop, and Shortcuts also save into the same library.
EOF

hdiutil create -volname "Cardfile Alpha" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

codesign --force --sign "$IDENTITY" "$DMG" || true

echo "== Verify =="
spctl --assess --type open --context context:primarySignature -v "$APP" 2>&1 || true
ls -lh "$DMG" "$APP"
SHA="$(shasum -a 256 "$DMG" | tee "$DIST/Cardfile-$VERSION.dmg.sha256" | awk '{print $1}')"

cat > "$NOTES" <<EOF
# Cardfile Alpha $VERSION

Public alpha. Local-first Mac visual library (rebranded from My Mind). Proprietary evaluation license — see \`LICENSE\`.

## Installer

\`dist/Cardfile-$VERSION.dmg\`

SHA-256: \`$SHA\`

1. Drag **Cardfile** into Applications.
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
- Legacy My Mind library / \`mymind://\` / \`.mymind\` archive migration accepted

## Known limits

- Not notarized — Gatekeeper requires right-click → Open
- Chrome Web Store listing not published yet (developer-mode load works)
- GIF / WebP / TIFF / SVG / video not accepted yet
- No Retry button after a failed save
- Opt-in clipboard watcher not built

## Sign

Developer ID Application: CHARLES B BONETTI (6KZQK3A2B3).
EOF

echo "DMG ready: $DMG"
echo "Notes: $NOTES"
