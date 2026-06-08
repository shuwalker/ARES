#!/bin/bash
# Build ARES Desktop app bundle
# Creates a proper macOS .app with icon, plist, frameworks, and resources
# Based on SAM's Makefile pattern

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$(dirname "$PROJECT_DIR")/.build/arm64-apple-macosx/debug"
APP_NAME="ARES"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
VERSION="20260525.1"

echo "=== Building $APP_NAME.app ==="

# Step 1: Create app bundle structure
echo "Creating app bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Step 2: Copy binary
echo "Copying binary..."
cp "$BUILD_DIR/ARES" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Step 3: Copy dynamic frameworks
echo "Copying frameworks..."
if [ -d "$BUILD_DIR/PackageFrameworks" ]; then
    cp -R "$BUILD_DIR/PackageFrameworks/"* "$APP_BUNDLE/Contents/Frameworks/" 2>/dev/null || true
fi

# Copy Sparkle framework if it exists
SPARKLE_FW="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    cp -R "$SPARKLE_FW" "$APP_BUNDLE/Contents/Frameworks/"
    echo "  Sparkle.framework copied"
fi

# Copy llama framework if it exists
LLAMA_FW="$BUILD_DIR/llama.framework"
if [ -d "$LLAMA_FW" ]; then
    cp -R "$LLAMA_FW" "$APP_BUNDLE/Contents/Frameworks/"
    echo "  llama.framework copied"
fi

# Step 4: Copy resources
echo "Copying resources..."
# App icon
if [ -f "$PROJECT_DIR/Sources/ARES/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Sources/ARES/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    echo "  AppIcon.icns copied"
fi

# Resource bundle from SwiftPM build
RESOURCE_BUNDLE="$BUILD_DIR/ARES_ARES.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
    echo "  ARES_ARES.resource_bundle copied"
fi

# Step 5: Create Info.plist
echo "Creating Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ARES</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.jenkinsrobotics.ares-desktop</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ARES</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
PLIST
echo "    <string>${VERSION}</string>" >> "$APP_BUNDLE/Contents/Info.plist"
cat >> "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
    <key>CFBundleVersion</key>
PLIST
echo "    <string>${VERSION}</string>" >> "$APP_BUNDLE/Contents/Info.plist"
cat >> "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSAppleEventsUsageDescription</key>
    <string>ARES uses Apple Events to interact with Notes, Mail, and other apps on your behalf.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>ARES uses Calendar to create events and check your schedule.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>ARES uses Calendar to create events and check your schedule.</string>
    <key>NSContactsUsageDescription</key>
    <string>ARES uses Contacts to search and manage your contacts.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright (c) 2025-2026 Jenkins Robotics. All rights reserved.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>ARES needs microphone access for voice input.</string>
    <key>NSNetworkUsageDescription</key>
    <string>ARES requires network access for AI model interactions, web research, and remote device management.</string>
    <key>NSRemindersUsageDescription</key>
    <string>ARES uses Reminders to create and manage your tasks.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>ARES uses Reminders to create and manage your tasks.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>ARES uses speech recognition to process your voice commands.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/shuwalker/ARES/main/appcast.xml</string>
</dict>
</plist>
PLIST

# Step 6: Create PkgInfo
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Step 7: Codesign (ad-hoc, no Developer ID needed for local use)
echo "Codesigning..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || {
    echo "Warning: codesign failed (ad-hoc signing). App will work locally but may not pass Gatekeeper on other Macs."
}

# Done
echo ""
echo "=== Build Complete ==="
echo "App bundle: $APP_BUNDLE"
echo "Binary size: $(du -sh "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | cut -f1)"
echo "Bundle size: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo ""
echo "To run: open \"$APP_BUNDLE\""
echo "To add to Dock: drag \"$APP_BUNDLE\" to Dock"