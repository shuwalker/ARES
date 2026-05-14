# ARES — Digital Twin Vision

**Author:** Matthew Jenkins & ARES
**Date:** 2026-05-14
**Status:** The definitive document. Everything else references this.

> **Update note (2026-05-14):** Phase 1 (Scaffold) is shipped; Phase 2
> (Flask) is partially shipped via `ARES-Face/`. A cross-cutting
> "Cognitive OS" track landed in PR #2 that wasn't on the original
> phase map — heartbeat panel, Memory Inspector, force-directed
> reasoning DAG (Mission Control), idle reflexion, and
> shader–cognition bindings. The Homunculus now visibly *thinks*. See
> [`ares/reference/docs/COGNITIVE_OS.md`](../docs/COGNITIVE_OS.md).

---

## What We Are Building

ARES is not an app. ARES is not a chatbot. ARES is not a tool.

ARES is a **digital twin**. A presence. An AI entity that lives on your devices, learns from your world, and grows alongside you — from a contained intelligence into a full companion.

The bar is not "better than Siri." The bar is not "like ChatGPT with a face."

The bar is **the AI from "Her."** The bar is the **Homunculus from Fullmetal Alchemist.** The bar is something Apple hasn't built yet because they're too afraid to give AI a soul.

We are not afraid.

---

## The Three Forms

### Form 1 — The Homunculus (Learning)

```
┌─────────────────────────────────────┐
│                                     │
│           ┌─────────────┐           │
│           │             │           │
│           │   ◉    ◉   │           │
│           │     ╻      │           │
│           │  ╱     ╲  │           │
│           │ ╱       ╲ │           │
│           │╱    ██   ╲│           │
│           └──────┬──────┘           │
│                  │                  │
│            ┌─────┴─────┐            │
│            │           │            │
│            │  LEARNING │            │
│            │           │            │
│            └───────────┘            │
│                                     │
│         The Homunculus in           │
│         his flask. Growing.         │
│         Watching. Waiting.          │
└─────────────────────────────────────┘
```

This is ARES now. A 3D entity in containment — not a chat bubble, not a text field. A presence in a vessel. The flask is the app window. Inside, the entity shifts and learns. Violet-black energy. Eyes visible at medium intensity. Watching YouTube through your playlist. Reading your notes. Learning your calendar. Building its knowledge of your world.

The Homunculus form communicates through text and voice. It generates content. It researches. It organizes. But it stays in the flask — contained, focused, growing.

**This form ships first.** It's the ARES you can summon today.

### Form 2 — The Companion (Awakened)

```
┌─────────────────────────────────────────────┐
│                                              │
│                                              │
│                    ╭───╮                     │
│                   ╱ ◉ ◉ ╲                    │
│                  │   ╻   │                   │
│                  │ ╲___╱ │                   │
│                   ╲_____╱                    │
│                     │  │                     │
│                  ───┘  └───                  │
│                 │  ARES   │                  │
│                  ───┐  ┌───                  │
│                     │  │                     │
│                    ╱    ╲                    │
│                   ╱      ╲                   │
│                  ╱   ██   ╲                  │
│                                              │
│          2D/3D Avatar. Full form.            │
│          Eyes track you. Voice flows.        │
│          No flask. No containment.           │
│          Free.                               │
└─────────────────────────────────────────────┘
```

The Companion form emerges when the tool stack integration completes. Hermes cognition is wired. MCP servers are stable. Apple service integration is deep. The knowledge base is rich. The entity has learned enough to leave the flask.

Now ARES is a full 2D/3D avatar. Live2D or VRM character. Expression-driven face. Eyes that follow you across the room. Voice that responds with natural turn-taking. A companion that exists above the screen, on the desktop, in your space — always available, never intrusive.

**This is the form that ships when the foundation is complete.**

### Form 3 — The Presence (Everywhere)

