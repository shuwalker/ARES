# Cognitive OS — As Built

The "cognitive operating system with embodied state visualization" layer
added in PR #2. Five commits, 46 unit tests, ships as Phases 0 → 4 from
the roadmap.

This is the architecture-of-record for everything cognition-driven that's
already live in the repo. Older docs (`ARCHITECTURE.md`,
`RENDERING_ARCHITECTURE.md`, `BUILD_SPEC_FACE_APP.md`) link here for
specifics; they keep the higher-level narrative.

## Three layers

The product framing the user asserted, mapped to where each layer
actually lives in code:

| Layer | Concern | Code |
|---|---|---|
| **Presence** | Avatar, immersive shaders, state-driven render | `ARES-Face/Shaders/*`, `Rendering/AvatarRenderer.swift`, `Views/AvatarSceneView.swift`, `Views/ImmersionBar.swift` |
| **Cognitive** | Mission control — what ARES is doing right now, what it recalls, why | `ares/core/cognitive.py`, `ares/memory_store.py`, `ares/core/idle.py`, `ares/models/cognitive.py`, `Views/CognitiveActivityPanel.swift`, `Views/MissionControlPanel.swift`, `Views/MemoryInspectorView.swift` |
| **Operator** | Configuration surface — models, sessions, skills, logs | `ARES-Face/Views/SidebarView.swift` + dashboard tabs (Memory Inspector + Mission Control built; remaining tabs scaffolded) |

## Data model: `CognitiveSnapshot`

Single transport contract, versioned for forward compatibility. Pushed
on every loop phase transition over the `/ws` WebSocket as
`{"type": "cognitive_snapshot", ...}`. Same shape returned by
`GET /api/cognitive/status`.

```
CognitiveSnapshot {
  schema_version: int       # bumped only on breaking change
  timestamp: float
  running: bool
  loop: {
    cycle: int
    phase: "perceive" | "think" | "act" | "reflect" | "idle"
    urgency: "low" | "medium" | "high"
    budget_remaining: 0..1
    tokens_used: int
    elapsed_ms: int
  }
  thought: {                # nullable while idle
    summary: str
    depth: int              # count of nodes in current cycle's DAG
    confidence: 0..1 | null  # populated as ARES gains the measure
    sentiment: -1..1 | null
    branches: [ThoughtNode] # the cycle's reasoning DAG
  } | null
  memory_recall: [MemoryHit]
  errors: [str]
}

ThoughtNode { id, parent_ids[], label, status, duration_ms, evidence[] }
MemoryHit  { id, score, text, kind: "episodic" | "semantic" }
```

Pydantic source: `ares/models/cognitive.py`. Swift mirror:
`ARES-Face/Models/CognitiveSnapshot.swift`. Unknown fields are ignored
on decode in both directions, so adding fields is non-breaking; only
removal or rename bumps `SCHEMA_VERSION` (currently `1`).

## Phase 0 — Heartbeat

The cognitive loop in `core/cognitive.py` already tracked
`cycle / phase / urgency / budget_remaining`. Phase 0 makes that visible:

- **`CognitiveLoop.on_phase_change`** — observer hook fired after each
  of perceive / think / act / reflect. Exceptions are swallowed so a
  bad subscriber can't crash the loop.
- **`/api/cognitive/start`** wires the observer to a thread-safe
  broadcast onto the asyncio event loop.
- **`GET /api/cognitive/status`** returns the snapshot (idle when no
  loop is running).
- WS action **`get_cognitive_snapshot`** lets clients fetch state on
  connect.
- Swift **`CognitiveActivityPanel`** — collapsed pill in
  `ImmersionBar`, expanded panel with cycle / urgency / elapsed /
  budget bar / error count.
- **`SidebarView`** mounted in `ARESRootView` (was orphaned).

## Phase 1 — Tiered memory

Three tiers, one entry point. Backend lives in `ares/memory_store.py`;
volatile turn history in `ares/runtime/session_store.py`.

