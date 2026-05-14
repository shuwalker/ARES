# ARES Competitive Research — May 2026

## Framework Deep Dives

### OpenAI Agents SDK
- **Architecture**: Minimal primitives (Agent, Handoff, Guardrail, Runner) on Responses API
- **Loop**: Reactive execution — LLM decides when to stop, no explicit planning
- **Memory**: `RunContextWrapper[T]` generic context, optional `Session` persistence (SQLite/Postgres), `Memory` abstraction with semantic search
- **MCP**: Native MCP support (stdio, HTTP, SSE)
- **Multi-agent**: Handoffs, Manager pattern, Chains
- **Guardrails**: Input/Output/Tool — pluggable checks at each boundary
- **Tracing**: OpenTelemetry-compatible per-agent spans
- **Steal for ARES**:
  - Guardrail layers (input/output/tool intercept at each phase boundary)
  - `RunContextWrapper[T]` typed context injection (replace scattered dict passing)
  - Native MCP server lifecycle management (connect/approve/filter)
  - OpenTelemetry tracing per cognitive phase

### Google ADK
- **Architecture**: Multi-language (Python/TS/Go/Java), graph-native, event-driven
- **Loop**: Multiple patterns — LLM loop, Workflow agents (sequential/parallel/conditional), Plan-Execute
- **Memory**: 3-tier: `session.state` (in-conversation KV), Memory Bank (short-term), RAG Memory (long-term)
- **Event system**: `Event(author, invocation_id, content, actions)` — formalized event bus
- **Multi-agent**: Parent/sub-agent hierarchy with shared state, A2A protocol
- **Steal for ARES**:
  - `AresEvent` dataclass on ZMQ (formalize bus messages)
  - Hierarchy: Parent orchestrator + sub-agents for PERCEIVE/THINK/ACT/REFLECT
  - Workflow agents for deterministic sub-pipelines (validation, formatting)
  - A2A protocol gateway for cross-agent interop
  - 3-session memory service (SessionService / MemoryService / ArtifactService)

### LangGraph
- **Architecture**: State-graph engine, nodes=actions, edges=transitions, cycles=first-class
- **Key innovation**: **Durable execution with checkpointing** — every step auto-snapshotted
- **Memory**: Thread-scoped state + MemoryStore KV with semantic search
- **Steal for ARES**:
  - Checkpoint ThoughtDAG to JSONL/SQLite after every cycle (crash recovery + time-travel debug)
  - Namespaced memory (`("user", "matthew", "facts")`) for scoped retrieval
  - Interrupt/Resume for idle reflexion (pause main loop, reflect, resume)

### Pydantic AI
- **Architecture**: Type-safe agent framework, `Agent[Deps, Output]` generic pattern
- **Key innovation**: Typed dependencies, structured output with auto-retry
- **Steal for ARES**:
  - Dependency injection for personality/memory/config into cognitive functions
  - Enforce Pydantic models for every LLM output (thought nodes, action plans) with retry on validation failure
  - "Capabilities" bundling (tools + hooks + instructions) — formalize ARES Domains as typed Capabilities

### CrewAI
- **Architecture**: Role-based multi-agent (Agent with Role/Goal/Backstory → Crew → Process)
- **Memory**: 4-tier: Short-term, Long-term, Entity, Contextual + Knowledge (RAG)
- **Steal for ARES**:
  - Role-based prompting (specialist sub-personas for different task types)
  - Explicit episodic/semantic/entity/contextual memory tiering
  - Sequential/Hierarchical/Consensual process modes for reasoning

### MemGPT / Letta
- **Architecture**: OS memory hierarchy metaphor — context window = RAM, external DB = disk
- **Key innovation**: LLM self-manages memory via function calls (`core_memory_replace`, `archival_memory_search`)
- **Sleep-time agents**: Background reasoning during idle (like ARES idle reflexion)
- **Memory blocks**: Modular, attachable/detachable sections
- **Steal for ARES**:
  - LLM-editable memory interfaces (`memory_store.promote_to_semantic()`, `memory_store.summarize_episodic()`)
  - Composable memory blocks that load into prompt context independently
  - Formal "sleep-time" worker for idle reflexion

### AutoGen (Microsoft)
- **Architecture**: Layered — AgentChat (high-level), Core (event-driven runtime), Extensions
- **Key pattern**: Actor-model, topic-based pub/sub, event-driven routing
- **Steal for ARES**:
  - Formalize ZMQ topics/subscriptions using actor-model pattern
  - Protobuf for ThoughtDAG checkpoint serialization
  - `McpWorkbench` wrapper pattern for tool management

