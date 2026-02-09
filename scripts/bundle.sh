#!/bin/bash
set -e

APP_NAME="Erdos"
BUNDLE_ID="com.adammccabe.erdos"
BUILD_DIR=$(cd "$(dirname "$0")/.." && pwd)
APP_DIR="$BUILD_DIR/build/${APP_NAME}.app"

echo "Building release..."
cd "$BUILD_DIR"
swift build -c release 2>&1

# Generate icon if not already present
ICNS_PATH="$BUILD_DIR/build/Erdos.icns"
if [ ! -f "$ICNS_PATH" ]; then
    echo "Generating app icon..."
    swift "$BUILD_DIR/scripts/generate-icon.swift"
fi

echo "Assembling ${APP_NAME}.app..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp ".build/release/Erdos" "$APP_DIR/Contents/MacOS/Erdos"

# Copy icon
if [ -f "$ICNS_PATH" ]; then
    cp "$ICNS_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>Erdos</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

echo ""
echo "Built: $APP_DIR"
echo ""
echo "To install:"
echo "  cp -r \"$APP_DIR\" /Applications/"
echo ""
echo "Or open directly:"
echo "  open \"$APP_DIR\""
