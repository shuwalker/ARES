# LangGraph vs ARES/Hermes: Pattern Comparison

This document compares LangGraph's architectural patterns with ARES/Hermes to identify what ARES can learn, adopt, or improve upon.

## Source Material

- **LangGraph** — LangChain's orchestration framework for stateful agents with durable execution, human-in-the-loop, checkpointing, and memory.
- **ARES/Hermes** — The agent runtime powering Hermes Agent, with session management, tool orchestration (MCP), cron, and skill-based workflows.

---

## 1. State Management

### LangGraph

LangGraph uses a **channel-based state model**:

- **StateGraph** — Users define a `TypedDict` or Pydantic model as the state schema. Each field is a "channel" with an optional reducer (e.g., `Annotated[list, operator.add]` for appending lists).
- **Channels** (`langgraph/channels/`) — Typed state containers:
  - `LastValue` — holds a single value, overwrites on update
  - `BinaryOperatorAggregate` — applies a reducer function (e.g., `operator.add`) to accumulate values
  - `Topic` — pub/sub, fan-out to multiple consumers
  - `EphemeralValue` — resets each superstep (not persisted)
  - `DeltaChannel` — accumulates deltas and snapshots periodically (beta)
- **Managed Values** — Special state that auto-updates per step (e.g., `RemainingSteps` counts down).
- **Overwrite** — `Command(update={"key": Overwrite(value=...)})` bypasses reducers to set a channel directly.
- **Subgraphs** — Nested StateGraphs have their own state scope; `Command.PARENT` lets a subgraph update parent state.

### ARES/Hermes

ARES uses a **session-centric state model**:

- **Agent Sessions** — Each conversation is a `session` with messages, tool calls, and responses stored in SQLite/Postgres.
- **Session state** is implicit in the message history; there's no formal state schema or reducer system.
- **Skills and plugins** define procedural steps, not state transitions.
- **Cron jobs** and background processes track state via their own persistence.

### What ARES Can Learn

| LangGraph Pattern | ARES Gap | Recommendation |
|---|---|---|
| Typed state schemas with reducers | No formal state schema for agent workflows | Consider a `WorkflowState` TypedDict for multi-step agent plans with explicit field-level reducers |
| Channel-based isolation | State is monolithic (message list) | Add state channels for parallel tool outputs that need merging (e.g., multiple research results combining into a summary) |
| `EphemeralValue` channels | No concept of step-scoped state | Useful for tracking "current step index" or "retry count" that resets between turns |
| `Command.PARENT` for subgraph → parent state | Nested agent sessions have no formal state bridging | When spawning sub-agents, allow them to write back to parent session state |

---

## 2. Checkpointing and Durability

### LangGraph

LangGraph's checkpointing is its most sophisticated subsystem (`checkpoint/`):

- **BaseCheckpointSaver** — Abstract base class defining the checkpoint interface:
  - `put()` / `aput()` — save a checkpoint
  - `get_tuple()` / `aget_tuple()` — retrieve checkpoint + metadata
  - `list()` / `alist()` — list checkpoints for a thread
- **Checkpoint structure** — TypedDict containing:
  - `v` (version), `id` (UUID6 monotonically increasing), `ts` (timestamp)
  - `channel_values` — snapshot of all state channels
  - `channel_versions` — per-channel monotonic version tracking
  - `versions_seen` — per-node tracking of which channel versions were processed (drives incremental execution)
- **Pending writes** — Uncommitted writes stored as `(task_id, channel, value)` tuples. Enables crash recovery: on resume, apply pending writes first.
- **Delta snapshots** — `DeltaChannel` support with configurable snapshot frequency; avoids storing full state on every step.
- **Serialization** — `JsonPlusSerializer` (JSON + msgpack for bytes), `EncryptedSerializer` for encrypted state.
- **Store** — Separate key-value store (`BaseStore`) for long-term memory scoped by namespace, with embedding-based search (`BaseStore.search()`).
- **Backends** — InMemorySaver, AsyncPostgresSaver, SqliteSaver, with Postgres being production-grade.

### ARES/Hermes

ARES has session persistence but lacks formal checkpointing:

- **Session storage** — Messages and tool results persisted in SQLite/Postgres per session.
- **No incremental state snapshots** — State is reconstructed from full message history.
- **No pending write recovery** — If a tool call crashes mid-execution, the session may be in an inconsistent state.
- **No formal "store" concept** — Skills and memories are flat files; no namespace-scoped key-value store.

### What ARES Can Learn

