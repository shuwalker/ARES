# Unit Tests

Mirrors the `ares/` package layout. Unit tests run fully in-process — they must
not require any ARES service to be listening on a network port. Use
`unittest.mock`, FastAPI's `TestClient`, Click's `CliRunner`, or
`httpx.MockTransport` instead of real I/O.

Tests collected under this directory are automatically tagged with the `unit`
marker (see `tests/unit/conftest.py`). Run them with:

```bash
pytest tests/unit -m unit --cov=ares --cov-report=term-missing
```

## Priority order for filling in tests

1. **`models/`** — `system.py`, `project.py`, `engineering.py`. Pure Pydantic
   validation logic; highest ROI, no mocking required.
2. **`cli` & `api`** — `ares/cli.py` (Click `CliRunner`) and `ares/api.py`
   (FastAPI `TestClient`). Largest user-facing surfaces.
3. **`llm/`** — `router.py`, `cloud.py`, `local.py`. Mock the Anthropic SDK
   and HTTP transports; verify routing decisions.
4. **`core/`** — `bus.py` (ZMQ in-process transport), `cognitive.py`,
   `personality.py` (deterministic given a seed), `memory.py`, `identity.py`,
   `face_state.py`.

Modules deferred to a later pass: `runtime/`, `tasks/`, `tools/`, `workflows/`,
`skills/cognitive/*`, and top-level `daemon.py`, `discovery.py`, `mcp_serve.py`,
`memory.py`, `reasoning.py`, `audit.py`, `sync.py`, `config.py`.
