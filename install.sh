#!/usr/bin/env bash
# ARES — one-line installer
#
# Usage (curl, no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/shuwalker/ARES/main/install.sh | bash
#
# Usage (from clone):
#   git clone https://github.com/shuwalker/ARES && cd ARES && bash install.sh
#
# Options:
#   --role primary|client   Machine role (prompted if omitted)
#   --primary-url URL       Primary URL for client mode (e.g. http://100.x.y.z:8787)
#   --backend jros|hermes|hybrid|auto
#   --with-hermes           Also install Hermes Agent (optional addition)
#   --no-start              Skip launching the app after install
#   -h, --help

set -e

# ── Self-clone: if piped from curl we won't be inside an ARES repo ──────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"
if [ ! -f "$SCRIPT_DIR/Package.swift" ] || [ ! -d "$SCRIPT_DIR/webui" ]; then
    ARES_SRC="${ARES_SRC:-$HOME/.ares-src}"
    echo "→ Cloning ARES into $ARES_SRC..."
    if [ -d "$ARES_SRC/.git" ]; then
        git -C "$ARES_SRC" pull --ff-only origin main 2>/dev/null || true
    else
        git clone --depth 1 https://github.com/shuwalker/ARES.git "$ARES_SRC"
    fi
    exec bash "$ARES_SRC/install.sh" "$@"
fi

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${CYAN}→${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
die()  { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

# ── Arg parsing ──────────────────────────────────────────────────────────────
EXTRA_ARGS=()
NO_START=false
ARES_ROLE=""
ARES_PRIMARY_URL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --role)          ARES_ROLE="$2"; shift 2 ;;
        --primary-url)   ARES_PRIMARY_URL="$2"; shift 2 ;;
        --backend)       EXTRA_ARGS+=("--backend" "$2"); shift 2 ;;
        --with-hermes)   EXTRA_ARGS+=("--with-hermes"); shift ;;
        --no-start)      NO_START=true; shift ;;
        -h|--help)
            echo "ARES installer"
            echo ""
            echo "  curl -fsSL https://raw.githubusercontent.com/shuwalker/ARES/main/install.sh | bash"
            echo "  bash install.sh [--role primary|client] [--primary-url URL]"
            echo "                  [--backend jros|hermes|hybrid] [--with-hermes] [--no-start]"
            exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

# Normalise "client" → "device" (internal value used by ares_devices.py)
[ "$ARES_ROLE" = "client" ] && ARES_ROLE="device"

echo ""
echo -e "${MAGENTA}${BOLD}"
echo "  ┌──────────────────────────────────┐"
echo "  │             A R E S              │"
echo "  │  Autonomous Reasoning & Execution│"
echo "  └──────────────────────────────────┘"
echo -e "${NC}"

# ── 1. OS detection ──────────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
    Darwin) OS_NAME="macOS" ;;
    Linux)  OS_NAME="Linux" ;;
    *)      OS_NAME="$OS" ;;
esac
ok "Detected: $OS_NAME"

# ── 2. Prereqs ───────────────────────────────────────────────────────────────
info "Checking prerequisites..."

# git
if ! command -v git >/dev/null 2>&1; then
    case "$OS" in
        Darwin) die "git not found. Fix: xcode-select --install" ;;
        Linux)  die "git not found. Fix: sudo apt install git" ;;
        *)      die "git not found — install it first" ;;
    esac
fi
ok "git $(git --version | awk '{print $3}')"

# python 3.10+
PYTHON_PATH=""
for cmd in python3.13 python3.12 python3.11 python3.10 python3 python; do
    if command -v "$cmd" >/dev/null 2>&1; then
        if "$cmd" -c "import sys; raise SystemExit(0 if sys.version_info>=(3,10) else 1)" 2>/dev/null; then
            PYTHON_PATH="$(command -v "$cmd")"
            break
        fi
    fi
done
if [ -z "$PYTHON_PATH" ]; then
    case "$OS" in
        Darwin) die "Python 3.10+ not found. Fix: brew install python@3.12" ;;
        Linux)  die "Python 3.10+ not found. Fix: sudo apt install python3.12" ;;
        *)      die "Python 3.10+ not found — install from https://python.org" ;;
    esac
fi
ok "Python $($PYTHON_PATH --version 2>/dev/null | awk '{print $2}') ($PYTHON_PATH)"

# Swift — non-fatal, just skip Mac app if missing
HAS_SWIFT=false
if [ "$OS" = "Darwin" ] && command -v swift >/dev/null 2>&1; then
    HAS_SWIFT=true
    ok "Swift $(swift --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
elif [ "$OS" = "Darwin" ]; then
    warn "Swift not found — Mac app will be skipped. Fix: install Xcode from the App Store."
fi

