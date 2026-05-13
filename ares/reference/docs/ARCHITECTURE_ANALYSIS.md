# ARES Architecture Analysis — Comparative Study

**Date:** May 12, 2026
**Analyzed:** Lilith-AI, crewAI, open-claude-code, SAM, VoiceLLM (pending)

---

## 1. Lilith-AI (John's Approach)

### Architecture Overview

Lilith is a **ZMQ pipeline bus** with independent plugin modules communicating through typed ports. The entire system is designed around physical process isolation — every module (STT, LLM, TTS, robot commands) runs as its own thread/process, connected by ZeroMQ sockets.

```
Mic ──PUSH──→ Port 5570 ──PULL──→ Whisper STT ──PUSH──→ Port 5571
                                                        │
Port 5572 ←──PUB── LLM Brain ←──PULL── Port 5571 ←─────┘
    │
    ├──SUB──→ TTS (Kokoro)
    ├──SUB──→ CLI
    └──SUB──→ Robot Commands (Port 5574, future)
```

### Core Module Breakdown

#### `zmq_bus.py` — LilithBus
- Manages ZMQ Context + socket lifecycle
- Socket types: PUSH (send workload), PULL (receive workload), PUB (broadcast), SUB (receive broadcasts with topic filter)
- All data serialized as JSON over ZMQ
- Every plugin receives a `bus: LilithBus` instance on construction
- `send(socket, data)` / `receive(socket, timeout_ms=100)` — poll-based non-blocking receive

#### `ports.py` — PortMap
```python
class PortMap:
    AUDIO_RAW: int    = 5570   # Mic audio chunks -> Whisper STT
    STT_TEXT: int     = 5571   # Whisper text -> LLM Brain
    LLM_RESPONSE: int = 5572   # LLM output -> all consumers (PUB/SUB)
    TTS_CONTROL: int  = 5573   # TTS commands
    ROBOT_CMD: int    = 5574   # Robot motor/behavior commands (future use)
    PIPELINE_LOG: int = 5575   # Internal logging bus
```
- **Key insight:** Named ports with fixed numbers. Simple, debuggable, no service discovery needed. Each port has a clear producer→consumer contract.

#### `base_plugin.py` — BasePlugin (ABC)
- Every module inherits from `BasePlugin(bus, config)`
- Lifecycle: `setup()` → `start()` → runs in daemon thread → `stop()` → `cleanup()`
- Built-in logging via PUB socket to `PIPELINE_LOG` port
- `_run_wrapper()` catches unhandled exceptions, logs them, sets `running=False`
- Thread-based concurrency (not async)

#### `registry.py` — PluginRegistry
- Discovers plugins by scanning directory for `plugin.json` manifests
- Dynamic import via `importlib.util` — creates a synthetic package namespace `lilith_plugins.{name}`
- Can start/stop individual plugins at runtime
- Plugins are fully hot-swappable

#### `personality.py` — 4-Layer Personality System
**This is Lilith's most novel contribution.** Every other system uses flat system prompts. Lilith uses 4 composable dataclass layers, each with 0.0-1.0 sliders:

1. **HexacoLayer** — Big Five + Honesty-Humility
   - openness, conscientiousness, extraversion, agreeableness, neuroticism, honesty_humility
   - Clamped to [0.0, 1.0] via `__post_init__`

2. **SpecialLayer** — Fallout S.P.E.C.I.A.L. capability model
   - strength, perception, endurance, charisma, intelligence, agility, luck
   - "Defines what the character CAN DO, not just who they are"

3. **ExpressionLayer** — Communication style
   - sarcasm, warmth, verbosity, formality, directness, humor, empathy, aggression
   - "HOW the character expresses themselves"

4. **DomainsLayer** — Knowledge domain weights
   - science, philosophy, combat, art, politics, technology, nature, psychology
   - "Affects what topics the character gravitates toward"

These compose into a `CharacterProfile`:
```python
@dataclass
class CharacterProfile:
    meta: CharacterMeta        # name, category, source, description, tags, backstory, speech_patterns, custom_instructions
    hexaco: HexacoLayer
    special: SpecialLayer
    expression: ExpressionLayer
    domains: DomainsLayer
```
The `generate_system_prompt()` method composes all 4 layers into a structured system prompt that encodes personality dimensions explicitly. Characters can be loaded, saved, and adjusted in real-time via Streamlit sliders.

#### `character_generator.py` — LLM-Generated Personalities
- Uses the running LLM to generate a complete `CharacterProfile` from a name or description
- Returns structured JSON matching the 4-layer schema
- The LLM essentially "casts" a character by filling in all trait sliders

#### `character_library.py` — Character Persistence
- File-based storage in `profiles/_library/{category}/{name}.json}`
- Categories: originals, clones, variants
- Active profile stored in `profiles/active.json`

