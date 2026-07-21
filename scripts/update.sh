#!/usr/bin/env bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

info() { echo -e "${YELLOW}ℹ ${1}${NC}"; }
ok() { echo -e "${GREEN}✔ ${1}${NC}"; }
error() { echo -e "${RED}✖ ${1}${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BOLD}── ARES Updater ──${NC}"
info "Stashing any local, uncommitted changes to prevent conflicts..."
git stash >/dev/null 2>&1 || true

info "Pulling latest changes from origin main..."
if git pull origin main; then
    ok "Successfully pulled latest code."
else
    error "Failed to pull changes. Are you connected to the internet?"
    exit 1
fi

info "Re-initializing ARES environment (no-start mode)..."
if bash install.sh --no-start; then
    ok "ARES successfully updated and re-initialized."
else
    error "Failed to run install.sh after update."
    exit 1
fi

echo -e "\n${GREEN}${BOLD}Update Complete!${NC}"
echo "You can now run 'ares' to start the application."
