#!/bin/bash
# build_app.sh — Build ARES.app macOS bundle
# Usage: ./build_app.sh [--install]
#   --install: also copy to /Applications and register with LaunchServices

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$REPO_DIR/build"
APP_NAME="ARES"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SWIFT_DIR="$REPO_DIR/ARES-Face"

echo "🔧 Building ARES.app..."

# 1. Build the Swift binary
echo "   Building Swift binary..."
cd "$SWIFT_DIR"
swift build --configuration debug 2>&1 | tail -3

# 2. Create app bundle structure (clean build)
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/Shaders"

# 3. Copy binary
cp "$SWIFT_DIR/.build/debug/ARES-Face" "$APP_BUNDLE/Contents/MacOS/ARES-Face"
chmod +x "$APP_BUNDLE/Contents/MacOS/ARES-Face"

# 4. Copy launcher script as CFBundleExecutable
cp "$REPO_DIR/build/ARES-launcher.sh" "$APP_BUNDLE/Contents/MacOS/ARES"
chmod +x "$APP_BUNDLE/Contents/MacOS/ARES"

# 5. Copy Info.plist from template
cp "$REPO_DIR/Info.plist.template" "$APP_BUNDLE/Contents/Info.plist"

# 6. Copy icon
if [ -f "$SWIFT_DIR/AppIcon.icns" ]; then
    cp "$SWIFT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "   Icon installed"
else
    echo "   WARNING: No AppIcon.icns found"
fi

# 7. Copy shaders as resources
cp "$SWIFT_DIR/ARES-Face/Shaders/"*.metal "$APP_BUNDLE/Contents/Resources/Shaders/" 2>/dev/null || true
cp "$SWIFT_DIR/ARES-Face/Shaders/"*.h "$APP_BUNDLE/Contents/Resources/Shaders/" 2>/dev/null || true
cp "$SWIFT_DIR/ARES-Face/Shaders/module.modulemap" "$APP_BUNDLE/Contents/Resources/Shaders/" 2>/dev/null || true

# 8. PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "✅ Built: $APP_BUNDLE"
BINARY_SIZE=$(du -h "$APP_BUNDLE/Contents/MacOS/ARES-Face" | cut -f1)
echo "   Binary: $BINARY_SIZE"
echo "   Icon:  $([ -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ] && echo "yes" || echo "no")"
echo "   Shaders: $(ls "$APP_BUNDLE/Contents/Resources/Shaders/"*.metal 2>/dev/null | wc -l | tr -d ' ') .metal files"
echo "   Launcher: $APP_BUNDLE/Contents/MacOS/ARES"

# Optional: install to /Applications
if [ "${1:-}" = "--install" ]; then
    echo "📦 Installing to /Applications..."
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    
    # Register with LaunchServices so Spotlight and Dock see it
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "/Applications/$APP_NAME.app" 2>/dev/null || true
    
    # Touch to update Dock cache
    touch "/Applications/$APP_NAME.app"
    
    echo "✅ Installed to /Applications/$APP_NAME.app"
    echo "   Open it and drag to your Dock to pin it."
fi

echo ""
echo "🚀 To run: open $APP_BUNDLE"
echo "   Or:     $APP_BUNDLE/Contents/MacOS/ARES"