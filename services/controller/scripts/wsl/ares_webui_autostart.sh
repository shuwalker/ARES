#!/usr/bin/env bash
set -euo pipefail

# WSL-friendly autostart launcher for Ares WebUI.
#
# Safe defaults:
# - derives the repo from this script location, override with ARES_WEBUI_REPO
# - uses a lock + pid file to avoid duplicate starts
# - treats a healthy /health endpoint as "already running"
# - writes logs under ~/.ares/webui/logs unless ARES_WEBUI_LOG_DIR is set

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ARES_WEBUI_REPO="${ARES_WEBUI_REPO:-${DEFAULT_REPO}}"
ARES_WEBUI_LOG_DIR="${ARES_WEBUI_LOG_DIR:-${HOME}/.ares/webui/logs}"
ARES_WEBUI_HOST="${ARES_WEBUI_HOST:-127.0.0.1}"
ARES_WEBUI_PORT="${ARES_WEBUI_PORT:-8787}"
ARES_WEBUI_HEALTH_HOST="${ARES_WEBUI_HEALTH_HOST:-127.0.0.1}"

# Shared TLS-aware probe (mirrors the server scheme; handles self-signed certs
# and the HTTP-fallback contract).
# shellcheck source=../lib/health_probe.sh
. "${SCRIPT_DIR}/../lib/health_probe.sh"

# Scheme-aware default health URL (https when TLS_CERT/KEY are set). When the
# user explicitly sets ARES_WEBUI_HEALTH_URL, it remains the authoritative
# probe target (documented override) — see webui_healthy() below. Otherwise the
# generated default is used for both the probe and human-readable log messages.
if [[ -n "${ARES_WEBUI_HEALTH_URL:-}" ]]; then
  _ARES_WEBUI_HEALTH_URL_EXPLICIT=1
else
  _ARES_WEBUI_HEALTH_URL_EXPLICIT=0
fi
ARES_WEBUI_HEALTH_URL="${ARES_WEBUI_HEALTH_URL:-$(ares_webui_probe_scheme)://${ARES_WEBUI_HEALTH_HOST}:${ARES_WEBUI_PORT}/health}"
ARES_WEBUI_PID_FILE="${ARES_WEBUI_PID_FILE:-${ARES_WEBUI_LOG_DIR}/ares-webui.pid}"
ARES_WEBUI_LOCK_FILE="${ARES_WEBUI_LOCK_FILE:-/tmp/ares-webui-autostart.lock}"
AUTOSTART_LOG="${ARES_WEBUI_LOG_DIR}/webui_autostart.log"
WEBUI_LOG="${ARES_WEBUI_LOG_DIR}/ares_webui.log"

# Make the WSL launcher knobs visible to start.sh/bootstrap.py.
export ARES_WEBUI_HOST ARES_WEBUI_PORT

mkdir -p "${ARES_WEBUI_LOG_DIR}"
chmod 700 "${ARES_WEBUI_LOG_DIR}" 2>/dev/null || true

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$*" | tee -a "${AUTOSTART_LOG}"
}

webui_healthy() {
  # Honor an explicit ARES_WEBUI_HEALTH_URL override (documented escape hatch):
  # probe that exact URL. The shared TLS-aware helper is used for the generated
  # default, which mirrors the server scheme and handles self-signed certs + the
  # HTTP-fallback contract.
  if [[ "${_ARES_WEBUI_HEALTH_URL_EXPLICIT}" == "1" ]]; then
    if command -v curl >/dev/null 2>&1; then
      curl -fsS -k --max-time 3 "${ARES_WEBUI_HEALTH_URL}" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
      wget -qO- --no-check-certificate --timeout=3 --tries=1 "${ARES_WEBUI_HEALTH_URL}" >/dev/null 2>&1
    else
      return 1
    fi
    return $?
  fi
  ares_webui_probe_health "${ARES_WEBUI_HEALTH_HOST}" "${ARES_WEBUI_PORT}" "/health" 3 >/dev/null 2>&1
}

pid_is_alive() {
  [[ -s "${ARES_WEBUI_PID_FILE}" ]] || return 1
  local pid
  pid="$(cat "${ARES_WEBUI_PID_FILE}" 2>/dev/null || true)"
  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" >/dev/null 2>&1
}

validate_repo() {
  if [[ ! -d "${ARES_WEBUI_REPO}" ]]; then
    log "Ares WebUI repo not found: ${ARES_WEBUI_REPO}"
    exit 1
  fi
  if [[ ! -f "${ARES_WEBUI_REPO}/start.sh" ]]; then
    log "start.sh not found under ARES_WEBUI_REPO=${ARES_WEBUI_REPO}"
    exit 1
  fi
}

maybe_require_agent_process() {
  # Ares WebUI usually launches the agent in-process, so this check is opt-in.
  # Set ARES_WEBUI_REQUIRE_AGENT_PROCESS=1 only if your setup depends on a
  # separately running Ares gateway/agent before WebUI starts.
  if [[ "${ARES_WEBUI_REQUIRE_AGENT_PROCESS:-0}" != "1" ]]; then
    return 0
  fi
  if ! pgrep -f "ares" >/dev/null 2>&1; then
    log "ARES_WEBUI_REQUIRE_AGENT_PROCESS=1 but no Ares process is running; skipping start"
    exit 1
  fi
}

acquire_lock() {
  exec 9>"${ARES_WEBUI_LOCK_FILE}"
  if command -v flock >/dev/null 2>&1; then
    if ! flock -n 9; then
      log "Autostart already running; lock held at ${ARES_WEBUI_LOCK_FILE}"
      exit 0
    fi
  else
    log "flock not found; continuing without lock-based duplicate protection"
  fi
}

start_webui() {
  validate_repo
  maybe_require_agent_process

  if webui_healthy; then
    log "Ares WebUI already running at ${ARES_WEBUI_HEALTH_URL}"
    exit 0
  fi

  if pid_is_alive; then
    log "Ares WebUI already running with pid $(cat "${ARES_WEBUI_PID_FILE}")"
    exit 0
  fi

  rm -f "${ARES_WEBUI_PID_FILE}"
  log "Starting Ares WebUI from ${ARES_WEBUI_REPO} on ${ARES_WEBUI_HOST}:${ARES_WEBUI_PORT}"

  (
    cd "${ARES_WEBUI_REPO}"
    nohup bash "${ARES_WEBUI_REPO}/start.sh" --foreground >>"${WEBUI_LOG}" 2>&1 &
    printf '%s\n' "$!" >"${ARES_WEBUI_PID_FILE}"
  )

  sleep "${ARES_WEBUI_STARTUP_GRACE_SECONDS:-2}"
  if webui_healthy; then
    log "Ares WebUI started and passed health check"
    exit 0
  fi

  if pid_is_alive; then
    log "Ares WebUI process started with pid $(cat "${ARES_WEBUI_PID_FILE}"); health check not ready yet"
    exit 0
  fi

  log "Ares WebUI failed to stay running; see ${WEBUI_LOG}"
  exit 1
}

acquire_lock
start_webui