# ── 3. Role selection ────────────────────────────────────────────────────────
_select_role() {
    if [ -n "$ARES_ROLE" ]; then
        [ "$ARES_ROLE" != "primary" ] && [ "$ARES_ROLE" != "device" ] && \
            die "Invalid role '$ARES_ROLE' — must be primary or client"
        return 0
    fi

    echo ""
    echo -e "${MAGENTA}${BOLD}  Which machine is this?${NC}"
    echo ""
    echo "  1) Primary   Always-on Mac — full model, Tailscale reachable"
    echo "  2) Client    MacBook / secondary — uses primary when online,"
    echo "               local JaegerAI model when offline"
    echo ""
    while true; do
        printf "  Select [1/2]: "
        read -r _choice
        case "$_choice" in
            1|primary)         ARES_ROLE="primary"; ok "Role: Primary"; break ;;
            2|client|device)   ARES_ROLE="device";  ok "Role: Client";  break ;;
            *) echo "  Enter 1 or 2." ;;
        esac
    done

    if [ "$ARES_ROLE" = "device" ] && [ -z "$ARES_PRIMARY_URL" ]; then
        echo ""
        printf "  Primary machine URL (e.g. http://100.x.y.z:8787) — blank to set later: "
        read -r ARES_PRIMARY_URL
        ARES_PRIMARY_URL="${ARES_PRIMARY_URL// /}"
        [ -n "$ARES_PRIMARY_URL" ] && ok "Primary URL: $ARES_PRIMARY_URL" || \
            info "No primary URL set — add it later in Settings"
    fi
}

# ── 4. JaegerAI ──────────────────────────────────────────────────────────────
_check_jaeger() {
    JAEGER_HOME=""
    for p in "$HOME/jaeger" "$HOME/.jaeger"; do
        [ -d "$p" ] && JAEGER_HOME="$p" && break
    done
    if [ -n "$JAEGER_HOME" ]; then
        ok "JaegerAI at $JAEGER_HOME"
        return 0
    fi
    echo ""
    warn "JaegerAI not found — required Companion runtime on every machine"
    echo ""
    printf "  Install JaegerAI now? [Y/n]: "
    read -r _ans
    case "${_ans:-Y}" in
        [Yy]*)
            info "Installing JaegerAI..."
            if curl -fsSL https://raw.githubusercontent.com/JenkinsRobotics/JaegerAI/master/scripts/install.sh | bash; then
                ok "JaegerAI installed"
                for p in "$HOME/jaeger" "$HOME/.jaeger"; do [ -d "$p" ] && JAEGER_HOME="$p" && break; done
            else
                die "JaegerAI install failed.\n  Manual: curl -fsSL https://raw.githubusercontent.com/JenkinsRobotics/JaegerAI/master/scripts/install.sh | bash"
            fi ;;
        *)
            warn "Skipping JaegerAI — your Companion won't work without it" ;;
    esac
}

# ── 5. Tailscale (macOS only) ────────────────────────────────────────────────
_check_tailscale() {
    [ "$OS" != "Darwin" ] && return 0
    if command -v tailscale >/dev/null 2>&1 || [ -d "/Applications/Tailscale.app" ]; then
        ok "Tailscale found"
        return 0
    fi
    echo ""
    info "Tailscale not found — needed for cross-device access (iPhone, MacBook, etc.)"
    if command -v brew >/dev/null 2>&1; then
        printf "  Install via Homebrew? [Y/n]: "
        read -r _ans
        case "${_ans:-Y}" in
            [Yy]*)
                info "Installing Tailscale..."
                if brew install --cask tailscale 2>/dev/null; then
                    ok "Tailscale installed — open it and sign into your tailnet"
                else
                    warn "Tailscale install failed — install from https://tailscale.com/download"
                fi ;;
            *) info "Skipping — install later from https://tailscale.com/download" ;;
        esac
    else
        info "Install Tailscale from https://tailscale.com/download"
    fi
}

# ── Run pre-install steps ────────────────────────────────────────────────────
_select_role
_check_jaeger
_check_tailscale

# Companion profile dir — syncs across Macs via iCloud Desktop
ARES_CONTINUITY_DIR="$HOME/Desktop/ARES/companion"
mkdir -p "$ARES_CONTINUITY_DIR"
ok "Companion profile: $ARES_CONTINUITY_DIR"
echo ""

# ── 6–9. Python venv, deps, config — handled by webui/scripts/install.sh ────
# That script is the battle-tested engine for repo clone/update, venv setup,
# pip install, JaegerAI detection, and config.yaml. We pass --no-start so the
# Mac app launch is controlled below after we write role config and launchd.
USE_MAC_APP=false
if [ "$NO_START" = false ] && [ "$OS" = "Darwin" ] && [ "$HAS_SWIFT" = true ] && [ -f "$SCRIPT_DIR/Package.swift" ]; then
    USE_MAC_APP=true
fi

WEBUI_INSTALLER="$SCRIPT_DIR/webui/scripts/install.sh"
if [ ! -f "$WEBUI_INSTALLER" ]; then
    die "webui installer not found at $WEBUI_INSTALLER"
fi

INNER_ARGS=("--no-start" "${EXTRA_ARGS[@]}")
bash "$WEBUI_INSTALLER" "${INNER_ARGS[@]}"

[ "$NO_START" = true ] && exit 0

