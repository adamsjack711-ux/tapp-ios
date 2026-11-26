#!/bin/sh
set -eu
[ "$PLATFORM_NAME" = iphonesimulator ] || { echo 'Companion runtime is simulator-only' >&2; exit 1; }
tapp_runtime="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/CompanionRuntime.app"
mkdir -p "$tapp_runtime"
"$DT_TOOLCHAIN_DIR/usr/bin/clang" -target arm64-apple-ios17.0-simulator -isysroot "$SDKROOT" -fobjc-arc -framework UIKit -framework QuartzCore -framework CoreGraphics "$SRCROOT/CompanionRuntime.m" "$SRCROOT/DraftRocketRenderer.m" -o "$tapp_runtime/CompanionRuntime"
cat > "$tapp_runtime/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.jackadamslovell.TappColorStudy.CompanionRuntime</string>
<key>CFBundleExecutable</key><string>CompanionRuntime</string>
<key>CFBundleName</key><string>Tapp Simulator Companion</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
</dict></plist>
PLIST