| LangGraph Pattern | ARES Gap | Recommendation |
|---|---|---|
| Versioned checkpoints with `channel_versions` | No versioned state snapshots | Add step-level checkpoints to agent sessions for time-travel debugging and crash recovery |
| Pending writes for crash recovery | No write-ahead log for tool results | Before executing a tool call, record intent; on resume, replay completed writes |
| Delta snapshots | Full message history reprocessed every turn | For long-running sessions, periodically snapshot computed state to avoid re-processing entire history |
| `BaseStore` with namespace + embedding search | No structured long-term memory store | Build a namespace-scoped store for agents to persist and retrieve cross-session knowledge |
| Encrypted serializer | No encryption layer on persisted state | For enterprise deployments, support encrypted state at rest |

---

## 3. Human-in-the-Loop

### LangGraph

LangGraph implements HITL via **interrupts**:

- **`interrupt(value)`** — A node calls `interrupt()` with an arbitrary value. This raises a `GraphInterrupt` exception that pauses execution.
- **`Command(resume=...)`** — The client resumes by passing a `Command` with a `resume` value, which is delivered back to the interrupted node.
- **Multiple interrupts per node** — Nodes can have multiple `interrupt()` calls; resume values are matched by order.
- **Interrupt IDs** — Each interrupt gets a unique ID; resume can target specific interrupts: `Command(resume={"interrupt_id": "value"})`.
- **HumanInterruptConfig** — Deprecated but shows the design: `allow_ignore`, `allow_respond`, `allow_edit`, `allow_accept` — a permissions model for HITL.
- **Requirement** — Interrupts require a checkpointer; state is saved before pausing so execution can resume from exactly that point.

### ARES/Hermes

ARES has implicit HITL via the chat interface:

- **Tool approval** — Some tool calls may require user confirmation (conceptual, not always enforced).
- **Clarification prompts** — `clarify.py` generates follow-up questions, but these are just messages, not formal interrupts.
- **No pause/resume** — A session doesn't pause mid-execution waiting for human input; the agent either completes or asks in a new turn.
- **No formal interrupt protocol** — No mechanism for a tool to signal "I need human input before continuing."

### What ARES Can Learn

| LangGraph Pattern | ARES Gap | Recommendation |
|---|---|---|
| `interrupt(value)` → pause mid-execution | No mid-turn pause mechanism | Add a `interrupt()` primitive that stops execution, saves state, and returns to the user. Critical for approval workflows. |
| `Command(resume=...)` to continue | No resume protocol | When an interrupt is resolved, the agent should pick up from the exact point, not re-run from scratch |
| Interrupt ID targeting | No way to address specific paused steps | For multi-step approval flows, allow resuming specific interrupts |
| `HumanInterruptConfig` permission model | No permission model for HITL actions | Define what actions a human can take: approve, edit, reject, ignore |

---

## 4. Graph Execution Model

### LangGraph

LangGraph's execution engine is the **Pregel** model (BSP-style bulk synchronous parallel):

- **Supersteps** — Execution proceeds in discrete steps. In each step:
  1. Read channel values that changed since last step
  2. Execute all ready nodes in parallel
  3. Write outputs to channels
  4. Check for convergence (no new writes → done)
- **Conditional edges** — `add_conditional_edges()` routes to different nodes based on state.
- **Send** — Dynamic fan-out: a node can `Send("node", input)` to invoke a node with custom input, enabling map-reduce patterns.
- **Branch** — Declarative routing: `BranchSpec` maps state conditions to target nodes.
- **Streaming** — Multiple stream modes: `values`, `updates`, `messages`, `custom`, `checkpoints`, `tasks`, `debug`.
- **RetryPolicy** — Configurable per-node retry with exponential backoff, jitter, and custom `retry_on` predicates.
- **TimeoutPolicy** — Per-node timeouts with cooperative cancellation (`run_timeout`, `idle_timeout`, `refresh_on`).
- **CachePolicy** — Per-node caching with configurable key functions and TTL.
- **Durability modes** — `sync` (persist before next step), `async` (persist in background), `exit` (persist on completion).

### ARES/Hermes

ARES uses a **sequential tool-calling loop**:

- **Agent loop** — LLM generates → tool calls execute → results feed back → LLM continues.
- **No formal graph** — Workflow is implicit in the prompt/skill instructions, not a declared graph.
- **No parallel execution** — Tool calls run sequentially (or the LLM decides order).
- **No retry/backoff** — Tool failures are handled by the LLM reasoning about errors, not by a policy engine.
- **No step-level streaming** — Output streams as tokens arrive; no intermediate state snapshots.

### What ARES Can Learn

