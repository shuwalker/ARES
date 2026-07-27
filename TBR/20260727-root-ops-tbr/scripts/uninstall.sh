#!/bin/bash
# uninstall.sh — Clean uninstaller for ARES app, services, and CLI launcher
set -euo pipefail

echo "=== Uninstalling ARES ==="

# 1. Stop processes
echo "→ Stopping ARES processes..."
pkill -9 ARES 2>/dev/null || true
pkill -9 -f "server.py" 2>/dev/null || true

# 2. Unload launchd agent
echo "→ Removing launchd auto-start agent..."
launchctl unload "$HOME/Library/LaunchAgents/com.ares.webui.plist" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.ares.webui.plist"

# 3. Remove Mac App bundle
echo "→ Removing ARES.app..."
rm -rf "$HOME/Applications/ARES.app" "/Applications/ARES.app" 2>/dev/null || true

# 4. Remove CLI launcher
echo "→ Removing CLI launcher..."
rm -f "$HOME/.local/bin/ares"

# 5. Reset UserDefaults
echo "→ Removing app preferences..."
defaults delete ARES 2>/dev/null || true
defaults delete com.jenkinsrobotics.ares-desktop 2>/dev/null || true

# 6. Remove ~/.ares symlink or folder if requested
if [ -L "$HOME/.ares" ]; then
    echo "→ Removing ~/.ares symlink..."
    rm -f "$HOME/.ares"
fi

echo ""
echo "✓ ARES has been completely uninstalled."
