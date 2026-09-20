#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/version.sh"
APP="${1:?app bundle path}"
IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: CHARLES B BONETTI (6KZQK3A2B3)}"

# Chrome spawns this helper itself. It is wrapped in a background-only bundle because a sandboxed
# process needs a bundle identity to get a container, and it needs the App Group to reach the same
# library Safari writes to.
swift build -c release --product StowmarkChromeHost --package-path "$ROOT"

HOST_APP="$APP/Contents/Helpers/StowmarkChromeHost.app"
rm -rf "$HOST_APP" "$APP/Contents/Helpers/StowmarkChromeHost"
mkdir -p "$HOST_APP/Contents/MacOS"
cp "$ROOT/.build/release/StowmarkChromeHost" "$HOST_APP/Contents/MacOS/StowmarkChromeHost"
cp "$ROOT/ChromeHost/Info.plist" "$HOST_APP/Contents/Info.plist"
stamp_plist "$HOST_APP/Contents/Info.plist"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/ChromeHost/StowmarkChromeHost.entitlements" \
    --sign "$IDENTITY" "$HOST_APP"
else
  echo "warning: $IDENTITY not available, ad-hoc signing the Chrome host" >&2
  codesign --force --entitlements "$ROOT/ChromeHost/StowmarkChromeHost.entitlements" \
    --sign - "$HOST_APP"
fi
echo "Assembled $HOST_APP"
