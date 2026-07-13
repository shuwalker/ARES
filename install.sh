#!/usr/bin/env bash
# ARES Installation Script
# Sets up role (primary / client), checks JaegerAI and Tailscale, installs the
# Web UI, writes role config, registers the launchd auto-start service, and
# launches the Mac app.
#
# Usage:
#   bash install.sh [--role primary|client] [--primary-url URL]
#                   [--backend auto|hermes|jros|hybrid]
#                   [--no-start] [--with-hermes]
#
# Options:
#   --role primary     This machine is always-on (Mac Studio / home server)
#   --role client      This machine connects to the primary when reachable
#   --primary-url URL  Primary machine URL for client mode (e.g. http://100.x.y.z:8787)
#   --backend MODE     Backend mode: auto, hermes, jros, or hybrid (default: auto)
#   --no-start         Skip auto-starting after installation
#   --with-hermes      Also install Hermes Agent (optional addition)

set -e

EXTRA_ARGS=()
NO_START=false
ARES_ROLE=""
ARES_PRIMARY_URL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --backend)
            EXTRA_ARGS+=("--backend" "$2")
            shift 2
            ;;
        --no-start)
            NO_START=true
            EXTRA_ARGS+=("--no-start")
            shift
            ;;
        --with-hermes)
            EXTRA_ARGS+=("--with-hermes")
            shift
            ;;
        --role)
            ARES_ROLE="$2"
            shift 2
            ;;
        --primary-url)
            ARES_PRIMARY_URL="$2"
            shift 2
            ;;
        -h|--help)
            echo "ARES Installation Script"
            echo ""
            echo "Usage: bash install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --role primary|client  Machine role (prompted if omitted)"
            echo "  --primary-url URL      Primary machine URL for client mode"
            echo "  --backend MODE         Backend mode: auto, hermes, jros, or hybrid"
            echo "  --no-start             Skip auto-starting after installation"
            echo "  --with-hermes          Also install Hermes Agent"
            echo "  -h, --help             Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: bash install.sh [--role primary|client] [--backend MODE] [--no-start]"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBUI_INSTALLER="$SCRIPT_DIR/webui/scripts/install.sh"

if [ ! -f "$WEBUI_INSTALLER" ]; then
    echo "ERROR: WebUI installer not found at $WEBUI_INSTALLER"
    echo "Make sure this script is run from the root of the ARES repository."
    exit 1
fi

echo "======================================"
echo "  ARES — Installation"
echo "======================================"
echo ""

# ── Step 1: Role selection ─────────────────────────────────────────────────────
# Determines whether this machine is the primary brain (always-on, full model)
# or a client that falls back to a local model when the primary is unreachable.
_select_role() {
    # Normalise "client" alias → internal value "device"
    if [ "$ARES_ROLE" = "client" ]; then ARES_ROLE="device"; fi

    if [ -n "$ARES_ROLE" ]; then
        if [ "$ARES_ROLE" != "primary" ] && [ "$ARES_ROLE" != "device" ]; then
            echo "Invalid role '$ARES_ROLE' — must be 'primary' or 'client'."
            exit 1
        fi
    else
        printf "\033[0;35m\033[1m"
        echo "┌──────────────────────────────────────────────────────┐"
        echo "│                 Which machine is this?               │"
        echo "├──────────────────────────────────────────────────────┤"
        echo "│  1) Primary   Always-on Mac (Mac Studio / server)   │"
        echo "│               Full model. Tailscale reachable.      │"
        echo "│                                                      │"
        echo "│  2) Client    MacBook or secondary Mac              │"
        echo "│               Uses primary when online,             │"
        echo "│               local JaegerAI model when offline.   │"
        echo "└──────────────────────────────────────────────────────┘"
        printf "\033[0m"
        echo ""

        while true; do
            printf "  Select role [1/2]: "
            read -r _role_choice
            case "$_role_choice" in
                1|primary)
                    ARES_ROLE="primary"
                    printf "\033[0;32m✓\033[0m Role: Primary (always-on)\n"
                    break
                    ;;
                2|client|device)
                    ARES_ROLE="device"
                    printf "\033[0;32m✓\033[0m Role: Client (connects to primary; local fallback)\n"
                    break
                    ;;
                *)
                    echo "  Please enter 1 or 2."
                    ;;
            esac
        done
    fi

    if [ "$ARES_ROLE" = "device" ] && [ -z "$ARES_PRIMARY_URL" ]; then
        echo ""
        printf "  Primary machine URL (e.g. http://100.x.y.z:8787) — leave blank to set later: "
        read -r ARES_PRIMARY_URL
        ARES_PRIMARY_URL="${ARES_PRIMARY_URL// /}"
        if [ -z "$ARES_PRIMARY_URL" ]; then
            echo "  → No primary URL set. Add it later in Settings → Role."
        else
            printf "\033[0;32m✓\033[0m Primary URL: %s\n" "$ARES_PRIMARY_URL"
        fi
    fi
}

