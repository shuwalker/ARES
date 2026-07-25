#!/usr/bin/env bash
<<<<<<< HEAD
# ARES — one-line installer
#
# Usage (curl, no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/shuwalker/ARES/main/install.sh | bash
#
# Usage (from clone):
#   git clone https://github.com/shuwalker/ARES && cd ARES && bash install.sh
#
# Options:
#   --role primary|client   Machine role (default: primary; only prompted if interactive + omitted)
#   --primary-url URL       Primary URL for client mode (e.g. http://100.x.y.z:8787)
#   --no-start              Skip launching the app after install
#   --no-autostart          Skip launchd WebUI registration (Jaeger-style: install only)
#   --with-jaeger           If JaegerAI peer missing, run Jaeger's official installer
#   -h, --help
#
# Jaeger-style product split:
#   install.sh  → put ARES on disk (prereqs, venv, app, CLI). Minimal interview.
#   first launch / `ares setup` → onboarding wizard (Companion, models, network).
#   JaegerAI is a required peer runtime, not a pip dep of ARES's WebUI venv.
=======
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
>>>>>>> wip/multiagent-orchestrator

set -euo pipefail

<<<<<<< HEAD
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
NO_AUTOSTART=false
WITH_JAEGER=false
ARES_ROLE=""
ARES_PRIMARY_URL=""
ARES_SOURCE_DIR="$SCRIPT_DIR"
ARES_BUNDLE_ID="com.jenkinsrobotics.ares-desktop"

while [[ $# -gt 0 ]]; do
    case $1 in
        --role)          ARES_ROLE="$2"; shift 2 ;;
        --primary-url)   ARES_PRIMARY_URL="$2"; shift 2 ;;
        --no-start)      NO_START=true; shift ;;
        --no-autostart)  NO_AUTOSTART=true; shift ;;
        --with-jaeger)   WITH_JAEGER=true; shift ;;
        -h|--help)
            echo "ARES installer"
            echo ""
            echo "  curl -fsSL https://raw.githubusercontent.com/shuwalker/ARES/main/install.sh | bash"
            echo "  bash install.sh [--role primary|client] [--primary-url URL]"
            echo "                  [--no-start] [--no-autostart] [--with-jaeger]"
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

# ── 3. Role selection (defaults like Jaeger: install is non-interview) ───────
_select_role() {
    if [ -n "$ARES_ROLE" ]; then
        [ "$ARES_ROLE" != "primary" ] && [ "$ARES_ROLE" != "device" ] && \
            die "Invalid role '$ARES_ROLE' — must be primary or client"
        ok "Role: $ARES_ROLE"
        return 0
    fi

    # Non-interactive / piped curl: default primary (onboarding can change later).
    if [ ! -t 0 ]; then
        ARES_ROLE="primary"
        ok "Role: primary (default — non-interactive install)"
        return 0
    fi

    echo ""
    echo -e "${MAGENTA}${BOLD}  Which machine is this?${NC}  ${CYAN}(Enter = Primary)${NC}"
    echo ""
    echo "  1) Primary   Always-on Mac — full model, Tailscale reachable  [default]"
    echo "  2) Client    MacBook / secondary — uses primary when online"
    echo ""
    printf "  Select [1/2]: "
    read -r _choice || _choice=""
    case "${_choice:-1}" in
        1|primary|"")      ARES_ROLE="primary"; ok "Role: Primary" ;;
        2|client|device)   ARES_ROLE="device";  ok "Role: Client"  ;;
        *) die "Invalid selection — use 1 or 2 (or pass --role primary)" ;;
    esac

    if [ "$ARES_ROLE" = "device" ] && [ -z "$ARES_PRIMARY_URL" ]; then
        echo ""
        printf "  Primary machine URL (e.g. http://100.x.y.z:8787) — blank to set later: "
        read -r ARES_PRIMARY_URL || ARES_PRIMARY_URL=""
        ARES_PRIMARY_URL="${ARES_PRIMARY_URL// /}"
        [ -n "$ARES_PRIMARY_URL" ] && ok "Primary URL: $ARES_PRIMARY_URL" || \
            info "No primary URL set — add it later in Settings / onboarding"
    fi
}

