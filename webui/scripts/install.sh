#!/bin/bash
# ============================================================================
# ARES Web UI Installer
# ============================================================================
# Installation script for Linux, macOS, and Windows (via WSL/Cygwin).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/shuwalker/ARES/main/webui/scripts/install.sh | bash
#
# Or with options:
#   curl -fsSL ... | bash -s -- --port 9000 --host 0.0.0.0 --skip-setup
#
# ============================================================================

set -e

# Guard against environment leakage
if [ -n "${PYTHONPATH:-}" ]; then
    echo "⚠ Ignoring inherited PYTHONPATH during install"
    unset PYTHONPATH
fi
if [ -n "${PYTHONHOME:-}" ]; then
    echo "⚠ Ignoring inherited PYTHONHOME during install"
    unset PYTHONHOME
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
REPO_URL_SSH="git@github.com:shuwalker/ARES.git"
REPO_URL_HTTPS="https://github.com/shuwalker/ARES.git"
ARES_HOME="${ARES_HOME:-$HOME/.ares}"
ARES_HOME="${ARES_HOME:-$HOME/.ares}"
INSTALL_DIR="${ARES_INSTALL_DIR:-$ARES_HOME}"
WEBUI_DIR="$INSTALL_DIR/webui"
PYTHON_VERSION="3.11"
BRANCH="main"
PORT="${ARES_WEBUI_PORT:-8787}"
HOST="${ARES_WEBUI_HOST:-0.0.0.0}"
RUN_SETUP=true
USE_VENV=true
JSON_OUTPUT=false
STAGE_NAME=""
MANIFEST_MODE=false
NON_INTERACTIVE=false
BACKEND_MODE="${ARES_BACKEND:-auto}"
NO_START=false

# JaegerAI is ARES's required Companion runtime — the brain, memory, character,
# and local model. ARES never forks or reimplements it; the installer only
# ever detects an existing install or delegates to JaegerAI's own installer,
# the same way ares-workspace's installer delegates to Nous's upstream
# ares-agent installer instead of reimplementing it.
JROS_INSTALL_URL="${JROS_INSTALL_URL:-https://raw.githubusercontent.com/JenkinsRobotics/JaegerAI/master/scripts/install.sh}"
SKIP_JROS=false

# Ares Agent is an optional addition (coding/terminal/skills capability),
# never installed unless the operator asks for it.
WITH_ARES=false

# Detect non-interactive mode
if [ -t 0 ]; then
    IS_INTERACTIVE=true
else
    IS_INTERACTIVE=false
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-venv) USE_VENV=false; shift ;;
        --skip-setup) RUN_SETUP=false; shift ;;
        --branch) BRANCH="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --host) HOST="$2"; shift 2 ;;
        --dir) INSTALL_DIR="$2"; WEBUI_DIR="$INSTALL_DIR/webui"; shift 2 ;;
        --manifest) MANIFEST_MODE=true; shift ;;
        --stage) STAGE_NAME="$2"; shift 2 ;;
        --json) JSON_OUTPUT=true; shift ;;
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        --backend) BACKEND_MODE="$2"; shift 2 ;;
        --no-start) NO_START=true; shift ;;
        --skip-jros) SKIP_JROS=true; shift ;;
        --with-ares) WITH_ARES=true; shift ;;
        -h|--help)
            echo "ARES Web UI Installer"
            echo ""
            echo "Usage: install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --no-venv       Don't create virtual environment"
            echo "  --skip-setup    Skip interactive setup wizard"
            echo "  --branch NAME   Git branch to install (default: main)"
            echo "  --port PORT     Web UI port (default: 8787)"
            echo "  --host HOST     Bind address (default: 0.0.0.0)"
            echo "  --dir PATH      Install directory (default: ~/.ares)"
            echo "  --manifest      Print desktop bootstrap stage manifest as JSON"
            echo "  --stage NAME    Run one desktop bootstrap stage"
            echo "  --json          Print a JSON result frame for --stage"
            echo "  --non-interactive  Skip stages that require user input"
            echo "  --backend MODE  Live adapter ID or short alias (default: auto → jros_local"
            echo "                  when JaegerAI is detected). Examples: auto, jros,"
            echo "                  jros_local, hermes, hermes_local, claude_local,"
            echo "                  ollama_local, openai_cloud. Deleted modes ares/hybrid are rejected."
            echo "  --no-start      Skip auto-starting the server after installation"
            echo "  --skip-jros     Skip installing JaegerAI (advanced/CI use — profile can still"
            echo "                  be saved without a Companion runtime)"
            echo "  --with-ares     Also install Ares Agent package (optional coding addition;"
            echo "                  does not select a runtime by itself)"
            echo "  -h, --help      Show this help"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ============================================================================
