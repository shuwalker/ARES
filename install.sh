#!/usr/bin/env bash
# ARES Installation Script
# Thin wrapper that delegates to webui/scripts/install.sh
#
# All options are implemented by webui/scripts/install.sh. Keep this file a
# transparent delegator so documented clean-install and CI flags cannot drift.

set -e

# Find the webui installer relative to this script's location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBUI_INSTALLER="$SCRIPT_DIR/webui/scripts/install.sh"

if [ ! -f "$WEBUI_INSTALLER" ]; then
    echo "ERROR: WebUI installer not found at $WEBUI_INSTALLER"
    echo "Make sure this script is run from the root of the ARES repository."
    exit 1
fi

# Delegate every argument unchanged.
exec bash "$WEBUI_INSTALLER" "$@"
