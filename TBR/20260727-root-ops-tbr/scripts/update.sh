#!/usr/bin/env bash
# ARES updater — pull latest, restore any local WIP, re-run install (no auto-launch).
#
# Important: never silently discard local work. We stash → pull → pop so
# uncommitted install/onboarding fixes are not lost (that was a real field bug).

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

info() { echo -e "${YELLOW}ℹ ${1}${NC}"; }
ok() { echo -e "${GREEN}✔ ${1}${NC}"; }
error() { echo -e "${RED}✖ ${1}${NC}"; }
note() { echo -e "${CYAN}→ ${1}${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BOLD}── ARES Updater ──${NC}"

STASHED=0
if [ -n "$(git status --porcelain 2>/dev/null || true)" ]; then
    info "Local changes detected — stashing before pull (will re-apply after)..."
    if git stash push -u -m "ares-update-autostash-$(date -u +%Y%m%d-%H%M%S)" >/dev/null; then
        STASHED=1
        ok "Stashed working tree (including untracked where safe)."
    else
        error "Could not stash local changes. Commit or clean the tree, then re-run."
        exit 1
    fi
else
    note "Working tree clean — no stash needed."
fi

info "Pulling latest changes from origin main..."
if git pull --ff-only origin main; then
    ok "Successfully pulled latest code."
else
    error "Failed to pull (ff-only). Resolve remote divergence, then re-run."
    if [ "$STASHED" -eq 1 ]; then
        info "Attempting to restore your stash..."
        git stash pop || error "Stash kept — run: git stash list && git stash pop"
    fi
    exit 1
fi

if [ "$STASHED" -eq 1 ]; then
    info "Re-applying your local changes..."
    if git stash pop; then
        ok "Local changes restored."
    else
        error "Stash pop had conflicts. Resolve them, then run: bash install.sh --role primary --no-start"
        error "Your stash is still in: git stash list"
        exit 1
    fi
fi

info "Re-initializing ARES environment (no-start mode)..."
if bash install.sh --role primary --no-start; then
    ok "ARES successfully updated and re-initialized."
else
    error "Failed to run install.sh after update."
    exit 1
fi

echo -e "\n${GREEN}${BOLD}Update Complete!${NC}"
echo "  ares           open the app / onboarding"
echo "  ares setup     reset onboarding wizard"
echo "  ares doctor    health + JaegerAI peer checks"
echo "  ares start --server   WebUI only"
