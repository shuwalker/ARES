# AI Agent Handoff Guide

For agents picking up work on ARES. Optimized for someone who has not
been in the previous session.

## Read these first (in order)

1. **[`ARCHITECTURE.md`](./ARCHITECTURE.md)** — system overview, file
   map, communication protocols, REST + WS endpoints.
2. **[`COGNITIVE_OS.md`](./COGNITIVE_OS.md)** — the cognition / memory
   / DAG / idle / shader-bindings layer that landed in PR #2.
3. **[`RENDERING_ARCHITECTURE.md`](./RENDERING_ARCHITECTURE.md)** —
   RealityKit + Metal pipeline and the cognition-driven shader uniform
   contract.
4. **[`FILES_INDEX.md`](./FILES_INDEX.md)** — repo file map.
5. The skill/project's `VISION.md` and `PLAN.md` (under
   `ares/reference/swift-ui/`) for the longer-arc product narrative.

## State of the world (current branch)

✅ **Built**
- Python brain: cognitive loop with DAG + observer, tiered memory
  (SQLite + swappable `VectorStore`), idle reflexion, personality,
  identity, ZMQ bus.
- FastAPI server (`ares/api.py`): REST + WebSocket; pushes
  `cognitive_snapshot` events on every phase transition.
- ARES-Face SwiftUI app: 6 RealityKit/Metal styles, heartbeat pill,
  Memory Inspector, force-directed Mission Control DAG, cognition-driven
  shader uniforms.
- Tests: 46 unit tests under `tests/unit/`, GitHub Actions CI for
  Python 3.11 + 3.12 with `ruff` + `black`.

🔨 **Open / next**
1. **Hermes bridge wiring** — `ares/runtime/hermes_bridge.py`
   `cognition_query()` is a stub. The agent owning this PR replaces it
   with a real Hermes invocation. `ares_bridge_minimal.py` shows the
   `hermes -z <text>` subprocess pattern. The snapshot's `memory_recall`
   field is the contract for context injection.
2. **Concrete `VectorStore`** — protocol is in `ares/memory_store.py`;
   ship one of `SqliteVssStore`, `LanceDbStore`, or `ChromaDbStore`
   behind it. Default stays `InMemoryVectorStore` for tests.
3. **Voice pipeline** — STT mic → brain → TTS speaker.
4. **Operator tab build-out** — `.models`, `.skills`, `.cron`,
   `.analytics` in `ARES-Face/Views/`. Sidebar is mounted; pages stubbed.
5. **DAG replay UI** — DAGs are persisted into episodic metadata
   already; build a scrubber that pulls one and replays it through
   `MissionControlPanel`.
6. **Robot control** — JP01 servo commands over bus.

## Tests

The test layout was added in PR #2. Use it.

```
tests/
├── integration/test_services.py    # 27 tests, auto-skip when services aren't running
└── unit/                            # 46 passing — fast, in-process
    ├── conftest.py                  # auto-marks `unit`
    ├── README.md                    # priority list
    ├── models/
    ├── runtime/
    └── *.py
```

Run:

```bash
pytest tests/unit -m unit                   # fast, deterministic
pytest tests/unit --cov=ares --cov-report=term-missing
pytest -m "not integration"                  # skip integration suite
```

Adding tests:
- Tests under `tests/unit/` are auto-marked `unit` by `conftest.py`.
- Use `tmp_path` for SQLite tests (see `test_memory_store.py`).
- For API tests, use `TestClient` with `monkeypatch.setattr("ares.api.SERVICES", [])`
  to prevent lifespan from spawning subprocesses (see
  `test_api_cognitive_status.py`).

## Conventions

- **No new files outside the established layout.** New Pydantic models
  go in `ares/models/`; new SwiftUI views in `ARES-Face/Views/`; new
  shaders in `ARES-Face/Shaders/`.
- **Forward-compatible contracts.** When extending `CognitiveSnapshot`
  or any other shared model, add fields with defaults. Bump
  `SCHEMA_VERSION` only on breaking change.
- **Protocols before implementations.** When introducing a new
  swappable backend (vector store, embedder, cognition backend, etc.),
  define the `Protocol` first, ship a zero-dep default, then add
  concretes.
- **Layering.** `core/` must not import Pydantic models from
  `ares/models/` — keeps the loop free of transport dependencies. The
  API layer maps `core/` dataclasses to `models/` Pydantic shapes (see
  `_build_snapshot` in `api.py`).
- **Tests for new features.** No new untested code paths in `core/`,
  `memory_store.py`, or `api.py`. Swift code isn't testable from
  Linux CI; rely on the Xcode test target for UI/shader changes.

## What to send for code review

When a feature is done:
1. `pytest tests/unit -m unit` passes locally.
2. `pytest tests/integration` doesn't fail (auto-skip is fine).
3. Commit on the designated feature branch with a descriptive message.
4. Open a draft PR; mark ready for review when you're done iterating.
5. Mention which doc(s) you updated. If the architecture changes,
   update `ARCHITECTURE.md` and/or `COGNITIVE_OS.md`.

## Common pitfalls

- **Don't access `_cognitive_loop._running` from a test** without
  setting it manually first — it's the default sentinel for "loop
  started" in `api.py`.
- **`max_cycles=1` runs zero phase transitions** — the stop hook fires
  before phases execute. Use `max_cycles=2` to get one full cycle of
  perceive/think/act/reflect.
- **Lifespan in `TestClient`** will try to spawn MCP subprocesses unless
  `SERVICES` is patched to `[]`.
- **Metal `SurfaceCustomUniforms` field order** must match
  `SharedHeader.h` and the Swift mirror in `AvatarRenderer.swift`.
  Appending fields is non-breaking; reordering breaks rendering.
