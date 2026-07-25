#!/bin/bash
<<<<<<< HEAD
# ARES Web UI launcher.
=======
# ARES Web UI launcher — replaces the old Ares WebUI on port 8787.
>>>>>>> wip/multiagent-orchestrator
# Binds to 0.0.0.0 so it's reachable over Tailscale.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

<<<<<<< HEAD
# ARES owns its listener and state namespace.
export ARES_WEBUI_PORT="${ARES_WEBUI_PORT:-8788}"
export ARES_WEBUI_HOST="${ARES_WEBUI_HOST:-0.0.0.0}"

export ARES_HOME="${ARES_HOME:-$HOME/.ares}"
export ARES_WEBUI_STATE_DIR="${ARES_WEBUI_STATE_DIR:-$ARES_HOME/webui}"
=======
# Port: ARES takes over port 8787 (same port the old Ares WebUI used)
export ARES_WEBUI_PORT="${ARES_WEBUI_PORT:-8787}"
export ARES_WEBUI_HOST="${ARES_WEBUI_HOST:-0.0.0.0}"

# Separate state dir — ARES has its own sessions, settings, and database
export ARES_WEBUI_STATE_DIR="${ARES_WEBUI_STATE_DIR:-$DIR/.ares_state}"

# Point at the same Ares Agent install (the brain)
export ARES_HOME="${ARES_HOME:-$HOME/.ares}"
>>>>>>> wip/multiagent-orchestrator

# Point ARES at the standard local JROS/Jaeger install when present.
if [ -z "${ARES_JAEGER_HOME:-}" ] && [ -x "$HOME/jaeger/jaeger" ]; then
  export ARES_JAEGER_HOME="$HOME/jaeger"
fi
if [ -n "${ARES_JAEGER_HOME:-}" ] && [ -z "${JAEGER_HOME:-}" ]; then
  export JAEGER_HOME="$ARES_JAEGER_HOME"
fi

<<<<<<< HEAD
# Use the ARES venv when available.
PYBIN="${ARES_WEBUI_PYTHON:-$DIR/.venv/bin/python}"
if [ ! -x "$PYBIN" ]; then
  PYBIN="$(command -v python3 || command -v python)"
=======
# Use the WebUI venv (installed by pip install or start_ares.sh)
# Fall back to Ares Agent venv if the local one doesn't exist.
if [ -x "$DIR/.venv/bin/python" ]; then
  PYBIN="$DIR/.venv/bin/python"
elif [ -x "$ARES_HOME/ares-agent/venv/bin/python" ]; then
  PYBIN="$ARES_HOME/ares-agent/venv/bin/python"
else
  echo "ERROR: No Python venv found. Run 'python -m venv .venv && .venv/bin/pip install -e .' first." >&2
  exit 1
>>>>>>> wip/multiagent-orchestrator
fi

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
