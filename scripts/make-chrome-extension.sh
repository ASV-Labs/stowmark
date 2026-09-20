#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/bin/plutil -extract version raw -o - "$ROOT/ChromeExtension/manifest.json" 2>/dev/null || echo "1.0.0")"
OUT="$ROOT/dist/chrome-extension"
ZIP="$ROOT/dist/mymind-chrome-$VERSION.zip"

# The scripts, popup, icons, and locales are shared with the Safari extension. Only the manifest
# differs, because Chrome needs a service worker and Safari needs a background script.
rm -rf "$OUT" "$ZIP"
mkdir -p "$OUT/images" "$OUT/_locales/en"

cp "$ROOT/ChromeExtension/manifest.json" "$OUT/manifest.json"
for file in popup.html popup.css popup.js background.js content.js; do
  cp "$ROOT/SafariExtension/Resources/$file" "$OUT/$file"
done
cp "$ROOT/SafariExtension/Resources/images/"*.png "$OUT/images/"
cp "$ROOT/SafariExtension/Resources/_locales/en/messages.json" "$OUT/_locales/en/"

/usr/bin/plutil -lint "$OUT/manifest.json" >/dev/null 2>&1 || python3 -c "import json,sys; json.load(open('$OUT/manifest.json'))"

cd "$OUT"
zip -qr "$ZIP" .
cd "$ROOT"

echo "Unpacked build: $OUT"
echo "Web Store upload: $ZIP"
echo
echo "To load it now: Chrome → Extensions → Developer mode → Load unpacked → $OUT"
echo "To publish: upload the zip at https://chrome.google.com/webstore/devconsole"
echo "After publishing, paste the assigned ID into My Mind → Settings → Capture."
