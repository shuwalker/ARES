#!/usr/bin/env bash
# ARES controller control — thin wrapper that delegates to services/controller/ctl.sh.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/services/controller/ctl.sh"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: controller control script not found at $TARGET"
    echo "Make sure this script is run from the root of the ARES repository."
    exit 1
fi

exec bash "$TARGET" "$@"
