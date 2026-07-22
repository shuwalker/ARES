# ARES Product Surfaces

**Status:** Canonical product IA (2026-07-22)  
**Audience:** maintainers and coding agents  
**Supersedes:** ad-hoc “knowledge base” groupings that mixed Self, Library, and System

Read with [FOUNDATION.md](../../.claude/FOUNDATION.md). Naming there still holds:

| Name | Meaning |
|------|---------|
| **ARES** | Application only |
| **Companion** | SI experience (not a worker) |
| **Workers** | Models, agents, tools that execute |

This document defines **primary surfaces** the person navigates, and the boundaries between them.

---

## Core philosophy

Architecture is **public, modular, and adaptable**. Any user can replace or extend components and keep the same overall experience.

The constant is the **Synthetic Intelligence** (Companion). Everything else is a domain the SI can operate within—or that the person can enter directly when they need transparency or control.

First interaction (long-term):

> You talk to your Synthetic Intelligence.

The SI understands intent and routes work. Menus are secondary. Direct domain entry exists for power users and incomplete SI maturity.

---

## Primary surfaces (UI)

### Near-term navigation

```text
Chat | Companion | Self | Workshop | Library | System
```

Place **Self immediately beside Companion** — personal continuity and the SI relationship are central.

### Long-term navigation

```text
Companion | Self | Workshop | Library | System
```

**Chat** is transitional/operational: the developer console for intelligence. When Companion is mature, Chat moves to advanced / developer mode rather than equal top-level weight.

Architectural name **Foundation** may appear in docs; the visible tab is **System**.

---

## Conceptual distinctions (locked)

| Surface | Primary question | What it holds |
|---------|------------------|---------------|
| **Companion** | Who walks with me? | Unified SI: identity, intent, routing, continuity, approvals, presence |
| **Chat** | Which machine am I talking to? | Transparent access to individual workers/providers |
| **Self** | Who am I / what am I living? | Knowledge *about* the person (inner record) |
| **Library** | What do we know and preserve? | Knowledge *owned* by the person (Alexandria) |
| **Workshop** | What are we building? | Artifacts and productive work |
| **System** | What serves me? | Local infrastructure, workers, memory *infrastructure* |

One-line boundaries:

```text
Self      = knowledge about me
Library   = knowledge owned by me
Workshop  = things created by me
System    = infrastructure serving me
Companion = intelligence walking with me
Chat      = direct access to the underlying AI machinery
```

**Do not** bury Self inside Library.  
**Do not** put knowledge *content* under System.  
**Do not** put memory *indexing / RAG / store config* under Library — that is **Memory Infrastructure** (System).

---

## 1. Chat

**Direct access to agents and backends.**

Transparent, technical interface for talking to individual workers:

- Hermes Agent, JROS, Claude, Gemini, Grok, local models, other workers
- Selected backend visible
- Model / provider switching
- Tool calls inspectable
- Context and execution details visible

**Role:** developer console for intelligence.  
**Not:** the long-term relationship face of the product.

```text
Chat exposes the backends.
Companion hides and orchestrates them.
```

---

## 2. Companion

**The unified SI experience.**

Not another model selector. One continuous personal intelligence above workers.

Eventually responsible for:

- Identity and personality
- Long-term continuity
- Intent recognition
- Context assembly
- Worker / agent selection
- Delegation
- Approvals
- Memory retrieval (with privacy tiers)
- Daily guidance
- Voice and presence
- Relationship history

User speaks to **one SI**. The SI decides whether Hermes, JROS, Claude, a local model, or another worker performs the task.

Front door to everything when mature:

> “Open my CAD project.”  
> “How is my server doing?”  
> “What did Marcus Aurelius say about grief?”

---

## 3. Self

**Private inner record — knowledge about me.**

Stricter permissions than the rest of the app by default. Engineering workers must **not** receive medical history or private journal entries just because they help on a Workshop project.

### Internal structure

```text
Self
├── Journal          # daily entries, reflections, decisions, events
├── Mind             # mood, thoughts, fears, meditation, development
├── Body             # medical, symptoms, meds, fitness, sleep, nutrition
├── Dreams           # dream journal, symbols, links to waking life
├── Life             # goals, relationships, timeline, values, identity
└── Private Records  # clinical, insurance, legal ID — highest protection
```

### Privacy rule (architecture)

Self data uses **explicit grants**:

- Default: Companion may use Self only under user-defined scope and autonomy settings
- Workshop workers: no Self by default
- Library indexing: Self collections opt-in only, often local-only, never export without consent
- Private Records: separate vault tier; never used for worker context unless explicitly unlocked for a purpose

See also [TRUST_AND_PRIVACY_MODEL.md](./TRUST_AND_PRIVACY_MODEL.md).

---

## 4. Workshop

**Create. Build. Engineer. — output-oriented.**

Primary question: *What are we building?*

Examples:

