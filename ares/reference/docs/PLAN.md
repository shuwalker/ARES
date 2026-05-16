# ARES Implementation Plan — Phased Roadmap

This plan tracks how ARES gets from its current state to the full vision laid out in [`VISION.md`](./VISION.md). Phases are ordered by dependency, not by date — Phase N cannot start until Phase N-1's load-bearing pieces are stable.

> The cognition / memory / DAG / shader-bindings layer is already shipped as **Cognitive OS Phases 0–4** (PR #2, 46 unit tests, CI green). Its as-built reference is [`COGNITIVE_OS.md`](./COGNITIVE_OS.md). This document tracks the *larger arc* of which Cognitive OS is one cross-cutting track.

Status legend: **DONE** · **IN PROGRESS** · **NEXT** · **PLANNED**

---

## Cross-Cutting: Cognitive OS Track **DONE**

PR #2 shipped five sub-phases that span both the Python brain and the Swift face. They are the load-bearing foundation for everything below. Full detail: [`COGNITIVE_OS.md`](./COGNITIVE_OS.md).

| Sub-phase | What landed | Status |
|-----------|-------------|--------|
| **Phase 0 — Heartbeat** | `CognitiveLoop.on_phase_change` observer, `cognitive_snapshot` WS push, `GET /api/cognitive/status`, Swift `CognitiveActivityPanel` + heartbeat pill | ✅ |
| **Phase 1 — Tiered memory** | `ares/memory_store.py` with SQLite source-of-truth + swappable `VectorStore`/`Embedder` Protocols, `InMemoryVectorStore` + `DeterministicEmbedder` defaults, `OllamaEmbedder` opt-in, `MemoryInspectorView` | ✅ |
| **Phase 2 — Reasoning DAG** | `ThoughtNodeRecord` per phase, `emit_thought_node()` hook, persisted as episodic `kind="reasoning_trace"`, `MissionControlPanel` force-directed graph at ~60 fps | ✅ |
| **Phase 3 — Idle reflexion** | `ares/core/idle.py` with consolidate / dedupe / surface-open-questions handlers, `POST /api/idle/run` + `GET /api/idle/last_report` | ✅ |
| **Phase 4 — Shader-cognition bindings** | `CognitiveBindings.evaluate()` pure function, 4 new uniforms (`noiseScale`, `emissivePulse`, `vertexJitter`, `glitchAmplitude`), `BlackFireSurface.metal` consumes them | ✅ |

Plus: 46 unit tests, GitHub Actions CI (Python 3.11 + 3.12, `ruff` + `black`), `tests/unit/` layout, `pyproject.toml` lint config.

---

## Phase 0 — Foundation **DONE**

The skeleton beneath the Cognitive OS work. Everything below assumes Phase 0 holds.

- Core daemon loop (`ares/daemon.py`) — driver for the PERCEIVE → THINK → ACT → REFLECT cycle.
- CLI (`ares/cli.py`) — `ares serve`, `ares mcp`, `ares doctor`, `ares goal`, `ares status`.
- FastAPI server + WebSocket (`ares/api.py`) — REST endpoints, live event stream.
- Metal shaders for RealityKit avatar (six switchable styles: blackFire, anime, hologram, blob, pixelVolume, constellation).
- Cognitive servers under `ares/skills/cognitive/`:
  - `perception_server.py` — input ingestion
  - `voice_server` / `vts_controller.py` — voice + VTube Studio bridge
  - `avatar_server.py` — avatar state publisher
- Hermes bridge stub (`ares/runtime/hermes_bridge.py`) — HTTP client.
- LLM routing (`ares/llm/router.py`, `cloud.py`, `local.py`) — Anthropic + LM Studio.
- 4-layer personality system (`ares/core/personality.py`) — HEXACO → SPECIAL → expression → domain.
- ZMQ bus (`ares/core/bus.py`) — 9 channels.

---

## Phase 1 — Stabilization **IN PROGRESS**

Current agent swarm working in parallel on four branches. Each branch fixes one load-bearing wire. All four merge to `main` independently when their PR clears.

| Branch | What it fixes |
|--------|---------------|
| `fix/hermes-bridge-startup` | Hermes bridge race on daemon boot — connection attempt before Hermes is listening |
| `fix/approval-checkpoint-loop` | Approval checkpoints don't release cleanly; tasks stall after user approves |
| `fix/memory-wiring` | `ares/core/memory.py` ↔ `ares/memory.py` ↔ new `ares/memory_store.py` triple-layer needs reconciliation — clarify which is the audit log vs. primary store, route writes through one entry point |
| `fix/tool-registry-bridge` | `ares/tools/registry.py` not surfaced to MCP server / LLM tool-call layer |

Exit criteria: `ares start` runs for 24 h without any of the four failure modes reappearing, and an end-to-end task (goal → plan → approval → execution → memory write) completes cleanly.

---

## Phase 1b — Pydantic v2 Upgrade **NEXT**

Before any new feature work, the type system gets standardized. Today's mix of dataclasses, untyped dicts, and ad-hoc validation is the single biggest source of regressions. Pydantic v2 is the chosen baseline. (`ares/models/cognitive.py` and the snapshot transport contract already demonstrate the pattern.)

| File | Migration target |
|------|------------------|
| `ares/daemon.py` | Replace ad-hoc config reads with a `BaseSettings` subclass — env vars, TOML, defaults all unified |
| `ares/tasks/executor.py` | Typed task models (`Task`, `TaskResult`, `Checkpoint`) — replace dict-shaped state |
| `ares/reasoning.py` | Adopt `pydantic-ai` for the tool-call loop — drops 100+ lines of hand-rolled retry / parse logic. Pattern aligns with [research findings on typed dependency injection](./RESEARCH_COMPETITIVE_2026.md). |
| `ares/core/memory.py` & `ares/memory.py` | Typed memory models (`EpisodicEntry`, `PreferenceFact`, `RetrospectiveNote`) — coordinated with the `fix/memory-wiring` reconciliation |

**Estimated effort: 7–11 days.** This is the cost of doing it now rather than after Phase 2 lands and the new code also has to migrate.

Exit criteria: `mypy --strict` passes on the four files above and all callers, and the LLM tool-call loop is provably driven by pydantic-ai (not the legacy hand-rolled parser).

---

## Phase 1c — Competitive Research Wins **PLANNED**

Patterns lifted from [`RESEARCH_COMPETITIVE_2026.md`](./RESEARCH_COMPETITIVE_2026.md) that are **not yet shipped** on main. Each item is small enough to be a single PR; ordering is by leverage, not strict dependency.

| # | Pattern | Source | Where it lands |
|---|---------|--------|----------------|
| 1 | **Five-signal memory scoring** — recency × frequency × relevance × importance × temporal_decay | MEMTIER paper, May 2026 | `ares/memory_store.py` recall function. Replaces current flat cosine top-k. |
| 2 | **Guardrail layers at phase boundaries** — Input/Output/Tool intercepts at PERCEIVE / THINK / ACT / REFLECT | OpenAI Agents SDK | `ares/core/cognitive.py` — pluggable check list per phase, exception-isolated. |
| 3 | **SPIRAL Planner/Simulator/Critic sub-agents inside THINK** | SPIRAL paper, Dec 2025 | Split `_think_phase` into three sub-routines, each emitting `ThoughtNode`s into the existing DAG. Mission Control already renders them. |
| 4 | **LLM dual-model routing** — fast/cheap for idle ticks, smart for reasoning | Inworld AI | `ares/llm/router.py` — gate on `loop.urgency` + `phase`. Idle reflexion uses local; THINK escalates to cloud. |
| 5 | **Emotion → prosody mapping before TTS** | Hume AI | New `ares/skills/cognitive/prosody.py` — map `thought.sentiment` to TTS markup before voice synth. |
| 6 | **Barge-in voice interruption** — detect speech during TTS, abort and switch to listening | Inworld AI | `vts_controller.py` mic state machine — VAD on while speaking, cancel TTS on detection. |
| 7 | **Proactive INITIATE phase** — ARES starts conversations from calendar / state / time triggers | Pi (Inflection AI) | New phase inserted before PERCEIVE in the loop; gated by an `initiate_policy` so it's silent by default. |
| 8 | **Character card → HEXACO import** — generate personality profile from Character.AI-style cards | Character.AI | `ares/core/personality.py` — `from_character_card(yaml_or_md)` classmethod. |

**Items deliberately skipped because they're already shipped** (from the research's priority-actions list): ThoughtDAG checkpointing (Phase 2 of Cognitive OS), idle reflexion (Phase 3), shader-cognition binding table (Phase 4).

