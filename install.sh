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
# it starts the web server itself via WebUIServerManager, so we suppress
# the webui installer's own server launch to avoid a duplicate start.
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

if [ "$USE_MAC_APP" = true ]; then
    echo ""
    echo "→ Launching ARES Mac app (builds if needed, then opens)..."
    cd "$SCRIPT_DIR"
    swift run ARES
else
    # Non-macOS or no Swift — webui installer already handled start above
    :
fi