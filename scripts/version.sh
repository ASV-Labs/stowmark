#!/bin/zsh
# Single source of truth: the VERSION file at the repo root.
# Marketing string is the full alpha tag (1.0.0-alpha.10).
# Build number is the integer after "alpha." so Finder and CFBundleVersion stay in lockstep.
#
# Usage from other scripts (after setting ROOT):
#   source "$ROOT/scripts/version.sh"
# Then use $VERSION, $MARKETING, $BUILD, and stamp_plist / stamp_json_version.

[[ -n "${ROOT:-}" ]] || { echo "version.sh: ROOT must be set" >&2; return 1 2>/dev/null || exit 1; }

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
MARKETING="$VERSION"
if [[ "$VERSION" == *alpha.* ]]; then
  BUILD="${VERSION##*alpha.}"
else
  BUILD="${VERSION##*.}"
fi

stamp_plist() {
  local plist="${1:?plist path}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $MARKETING" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD" "$plist"
}

stamp_json_version() {
  local json="${1:?json path}"
  python3 - "$json" "$MARKETING" <<'PY'
import json, sys
path, version = sys.argv[1], sys.argv[2]
with open(path) as handle:
    data = json.load(handle)
data["version"] = version
with open(path, "w") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
}
