#!/usr/bin/env bash
# ARES uninstaller
#
# Usage:
#   bash uninstall.sh          Remove the ARES install (server, launchd, app command).
#                              Keeps your Companion (JaegerAI instance), profile, and
#                              Hermes config — reinstalling picks them back up.
#   bash uninstall.sh --purge  Also remove Companion instances, ~/.hermes, and the
#                              companion profile dir. Use for a truly fresh onboarding.

set -e

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }

PURGE=false
[ "${1:-}" = "--purge" ] && PURGE=true

echo "── ARES uninstall ──"

# 1. Stop processes
pkill -f "\.build/.*/ARES$" 2>/dev/null || true
pkill -f "swift run ARES" 2>/dev/null || true
pkill -f "$HOME/.ares/webui/server.py" 2>/dev/null || true
ok "Processes stopped"

# 2. launchd service
if [ -f "$HOME/Library/LaunchAgents/com.ares.webui.plist" ]; then
    launchctl unload "$HOME/Library/LaunchAgents/com.ares.webui.plist" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/com.ares.webui.plist"
    ok "launchd service removed"
fi

# 3. Production install
if [ -d "$HOME/.ares" ]; then
    rm -rf "$HOME/.ares"
    ok "~/.ares removed"
fi

# 4. Launcher command + Mac app defaults
rm -f "$HOME/.local/bin/ares"
rm -rf "$HOME/Applications/ARES.app"
defaults delete ARES 2>/dev/null || true
ok "Launcher command, ARES.app, and app defaults removed"

if [ "$PURGE" = false ]; then
    echo ""
    ok "Uninstalled. Companion data kept:"
    echo "    • JaegerAI instances:  ~/jaeger/.jaeger_os/instances/"
    echo "    • Companion profile:   ~/Desktop/ARES/companion/"
    echo "    • Hermes config:       ~/.hermes/"
    echo "  Run with --purge to remove those too (fresh onboarding)."
    exit 0
fi

# ── --purge: remove companion + agent state so onboarding starts fresh ──────
echo ""
echo "── Purging companion and agent state ──"

# Companion instances — these are what make onboarding think it already ran
for jh in "$HOME/jaeger" "$HOME/.jaeger"; do
    if [ -d "$jh/.jaeger_os/instances" ]; then
        rm -rf "$jh/.jaeger_os/instances"
        ok "Companion instances removed ($jh/.jaeger_os/instances)"
    fi
done

# Hermes state (old configs make onboarding auto-complete or misreport)
if [ -d "$HOME/.hermes" ]; then
    rm -rf "$HOME/.hermes"
    ok "~/.hermes removed"
fi
# Stale hermes wrapper pointing at a removed venv
if [ -f "$HOME/.local/bin/hermes" ]; then
    _target=$(grep -oE '"/[^"]*/bin/hermes"' "$HOME/.local/bin/hermes" 2>/dev/null | tr -d '"' || true)
    if [ -n "$_target" ] && [ ! -f "$_target" ]; then
        rm -f "$HOME/.local/bin/hermes"
        ok "Stale hermes wrapper removed"
    fi
fi

# Companion profile dir
if [ -d "$HOME/Desktop/ARES/companion" ]; then
    rm -rf "$HOME/Desktop/ARES/companion"
    ok "Companion profile removed (~/Desktop/ARES/companion)"
fi

echo ""
ok "Fully purged. Next install will run the complete onboarding sequence."
