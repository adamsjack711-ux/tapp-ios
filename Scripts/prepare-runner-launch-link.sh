#!/bin/bash
# Add iCTRL's documented start/callback link to the built runner, without
# changing pinned source or installing the optional companion app.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
runner="$project_root/DeveloperTools/iCTRL/build/Build/Products/Debug-iphoneos/iCTRLUITests-Runner.app"
plist="$runner/Info.plist"
test -f "$plist" || { echo "Build the runner first." >&2; exit 1; }
identity="$(codesign -dvv "$runner" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
[[ "$identity" == "Apple Development:"* ]] || { echo "Expected a developer-signed runner." >&2; exit 1; }
/usr/libexec/PlistBuddy -c 'Delete :CFBundleURLTypes' "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes array' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0 dict' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLName string com.openminis.ictrl' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes array' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string ictrl' "$plist"
codesign --force --sign "$identity" --preserve-metadata=entitlements --timestamp=none "$runner"
codesign --verify --deep --strict "$runner"
echo "Runner launch link prepared and signature verified. Install this generated app after the last build."
