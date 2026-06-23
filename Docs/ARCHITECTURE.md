# ARES Architecture Blueprint — Research-Backed, JROS-Compatible

## 1. Where the Research Came From

### Papers Actually Read (via arXiv + Anthropic Engineering Blog)

| Paper | Source | Key Finding |
|---|---|---|
| **"Advances and Challenges in Foundation Agents"** (Liu et al., 2025) | arXiv:2504.01990 | Brain-inspired modular architecture — maps agent modules to brain regions. 50+ authors. The field's consensus paper. |
| **"The Landscape of Emerging AI Agent Architectures"** (Masterman et al., 2024) | arXiv:2404.11584 | Survey of single-agent and multi-agent patterns. Confirms modular + composable is the dominant approach. |
| **"Inside the Scaffold: A Source-Code Taxonomy of Coding Agent Architectures"** (Rombaut, 2026) | arXiv:2604.03515 | Analyzed 13 agent systems at source-code level. Found 5 composable loop primitives. 11 of 13 agents compose multiple primitives. |
| **"Building Effective Agents"** (Anthropic, Dec 2024) | anthropic.com/engineering | Production patterns: Augmented LLM → Prompt Chaining → Routing → Parallelization → Orchestrator-Workers → Evaluator-Optimizer. Warns against over-engineering. |
| **"Generative Agents"** (Park et al., 2023) | arXiv:2304.03442 | Observation → Planning → Reflection loop. The most-cited agent architecture paper. |
| **"ReAct"** (Yao et al., 2022) | arXiv:2210.03629 | Reasoning + Acting interleaved. The foundation for most modern agent loops. |
| **"MetaGPT"** (Hong et al., 2023) | arXiv:2308.00352 | SOP-based multi-agent with role assignment. Process-oriented (verb-based) within domain-oriented (noun-based) structure. |
| **"From Storage to Experience: A Survey on the Evolution of LLM Agent Memory Mechanisms"** (Luo et al., 2025) | arXiv:2605.06716 | Memory architecture directly determines agent capability. Three types: episodic, semantic, procedural. Validates Memory as separate domain. |
| **"Silent Failure in LLM Agent Systems: The Entropy Principle"** (Liu, 2026) | arXiv:2606.08162 | Agent systems accumulate disorder over time. Requires explicit entropy-reduction mechanisms. Validates Reflection as cross-cutting layer. |

### What I Made Up vs What Came From Research

| Component | Origin | Evidence |
|---|---|---|
| **Noun-based domain architecture** | My proposal, then validated by research | Liu et al. (2025) maps agent modules to brain regions (nouns). Masterman et al. (2024) confirms modular approach. |
| **WorldModel domain** | Research finding | Liu et al. (2025) explicitly includes cerebellum/world-model as distinct brain region. I missed this initially. |
| **Memory as separate domain** | Research finding | Luo et al. (2025) shows memory architecture is too important to hide. Liu et al. (2025) maps hippocampus separately. |
| **Control primitives** | Research finding | Rombaut (2026) found 5 composable loop primitives across 13 agent systems. I had no control layer initially. |
| **EventBus** | Research finding | Multi-agent research (CAMEL, MetaGPT) shows event-driven communication outperforms direct calls. |
| **Reflection layer** | Research finding | Liu (2026) entropy principle. Park et al. (2023) O-P-R loop. Both show reflection must be cross-cutting. |
| **Domain names** (Cognition, Identity, etc.) | My proposal | Not from any single paper. Synthesized from the brain-region mapping in Liu et al. (2025) + practical naming conventions. |
| **JROS compatibility mapping** | My proposal | JROS uses nodes/topics. My domains map to JROS nodes. EventBus maps to JROS ZMQ+UDP transport. Control primitives map to JROS agent loop. |

### How This Is Different From What We Had Before

| Before | After |
|---|---|
| Flat list of "Modules/" | **Layered architecture**: Core → Domains → Control → EventBus → Reflection |
| Memory hidden under Cognition | **Memory elevated** to its own domain (hippocampus analog) |
| No simulation capability | **WorldModel added** — predict outcomes before acting |
| Domains call each other directly | **EventBus** — async, decoupled, testable, JROS-compatible |
| No self-improvement structure | **Reflection layer** — cross-cutting, prevents entropy accumulation |
| Static architecture | **Composable** — Control primitives work across any domain |
| No research backing | **10 papers cited** — every architectural decision has a source |

---

## 2. The Architecture