| LangGraph Pattern | ARES Gap | Recommendation |
|---|---|---|
| Declarative graph with compile-time validation | Workflows are implicit in prompts | For complex multi-step workflows (research, planning), consider a declarative graph definition that can be validated and visualized |
| Parallel node execution via BSP | Sequential tool calls | For independent tool calls, execute in parallel and merge results |
| `Send` for dynamic fan-out | No map-reduce pattern | Allow a step to spawn N sub-tasks (e.g., research N topics) and collect results |
| `RetryPolicy` per node | No automatic retry for tool failures | Add configurable retry policies for tool calls (especially for rate-limited APIs) |
| `TimeoutPolicy` with cooperative cancellation | No per-tool timeout enforcement | Add per-tool timeouts that can cancel long-running operations |
| `CachePolicy` for node outputs | No caching of tool results | For deterministic tools (e.g., web search within TTL), cache results to avoid redundant calls |
| Stream modes (values, updates, tasks) | Only token streaming | Add structured streaming: task start/end events, state snapshots, debug traces |

---

## 5. Tool Calling

### LangGraph

LangGraph's `ToolNode` and related patterns (`prebuilt/tool_node.py`):

- **ToolNode** — A graph node that executes tool calls from `AIMessage.tool_calls`.
- **Parallel execution** — Multiple tool calls in one turn execute concurrently.
- **Error handling** — `ToolException` → `ToolMessage` with error content; configurable error filtering.
- **State injection** — `InjectedState` and `InjectedStore` annotations let tools access graph state and the long-term store without polluting their signatures.
- **ToolRuntime** — Bundles `state`, `config`, `stream_writer`, `tool_call_id`, `store` into a runtime object available to tools.
- **Command-based returns** — Tools can return `Command(update=..., goto=...)` to update state and redirect flow, not just return a string.
- **Validation** — `ToolValidator` ensures tool schemas match their declared types.
- **Tool call transformers** — Intercept and modify tool calls before execution (e.g., inject context).

### ARES/Hermes

ARES uses **MCP (Model Context Protocol)** for tool integration:

- **MCP tools** — External tools accessed via stdio/SSE transports.
- **Skills** — Procedural knowledge that drives tool usage (not tools themselves).
- **Tool adapter** — `ares_tool_adapter.py` bridges MCP tools to the agent loop.
- **No state injection** — Tools are pure input/output; no access to session state beyond what's in the prompt.
- **No command returns** — Tools return text results; they can't redirect agent flow.

### What ARES Can Learn

| LangGraph Pattern | ARES Gap | Recommendation |
|---|---|---|
| `InjectedState` / `InjectedStore` | Tools have no access to session state | Allow MCP tools to opt-in to receiving session context (user preferences, history summary) |
| `ToolRuntime` bundle | No runtime context for tools | Provide a runtime context object with `config`, `stream_writer`, `store` to MCP tools |
| `Command` returns from tools | Tools can't redirect flow | Allow tools to return commands like "pause for approval" or "switch to sub-agent X" |
| Tool call transformers | No tool call interception | Add middleware hooks before/after tool execution for logging, rate limiting, context injection |
| Parallel tool call execution | Sequential or LLM-decided ordering | Execute independent tool calls concurrently when safe |

---

## 6. SDK and Client Patterns

### LangGraph SDK (`sdk-py/`)

The SDK provides a client for the LangGraph Server REST API:

- **Dual sync/async clients** — `_sync/` and `_async/` mirrors with identical interfaces.
- **Resource-oriented API** — `client.threads`, `client.runs`, `client.assistants`, `client.crons`, `client.store`.
- **Streaming** — SSE + WebSocket transports with cursor-based pagination (`multi_cursor_buffer`).
- **Auth** — Token-based auth with `langgraph_sdk.auth` module.
- **Encryption** — Client-side encryption types for sending encrypted state.

### ARES/Hermes

ARES's client interaction is via the web UI and CLI:

- **Web UI** — React frontend talking to a FastAPI backend.
- **CLI** — `hermes` command-line tool for configuration.
- **No formal SDK** — No programmatic client library for external applications to integrate with ARES.

### What ARES Can Learn

| LangGraph Pattern | ARES Gap | Recommendation |
|---|---|---|
| Sync + async client libraries | No external SDK | Build a Python SDK for programmatic access to ARES sessions, tools, and cron |
| Resource-oriented API (threads, runs, assistants) | Ad-hoc API endpoints | Standardize the API around resources: sessions, runs, skills, tools, memories |
| Cursor-based streaming | No structured streaming protocol | Add SSE/WebSocket streaming with cursors for resumable consumption |
| Client-side encryption types | No encryption at API boundary | For enterprise, support encrypted state in transit and at rest |

