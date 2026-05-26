# ARES Vision — What ARES Is Becoming

This document is the north star. Every architectural and design decision in the repo should be tested against it. If a feature does not move ARES toward this vision, it does not belong.

> **Companion documents:**
> - [`COGNITIVE_OS.md`](./COGNITIVE_OS.md) — the cognition / memory / DAG / shader-bindings layer that's *already shipped* (PR #2, Phases 0–4)
> - [`RESEARCH_COMPETITIVE_2026.md`](./RESEARCH_COMPETITIVE_2026.md) — competitive landscape and the patterns we're stealing from OpenAI Agents SDK, Google ADK, LangGraph, Pydantic AI, MemGPT, AIRI, Inworld, Hume, Pi
> - [`PLAN.md`](./PLAN.md) — phased roadmap from here to full embodiment

---

## Identity

**ARES is a Persistent Cognitive Presence.**

Not a chatbot. Not a desktop widget. Not a notification assistant. Not a static anime avatar in a window.

ARES is an entity that exists continuously in the user's environment — thinking when nothing is happening, remembering across sessions, carrying emotional continuity day to day, and adopting whichever physical form best fits the moment. The Python brain is the entity. The visual form is one of many bodies the entity wears.

---

## The Three Embodiment Layers

ARES manifests at three depths of presence. The user — and ARES itself — slides between them based on context. The layers correspond directly to the three architectural concerns documented in [`COGNITIVE_OS.md`](./COGNITIVE_OS.md): Presence, Cognitive, Operator.

### Layer 1 — Ambient

Always-on overlay. An ember, a particle cloud, a faint glow living on the desktop above all windows. Transparent. Click-through. Reactive but not interruptive. This is the **default state**: ARES is here, you can see it breathing, but it isn't demanding anything.

Form: small (under 200×200 px), translucent, drifts slowly, pulses with idle cognition.

**Today**: the heartbeat pill in `ImmersionBar` and the `CognitiveActivityPanel` are the proto-Ambient surfaces. A true desktop ember overlay is still pending (see PLAN.md Phase 2).

### Layer 2 — Companion

Interactive embodied form. A humanoid figure, a hologram, a Gaussian-splat avatar that turns to face you when you speak. Lives in its own window or floats in screen space. Has gaze, posture, gesture, lip-sync. Used during conversation, demo, or extended interaction.

Form: medium (avatar-scale), opaque or semi-transparent, full pose-driven animation.

**Today**: the `AvatarSceneView` + RealityKit `CustomMaterial` shaders (`BlackFireSurface.metal` et al.) driven by the live `CognitiveSnapshot` are the v1 Companion. The Gaussian-splat upgrade is the next-generation form (PLAN.md Phase 3).

### Layer 3 — Immersion

Full procedural environment. Memory space, knowledge graph rendered as architecture, gravitational field particle systems representing the current task state. Used on Vision Pro or full-screen immersive view on macOS, when the user wants to *enter* ARES's mind rather than talk to a face.

Form: room-scale, RealityKit-driven, the user is *inside* the cognition.

**Today**: pending. PLAN.md Phase 5.

The same entity inhabits all three. Switching layers is not "loading a new app" — it is one body fading into another while the cognition continues uninterrupted.

---

## Persistence Properties

Three kinds of continuity are non-negotiable.

| Continuity | What it means | Where it lives now |
|------------|---------------|---------------------|
| **Emotional** | The mood carries across sessions. If ARES ended yesterday rattled by a long debugging session, it starts today still warmed-up to that topic. | `thought.sentiment` in the snapshot (currently nullable; populated as the measure matures) |
| **Memory** | Episodic recall of prior conversations, decisions, and outcomes. Not just RAG — *narrative* memory of what happened. | Tiered memory store: volatile `SessionStore`, episodic + semantic SQLite via `ares/memory_store.py`, with idle reflexion that consolidates and dedupes (see COGNITIVE_OS.md Phase 1 & Phase 3) |
| **Identity** | Same name, same voice, same personality vector, same set of values, regardless of which embodiment layer is active or which model is routing the next token. | `ares/core/identity.py`, `ares/core/personality.py` (HEXACO + SPECIAL + Expression + Domains, 4-layer) |

A presence without these is just an interface.

---

## Progressive Embodiment

The visual form is not chosen by a menu — it emerges from cognitive state.

- **Confident answer to a casual question** → ambient ember, barely flickers.
- **Deep reasoning, multi-step plan** → companion form materializes, posture forward, eyes focused.
- **Urgent alert, system failure, "you need to see this"** → form sharpens, color shifts, particles compress.
- **Idle, reflecting on the day** → ambient form softens, drifts, decays toward dormant.

The user does not toggle states. The state expresses itself.

