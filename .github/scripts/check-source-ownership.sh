#!/usr/bin/env bash
set -euo pipefail

# Script lives in .github/scripts/ — monorepo root is two levels up.
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
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
  services/controller/api/langgraph_study
  services/controller/api/evolution
  services/controller/api/steering
  services/controller/api/compression_eval
  services/controller/api/hwfit
)
retired_tracked="$(git ls-files -- "${retired_roots[@]}")"
if [[ -n "$retired_tracked" ]]; then
  echo "Retired experimental source trees are tracked:" >&2
  echo "$retired_tracked" >&2
  echo "Integrate code through an active ARES service or keep experiments on a branch." >&2
  exit 1
fi

# Compatibility shims under api/adapters/ are allowed (implementation lives in
# integrations/tools/adapters/). Flag only non-shim Python under that path.
retired_device_python="$(
  git ls-files -- 'services/controller/api/adapters/**/*.py' 'services/controller/api/adapters/*.py' \
    | while read -r f; do
        # Shim packages are a single __init__.py re-export; anything else is retired source.
        base="$(basename "$f")"
        if [[ "$base" != "__init__.py" ]]; then
          printf '%s\n' "$f"
        fi
      done
)"
if [[ -n "$retired_device_python" ]]; then
  echo "Unowned Python device-adapter source is tracked:" >&2
  echo "$retired_device_python" >&2
  echo "Web device APIs must have an initialized service, reachable UI, and real probes." >&2
  exit 1
fi

echo "Source ownership check passed."