#### `memory.py` — ConversationMemory
- **Sliding window only** — `max_size=20`, oldest message dropped on overflow
- No vector search, no persistence across sessions, no consolidation
- This is the weakest part of Lilith

#### `inference.py` — LLM Inference
- `llama-cpp-python` only (local GGUF models)
- `chat_with_lilith()` manually builds prompt with role formatting
- No tool calling, no function calling, no streaming
- Single provider, no fallback

#### `cli.py` — CLI Interface
- ZMQ PUSH socket for input, SUB socket for responses
- Background listener thread for real-time output
- Demonstrates that any interface can plug into the bus

### What Works in Lilith

1. **True process isolation** — Every module is independently replaceable. Swap Whisper for a different STT? Change one plugin. No other code touches.
2. **4-layer personality** — Far more expressive than any other system's approach to agent character. The sliders make personality tunable and measurable.
3. **Plugin discovery and hot-swap** — The `plugin.json` manifest + dynamic import pattern is clean and extensible.
4. **Multiple simultaneous interfaces** — CLI and Streamlit can both run on the bus at the same time. Adding a new face means writing a new subscriber.

### What's Weak in Lilith

1. **No memory persistence or retrieval** — 20-message sliding window. No vector search, no semantic recall, no cross-session. ARES already surpasses this with Hermes sessions.
2. **No coordination/health layer** — If STT crashes, the bus doesn't know. No retries, no health checks, no graceful degradation.
3. **Single LLM provider** — llama-cpp-python only. No fallback chain, no cloud options, no tool calling.
4. **No tool system** — Lilith can only talk. It can't act on the world. No function calling, no tool execution, no MCP.
5. **No async** — Thread-based, not async. Fine for a few modules, but won't scale to many concurrent operations.
6. **Hard-coded ports** — PortMap is a dataclass with fixed numbers. No dynamic allocation, no service discovery. Works for a single machine, breaks for distributed deployment.

### ARES Recommendation: Adopt the Bus, Drop the Rest

**Keep:**
- ZMQ bus pattern for connecting face modules (voice, vision, robot) to the brain
- 4-layer personality system (HEXACO + SPECIAL + Expression + Domains)
- Plugin discovery via manifest + dynamic import
- PortMap concept (named, typed ports)

**Replace:**
- Memory → Hermes sessions + brain transport + future vector RAG
- LLM inference → Hermes (already handles multi-provider, streaming, tool calling)
- Thread-based concurrency → async where possible, ZMQ for process isolation
- Hard-coded ports → configurable port mapping via config.yaml

---

## 2. crewAI

### Architecture Overview

crewAI is a **role-based multi-agent orchestration framework**. Agents are Pydantic models with role/goal/backstory, tasks form explicit DAGs with context edges, and the Flow system provides reactive DAG orchestration with `@start`/`@listen`/`@router` decorators.

### Core Abstractions

#### Agent — Role/Goal/Backstory Pydantic Model
- `BaseAgent(BaseModel)` — ~40 fields: role, goal, backstory, llm, tools, knowledge, memory, max_iter, max_retry_limit, rpm_controller
- `Agent(BaseAgent)` — concrete implementation executing via `CrewAgentExecutor`
- `BaseAgentAdapter` — extends BaseAgent for external frameworks (Langchain, autogen)
- Interpolation: agents support `{variable}` placeholders in role/goal/backstory
- Fingerprinting: cryptographic fingerprints for security/auditing
- Copy semantics: shallow-copy LLM, knowledge, knowledge_storage (shared); per-agent tools

#### Task — DAG Node with Explicit Context
- `description`, `expected_output`, `agent` (assigned)
- `context: list[Task]` — **explicit dependency edges** pointing to prior tasks whose outputs become context
- `async_execution: bool` — marks tasks for concurrent execution
- `output: TaskOutput` — raw, pydantic, json_dict, summary
- `callback`, `human_input`, `output_file`
- **ConditionalTask** — subclass that evaluates a condition function against prior outputs to decide whether to skip

#### Crew — Task Executor
- **Sequential process**: iterate tasks in order; context = all prior outputs; async tasks batched into ThreadPoolExecutor
- **Hierarchical process**: creates a manager agent that delegates using `DelegateWorkTool` and `AskQuestionTool`
- Context assembly (`_get_context`): collects prior task outputs, interpolates `{inputs}`, injects memory

