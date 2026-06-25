#!/bin/zsh
set -e

echo "Building..."
swift build -c release

APP="GPU-Monitor.app"
BUNDLE="GPU-Monitor.app/Contents"
MACOS="$BUNDLE/MacOS"
RESOURCES="$BUNDLE/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp -f .build/release/GPU-Monitor "$MACOS/"

cat > "$BUNDLE/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>GPU-Monitor</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.gpu-monitor.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>GPU Monitor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMainStoryboardFile</key>
    <string></string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
PLIST

cp -f .build/release/GPU-Monitor.app.dSYM "$BUNDLE/" 2>/dev/null || true

if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "$RESOURCES/"
fi

# Codesign the application bundle to prevent macOS security/firewall warnings
echo "Codesigning..."
codesign --force --deep --sign - "$APP"

echo ""
echo "✓ Built GPU-Monitor.app"
echo "  Run: open GPU-Monitor.app"

