#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/version.sh"
APP="${1:?app bundle path}"
IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: CHARLES B BONETTI (6KZQK3A2B3)}"

swift build -c release --product CardfileExtension --package-path "$ROOT"

APEX="$APP/Contents/PlugIns/Cardfile.appex"
rm -rf "$APEX"
mkdir -p "$APEX/Contents/MacOS" "$APEX/Contents/Resources"

cp "$ROOT/.build/release/CardfileExtension" "$APEX/Contents/MacOS/CardfileExtension"
cp "$ROOT/SafariExtension/Info.plist" "$APEX/Contents/Info.plist"
stamp_plist "$APEX/Contents/Info.plist"
cp "$ROOT/SafariExtension/Resources/extension-manifest.json" "$APEX/Contents/Resources/manifest.json"
stamp_json_version "$APEX/Contents/Resources/manifest.json"
cp "$ROOT/SafariExtension/Resources/popup.html" "$APEX/Contents/Resources/"
cp "$ROOT/SafariExtension/Resources/popup.js" "$APEX/Contents/Resources/"
cp "$ROOT/SafariExtension/Resources/popup.css" "$APEX/Contents/Resources/"
cp "$ROOT/SafariExtension/Resources/background.js" "$APEX/Contents/Resources/"
cp "$ROOT/SafariExtension/Resources/content.js" "$APEX/Contents/Resources/"
mkdir -p "$APEX/Contents/Resources/_locales/en" "$APEX/Contents/Resources/images"
cp "$ROOT/SafariExtension/Resources/_locales/en/messages.json" "$APEX/Contents/Resources/_locales/en/"
cp "$ROOT/SafariExtension/Resources/images/"*.png "$APEX/Contents/Resources/images/"

codesign --force --options runtime --timestamp \
  --entitlements "$ROOT/SafariExtension/CardfileExtension.entitlements" \
  --sign "$IDENTITY" "$APEX"
echo "Assembled $APEX"