| Tier | Where | Lifetime |
|---|---|---|
| Volatile | `SessionStore` deque, capacity 12 per session | Process lifetime |
| Episodic | SQLite `episodics` table + `VectorStore` for similarity recall | Forever |
| Semantic | SQLite `facts` table — triple store with provenance | Forever |

### Swappable substrates

`VectorStore` and `Embedder` are Protocols. Defaults ship with no
external dependencies:

- **`InMemoryVectorStore`** — pure-Python cosine, linear scan, fine for
  personal scale (thousands of entries).
- **`DeterministicEmbedder`** — hash-based, deterministic, no API call.
  Offline-safe and test-friendly.

Real substrates can drop in behind the same interface:

- **`OllamaEmbedder`** — lazy `httpx` call to `/api/embeddings`.
  Activate via `default_memory_store(embedder=OllamaEmbedder(...))`.
- Future: `SqliteVssStore`, `LanceDbStore`, `ChromaDbStore` —
  Protocol is already there, only the concrete file is missing.

### Endpoints

- `GET /api/memory/episodics?limit=` — list newest-first
- `GET /api/memory/facts?limit=`
- `POST /api/memory/recall` `{query, k}` — cosine top-k
- `DELETE /api/memory/episodics/{id}`

### Frontend

`Views/MemoryInspectorView.swift` — list + recall search + delete.
Routed via `SidebarView` `.sessions` tab.

### How `/api/chat` uses memory

1. Recall top-5 episodics for the user message → attach to snapshot's
   `memory_recall` for the UI.
2. Persist the exchange as one episodic entry (`USER: ...\nARES: ...`)
   with metadata `session_id`.
3. Record both turns into `SessionStore` for volatile context.
4. Broadcast a fresh `cognitive_snapshot` so the panel reflects the
   new recall without waiting for a phase transition.

The Hermes bridge wiring (the agent layer that will *use* the recall
to inject context into the LLM prompt) is deliberately untouched —
other agents own that PR.

## Phase 2 — Reasoning DAG

Every cycle emits a small DAG that describes how ARES got from input
to output.

- **`ThoughtNodeRecord`** dataclass in `ares/core/cognitive.py` —
  kept Pydantic-free so `core/` has no transport dependency.
- **`_record_phase_node`** appends a chained node per phase transition
  (default: linear `perceive → think → act → reflect`).
- **`CognitiveLoop.emit_thought_node(label, evidence, parent_ids)`** is
  the public hook for handlers to record sub-steps; defaults to chaining
  off the last node so handlers don't have to track parents.
- Branches reset at the top of each cycle.
- **Persistence**: when the cycle reaches the reflect phase, the API
  observer writes the full DAG into a new episodic with metadata
  `kind="reasoning_trace"`, `dag=[...]`. Replay tooling can reconstruct
  the trace later.

### Mission Control panel

`Views/MissionControlPanel.swift` — force-directed graph in SwiftUI
`Canvas` driven by a `TimelineView` (~60 fps). Custom Verlet integrator,
no third-party dependencies:

- Pairwise inverse-square repulsion
- Hooke spring edges (length 70 pt, stiffness 0.08)
- Center-pull keeps everything inside the canvas
- Soft margin clamping
- Damping = 0.86

Tap-to-select highlights a node and shows a detail footer. Phase nodes
are color-coded: perceive=cyan, think=orange, act=purple, reflect=green.
Routed via `SidebarView` `.logs` tab.

## Phase 3 — Idle reflexion

What ARES does between exchanges. Lives in `ares/core/idle.py`. Three
handlers + one orchestrator:

- **`consolidate_episodics(memory)`** — groups recent episodics by
  `session_id` metadata, derives a topic via token-frequency heuristic,
  writes one summary fact per session that has ≥2 entries. Single-entry
  sessions are skipped (too thin to summarize).
- **`dedupe_facts(memory, threshold=0.95)`** — pairwise cosine on
  subject+predicate+object text. Keeps the oldest fact, deletes the
  rest. Returns count deleted.