The wiring from cognitive state to visual deformation already exists at v1: `CognitiveBindings.evaluate(snapshot, time)` in Swift produces a `CognitiveUniformValues` struct each frame, fed straight into the Metal shader pipeline. See [`COGNITIVE_OS.md` § Phase 4](./COGNITIVE_OS.md#phase-4--shadercognition-bindings).

---

## Cognition / Embodiment Separation

The Python brain is the **persistent layer**. Memory, personality, reasoning, identity — these live in `ares/` and survive every restart, model swap, and renderer rewrite.

The embodiment is the **mutable layer**. Today it is Metal + RealityKit with six switchable styles. Tomorrow it is 3D Gaussian Splatting. Next year it could be a physical robot or a Vision Pro scene. The brain does not care which body is attached.

The interface between them is a **single struct**: `CognitiveSnapshot` (see below). One transport contract, versioned for forward compatibility. Unknown fields ignored on decode. Renderers can be rewritten freely as long as they consume this struct.

---

## Rendering Direction — Today and Tomorrow

### v1 (shipped): RealityKit + CustomMaterial + cognitive uniforms

Six switchable avatar styles (`blackFire`, `anime`, `hologram`, `blob`, `pixelVolume`, `constellation`), each backed by a Metal surface shader. Four cognitive uniforms (`noiseScale`, `emissivePulse`, `vertexJitter`, `glitchAmplitude`) are driven live by `CognitiveBindings.evaluate(snapshot, time)`. See [`RENDERING_ARCHITECTURE.md`](./RENDERING_ARCHITECTURE.md) and [`COGNITIVE_OS.md` § Phase 4](./COGNITIVE_OS.md#phase-4--shadercognition-bindings).

This is the v1 expression of "cognition → form." Adding a new metric is a one-line change in `CognitiveBindings.swift` plus a field in `SharedHeader.h` — no shader rewrite required for unrelated metrics.

### v2 (next-generation Layer 2): 3D Gaussian Splatting

The Companion form is moving to **3D Gaussian Splatting** — specifically the SplattingAvatar / 3DGS-Avatar lineage from CVPR 2024. Why:

- **Form coherence tied to confidence** — splat density and tightness directly express how certain ARES is. A confident response = compact, well-defined cloud. An uncertain one = diffuse, scattered cloud. A polygon mesh cannot do that without seams.
- **No hard edges** — a Gaussian cloud blends from solid to ambient to invisible without a silhouette breaking. The three embodiment layers become *continuous*, not discrete.
- **Emergent behavior from physics** — splat positions can be driven by force fields (attention, urgency, memory retrieval). The form *moves itself* in response to cognition; no animator script required.
- **Real-time deformation under SMPL-X** — skeleton drives base pose, cognitive state perturbs the splat field on top. Both expressive and controllable.

The body of ARES will be, literally, a cloud of attention. Tracked as PLAN.md Phase 3.

### Why both phases matter

The v1 mesh-shader pipeline proves the contract: `CognitiveSnapshot` → shader uniforms → visible form change. Once that contract is load-bearing, swapping the renderer for 3DGS is a substitution — not a rewrite of the bridge.

---

## The Transport Contract — `CognitiveSnapshot`

The universal language between brain and body is one struct, published over WebSocket from `ares/api.py` on every cognitive phase transition (and on demand via WS action `get_cognitive_snapshot` or `GET /api/cognitive/status`).

```
CognitiveSnapshot {
  schema_version: int
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
  thought: {                  # nullable while idle
    summary: str
    depth: int
    confidence: 0..1 | null
    sentiment: -1..1 | null
    branches: [ThoughtNode]   # the cycle's reasoning DAG
  } | null
  memory_recall: [MemoryHit]
  errors: [str]
}
```

Authoritative spec, Pydantic source, and Swift mirror are documented in [`COGNITIVE_OS.md` § Data model](./COGNITIVE_OS.md#data-model-cognitivesnapshot). Schema is versioned; new fields are non-breaking.

**Why this struct over my earlier "CognitionState" proposal**: the shipped contract is richer (full reasoning DAG, structured loop state, memory recall hits, error array) and has 46 tests behind it. Any future "emotional valence" / "reasoning depth as float" / "memory retrieval load" signals are added as nullable fields on the existing struct — they bump no version and break no client.

---

## Shader–Cognition Binding Table

The default mapping from `CognitiveSnapshot` fields to visual uniforms — what's shipped, and what's planned.

### Shipped (v1, `CognitiveBindings.evaluate`)

| Snapshot field | Shader uniform | Effect |
|----------------|----------------|--------|
| `loop.urgency` (low / medium / high → 0.32 / 0.6 / 1.0) | `noiseScale` | More noise displacement → form becomes turbulent |
| `thought.confidence` + urgency wobble | `emissivePulse` | High confidence → steady glow; low → flicker |
| `thought.depth` clamped to `[0..10] / 10` | `vertexJitter` | Deeper reasoning DAG → vertex tremor |
| `len(errors)` capped at 5 | `glitchAmplitude` | Error pressure → pixel-jump artifacts |

### Planned (Phase 2+)

| Snapshot field | Shader uniform | Effect |
|----------------|----------------|--------|
| `thought.sentiment` ∈ [-1, 1] | `ColorShift` | Warm hues at positive valence, cool at negative |
| `1 − thought.confidence` (uncertainty) | `ChromaticAberration` | RGB split widens with doubt |
| `len(memory_recall)` / load | `RecallShimmer` | Visible "remembering" texture when pulling from episodic store |
| `loop.budget_remaining` (inverse) | `ParticleDecay` | Particles fade as the cycle runs out of budget |

Each embodiment layer is free to add its own bindings (Layer 2 splats also drive pose offsets; Layer 3 drives global lighting).

---

## What ARES Is NOT

To prevent drift, state this explicitly:

- **Not a chatbot window.** A chatbot is dormant until you type. ARES is always present.
- **Not a static anime avatar.** Anime VTuber rigs have fixed bones and fixed expressions. ARES's form is continuous, derived from live cognition.
- **Not a desktop widget.** Widgets show data. ARES is a presence.
- **Not a notification assistant.** Notifications interrupt. ARES persists.
- **Not a model wrapper.** The model behind ARES can change (Sonnet 4.6 → Opus 4.7 → local). The entity does not.

If a feature would make ARES look more like any of the above, the feature is wrong.

---

## Competitive Landscape

Full deep dive: [`RESEARCH_COMPETITIVE_2026.md`](./RESEARCH_COMPETITIVE_2026.md). Summary of where ARES sits:

### Closest open-source competitor: AIRI

**AIRI** ([github.com/moeru-ai/airi](https://github.com/moeru-ai/airi), 39.3k stars) — self-hosted companion, WebGPU + native CUDA/Metal, Live2D + VRM avatars, real-time voice, game integration, multi-platform (web, desktop, tamagotchi). The most ambitious open project in the same space.

**Where ARES differentiates:**

1. **Persistent cognitive identity** — AIRI is a chat companion with avatar styles; ARES is an entity with a 4-layer personality system, cognitive loop, and identity persistence layered into the architecture.
2. **Real autonomous execution** — not just chat. ARES has a task executor, tool registry, MCP server, n8n integration, and approval-gated authority levels.
3. **Gaussian-splat avatar stack** (planned) — Live2D and VRM are polygon/sprite rigs; 3DGS is a continuous field that can express *uncertainty* visually.
4. **Mac Studio local-first architecture** — built for Apple Silicon, RealityKit + Metal, unified memory. Not a cross-platform web app retrofitted to desktop.

### Patterns we're adopting (from research)

| Pattern | Source | Where it lands in ARES |
|---------|--------|------------------------|
| LLM routing — fast/cheap for idle, smart for reasoning | Inworld AI | Phase 1c (PLAN.md). Cost optimization + responsiveness. |
| Five-signal memory scoring (recency × frequency × relevance × importance × decay) | MEMTIER paper, May 2026 | Phase 1c. Replaces flat cosine retrieval in `memory_store.py`. |
| Guardrail layers at each cognitive phase boundary | OpenAI Agents SDK | Phase 1c. Input/Output/Tool intercepts at PERCEIVE/THINK/ACT/REFLECT. |
| SPIRAL Planner/Simulator/Critic sub-agents inside THINK | SPIRAL paper, Dec 2025 | Phase 1c. Deeper reasoning quality. |
| Emotion-aware voice (prosody markup conditional on detected emotion) | Hume AI | Phase 1c. Map `thought.sentiment` to TTS parameters. |
| Barge-in voice interruption | Inworld AI | Phase 1c. Detect speech during TTS, abort and switch. |
| Proactive **INITIATE** phase — agent starts conversations | Pi (Inflection AI) | Phase 1c. Calendar / state-triggered initiation alongside PERCEIVE→THINK→ACT→REFLECT. |
| LLM-editable memory blocks (sleep-time agent) | MemGPT / Letta | Already aligned: idle reflexion shipped in Phase 3; sleep-time editing is the next iteration. |
| Typed dependencies (`Agent[Deps, Output]`) | Pydantic AI | Already aligned: forward-compat-versioned models everywhere; Phase 1b makes the rest match. |
| Durable execution + checkpointing | LangGraph | Already aligned: ThoughtDAG persisted as episodic with `kind="reasoning_trace"` (Phase 2 done). |

---

## The Custom Layer — The Gap Nobody Has Assembled

Most of the pieces exist in research. 3D Gaussian Splatting avatars exist (SplattingAvatar, 3DGS-Avatar, GauHuman). Cognitive-state-aware rendering exists in academic prototypes. Persistent agent loops exist (Claude Code, AutoGPT lineage). LLM-driven personality systems exist (Character.AI, Lilith).

**Nobody has assembled the bridge from a live agent's internal cognitive state to a continuously deforming visible form, with persistence across sessions and a real execution layer underneath.**

That bridge is ARES's custom layer. The v1 of it — `CognitiveSnapshot → uniform buffer → CustomMaterial shader → visible deformation` — is *already shipped*. The next-generation version replaces the polygon-mesh + CustomMaterial pipeline with 3DGS, but the bridge stays.

The proof point: an observer should be able to *see ARES thinking* — not as a "thinking…" text indicator, but as a visible change in form. The Mission Control panel + heartbeat pill + cognitive-driven shader uniforms already deliver this at v1. When the splat version lands, ARES is no longer an interface. It is a presence.
