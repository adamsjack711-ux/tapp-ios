#!/bin/bash
# Package the already built WidgetKit extension into XCTest's generated host.
# Changes only the task's generated product. Preserves existing signing rights.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
products="$project_root/DerivedData/RunnerStatus/Build/Products/Debug-iphoneos"
runner_app="$products/iCTRLUITests-Runner.app"
widget_app="$products/PocketAgentActivity.appex"
runner_plist="$runner_app/Info.plist"
test -f "$runner_plist" && test -f "$widget_app/Info.plist"
runner_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$runner_plist")"
widget_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$widget_app/Info.plist")"
[[ "$runner_id" == *.ictrl.uitests.xctrunner && "$widget_id" == "$runner_id.activity" ]] || { echo 'Unexpected bundle identifiers.' >&2; exit 1; }
identity="$(codesign -dvv "$runner_app" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
[[ "$identity" == "Apple Development:"* ]] || { echo 'Expected development signature.' >&2; exit 1; }
mkdir -p "$runner_app/PlugIns"
ditto "$widget_app" "$runner_app/PlugIns/PocketAgentActivity.appex"
/usr/libexec/PlistBuddy -c 'Delete :NSSupportsLiveActivities' "$runner_plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :NSSupportsLiveActivities bool true' "$runner_plist"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleURLTypes' "$runner_plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes array' "$runner_plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0 dict' "$runner_plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLName string com.openminis.ictrl' "$runner_plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes array' "$runner_plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string ictrl' "$runner_plist"
codesign --verify --strict "$runner_app/PlugIns/PocketAgentActivity.appex"
codesign --force --sign "$identity" --preserve-metadata=entitlements --timestamp=none "$runner_app"
codesign --verify --deep --strict "$runner_app"
echo "Ready to install: $runner_app"