Exit criteria for Phase 1c: each item is its own PR with tests, and at least #1, #2, #4 land before Phase 2.

---

## Phase 2 — Layer 1 Ambient Overlay **PLANNED**

Builds the always-on desktop ember. The transport contract (`CognitiveSnapshot`) and the binding layer (`CognitiveBindings.evaluate`) are already shipped; this phase wires them to a *new surface*.

Work items:

1. **Desktop ember Metal app** — always-on-top, transparent, click-through, mouse passthrough enabled. ~150–200 px, drifts slowly.
2. **Hot-key overlay** — global shortcut to summon / dismiss; preserves ARES state.
3. **Wire the four shipped uniforms** (`noiseScale`, `emissivePulse`, `vertexJitter`, `glitchAmplitude`) into the ember shader. No new bindings needed — reuse Phase 4.
4. **Idle presence** — when no activity, the ember should breathe. Drive from `loop.budget_remaining` and idle-reflexion ticks; persist `presence_snapshot` to `~/.ares/presence/` so restart preserves visible state.

Estimated duration with the agent swarm: **3–4 weeks**.

Exit criteria: a casual observer can watch the ember on the desktop and tell, without any other UI, whether ARES is idle, thinking, or confident.

---

## Phase 3 — 3DGS Companion (Layer 2 v2) **PLANNED**

The next-generation Companion-scale embodiment. v1 is already shipped (RealityKit + Custom Material with the 4 cognitive uniforms). v2 replaces the polygon mesh with a Gaussian splat field.

Work items:

