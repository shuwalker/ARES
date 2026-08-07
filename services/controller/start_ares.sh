#!/bin/bash
# ARES Web UI launcher — dedicated to ARES on port 8788.
# Binds to 0.0.0.0 so it's reachable over Tailscale.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

# Port 8787 is reserved for Hermes WebUI.
export ARES_WEBUI_PORT="${ARES_WEBUI_PORT:-8788}"
export ARES_WEBUI_HOST="${ARES_WEBUI_HOST:-0.0.0.0}"

# Separate state dir — ARES has its own sessions, settings, and database
export ARES_WEBUI_STATE_DIR="${ARES_WEBUI_STATE_DIR:-$DIR/.ares_state}"

# PID file for single-instance enforcement
_PID_FILE="${ARES_WEBUI_STATE_DIR}/webui-${ARES_WEBUI_PORT}.pid"

# Point at the same Ares Agent install (the brain)
export ARES_HOME="${ARES_HOME:-$HOME/.ares}"

# Point ARES at the standard local JROS/Jaeger install when present.
if [ -z "${ARES_JAEGER_HOME:-}" ] && [ -x "$HOME/jaeger/jaeger" ]; then
  export ARES_JAEGER_HOME="$HOME/jaeger"
fi
if [ -n "${ARES_JAEGER_HOME:-}" ] && [ -z "${JAEGER_HOME:-}" ]; then
  export JAEGER_HOME="$ARES_JAEGER_HOME"
fi

# ── Single-instance guard ──────────────────────────────────────────────────
# Refuse to start if a live HTTP server is already responding on this port.
# This prevents the dual-bind problem (0.0.0.0 + 127.0.0.1 both on :8788).
_probe_host="127.0.0.1"
if [ "$ARES_WEBUI_HOST" != "0.0.0.0" ] && [ "$ARES_WEBUI_HOST" != "::" ] && [ -n "$ARES_WEBUI_HOST" ]; then
  _probe_host="$ARES_WEBUI_HOST"
fi

if command -v curl &>/dev/null; then
  if curl -sS -m 2 "http://${_probe_host}:${ARES_WEBUI_PORT}/health" >/dev/null 2>&1; then
    echo "[!!] FATAL: ARES is already running on ${_probe_host}:${ARES_WEBUI_PORT}." >&2
    echo "       Stop the existing instance first, e.g.:" >&2
    echo "         kill \$(cat $_PID_FILE) 2>/dev/null" >&2
    echo "         lsof -tiTCP:${ARES_WEBUI_PORT} -sTCP:LISTEN | xargs kill" >&2
    exit 1
  fi
fi

# Stale PID file cleanup: if pidfile exists but the process is gone, remove it.
if [ -f "$_PID_FILE" ]; then
  _old_pid=$(cat "$_PID_FILE" 2>/dev/null || echo "")
  if [ -n "$_old_pid" ] && ! kill -0 "$_old_pid" 2>/dev/null; then
    rm -f "$_PID_FILE"
  fi
fi
# ────────────────────────────────────────────────────────────────────────────

# Use the WebUI venv (installed by pip install or start_ares.sh)
# Fall back to Ares Agent venv if the local one doesn't exist.
if [ -x "$DIR/.venv/bin/python" ]; then
  PYBIN="$DIR/.venv/bin/python"
elif [ -x "$ARES_HOME/ares-agent/venv/bin/python" ]; then
  PYBIN="$ARES_HOME/ares-agent/venv/bin/python"
else
  echo "ERROR: No Python venv found. Run 'python -m venv .venv && .venv/bin/pip install -e .' first." >&2
  exit 1
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

# Write PID file after confirming we're clear to start
echo $$ > "$_PID_FILE"

exec "$PYBIN" -m uvicorn fastapi_app.main:app \
  --host "$ARES_WEBUI_HOST" --port "$ARES_WEBUI_PORT" --no-server-header