## Academic Papers (2025-2026)

### MEMTIER (May 2026)
- Tripartite memory: episodic JSONL, semantic tier, retrieval engine
- **Five-signal weighted retrieval**: recency × frequency × relevance × importance × temporal_decay
- **Consolidation daemon**: Async promotes episodic → semantic (like sleep)
- PPO-based policy for adaptive retrieval weights
- **Steal**: Five-signal scoring for `memory_store.py`, async consolidation during idle reflexion

### LoongFlow (Dec 2025)
- Plan-Execute-Summarize (PES) loop for self-evolving agents
- MAP-Elites + Multi-Island evolutionary memory for diverse reasoning
- **Steal**: MAP-Elites niche concept for maintaining diverse "lines of reasoning" in ThoughtDAG

### SPIRAL (Dec 2025)
- Three sub-agents in MCTS: Planner, Simulator, Critic
- **Steal**: Split ARES THINK phase into Planner/Simulator/Critic sub-routines for deeper reasoning

## Embodied AI / Companion Platforms

### Soul Machines — DEAD (Feb 2026 receivership)
- Had Digital Brain™ layered cognitive model (sensory, motor, attention, autonomic)
- 100% cloud, proprietary. RIP.

### Razer Project Ava — Canceled (404)
- Companion overlay UI concept. Dead.

### AIRI (github.com/moeru-ai/airi) — 39.3k stars ⭐
- Self-hosted Grok companion, WebGPU + native CUDA/Metal
- Live2D + VRM avatars, real-time voice, game integration
- Multi-platform (web, desktop, tamagotchi)
- **Steal**: VRM avatar support, Live2D as lightweight fallback, game state detection

### Replika
- Relationship XP/progression system
- Explicit memory tagging UX (user corrects memories)
- Trait voting (thumbs up/down shapes personality)
- **Steal**: Bonding metric, memory correction UI

### Character.AI
- Character card format (name + short desc + long desc + example dialogue)
- **Steal**: Auto-generate HEXACO profile from character cards

### Hume AI
- Emotion-aware voice — prosody conditional on detected emotion
- Back-channeling (mm-hmm while listening)
- Expression measurement API (vocal + facial)
- **Steal**: Emotion classifier before TTS, back-channeling audio cues

### Inworld AI
- Best-in-class realtime voice (sub-130ms)
- Provider-agnostic LLM routing
- **Steal**: LLM routing (fast/cheap for idle, smart for reasoning), prosody markup

### Pi (Inflection AI)
- Proactive check-ins (agent initiates conversation)
- **Steal**: "INITIATE" cognitive phase — ARES starts conversations based on time/calendar/state

## ARES Competitive Advantages (Defend These)

1. **Fully local-first** — No cloud required. Only project with this level of integration.
2. **Real 3D face on Apple Silicon** — RealityKit + Metal, not a web widget.
3. **Cognitive architecture** — PERCEIVE→THINK→ACT→REFLECT + ThoughtDAG + idle reflexion. Deepest reasoning of any project.
4. **ZMQ pub/sub bus** — True microservices. Most projects are monolithic.
5. **Personality system** — HEXACO + SPECIAL + Expression + Domains. 4-layer adjustable. Most competitors have a slider at best.
6. **Self-owned** — Not subscription, not cloud-locked, not privacy-invading.

## Recommended Priority Actions

1. **Guardrail system** — Input/Output/Tool at each cognitive phase boundary
2. **Five-signal memory scoring** — recency × frequency × relevance × importance × temporal_decay
3. **Barge-in voice interruption** — Detect speech during TTS, abort and switch
4. **ThoughtDAG checkpointing** — JSONL/SQLite after every cycle for crash recovery
5. **Emotion classifier → prosody** — Before Piper TTS, map emotion to voice parameters
6. **VRM avatar fallback** — Lightweight alternative to RealityKit for lower-end hardware
7. **Proactive initiation** — "INITIATE" phase where ARES starts conversations
8. **Character card import** — Generate HEXACO profile from Character.AI-style cards
9. **LLM routing** — Route to fast/cheap model for idle tasks, smart model for reasoning
10. **SPIRAL sub-agents** — Split THINK into Planner/Simulator/Critic sub-routines