#### Memory — Vector-Backed, Scoped, LLM-Analyzed
- **MemoryRecord**: content, scope (hierarchical path like `/company/team/user`), categories, importance (0-1), embedding, private flag, source
- **Composite scoring**: `weight_semantic * similarity + weight_recency * decay + weight_importance * importance`
- **Consolidation**: On save, if similarity > 0.85, LLM decides whether to merge/update/delete overlapping records
- **RecallFlow**: Adaptive-depth retrieval — if confidence low, LLM-driven exploration round
- **MemoryScope**: Query only `/org/team/` subtree
- **MemorySlice**: Frozen, serializable subset for passing between agents
- **Background writes**: `remember()` returns immediately; writes in ThreadPoolExecutor; drain via `drain_writes()`
- **Knowledge** is separate from Memory: static ingested documents vs. runtime observations

#### Tool System
- `BaseTool(BaseModel)` — Pydantic model with name, description, args_schema, cache_function, result_as_answer, max_usage_count
- `CrewStructuredTool` — wraps any function with auto-generated pydantic args_schema
- `EnvVar` — inject environment variables into tool args at runtime
- `ToolUsage` — parses LLM tool calls, validates args, executes, checks usage limits
- **MCP Integration**: `MCPToolResolver` converts MCP server configs into BaseTool instances
- **Delegation Tools**: `DelegateWorkTool` and `AskQuestionTool` — agents communicate by "calling" delegation tools

#### Event Bus — The Nervous System
- `CrewAIEventsBus` — singleton, thread-safe, async-capable
- `@bus.on(EventType)` decorator with optional `depends_on=Depends(fn)` for handler ordering
- Topological sort of handlers into execution levels
- Event scoping: parent IDs create trace trees
- Rich taxonomy: LLMCallStarted, ToolUsageStarted, CrewKickoffStarted, MemorySaveStarted, FlowStarted, etc.

#### Flow System — Reactive DAG
- `@start()` marks entry points
- `@listen(method)` reacts to method output
- `@router(method)` conditional branching — returns constant that routes to different `@listen` methods
- `@or_()` / `@and_()` — OR/AND conditions for triggering listeners
- `FlowState` — Pydantic model that persists between method calls
- `FlowPersistence` — SQLite-based resumable flows
- `@human_feedback()` — pause for human input
- Full streaming support via `FlowStreamingOutput`

#### Agent Execution Loop (ReAct Pattern)
1. Setup messages: system prompt + user prompt with task, context, tools
2. Loop up to `max_iter`:
   - Call LLM
   - Parse response for tool calls
   - If tool call → execute, add observation, continue
   - If `AgentFinish` → return result
3. Human input optionally
4. Delegation via DelegateWorkTool/AskQuestionTool if `allow_delegation=True`

Hooks: `before_llm_call_hooks` → LLM → `after_llm_call_hooks`, `before_tool_call_hooks` → tool → `after_tool_call_hooks`

#### Skills System — Progressive Disclosure
- Level 1 (METADATA): name + description
- Level 2 (INSTRUCTIONS): full SKILL.md body
- Level 3 (RESOURCES): scripts, references, assets
- Each skill has `SkillFrontmatter` with name, description, license, compatibility, `allowed_tools`

### crewAI vs Standard Practice

| Aspect | Standard Practice | crewAI |
|--------|-------------------|--------|
| Agent definition | Static prompt string | Rich Pydantic model with role/goal/backstory + tools + knowledge + memory |
| Task routing | Fixed chain | Context edges (DAG) + ConditionalTask branching + async parallelism |
| Inter-agent communication | None or manual | Delegation tools + hierarchical manager routing |
| Memory | Conversation history | Vector-backed, scoped, LLM-analyzed, consolidated, importance-scored |
| Observability | Print statements | Singleton event bus with dependency-ordered handlers |
| Orchestration | Linear chain | @start/@listen/@router reactive DAG + Crews with sequential/hierarchical processes |
| Tool execution | Direct function calls | Schema-validated, usage-limited, cached, hookable, with MCP integration |
| Extensibility | Subclass | BaseAgentAdapter pattern for external frameworks, skill packages, MCP tool resolver |

### What Works in crewAI

1. **Pydantic everywhere** — All core types are models. Validation, serialization, schema generation for free.
2. **Task-as-DAG-node with explicit context edges** — Clear data flow, enables branching and parallelism.
3. **Delegation-as-tool** — Elegant. Agents don't need to know about each other; they call a delegation tool.
4. **Flow system** — `@start/@listen/@router` is the most powerful orchestration pattern seen. Declarative, composable, resumable.
5. **Event bus as nervous system** — Enables tracing, streaming, debugging without coupling to core logic.
6. **Progressive disclosure for skills** — Load metadata first, full instructions on demand.
7. **Background memory writes with `drain_writes()`** — Don't block agent execution for memory persistence.

### What's Weak in crewAI

