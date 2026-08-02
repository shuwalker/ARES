# Controller Agent Guide

Read the repository [`AGENTS.md`](../../AGENTS.md) first. The text documents in
`services/controller/docs/` are active compatibility and upstream-derived
contracts; do not delete them merely because canonical ARES docs live at root.

## Scope

The controller owns authentication, ARES persistence, settings, normalized
runtime adapters, HTTP/SSE contracts, and production Web UI serving.

## Rules

- Keep ARES-owned state separate from worker-owned state.
- New provider state uses canonical backend IDs from `api/backend_catalog.py`.
- Legacy JROS variables and IDs are migration inputs only; do not emit them from
  new launchers, API responses, or UI contracts.
- Keep framework-native imports and payloads behind adapters.
- Settings changes require validation, API documentation, and persistence or
  behavior tests.
- Prompt configuration must not bypass permissions, safety instructions, or
  approval policy.
- Maintain the monorepo paths to `core/`, `integrations/`, and `apps/web/dist`.

## Verification

Use the controller virtual environment and focused tests while iterating:

```bash
.venv/bin/python -m pytest -q tests/<relevant_test>.py
```

Run `./scripts/test.sh` for a broad pass. Read `docs/CURRENT_STATE.md` before
interpreting inherited full-suite failures.
