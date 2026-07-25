#!/usr/bin/env bash
# ============================================================================
# ARES Installer — One-Line Install
# ============================================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/shuwalker/ARES/main/install.sh | bash
#
# Custom location:
#   ARES_HOME=/opt/ares curl -fsSL .../install.sh | bash
#
# Pin branch:
#   ARES_REF=wip/odysseus-import curl -fsSL .../install.sh | bash
#
# What this does:
#   1. Verify prereqs (git, python 3.11/3.12, C toolchain)
#   2. Clone ARES into $ARES_HOME
#   3. Detect existing JaegerAI install (recommended Companion runtime)
#   4. Run the in-repo installer (.venv, deps, config)
#   5. Print next steps
#
# Re-running refreshes ARES (git pull + reinstall) while preserving
# config, sessions, and state.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SCRIPT_DIR/.git" ]]; then
  ARES_HOME="${ARES_HOME:-$SCRIPT_DIR}"
else
  ARES_HOME="${ARES_HOME:-$HOME/.ares}"
fi
ARES_REF="${ARES_REF:-main}"
REPO_URL="${ARES_REPO_URL:-https://github.com/shuwalker/ARES.git}"
RAW_URL="$(printf '%s' "$REPO_URL" | sed 's#github.com#raw.githubusercontent.com#; s#\.git$##')/$ARES_REF/install.sh"

cat <<EOF
╔══════════════════════════════════════════════╗
║  ARES Installer — Artificial Reasoning System ║
╚══════════════════════════════════════════════╝
  install location: $ARES_HOME
  ref:              $ARES_REF

EOF

# ─────────────────────────────────────────────────────────────────────────────
# 1. Prereqs
# ─────────────────────────────────────────────────────────────────────────────

if ! command -v git >/dev/null 2>&1; then
  echo "✗ 'git' not found in PATH — install it first" >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin)
    if ! xcode-select -p >/dev/null 2>&1; then
      echo "✗ Xcode Command Line Tools not found (needed to build deps)" >&2
      echo "  fix: xcode-select --install" >&2
      exit 1
    fi
    if ! command -v swift >/dev/null 2>&1; then
      echo "⚠ Swift toolchain not found — macOS app won't build (terminal still works)" >&2
    fi
    ;;
  Linux)
    if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1 \
       && ! command -v clang >/dev/null 2>&1; then
      echo "✗ No C compiler (cc/gcc/clang) — needed to build deps" >&2
      echo "  fix: Ubuntu — sudo apt install build-essential" >&2
      exit 1
    fi
    ;;
esac

PY="$(command -v python3.12 || command -v python3.11 || command -v python3 || true)"
if [[ -z "$PY" ]]; then
  echo "✗ No python3.12 / python3.11 / python3 found" >&2
  echo "  hint: macOS — 'brew install python@3.12'" >&2
  exit 1
fi
PY_VERSION=$("$PY" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
case "$PY_VERSION" in
  3.11|3.12) ;;
  *)
    echo "✗ Python $PY_VERSION not supported (need 3.11 or 3.12)" >&2
    exit 1
    ;;
esac

echo "✓ prereqs OK (git, C toolchain, $PY → python$PY_VERSION)"
export PY

# ─────────────────────────────────────────────────────────────────────────────
# 2. Clone ARES
# ─────────────────────────────────────────────────────────────────────────────

if [[ -d "$ARES_HOME/.git" ]]; then
  echo "→ updating $ARES_HOME"
  git -C "$ARES_HOME" fetch origin --tags --quiet
  git -C "$ARES_HOME" checkout "$ARES_REF" --quiet
  git -C "$ARES_HOME" pull --ff-only origin "$ARES_REF" --quiet 2>/dev/null || true
else
  if [[ -e "$ARES_HOME" ]]; then
    echo "✗ $ARES_HOME exists but is not a git repo — move it aside or set ARES_HOME" >&2
    exit 1
  fi
  echo "→ cloning ARES into $ARES_HOME"
  mkdir -p "$(dirname "$ARES_HOME")"
  git clone --branch "$ARES_REF" "$REPO_URL" "$ARES_HOME" --quiet
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Detect JaegerAI (recommended, not required) — auto-wire if found
# ─────────────────────────────────────────────────────────────────────────────

JAEGER_FOUND=false
JAEGER_PATH=""

