#!/bin/bash
# ARES Web UI launcher.
# Binds to 0.0.0.0 so it's reachable over Tailscale.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

# ARES owns its listener and state namespace.
export ARES_WEBUI_PORT="${ARES_WEBUI_PORT:-8788}"
export ARES_WEBUI_HOST="${ARES_WEBUI_HOST:-0.0.0.0}"

export ARES_HOME="${ARES_HOME:-$HOME/.ares}"
export ARES_WEBUI_STATE_DIR="${ARES_WEBUI_STATE_DIR:-$ARES_HOME/webui}"

# Point ARES at the standard local JROS/Jaeger install when present.
if [ -z "${ARES_JAEGER_HOME:-}" ] && [ -x "$HOME/jaeger/jaeger" ]; then
  export ARES_JAEGER_HOME="$HOME/jaeger"
fi
if [ -n "${ARES_JAEGER_HOME:-}" ] && [ -z "${JAEGER_HOME:-}" ]; then
  export JAEGER_HOME="$ARES_JAEGER_HOME"
fi

# Use the ARES venv when available.
PYBIN="${ARES_WEBUI_PYTHON:-$DIR/.venv/bin/python}"
if [ ! -x "$PYBIN" ]; then
  PYBIN="$(command -v python3 || command -v python)"
fi

# Create state dir if needed
mkdir -p "$ARES_WEBUI_STATE_DIR"

echo "Starting ARES Web UI on port $ARES_WEBUI_PORT (host: $ARES_WEBUI_HOST)..."
echo "State dir: $ARES_WEBUI_STATE_DIR"
echo "Source: $DIR"
if [ -n "${ARES_JAEGER_HOME:-}" ]; then
  echo "JROS home: $ARES_JAEGER_HOME"
fi
exec "$PYBIN" "$DIR/server.py"