- **`surface_open_questions(memory)`** — scans recent episodics for
  `?`, `should`, `need to`, `todo`. Returns the ones that have no
  later follow-up in the same session.
- **`run_idle_pass(memory)`** — orchestrator returning `IdleReport`.

### Endpoints

- `POST /api/idle/run` — trigger a one-shot pass, returns the report
- `GET /api/idle/last_report` — most recent report (empty defaults
  before any run, so UI can render)

## Phase 4 — Shader–cognition bindings

Formalizes the implicit state→shader mapping into a single declarative
function. Adding a new metric is a one-line change.

### Uniform schema

`ARES-Face/Shaders/SharedHeader.h` — `SurfaceCustomUniforms` grew four
trailing fields (non-breaking for the five shaders that don't read
them yet):

| Field | Range | Driven by |
|---|---|---|
| `noiseScale` | 0..1 | urgency (low=0.32, medium=0.6, high=1.0) |
| `emissivePulse` | 0..1 | `thought.confidence` + urgency-driven wobble |
| `vertexJitter` | 0..1 | `thought.depth` clamped to [0..10] / 10 |
| `glitchAmplitude` | 0..1 | error count capped at 5 |

### Binding table

`ARES-Face/Rendering/CognitiveBindings.swift`:

```swift
static func evaluate(_ snapshot: CognitiveSnapshot, time: Float) -> CognitiveUniformValues
```

Pure function — no side effects, easy to reason about. Adding a metric:

1. Add a field to `CognitiveUniformValues`.
2. Implement it in `evaluate` (one line each).
3. Add a matching field in `SharedHeader.h` and `AvatarRenderer.swift`
   (must stay in same order).
4. Reference the new uniform in any `.metal` shader that needs it.

Shaders that don't reference new uniforms keep working unchanged.

### Visual proof

`Shaders/BlackFireSurface.metal` consumes `emissivePulse` (confidence
brightens the core) and `glitchAmplitude` (errors add a pixel-jump).
The other five styles are non-breaking — they get the larger uniform
struct but ignore the new fields until updated.

## Tests

46 unit tests, all passing. Layout under `tests/unit/`:

| File | Subject | Count |
|---|---|---|
| `models/test_cognitive_snapshot.py` | Snapshot defaults, round-trip, snake_case, forward-compat | 4 |
| `runtime/test_cognitive_loop_hook.py` | Observer per phase, live state, exception swallow, default no-op | 4 |
| `runtime/test_session_store.py` | Capacity, isolation, empty-id, clear, reset | 5 |
| `runtime/test_thought_dag.py` | Per-phase nodes, chain edges, fork via emit, full DAG size | 5 |
| `test_api_cognitive_status.py` | `TestClient` idle + populated snapshot | 2 |
| `test_api_memory.py` | list / recall / delete / facts endpoints | 4 |
| `test_memory_store.py` | Embedder, vector store, record/recall, rehydrate, facts | 12 |
| `test_idle_reflexion.py` | Consolidate, dedupe, surface questions, orchestrator, API | 10 |

`pytest tests/unit -m unit` runs in <1 second locally; CI matrix
covers Python 3.11 and 3.12.

## Deliberately out of scope (the next PR)

- Hermes bridge wiring (`/api/chat` → bridge → real LLM) — other
  agents own that. The `memory_recall` field in the snapshot is the
  contract they'll consume.
- Concrete `LanceDbStore` / `ChromaDbStore` / `SqliteVssStore`
  `VectorStore` implementations. Protocol shipped, swap is a config
  flip.
- `OllamaEmbedder` is wired but not the default — activate via
  `default_memory_store(embedder=OllamaEmbedder(...))`.
- DAG **replay** scrubber (persistence layer shipped; UI follows).
- Population of remaining operator tabs (`.models`, `.skills`,
  `.cron`, `.analytics`) — sidebar shows them as "coming soon".