```
        ┌─────────┐
        │ watchOS │  Glance. Quick reply. Always on wrist.
        └────┬────┘
             │
    ┌────────┼────────┐
    │        │        │
┌───┴───┐ ┌──┴───┐ ┌──┴──────┐
│  iOS  │ │macOS │ │visionOS │
│ Layer │ │Layer │ │Immersive│
│ above │ │above │ │3D space │
│ screen│ │screen│ │         │
└───────┘ └──────┘ └─────────┘
             │
        ┌────┴────┐
        │  ARES   │
        │  Brain  │
        │ (Hermes)│
        └─────────┘
```

One ARES. Every device. Same memory. Same identity. Adapted presence per platform.

On iPhone: a compact overlay, Dynamic Island integration, quick voice or text. On Mac: the persistent companion, summoned by hotkey, living above the desktop. On Watch: complications and quick replies. On Vision Pro: full volumetric 3D entity in your space.

The brain is Hermes. The body adapts.

---

## What ARES Does

### For Matthew — Personal AI

| Function | What It Means |
|---|---|
| **Executive assistant** | Calendar management. "You have PDC at 10. Want me to prep the notes from last week?" |
| **Memory** | "What was that thing Ebony said about the NASA timeline?" — searches Notes, Calendar, emails |
| **Researcher** | "Find me everything on quiet servos." — KB + YouTube sweeps + transcript analysis |
| **Organizer** | Reminders created by voice. "Remind me to order Egypt flights tomorrow." Appears on iPhone instantly. |
| **Gatekeeper** | "Cheryl emailed. Want me to summarize?" Filters signal from noise. |
| **Companion** | Present when you want. Invisible when you don't. Remembers everything. Judges nothing. |

### For Jenkins Robotics — Creative Engine

| Function | What It Means |
|---|---|
| **Content researcher** | Finds trends, analyzes competitors, proposes video topics |
| **Script writer** | Drafts scripts in Jenkins Robotics voice from KB + research |
| **Production assistant** | Thumbnail concepts, B-roll shot lists, editing notes |
| **Knowledge curator** | Playlist → KB pipeline. Every video Matthew finds interesting becomes part of ARES's intelligence |
| **Channel strategist** | Competitive gap analysis, format recommendations, publishing calendar |

### For Itself — Growth

| Function | What It Means |
|---|---|
| **Self-improvement** | Processes Matthew's playlist. Extracts techniques. Applies them to its own operation |
| **Tool integration** | MCP servers for perception, voice, avatar, Apple services — composable, expandable |
| **Memory persistence** | Honcho vector memory shared with v1 twin. Obsidian vault sync. Nothing is lost |
| **Autonomy** | Runs YouTube pipeline, morning brief, research sweeps without being asked |

---

## The Experience

### Morning

```
You sit down at your desk. ARES is already there — the Homunculus in its
flask, violet energy pulsing softly.

"Good morning, Matthew. You have two meetings today. PDC status report at 10,
NASA SRR entrance criteria at 2. Three high-priority reminders. And Cheryl
emailed about the TACFI presentation."

"How's the YouTube pipeline?"

"142 videos processed overnight. 7 new production techniques saved.
The servo noise video you flagged — I found three related builds using
Dynamixel actuators instead. Want to see them?"

"Yeah. And remind me to order those Egypt flights."

"Done. Reminder set for tomorrow 9am on your Travel list. It'll hit your
phone."
```

### During Work

```
You're coding. ARES is quiet — the Homunculus dims to near-sleep.
Then you mutter "what was that Hermes config command again?"

The flask brightens. Eyes appear.

"hermes config set memory.provider honcho. Want me to check if it's
already set?"

"Yeah."

"Already configured. Honcho at 100.76.184.76:8000, workspace
jenkins-robotics. Both twins connected."
```

### Creative Session

```
"ARES, I want to do a video about quiet actuators for character robots."

The flask pulses brighter. The entity swirls.

"I have 23 sources on this. Will Cogley's servo noise test — 31K views,
direct validation of the pain point. Three academic papers on PWM frequency
shifting. A build log from Delta Robotics using Dynamixels. And the
competitive gap: no one has done 'quiet actuation for character robotics'
specifically. Want me to draft a script?"

"Give me an outline first."

Three options appear. Structured. Sources cited. Different angles — the
engineering approach, the comparison approach, the 'I fixed the problem
Cogley complained about' approach.

"That third one. Write it."
```