# ── Step 2: JaegerAI check ────────────────────────────────────────────────────
# JaegerAI is the required Companion runtime (agent loop, memory, character,
# local model). It must be installed on BOTH primary and client machines.
_check_jaeger() {
    local jaeger_home=""
    for p in "$HOME/jaeger" "$HOME/.jaeger"; do
        [ -d "$p" ] && jaeger_home="$p" && break
    done
    if [ -n "$jaeger_home" ]; then
        printf "\033[0;32m✓\033[0m JaegerAI found at %s\n" "$jaeger_home"
        return 0
    fi

    echo ""
    printf "\033[0;33m⚠\033[0m  JaegerAI not found.\n"
    echo "    ARES requires JaegerAI as the Companion runtime on every machine."
    echo ""
    printf "  Install JaegerAI now? [Y/n]: "
    read -r _jros_ans
    case "${_jros_ans:-Y}" in
        [Yy]*)
            echo "→ Installing JaegerAI..."
            if curl -fsSL https://raw.githubusercontent.com/JenkinsRobotics/JaegerAI/master/scripts/install.sh | bash; then
                printf "\033[0;32m✓\033[0m JaegerAI installed\n"
            else
                echo ""
                echo "  JaegerAI install failed. Install manually, then re-run:"
                echo "  curl -fsSL https://raw.githubusercontent.com/JenkinsRobotics/JaegerAI/master/scripts/install.sh | bash"
                exit 1
            fi
            ;;
        *)
            echo "→ Skipping JaegerAI install — your Companion will not work without it."
            ;;
    esac
}

# ── Step 3: Tailscale check ───────────────────────────────────────────────────
# Tailscale provides the private network that lets your Companion be reached
# from your iPhone and other devices. Install is done here so it's ready before
# the Mac app or wizard starts.
_check_tailscale() {
    if command -v tailscale >/dev/null 2>&1 || [ -d "/Applications/Tailscale.app" ]; then
        printf "\033[0;32m✓\033[0m Tailscale found\n"
        return 0
    fi

    echo ""
    printf "\033[0;36m→\033[0m Tailscale not found.\n"
    echo "    Tailscale lets your Companion be reached from your iPhone and other devices."

    if command -v brew >/dev/null 2>&1; then
        echo ""
        printf "  Install Tailscale via Homebrew? [Y/n]: "
        read -r _ts_ans
        case "${_ts_ans:-Y}" in
            [Yy]*)
                echo "→ Installing Tailscale..."
                if brew install --cask tailscale 2>/dev/null; then
                    printf "\033[0;32m✓\033[0m Tailscale installed.\n"
                    echo "    Open Tailscale from Applications and sign in to your tailnet."
                else
                    echo "  Tailscale install failed. Install manually: https://tailscale.com/download"
                fi
                ;;
            *)
                echo "→ Skipping Tailscale — install later from https://tailscale.com/download"
                ;;
        esac
    else
        echo "    Install Tailscale from: https://tailscale.com/download"
        echo "    Sign in with the same account on all your devices."
    fi
}

# ── Pre-install checks ────────────────────────────────────────────────────────
_select_role
_check_jaeger
_check_tailscale
echo ""

# Profile directory — ~/Desktop/ARES/companion/ syncs across Macs via iCloud Desktop
ARES_CONTINUITY_DIR="$HOME/Desktop/ARES/companion"
mkdir -p "$ARES_CONTINUITY_DIR"
printf "\033[0;32m✓\033[0m Companion profile: %s\n" "$ARES_CONTINUITY_DIR"
echo ""

