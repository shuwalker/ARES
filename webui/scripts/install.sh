#!/bin/bash
# ARES Web UI — one-line installer
#   curl -fsSL https://raw.githubusercontent.com/shuwalker/ARES/main/webui/scripts/install.sh | bash
#
# Or with options:
#   curl -fsSL ... | bash -s -- --port 9000 --host 0.0.0.0
#
# Clones the repo, sets up Python venv, installs deps, and starts the server.
# The WebUI onboarding wizard handles the rest (provider, password, etc.).

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

REPO_URL="https://github.com/shuwalker/ARES.git"
BRANCH="main"
PORT="${ARES_WEBUI_PORT:-8787}"
HOST="${ARES_WEBUI_HOST:-0.0.0.0}"
INSTALL_DIR="${ARES_INSTALL_DIR:-$HOME/ARES}"

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --port) PORT="$2"; shift 2 ;;
        --host) HOST="$2"; shift 2 ;;
        --dir) INSTALL_DIR="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        -h|--help)
            echo "ARES Web UI Installer"
            echo "Usage: curl -fsSL https://.../install.sh | bash -s -- [OPTIONS]"
            echo "  --port PORT     Port (default: 8787)"
            echo "  --host HOST     Bind address (default: 0.0.0.0)"
            echo "  --dir PATH      Install directory (default: ~/ARES)"
            echo "  --branch NAME   Git branch (default: main)"
            exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

echo ""
echo "┌────────────────────────────────────────────┐"
echo "│           ARES Web UI Installer            │"
echo "└────────────────────────────────────────────┘"
echo ""

# === Check prerequisites ===
command -v git >/dev/null 2>&1 || { echo -e "${RED}✗ git is required${NC}"; exit 1; }
PYTHON=""
for cmd in python3 python; do
    if command -v "$cmd" >/dev/null 2>&1; then
        PYTHON="$cmd"
        break
    fi
done
if [ -z "$PYTHON" ]; then
    echo -e "${RED}✗ Python 3 is required. Install from https://python.org${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Found $("$PYTHON" --version)"

# === Clone / update repo ===
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${CYAN}→${NC} Updating existing install at $INSTALL_DIR..."
    cd "$INSTALL_DIR"
    git stash --include-untracked 2>/dev/null || true
    git checkout "$BRANCH" 2>/dev/null || true
    git pull origin "$BRANCH"
else
    echo -e "${CYAN}→${NC} Cloning ARES into $INSTALL_DIR..."
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

cd webui

# === Create venv ===
if [ ! -d ".venv" ]; then
    echo -e "${CYAN}→${NC} Creating virtual environment..."
    "$PYTHON" -m venv .venv
fi
source .venv/bin/activate

# === Install deps ===
echo -e "${CYAN}→${NC} Installing Python dependencies..."
pip install -q -r requirements.txt
pip install -q hermes-agent 2>/dev/null || echo -e "${YELLOW}⚠ hermes-agent not found via pip (WebUI will still work for basic use)${NC}"

# === Create .env if missing ===
if [ ! -f ".env" ] && [ -f ".env.example" ]; then
    cp .env.example .env
    echo -e "${GREEN}✓${NC} Created .env from template"
fi

# === Start ===
echo ""
echo -e "${GREEN}✓${NC} Setup complete!"
echo ""
echo -e "  ${BOLD}ARES Web UI${NC}"
echo "  Open: http://localhost:$PORT"
echo "  Ctrl+C to stop"
echo ""

export HERMES_WEBUI_HOST="$HOST"
export HERMES_WEBUI_PORT="$PORT"
exec python server.py