# ── 4. Tailscale — probe only during install (setup/onboarding owns enable) ──
_tailscale_bin() {
    if command -v tailscale >/dev/null 2>&1; then
        echo "tailscale"
    elif [ -x "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]; then
        echo "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    fi
}

_tailscale_ip() {
    local ts; ts="$(_tailscale_bin)"
    [ -z "$ts" ] && return 1
    "$ts" ip -4 2>/dev/null | head -1
}

_check_tailscale() {
    [ "$OS" != "Darwin" ] && return 0

    if [ -z "$(_tailscale_bin)" ]; then
        warn "Tailscale not installed — optional; enable in onboarding for remote/iPhone access"
        info "  https://tailscale.com/download"
        return 0
    fi

    local ip; ip="$(_tailscale_ip || true)"
    if [ -n "$ip" ]; then
        ok "Tailscale connected ($ip)"
    else
        warn "Tailscale installed but not connected — remote access unavailable until signed in"
    fi
}

# ── 5. JaegerAI peer probe (required Companion; separate product install) ────
_probe_jaeger() {
    local home="${ARES_JAEGER_HOME:-${JAEGER_HOME:-$HOME/jaeger}}"
    local launcher="$home/jaeger"

    info "Checking JaegerAI peer runtime at $home..."
    if [ -x "$launcher" ]; then
        ok "JaegerAI peer present: $launcher"
        return 0
    fi

    warn "JaegerAI peer not found at $launcher"
    if [ "$WITH_JAEGER" = true ]; then
        info "Installing JaegerAI via official one-liner (--with-jaeger)..."
        if curl -fsSL "https://raw.githubusercontent.com/JenkinsRobotics/JaegerAI/master/scripts/install.sh" \
            | JAEGER_HOME="$home" bash; then
            if [ -x "$launcher" ]; then
                ok "JaegerAI installed at $home"
                return 0
            fi
            warn "JaegerAI installer finished but launcher still missing — check $home"
        else
            warn "JaegerAI installer failed — Companion onboarding will retry / show fix"
        fi
        return 0
    fi

    info "Companion requires JaegerAI. Install peer (or re-run with --with-jaeger):"
    info "  curl -fsSL https://raw.githubusercontent.com/JenkinsRobotics/JaegerAI/master/scripts/install.sh | bash"
    info "ARES onboarding can also install it when the WebUI is running."
}

# ── Run pre-install steps ────────────────────────────────────────────────────
_select_role
_check_tailscale
_probe_jaeger

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
if [ "$OS" = "Darwin" ] && [ "$HAS_SWIFT" = true ] && [ -f "$SCRIPT_DIR/Package.swift" ]; then
    USE_MAC_APP=true
fi

WEBUI_INSTALLER="$SCRIPT_DIR/webui/scripts/install.sh"
if [ ! -f "$WEBUI_INSTALLER" ]; then
    die "webui installer not found at $WEBUI_INSTALLER"
fi

INNER_ARGS=("--no-start" "--dir" "$HOME/.ares" "--source-dir" "$ARES_SOURCE_DIR" "${EXTRA_ARGS[@]}")
bash "$WEBUI_INSTALLER" "${INNER_ARGS[@]}"

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
        # Match CFBundleIdentifier used by packaged ARES.app (UserDefaults.standard domain)
        for domain in "$ARES_BUNDLE_ID" "com.jenkinsrobotics.ares" "ARES"; do
            defaults write "$domain" ares.config.role         "$ARES_ROLE"           2>/dev/null || true
            defaults write "$domain" ares.config.continuityDir "$ARES_CONTINUITY_DIR" 2>/dev/null || true
            [ -n "$ARES_PRIMARY_URL" ] && \
                defaults write "$domain" ares.config.primaryURL "$ARES_PRIMARY_URL" 2>/dev/null || true
        done
        ok "Mac app config synced ($ARES_BUNDLE_ID)"
    fi
}

_write_role_config