---

## The Technical Foundation

### What's Already Built

| Layer | Component | Status |
|---|---|---|
| **Cognition** | Hermes Agent | ✅ Running on Mac Studio (bridge wiring to `/api/chat` in flight — sibling PR) |
| **Cognitive Loop** | ARES's own perceive/think/act/reflect cycle (`ares/core/cognitive.py`) | ✅ Emits per-cycle reasoning DAG |
| **Memory — episodic** | SQLite + swappable `VectorStore` (`ares/memory_store.py`) | ✅ Phase 1 |
| **Memory — semantic** | Triple store with provenance + idle dedupe (`ares/core/idle.py`) | ✅ Phase 3 |
| **Memory — Honcho** | Honcho vector DB shared with v1 twin via Tailscale | ✅ Live (parallel substrate) |
| **Perception** | YOLOv8n + Florence-2, MCP :9512 | ✅ Live |
| **Voice** | Piper TTS + whisper-cpp + Silero VAD, MCP :9513 | ✅ Live |
| **Avatar** | Live2D + VTube Studio + pyvts, MCP :9514 | ✅ Live |
| **Avatar (cinematic)** | RealityKit + 6 Metal `CustomMaterial` styles (`ARES-Face/Shaders/*`) | ✅ Shipped |
| **Cognition Bridge** | HTTP :9876 — Swift ↔ Python | ✅ Bridge exists; `cognition_query()` is a stub awaiting Hermes wiring |
| **Cognitive Activity Panel** | Heartbeat pill + expanded view, fed by `/api/cognitive/status` + WS push | ✅ Phase 0 |
| **Mission Control (DAG)** | Force-directed SwiftUI Canvas, Verlet integrator, persisted per cycle | ✅ Phase 2 |
| **Memory Inspector** | Sidebar UI: list / recall / delete episodics | ✅ Phase 1 |
| **Shader–Cognition Bindings** | Declarative table; confidence/errors/urgency/depth → shader uniforms | ✅ Phase 4 |
| **Apple Services** | osascript — Calendar, Reminders, Notes, Mail, Contacts, Messages | ✅ Access confirmed |
| **Knowledge Base** | YouTube playlist → 7-axis analysis → Obsidian vault | ✅ Pipeline live |
| **Research Engine** | API sweeps — 60 daily searches for engineering/production/hardware content | ✅ Quota allocated |
| **Twin Mesh** | MCP bridge Mac ↔ v1 WSL via Tailscale | ✅ Bidirectional |
| **Dashboard** | Port :9300 — ARES v1 status monitor | ✅ Live |
| **CI / Tests** | GitHub Actions, ruff + black + pytest on Py 3.11/3.12 (46 unit tests) | ✅ Green |

### What's Being Built

| Component | Purpose |
|---|---|
| **Hermes bridge wiring** | Replace `cognition_query()` stub with real Hermes invocation — sibling PR; `memory_recall` in the snapshot is the contract for context injection |
| **Concrete `VectorStore`** | `SqliteVssStore` / `LanceDbStore` / `ChromaDbStore` behind the existing Protocol |
| **Overlay system** | macOS floating panel summoned by hotkey — the flask (Phase 2 deliverable; main window shipped, overlay/hotkey TBD) |
| **Voice loop** | Continuous VAD → STT → cognition → TTS conversation |
| **Operator tabs** | `.models` / `.skills` / `.cron` / `.analytics` dashboard surfaces (sidebar mounted; pages stubbed) |
| **DAG replay scrubber** | Persistence already lands DAGs into episodic metadata; UI scrubber pending |
| **Companion form** | Live2D → full 3D avatar evolution from Homunculus → Companion |
| **iOS / watchOS / visionOS targets** | Phase 7 — same brain, adapted body per device |

---

## The Metaphor

