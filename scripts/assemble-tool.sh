#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/version.sh"
APP="${1:?app bundle path}"
IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: CHARLES B BONETTI (6KZQK3A2B3)}"

# The diagnostic tool is sandboxed like the app, so it needs a bundle identity to launch at all.
swift build -c release --product CardfileTool --package-path "$ROOT"

TOOL_APP="$APP/Contents/Helpers/CardfileTool.app"
rm -rf "$TOOL_APP" "$APP/Contents/Helpers/CardfileTool"
mkdir -p "$TOOL_APP/Contents/MacOS"
cp "$ROOT/.build/release/CardfileTool" "$TOOL_APP/Contents/MacOS/CardfileTool"
cp "$ROOT/ChromeHost/ToolInfo.plist" "$TOOL_APP/Contents/Info.plist"
stamp_plist "$TOOL_APP/Contents/Info.plist"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/App/Cardfile.entitlements" --sign "$IDENTITY" "$TOOL_APP"
else
  echo "warning: $IDENTITY not available, ad-hoc signing the tool" >&2
  codesign --force --entitlements "$ROOT/App/Cardfile.entitlements" --sign - "$TOOL_APP"
fi
echo "Assembled $TOOL_APP"