- Projects, files, code, IDE, terminal
- CAD, simulation, robotics
- Documents, media creation, reports
- Research, analysis, data science
- Generated artifacts

Workspace-scoped: a rooted folder plus tool profile (code / cad / media / mixed).  
Anything that **produces an artifact** belongs here.

---

## 5. Library

**Personal Alexandria — knowledge-oriented.**

Primary question: *What do we know, study, and preserve?*

Examples:

- Books, PDFs, notes, highlights
- Courses, education, philosophy, world history
- Research archive, reference material
- Personal knowledge graph / collections

Lifelong owned knowledge and culture.  
**Not** infrastructure. **Not** the private medical/identity vault (that is Self).

---

## 6. System

**Local self-hosted infrastructure (UI name for Foundation).**

Primary question: *How does my digital world work?*

Examples:

- Agents, workers, AI providers, local models
- MCP servers, devices, smart home
- Network, storage, Docker/K8s, services
- Backups, security, permissions
- **Memory infrastructure** / knowledge indexing / RAG configuration
- System health

This is where the self-hoster configures the box.  
Knowledge *content* is not managed here — only how it is stored, indexed, synced, searched, and protected.

---

## Intent flow

```text
            You
             │
             ▼
     Synthetic Intelligence
     (Companion — long term)
             │
     ┌───────┼────────┬──────────┬─────────┐
     ▼       ▼        ▼          ▼         ▼
   Self  Workshop  Library    System     Chat*
```

\*Chat is direct machinery access; Companion routes into domains when possible.

User speech maps to domains without forcing menu tourism:

| Intent | Domain |
|--------|--------|
| Plan my day / talk it through | Companion |
| How am I doing / journal / health | Self |
| Open CAD / edit code / run analysis | Workshop |
| What did Aurelius say / find a PDF | Library |
| Is the server healthy / add a model | System |
| Talk to Hermes only, show tools | Chat |

---

## Modularity (public architecture)

Surfaces are stable; **packs** fill them:

```text
core/                 # Companion contracts, trust, journal spine, workspace
surfaces/
  chat/
  companion/
  self/
  workshop/
  library/
  system/
packs/                # optional extensions
  workshop-code/
  workshop-cad/
  library-alexandria/
  system-homeassistant/
  channel-creator/    # example first-path pack (e.g. YouTube production)
```

Rules:

1. Core must run with Companion + empty optional packs.
2. A pack registers capabilities into one or more surfaces; it does not invent a seventh top-level tab without a product decision.
3. Adapters expose identity, health, capabilities, permissions, config schema ([WORKER_ADAPTER_CONTRACT.md](./WORKER_ADAPTER_CONTRACT.md)).
4. First implementation path may prioritize one user’s creative/work pack; architecture stays general.

---

## Memory vs knowledge (terminology)

| Term | Belongs in | Meaning |
|------|------------|---------|
| **Memory infrastructure** | System | Stores, indexes, sync, retention, RAG pipelines, embeddings hosts |
| **Self record** | Self | Lived personal data about the user |
| **Library collections** | Library | Owned cultural/knowledge assets |
| **Companion continuity** | Companion | Relationship state, preferences, routing memory — assembled with privacy tiers |

Never call System “the knowledge base.” Never call Library “memory config.”

---

## Implementation guidance for UI agents

1. Design around the six surfaces above; default rail/order:  
   `Chat · Companion · Self · Workshop · Library · System`
2. Chat: bare, transparent worker console (current technical conversation can live here until Companion matures).
3. Companion: SI shell — not a second model picker; orchestration and continuity.
4. Self: private modules (Journal, Mind, Body, Dreams, Life, Private Records) with hard permission boundaries.
5. Workshop: projects/files/IDE/terminal/CAD/artifacts — create path.
6. Library: Alexandria — study and preserve path.
7. System: workers, devices, services, memory infrastructure, health.
8. Do not reintroduce a “Hermes Original” or framework-branded top-level section.
9. Prefer intent entry via Companion; keep deep links into each surface for power users.

---

## Alignment notes

- **FOUNDATION** Companion = SI control plane; this doc’s Companion surface is that experience in the UI.
- **Chat** is not a second Companion; it is worker-direct access (may remain useful forever under Advanced).
- Historical “journal as single bag for everything” should migrate: personal journal → **Self**; research notes/books → **Library**; episode/code artifacts → **Workshop**.
- Trust model must encode Self vault tiers before any “auto-context everything” feature ships.

---

## Status checklist (product, not sprint)

| Surface | Near-term | Mature |
|---------|-----------|--------|
| Chat | Primary technical talk path | Advanced / developer |
| Companion | Identity + continuity + routing stub | Full SI front door |
| Self | Journal + privacy shell | Mind/Body/Dreams/Life/Records |
| Workshop | Files + IDE + terminal | CAD/sim packs |
| Library | Search workspace docs + shelves | Full Alexandria |
| System | Workers, connections, health | Home, memory infra, services |