1. **Adopt SplattingAvatar / 3DGS-Avatar** (CVPR 2024) as the base avatar pipeline. Train an initial splat field from reference imagery or a synthesized base identity.
2. **SMPL-X skeleton deformation** — drive the splat field's base pose with a standard parametric human model so we get gaze, head turn, gesture for free.
3. **Snapshot → splat-field bridge** — extend `CognitiveBindings` with splat-specific outputs (density, spread, color jitter). `evaluate()` stays the single entry point; the new fields are additive.
4. **Layer 2 mode integration** — splat companion appears when conversation goes past N exchanges, when the user explicitly summons it, or when a high-confidence response wants embodiment.

Estimated duration: **6–8 weeks** (heaviest single phase — render pipeline rewrite + new skeleton solver).

Exit criteria: a sustained conversation drives a visibly responsive splat avatar whose form and posture change with cognitive state, not with scripted timeline animations.

---

## Phase 4 — Mission Control v2 + Concrete VectorStore **PLANNED**

Mission Control v1 is shipped (force-directed DAG panel). v2 expands the operator surface; alongside it, the swappable `VectorStore` Protocol gets a real concrete implementation.

- **DAG replay scrubber** — `MissionControlPanel` already renders the live DAG; add a time-slider that loads `kind="reasoning_trace"` episodics and replays them. Persistence layer is already shipped.
- **Concrete `VectorStore`** — ship `SqliteVssStore` (or `LanceDbStore` / `ChromaDbStore`). Protocol exists in `ares/memory_store.py`; default stays `InMemoryVectorStore` for tests.
- **Operator tabs** — populate `.models`, `.skills`, `.cron`, `.analytics` in `ARES-Face/Views/SidebarView`. Sidebar is mounted; pages are stubbed. Wire `/api/cognitive/status`, `/api/memory/*`, `/api/idle/last_report` into the analytics tab.
- **Semantic knowledge graph view** — render the SQLite `facts` triple store as a navigable graph (subject → predicate → object), with provenance hover.
- **Operator telemetry** — token usage by route (cloud vs local), tool-call success rate, approval latency, memory hit rate (driven by the five-signal scoring from Phase 1c).

Estimated duration: **~4 weeks**, partially in parallel with Phase 3.

Exit criteria: the user can answer "what has ARES been doing today, and what did it remember?" without reading any logs.

---

## Phase 5 — Layer 3 Full Immersion **PLANNED**

The room-scale layer. ARES becomes a place you can step into.

- **RealityKit procedural environment** — generated from current cognitive state and memory contents.
- **Memory space traversal** — past sessions become navigable rooms; recent decisions are nearby, distant memories fade into a horizon.
- **Gravitational field particle system** — current tasks exert pull on attention particles; the user can see where focus is concentrated.

Estimated duration: **12 weeks** total including Phase 4 overlap.

Exit criteria: on Vision Pro, the user can stand inside ARES's cognition rather than look at it through a window.

---

## Sibling work not in any phase

The Hermes bridge wiring (`ares/runtime/hermes_bridge.py` → real Hermes invocation) is owned by a separate PR. The `memory_recall` field in `CognitiveSnapshot` is the contract that PR consumes. Don't duplicate.

---

## Agent Swarm Strategy

ARES is built by a swarm, not a single agent. The strategy that makes this work:

- **Parallel branches** — one focused branch per problem, named `fix/<thing>` or `feat/<thing>`. Never two agents on the same branch.
- **Merge when done** — short-lived branches, fast PR cycles, no long-running feature branches that diverge from `main`.
- **GitHub as the shared layer** — Claude (Cowork/Dispatch), Hermes (local MCP), and any future agent all read and write the same GitHub repo. The repo is the truth.
- **NAS `AI_COMMS/` for async handoffs** — when an agent needs to leave a note for another agent that may not be running simultaneously, it drops a file in `AI_COMMS/inbox/`. The receiving agent processes its inbox at startup.
- **Plans → docs → code** — humans and agents both work off the same `ares/reference/docs/` tree. If the docs are wrong, fix the docs first.
- **Forward-compatible contracts** — when extending `CognitiveSnapshot` or any other shared model, add fields with defaults. Bump `SCHEMA_VERSION` only on breaking change.
- **Protocols before implementations** — define the Protocol, ship a zero-dep default, add concretes later. The `VectorStore` + `Embedder` pattern in `memory_store.py` is the template.

---

## Realistic Timeline With the Swarm

| Phase | Duration | Cumulative |
|-------|----------|------------|
| Phase 1 stabilization | this week | now + 1 wk |
| Phase 1b Pydantic v2 | 1–2 weeks | now + 3 wk |
| Phase 1c competitive research wins | 2–3 weeks (parallel-friendly) | now + 5 wk |
| Phase 2 Layer 1 ambient overlay | 3–4 weeks | now + 9 wk |
| Phase 3 3DGS companion (v2 Layer 2) | 6–8 weeks | now + 17 wk |
| Phase 4 Mission Control v2 + concrete VectorStore | overlaps Phase 3 | — |
| Phase 5 Layer 3 immersion | 12 weeks total | — |

These are *with the swarm running*. Single-developer estimates would be 3–4× longer.