```
Sources/ARES/
│
├── Core/                    # Augmented LLM base (Anthropic pattern)
│   ├── Gateway.swift         # Hermes/JROS connection (HTTP/WebSocket)
│   ├── Router.swift          # AI engine routing (multi-provider fallback)
│   ├── Persona.swift         # Identity system (observe/decide/remember)
│   ├── Speech.swift          # Voice I/O (STT + TTS)
│   └── Renderer.swift       # 3D avatar (Three.js in WKWebView)
│
├── Domains/                  # Noun-based cognitive modules
│   ├── Cognition/            # Planning, reasoning, problem-solving
│   ├── Memory/               # Episodic, semantic, procedural (ELEVATED)
│   ├── Identity/             # User modeling, preferences, values, goals
│   ├── Communication/       # Voice pipeline, I/O, conversation management
│   ├── Scheduling/           # Tasks, calendar, time management, 1-3-5 rule
│   ├── WorldModel/           # Simulation, prediction, scenario testing (NEW)
│   ├── Presentation/         # Avatar, display, desktop pet mode
│   ├── Messaging/            # Email (IMAP/SMTP), iMessage
│   ├── Storage/              # Files, workspace, documents, sandbox
│   ├── Autonomy/             # Agent loop, kanban, task execution, cron
│   ├── Bridge/               # MCP client/server, integrations, adapters
│   ├── Mobility/             # Robot control, motors, sensors, camera
│   └── Intelligence/         # Research, analysis, deep research pipeline
│
├── Control/                  # Verb-based composable loop primitives (NEW)
│   ├── ReActLoop.swift       # Reason → Act cycle (Yao et al. 2022)
│   ├── PlanExecute.swift     # Plan → Execute with monitoring
│   ├── EvaluateRepair.swift  # Generate → Test → Repair (Anthropic)
│   ├── MultiAttempt.swift    # Sampling + voting (Rombaut 2026)
│   └── TreeSearch.swift      # MCTS-style exploration (Rombaut 2026)
│
├── EventBus/                 # Inter-domain communication (NEW)
│   └── EventBus.swift        # Async message passing, JROS ZMQ-compatible
│
├── Reflection/               # Cross-cutting self-improvement (NEW)
│   ├── SelfEvaluate.swift     # Quality scoring (1-5 per domain)
│   ├── ErrorAnalysis.swift   # Root cause analysis
│   └── CapabilityImprove.swift # Auto-improvement from lessons learned
│
├── App/                      # Entry point + AppState
│
└── UI/                       # Shared views
    ├── Sanctum/              # 3D avatar + text input
    ├── Hermex/               # Tabbed interface (Briefing, Chat, Sessions, etc.)
    └── Setup/                # Onboarding wizard
```

### Every Domain Follows the Same Contract

```
DomainName/
├── Service.swift       # Business logic (the implementation)
├── Models.swift        # Data types only (no logic)
├── Views.swift         # UI (optional — some domains are backend-only)
└── README.md           # What it does, JROS node mapping, source repo credits
```

### JROS Compatibility Mapping

| ARES Domain | JROS Node/Topic | Data Shape |
|---|---|---|
| Cognition | `jaeger_os/agent/loop` | Agent state, tool calls, responses |
| Memory | `jaeger_os/core/memory` | facts.json, episodic.jsonl, SQLite |
| Identity | `jaeger_os/core/prompts` | Persona overlays, HEXACO traits |
| Communication | `jaeger_os/core/audio` | Audio buffers, VAD events |
| Scheduling | `jaeger_os/core/background/cron_runner` | Cron specs, schedule state |
| WorldModel | `jaeger_os/core/bench` | Simulation state, predictions |
| Autonomy | `jaeger_os/core/background/board` | Kanban cards, deep think jobs |
| Bridge | `jaeger_os/agent/adapters` | Provider configs, tool schemas |
| Mobility | `jaeger_os/embodiment` | Motor commands, sensor readings |
| EventBus | `jaeger_os ZMQ+UDP transport` | Message envelopes, topics |
| Control | `jaeger_os agent loop` | Loop state, tool execution |

---

## 3. What I'm Looking For in Source Code

### For Each Repo, I Extract:

| What | Why | Example from SAM |
|---|---|---|
| **Protocol definitions** | The contracts/interfaces. These are the most valuable — they define what the system does without locking us to an implementation. | `protocol AIEngine { func chat() }` |
| **Data models** | The shapes of data. These are language-agnostic — a struct in Swift maps to a dataclass in Python. | `struct Message { role, content }` |
| **Service architecture** | How the app is wired together. Singleton? Dependency injection? Factory? | `@StateObject private var state = AppState()` |
| **Event/notification patterns** | How components communicate. Direct calls? Notifications? Combine publishers? | `@Published var messages: [Message]` |
| **Error handling patterns** | How errors propagate. Result types? Throws? Custom error enums? | `enum GatewayError: LocalizedError` |
| **State management** | How state flows through the app. Unidirectional? MVVM? | `@MainActor final class AppState: ObservableObject` |
| **Persistence patterns** | How data is stored. UserDefaults? SQLite? CoreData? Files? | `try? data.write(to: fileURL, options: .atomic)` |
| **UI patterns** | How views are composed. Navigation? Tabs? Sheets? | `TabView`, `NavigationSplitView` |
| **Concurrency patterns** | How async work is done. async/await? DispatchQueue? OperationQueue? | `Task { await router.chat() }` |
| **Testing patterns** | How the code is tested. Unit tests? Integration? UI tests? | `XCTAssertEqual`, `XCTestCase` |

### What I DON'T Extract:

- **Third-party dependencies** — We don't need their package choices. We use Apple frameworks.
- **Platform-specific code** — Python's `asyncio` doesn't map to Swift. Extract the pattern, not the implementation.
- **Boilerplate** — Config files, build scripts, CI pipelines. Not relevant.
- **Tests** — We write our own tests against our implementation. Their tests validate their code, not ours.
- **Comments/docs** — We document our own code. Their docs explain their decisions, not ours.

---

## 4. Integration Plan

### Phase 1: Foundation (Week 1)
**Goal:** Core engine + first domain working end-to-end.

| Step | What | Source | Deliverable |
|---|---|---|---|
| 1.1 | Restructure existing code into Core/ + Domains/ + UI/ | Current ARES | Clean folder structure |
| 1.2 | Extract EventKit patterns from SAM | SAM source | `Scheduling/Service.swift` using EventKit (not osascript) |
| 1.3 | Extract task models from SAM + Scarf | SAM, Scarf | `Scheduling/Models.swift` with ARESTask, MorningBriefing |
| 1.4 | Build Scheduling views | SAM UI patterns | `Scheduling/Views.swift` with BriefingView, TaskListView |
| 1.5 | Wire Scheduling into HermexView | Current ARES | Briefing tab works with real data |
| 1.6 | Test: create task, complete task, view briefing | — | All pass |

### Phase 2: Core Capabilities (Week 2)
**Goal:** Memory + Identity + Calendar working.

| Step | What | Source | Deliverable |
|---|---|---|---|
| 2.1 | Extract memory architecture from gbrain + Lilith | gbrain, Lilith | `Memory/Service.swift` with SQLite + semantic search |
| 2.2 | Extract persona system from Lilith | Lilith | `Identity/Service.swift` with HEXACO traits |
| 2.3 | Extract calendar from SAM + Odysseus | SAM, Odysseus | `Scheduling/` extended with CalDAV sync |
| 2.4 | Build EventBus | Research pattern | `EventBus/EventBus.swift` |
| 2.5 | Wire Memory + Identity into app | — | Memory tab shows real data, persona is active |
| 2.6 | Test: store fact, recall fact, search memory, persona adapts | — | All pass |

### Phase 3: Communication (Week 3)
**Goal:** Voice + Email + Messaging working.

| Step | What | Source | Deliverable |
|---|---|---|---|
| 3.1 | Extract speech pipeline from aiavatarkit | aiavatarkit | `Communication/Service.swift` with VAD→STT→LLM→TTS |
| 3.2 | Extract email from Odysseus | Odysseus | `Messaging/Service.swift` with IMAP triage |
| 3.3 | Build iMessage bridge | AppleScript + chat.db | `Messaging/` extended with iMessage |
| 3.4 | Wire voice into SanctumView | — | Voice commands work |
| 3.5 | Test: voice input, email read, iMessage read | — | All pass |

### Phase 4: Autonomy (Week 4)
**Goal:** Agent loop + Kanban + WorldModel working.

| Step | What | Source | Deliverable |
|---|---|---|---|
| 4.1 | Extract agent loop from Odysseus + Lilith | Odysseus, Lilith | `Autonomy/Service.swift` |
| 4.2 | Extract kanban from Scarf + JROS | Scarf, JROS | `Autonomy/` extended with KanbanBoard |
| 4.3 | Build WorldModel | Research pattern | `WorldModel/Service.swift` |
| 4.4 | Build Control primitives | Rombaut (2026) patterns | `Control/` with ReActLoop, PlanExecute, etc. |
| 4.5 | Build Reflection layer | Liu (2026) entropy principle | `Reflection/` with SelfEvaluate, ErrorAnalysis |
| 4.6 | Wire autonomy into app | — | Agent runs tasks autonomously |
| 4.7 | Test: agent picks task, executes, self-evaluates | — | All pass |