# Helper functions
# ============================================================================

print_banner() {
    echo ""
    echo -e "${MAGENTA}${BOLD}"
    echo "┌────────────────────────────────────────────┐"
    echo "│           ARES Web UI Installer           │"
    echo "├────────────────────────────────────────────┤"
    echo "│  Artificial Reasoning Entity System        │"
    echo "└────────────────────────────────────────────┘"
    echo -e "${NC}"
}

log_info() { echo -e "${CYAN}→${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

json_escape() {
    printf '%s' "$1" | tr '\n' ' ' | sed \
        -e 's/\\/\\\\/g' \
        -e 's/"/\\"/g'
}

emit_manifest() {
    printf '%s' '{"protocol_version":1,"stages":[{"name":"prerequisites","title":"System prerequisites","category":"runtime","needs_user_input":false},{"name":"repository","title":"Download ARES Web UI","category":"runtime","needs_user_input":false},{"name":"jros","title":"Install JaegerAI (required Companion runtime)","category":"runtime","needs_user_input":false},{"name":"venv","title":"Create Python virtual environment","category":"runtime","needs_user_input":false},{"name":"python-deps","title":"Install Python dependencies","category":"runtime","needs_user_input":false},{"name":"config","title":"Prepare configuration","category":"configuration","needs_user_input":false},{"name":"setup","title":"Configure Companion and optional additions","category":"configuration","needs_user_input":true},{"name":"complete","title":"Finish install","category":"runtime","needs_user_input":false}]}'
    printf '\n'
}

emit_stage_json() {
    local stage="$1" ok="$2" skipped="${3:-false}" reason="${4:-}"
    local escaped_reason
    escaped_reason="$(json_escape "$reason")"
    if [ -n "$escaped_reason" ]; then
        printf '{"ok":%s,"stage":"%s","skipped":%s,"reason":"%s"}\n' "$ok" "$stage" "$skipped" "$escaped_reason"
    else
        printf '{"ok":%s,"stage":"%s","skipped":%s}\n' "$ok" "$stage" "$skipped"
    fi
}

prompt_yes_no() {
    local question="$1" default="${2:-yes}" answer=""
    local prompt_suffix
    case "$default" in
        [yY]|[yY][eE][sS]|1) prompt_suffix="[Y/n]" ;;
        *) prompt_suffix="[y/N]" ;;
    esac
    if [ "$NON_INTERACTIVE" = true ]; then
        answer=""
    elif [ "$IS_INTERACTIVE" = true ]; then
        read -r -p "$question $prompt_suffix " answer || answer=""
    elif [ -r /dev/tty ] && [ -w /dev/tty ]; then
        printf "%s %s " "$question" "$prompt_suffix" > /dev/tty
        IFS= read -r answer < /dev/tty || answer=""
    else
        answer=""
    fi
    answer="${answer#"${answer%%[![:space:]]*}"}"
    answer="${answer%"${answer##*[![:space:]]}"}"
    if [ -z "$answer" ]; then
        case "$default" in
            [yY]|[yY][eE][sS]|1) return 0 ;;
            *) return 1 ;;
        esac
    fi
    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================================================
# System detection
# ============================================================================

