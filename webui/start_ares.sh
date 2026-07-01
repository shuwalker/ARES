#!/bin/bash
# ARES Web UI launcher — replaces the old Hermes WebUI on port 8787.
# Binds to 0.0.0.0 so it's reachable over Tailscale.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

# Port: ARES takes over port 8787 (same port the old Hermes WebUI used)
export HERMES_WEBUI_PORT="${ARES_WEBUI_PORT:-8787}"
export HERMES_WEBUI_HOST="${ARES_WEBUI_HOST:-0.0.0.0}"

# Separate state dir — ARES has its own sessions, settings, and database
export HERMES_WEBUI_STATE_DIR="${HERMES_WEBUI_STATE_DIR:-$DIR/.ares_state}"

# Point at the same Hermes Agent install (the brain)
export HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

# Use the Hermes Agent venv (Python 3.11) — the WebUI needs 3.10+
PYBIN="$HERMES_HOME/hermes-agent/venv/bin/python"

# Create state dir if needed
mkdir -p "$HERMES_WEBUI_STATE_DIR"

echo "Starting ARES Web UI on port $HERMES_WEBUI_PORT (host: $HERMES_WEBUI_HOST)..."
echo "State dir: $HERMES_WEBUI_STATE_DIR"
echo "Source: $DIR"
exec "$PYBIN" "$DIR/server.py"