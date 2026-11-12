#!/bin/bash
# Builds EncoConsole.app from the SwiftPM release binary and ad-hoc codesigns it.
# Usage: ./Scripts/make_app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP_NAME="Enco Console"
APP_DIR="build/${APP_NAME}.app"
BIN=".build/release/EncoConsole"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/EncoConsole"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Enco Console</string>
    <key>CFBundleDisplayName</key>
    <string>Enco Console</string>
    <key>CFBundleExecutable</key>
    <string>EncoConsole</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.encoconsole.EncoConsole</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Enco Console connects to your paired OPPO Enco earbuds over Bluetooth to read status and adjust settings.</string>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License. Unofficial community tool, not affiliated with OPPO.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR"

echo "Built $APP_DIR"
echo "First launch: right-click the app and choose Open, or run:"
echo "  xattr -d com.apple.quarantine '$APP_DIR'   # only if you downloaded the zip"