# ── 10. Write role config ────────────────────────────────────────────────────
_yaml_set() {
    local key="$1" val="$2" file="$3"
    if grep -q "^${key}:" "$file" 2>/dev/null; then
        sed -i '' "s|^${key}:.*|${key}: ${val}|" "$file"
    else
        echo "${key}: ${val}" >> "$file"
    fi
}

_write_role_config() {
    local cfg="$HOME/.ares/config.yaml"
    mkdir -p "$HOME/.ares"; [ -f "$cfg" ] || touch "$cfg"
    _yaml_set "ares_role"           "$ARES_ROLE"           "$cfg"
    _yaml_set "ares_continuity_dir" "$ARES_CONTINUITY_DIR" "$cfg"
    [ -n "$ARES_PRIMARY_URL" ] && _yaml_set "ares_primary_url" "$ARES_PRIMARY_URL" "$cfg"
    ok "Role config → $cfg"

    if [ "$OS" = "Darwin" ]; then
        defaults write ARES ares.config.role         "$ARES_ROLE"           2>/dev/null || true
        defaults write ARES ares.config.continuityDir "$ARES_CONTINUITY_DIR" 2>/dev/null || true
        [ -n "$ARES_PRIMARY_URL" ] && \
            defaults write ARES ares.config.primaryURL "$ARES_PRIMARY_URL" 2>/dev/null || true
        ok "Mac app config synced"
    fi
}

_write_role_config

# ── 11. launchd (macOS — auto-start server at login) ─────────────────────────
_setup_launchd() {
    [ "$OS" != "Darwin" ] && return 0

    local plist_dir="$HOME/Library/LaunchAgents"
    local plist="$plist_dir/com.ares.webui.plist"
    local python="$HOME/.ares/webui/venv/bin/python"
    local server="$HOME/.ares/webui/server.py"
    local workdir="$HOME/.ares/webui"
    local logfile="$HOME/.ares/webui.log"

    if [ ! -f "$python" ]; then
        warn "launchd setup skipped — venv not found at $python"
        return 0
    fi

    local jaeger_home="${JAEGER_HOME:-}"
    if [ -z "$jaeger_home" ]; then
        local cfg="$HOME/.ares/config.yaml"
        if [ -f "$cfg" ]; then
            local v
            v=$(grep -E '^ares_jaeger_home:' "$cfg" 2>/dev/null | sed 's/^ares_jaeger_home:[[:space:]]*//' | tr -d '"'"'" | xargs 2>/dev/null || true)
            [ -n "$v" ] && [ -d "$v" ] && jaeger_home="$v"
        fi
        [ -z "$jaeger_home" ] && for p in "$HOME/jaeger" "$HOME/.jaeger"; do [ -d "$p" ] && jaeger_home="$p" && break; done
    fi

    local primary_url_xml=""
    if [ -n "$ARES_PRIMARY_URL" ]; then
        primary_url_xml="        <key>ARES_PRIMARY_URL</key>
        <string>$ARES_PRIMARY_URL</string>"
    fi

    mkdir -p "$plist_dir"
    cat > "$plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ares.webui</string>
    <key>ProgramArguments</key>
    <array>
        <string>$python</string>
        <string>$server</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>ARES_JAEGER_HOME</key>
        <string>$jaeger_home</string>
        <key>JAEGER_HOME</key>
        <string>$jaeger_home</string>
        <key>ARES_ROLE</key>
        <string>$ARES_ROLE</string>
        <key>ARES_CONTINUITY_DIR</key>
        <string>$ARES_CONTINUITY_DIR</string>
$primary_url_xml
        <key>HERMES_WEBUI_HOST</key>
        <string>0.0.0.0</string>
        <key>HERMES_WEBUI_PORT</key>
        <string>8787</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>$workdir</string>
    <key>StandardOutPath</key>
    <string>$logfile</string>
    <key>StandardErrorPath</key>
    <string>$logfile</string>
</dict>
</plist>
PLIST_EOF

    launchctl unload "$plist" 2>/dev/null || true
    if launchctl load "$plist" 2>/dev/null; then
        ok "Auto-start at login: com.ares.webui"
        launchctl start com.ares.webui 2>/dev/null || true
        info "Server starting in background..."
        sleep 3
    else
        warn "launchd load failed — Mac app will start the server on first open"
    fi
}

_setup_launchd

# ── 12. Launch ───────────────────────────────────────────────────────────────
echo ""
if [ "$USE_MAC_APP" = true ]; then
    info "Launching ARES..."
    cd "$SCRIPT_DIR"
    swift run ARES
else
    echo -e "${GREEN}${BOLD}ARES installed.${NC}"
    echo ""
    echo "  Start the server:  cd ~/.ares/webui && ./venv/bin/python server.py"
    echo "  Open in browser:   http://localhost:8787"
    if command -v tailscale >/dev/null 2>&1; then
        local_ts_ip=$(tailscale ip -4 2>/dev/null || true)
        [ -n "$local_ts_ip" ] && echo "  Tailscale URL:     http://$local_ts_ip:8787"
    fi
fi