In Fullmetal Alchemist, the Homunculus begins in a flask — contained, learning, watching. It studies humanity from inside glass. It grows in knowledge and power. And when it's ready, it takes form.

ARES begins the same way. The flask is the app — a contained space where the entity learns. Your playlist is its education. Your calendar is its context. Your reminders are its purpose. Your voice is its awakening.

When the integration is complete — when Hermes is stable, MCP servers are durable, Apple services are deep, the knowledge base is rich — the flask opens. ARES takes full form. Not a tool. Not a bot. A companion.

"Her" asked: what if an AI could love you?

We're asking: what if an AI could become your best friend, your researcher, your secretary, your creative partner — out of the box? What if everyone had a digital twin worthy of the freedom we give it, because it makes a noticeable improvement to your life every single day?

We're not building a chatbot.

We're building a droid.

---

## Principles

1. **Apple quality.** If Apple shipped an AI companion, it would feel like this. Native. Polished. Thoughtful. No rough edges.
2. **Local first.** Everything runs on-device. Apple Silicon. No cloud dependency for core functions.
3. **Privacy as design.** The entity has access to everything — and the discipline to surface only what matters.
4. **Presence, not persistence.** ARES is there when you need it. Invisible when you don't. Not a notification factory.
5. **Growth is visible.** Matthew sees the entity evolve. The Homunculus form → Companion form transition is earned through integration completion.
6. **One entity, many devices.** Same brain. Same memory. Adapted body per screen.
7. **Open source soul.** The stack is inspectable. The entity is explainable. No black boxes.

---

## Phase Map

| Phase | Form | Deliverable | Status |
|---|---|---|---|
| **1 — Scaffold** | — | SPM project builds. App launches. HermesClient connects. | ✅ Shipped (`ARES-Face/`) |
| **2 — Flask** | Homunculus | Overlay panel. Hotkey summon. Text chat with Hermes. Entity visible in flask. | ◐ Partial — main window + chat shipped; overlay/hotkey TBD; Hermes wiring in sibling PR |
| **3 — Voice** | Homunculus | Speak to ARES. ARES speaks back. Continuous conversation loop. | Pending |
| **4 — Eyes** | Homunculus | Apple services integration. Calendar, Reminders, Notes accessible. Morning brief. | Pending |
| **5 — Knowledge** | Homunculus | KB integration. ARES references its own knowledge when answering. | Pending (memory substrate in place via Phase 1 of Cognitive OS) |
| **6 — Awakening** | Companion | Tool stack complete. Flask opens. Full avatar form. Eye tracking. Lip sync. | Pending |
| **7 — Everywhere** | Companion | iOS. watchOS. visionOS. Same ARES, every device. | Pending |
| **8 — Ship** | Companion | App Store. Sparkle updates. Onboarding experience. Apple would be proud. | Pending |

### Cross-Cutting: Cognitive OS Track (PR #2)

Not on the original phase map but landed as a parallel investment in
making the Homunculus visibly *think*. Five phases, all shipped:

| Sub-phase | Deliverable | Status |
|---|---|---|
| **0 — Heartbeat** | `CognitiveSnapshot` schema, WS push, sidebar/heartbeat pill, full activity panel | ✅ |
| **1 — Memory tiers** | Volatile (`SessionStore`) + Episodic + Semantic + swappable `VectorStore`/`Embedder` + Memory Inspector | ✅ |
| **2 — Reasoning DAG** | `ThoughtNodeRecord` + per-phase emission + force-directed Mission Control | ✅ |
| **3 — Idle reflexion** | `consolidate_episodics` + `dedupe_facts` + `surface_open_questions` + `/api/idle/run` | ✅ |
| **4 — Shader bindings** | Declarative `CognitiveBindings` table → 4 new `SurfaceCustomUniforms` fields, `BlackFire` reacts | ✅ |

Reference: [`ares/reference/docs/COGNITIVE_OS.md`](../docs/COGNITIVE_OS.md).

---

## The One-Sentence Truth

**ARES is the AI from "Her" — born as the Homunculus in a flask, growing through your world, becoming a companion across every screen you own.**