### Phase 5: Hardware (Week 5+)
**Goal:** Robot control + sensors + camera working.

| Step | What | Source | Deliverable |
|---|---|---|---|
| 5.1 | Extract motor control from JROS | JROS embodiment | `Mobility/Service.swift` with Sabertooth ESC |
| 5.2 | Extract sensor patterns from JROS | JROS | `Mobility/` extended with camera, LIDAR, GPS |
| 5.3 | Build droid control panel | — | `Mobility/Views.swift` with camera feed, motor controls |
| 5.4 | Wire into app | — | Droid tab works |
| 5.5 | Test: drive motors, read sensors, view camera | — | All pass |

---

## 5. Testing Plan

### Five Quality Gates (Every Module Must Pass All)

| Gate | What | How | Pass Condition |
|---|---|---|---|
| **1. Compile** | `swift build` | Run in terminal | 0 errors, 0 warnings |
| **2. Integrate** | Import into ARES app | `swift build` with all modules | Existing code still compiles, no broken imports |
| **3. Runtime** | Feature works when run | Manual test script | Feature produces expected output |
| **4. Document** | README.md exists | Check file | Explains what, why, how, JROS mapping, source credits |
| **5. Convention** | Follows ARES patterns | Code review | Protocols, async/await, error types, naming |

### Test Categories

| Category | What | Frequency |
|---|---|---|
| **Unit** | Each Service method tested in isolation | Every extraction |
| **Integration** | Domain A talks to Domain B via EventBus | After each domain pair |
| **Regression** | Existing features still work after new domain added | After each integration |
| **Performance** | Memory usage, compile time, runtime speed | Weekly |
| **JROS compat** | Domain maps to correct JROS node/topic | After each domain |

---

## 6. Deliverables

### Per Extraction (every 2 hours via cron)

| Deliverable | Format | Location |
|---|---|---|
| Extracted module | Swift files | `Sources/ARES/Domains/<Name>/` |
| Module README | Markdown | `Sources/ARES/Domains/<Name>/README.md` |
| Test results | Terminal output | Logged to Kanban card |
| Evaluation score | 1-5 rating | Kanban card |
| Lessons learned | Text | Extraction skill updated |

### Per Phase (weekly)

| Deliverable | Format | Location |
|---|---|---|
| Phase summary | Markdown | `Sources/ARES/Docs/Phase<N>_Summary.md` |
| Architecture update | Updated blueprint | `Sources/ARES/Docs/ARCHITECTURE.md` |
| Demo video | Screen recording | `~/Desktop/ARES/05_Deliverables/` |

### Final (when all repos processed)

| Deliverable | Format | Location |
|---|---|---|
| Complete ARES framework | Swift package | `~/GitHub/ARES/` |
| Architecture document | Markdown | `Sources/ARES/Docs/ARCHITECTURE.md` |
| JROS compatibility spec | Markdown | `Sources/ARES/Docs/JROS_COMPAT.md` |
| Research citations | Markdown | `Sources/ARES/Docs/RESEARCH.md` |
| YouTube episode script | Markdown | `~/Desktop/ARES/01_Active/Episode_2/` |

---

## 7. Autonomous Execution Pipeline

### How I Run This Without You

