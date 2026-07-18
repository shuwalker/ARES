#!/usr/bin/env bash
# ARES Installation Script
# Thin wrapper that delegates to webui/scripts/install.sh
#
# Usage:
#   bash install.sh [--backend auto|ares|jros|hybrid] [--no-start]
#
# Options:
#   --backend MODE  Backend mode: auto, ares, jros, or hybrid (default: auto)
#   --no-start      Skip auto-starting the server after installation

set -e

# Collect extra args to pass through to the webui installer
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --backend)
            EXTRA_ARGS+=("--backend" "$2")
            shift 2
            ;;
        --no-start)
            EXTRA_ARGS+=("--no-start")
            shift
            ;;
        -h|--help)
            echo "ARES Installation Script"
            echo ""
            echo "Usage: bash install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --backend MODE  Backend mode: auto, ares, jros, or hybrid (default: auto)"
            echo "  --no-start      Skip auto-starting the server after installation"
            echo "  -h, --help      Show this help"
            echo ""
            echo "For full options, see: webui/scripts/install.sh --help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: bash install.sh [--backend auto|ares|jros|hybrid] [--no-start]"
            exit 1
            ;;
    esac
done

# Find the webui installer relative to this script's location
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

# Delegate to the webui installer with any extra args
exec bash "$WEBUI_INSTALLER" "${EXTRA_ARGS[@]}"