1. **Overkill for single-agent use** — CrewAI is designed for multi-agent teams. The overhead of Crew/Flow/Task/Agent is significant for a single agent.
2. **No persistent identity** — Agents are instantiated per-task. No concept of an agent that "is" something across sessions.
3. **No physical embodiment** — No voice, no vision, no robot control. Purely software.
4. **Memory is over-engineered for our use case** — We have Hermes sessions already. crewAI's vector memory is good but we'd replace it.
5. **No streaming/real-time output** — The event bus exists but isn't designed for real-time user-facing streaming.

### ARES Recommendations from crewAI

**Adopt:**
- Pydantic models for all data contracts (already started with `ares/models/`)
- Delegation-as-tool (Hermes already does this with `delegate_task`)
- Event bus pattern for observability (future: add to ARES runtime)
- Progressive disclosure for skills (Hermes already does this)
- Background memory writes pattern

**Don't adopt:**
- Crew/Task/Agent orchestration overhead (too heavy for our single-brain + multiple-faces design)
- crewAI's memory system (we'll build our own with Hermes sessions as foundation)
- The entire Flow system as-is (too coupled to Crew execution model)

---

## 3. open-claude-code

### Architecture Overview

open-claude-code is a **TypeScript/Node.js coding agent** using async generator functions as the core execution model. The agent loop is an `async function*` that yields typed events, enabling streaming, headless operation, and UI-agnostic core logic.

### Core Abstractions

#### Agent Loop — Async Generator Pattern
```javascript
async function* run(userMessage, { continuation = false } = {}) {
    // 1. Add user message to context
    // 2. Check shouldCompact() → compress if needed
    // 3. Loop up to maxIterations:
    //    a. Call LLM
    //    b. Parse response for tool calls
    //    c. If tool call → yield tool events, execute, yield* run(null, { continuation: true })
    //    d. If text response → yield assistant event, check stop hooks
    //    e. If stop hooks say "continue" → yield continuation nudge, loop again
}
```

**13 event types**: stream_event, thinking, thinking_complete, tool_progress, result, assistant, compaction, hookPermissionResult, stop, error, stream_request_start, etc.

**Key insight:** The recursive `yield* run(null, { continuation: true })` pattern means tool results flow back through the same generator — no external state machine needed.

#### Context Management — Two-Tier Compaction
- **Micro-compaction**: Truncates tool results older than 5 turns (>200 chars → 100 chars + `...[truncated]`). Applied first.
- **Full compaction**: If micro isn't enough, summarizes old messages into a single `[Context compacted]` user message, keeping only the last 6 messages.
- **Threshold**: 80% of token limit triggers compaction (144k of 180k default).
- **Token estimation**: Char-based (4 chars ≈ 1 token). No external tokenizer dependency.

#### Tool System — Declarative Registry Pattern
```javascript
{ name, description, inputSchema, validateInput, call }
```
- `createToolRegistry()` returns a Map-based registry
- `registerMcpTools()` wraps external MCP tools as same-interface objects with closure over MCP client
- 25+ built-in tools: Bash, Read, Edit, Write, Glob, Grep, Agent, WebFetch, WebSearch, TodoWrite, MultiEdit, Ls, AskUser, Skill, etc.
- Validation before execution: `validateInput()` returns error array; errors block execution

#### Multi-Provider API — Response Normalization
- Three API callers: `callAnthropic`, `callOpenAI`, `callGoogle`
- Each normalizes responses to `{ content, stop_reason, usage }`
- Provider detection by model name prefix
- Streaming uses Anthropic's SSE format as canonical

#### Permission System — 6 Modes
- `default`, `bypassPermissions`, `acceptEdits`, `auto`, `dontAsk`, `plan`
- Bash commands always scanned for dangerous patterns regardless of mode
- File operations always validate paths (prevent traversal)
- Safe tools whitelist: Read, Glob, Grep, Ls, ToolSearch, AskUser, etc.

#### Hook System — Lifecycle Interception
- 6 hook points: PreToolUse, PostToolUse, Stop, Notification, PrePrompt, PostResponse
- PreToolUse can block execution (`{ decision: 'deny' }`)
- PostToolUse can modify results (`{ modifiedResult }`)
- Stop hook can prevent termination — **critical for autonomous agents**
- Both shell commands and JS functions supported

#### Session Persistence + Checkpointing
- `SessionManager`: saves/loads conversation history, token usage, model to `~/.claude/projects/<hash>/session.json`
- Teleport: export/import as base64
- `CheckpointManager`: saves original file content before every edit. Undo pops the stack. Max 50 checkpoints.

#### Subagents — Composed Agent Loops
- The `Agent` tool spawns a new `createAgentLoop` with its own tools, permissions, context
- Subagents can run background or foreground
- Type-specific system prompts: coder, reviewer, researcher, tester, planner
- Not a separate class — just a new instance of the same loop. Composition over inheritance.

