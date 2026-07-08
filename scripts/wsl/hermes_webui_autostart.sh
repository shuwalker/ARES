#!/usr/bin/env bash
set -euo pipefail

# Compatibility wrapper. The canonical WSL autostart implementation lives with
# the WebUI launcher scripts so fixes only need to be made in one place.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
exec "${REPO_ROOT}/webui/scripts/wsl/hermes_webui_autostart.sh" "$@"
