# ARES Architecture

## Process topology

```
Browser / Native App
  │  HTTP + SSE
  ▼
FastAPI Controller (services/controller/fastapi_app/)
  │  routers → api/ business logic
  ▼
Worker Adapters (integrations/workers/)
  │  subprocess per turn
  ▼
Worker processes: Jaeger AI · Hermes · Claude Code · Codex · Ollama · cloud APIs
```

Three layers, one product:

| Layer | Owns |
|-------|------|
| Client (`apps/web/`, `apps/macos/`) | Presentation, navigation, user interaction |
| Controller (`services/controller/`) | Sessions, identity, auth, context assembly, streaming |
| Workers (`integrations/workers/`) | Model inference, tool execution, code loops |

## Dispatch model

ARES dispatches work to agents through a planner → orchestrator → worker pipeline:

1. **User sends a message** in the Agent conversation
2. **ARES classifies the request** — simple (direct response) or complex (needs a plan)
3. **For complex requests:** the planner decomposes into steps with dependencies, the orchestrator assigns steps to workers by capability/privacy/cost, and steps execute sequentially or in parallel
4. **Each worker** receives a filtered context briefing (not the full journal), executes in an isolated subprocess, and returns a structured result
5. **The evaluator** checks every result before the response composer presents it to the user
6. **Control Center** shows live plans, active workers, progress, approvals, and provenance

### Simple tasks
```
User message → classify intent → pick worker → send briefing → get result → verify → respond
```

### Complex tasks
```
User message → create plan → execute step 1 → verify → execute step 2 → verify → ... → synthesize → respond
```

### Parallel execution
Independent steps run concurrently. Dependent steps run sequentially. Concurrency limits are configurable.

## Guard and verification

ARES enforces a hard boundary between *the model proposes* and *the system acts*:

1. **Trust Engine** — classifies data sensitivity (public/personal/private/sensitive/secret), gates provider eligibility, enforces local-only mode
2. **Evaluator** — checks worker output against expectations before presenting to user (6 checks: completeness, consistency, safety, accuracy, format, policy)
3. **Approval gates** — shell commands, file deletion, external API calls, spending above threshold, sending sensitive data all require explicit user approval
4. **Response Composer** — assembles verified results into one coherent answer with provenance

### Data classification

| Class | Who can see | Rule |
|-------|------------|------|
| Public | Any worker | Include freely |
| Personal | Approved providers | Include with disclosure tracking |
| Private | Local workers only | Redact from cloud briefings |
| Sensitive | Explicit approval per task | Redact by default |
| Secret | Never leaves device | Never include in any briefing |

## Memory and state

### Two stores, one direction

```
ARES_HOME/          ARES-owned state (read + WRITE)
Worker stores       Worker-owned state (read ONLY)
```

ARES never writes another app's store. When a worker session needs a new turn, ARES asks the worker to write it. This is a deliberate boundary.

### Memory types

| Type | What | Lifecycle |
|------|------|-----------|
| Episodic | Conversations, events, actions | Permanent, searchable |
| Semantic | Facts, preferences, decisions | Permanent, searchable |
| Working | Current task state, active plan | Cleared when task completes |
| Scratchpad | Worker temporary state | Cleared when worker task completes |

### Context assembly

Workers never see the full journal. The context compiler assembles a filtered, token-budgeted briefing per task: identity, relevant user context, project context, recent conversation, relevant memories, constraints, privacy policy, available tools, and output requirements.

## System boundaries

### What ARES owns

| Subsystem | Owns |
|-----------|------|
| Identity | Name, persona, behavioral principles |
| Memory | Journal, user model, preferences, decisions |
| Context | What to send, what to redact, what budget |
| Trust | Data classification, provider eligibility, approval gates |
| Planning | Task decomposition, step ordering, dependencies |
| Routing | Which worker for which task |
| Verification | Checking worker output against expectations |
| Response | Final voice, uncertainty framing, activity summary |
| Policy | What requires approval, what data can leave the device |

### What workers own

Workers own execution. They do NOT own identity, memory, policy, or the user relationship.

| Worker | Owns |
|--------|------|
| Hermes | Tool execution, terminal ops, file ops, agent loops |
| Claude Code | Code generation, reasoning |
| Codex | Code generation, general reasoning |
| Ollama | Local inference, privacy-safe computation |
| Jaeger AI | Local companion, macOS control, voice |

### Boundary enforcement

1. Workers cannot directly mutate permanent memory — only ARES writes to the journal
2. Workers cannot bypass trust policy — the trust engine gates all data
3. Workers cannot access secrets — API keys are injected by ARES, never in briefings
4. Workers cannot initiate actions — ARES dispatches all tasks
5. Worker outputs are untrusted input — the evaluator checks all results

## Worker adapter contract

All workers are accessed through a common interface:

```python
class ReasoningProvider(Protocol):
    worker_id: str
    provider: str
    capabilities: list[str]
    data_location: str      # "local" | "cloud"
    privacy_class: str      # "local_only" | "external_provider" | "approved_provider"

    async def generate(self, briefing: ContextBriefing, message: str) -> WorkerResult: ...
    async def check_availability(self) -> AvailabilityStatus: ...
```

### ContextBriefing (what ARES sends to workers)

Filtered, budgeted context per task: identity, user context, project context, recent conversation, relevant memories, constraints, privacy policy, available tools, output requirements, and a manifest of what was included/excluded/redacted.

### WorkerResult (what workers return)

Structured result: content, artifacts, tool calls, confidence, cost report, metadata, and verification evidence.

## Runtime invariants

- ARES never silently selects a worker on a new profile
- Profile readiness and execution readiness are reported separately
- Backend selection, model selection, and tool selection remain distinct
- Every completed turn retains worker and model provenance
- External stores are opened read-only
- Worker failure degrades a capability; it must not erase the ARES session

## Extensions

ARES WebUI supports an opt-in extension surface for self-hosted installs. Extensions can serve static assets and inject same-origin CSS/JS. They execute with full WebUI session authority — only enable extensions you wrote yourself or from sources you trust.

## Contracts

For contract-affecting changes, see `services/controller/docs/CONTRACTS.md` for the full contract index, RFCs, and review expectations. Key contracts:

- Session resolution: `services/controller/docs/rfcs/canonical-session-resolution.md`
- Run adapter: `services/controller/docs/rfcs/ares-run-adapter-contract.md`
- Agent source boundary: `services/controller/docs/rfcs/agent-source-boundary.md`
- Turn journal: `services/controller/docs/rfcs/turn-journal.md`