#### Agent Teams — Multi-Agent Communication
- `AgentTeams`: registers named agent loops as teammates
- `sendMessage()`: posts to shared message queue
- `broadcast()`: sends to all teammates in parallel
- Track status (idle/running) per agent
- Message queue pattern: `Map<agentId, messages[]>`

#### Skills as Prompt Injection
- Markdown files with YAML frontmatter loaded from `.claude/skills/{name}/SKILL.md`
- Invoked by injecting prompt text as user message prefixed with `[Skill: name]`
- Zero-code extensibility

### open-claude-code vs Standard Practice

| Aspect | Standard Practice | open-claude-code |
|--------|-------------------|-----------------|
| Agent loop | while(prompt) { call(prompt); print(response) } | Async generator yielding 13 typed events |
| Tool continuation | External state machine | Recursive yield* — same generator |
| Context management | Truncate oldest messages | Two-tier: micro-compact → full-summarize |
| Tool execution | Function calls | Validated registry with MCP adapter |
| Permissions | Boolean flag | 6 modes + always-enforced injection/path checks |
| Subagents | Separate class hierarchy | Composed instances of same loop |
| Streaming | Callback-based | yield* events consumed by any listener |
| Skills | Imported modules | Markdown files prompt-injected |

### What Works in open-claude-code

1. **Async generator agent loop** — Clean separation of execution from rendering. Enables streaming, headless, UI modes from same core.
2. **Two-tier context compaction** — Practical and avoids context explosion. Micro-truncate tool results first, full-summarize as fallback.
3. **Hook middleware** — Pre/post interception at lifecycle points enables safety, observability, and forced continuation.
4. **File checkpointing** — Simple undo stack for destructive operations. 50-deep.
5. **Stop hook for forced continuation** — Critical for autonomous agents. Prevents premature termination.
6. **Provider-normalized response shape** — Makes core loop provider-agnostic.

### What's Weak in open-claude-code

1. **Single-process, single-user** — No multi-agent bus, no distributed deployment.
2. **No physical embodiment** — Pure coding agent. No voice, no vision, no robot.
3. **No persistent identity** — Session-based, no "who I am" across sessions.
4. **File-based state** — `~/.claude/` structure is simple but not designed for concurrent access.
5. **No real memory** — Just conversation history with compaction. No vector search, no semantic recall.

### ARES Recommendations from open-claude-code

**Adopt:**
- Two-tier compaction pattern ( Hermes already does compaction, but we can improve it)
- Stop hooks for forced continuation (add to Hermes agent loop)
- File checkpointing before edits (safety net for autonomous operation)
- Hook system pattern for lifecycle interception

**Don't adopt:**
- The entire async generator pattern (Hermes is Python, not Node — different concurrency model)
- Session persistence approach (we have Hermes sessions which are better)
- Skills as prompt injection (Hermes already has a better skill system)

---

## 4. SAM (Synthetic Autonomic Mind)

**Important:** This SAM is NOT Meta's Segment Anything Model. It is a native macOS AI assistant built with Swift/SwiftUI.

### Architecture Overview

SAM is a multi-provider AI assistant with a **MessageBus-based architecture**, per-conversation SQLite memory, and sophisticated context management including YaRN compression and Vector RAG.

### Core Abstractions

#### ConversationMessageBus — Single Source of Truth
- All messages flow through a single bus
- `ConversationModel` syncs from bus via delta updates (not array copies)
- Debounced persistence (500ms during streaming)
- Decouples UI from data layer

#### ConversationSession — Context Safety
- Creates snapshots of working context before async operations
- If conversation switches/deletes during long-running operation, session invalidates and operation stops gracefully
- Prevents data leakage between conversations

#### AgentOrchestrator — Autonomous Workflow Engine
- **2×2 Continuation Guidance Matrix**:

| | Last iteration had tool results | Last iteration had NO tool results |
|---|---|---|
| **Has incomplete todos** | "Continue working on your todos" | "Decide what to do next to advance your todos" |
| **No incomplete todos** | "Analyze the results and decide next steps" | "Summarize what you've accomplished" |

- This replaced rigid "force tools on/off" flags and reduced planning loops by 60%+

#### APIFramework — Multi-Provider Routing
- `AIProvider` protocol — all providers implement: OpenAI, Anthropic, GitHub Copilot, DeepSeek, Gemini, local GGUF/MLX
- `EndpointManager` routes by model identifier prefix (`github_copilot/`, `anthropic/`, etc.)
- All responses normalized to OpenAI format
- New providers just implement the protocol

#### MCPFramework — Operation-Based Tool Consolidation
- 39 individual tools → 8 consolidated operation-based tools
- Each tool takes an `operation` parameter (e.g., `file_operations` with `read_file`, `search`, `write` sub-operations)
- Reduced system prompt tokens by ~62%
- Authorization sandboxing per operation

