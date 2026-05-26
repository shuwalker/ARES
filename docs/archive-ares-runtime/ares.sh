#!/bin/zsh
# ARES — top layer shell
# Routes between local (LM Studio) and cloud (Anthropic)
# Usage: ares [status|start|stop|local|cloud|chat]

ARES_DIR="$HOME/.ares"
PROXY_PORT=4000
PROXY_PID_FILE="$ARES_DIR/litellm.pid"
PROXY_LOG="$ARES_DIR/logs/litellm.log"
LM_STUDIO_URL="http://localhost:1234"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

_ares_lm_running() {
  curl -s "$LM_STUDIO_URL/v1/models" >/dev/null 2>&1
}

_ares_proxy_running() {
  curl -s "http://localhost:$PROXY_PORT/health" >/dev/null 2>&1
}

_ares_status() {
  echo ""
  echo "${BLUE}ARES Status${NC}"
  echo "─────────────────────────────"

  if _ares_lm_running; then
    MODELS=$(curl -s "$LM_STUDIO_URL/v1/models" | python3 -c "import sys,json; d=json.load(sys.stdin); [print('  •', m['id']) for m in d['data']]" 2>/dev/null)
    echo "${GREEN}✓ LM Studio${NC} (local brain)"
    echo "$MODELS"
  else
    echo "${RED}✗ LM Studio${NC} — not running"
  fi

  if _ares_proxy_running; then
    echo "${GREEN}✓ ARES Proxy${NC} (localhost:$PROXY_PORT)"
  else
    echo "${RED}✗ ARES Proxy${NC} — not running (run: ares start)"
  fi

  if [[ -n "$ANTHROPIC_API_KEY" ]]; then
    echo "${GREEN}✓ Anthropic${NC} (cloud fallback ready)"
  else
    echo "${YELLOW}⚠ Anthropic${NC} — ANTHROPIC_API_KEY not set (cloud fallback unavailable)"
  fi

  echo ""
  echo "Claude Code is pointed at: ${BLUE}$ANTHROPIC_BASE_URL${NC}"
  echo ""
}

_ares_start() {
  echo "Starting ARES proxy..."
  mkdir -p "$ARES_DIR/logs"

  if _ares_proxy_running; then
    echo "${GREEN}Proxy already running on port $PROXY_PORT${NC}"
    return
  fi

  if ! _ares_lm_running; then
    echo "${YELLOW}Warning: LM Studio not running. Start it for local inference.${NC}"
    echo "Cloud fallback will be used if ANTHROPIC_API_KEY is set."
  fi

  nohup python3 -m litellm \
    --config "$ARES_DIR/litellm_config.yaml" \
    --port $PROXY_PORT \
    > "$PROXY_LOG" 2>&1 &

  echo $! > "$PROXY_PID_FILE"
  sleep 2

  if _ares_proxy_running; then
    echo "${GREEN}✓ ARES proxy running on localhost:$PROXY_PORT${NC}"
    echo "  Local: LM Studio (Gemma-3-12B)"
    echo "  Fallback: Anthropic API"
    echo ""
    echo "Claude Code is now using ARES. Run: claude"
  else
    echo "${RED}✗ Failed to start proxy. Check log: $PROXY_LOG${NC}"
  fi
}

_ares_stop() {
  if [[ -f "$PROXY_PID_FILE" ]]; then
    kill $(cat "$PROXY_PID_FILE") 2>/dev/null
    rm -f "$PROXY_PID_FILE"
    echo "${GREEN}ARES proxy stopped${NC}"
  else
    pkill -f "litellm.*$PROXY_PORT" 2>/dev/null
    echo "Proxy stopped"
  fi
}

_ares_use_local() {
  export ANTHROPIC_BASE_URL="http://localhost:$PROXY_PORT"
  export ANTHROPIC_API_KEY="sk-ares-local-proxy"
  echo "${GREEN}ARES → Local first (LM Studio → Anthropic fallback)${NC}"
}

_ares_use_cloud() {
  unset ANTHROPIC_BASE_URL
  echo "${BLUE}ARES → Cloud (direct Anthropic API)${NC}"
}

_ares_logs() {
  tail -f "$PROXY_LOG"
}

case "${1:-status}" in
  start)   _ares_start ;;
  stop)    _ares_stop ;;
  status)  _ares_status ;;
  local)   _ares_use_local ;;
  cloud)   _ares_use_cloud ;;
  logs)    _ares_logs ;;
  *)
    echo "Usage: ares [start|stop|status|local|cloud|logs]"
    echo ""
    echo "  start   — Start ARES proxy (LM Studio → Anthropic fallback)"
    echo "  stop    — Stop proxy"
    echo "  status  — Show what's running"
    echo "  local   — Point Claude Code at local proxy"
    echo "  cloud   — Point Claude Code at Anthropic directly"
    echo "  logs    — Watch proxy logs"
    ;;
esac