---

## 7. Key Architectural Differences

| Dimension | LangGraph | ARES/Hermes |
|---|---|---|
| **Paradigm** | Declarative graph (compile → execute) | Imperative agent loop (prompt → tools → respond) |
| **State** | Typed channels with reducers | Message history + implicit state |
| **Persistence** | Versioned checkpoints with pending writes | Full message history replay |
| **HITL** | `interrupt()` / `Command(resume=)` | Natural language clarification |
| **Execution** | BSP supersteps with parallel nodes | Sequential tool-calling loop |
| **Tools** | State-injectable with Command returns | MCP with text-only returns |
| **Retry/Timeout** | Per-node policies with backoff | LLM-driven error recovery |
| **Streaming** | 7 modes (values, updates, messages, custom, checkpoints, tasks, debug) | Token streaming only |
| **Subgraphs** | Nested StateGraphs with state bridging | Nested agent sessions, no state bridge |
| **Long-term memory** | `BaseStore` with embedding search | Flat file skills/memories |

---

## 8. What ARES Should Adopt (Priority Order)

### P0 — Critical for Enterprise Production

1. **Formal checkpointing with pending writes** — Crash recovery for tool execution. Before calling a tool, record intent; on resume, replay or skip completed writes.
2. **`interrupt()` / `Command(resume=)` for HITL** — Essential for approval workflows. An agent should be able to pause mid-turn and resume from the exact point.
3. **Per-tool timeout policies** — Prevent hung tools from blocking sessions. Add `run_timeout` and `idle_timeout` with cooperative cancellation.

### P1 — Significant Quality Improvements

4. **Typed workflow state with reducers** — For multi-step workflows, define state schemas so intermediate results accumulate correctly (e.g., research results merging into a summary).
5. **Structured streaming modes** — Beyond token streaming, add task start/end events, state snapshots, and debug traces.
6. **Tool middleware hooks** — Pre/post-execution hooks for logging, rate limiting, context injection, and validation.
7. **Parallel tool execution** — When tools are independent, execute concurrently.

### P2 — Nice-to-Have Differentiation

8. **Declarative graph compilation for complex workflows** — Optional: let users define multi-step agent plans as compiled graphs for validation and visualization.
9. **`BaseStore` with embedding search** — Long-term memory store scoped by namespace with semantic search.
10. **Delta snapshots for long sessions** — Avoid reprocessing entire history on every turn.
11. **SDK client library** — Python SDK for programmatic ARES access.
12. **`Send` fan-out pattern** — Dynamic parallel sub-tasks (map-reduce for agents).

---

## 9. Directory Structure Reference

```
langgraph_study/
├── langgraph/          # Core graph definition and execution
│   ├── channels/       # State channel types (LastValue, BinOp, Topic, etc.)
│   ├── graph/          # StateGraph builder, compiled graph, message state
│   ├── pregel/         # Pregel execution engine (BSP loop, checkpointing, streaming)
│   ├── stream/         # Stream modes and transformers
│   ├── _internal/      # Serialization, config, retry, timeout, pydantic utilities
│   ├── managed/        # Auto-updating managed values (RemainingSteps)
│   └── utils/          # Config and runnable helpers
├── checkpoint/         # Checkpointing and persistence
│   ├── checkpoint/
│   │   ├── base/       # BaseCheckpointSaver, Checkpoint, CheckpointTuple
│   │   ├── memory/     # InMemorySaver
│   │   └── serde/       # JsonPlusSerializer, msgpack, encrypted serde
│   ├── store/          # BaseStore, InMemoryStore (namespace-scoped KV + embedding search)
│   └── cache/          # BaseCache, InMemoryCache, RedisCache
├── prebuilt/            # Prebuilt agent patterns
│   ├── chat_agent_executor.py  # ReAct agent construction
│   ├── tool_node.py    # ToolNode for executing tool calls
│   ├── interrupt.py    # HumanInterruptConfig, ActionRequest, HumanResponse
│   └── tool_validator.py       # Tool schema validation
├── sdk-py/              # Python SDK for LangGraph Server
│   ├── _sync/          # Synchronous client (threads, runs, assistants, crons, store)
│   ├── _async/         # Async client (mirrors _sync)
│   ├── stream/         # SSE/WS streaming with cursor buffers
│   ├── auth/           # Token auth
│   └── encryption/     # Client-side encryption types
└── COMPARISON.md        # This file
```