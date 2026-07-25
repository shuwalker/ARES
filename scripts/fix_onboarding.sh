#!/bin/bash
# fix_onboarding.sh — Automated script for ARES Mac App onboarding fixes & build sync
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "=== ARES Onboarding & App Fix Dispatcher ==="
echo "Repo root: $REPO_DIR"

# 1. Clean up stale directories & enforce single workspace
echo "→ Cleaning up stale directories..."
rm -rf "$REPO_DIR/ARES-Mac_os" "$HOME/.ares-src" 2>/dev/null || true

# 2. Enforce ~/.ares symlink to repo
if [ ! -L "$HOME/.ares" ]; then
    echo "→ Creating ~/.ares symlink to $REPO_DIR..."
    rm -rf "$HOME/.ares" 2>/dev/null || true
    ln -s "$REPO_DIR" "$HOME/.ares"
fi

# 3. Sync persona cards artwork
echo "→ Syncing character persona cards artwork..."
mkdir -p "$REPO_DIR/ARES-Desktop/Sources/ARES/Resources/Characters"
if [ -d "$REPO_DIR/webui/static/persona-cards" ]; then
    cp "$REPO_DIR/webui/static/persona-cards/"*.png "$REPO_DIR/ARES-Desktop/Sources/ARES/Resources/Characters/" 2>/dev/null || true
fi

# 4. Rebuild Swift desktop application
echo "→ Building ARES.app bundle..."
bash "$REPO_DIR/ARES-Desktop/build-app.sh"

# 5. Reset onboarding state & launch fresh app
echo "→ Launching ARES setup..."
pkill -9 ARES 2>/dev/null || true
defaults delete ARES 2>/dev/null || true
open "$HOME/Applications/ARES.app"

echo "✓ ARES Onboarding & App Fix Complete!"
