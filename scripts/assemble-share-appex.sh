#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/version.sh"
APP="${1:?app bundle path}"
IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: CHARLES B BONETTI (6KZQK3A2B3)}"

swift build -c release --product StowmarkShare --package-path "$ROOT"

APEX="$APP/Contents/PlugIns/StowmarkShare.appex"
rm -rf "$APEX"
mkdir -p "$APEX/Contents/MacOS" "$APEX/Contents/Resources"

cp "$ROOT/.build/release/StowmarkShare" "$APEX/Contents/MacOS/StowmarkShare"
cp "$ROOT/ShareExtension/Info.plist" "$APEX/Contents/Info.plist"
stamp_plist "$APEX/Contents/Info.plist"

# Developer ID is optional in this environment. Ad-hoc still produces a bundle the rest of the script can nest.
if command -v codesign >/dev/null 2>&1; then
  if command -v security >/dev/null 2>&1 && security find-identity -v -p codesigning 2>/dev/null | grep -F "$IDENTITY" >/dev/null; then
    codesign --force --options runtime --timestamp \
      --entitlements "$ROOT/ShareExtension/StowmarkShare.entitlements" \
      --sign "$IDENTITY" "$APEX"
  else
    echo "warning: signing identity not found; ad-hoc signing $APEX"
    codesign --force \
      --entitlements "$ROOT/ShareExtension/StowmarkShare.entitlements" \
      --sign - "$APEX"
  fi
else
  echo "warning: codesign is not available; $APEX was not signed"
fi
echo "Assembled $APEX"