detect_jros() {
    JAEGER_HOME_DETECTED="${ARES_JAEGER_HOME:-${JAEGER_HOME:-$HOME/jaeger}}"
    JAEGER_LAUNCHER="$JAEGER_HOME_DETECTED/jaeger"
    if [ -x "$JAEGER_LAUNCHER" ]; then
        JROS_DETECTED=true
        log_success "JaegerAI detected at $JAEGER_HOME_DETECTED"
    else
        JROS_DETECTED=false
        log_info "JaegerAI not detected at $JAEGER_HOME_DETECTED"
    fi
}

# JaegerAI is ARES's required Companion runtime (the brain, memory, character,
# local model). This stage never reimplements JaegerAI — it only detects an
# existing install or delegates to JaegerAI's own installer, exactly the way
# ARES already delegates to Nous's own installer for the optional Ares
# addition (see install_deps below).
stage_jros() {
    detect_jros
    if [ "$JROS_DETECTED" = true ]; then
        log_success "JaegerAI already installed at $JAEGER_HOME_DETECTED — skipping install"
        return 0
    fi
    if [ "$SKIP_JROS" = true ]; then
        log_warn "Skipping JaegerAI install (--skip-jros). ARES has no Companion runtime until"
        log_warn "JaegerAI is installed separately at $JAEGER_HOME_DETECTED."
        return 0
    fi

    log_info "JaegerAI not found — installing the required Companion runtime..."
    log_info "  Delegating to JaegerAI's own installer: $JROS_INSTALL_URL"
    if ! curl -fsSL "$JROS_INSTALL_URL" | JAEGER_HOME="$JAEGER_HOME_DETECTED" bash; then
        log_error "JaegerAI install failed."
        log_error "ARES requires JaegerAI as its Companion runtime — retry manually with:"
        log_error "  curl -fsSL $JROS_INSTALL_URL | bash"
        log_error "or pass --skip-jros to continue without a Companion (not recommended)."
        exit 1
    fi

    detect_jros
    if [ "$JROS_DETECTED" != true ]; then
        log_error "JaegerAI installer finished but no launcher was found at $JAEGER_HOME_DETECTED."
        log_error "Check the installer output above, or set ARES_JAEGER_HOME/JAEGER_HOME"
        log_error "to the location JaegerAI actually installed to."
        exit 1
    fi
    log_success "JaegerAI installed at $JAEGER_HOME_DETECTED"
}

detect_os() {
    case "$(uname -s)" in
        Linux*) OS="linux"; DISTRO="linux" ;;
        Darwin*) OS="macos"; DISTRO="macos" ;;
        CYGWIN*|MINGW*|MSYS*)
            OS="windows"
            DISTRO="windows"
            log_error "Windows detected. Please use the PowerShell installer:"
            log_info "  iex (irm https://raw.githubusercontent.com/shuwalker/ARES/main/webui/scripts/install.ps1)"
            exit 1 ;;
        *) OS="unknown"; DISTRO="unknown"; log_warn "Unknown operating system" ;;
    esac
    log_success "Detected: $OS ($DISTRO)"
}

# ============================================================================
# Dependency checks
# ============================================================================

check_git() {
    log_info "Checking Git..."
    if command -v git &> /dev/null && git --version &> /dev/null; then
        GIT_VERSION=$(git --version | awk '{print $3}')
        log_success "Git $GIT_VERSION found"
        return 0
    fi
    log_error "Git not found"
    case "$OS" in
        macos) log_info "  xcode-select --install  or  brew install git" ;;
        linux) log_info "  sudo apt install git  or  sudo dnf install git" ;;
    esac
    exit 1
}

check_python() {
    log_info "Checking Python $PYTHON_VERSION..."
    PYTHON_PATH=""
    # Versioned binaries first: a plain `python3`/`python` lookup can resolve
    # to macOS's ancient system stub (/usr/bin/python3, still 3.9.x) ahead of
    # a newer Homebrew/pyenv install in a script's PATH — a bare `curl | bash`
    # gets exactly this PATH, so this isn't just a local dev-shell quirk.
    # Mirrors JaegerAI's own installer's search order.
    for cmd in python3.13 python3.12 python3.11 python3 python; do
        if command -v "$cmd" >/dev/null 2>&1; then
            if "$cmd" -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)" 2>/dev/null; then
                PYTHON_PATH=$(command -v "$cmd")
                break
            fi
        fi
    done
    if [ -z "$PYTHON_PATH" ]; then
        log_error "Python 3.10+ not found. Install from https://python.org"
        log_info "  macOS: brew install python@3.12"
        exit 1
    fi
    PYTHON_FOUND_VERSION=$("$PYTHON_PATH" --version 2>/dev/null)
    log_success "Python found: $PYTHON_FOUND_VERSION ($PYTHON_PATH)"
}

