# Orphaned tests

Tests preserved here target APIs that do not exist in ARES. They are kept rather
than deleted (per `.claude/CLAUDE.md`) in case the feature is later built.

## test_ares_ollama_provider_sync.py

Imports four symbols that ARES does not have:

| Symbol | Status |
|---|---|
| `api.routes._JROS_COMPATIBLE_MODEL_PROVIDERS` | `api/routes.py` is upstream's 26k-line monolith. ARES replaced it with `fastapi_app/routers/`, so the module does not exist. |
| `api.ares_provider_sync.provider_runtime_status` | Never implemented in ARES. |
| `PROVIDER_PRESETS["ollama-launch"]` | No such preset. |
| `JROS_FALLBACK_PROVIDER_MAP["ollama-launch"]` | No such entry. |

Because the import fails at collection time, **the whole file never ran** — it
was not a set of failing tests, it was zero tests silently not executing.

Its intent is still worth building: `test_provider_status_distinguishes_installed_from_running`
describes a provider status that separates "installed but not running" from
"not installed", which matches FOUNDATION's requirement to degrade honestly when
a service is absent. Restore this file when that status API and the
`ollama-launch` provider lane actually exist.