# ── 11. launchd (macOS — auto-start server at login) ─────────────────────────
_setup_launchd() {
    [ "$OS" != "Darwin" ] && return 0
    if [ "$NO_AUTOSTART" = true ]; then
        info "Skipping launchd WebUI (--no-autostart) — start via ARES.app / ares start"
        return 0
    fi

    local plist_dir="$HOME/Library/LaunchAgents"
    local plist="$plist_dir/com.ares.webui.plist"
    local python=""
    for candidate in \
        "$HOME/.ares/webui/venv/bin/python" \
        "$HOME/.ares/webui/.venv/bin/python" \
        "$SCRIPT_DIR/webui/venv/bin/python" \
        "$SCRIPT_DIR/webui/.venv/bin/python"
    do
        if [ -x "$candidate" ]; then
            python="$candidate"
            break
        fi
    done
    local server="$HOME/.ares/webui/server.py"
    [ -f "$server" ] || server="$SCRIPT_DIR/webui/server.py"
    local workdir
    workdir="$(cd "$(dirname "$server")" && pwd)"
    local logfile="$HOME/.ares/webui.log"

    if [ -z "$python" ] || [ ! -x "$python" ]; then
        warn "launchd setup skipped — WebUI venv python not found"
        return 0
    fi
    if [ ! -f "$server" ]; then
        warn "launchd setup skipped — server.py not found"
        return 0
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
        <key>ARES_ROLE</key>
        <string>$ARES_ROLE</string>
        <key>ARES_CONTINUITY_DIR</key>
        <string>$ARES_CONTINUITY_DIR</string>
$primary_url_xml
        <key>HERMES_HOME</key>
        <string>$HOME/.ares</string>
        <key>HERMES_WEBUI_STATE_DIR</key>
        <string>$HOME/.ares/webui</string>
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

# ── 12. Build and package ARES.app ───────────────────────────────────────────
# A real .app bundle (not a bare binary): `open` grants window activation so
# the app comes to the FRONT, it survives the terminal closing, and it is
# reopenable from Spotlight / Finder / Dock like any other Mac app.
ARES_APP="$HOME/Applications/ARES.app"

_install_cli() {
    # Always install the ares CLI even if the Mac app build fails.
    local cmd_dir="$HOME/.local/bin"
    mkdir -p "$cmd_dir"
    cat > "$cmd_dir/ares" << CMD_EOF
#!/usr/bin/env bash
# ARES CLI Dispatcher

ARES_SRC="${SCRIPT_DIR}"
ARES_APP="${ARES_APP}"
ARES_BUNDLE_ID="${ARES_BUNDLE_ID}"
WEBUI_DIR="\$ARES_SRC/webui"
if [ ! -f "\$WEBUI_DIR/server.py" ] && [ -f "\$HOME/.ares/webui/server.py" ]; then
    WEBUI_DIR="\$HOME/.ares/webui"
fi

_webui_python() {
    for p in "\$WEBUI_DIR/venv/bin/python" "\$WEBUI_DIR/.venv/bin/python"; do
        [ -x "\$p" ] && { echo "\$p"; return 0; }
    done
    return 1
}

_reset_onboarding_defaults() {
    # Swift OnboardingManager uses UserDefaults key ares_onboarding_completed
    # under the app's CFBundleIdentifier domain.
    for domain in "\$ARES_BUNDLE_ID" "com.jenkinsrobotics.ares" "ARES"; do
        defaults delete "\$domain" ares_onboarding_completed 2>/dev/null || true
        defaults write "\$domain" ares_onboarding_completed -bool false 2>/dev/null || true
        defaults write "\$domain" ARESForceOnboarding -bool true 2>/dev/null || true
    done
}

CMD="\${1:-}"

case "\$CMD" in
    doctor)
        shift
        PY="\$(_webui_python || true)"
        if [ -n "\$PY" ]; then
            exec "\$PY" "\$ARES_SRC/webui/cli/doctor.py" "\$@"
        else
            exec python3 "\$ARES_SRC/webui/cli/doctor.py" "\$@"
        fi
        ;;
    update)
        shift
        exec bash "\$ARES_SRC/scripts/update.sh" "\$@"
        ;;
    setup|--setup|onboarding|--onboarding)
        shift
        WIPE=false
        for arg in "\$@"; do
            [ "\$arg" = "--wipe-companion" ] && WIPE=true
        done
        _reset_onboarding_defaults
        if [ "\$WIPE" = true ]; then
            echo "Wiping Companion instances (--wipe-companion)..."
            rm -rf "\$HOME/jaeger/.jaeger_os/instances" "\$HOME/.jaeger/.jaeger_os/instances" \\
                   "\$HOME/.jaeger/instances" "\$HOME/.ares/instances" "\$ARES_SRC/webui/.ares_state" 2>/dev/null || true
        fi
        echo "Resetting ARES onboarding... Opening wizard."
        if [ -d "\$ARES_APP" ]; then
            exec open "\$ARES_APP"
        else
            echo "ARES.app not found at \$ARES_APP — start WebUI and open http://127.0.0.1:8787"
            exit 1
        fi
        ;;
    uninstall)
        shift
        exec bash "\$ARES_SRC/scripts/uninstall.sh" "\$@"
        ;;
    start|"")
        shift
        if [ "\${1:-}" = "--cli" ] || [ "\${1:-}" = "--server" ]; then
            cd "\$WEBUI_DIR"
            PY="\$(_webui_python || true)"
            if [ -n "\$PY" ] && [ -f "server.py" ]; then
                export HERMES_HOME="\${HERMES_HOME:-\$HOME/.ares}"
                export HERMES_WEBUI_STATE_DIR="\${HERMES_WEBUI_STATE_DIR:-\$HOME/.ares/webui}"
                export HERMES_WEBUI_HOST="\${HERMES_WEBUI_HOST:-127.0.0.1}"
                export HERMES_WEBUI_PORT="\${HERMES_WEBUI_PORT:-8787}"
                exec "\$PY" server.py
            else
                echo "WebUI server.py / venv not found under \$WEBUI_DIR" >&2
                exit 1
            fi
        else
            if [ -d "\$ARES_APP" ]; then
                exec open "\$ARES_APP"
            else
                echo "ARES.app missing — try: ares start --server" >&2
                exit 1
            fi
        fi
        ;;
    *)
        echo "Unknown ARES command: \$CMD"
        echo "Available commands: start, setup, update, doctor, uninstall"
        echo "  ares setup                 Reset onboarding flags and open wizard"
        echo "  ares setup --wipe-companion Also delete Jaeger companion instances"
        echo "  ares start --server        Run WebUI server.py in foreground"
        exit 1
        ;;
