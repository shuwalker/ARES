#!/bin/bash
# Compatibility entrypoint. There is one authoritative app-bundle builder so
# signing, resources, helper binaries, and Info.plist metadata cannot drift.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/../build-app.sh" "$@"
