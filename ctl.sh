#!/usr/bin/env bash
# ARES Web UI control — thin wrapper that delegates to webui/ctl.sh.
# The web app lives entirely under webui/; this keeps `./ctl.sh` from the
# repo root working the way it always has.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/webui/ctl.sh"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: webui control script not found at $TARGET"
    echo "Make sure this script is run from the root of the ARES repository."
    exit 1
fi

exec bash "$TARGET" "$@"