#### Memory — Per-Conversation SQLite + Vector RAG
- Each conversation gets its own SQLite database (prevents data leakage)
- Vector RAG service enables semantic search across all conversations
- Fallback chain: RAG search → traditional search → combined results
- YaRN context compression: analyzes message importance, applies progressive compression, scales attention patterns from 8K→65K tokens

#### MLX Integration — Local Model Inference
- Metal GPU acceleration for Apple Silicon
- LRU model caching
- Streaming and non-streaming paths unified

### SAM vs Standard Practice

| Aspect | Standard Practice | SAM |
|--------|-------------------|-----|
| Message handling | Direct array manipulation | MessageBus with delta updates |
| Context safety | Assume stable | Session snapshot + invalidation |
| Tool proliferation | One tool per function | 8 operation-based consolidated tools (-62% prompt tokens) |
| Orchestration | Fixed FSM or prompt-only | 2×2 context-aware guidance matrix |
| Context window | Truncate or summarize | YaRN importance-weighted compression |
| Memory | Single DB or in-memory | Per-conversation SQLite + cross-conversation RAG |
| Provider routing | Switch statement | Protocol pattern with prefix-based routing |

### What Works in SAM

1. **Operation-based tool consolidation (39→8)** — Massive prompt token savings. Cleaner decision boundaries for LLM.
2. **Context-aware orchestration guidance** — 2×2 matrix is simple but effective. Replaces rigid FSM.
3. **Session snapshots for async pipelines** — Self-invalidation on context change. Prevents stale writes.
4. **Per-task memory isolation + cross-task RAG** — Best of both worlds: isolation prevents leakage, RAG enables recall.
5. **Two-tier streaming** — Same core handles streaming and non-streaming, differs only in delivery.

### What's Weak in SAM

1. **Swift-only** — Not portable. Can't run on Linux or embedded.
2. **Single-user, single-machine** — No distributed deployment story.
3. **No physical embodiment** — Desktop-only AI assistant.
4. **Over-engineered LLM routing** — Provider normalization is good but the 6-provider matrix is complex.

### ARES Recommendations from SAM

**Adopt:**
- Operation-based tool consolidation (reduce ARES MCP tools from many to grouped)
- 2×2 continuation guidance pattern for our cognitive loop
- Per-task memory isolation + cross-task RAG
- Session snapshot pattern for async pipelines
- YaRN-inspired importance-weighted context compression

**Don't adopt:**
- Swift/Apple-specific code (ARES is Python)
- Single-provider LLM abstraction (Hermes already handles this)
- Per-conversation SQLite (Hermes session DB is better)

---

## 5. What ARES Should Actually Build

### The Synthesis

| From | Pattern | ARES Implementation |
|------|---------|---------------------|
| Lilith | ZMQ bus for face modules | `ares/runtime/bus.py` — ZMQ PUB/SUB/PUSH for voice, vision, robot control |
| Lilith | 4-layer personality system | `ares/core/personality.py` — HEXACO + SPECIAL + Expression + Domains |
| Lilith | Plugin manifest + discovery | Already in Hermes skills system, but add `plugin.json` pattern for MCP servers |
| crewAI | Pydantic models everywhere | `ares/models/` — already started |
| crewAI | Delegation-as-tool | Hermes `delegate_task` — already working |
| crewAI | Background memory writes | Add to brain transport for async persistence |
| open-claude-code | Two-tier compaction | Improve Hermes compaction with micro-truncate → full-summarize |
| open-claude-code | Stop hooks | Add to ARES agent loop for forced continuation |
| open-claude-code | File checkpointing | Add to ARES before destructive tool calls |
| SAM | Operation-based tools | Consolidate ARES MCP tools into grouped operations |
| SAM | 2×2 guidance matrix | Use for ARES cognitive loop |
| SAM | Per-task memory isolation | Each autonomous task gets its own memory scope |
| SAM | Session snapshots | Add for async perception pipelines |
| Hermes | Everything else | Hermes already has: tool system, session DB, skill system, multi-provider, streaming, delegation |

### What Makes ARES Different from All of Them

1. **We have a working brain** — Hermes handles LLM, tools, sessions, skills, memory, delegation. None of these systems have an equivalent.
2. **Physical embodiment is core** — Voice (STT/TTS), vision, robot control. Lilith has the bus for it but no implementation. SAM is Mac-only. No one else does this.
3. **Personality as data** — Lilith's 4-layer system is the best approach any of them have. We should adopt it.
4. **One brain, many faces** — Mac Studio runs Hermes. iPhone/Watch/Vision Pro are thin clients. None of these systems have this architecture.

### Priority Build Order

