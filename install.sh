#!/usr/bin/env bash
# ARES Installation Script
# Thin wrapper that delegates to webui/scripts/install.sh, then launches the
# Mac app on macOS (which starts the web server itself via WebUIServerManager).
#
# Usage:
#   bash install.sh [--backend auto|hermes|jros|hybrid] [--no-start] [--with-hermes]
#
# Options:
#   --backend MODE  Backend mode: auto, hermes, jros, or hybrid (default: auto)
#   --no-start      Skip auto-starting after installation
#   --with-hermes   Also install Hermes Agent (optional coding/terminal addition)

set -e

EXTRA_ARGS=()
NO_START=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --backend)
            EXTRA_ARGS+=("--backend" "$2")
            shift 2
            ;;
        --no-start)
            NO_START=true
            EXTRA_ARGS+=("--no-start")
            shift
            ;;
        --with-hermes)
            EXTRA_ARGS+=("--with-hermes")
            shift
            ;;
        -h|--help)
            echo "ARES Installation Script"
            echo ""
            echo "Usage: bash install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --backend MODE  Backend mode: auto, hermes, jros, or hybrid (default: auto)"
            echo "  --no-start      Skip auto-starting after installation"
            echo "  --with-hermes   Also install Hermes Agent (optional coding/terminal addition)"
            echo "  -h, --help      Show this help"
            echo ""
            echo "For full options, see: webui/scripts/install.sh --help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: bash install.sh [--backend auto|hermes|jros|hybrid] [--no-start]"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBUI_INSTALLER="$SCRIPT_DIR/webui/scripts/install.sh"

if [ ! -f "$WEBUI_INSTALLER" ]; then
    echo "ERROR: WebUI installer not found at $WEBUI_INSTALLER"
    echo "Make sure this script is run from the root of the ARES repository."
    exit 1
fi

echo "======================================"
echo "  ARES — Installation"
echo "======================================"
echo ""

# On macOS with Swift available, launch the Mac app after install —
# the Mac app adopts the already-running launchd server immediately
# instead of starting its own copy, so there is no duplicate start.
USE_MAC_APP=false
if [ "$NO_START" = false ] \
   && [ "$(uname -s)" = "Darwin" ] \
   && [ -f "$SCRIPT_DIR/Package.swift" ] \
   && command -v swift >/dev/null 2>&1; then
    USE_MAC_APP=true
    EXTRA_ARGS+=("--no-start")
fi

bash "$WEBUI_INSTALLER" "${EXTRA_ARGS[@]}"

if [ "$NO_START" = true ]; then
    exit 0
fi

# ── macOS: install a launchd service so the web server pre-starts at login ────
# This lets the Mac app open to the companion interface instantly — the server
# is already running by the time the app window appears.
_setup_launchd() {
    local plist_dir="$HOME/Library/LaunchAgents"
    local plist="$plist_dir/com.ares.webui.plist"
    local python="$HOME/.ares/webui/venv/bin/python"
    local server="$HOME/.ares/webui/server.py"
    local workdir="$HOME/.ares/webui"
    local logfile="$HOME/.ares/webui.log"

    if [ ! -f "$python" ]; then
        echo "→ launchd setup skipped (venv not found at $python)"
        return 0
    fi

    # Detect JAEGER_HOME from installed config or common paths
    local jaeger_home=""
    local cfg="$HOME/.ares/config.yaml"
    if [ -f "$cfg" ]; then
        local cfg_val
        cfg_val=$(grep -E '^ares_jaeger_home:' "$cfg" 2>/dev/null | sed 's/^ares_jaeger_home:[[:space:]]*//' | tr -d '"' | tr -d "'" | xargs)
        [ -n "$cfg_val" ] && [ -d "$cfg_val" ] && jaeger_home="$cfg_val"
    fi
    if [ -z "$jaeger_home" ]; then
        for p in "$HOME/jaeger" "$HOME/.jaeger"; do
            [ -d "$p" ] && jaeger_home="$p" && break
        done
    fi

    mkdir -p "$plist_dir"
    cat > "$plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ares.webui</string>
    <key>ProgramArguments</key>
    <array>
        <string>$python</string>
        <string>$server</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>ARES_JAEGER_HOME</key>
        <string>$jaeger_home</string>
        <key>JAEGER_HOME</key>
        <string>$jaeger_home</string>
        <key>HERMES_WEBUI_HOST</key>
        <string>0.0.0.0</string>
        <key>HERMES_WEBUI_PORT</key>
        <string>8787</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>$workdir</string>
    <key>StandardOutPath</key>
    <string>$logfile</string>
    <key>StandardErrorPath</key>
    <string>$logfile</string>
</dict>
</plist>
PLIST_EOF

    # Reload so the updated plist takes effect
    launchctl unload "$plist" 2>/dev/null || true
    if launchctl load "$plist" 2>/dev/null; then
        echo "→ ARES web server: auto-start at login enabled (com.ares.webui)"
        # Start it right now so the Mac app opens to the companion immediately
        launchctl start com.ares.webui 2>/dev/null || true
        echo "→ Starting ARES web server in background..."
        sleep 3  # Give Python server time to boot before Mac app tries to connect
    else
        echo "→ launchd load failed — Mac app will start the server on first open"
    fi
}

if [ "$USE_MAC_APP" = true ]; then
    _setup_launchd
    echo ""
    echo "→ Launching ARES Mac app (builds if needed, then opens)..."
    cd "$SCRIPT_DIR"
    swift run ARES
else
    # Non-macOS or no Swift — webui installer already handled start above
    :
fi