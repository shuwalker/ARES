#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

orphaned="$(find attic -type f \( \
  -name '*.swift' -o -name '*.rs' -o -name '*.py' -o -name '*.ts' -o \
  -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.c' -o \
  -name '*.cc' -o -name '*.cpp' -o -name '*.h' -o -name '*.m' -o \
  -name '*.mm' \
\) -print 2>/dev/null || true)"

if [[ -n "$orphaned" ]]; then
  echo "Source files without a build/runtime owner were found under attic/:" >&2
  echo "$orphaned" >&2
  echo "Move the capability behind an active ARES contract or remove the copy." >&2
  exit 1
fi

retired_roots=(
  webui/api/langgraph_study
  webui/api/evolution
  webui/api/steering
  webui/api/compression_eval
  webui/api/hwfit
)
retired_tracked="$(git ls-files -- "${retired_roots[@]}")"
if [[ -n "$retired_tracked" ]]; then
  echo "Retired experimental source trees are tracked:" >&2
  echo "$retired_tracked" >&2
  echo "Integrate code through an active ARES service or keep experiments on a branch." >&2
  exit 1
fi

retired_device_python="$(git ls-files -- 'webui/api/adapters/*.py')"
if [[ -n "$retired_device_python" ]]; then
  echo "Unowned Python device-adapter source is tracked:" >&2
  echo "$retired_device_python" >&2
  echo "Web device APIs must have an initialized service, reachable UI, and real probes." >&2
  exit 1
fi

echo "Source ownership check passed."