1. **ZMQ face bus** — Connect voice/vision/robot modules to Hermes
2. **Personality system** — 4-layer dataclass model, runtime-adjustable
3. **Operation-based MCP tools** — Consolidate from many individual tools to grouped operations
4. **Cognitive loop guidance** — 2×2 matrix for autonomous decision-making
5. **Session snapshots** — Context invalidation for async perception pipelines
6. **Two-tier compaction** — Improve Hermes context management
7. **Stop hooks** — Forced continuation for autonomous operation
8. **Per-task memory isolation** — Scopes like `/project/task/`
---

## 6. VoiceLLM — Voice Pipeline Architecture

### Architecture Overview

VoiceLLM is a **single-process, multi-threaded, pub/sub voice pipeline** running entirely on-device. No HTTP/WebSocket server — all communication via an internal `queue.Queue` bus.

```
Mic → [VAD/Energy detect] → [Whisper STT] → bus("stt.text")
    → Orchestrator (state: IDLE→THINKING)
    → LLMNode.ask_stream() [threaded]
        → streams llm.token deltas → Orchestrator._on_llm_token()
            → LLM gate check (buffer first 30 chars for <ignore>/<reply>)
            → if <reply>: forward post-tag deltas to TTS via tts.feed_text()
            → if <ignore>: discard all tokens, skip TTS, return to IDLE
        → llm.done → tts.flush()
    → KokoroNode synthesizes sentences, plays via sounddevice
        → mic.pause(True) while speaking, mic.pause(False) when done
    → tts.done → Orchestrator (state: RESPONDING→IDLE)
```

### Key Design Patterns

#### LLM-Gated Speech (Critical Pattern)
Every LLM response begins with `<ignore>` or `<reply>`. The orchestrator buffers the first 30 chars before deciding whether to route to TTS. This is the primary mechanism for distinguishing directed speech from noise/hallucination. Cost: ~50-150ms latency on reply path. Zero cost on ignore path. Fallback: if no tag in 30 chars, treat as `<reply>`.

#### Self-Speech Rejection (4-Layer Defense)
- Layer A: Mic-pause during TTS (catches ~95%)
- Layer B: AEC via speexdsp (for barge-in mode)
- Layer C: Reply-text similarity filter (SequenceMatcher ≥ 0.75)
- Layer D: LLM gate (catches everything A/B/C miss)

#### Swappable Backend Pattern (Strategy Pattern)
`BackendBase` ABC with `load()`, `warm()`, `stream_chat()`, `cancel()`. Two implementations:
- `LlamaCppBackend`: llama-cpp-python, `create_chat_completion(stream=True)`, auto-stop on `<end_of_turn>`
- `MLXBackend`: mlx-lm, `stream_generate()`, hand-rolled stop-marker detection

#### Dual STT Pipeline
- **Two-pass**: WebRTC VAD → fast Whisper (`base.en`) → wake-word check → accurate Whisper (`medium.en`). Best for wake-word mode.
- **Continuous**: Energy-based phrase detection, single Whisper model, rolling re-transcription, dedup via SequenceMatcher at 0.92 threshold. Better for always-listening mode.

#### TTS Sentence-Streaming (Dual-Thread)
- **synth_loop**: Buffers LLM deltas, pops at sentence boundaries (`[.!?]\s` or min 60 chars), calls Kokoro `KPipeline`, pushes audio to `audio_q`
- **play_loop**: Drains `audio_q`, publishes `mic.pause(True)`, plays via `sounddevice`, publishes `mic.pause(False)` + `tts.done` on sentinel

#### Pending-Turn Queue (Single-Slot, Last-Win)
New `stt.text` mid-turn replaces any pending text. On `tts.done`, orchestrator checks staleness (3.0s max age). If fresh, re-enters `_on_stt_text()`.

#### State Machine
```
IDLE → THINKING  (on stt.text)
THINKING → RESPONDING  (on first post-gate LLM token)
RESPONDING → IDLE  (on tts.done or ignore-path llm.done)
```

### ARES Voice Pipeline Recommendations

| Pattern | Recommendation |
|---------|---------------|
| Architecture | Adopt bus + node pattern. Decouples components, makes barge-in, metrics, and future GUI sinks trivial |
| LLM Gate | Essential for always-listening. Implement `<ignore>`/`<reply>` tag protocol with ~30 char buffer |
| Self-Speech | Start with mic-pause (Layer A) + text similarity (Layer C). Add AEC only for barge-in |
| STT | Two-pass for wake-word modes; continuous for always-listening |
| TTS | Sentence-streaming is critical. Dual-queue (text_q → synth → audio_q → play) pattern works well |
| Backend Abstraction | `BackendBase` ABC pattern cleanly isolates inference. Use same for cloud API calls |
| Config | Single config module with all tunables — simple and effective for local deployment |
| Metrics | `TurnMetrics` dataclass with timestamps at each phase boundary, written to CSV. Easy to extend for ARES telemetry |

