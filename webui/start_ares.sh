#!/bin/bash
# ARES Web UI launcher — replaces the old Ares WebUI on port 8787.
# Binds to 0.0.0.0 so it's reachable over Tailscale.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

# Port: ARES takes over port 8787 (same port the old Ares WebUI used)
export ARES_WEBUI_PORT="${ARES_WEBUI_PORT:-8787}"
export ARES_WEBUI_HOST="${ARES_WEBUI_HOST:-0.0.0.0}"

# Separate state dir — ARES has its own sessions, settings, and database
export ARES_WEBUI_STATE_DIR="${ARES_WEBUI_STATE_DIR:-$DIR/.ares_state}"

# Point at the same Ares Agent install (the brain)
export ARES_HOME="${ARES_HOME:-$HOME/.ares}"

# Point ARES at the standard local JROS/Jaeger install when present.
if [ -z "${ARES_JAEGER_HOME:-}" ] && [ -x "$HOME/jaeger/jaeger" ]; then
  export ARES_JAEGER_HOME="$HOME/jaeger"
fi
if [ -n "${ARES_JAEGER_HOME:-}" ] && [ -z "${JAEGER_HOME:-}" ]; then
  export JAEGER_HOME="$ARES_JAEGER_HOME"
fi

# Use the Ares Agent venv (Python 3.11) — the WebUI needs 3.10+
PYBIN="$ARES_HOME/ares-agent/venv/bin/python"

# Create state dir if needed
mkdir -p "$ARES_WEBUI_STATE_DIR"

echo "Starting ARES Web UI on port $ARES_WEBUI_PORT (host: $ARES_WEBUI_HOST)..."
echo "State dir: $ARES_WEBUI_STATE_DIR"
echo "Source: $DIR"
if [ -n "${ARES_JAEGER_HOME:-}" ]; then
  echo "JROS home: $ARES_JAEGER_HOME"
fi
cd "$DIR"
exec "$PYBIN" -m uvicorn fastapi_app.main:app \
  --host "$ARES_WEBUI_HOST" --port "$ARES_WEBUI_PORT" --no-server-header