esac
CMD_EOF
    chmod +x "$cmd_dir/ares"
    ok "Command installed: ares"

    # Compatibility for installs whose shell profile still aliases `ares` to
    # ~/.ares/ares.sh. This prevents the alias from masking the real command.
    mkdir -p "$HOME/.ares"
    cat > "$HOME/.ares/ares.sh" << 'COMPAT_EOF'
#!/usr/bin/env bash
exec "$HOME/.local/bin/ares" "$@"
COMPAT_EOF
    chmod +x "$HOME/.ares/ares.sh"
    if ! echo "$PATH" | grep -q "$cmd_dir"; then
        local path_line='export PATH="$HOME/.local/bin:$PATH"'
        for profile in "$HOME/.zprofile" "$HOME/.zshrc"; do
            touch "$profile"
            if ! grep -Fqx "$path_line" "$profile" 2>/dev/null; then
                printf '\n# ARES command-line launchers\n%s\n' "$path_line" >> "$profile"
            fi
        done
        export PATH="$cmd_dir:$PATH"
        hash -r 2>/dev/null || true
        ok "Added ~/.local/bin to zsh PATH"
    fi
}

_package_app() {
    [ "$OS" != "Darwin" ] && return 0
    [ "$HAS_SWIFT" != true ] && return 0

    info "Building ARES app (first build can take a few minutes)..."
    cd "$SCRIPT_DIR"
    local build_log="$HOME/.ares/build.log"
    mkdir -p "$HOME/.ares"
    if ! swift build -c release > "$build_log" 2>&1; then
        warn "Build failed — see $build_log"
        return 0
    fi
    local bin_dir bin
    bin_dir="$(swift build -c release --show-bin-path 2>/dev/null)"
    bin="$bin_dir/ARES"
    if [ ! -f "$bin" ]; then
        warn "Build output not found at $bin — skipping app packaging"
        return 0
    fi
    ok "ARES built"
    local app_version
    app_version="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "0.0.0")"

    # Assemble the bundle
    mkdir -p "$ARES_APP/Contents/MacOS" "$ARES_APP/Contents/Resources"
    cp -f "$bin" "$ARES_APP/Contents/MacOS/ARES"
    if [ -f "$SCRIPT_DIR/ARES-Desktop/Sources/ARES/Resources/AppIcon.icns" ]; then
        cp -f "$SCRIPT_DIR/ARES-Desktop/Sources/ARES/Resources/AppIcon.icns" \
            "$ARES_APP/Contents/Resources/AppIcon.icns"
    fi
    # SPM resource bundles (if any) live next to the binary
    for b in "$bin_dir"/*.bundle; do
        [ -e "$b" ] && cp -Rf "$b" "$ARES_APP/Contents/Resources/"
    done
    cat > "$ARES_APP/Contents/Info.plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ARES</string>
    <key>CFBundleIdentifier</key>
    <string>com.jenkinsrobotics.ares-desktop</string>
    <key>CFBundleName</key>
    <string>ARES</string>
    <key>CFBundleDisplayName</key>
    <string>ARES</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${app_version}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST_EOF
    # Ad-hoc sign so Gatekeeper/TCC treat it as a stable identity
    codesign --force --deep --sign - "$ARES_APP" 2>/dev/null || true
    ok "Packaged $ARES_APP"
}

_write_install_manifest() {
    local manifest="$HOME/.ares/installation.json"
    local version
    version="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "0.0.0")"
    cat > "$manifest" << MANIFEST_EOF
{
  "product": "ARES",
  "version": "$version",
  "source_dir": "$SCRIPT_DIR",
  "install_dir": "$HOME/.ares",
  "webui_dir": "$HOME/.ares/webui",
  "app_path": "$ARES_APP",
  "backend": "unconfigured",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
MANIFEST_EOF
    ok "Installation manifest: $manifest"
}

_install_cli
_package_app
_write_install_manifest

# ── 13. Verification — report what is actually LIVE, not what's on disk ──────
_verify_install() {
    echo ""
    echo -e "${MAGENTA}${BOLD}── Install verification ──${NC}"

    # Web server responding?
    if curl -s -m 3 http://127.0.0.1:8787/health >/dev/null 2>&1; then
        ok "Web server      responding at http://localhost:8787"
    else
        warn "Web server      NOT responding — check ~/.ares/webui.log"
    fi

    # Tailscale connected?
    local ts_ip; ts_ip="$(_tailscale_ip || true)"
    if [ -n "$ts_ip" ]; then
        ok "Tailscale       connected — remote URL: http://$ts_ip:8787"
    else
        warn "Tailscale       NOT connected — no iPhone/remote access until you sign in"
    fi

    echo ""
}

_verify_install

# ── 14. Launch ────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}ARES installed.${NC}"
echo ""
echo "  Next steps (Jaeger-style: install code, then configure):"
echo "    ares                  # open ARES.app / onboarding wizard"
echo "    ares setup            # force re-run onboarding"
echo "    ares doctor           # health + JaegerAI peer checks"
echo "    ares start --server   # WebUI only on http://127.0.0.1:8787"
if [ ! -x "${ARES_JAEGER_HOME:-${JAEGER_HOME:-$HOME/jaeger}}/jaeger" ]; then
    echo ""
    echo "  JaegerAI peer (required Companion) not detected — install with:"
    echo "    curl -fsSL https://raw.githubusercontent.com/JenkinsRobotics/JaegerAI/master/scripts/install.sh | bash"
    echo "    # or: bash install.sh --with-jaeger"
fi
echo ""

if [ "$USE_MAC_APP" = true ] && [ "$NO_START" = false ]; then
    local_bin="$HOME/.local/bin/ares"
    if [ -f "$local_bin" ]; then
        info "Launching ARES (detached — survives closing this terminal)..."
        bash "$local_bin" || open "$ARES_APP" 2>/dev/null || true
        echo "  Menu bar app launching; complete onboarding in the window."
    else
        warn "App build unavailable — use: ares start --server  →  http://localhost:8787"
    fi
elif [ "$USE_MAC_APP" != true ] && [ "$NO_START" = false ]; then
    echo "  Open in browser after start:   http://localhost:8787"
    _ts_ip="$(_tailscale_ip || true)"
    [ -n "$_ts_ip" ] && echo "  Remote URL:        http://$_ts_ip:8787"
fi

if [ "$NO_START" = true ]; then
    echo "  Start when ready:  ares"
fi
=======
ARES_HOME="${ARES_HOME:-$HOME/.ares}"
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
# 4. Run in-repo installer
# ─────────────────────────────────────────────────────────────────────────────

echo "→ running ARES installer..."
if [[ -x "$ARES_HOME/install.sh" ]]; then
  bash "$ARES_HOME/install.sh"
else
  echo "✗ $ARES_HOME/install.sh not found" >&2
  exit 1
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
echo "  ares                      # Launch ARES (CLI)"
echo "  ares --setup              # Run setup wizard"
echo "  ares update               # Update ARES to latest"
echo
if [[ "$JAEGER_FOUND" == "true" ]]; then
  echo "JaegerAI is already installed — ARES will auto-detect it."
else
  echo "Optional: Install JaegerAI for local Companion runtime:"
  echo "  curl -fsSL https://raw.githubusercontent.com/JenkinsRobotics/JaegerAI/master/scripts/install.sh | bash"
fi
echo
>>>>>>> wip/multiagent-orchestrator