# ── On macOS with Swift, launch the Mac app after install ─────────────────────
USE_MAC_APP=false
if [ "$NO_START" = false ] \
   && [ "$(uname -s)" = "Darwin" ] \
   && [ -f "$SCRIPT_DIR/Package.swift" ] \
   && command -v swift >/dev/null 2>&1; then
    USE_MAC_APP=true
    EXTRA_ARGS+=("--no-start")
fi

bash "$WEBUI_INSTALLER" "${EXTRA_ARGS[@]}"

if [ "$NO_START" = true ]; then
    exit 0
fi

# ── Write role config ─────────────────────────────────────────────────────────
# Writes ares_role, ares_primary_url, ares_continuity_dir to ~/.ares/config.yaml
# (read by the Python server) and to ARES UserDefaults (read by the Mac app).
_write_role_config() {
    local cfg="$HOME/.ares/config.yaml"
    mkdir -p "$HOME/.ares"
    [ -f "$cfg" ] || touch "$cfg"

    _yaml_set() {
        local key="$1" val="$2" file="$3"
        if grep -q "^${key}:" "$file" 2>/dev/null; then
            sed -i '' "s|^${key}:.*|${key}: ${val}|" "$file"
        else
            echo "${key}: ${val}" >> "$file"
        fi
    }

    _yaml_set "ares_role" "$ARES_ROLE" "$cfg"
    _yaml_set "ares_continuity_dir" "$ARES_CONTINUITY_DIR" "$cfg"
    [ -n "$ARES_PRIMARY_URL" ] && _yaml_set "ares_primary_url" "$ARES_PRIMARY_URL" "$cfg"

    printf "\033[0;32m✓\033[0m Role config → %s\n" "$cfg"

    # Sync to ARES UserDefaults so the Mac app picks up the role without a restart
    defaults write ARES ares.config.role "$ARES_ROLE" 2>/dev/null || true
    defaults write ARES ares.config.continuityDir "$ARES_CONTINUITY_DIR" 2>/dev/null || true
    [ -n "$ARES_PRIMARY_URL" ] && defaults write ARES ares.config.primaryURL "$ARES_PRIMARY_URL" 2>/dev/null || true
    printf "\033[0;32m✓\033[0m Role synced to Mac app defaults\n"
}

_write_role_config

# ── macOS: install a launchd service so the web server pre-starts at login ────
_setup_launchd() {
    local plist_dir="$HOME/Library/LaunchAgents"
    local plist="$plist_dir/com.ares.webui.plist"
    local python="$HOME/.ares/webui/venv/bin/python"
    local server="$HOME/.ares/webui/server.py"
    local workdir="$HOME/.ares/webui"
    local logfile="$HOME/.ares/webui.log"

    if [ ! -f "$python" ]; then
        echo "→ launchd setup skipped (venv not found at $python)"
        return 0
    fi

    local jaeger_home=""
    local cfg="$HOME/.ares/config.yaml"
    if [ -f "$cfg" ]; then
        local cfg_val
        cfg_val=$(grep -E '^ares_jaeger_home:' "$cfg" 2>/dev/null | sed 's/^ares_jaeger_home:[[:space:]]*//' | tr -d '"' | tr -d "'" | xargs)
        [ -n "$cfg_val" ] && [ -d "$cfg_val" ] && jaeger_home="$cfg_val"
    fi
    if [ -z "$jaeger_home" ]; then
        for p in "$HOME/jaeger" "$HOME/.jaeger"; do
            [ -d "$p" ] && jaeger_home="$p" && break
        done
    fi

    local primary_url_entry=""
    if [ -n "$ARES_PRIMARY_URL" ]; then
        primary_url_entry="        <key>ARES_PRIMARY_URL</key>
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
$primary_url_entry
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
        echo "→ ARES web server: auto-start at login enabled (com.ares.webui)"
        launchctl start com.ares.webui 2>/dev/null || true
        echo "→ Starting ARES web server in background..."
        sleep 3
    else
        echo "→ launchd load failed — Mac app will start the server on first open"
    fi
}

if [ "$USE_MAC_APP" = true ]; then
    _setup_launchd
    echo ""
    echo "→ Launching ARES Mac app (builds if needed, then opens)..."
    cd "$SCRIPT_DIR"
    swift run ARES
else
    :
fi