---

## 7. OpenClaw — Personal AI Assistant Platform (NOT Robotics)

### What It Actually Is

OpenClaw is a **multi-channel messaging gateway** (WhatsApp, Telegram, Slack, Discord, Signal, iMessage, etc.) that runs LLM inference and manages conversations. It is NOT a robotics codebase — the name is misleading.

### Patterns Worth Noting for ARES

| Pattern | Applicability |
|---------|--------------|
| **Plugin architecture** (manifest → registry → lifecycle hooks → typed SDK contracts) | Highly relevant — ARES hardware drivers as plugins |
| **State machine formalism** (formal state transitions with typed events) | Relevant — adapt for robot gait phases, safety modes |
| **Security/sandbox boundaries** (exec allowlists, approval binding) | Maps to robot safety: motion commands must pass safety checks |
| **Capability registry** (plugin capability discovery) | Maps to hardware capability advertising (servo count, DOF, sensor types) |
| **Real-time voice pipeline** (audio streaming) | Streaming pattern applicable to sensor data processing |

### Not Found (Must Build From Scratch for JP01/Tamotu)
- Gait generation algorithms
- Servo control / PWM interfaces
- Inverse kinematics solvers
- Real-time control loops
- Motor safety interlocks
- Hardware abstraction for servos/IMU/force sensors

---

## 8. Worldview — Spatial Intelligence Terminal

Worldview is a **satellite and aircraft tracking visualization app** built on CesiumJS. It shows live satellite orbits (SGP4 propagation from CelesTrak TLE data) and live aircraft positions (OpenSky Network ADS-B) on a 3D globe with military-style shader overlays (NVG, FLIR, CRT).

**Architecture:** Minimal — 3 core JS files. `server.js` is an Express proxy for CORS bypass. `worldview.js` is the monolithic client with all CesiumJS scene setup, satellite propagation, and rendering. `electron.js` wraps as Mac app. There's also a `VisionWorldview/` visionOS app and `WorldviewNative/` Swift Package.

**Relevance to ARES:** Low. Spatial visualization could be useful for robot situational awareness (showing JP01's position on a map), but the actual code (CesiumJS rendering, satellite propagation) isn't directly applicable. The cross-platform packaging pattern (web → Electron → visionOS) mirrors our Mac Studio → iPhone/Watch/Vision Pro approach, but the implementation is too different to borrow.

---

## 9. The Old ARES-App: Honest Assessment

The old ARES-App code (the one we had in ARES-apps/ARES-App/) was a **scaffold with good ideas and prototype wiring**.

### What It Did Well
- **Architecture was sound**: HTTP boundary between SwiftUI and Python (`hermes_bridge.py` on :9876), response+state+expression tuple, MCP tool calls through mcporter subprocess
- **Identity was thoughtful**: Frozen dataclass, JSON persistence, system prompt generation from identity fields
- **Face state was clean**: 6 states (IDLE, AWAKENED, LISTENING, THINKING, SPEAKING, SLEEPING) with RGB+opacity+pulse+pupil parameters. Emotion-to-state mapping. Directly usable by SwiftUI FaceRenderer.
- **Memory had the right shape**: SQLite+WAL, thread-safe, schema migrations, three-tier persistence concept (SQLite → Obsidian vault → twin_state.json). But no vector search, no semantic recall.

### What It Didn't Do Well
- **The actual cognition in hermes_bridge.py was keyword matching**: Lines 68-113 were `if "hello" in text: return "Hello Matthew"`. That's a demo, not a reasoning engine.
- **No personality sliders**: Identity was a static dataclass. Lilith's 4-layer HEXACO+SPECIAL+Expression+Domains is far richer.
- **No async**: ThreadingHTTPServer for the bridge. Fine for prototype, won't scale.
- **MCP calls via subprocess**: Calling mcporter via `subprocess.run(["npx", "-y", "mcporter", ...])` for every tool call. 30-second timeout. No connection pooling. This is slow and fragile.
- **Face state was binary**: 6 discrete states with no interpolation. Lilith's approach allows continuous adjustment across dozens of dimensions.

### Verdict
The ideas survive. The code gets rewritten. We've already merged the good structural ideas (identity, face_state, memory, hermes_bridge HTTP contract) into the main `ares/` package. The bridge needs to be rewritten with:
1. Real cognition through Hermes (not keyword matching)
2. ZMQ bus for face modules (not just HTTP)
3. Personality sliders (not static identity)
4. Async FastAPI (not ThreadingHTTPServer)
5. MCP via Python SDK (not subprocess mcporter calls)