check_node() {
    log_info "Checking Node.js..."
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
        log_error "Node.js and npm are required to build the ARES frontend."
        log_info "  Install the current Node.js LTS release from https://nodejs.org"
        exit 1
    fi
    if ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 20 ? 0 : 1)' 2>/dev/null; then
        log_error "Node.js 20 or newer is required (found $(node --version 2>/dev/null || echo unknown))."
        exit 1
    fi
    log_success "Node.js $(node --version) found"
}

# ============================================================================
# Installation stages
# ============================================================================

stage_prerequisites() {
    log_info "Checking prerequisites..."
    check_git
    check_python
    check_node
    log_success "All prerequisites met"
}

clone_repo() {
    log_info "Installing to $INSTALL_DIR..."

    if [ -d "$INSTALL_DIR" ]; then
        if [ -d "$INSTALL_DIR/.git" ]; then
            log_info "Existing installation found, updating..."
            cd "$INSTALL_DIR"
            if [ -n "$(git status --porcelain)" ]; then
                log_info "Local changes detected, stashing before update..."
                git stash push --include-untracked -m "ares-install-autostash-$(date -u +%Y%m%d-%H%M%S)"
            fi
            git remote set-branches origin "$BRANCH" 2>/dev/null || true
            git fetch origin "$BRANCH"
            git checkout "$BRANCH"
            if ! git pull --ff-only origin "$BRANCH"; then
                log_warn "Fast-forward not possible; resetting to origin/$BRANCH..."
                git reset --hard "origin/$BRANCH"
            fi
        else
            log_error "Directory exists but is not a git repository: $INSTALL_DIR"
            exit 1
        fi
    else
        mkdir -p "$(dirname "$INSTALL_DIR")"
        log_info "Trying SSH clone..."
        if GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5" \
           git clone --depth 1 --branch "$BRANCH" "$REPO_URL_SSH" "$INSTALL_DIR" 2>/dev/null; then
            log_success "Cloned via SSH"
        else
            rm -rf "$INSTALL_DIR" 2>/dev/null
            log_info "SSH failed, trying HTTPS..."
            if git clone --depth 1 --branch "$BRANCH" "$REPO_URL_HTTPS" "$INSTALL_DIR"; then
                log_success "Cloned via HTTPS"
            else
                log_error "Failed to clone repository"
                exit 1
            fi
        fi
    fi

    cd "$WEBUI_DIR"
    log_success "Repository ready"
}

setup_venv() {
    if [ "$USE_VENV" = false ]; then
        log_info "Skipping virtual environment (--no-venv)"
        return 0
    fi

    # PYTHON_PATH is set by check_python(), called from stage_prerequisites().
    # In a full sequential run that already happened in this same process, but
    # `--stage venv` runs standalone (the desktop bootstrap drives stages one
    # at a time) — re-derive it here so this stage works in isolation too.
    if [ -z "${PYTHON_PATH:-}" ]; then
        check_python
    fi

    log_info "Creating virtual environment..."

    if [ -d "venv" ]; then
        log_info "Virtual environment already exists, recreating..."
        rm -rf venv
    fi

    "$PYTHON_PATH" -m venv venv

    log_success "Virtual environment ready ($(./venv/bin/python --version 2>/dev/null))"
}

