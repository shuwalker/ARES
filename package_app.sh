#!/bin/bash
set -e

echo "📦 Packaging ARES.app..."

APP_NAME="ARES.app"
CONTENTS_DIR="${APP_NAME}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# 1. Clean previous app
rm -rf "${APP_NAME}"

# 2. Create standard macOS app structure
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 3. Build ARES executable
echo "🔨 Building ARES (release mode)..."
swift build -c release

# 4. Copy executable
EXECUTABLE_PATH=$(swift build -c release --show-bin-path)/ARES
if [ -f "$EXECUTABLE_PATH" ]; then
    cp "$EXECUTABLE_PATH" "${MACOS_DIR}/ARES"
    echo "✅ Executable copied to ${MACOS_DIR}/ARES"
else
    echo "❌ Executable not found at $EXECUTABLE_PATH"
    exit 1
fi

# 5. Copy Info.plist
cp Info.plist.template "${CONTENTS_DIR}/Info.plist"

# 6. Copy Resources if any
# Find the bundle containing resources (SwiftPM generates bundles)
BUNDLE_DIR=$(find $(swift build -c release --show-bin-path) -name "*.bundle" | head -n 1)
if [ -n "$BUNDLE_DIR" ]; then
    cp -R "$BUNDLE_DIR"/* "${RESOURCES_DIR}/" || true
    echo "✅ Resources copied"
fi

echo "🚀 ARES.app is packaged!"
echo "Run it using: open ARES.app"
