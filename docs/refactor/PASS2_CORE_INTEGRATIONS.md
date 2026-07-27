# Pass 2 — core/ and integrations/ (real modules)

Branch: `refactor/move-only-folder-structure`

## What moved

| Original | New | Compatibility |
|----------|-----|-----------------|
| `services/controller/api/si` | `core/si` | `api/si` shim |
| `services/controller/api/journal` | `core/memory/journal` | `api/journal` shim |
| `services/controller/api/research` | `core/knowledge/research` | `api/research` shim |
| `services/controller/api/backends` | `integrations/workers` | `api/backends` shim |
| `services/controller/api/providers` | `integrations/providers` | `api/providers` shim |
| `services/controller/api/adapters` | `integrations/tools/adapters` | `api/adapters` shim |

## Layout now

```text
core/
  si/                 # Companion SI control plane (split further later)
  memory/journal/     # Companion journal
  knowledge/research/ # research service
integrations/
  workers/            # execution backends
  providers/          # provider adapters
  tools/adapters/     # e.g. Safari MCP
```

## Path repairs

- `services/controller/pytest.ini` pythonpath includes monorepo root
- `tests/conftest.py` sys.path + test-server PYTHONPATH
- `bootstrap.py` PYTHONPATH includes monorepo root
- Compatibility packages set `__path__` at real dirs and seed monorepo on `sys.path`

## Verification

| Check | Result |
|-------|--------|
| SI baseline (128) | **passed** after moves |
| Import smoke `api.backends` / `api.si` / `api.journal` | ok |

## Still later

- Split `core/si` into `identity/`, `orchestration/`, `authority/`, `events/` without breaking relative imports
- Move more flat `api/*.py` memory/session modules into `core/memory`
- Sensors under `integrations/sensors` (observer already at `services/observer`)
- Remove shims once call sites import `core.*` / `integrations.*` directly (Pass 4)