install_deps() {
    log_info "Installing dependencies..."

    if [ "$USE_VENV" = true ]; then
        export VIRTUAL_ENV="$WEBUI_DIR/venv"
        PIP_PYTHON="$WEBUI_DIR/venv/bin/python"
    else
        PIP_PYTHON="$PYTHON_PATH"
    fi

    "$PIP_PYTHON" -m pip install --upgrade pip -q

    # Install WebUI deps
    log_info "Installing WebUI Python dependencies..."
    if ! "$PIP_PYTHON" -m pip install -r "$WEBUI_DIR/requirements.txt"; then
        log_error "Failed to install WebUI dependencies"
        exit 1
    fi

    log_info "Building React frontend..."
    if ! (cd "$WEBUI_DIR/frontend" && npm ci && npm run build); then
        log_error "Failed to build the React frontend"
        exit 1
    fi

    # Ares Agent is an optional addition (coding/terminal/skills capability),
    # not the Companion runtime — JaegerAI already covers that. Only install it
    # when explicitly requested via --with-ares, or the operator opts in
    # here on an interactive terminal.
    if [ "$WITH_ARES" != true ] && [ "$NON_INTERACTIVE" != true ] && [ "$IS_INTERACTIVE" = true ]; then
        if prompt_yes_no "Also install Ares Agent (optional coding/terminal addition)?" "no"; then
            WITH_ARES=true
        fi
    fi

    if [ "$WITH_ARES" = true ]; then
        log_info "Installing Ares Agent (optional addition)..."
        if ! "$PIP_PYTHON" -m pip install ares-agent 2>/dev/null; then
            log_warn "ares-agent not found via pip"
            log_info "Trying git install..."
            if ! "$PIP_PYTHON" -m pip install git+https://github.com/nousresearch/ares-agent.git 2>/dev/null; then
                log_warn "Could not install ares-agent. The Ares addition will be unavailable."
                log_info "Install manually later: pip install ares-agent"
                WITH_ARES=false
            fi
        fi
    else
        log_info "Skipping Ares Agent (optional addition — add later with --with-ares)"
    fi

    log_success "All dependencies installed and frontend built"
}

setup_config() {
    log_info "Preparing configuration..."

    cd "$WEBUI_DIR"

    # Create .env from template if missing
    if [ ! -f ".env" ] && [ -f ".env.example" ]; then
        cp .env.example .env
        log_success "Created .env from template"
    fi

    # Create state directory
    mkdir -p "$ARES_HOME"

    detect_jros
    # Canonical live adapter IDs must match api.backend_selector.VALID_BACKENDS.
    # Short aliases map at write time; deleted ares/hybrid modes fail closed.
    selected_backend="$BACKEND_MODE"
    case "$selected_backend" in
        auto)
            if [ "${JROS_DETECTED:-false}" = true ]; then
                selected_backend="jros_local"
            else
                # Profile can be saved without an elected runtime.
                selected_backend=""
                log_warn "No JaegerAI install detected; leaving ares_backend unset (profile-only)."
                log_warn "Connect a live adapter later in Connections, or re-run with --backend jros_local."
            fi
            ;;
        jros|jros_local) selected_backend="jros_local" ;;
        hermes|hermes_local) selected_backend="hermes_local" ;;
        claude_local|codex_local|gemini_local|grok_local|opencode_local|cursor_local|pi_local|openai_cloud|xai_cloud|gemini_cloud|gemini_antigravity|ollama_local)
            selected_backend="$selected_backend"
            ;;
        ares|ares_local|hybrid)
            log_error "Backend '$selected_backend' is no longer supported."
            log_error "Use a live adapter ID such as jros_local or hermes_local (see --help)."
            exit 1
            ;;
        *)
            log_error "Invalid backend mode: $selected_backend"
            log_error "Expected auto or a live adapter ID (jros_local, hermes_local, claude_local, ...)."
            exit 1
            ;;
    esac
    if [ "$selected_backend" = "jros_local" ] && [ "${JROS_DETECTED:-false}" != true ]; then
        log_error "Backend 'jros_local' selected but no JaegerAI install was found at ${JAEGER_HOME_DETECTED:-unknown}."
        log_error "Re-run without --skip-jros, install JaegerAI manually, or choose another --backend."
        exit 1
    fi

    if [ -z "${PYTHON_PATH:-}" ]; then
        check_python
    fi
    CONFIG_PYTHON="${PYTHON_PATH:-}"
    if [ -z "$CONFIG_PYTHON" ]; then
        log_error "Python not found; cannot write ARES backend settings"
        exit 1
    fi
    "$CONFIG_PYTHON" - "$selected_backend" "$ARES_HOME" "$ARES_HOME" <<'PY'
