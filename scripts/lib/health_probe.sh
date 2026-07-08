#!/usr/bin/env bash
# Compatibility wrapper. The canonical TLS-aware WebUI health probe lives under
# webui/scripts/lib so shell launcher fixes have one source of truth.
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "${_SCRIPT_DIR}/../.." && pwd)"
_CANONICAL="${_REPO_ROOT}/webui/scripts/lib/health_probe.sh"

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  exec bash "${_CANONICAL}" "$@"
fi

# shellcheck source=../../webui/scripts/lib/health_probe.sh
. "${_CANONICAL}"
