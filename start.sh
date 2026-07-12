#!/usr/bin/env bash
# ARES Web UI launcher — thin wrapper that delegates to webui/start.sh.
# The web app lives entirely under webui/; this keeps `./start.sh` from the
# repo root working the way it always has.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/webui/start.sh"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: webui launcher not found at $TARGET"
    echo "Make sure this script is run from the root of the ARES repository."
    exit 1
fi

exec bash "$TARGET" "$@"