import json
import sys
from pathlib import Path

backend = (sys.argv[1] or "").strip()
state_home = Path(sys.argv[2]) / "webui"
ares_home = Path(sys.argv[3])
state_home.mkdir(parents=True, exist_ok=True)
settings = state_home / "settings.json"
data = {}
if settings.exists():
    try:
        data = json.loads(settings.read_text(encoding="utf-8"))
    except Exception:
        data = {}
if backend:
    data["ares_backend"] = backend
else:
    # Profile-only install: do not persist a deleted or empty election.
    data.pop("ares_backend", None)
settings.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")

# Runtime reads the selected backend from Ares config.yaml, not settings.json.
# Keep this line-oriented and dependency-free so it works even if PyYAML is absent.
ares_home.mkdir(parents=True, exist_ok=True)
config_path = ares_home / "config.yaml"
lines = config_path.read_text(encoding="utf-8").splitlines() if config_path.exists() else []
out = []
seen = False
for line in lines:
    if line.startswith("ares_backend:"):
        if backend:
            out.append(f"ares_backend: {backend}")
            seen = True
        # else drop stale election line on profile-only install
        else:
            seen = True
    else:
        out.append(line)
if backend and not seen:
    if out and out[-1].strip():
        out.append("")
    out.append(f"ares_backend: {backend}")
config_path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
PY
    if [ "${JROS_DETECTED:-false}" = true ]; then
        "$CONFIG_PYTHON" - "$WEBUI_DIR/.env" "$JAEGER_HOME_DETECTED" <<'PY'
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
jros_home = sys.argv[2]
updates = {
    "ARES_JAEGER_HOME": jros_home,
    "JAEGER_HOME": jros_home,
}
lines = []
seen = set()
if env_path.exists():
    lines = env_path.read_text(encoding="utf-8").splitlines()
out = []
for line in lines:
    stripped = line.strip()
    key = stripped.split("=", 1)[0] if "=" in stripped and not stripped.startswith("#") else None
    if key in updates:
        out.append(f'{key}="{updates[key]}"')
        seen.add(key)
    else:
        out.append(line)
for key, value in updates.items():
    if key not in seen:
        out.append(f'{key}="{value}"')
env_path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
PY
        log_success "Persisted JaegerAI runtime path: $JAEGER_HOME_DETECTED"
    fi
    if [ -n "$selected_backend" ]; then
        log_success "Configured ARES backend: $selected_backend"
    else
        log_success "ARES backend left unset (profile-only; connect a runtime later)"
    fi

    log_success "Configuration ready"
}

run_setup_wizard() {
    if [ "$RUN_SETUP" = false ]; then
        log_info "Skipping setup wizard (--skip-setup)"
        return 0
    fi

    log_info "Setup wizard..."
    log_info "Open http://localhost:$PORT in your browser to complete setup."
    log_info "The onboarding wizard will walk you through naming your Companion (JaegerAI),"
    log_info "connecting from your other devices over Tailscale, and any optional"
    log_info "additions (Ares, cloud providers, MCP servers)."
}

# ============================================================================
# Main
# ============================================================================

# Manifest mode: print stages and exit
if [ "$MANIFEST_MODE" = true ]; then
    emit_manifest
    exit 0
fi

# Stage mode: run one stage
if [ -n "$STAGE_NAME" ]; then
    case "$STAGE_NAME" in
        prerequisites) stage_prerequisites ;;
        repository) clone_repo ;;
        jros) stage_jros ;;
        venv) setup_venv ;;
        python-deps) install_deps ;;
        config) setup_config ;;
        setup) run_setup_wizard ;;
        complete)
            log_success "ARES Web UI installation complete!"
            log_info "Open http://localhost:$PORT"
            ;;
        *) log_error "Unknown stage: $STAGE_NAME"; exit 1 ;;
    esac
    if [ "$JSON_OUTPUT" = true ]; then
        emit_stage_json "$STAGE_NAME" true
    fi
    exit 0