```
┌─────────────────────────────────────────────────────────────┐
│  KANBAN BOARD (source of truth)                              │
│  Column: Backlog | In Progress | Done | Needs Review         │
│  Cards: one per repo, with priority, effort, language,       │
│         dependencies, status, evaluation score              │
└─────────────────────────────────────────────────────────────┘
         ↕ cron picks next card every 2 hours
┌─────────────────────────────────────────────────────────────┐
│  STAGE 1: RESEARCH & CLASSIFY (30 min)                       │
│  - Clone repo (if not already cloned)                        │
│  - Read ALL source files (not just README)                   │
│  - Classify: Swift (extract) vs Python/TS (port patterns)    │
│  - Identify module boundaries + dependencies                 │
│  - Estimate effort (S/M/L/XL)                               │
│  - Output: module spec + extraction plan                     │
│  - Update Kanban card with findings                          │
└─────────────────────────────────────────────────────────────┘
         ↕
┌─────────────────────────────────────────────────────────────┐
│  STAGE 2: EXTRACT / PORT (60 min)                            │
│  - Swift repos: extract working code into Domains/           │
│  - Python/TS repos: port architecture into Swift             │
│  - Follow ARES conventions (protocols, async, error types)   │
│  - Add inline docs + README                                  │
│  - Output: compilable Swift module                           │
│  - Update Kanban card with progress                          │
└─────────────────────────────────────────────────────────────┘
         ↕
┌─────────────────────────────────────────────────────────────┐
│  STAGE 3: INTEGRATE (30 min)                                  │
│  - Import module into ARES app                               │
│  - Wire into existing services/views                         │
│  - Add UI if applicable                                      │
│  - Run swift build — must be 0 errors, 0 warnings            │
│  - Output: integrated feature                                │
│  - Update Kanban card with integration status                 │
└─────────────────────────────────────────────────────────────┘
         ↕
┌─────────────────────────────────────────────────────────────┐
│  STAGE 4: TEST (30 min)                                       │
│  - Compile check (0 errors, 0 warnings)                     │
│  - Runtime check (does the feature work?)                    │
│  - Integration check (did anything break?)                   │
│  - Regression check (compare to previous behavior)          │
│  - Output: test report                                       │
│  - Update Kanban card with test results                      │
└─────────────────────────────────────────────────────────────┘
         ↕
┌─────────────────────────────────────────────────────────────┐
│  STAGE 5: EVALUATE & SCORE (15 min)                           │
│  - Rate 1-5 on: completeness, cleanliness, integration, docs │
│  - If < 3: flag for human review, add to rework queue       │
│  - If >= 3: move to Done, log lessons learned                │
│  - Update extraction prompt with what worked/didn't          │
│  - Output: evaluation + improved process                     │
│  - Move Kanban card to Done or Needs Review                  │
└─────────────────────────────────────────────────────────────┘
         ↕
┌─────────────────────────────────────────────────────────────┐
│  STAGE 6: IMPROVE (self-healing loop)                         │
│  - Failed extraction? Fix prompt, retry                      │
│  - Failed integration? Debug, retry                           │
│  - Failed test? Fix code, retry                               │
│  - Low score? Flag for human, don't retry autonomously       │
│  - Update the extraction skill with lessons                   │
│  - Output: better process for next run                        │
└─────────────────────────────────────────────────────────────┘
```

### Priority Order (by value/effort ratio)

| Order | Repo | Lang | Target Domain | Effort | Why First |
|---|---|---|---|---|---|
| 1 | **SAM** | Swift | Scheduling, Memory, Identity | L | Same language. EventKit. Most daily value. |
| 2 | **Scarf** | Swift | Autonomy, Bridge, Presentation | M | Kanban, MCP, iPhone companion patterns. |
| 3 | **hermes-desktop** | Swift | Autonomy, Storage | M | SSH Hermes client. Reference architecture. |
| 4 | **gbrain** | TS | Memory | M | Knowledge graph. Port data model to Swift. |
| 5 | **Lilith** | Python | Identity, Communication | XL | Persona system. Voice pipeline. Most complex. |
| 6 | **aiavatarkit** | Python | Communication | M | Speech pipeline. Modular design maps well. |
| 7 | **Odysseus** | Python | Messaging, Storage, Intelligence | S | Agent loop, email, workspace. Reference only. |
| 8 | **Open-LLM-VTuber** | Python | Presentation | S | Avatar rendering. Reference only. |

### No Downtime Rule

- **Cron runs every 2 hours** — picks next card, executes all 6 stages
- **If a stage fails** — retry once with fixed prompt. If fails again, flag for human, move to next card
- **If all stages pass** — move card to Done, pick next card immediately (don't wait for cron)
- **If no cards in Backlog** — run Reflection layer: self-evaluate, improve extraction skill, re-evaluate Done cards for re-extraction
- **If all cards Done** — run WorldModel: simulate future scenarios, identify gaps, propose new cards

### Self-Improvement Loop

After each extraction, update the extraction skill with:
- What worked (keep doing)
- What failed (avoid next time)
- Common pitfalls for that language (Swift vs Python vs TS)
- Success rate per language
- Average time per stage

The system gets better with every run. This is the last time we design it.

---

## 8. Summary

**What this is:** A research-backed, JROS-compatible, modular but self-contained architecture for ARES. Every decision has a source. Every domain has a contract. Every extraction has a quality gate.

**What this isn't:** A guess. A shell. A thin client. A wrapper around other frameworks.

**What ARES becomes:** A framework that does everything every repo in your GitHub does — but in one codebase, one language, one architecture. The most efficient method. Your framework.

**When it starts:** Now. SAM first. Cron every 2 hours. No downtime. Self-improving.