# Check common locations
for candidate in "$HOME/jaeger" "$HOME/GitHub/JaegerAI" "$HOME/.jaeger"; do
  if [[ -x "$candidate/jaeger" ]] || [[ -f "$candidate/install.sh" ]]; then
    JAEGER_FOUND=true
    JAEGER_PATH="$candidate"
    break
  fi
done

echo
if [[ "$JAEGER_FOUND" == "true" ]]; then
  echo -e "${GREEN}✓${NC} JaegerAI detected at: $JAEGER_PATH"
  echo "  → ARES will auto-detect JaegerAI on first launch"
  echo "  → Native onboarding window will appear when you open ARES"
else
  echo "⚠ JaegerAI not detected"
  echo "  → ARES will start with all adapters in Pending state"
  echo "  → Install JaegerAI later for full local Companion experience:"
  echo "      curl -fsSL https://raw.githubusercontent.com/JenkinsRobotics/JaegerAI/master/scripts/install.sh | bash"
fi
echo

# ─────────────────────────────────────────────────────────────────────────────
# 4. Generate CLI Dispatcher
# ─────────────────────────────────────────────────────────────────────────────

echo "→ generating ARES CLI launcher script..."
mkdir -p "$HOME/.local/bin"
LAUNCHER="$HOME/.local/bin/ares"

cat <<'EOF' > "$LAUNCHER"
#!/usr/bin/env bash
# ARES CLI Dispatcher

ARES_HOME="ARES_HOME_PLACEHOLDER"

CMD="${1:-}"

case "$CMD" in
    doctor)
        shift
        if [ -x "$ARES_HOME/webui/venv/bin/python" ]; then
            exec "$ARES_HOME/webui/venv/bin/python" "$ARES_HOME/webui/cli/doctor.py" "$@"
        else
            exec python3 "$ARES_HOME/webui/cli/doctor.py" "$@"
        fi
        ;;
    update)
        shift
        exec bash "$ARES_HOME/scripts/update.sh" "$@"
        ;;
    setup|--setup|onboarding|--onboarding)
        shift
        defaults delete ARES onboarding_completed 2>/dev/null || true
        defaults write ARES ARESForceOnboarding -bool true
        rm -rf "$HOME/jaeger/.jaeger_os/instances" "$HOME/.jaeger/.jaeger_os/instances" "$HOME/.jaeger/instances" "$HOME/.ares/instances" "$ARES_HOME/webui/.ares_state" 2>/dev/null || true
        echo "Resetting onboarding state... Opening ARES onboarding wizard."
        exec open "$ARES_HOME/ARES-Mac_os/ARES.app"
        ;;
    start|"")
        shift
        if [ "${1:-}" = "--cli" ] || [ "${1:-}" = "--server" ]; then
            cd "$ARES_HOME/webui"
            if [ -x "venv/bin/python" ]; then
                exec "venv/bin/python" -m uvicorn fastapi_app.main:app --port 8787 --host 127.0.0.1
            else
                exec python3 -m uvicorn fastapi_app.main:app --port 8787 --host 127.0.0.1
            fi
        else
            exec open "$ARES_HOME/ARES-Mac_os/ARES.app"
        fi
        ;;
    *)
        echo "Unknown ARES command: $CMD"
        echo "Available commands: start, setup, update, doctor"
        exit 1
        ;;
esac
EOF

sed -i '' "s#ARES_HOME_PLACEHOLDER#$ARES_HOME#g" "$LAUNCHER"
chmod +x "$LAUNCHER"

if [[ -w "/usr/local/bin" ]]; then
  cp "$LAUNCHER" "/usr/local/bin/ares" 2>/dev/null || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. Next steps
# ─────────────────────────────────────────────────────────────────────────────

echo
echo "╔══════════════════════════════════════════════╗"
echo "║  Installation Complete                       ║"
echo "╚══════════════════════════════════════════════╝"
echo
echo "Next steps:"
echo "  ares                      # Launch ARES"
echo "  ares setup                # Run setup / onboarding wizard"
echo "  ares update               # Update ARES to latest"
echo "  ares doctor               # Run system diagnostics"
echo
if [[ "$JAEGER_FOUND" == "true" ]]; then
  echo "✓ JaegerAI detected — ARES will auto-detect it."
else
  echo "Optional: Install JaegerAI for local Companion runtime:"
  echo "  curl -fsSL https://raw.githubusercontent.com/JenkinsRobotics/JaegerAI/master/scripts/install.sh | bash"
fi
echo