fi

# Full install
print_banner
detect_os
setup_cli() {
    log_info "Setting up ARES CLI..."
    mkdir -p ~/.local/bin
    if [ -f "$INSTALL_DIR/bin/ares" ]; then
        ln -sf "$INSTALL_DIR/bin/ares" ~/.local/bin/ares
        log_success "Created symlink: ~/.local/bin/ares -> $INSTALL_DIR/bin/ares"
        
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            log_info "NOTE: ~/.local/bin is not in your PATH."
            log_info "Add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to your shell profile."
        fi
    fi
}

stage_prerequisites
clone_repo
stage_jros
setup_venv
install_deps
setup_config
run_setup_wizard
setup_cli

echo ""
echo -e "${GREEN}${BOLD}ARES Web UI installation complete!${NC}"
echo ""
echo "  Start the server:"
if [ "${JROS_DETECTED:-false}" = true ]; then
    echo "    cd $WEBUI_DIR && ARES_JAEGER_HOME=$JAEGER_HOME_DETECTED ./venv/bin/python -m uvicorn fastapi_app.main:app --host $HOST --port $PORT --no-server-header"
else
    echo "    cd $WEBUI_DIR && ./venv/bin/python -m uvicorn fastapi_app.main:app --host $HOST --port $PORT --no-server-header"
fi
echo ""
echo "  Or set env and run:"
if [ "${JROS_DETECTED:-false}" = true ]; then
    echo "    cd $WEBUI_DIR && ARES_JAEGER_HOME=$JAEGER_HOME_DETECTED ARES_WEBUI_HOST=$HOST ARES_WEBUI_PORT=$PORT ./venv/bin/python -m uvicorn fastapi_app.main:app --host $HOST --port $PORT --no-server-header"
else
    echo "    cd $WEBUI_DIR && ARES_WEBUI_HOST=$HOST ARES_WEBUI_PORT=$PORT ./venv/bin/python -m uvicorn fastapi_app.main:app --host $HOST --port $PORT --no-server-header"
fi
echo ""
echo "  Then open: http://localhost:$PORT"
echo ""
echo "  For remote access over Tailscale:"
echo "    Install Tailscale on both machines, sign into the same tailnet,"
echo "    then access via http://<tailscale-ip>:$PORT"
echo ""

if [ "$NO_START" = false ] && [ -t 0 ]; then
    echo -e "${CYAN}→ Starting ARES Web UI...${NC}"
    cd "$WEBUI_DIR"
    if [ "${JROS_DETECTED:-false}" = true ]; then
        ARES_JAEGER_HOME="$JAEGER_HOME_DETECTED" JAEGER_HOME="$JAEGER_HOME_DETECTED" ARES_WEBUI_HOST="$HOST" ARES_WEBUI_PORT="$PORT" ./venv/bin/python -m uvicorn fastapi_app.main:app --host "$HOST" --port "$PORT" --no-server-header
    else
        ARES_WEBUI_HOST="$HOST" ARES_WEBUI_PORT="$PORT" ./venv/bin/python -m uvicorn fastapi_app.main:app --host "$HOST" --port "$PORT" --no-server-header
    fi
else
    echo -e "${CYAN}→ To start the server later, run:${NC}"
    if [ "${JROS_DETECTED:-false}" = true ]; then
        echo "  cd $WEBUI_DIR && ARES_JAEGER_HOME=$JAEGER_HOME_DETECTED JAEGER_HOME=$JAEGER_HOME_DETECTED ARES_WEBUI_HOST=$HOST ARES_WEBUI_PORT=$PORT ./venv/bin/python -m uvicorn fastapi_app.main:app --host $HOST --port $PORT --no-server-header"
    else
        echo "  cd $WEBUI_DIR && ARES_WEBUI_HOST=$HOST ARES_WEBUI_PORT=$PORT ./venv/bin/python -m uvicorn fastapi_app.main:app --host $HOST --port $PORT --no-server-header"
    fi
fi
